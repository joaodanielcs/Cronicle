#!/usr/bin/env bash

set -euo pipefail

# Uso:
#   bash agente.sh <MANAGER_IP_OU_HOST> <SECRET_KEY>

MANAGER_HOST="${1:-}"
SECRET_KEY="${2:-}"

if [ -z "$MANAGER_HOST" ] || [ -z "$SECRET_KEY" ]; then
    exit 1
fi

CRONICLE_DIR="/opt/cronicle"
CRONICLE_REPO="https://github.com/cronicle-edge/cronicle-edge.git"
MANAGER_URL="http://${MANAGER_HOST}:3012"

# ==========================================================
# 1. DEPENDÊNCIAS
# ==========================================================
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
    nodejs \
    npm

# ==========================================================
# 2. INSTALAÇÃO DO CRONICLE-EDGE
# ==========================================================
rm -rf /tmp/cronicle-edge
git clone --depth 1 "$CRONICLE_REPO" /tmp/cronicle-edge
cd /tmp/cronicle-edge

./bundle "$CRONICLE_DIR"

cd "$CRONICLE_DIR"

# ==========================================================
# 3. SECRET KEY
# ==========================================================
install -m 700 -d "$CRONICLE_DIR/conf"
printf '%s\n' "$SECRET_KEY" > "$CRONICLE_DIR/conf/secret_key"
chmod 600 "$CRONICLE_DIR/conf/secret_key"

# ==========================================================
# 4. AJUSTES DE CONFIGURAÇÃO
# ==========================================================
# Mantém a secret_key coerente também no config.json
TMP_JSON="$(mktemp)"
jq \
  --arg secret "$SECRET_KEY" \
  '
    .secret_key = $secret
  ' conf/config.json > "$TMP_JSON"
mv "$TMP_JSON" conf/config.json

# Setup inicial do storage/config do cronicle-edge
node "$CRONICLE_DIR/bin/storage-cli.js" setup || true

# ==========================================================
# 5. SERVIÇO SYSTEMD - WORKER
# ==========================================================
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

# ==========================================================
# 6. VALIDAÇÃO
# ==========================================================
sleep 5

echo
echo "========== VALIDAÇÃO =========="
echo "Serviço:"
systemctl --no-pager --full status cronicle-edge-worker || true

echo
echo "Secret key em arquivo:"
cat "$CRONICLE_DIR/conf/secret_key" || true

echo
echo "Secret key no config.json:"
jq -r '.secret_key' "$CRONICLE_DIR/conf/config.json" || true

echo
echo "Processo:"
pgrep -af 'cronicle|worker' || true

echo
echo "========== PRÓXIMO PASSO =========="
echo "Manager: $MANAGER_URL"
echo "Adicione este worker no manager em: Admin / Servers"
echo "=================================="
