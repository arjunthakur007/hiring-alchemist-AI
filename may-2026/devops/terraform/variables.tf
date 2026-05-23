variable "aws_region" {
  description = "The AWS region to deploy resources into"
  type        = string
  default     = "ap-south-1"
}

variable "github_repo_url" {
  description = "The full HTTPS URL of your cloned GitHub repository"
  type        = string
  default     = "https://github.com/arjunthakur007/hiring-alchemist-AI.git"
}

variable "instance_type" {
  description = "EC2 instance size for our worker VMs"
  type        = string
  default     = "t3.medium" # t3.medium provides 4GB RAM, which easily runs small language models smoothly
}

variable "cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_private" {
  description = "The CIDR block for private subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "subnet_cidr_public_A" {
  description = "The CIDR block for public subnet A"
  type        = string
  default     = "10.0.2.0/24"
}

variable "subnet_cidr_public_B" {
  description = "The CIDR block for public subnet B"
  type        = string
  default     = "10.0.3.0/24"
}

