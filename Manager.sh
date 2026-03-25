#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# 1. VERIFICAÇÃO DE DEPENDÊNCIAS (WHIPTAIL / JQ)
# ==========================================================
if ! command -v whiptail &> /dev/null; then
    apt-get update >/dev/null 2>&1
    apt-get install -y whiptail >/dev/null 2>&1
fi

if ! command -v jq &> /dev/null; then
    apt-get update >/dev/null 2>&1
    apt-get install -y jq >/dev/null 2>&1
fi

# ==========================================================
# 2. INTERFACE GRÁFICA (TUI) - COLETA DE VARIÁVEIS
# ==========================================================

NEXT_ID=$(pvesh get /cluster/nextid)
VM_ID=$(whiptail --title "VM ID" --inputbox "Set VM ID\n(O Proxmox sugeriu o próximo ID livre automaticamente)" 10 58 "$NEXT_ID" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$VM_ID" ]; then exit 1; fi

VM_NAME=$(whiptail --title "HOSTNAME" --inputbox "Set Hostname (ou FQDN)\nSugestão: srvCronicle" 10 58 "srvCronicle" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$VM_NAME" ]; then exit 1; fi

while true; do
    ROOT_PASS=$(whiptail --title "ROOT PASSWORD" --passwordbox "Set Root Password (needed for root ssh access)" 10 58 3>&1 1>&2 2>&3)
    if [ $? != 0 ] || [ -z "$ROOT_PASS" ]; then exit 1; fi

    ROOT_PASS_CONFIRM=$(whiptail --title "ROOT PASSWORD CONFIRMATION" --passwordbox "Please confirm your Root Password" 10 58 3>&1 1>&2 2>&3)
    if [ $? != 0 ] || [ -z "$ROOT_PASS_CONFIRM" ]; then exit 1; fi

    if [ "$ROOT_PASS" == "$ROOT_PASS_CONFIRM" ]; then
        break
    else
        whiptail --title "ERROR" --msgbox "As senhas não coincidem. Por favor, tente novamente." 8 45
    fi
done

VM_CORES=$(whiptail --title "CPU CORES" --inputbox "Allocate CPU Cores" 10 58 "2" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$VM_CORES" ]; then exit 1; fi

VM_MEM=$(whiptail --title "RAM SIZE" --inputbox "Allocate RAM in MiB" 10 58 "2048" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$VM_MEM" ]; then exit 1; fi

DISK_SIZE=$(whiptail --title "DISK SIZE" --inputbox "Set Disk Size in GB" 10 58 "20" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$DISK_SIZE" ]; then exit 1; fi

mapfile -t AVAILABLE_STORAGES < <(pvesm status -content images | awk 'NR>1 {print $1}')
if [ ${#AVAILABLE_STORAGES[@]} -eq 0 ]; then
    whiptail --msgbox "Nenhum storage compatível encontrado." 10 58
    exit 1
fi

MENU_OPTIONS=()
for st in "${AVAILABLE_STORAGES[@]}"; do
    MENU_OPTIONS+=("$st" "" "OFF")
done
MENU_OPTIONS[2]="ON"

STORAGE_NAME=$(whiptail --title "STORAGE POOLS" --radiolist "Which storage pool for VM disk?\n(Spacebar to select)" 15 60 5 "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$STORAGE_NAME" ]; then exit 1; fi

BRIDGE_NET=$(whiptail --title "NETWORK BRIDGE" --inputbox "Select network bridge:" 10 58 "vmbr0" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$BRIDGE_NET" ]; then exit 1; fi

MTU_SIZE=$(whiptail --title "MTU SIZE" --inputbox "Set Interface MTU Size\n(leave blank for default 1500)" 10 58 "" 3>&1 1>&2 2>&3)
if [ $? != 0 ]; then exit 1; fi

IP_METHOD=$(whiptail --title "IPv4 CONFIGURATION" --menu "Select IPv4 Address Assignment:" 15 58 3 \
"dhcp" "Automatic (DHCP)" \
"static" "Static (manual entry)" \
3>&1 1>&2 2>&3)
if [ $? != 0 ]; then exit 1; fi

IPV4_STATIC=""
GW_ADDR=""
if [ "$IP_METHOD" = "static" ]; then
    IPV4_STATIC=$(whiptail --title "STATIC IPv4 ADDRESS" --inputbox "Enter Static IPv4 CIDR Address\n(e.g. 192.168.0.110/24)" 10 58 "" 3>&1 1>&2 2>&3)
    if [ $? != 0 ] || [ -z "$IPV4_STATIC" ]; then exit 1; fi

    GW_ADDR=$(whiptail --title "GATEWAY IP" --inputbox "Enter Gateway IP address\n(e.g. 192.168.0.1)" 10 58 "" 3>&1 1>&2 2>&3)
    if [ $? != 0 ] || [ -z "$GW_ADDR" ]; then exit 1; fi
fi

DNS_ADDR=$(whiptail --title "DNS SERVER" --inputbox "Set DNS Server IP\n(leave blank to use host setting)" 10 58 "" 3>&1 1>&2 2>&3)
if [ $? != 0 ]; then exit 1; fi

DOMAIN_SRCH=$(whiptail --title "DNS SEARCH DOMAIN" --inputbox "Set DNS Search Domain\n(leave blank to use host setting)" 10 58 "" 3>&1 1>&2 2>&3)
if [ $? != 0 ]; then exit 1; fi

CRONICLE_URL=$(whiptail --title "CRONICLE-EDGE BASE URL" --inputbox "Set the Base URL for the Cronicle-Edge Web UI" 10 70 "http://cronicle.local:3012" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$CRONICLE_URL" ]; then exit 1; fi

DISABLE_IPV6=$(whiptail --title "IPv6 CONFIGURATION" --menu "Select IPv6 Address Management:" 15 65 3 \
"auto" " - SLAAC/AUTO" \
"disable" " - Fully Disabled (recommended)" \
3>&1 1>&2 2>&3)
if [ $? != 0 ]; then exit 1; fi

TZ_SET=$(whiptail --title "CONTAINER TIMEZONE" --inputbox "Set VM timezone.\nLeave empty to inherit from host." 10 58 "America/Sao_Paulo" 3>&1 1>&2 2>&3)
if [ $? != 0 ]; then exit 1; fi

whiptail --title "SSH ACCESS" --yesno "Enable root SSH access?" 10 58
if [ $? -eq 0 ]; then SSH_ENABLE="true"; else SSH_ENABLE="false"; fi

# ==========================================================
# 3. PREPARAÇÃO DOS DADOS
# ==========================================================

# Senha de root
HASH_PASS=$(openssl passwd -6 "$ROOT_PASS")

# Garante porta padrão do cronicle-edge se a URL vier sem porta
if [[ "$CRONICLE_URL" =~ ^https?://[^/:]+$ ]]; then
    CRONICLE_URL="${CRONICLE_URL}:3012"
fi

# Tratamento do E-mail a partir da URL (sem porta)
CLEAN_DOMAIN_FOR_EMAIL=$(echo "$CRONICLE_URL" | sed -E 's|https?://||' | sed -E 's|/.*$||' | sed -E 's|:.*$||' | sed -E 's|^[^.]+\.|ti@|')

NET_STR="virtio,bridge=$BRIDGE_NET"
if [ -n "${MTU_SIZE:-}" ]; then
    NET_STR="$NET_STR,mtu=$MTU_SIZE"
fi

if [ "$IP_METHOD" = "dhcp" ]; then
    IP_CONF="ip=dhcp"
    IP_DISP="DHCP"
else
    IP_CONF="ip=$IPV4_STATIC,gw=$GW_ADDR"
    IP_DISP="$IPV4_STATIC"
fi

if [ "$SSH_ENABLE" = "true" ]; then
    CMD_SSH1="mkdir -p /etc/ssh/sshd_config.d"
    CMD_SSH2="printf '%s\n' 'PermitRootLogin yes' 'PasswordAuthentication yes' > /etc/ssh/sshd_config.d/99-root.conf"
    CMD_SSH3="systemctl restart ssh || systemctl restart sshd || true"
else
    CMD_SSH1="# SSH desativado"
    CMD_SSH2="# SSH desativado"
    CMD_SSH3="# SSH desativado"
fi

if [ "$DISABLE_IPV6" = "disable" ]; then
    CMD_IPV6_GRUB="sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"ipv6.disable=1 /' /etc/default/grub || true"
    CMD_IPV6_SYS1="printf '%s\n' 'net.ipv6.conf.all.disable_ipv6 = 1' > /etc/sysctl.d/99-disable-ipv6.conf"
    CMD_IPV6_SYS2="printf '%s\n' 'net.ipv6.conf.default.disable_ipv6 = 1' >> /etc/sysctl.d/99-disable-ipv6.conf"
    CMD_IPV6_SYS3="printf '%s\n' 'net.ipv6.conf.lo.disable_ipv6 = 1' >> /etc/sysctl.d/99-disable-ipv6.conf"
    CMD_IPV6_SYS4="sysctl --system || true"
else
    CMD_IPV6_GRUB="# IPv6 mantido"
    CMD_IPV6_SYS1="# IPv6 mantido"
    CMD_IPV6_SYS2="# IPv6 mantido"
    CMD_IPV6_SYS3="# IPv6 mantido"
    CMD_IPV6_SYS4="# IPv6 mantido"
fi

CRONICLE_DIR="/opt/cronicle"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
IMAGE_FILE="debian-13-generic-amd64.qcow2"
SECRET_KEY=$(openssl rand -hex 32)

if [ -n "${DOMAIN_SRCH:-}" ]; then
    FQDN_LINE="fqdn: ${VM_NAME}.${DOMAIN_SRCH}"
else
    FQDN_LINE="fqdn: ${VM_NAME}"
fi

# ==========================================================
# 4. TELA DE RESUMO
# ==========================================================
C_GREEN_BOLD="\e[1;32m"
C_BLUE_BOLD="\e[1;34m"
C_YELLOW_BOLD="\e[1;33m"
C_BLUE_BOLD_UNDER="\e[1;34;4m"
C_RESET="\e[0m"

clear
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "💡" "PVE Version:" "$(pveversion | cut -d' ' -f1)"
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "🖥️" "O.S.:" "Debian 13 (Q35 + UEFI)"
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "📦" "Type:" "Virtual Machine (QEMU)"
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "🆔" "VM ID:" "$VM_ID"
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "🏠" "Hostname:" "$VM_NAME"
printf " %s  %-15s ${C_GREEN_BOLD}%s GB${C_RESET}\n" "💾" "Disk Size:" "$DISK_SIZE"
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "🧠" "CPU Cores:" "$VM_CORES"
printf " %s  %-15s ${C_GREEN_BOLD}%s MiB${C_RESET}\n" "🛠️" "RAM Size:" "$VM_MEM"
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "🌉" "Bridge:" "$BRIDGE_NET"
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "📡" "IPv4:" "$IP_DISP"
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "📡" "IPv6:" "$DISABLE_IPV6"
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "🌍" "DNS Domain:" "${DOMAIN_SRCH:-Host Default}"
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "🌍" "DNS Server:" "${DNS_ADDR:-Host Default}"
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "💡" "Timezone:" "${TZ_SET:-Host Default}"
printf " %s  %-15s ${C_GREEN_BOLD}%s${C_RESET}\n" "🌐" "Base URL:" "$CRONICLE_URL"
printf "\n"
printf " 🚀  Creating VM of Cronicle-Edge Master using the above settings...\n\n"

# ==========================================================
# 5. DEPLOY NO PROXMOX
# ==========================================================
if [ ! -f "$IMAGE_FILE" ]; then
    wget -q --show-progress -O "$IMAGE_FILE" "$IMAGE_URL"
fi

qm create "$VM_ID" --name "$VM_NAME" --memory "$VM_MEM" --cores "$VM_CORES" --net0 "$NET_STR" > /dev/null 2>&1
qm importdisk "$VM_ID" "$IMAGE_FILE" "$STORAGE_NAME" > /dev/null 2>&1

qm set "$VM_ID" \
    --machine q35 \
    --bios ovmf \
    --efidisk0 "$STORAGE_NAME:0,efitype=4m,pre-enrolled-keys=1" \
    --scsihw virtio-scsi-single \
    --scsi0 "$STORAGE_NAME:vm-$VM_ID-disk-0,iothread=1,discard=on" \
    --boot c --bootdisk scsi0 \
    --tablet 0 \
    --agent enabled=1 \
    --cpu host \
    --onboot 1 \
    --ostype l26 > /dev/null 2>&1

qm set "$VM_ID" --ipconfig0 "$IP_CONF" > /dev/null 2>&1
if [ -n "${DNS_ADDR:-}" ]; then qm set "$VM_ID" --nameserver "$DNS_ADDR" > /dev/null 2>&1; fi
if [ -n "${DOMAIN_SRCH:-}" ]; then qm set "$VM_ID" --searchdomain "$DOMAIN_SRCH" > /dev/null 2>&1; fi

qm set "$VM_ID" --ciuser "root" --cipassword "$ROOT_PASS" > /dev/null 2>&1

SNIPPET_PATH="/var/lib/vz/snippets/edge-manager-$VM_ID.yaml"
mkdir -p /var/lib/vz/snippets

cat <<EOF > "$SNIPPET_PATH"
#cloud-config
hostname: $VM_NAME
$FQDN_LINE
manage_etc_hosts: true
timezone: $TZ_SET

disable_root: false
ssh_pwauth: $SSH_ENABLE

chpasswd:
  list:
    - root:$HASH_PASS
  expire: False

packages:
  - qemu-guest-agent
  - ca-certificates
  - curl
  - wget
  - git
  - jq
  - procps
  - build-essential
  - openssl
  - nodejs
  - npm
  - python3
  - python3-venv

write_files:
  - path: /root/configure_os.sh
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      set -euxo pipefail
      $CMD_IPV6_GRUB
      $CMD_IPV6_SYS1
      $CMD_IPV6_SYS2
      $CMD_IPV6_SYS3
      $CMD_IPV6_SYS4
      update-grub || true
      $CMD_SSH1
      $CMD_SSH2
      $CMD_SSH3

  - path: /root/install_cronicle_edge.sh
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      set -euxo pipefail
      export HOME=/root
      exec > >(tee -a /var/log/cronicle_edge_install.log) 2>&1

      CRONICLE_DIR="$CRONICLE_DIR"
      CRONICLE_URL="$CRONICLE_URL"
      DOMAIN_SRCH="$DOMAIN_SRCH"
      CLEAN_DOMAIN_FOR_EMAIL="$CLEAN_DOMAIN_FOR_EMAIL"
      SECRET_KEY="$SECRET_KEY"

      rm -rf /tmp/cronicle-edge
      git clone --depth 1 https://github.com/cronicle-edge/cronicle-edge.git /tmp/cronicle-edge
      cd /tmp/cronicle-edge

      ./bundle "\$CRONICLE_DIR"

      cd "\$CRONICLE_DIR"

      # secret key antes do primeiro start
      install -m 700 -d "\$CRONICLE_DIR/conf"
      printf '%s\n' "\$SECRET_KEY" > "\$CRONICLE_DIR/conf/secret_key"
      chmod 600 "\$CRONICLE_DIR/conf/secret_key"

      # Injeta as variaveis diretamente no setup.json usando sed
      sed -i "s|http://localhost:3012|\$CRONICLE_URL|g" conf/setup.json
      sed -i "s|admin@cronicle.com|\$CLEAN_DOMAIN_FOR_EMAIL|g" conf/setup.json
      sed -i "s|corp.cronicle.com|\$DOMAIN_SRCH|g" conf/setup.json

      # Ajusta plugin padrão "Shell Script" para usar UID root antes do setup inicial
      TMP_SETUP=\$(mktemp)
      jq '
        .storage |= map(
          if (
            .[0] == "listPush"
            and .[1] == "global/plugins"
            and (
              .[2].id == "shellplug"
              or .[2].title == "Shell Script"
              or .[2].command == "node bin/shell-plugin.js"
            )
          ) then
            .[2].uid = "root"
            | .[2].title = "Shell Script"
          else
            .
          end
        )
      ' conf/setup.json > "\$TMP_SETUP"
      mv "\$TMP_SETUP" conf/setup.json

      # Ajusta também config.json antes do primeiro start
      jq \
        --arg url "\$CRONICLE_URL" \
        --arg email "\$CLEAN_DOMAIN_FOR_EMAIL" \
        --arg domain "\$DOMAIN_SRCH" \
        --arg secret "\$SECRET_KEY" \
        '
          .base_app_url = \$url
          | .custom_live_log_socket_url = \$url
          | .email_from = \$email
          | .ad_domain = \$domain
          | .secret_key = \$secret
          | .WebServer.http_port = 3012
          | .WebServer.https_port = 3013
        ' conf/config.json > conf/config.json.tmp
      mv conf/config.json.tmp conf/config.json

      # prepara storage/setup antes do start
      node "\$CRONICLE_DIR/bin/storage-cli.js" setup || true

      # Serviço systemd em modo manager
      cat > /etc/systemd/system/cronicle-edge.service <<UNIT
      [Unit]
      Description=Cronicle Edge Manager
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=simple
      WorkingDirectory=$CRONICLE_DIR
      ExecStart=$CRONICLE_DIR/bin/manager --port 3012
      Restart=always
      RestartSec=5
      User=root
      Environment=HOME=/root
      LimitNOFILE=65535

      [Install]
      WantedBy=multi-user.target
      UNIT

      systemctl daemon-reload
      systemctl enable cronicle-edge
      systemctl restart cronicle-edge

      for i in \$(seq 1 60); do
          if ss -lntp | grep -q ':3012 '; then
              exit 0
          fi
          sleep 2
      done

      echo "Cronicle-Edge manager não abriu na porta 3012 a tempo."
      exit 1

runcmd:
  - sh -c 'echo "kernel.printk = 3 4 1 3" > /etc/sysctl.d/20-quiet.conf'
  - sysctl -p /etc/sysctl.d/20-quiet.conf
  - dmesg -n 1
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - usermod -U root
  - /root/configure_os.sh
  - /root/install_cronicle_edge.sh
EOF

qm set "$VM_ID" --ide2 "$STORAGE_NAME:cloudinit" > /dev/null 2>&1
qm set "$VM_ID" --cicustom "user=local:snippets/edge-manager-$VM_ID.yaml" > /dev/null 2>&1
qm resize "$VM_ID" scsi0 "${DISK_SIZE}G" > /dev/null 2>&1

# ==========================================================
# 6. INICIALIZAÇÃO E VALIDAÇÃO SÍNCRONA
# ==========================================================

printf "\n ⚙️  ${C_BLUE_BOLD}Starting the Virtual Machine and validating installation...${C_RESET}\n"
qm start "$VM_ID" > /dev/null 2>&1

printf "    ⏳ Waiting for QEMU Guest Agent...\n"
while ! qm agent "$VM_ID" ping >/dev/null 2>&1; do sleep 5; done

printf "    ⏳ Waiting for Cloud-Init...\n"
while true; do
    CI_STATUS=$(qm guest exec "$VM_ID" -- cloud-init status 2>/dev/null || true)
    if echo "$CI_STATUS" | grep -q "status: done"; then
        break
    elif echo "$CI_STATUS" | grep -q "status: error"; then
        printf "    ❌ Critical Cloud-Init failure on the VM. Check /var/log/cloud-init-output.log\n"
        exit 1
    fi
    sleep 5
done

printf "    ⏳ Validating Cronicle-Edge Manager on port 3012...\n"
while true; do
    CURL_TEST=$(qm guest exec "$VM_ID" -- bash -lc "ss -lntp | grep ':3012 '" 2>/dev/null || true)
    if echo "$CURL_TEST" | grep -q "LISTEN"; then
        break
    fi
    sleep 3
done

# ==========================================================
# 7. CONCLUSÃO E LIMPEZA
# ==========================================================

qm set "$VM_ID" --delete cicustom > /dev/null 2>&1
rm -f "/var/lib/vz/snippets/edge-manager-$VM_ID.yaml"

CLEAN_URL=$(echo "$CRONICLE_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
if [ "$IP_METHOD" = "static" ]; then
    CLEAN_IP="${IPV4_STATIC%/*}"
else
    CLEAN_IP="DHCP"
fi

printf "\n${C_GREEN_BOLD}✔ Done!${C_RESET}\n"
printf "\n🌐  ${C_BLUE_BOLD_UNDER}%s${C_RESET}\n" "$CRONICLE_URL"
printf "🧩  Cronicle-Edge role: ${C_GREEN_BOLD}MANAGER${C_RESET}\n"
printf "🐍  Python installed: ${C_GREEN_BOLD}python3 + python3-venv${C_RESET}\n"
printf "🛠️  Service name: ${C_GREEN_BOLD}cronicle-edge.service${C_RESET}\n"

if [ "$IP_METHOD" = "static" ]; then
    printf "\n⚠️  ${C_YELLOW_BOLD}Lembre-se:${C_RESET} Aponte o DNS/local name de ${C_BLUE_BOLD}%s${C_RESET} para ${C_GREEN_BOLD}%s${C_RESET}.\n\n" "$CLEAN_URL" "$CLEAN_IP"
else
    printf "\n⚠️  ${C_YELLOW_BOLD}Lembre-se:${C_RESET} Como a VM está em DHCP, confira o IP recebido e aponte ${C_BLUE_BOLD}%s${C_RESET} para ele.\n\n" "$CLEAN_URL"
fi
