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

# NOTE: Auditbeat now runs in a dedicated container (`auditbeat` service
# in docker-compose.yml) with host-level access to the kernel audit
# subsystem. We no longer install or start Auditbeat inside ssh-target.

echo "✅ Starting SSHD in foreground..."
# Log SSHD output to a dedicated log file so we can inspect certificate/auth errors
exec /usr/sbin/sshd -D -E /var/log/sshd.log
