#!/usr/bin/env bash

# ==========================================================
# 1. VALIDAÇÃO DE PARÂMETROS
# ==========================================================
if [ -z "$1" ] || [ -z "$2" ]; then
    echo -e "\e[1;31mErro: Parâmetros ausentes.\e[0m"
    echo -e "Uso correto: $0 <MANAGER_URL> <SECRET_KEY>"
    exit 1
fi

MANAGER_URL="$1"
SECRET_KEY="$2"

echo -e "\e[1;34m==> Iniciando instalação do Cronicle-Edge Worker...\e[0m"

# ==========================================================
# 2. INSTALAÇÃO DE DEPENDÊNCIAS
# ==========================================================
echo -e "\e[1;33m==> Instalando dependências do SO (git, nodejs, npm, build-essential)...\e[0m"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y > /dev/null 2>&1
apt-get install -y git curl nodejs npm build-essential jq > /dev/null 2>&1

# ==========================================================
# 3. LIMPEZA DE INSTALAÇÕES ANTERIORES
# ==========================================================
echo -e "\e[1;33m==> Parando serviços e limpando lixo de instalações antigas...\e[0m"
if [ -f "/opt/cronicle/bin/control.sh" ]; then
    /opt/cronicle/bin/control.sh stop > /dev/null 2>&1
    sleep 3
fi
rm -rf /opt/cronicle /tmp/cronicle-edge

# ==========================================================
# 4. DOWNLOAD E COMPILAÇÃO (BUNDLE)
# ==========================================================
echo -e "\e[1;33m==> Baixando e empacotando o Cronicle-Edge...\e[0m"
git clone https://github.com/cronicle-edge/cronicle-edge.git /tmp/cronicle-edge > /dev/null 2>&1
cd /tmp/cronicle-edge
./bundle /opt/cronicle > /dev/null 2>&1

# ==========================================================
# 5. SETUP E INICIALIZAÇÃO
# ==========================================================
echo -e "\e[1;33m==> Conectando ao Master ($MANAGER_URL)...\e[0m"
cd /opt/cronicle
./bin/control.sh setup --manager "$MANAGER_URL" --secret "$SECRET_KEY" > /dev/null 2>&1

echo -e "\e[1;33m==> Iniciando o motor do Worker...\e[0m"
./bin/control.sh start

# Garantir que suba junto com o boot do servidor
if ! grep -q "/opt/cronicle/bin/control.sh start" /etc/rc.local 2>/dev/null; then
    echo "/opt/cronicle/bin/control.sh start" >> /etc/rc.local
    chmod +x /etc/rc.local 2>/dev/null
fi

echo -e "\e[1;32m✔ Instalação concluída com sucesso! Verifique a aba 'Servers' no Master.\e[0m"
