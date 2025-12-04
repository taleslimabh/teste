#!/bin/bash
set -e

apt-get update -y
apt-get install -y docker.io curl

systemctl enable docker
systemctl start docker

mkdir -p /opt/app
cd /opt/app


docker pull phoenix-image


docker run -d --name phoenix-app -p 5000:5000 phoenix-image


cp /home/ubuntu/self_heal.sh /usr/local/bin/self_heal.sh
chmod +x /usr/local/bin/self_heal.sh


