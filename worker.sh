#!/usr/bin/env bash
set -euo pipefail

MANAGER_HOST="${1:-}"
SECRET_KEY="${2:-}"

if [ -z "$MANAGER_HOST" ] || [ -z "$SECRET_KEY" ]; then
    echo "Uso: $0 <MANAGER_IP_OU_HOST> <SECRET_KEY>"
    exit 1
fi

CRONICLE_DIR="/opt/cronicle"
CRONICLE_REPO="https://github.com/cronicle-edge/cronicle-edge.git"
MANAGER_URL="http://${MANAGER_HOST}:3012"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    ca-certificates \
    curl \
    wget \
    git \
    jq \
    procps \
    build-essential \
    openssl \
    nodejs

rm -rf /tmp/cronicle-edge
git clone --depth 1 "$CRONICLE_REPO" /tmp/cronicle-edge
apt-get update && apt-get install -y npm
cd /tmp/cronicle-edge

./bundle "$CRONICLE_DIR"

cd "$CRONICLE_DIR"

install -m 700 -d "$CRONICLE_DIR/conf"
printf '%s\n' "$SECRET_KEY" > "$CRONICLE_DIR/conf/secret_key"
chmod 600 "$CRONICLE_DIR/conf/secret_key"

TMP_JSON="$(mktemp)"
jq \
  --arg secret "$SECRET_KEY" \
  '
    .secret_key = $secret
  ' conf/config.json > "$TMP_JSON"
mv "$TMP_JSON" conf/config.json

cat > /etc/systemd/system/cronicle-edge-worker.service <<UNIT
[Unit]
Description=Cronicle Edge Worker
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$CRONICLE_DIR
ExecStart=$CRONICLE_DIR/bin/worker
Restart=always
RestartSec=5
User=root
Environment=HOME=/root
Environment=CRONICLE_secret_key=$SECRET_KEY
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable cronicle-edge-worker
systemctl restart cronicle-edge-worker

sleep 5
systemctl --no-pager --full status cronicle-edge-worker || true

echo
echo "========== PRÓXIMO PASSO =========="
echo "Manager: $MANAGER_URL"
echo "Secret key no config.json:"
jq -r '.secret_key' "$CRONICLE_DIR/conf/config.json" || true
echo "Adicione este worker no manager em: Admin / Servers"
echo "=================================="
