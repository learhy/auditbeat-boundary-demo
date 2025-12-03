#!/bin/bash
set -e

echo "🎯 Setting up SSH target..."

# Install packages
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server sudo curl jq wget unzip gnupg

# Create SSH directory and user
mkdir -p /var/run/sshd
useradd -m -s /bin/bash ubuntu || true
echo 'ubuntu:password' | chpasswd
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Wait for Vault CA to be ready
echo "Waiting for Vault CA (/shared/vault-ca.pem)..."
for i in {1..60}; do
  if [ -s /shared/vault-ca.pem ]; then
    echo "✅ Found Vault CA"
    break
  fi
  echo "  retry $i"
  sleep 2
  if [ "$i" -eq 60 ]; then
    echo "❌ Vault CA not found after 60 attempts"
    exit 1
  fi
done

# Configure SSH to trust Vault CA
cp /shared/vault-ca.pem /etc/ssh/trusted-ca.pem
echo 'TrustedUserCAKeys /etc/ssh/trusted-ca.pem' >> /etc/ssh/sshd_config
echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config
echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
echo 'LogLevel VERBOSE' >> /etc/ssh/sshd_config
echo 'SyslogFacility AUTHPRIV' >> /etc/ssh/sshd_config

# Install Auditbeat
ARCH=$(dpkg --print-architecture)
AB_VER=8.11.0
AB_DEB="auditbeat-${AB_VER}-${ARCH}.deb"
echo "Downloading Auditbeat ${AB_VER} for ${ARCH}"
curl -fsSL -o "/tmp/${AB_DEB}" "https://artifacts.elastic.co/downloads/beats/auditbeat/${AB_DEB}"
DEBIAN_FRONTEND=noninteractive dpkg -i "/tmp/${AB_DEB}"
rm -f "/tmp/${AB_DEB}"

# Copy our custom config
echo "Copying custom auditbeat config..."
cp /config/auditbeat.yml /etc/auditbeat/auditbeat.yml

# Skip auditbeat for now - it needs host audit subsystem access
# echo "✅ Starting Auditbeat in background..."
# /usr/bin/auditbeat -c /etc/auditbeat/auditbeat.yml -e &

echo "✅ Starting SSHD in foreground..."
exec /usr/sbin/sshd -D
