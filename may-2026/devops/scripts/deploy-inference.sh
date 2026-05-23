#!/bin/bash
# Redirect all outputs and errors to a log file for easy debugging
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

echo "=== Starting Inference Worker (Python) Deployment ==="

# 1. Update system packages
sudo apt-get update -y

# 2. Install Git, Python3, Pip, and Node.js (Required for PM2)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install git python3 python3-pip python3-venv nodejs -y

# 3. Clone the repository and navigate to the inference-worker directory
cd /home/ubuntu
# NOTE: Replace this with your actual repository URL when pushing code
git clone https://github.com/arjunthakur007/hiring-alchemist-AI.git
cd hiring-alchemist-AI/may-2026/devops/quickstart/workers/inference-worker

# 4. Fix permissions so the 'ubuntu' user owns the files
sudo chown -R ubuntu:ubuntu /home/ubuntu/hiring-alchemist-AI

# 5. Create a Python Virtual Environment and install dependencies as the ubuntu user
sudo -u ubuntu python3 -m venv venv
sudo -u ubuntu /home/ubuntu/hiring-alchemist-AI/may-2026/devops/quickstart/workers/inference-worker/venv/bin/pip install --upgrade pip
sudo -u ubuntu /home/ubuntu/hiring-alchemist-AI/may-2026/devops/quickstart/workers/inference-worker/venv/bin/pip install -r requirements.txt

# 6. Set Environment Variables
export RPC_PORT="50051"

# 7. Start the Python worker in the background using PM2 as the ubuntu user
sudo npm install -g pm2

# Run PM2 directly as the ubuntu user using the venv python interpreter inside the absolute working directory
sudo -u ubuntu env RPC_PORT="50051" pm2 start /home/ubuntu/hiring-alchemist-AI/may-2026/devops/quickstart/workers/inference-worker/venv/bin/python --name "inference-worker" --cwd /home/ubuntu/hiring-alchemist-AI/may-2026/devops/quickstart/workers/inference-worker -- inference_worker.py

# Save PM2 state so it restarts if the VM reboots for the ubuntu user
sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u ubuntu --hp /home/ubuntu
sudo -u ubuntu pm2 save

echo "=== Inference Worker Deployment Complete ==="