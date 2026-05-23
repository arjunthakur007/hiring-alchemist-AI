Infrastructure Setup (Terraform)This directory contains the Infrastructure-as-Code (IaC) configuration files to spin up the VPC, public/private subnets, firewalls, and application instances inside AWS.📋 Execution Order & Setup StepsFollow this procedural breakdown to deploy the environment from scratch.1.Configure AWS Credentials:Prerequisite.Open your terminal and configure your global AWS CLI credentials so Terraform can make authorized API calls to your account:Bashaws configure

## You will be prompted to enter your:
AWS Access Key IDAWS Secret Access KeyDefault region name (e.g., ap-south-1)Default output format (press enter for json)2.Initialize the Directory:1-2 minutes.Download the required cloud providers, backend modules, and structure configurations defined inside main.tf:

```bash
terraform init
```

## Validate and Plan Changes:
Run a predictive plan check to review exactly what resources Terraform will create, change, or destroy before touching any live cloud environments:

```bash
terraform plan
```

## Apply Infrastructure Changes:

Deploy the infrastructure resources directly to your live cloud workspace. Review the generated plan summary and type yes when prompted to authorize execution:

```bash
terraform apply
```

## Verifying Success

Upon successful execution, the terminal will print out your active public entry point under the outputs key:

```bash
Plaintext

Outputs:

alb_dns_name = "external-alb-1122176303.ap-south-1.elb.amazonaws.com"
```

Copy this output parameter link to run your API application verification tests.