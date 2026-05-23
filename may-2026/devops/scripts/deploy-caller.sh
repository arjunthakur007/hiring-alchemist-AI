#!/bin/bash

# Redirecting all outputs and errors to a log file for debugging purposes.
exec > /var/log/user-data.log 2>&1

# Wait for internet egress before doing anything
for i in {1..30}; do
  if curl -s --max-time 3 https://archive.ubuntu.com > /dev/null; then
    echo "Network ready after $i attempts"
    break
  fi
  echo "Waiting for network... attempt $i"
  sleep 5
done

echo "=== Starting Caller Worker (TypeScript) Deployment ==="

# 1. Update system packages
sudo apt-get update -y

# 2. Install Git
sudo apt-get install git -y

# 3. Install Node.js (Version 20)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# 4. Clone the repository and navigate to the worker directory
cd /home/ubuntu
# NOTE: Replace this with your actual repository URL when pushing code
git clone https://github.com/arjunthakur007/hiring-alchemist-AI.git
cd hiring-alchemist-AI/may-2026/devops/quickstart/workers/caller-worker

# 5. Fix permissions so the 'ubuntu' user owns these files
sudo chown -R ubuntu:ubuntu /home/ubuntu/hiring-alchemist-AI

# 6. Install dependencies as the ubuntu user
# Running this as ubuntu avoids file permission conflicts during execution
sudo -u ubuntu npm install

# 7. Setup Environment Variables
# The worker needs to find the Python instance. Terraform will replace this placeholder later!
export INFERENCE_WORKER_URL="PYTHON_PRIVATE_IP_PLACEHOLDER:50051"
export PORT="3000"

# 8. Keep the application running in the background using PM2 as the ubuntu user
sudo npm install -g pm2

# Run PM2 directly as the ubuntu user inside the correct folder with environment variables
sudo -u ubuntu env INFERENCE_WORKER_URL="PYTHON_PRIVATE_IP_PLACEHOLDER:50051" PORT="3000" pm2 start npm --name "caller-worker" --cwd /home/ubuntu/hiring-alchemist-AI/may-2026/devops/quickstart/workers/caller-worker -- start

# Configure PM2 to boot automatically if the VM restarts and save the state
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u ubuntu --hp /home/ubuntu
sudo -u ubuntu pm2 save

echo "=== Caller Worker Deployment Complete ==="