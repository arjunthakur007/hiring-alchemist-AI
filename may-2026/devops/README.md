# README.md

# VPC architecture for Quickstart

## Flow Chart

The following diagram map details the layout of all network resources, subnets, and the internal Remote Procedure Call (RPC) traffic flow:

```text
               [ PUBLIC INTERNET ]
                        │
                        ▼
┌────────────────────────────────────────────────────────┐
│               1. AWS INTERNET GATEWAY                  │
└───────────────────────┬────────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────────┐
│         2. APPLICATION LOAD BALANCER (ALB)             │
│            • Listens on Public Port 80                 │
└───────────────────────┬────────────────────────────────┘
                        │ (Forwards traffic across AZ boundaries)
                        ▼
┌────────────────────────────────────────────────────────┐
│           3. PUBLIC SUBNET ROUTING LAYER               │
│  • Subnet A (ap-south-1a) | Subnet B (ap-south-1b)    │
│  • Contains NAT GATEWAY (One-way outbound valve)      │
└───────────────────────┬────────────────────────────────┘
                        │
                        ▼ (Traffic routed to private pool)
┌────────────────────────────────────────────────────────┐
│         4. PRIVATE SUBNET LAYER (ap-south-1a)          │
│                                                        │
│  ┌──────────────────────────┐   ┌───────────────────┐  │
│  │   [5. CALLER WORKER]     │   │[6. INFERENCE WRK] │  │
│  │    EC2 (TypeScript)      │   │   EC2 (Python)    │  │
│  │                          │   │                   │  │
│  │ • Port: 3000             │   │• Port: 50051      │  │
│  │ • Receives traffic from  │───>• Handles backend │  │
│  │   the Load Balancer      │RPC│  model logic.     │  │
│  └──────────────────────────┘   └───────────────────┘  │
└────────────────────────────────────────────────────────┘

** Note: Before using curl make sure to navigate to the `interview_project\hiring-alchemist-AI\may-2026\devops\terraform` and apply the command mentioned in the README.md. Only then aplly the curl command mentioned here to get the desired results.**

## Curl Command 

To test the JSON API exposed by the Caller Worker, you can use the following `curl` command:

```bash 
`curl -X POST http://<YOUR_ALB_DNS_NAME>/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"message": "Hello from my fresh infrastructure!"}' `
```

Sample Paylaod Request

```bash
{
  "message": "Hello from my fresh infrastructure!"
}
```

Expected JSON Response
```bash
{
  "response": "Inference result from the backend model."
}
```

