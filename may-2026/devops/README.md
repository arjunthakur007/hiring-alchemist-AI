# DevOps Internship Assignment — Hiring Alchemist AI

End-to-end deployment of the `quickstart` cross-language (TypeScript + Python) worker mesh on AWS, with:
- A VPC isolating compute on private subnets
- A public Application Load Balancer as the only internet-facing surface
- Worker-to-worker RPC restricted to the private subnet
- An `/v1/chat/completions` JSON HTTP API exposed through the ALB
- Full Infrastructure-as-Code via Terraform — `terraform destroy && terraform apply` rebuilds the stack from scratch

---

## Architecture Diagram

```text
                            ┌────────────────────────────┐
                            │     PUBLIC INTERNET        │
                            └────────────┬───────────────┘
                                         │
                                         │  HTTP POST /v1/chat/completions
                                         │  (Port 80)
                                         ▼
                            ┌────────────────────────────┐
                            │  INTERNET GATEWAY (IGW)    │
                            │  • Attached to the VPC     │
                            │  • Provides bidirectional  │
                            │    internet ↔ public subnet│
                            │    connectivity            │
                            └────────────┬───────────────┘
                                         │
                                         ▼
╔══════════════════════════════════════════════════════════════════════════╗
║                   VPC  (CIDR: 10.0.0.0/16)                               ║
║                                                                          ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │  PUBLIC ROUTE TABLE                                                │  ║
║  │  • 10.0.0.0/16  → local      (VPC-internal traffic stays inside)   │  ║
║  │  • 0.0.0.0/0    → IGW        (default route to the internet)       │  ║
║  │  • Associated with: Public Subnet A, Public Subnet B               │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                                                                          ║
║  ┌──────────────────────────────┐   ┌─────────────────────────────────┐  ║
║  │  PUBLIC SUBNET A             │   │  PUBLIC SUBNET B                │  ║
║  │  • CIDR: 10.0.2.0/24         │   │  • CIDR: 10.0.3.0/24            │  ║
║  │  • AZ: ap-south-1a           │   │  • AZ: ap-south-1b              │  ║
║  │  • map_public_ip_on_launch   │   │  • map_public_ip_on_launch      │  ║
║  │                              │   │                                 │  ║
║  │  ┌────────────────────────┐  │   │  (Empty — exists only to        │  ║
║  │  │  NAT GATEWAY           │  │   │   satisfy the ALB multi-AZ      │  ║
║  │  │  • Has Elastic IP      │  │   │   requirement)                  │  ║
║  │  │  • One-way valve:      │  │   │                                 │  ║
║  │  │    private → internet  │  │   │                                 │  ║
║  │  │    (return traffic OK) │  │   │                                 │  ║
║  │  └────────────────────────┘  │   │                                 │  ║
║  └──────────────────────────────┘   └─────────────────────────────────┘  ║
║                                                                          ║
║              ┌──────────────────────────────────────────────┐            ║
║              │  APPLICATION LOAD BALANCER (external-alb)    │            ║
║              │  • Spans Public Subnet A + B (multi-AZ HA)   │            ║
║              │  • Listener: Port 80 HTTP                    │            ║
║              │  • Forwards to Target Group → port 3000      │            ║
║              │  • Health check: GET /health, matcher 200    │            ║
║              │  • Security Group: alb-sg                    │            ║
║              │     - Inbound:  0.0.0.0/0  → :80             │            ║
║              │     - Outbound: all                          │            ║
║              └────────────────────┬─────────────────────────┘            ║
║                                   │                                      ║
║                                   │  Only traffic from alb-sg            ║
║                                   │  can reach private workers on :3000  ║
║                                   ▼                                      ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │  PRIVATE ROUTE TABLE                                               │  ║
║  │  • 10.0.0.0/16  → local       (VPC-internal RPC stays inside)      │  ║
║  │  • 0.0.0.0/0    → NAT Gateway (outbound only, for apt/git/npm/pip) │  ║
║  │  • Associated with: Private Subnet                                 │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                                                                          ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │  PRIVATE SUBNET  (CIDR: 10.0.0.0/24, AZ: ap-south-1a)              │  ║
║  │  • No public IP addresses                                          │  ║
║  │  • Unreachable from the public internet                            │  ║
║  │  • Outbound internet only via NAT (apt/git/npm/pip installs)       │  ║
║  │                                                                    │  ║
║  │  ┌──────────────────────────┐    ┌──────────────────────────────┐  │  ║
║  │  │  CALLER WORKER EC2       │    │  INFERENCE WORKER EC2        │  │  ║
║  │  │  • Ubuntu 22.04          │    │  • Ubuntu 22.04              │  │  ║
║  │  │  • t3.medium (4 GB RAM)  │    │  • t3.medium (4 GB RAM)      │  │  ║
║  │  │  • Node.js 20 + PM2      │    │  • Python 3 + venv + PM2     │  │  ║
║  │  │  • Runs worker.ts (tsx)  │    │  • Runs inference_worker.py  │  │  ║
║  │  │  • Listens on :3000      │◄───┤  • Listens on :50051         │  │  ║
║  │  │  • Pulls code from       │RPC │  • Pulls code from           │  │  ║
║  │  │    GitHub at boot via    │    │    GitHub at boot via        │  │  ║
║  │  │    cloud-init user_data  │    │    cloud-init user_data      │  │  ║
║  │  │                          │    │                              │  │  ║
║  │  │  SG: workers-sg          │    │  SG: workers-sg              │  │  ║
║  │  │   - In  :3000 ← alb-sg   │    │   - In  ALL  ← self (workers)│  │  ║
║  │  │   - In  ALL  ← self      │    │   - Out ALL                  │  │  ║
║  │  │   - Out ALL              │    │                              │  │  ║
║  │  │                          │    │                              │  │  ║
║  │  │  IAM: ec2-ssm-role       │    │  IAM: ec2-ssm-role           │  │  ║
║  │  │  (SSM Session Manager    │    │  (SSM Session Manager        │  │  ║
║  │  │   access — no SSH keys,  │    │   access — no SSH keys,      │  │  ║
║  │  │   no bastion needed)     │    │   no bastion needed)         │  │  ║
║  │  └──────────────────────────┘    └──────────────────────────────┘  │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
╚══════════════════════════════════════════════════════════════════════════╝

  Outbound install path (apt/git/npm/pip during cloud-init):
  Private EC2  →  Private Route Table  →  NAT Gateway  →  IGW  →  Internet
  Return traffic uses the NAT's Elastic IP and is routed back to the
  originating private instance — workers never get a public IP themselves.

  RPC path (worker ↔ worker):
  Caller :3000  ⇄  Inference :50051   (both inside private subnet,
                                       traffic never leaves the VPC)
```

---

## Component Reference

| Component               | What it does                                                                 |
|-------------------------|------------------------------------------------------------------------------|
| **VPC**                 | Isolated network boundary (CIDR `10.0.0.0/16`).                              |
| **Internet Gateway**    | The only door for inbound public traffic; attached to the VPC.               |
| **Public Subnet A/B**   | Host the ALB across two AZs (ALB requires multi-AZ) + the NAT in Subnet A.   |
| **Private Subnet**      | Hosts the workers. No public IPs. Reachable only via the ALB or SSM.         |
| **NAT Gateway + EIP**   | Lets private workers reach the internet *outbound* (npm, apt, GitHub) without being reachable *inbound*. |
| **Public Route Table**  | Sends public-subnet traffic destined for `0.0.0.0/0` to the IGW.             |
| **Private Route Table** | Sends private-subnet outbound traffic to the NAT, keeps VPC-local traffic local. |
| **ALB**                 | Sole public entry point. Terminates HTTP on port 80 and forwards to the caller worker. |
| **Target Group**        | Tracks caller-worker instance health on `GET /health`.                        |
| **alb-sg**              | Allows the world to hit the ALB on port 80, blocks all else.                 |
| **workers-sg**          | Allows only the ALB to reach port 3000 on workers; allows workers to talk freely to each other. |
| **EC2 (Caller)**        | TypeScript worker. Receives HTTP, dispatches RPC to inference worker.        |
| **EC2 (Inference)**     | Python worker. Holds the small language model. Returns inference results.    |
| **IAM SSM role**        | Lets you `aws ssm start-session` into workers without SSH keys or a bastion. |

---

## Reproduce From Scratch

### Prerequisites
- An AWS account with billing enabled (free tier is sufficient for `t3.medium` workers)
- AWS CLI v2 installed and authenticated (`aws configure`)
- Terraform `>= 1.5` installed
- SSM Session Manager plugin installed locally (for debugging worker instances)

### Deploy

```bash
# 1. Clone this repository
git clone https://github.com/arjunthakur007/hiring-alchemist-AI.git
cd hiring-alchemist-AI/may-2026/devops/terraform

# 2. Initialize Terraform (downloads the AWS provider)
terraform init

# 3. Review the plan
terraform plan

# 4. Apply
terraform apply
#    Type 'yes' when prompted.
#    Provisioning takes ~3 minutes; user_data on each worker takes another
#    ~3 minutes to complete (apt install, git clone, npm install, PM2 start).
```

Successful `apply` prints:

```text
Outputs:
alb_dns_name = "external-alb-XXXXXXXXXX.ap-south-1.elb.amazonaws.com"
```

### Tear down

```bash
terraform destroy
```

---

## API

**Endpoint:** `POST http://<alb_dns_name>/v1/chat/completions`

**Sample request:**

```bash
curl -X POST http://<alb_dns_name>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "user", "content": "Say hello in one sentence." }
    ]
  }'
```

**Sample response (intended):**

```json
{
  "result": {
    "response": "Hello! How can I assist you today?",
    "success": "You've connected two workers and they're interoperating seamlessly..."
  }
}
```

---
## Current State and Known Gap

The Terraform infrastructure provisions cleanly, both EC2 workers boot, and the deploy scripts run to completion. PM2 starts the caller worker without errors and shows it as `online`. But the ALB target stays unhealthy because nothing is listening on port 3000. PM2 logs show:
```
[OTel] WebSocket error: connect ECONNREFUSED 127.0.0.1:49134
[iii] Reconnecting in 38596ms (attempt 11)...
```

After debugging, I found that the `iii` framework doesn't work the way I initially assumed. The worker process itself doesn't serve HTTP. Instead, it connects over WebSocket to a separate **iii engine** process on port 49134, and the engine is what binds the HTTP port and routes incoming requests to the worker. My current setup installs the `iii-sdk` library (via `npm install`) but doesn't install or run the iii engine binary on the EC2 — so the worker has nothing to connect to.

### Diagnostic chain that led here

| Symptom                                       | What I found and what I changed                                                       |
|-----------------------------------------------|---------------------------------------------------------------------------------------|
| Target group permanently in `initial` state   | I couldn't shell into the EC2 to debug because there was no SSH key, no public IP, and no IAM role for SSM. Added an IAM role with `AmazonSSMManagedInstanceCore` so I could connect via SSM Session Manager. |
| Worker user_data silently failing on `apt`    | Terraform was creating the EC2 before the NAT Gateway route was in place, so `apt update` had no internet and the script died on line one. Added `depends_on` for the NAT and the private route table, plus a network-wait loop at the top of each deploy script. |
| `npm error Missing script: "start"` in PM2   | The `package.json` for the caller worker has `dev` and `build` but no `start`. Changed the PM2 command from `-- start` to `-- run dev`. |
| Worker now `online` but port 3000 not bound | The iii framework requires a separate engine process to serve HTTP (see explanation above). Identified but not yet fixed — see Next Steps. |

### Next steps to complete the system

To finish wiring the system end-to-end, I would:

1. Install the iii engine on the caller-worker EC2 by adding `curl -fsSL https://install.iii.dev/iii/main/install.sh | sh` to the deploy script.
2. Run the engine alongside the worker under PM2, so both come up together on boot.
3. Find out which port the engine serves HTTP on (from its config) and update the Terraform target group to point at that port instead of 3000.
4. Make the inference worker connect to the caller's engine across the private subnet (over the worker's private IP) instead of its default of localhost — that's what fulfils the assignment's "RPC across the subnet" requirement.

---

## Production Hardening Notes

If this were going toward production, the things I would prioritize:

- **HTTPS instead of HTTP.** The ALB currently listens on plain HTTP. I'd add a TLS certificate via AWS Certificate Manager so traffic between users and the ALB is encrypted.
- **Move secrets out of code.** Environment variables are currently injected into the EC2's user_data by Terraform. Storing them in AWS SSM Parameter Store and fetching them at boot would be safer.
- **Store Terraform state remotely.** `terraform.tfstate` lives on my laptop right now. If I lose the file, I lose the ability to manage what's deployed. Moving state to an S3 bucket (with DynamoDB for state locking, so two people can't apply at the same time) would fix that.
- **Pre-build the EC2 image.** Every fresh EC2 takes ~3 minutes to install dependencies because it runs `apt update`, `git clone`, and `npm install` at every boot. Building a custom AMI with everything pre-installed would make boot near-instant and remove the dependency on GitHub being reachable at boot.
- **Add monitoring and alerts.** Right now there's no way to know if a worker becomes unhealthy in production. CloudWatch alarms on the target group's unhealthy-host count and on ALB 5xx error rates would catch issues early.
- **Replace single EC2s with Auto Scaling Groups.** There's one EC2 per worker. If either dies, the system is down until I notice and re-apply. Wrapping each tier in an Auto Scaling Group would let AWS automatically replace failed instances.

---

## If the Model Were 100× Larger

A larger model would change the problem in a few practical ways:

- **Scale vertically (use a bigger instance).** A `t3.medium` only has 4 GB of RAM and no GPU, so a 100× larger model wouldn't even fit in memory. I would move the inference worker to a larger instance type — ideally one with a GPU, which is designed for the heavy math that model inference does. CPU-only inference at that size would be far too slow to be usable. This is vertical scaling: replacing one machine with a more powerful one rather than adding more machines.
- **Store the model file separately from the code.** Right now every EC2 pulls the entire repository from GitHub on boot via `git clone`. A model 100× larger would make the repo too big to clone quickly, and Git isn't the right place to store large binary files anyway. I'd store the model file in an S3 bucket and download it on first boot — the code stays small, and the model can be updated independently.
- **Increase request timeouts.** A larger model takes longer to generate a response. The ALB's default idle timeout is 60 seconds and the worker-to-worker RPC call would also have its own timeout. Both would need to be increased so requests don't get killed mid-generation.
- **Plan for cost.** GPU instances are roughly 10–20× the hourly cost of a `t3.medium`. Running one 24/7 even when nobody is using the API would get expensive fast. I would think about whether the inference worker needs to be running all the time, or whether it can be stopped during low-traffic hours.

---

## Repository Structure

```
may-2026/devops/
├── README.md                ← you are here
├── terraform/
│   ├── main.tf              ← VPC, subnets, SGs, ALB, EC2s, IAM
│   ├── variables.tf         ← input variables with defaults
│   └── providers.tf         ← AWS provider pinned to ~> 6.0
├── scripts/
│   ├── deploy-caller.sh     ← user_data for the caller-worker EC2
│   └── deploy-inference.sh  ← user_data for the inference-worker EC2
└── quickstart/              ← upstream worker code (TypeScript + Python)
    └── workers/
        ├── caller-worker/
        └── inference-worker/
```