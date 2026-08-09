#!/bin/bash
set -euo pipefail

# Log all output
exec > >(tee -a /var/log/cloudflared-startup.log)
exec 2>&1

echo "[$(date)] Starting cloudflared installation and setup"

# Configuration
AWS_REGION="${AWS_REGION:-eu-central-1}"
SECRETS_MANAGER_SECRET_NAME="${SECRETS_MANAGER_SECRET_NAME:-maimons/cloudflare-tunnel-token}"
CLOUDFLARED_USER="cloudflared"
CLOUDFLARED_HOME="/opt/cloudflared"
CLOUDFLARED_CERT_PATH="${CLOUDFLARED_HOME}/.cloudflared"

# Step 1: Install cloudflared
echo "[$(date)] Installing cloudflared..."
if ! command -v cloudflared &> /dev/null; then
  cd /tmp
  curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.tgz -o cloudflared.tgz
  curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/SHA256 -o SHA256

  # Verify checksum
  echo "[$(date)] Verifying cloudflared binary checksum..."
  EXPECTED_CHECKSUM=$(grep cloudflared-linux-arm64.tgz SHA256 | awk '{print $1}')
  ACTUAL_CHECKSUM=$(sha256sum cloudflared.tgz | awk '{print $1}')

  if [ "${EXPECTED_CHECKSUM}" != "${ACTUAL_CHECKSUM}" ]; then
    echo "[$(date)] ERROR: Checksum verification failed. Expected: ${EXPECTED_CHECKSUM}, Got: ${ACTUAL_CHECKSUM}"
    exit 1
  fi

  tar xzf cloudflared.tgz
  install -m 755 cloudflared /usr/local/bin/
  rm -f cloudflared cloudflared.tgz SHA256
  echo "[$(date)] cloudflared installed and verified"
else
  echo "[$(date)] cloudflared already installed: $(cloudflared --version)"
fi

# Step 2: Create cloudflared system user
echo "[$(date)] Setting up cloudflared user and directories..."
if ! id "${CLOUDFLARED_USER}" &>/dev/null; then
  useradd --system --home-dir "${CLOUDFLARED_HOME}" --shell /usr/sbin/nologin "${CLOUDFLARED_USER}"
fi

mkdir -p "${CLOUDFLARED_CERT_PATH}"
chown -R "${CLOUDFLARED_USER}:${CLOUDFLARED_USER}" "${CLOUDFLARED_HOME}"
chmod 755 "${CLOUDFLARED_HOME}"

# Step 3: Retrieve tunnel token from AWS Secrets Manager
echo "[$(date)] Retrieving tunnel token from Secrets Manager..."
TUNNEL_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id "${SECRETS_MANAGER_SECRET_NAME}" \
  --region "${AWS_REGION}" \
  --query SecretString \
  --output text)

if [ -z "${TUNNEL_TOKEN}" ]; then
  echo "[$(date)] ERROR: Failed to retrieve tunnel token from Secrets Manager"
  exit 1
fi

# Step 4: Create cloudflared config directory and credentials
echo "[$(date)] Configuring cloudflared..."
echo "${TUNNEL_TOKEN}" > "${CLOUDFLARED_CERT_PATH}/credentials.json"

chown "${CLOUDFLARED_USER}:${CLOUDFLARED_USER}" "${CLOUDFLARED_CERT_PATH}/credentials.json"
chmod 600 "${CLOUDFLARED_CERT_PATH}/credentials.json"

# Step 5: Create systemd service file
echo "[$(date)] Creating systemd service..."
tee /etc/systemd/system/cloudflared.service > /dev/null << EOF
[Unit]
Description=Cloudflare Tunnel Service
After=network.target
StartLimitInterval=0

[Service]
Type=simple
User=${CLOUDFLARED_USER}
WorkingDirectory=${CLOUDFLARED_HOME}
ExecStart=/usr/local/bin/cloudflared tunnel run --credentials-file=${CLOUDFLARED_CERT_PATH}/credentials.json
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Step 6: Enable and start the service
echo "[$(date)] Enabling and starting cloudflared service..."
systemctl daemon-reload
systemctl enable cloudflared
systemctl start cloudflared

# Verify service is running
sleep 5
if systemctl is-active --quiet cloudflared; then
  echo "[$(date)] SUCCESS: cloudflared service is running"
else
  echo "[$(date)] WARNING: cloudflared service failed to start. Check logs:"
  systemctl status cloudflared || true
  exit 1
fi

echo "[$(date)] cloudflared setup complete"
