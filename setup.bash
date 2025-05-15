#!/bin/bash

set -e

# === CONFIGURATION ===

# docker container name
GITEA_CONTAINER_NAME="gitea"\

#local data directory (where Gitea stores its data)
LOCAL_GITEA_DATA="/var/lib/gitea-docker-data"

# Ports
HTTP_PORT=3000
SSH_PORT=2222

#USER
USER=$(whoami)

echo "Updating package lists..."
sudo apt update

echo "Installing required packages (Docker)..."
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# === Install Docker ===
# Check if Docker is already installed
if ! command -v docker &>/dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io
else
  echo "Docker is already installed."
fi

echo "Adding current user to docker group (if not already)..."
sudo usermod -aG docker $USER

# === Setup local Gitea data directory ===
echo "Creating local data directory at $LOCAL_GITEA_DATA"
sudo mkdir -p "$LOCAL_GITEA_DATA"
sudo chown -R 1000:1000 "$LOCAL_GITEA_DATA"

# Makes sure that the container doesn't run more than once
echo "Removing Gitea container if it exists..."
sudo docker stop $GITEA_CONTAINER_NAME 2>/dev/null || true
sudo docker rm $GITEA_CONTAINER_NAME 2>/dev/null || true

# === Pull and run Gitea ===
# pull the latest Gitea image and runs it
echo "Running Gitea Docker container..."
sudo docker run -d --name $GITEA_CONTAINER_NAME \
  -p $HTTP_PORT:3000 \
  -p $SSH_PORT:22 \
  -v "$LOCAL_GITEA_DATA":/data \
  --restart=always \
  gitea/gitea:latest

# === Create systemd service ===
echo "Creating systemd service for Gitea..."
sudo bash -c "cat > /etc/systemd/system/gitea-docker.service" <<EOF
[Unit]
Description=Gitea (Docker) - Local Data
Requires=docker.service
After=docker.service

[Service]
Restart=always
ExecStart=/usr/bin/docker start -a $GITEA_CONTAINER_NAME
ExecStop=/usr/bin/docker stop -t 2 $GITEA_CONTAINER_NAME

[Install]
WantedBy=multi-user.target
EOF

# === Enable and start service ===
echo "Enabling and starting Gitea service..."
sudo systemctl daemon-reload
sudo systemctl enable gitea-docker.service
sudo systemctl start gitea-docker.service

# === Create automatic startup ===
#opens web browser to Gitea UI on startup
#
#MAKE SURE TO ChANGE TO CHROMIUM IF NOT USING CHROME, or other web browser
#
sudo bash -c "cat > /etc/systemd/system/auto-launch.service" <<EOF
[Unit]
Description=Start Chrome to Gitea UI
After=graphical.target
Requires=graphical.target

[Service]
Type=simple
ExecStart=/usr/bin/google-chrome --noerrdialogs --disable-infobars --kiosk http://localhost:$HTTP_PORT
Environment=DISPLAY=:0
User=$USER


[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable auto-launch.service
sudo systemctl start auto-launch.service

echo ""
echo "Gitea is installed and running!"
echo "Visit: http://localhost:$HTTP_PORT"
echo "SSH Git port: $SSH_PORT"
echo "Data stored at: $LOCAL_GITEA_DATA"
echo "Reboot if group changes don't take effect immediately."


