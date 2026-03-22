#!/usr/bin/env bash

# ==========================================================
# 1. VERIFICAÇÃO DE DEPENDÊNCIAS (WHIPTAIL)
# ==========================================================
if ! command -v whiptail &> /dev/null; then
    apt-get update >/dev/null 2>&1
    apt-get install -y whiptail >/dev/null 2>&1
fi

# ==========================================================
# 2. INTERFACE GRÁFICA (TUI) - COLETA DE VARIÁVEIS
# ==========================================================

NEXT_ID=$(pvesh get /cluster/nextid)
VM_ID=$(whiptail --title "VM ID" --inputbox "Set VM ID\n(O Proxmox sugeriu o próximo ID livre automaticamente)" 10 58 "$NEXT_ID" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$VM_ID" ]; then exit 1; fi

VM_NAME=$(whiptail --title "HOSTNAME" --inputbox "Set Hostname (or FQDN, e.g. host.example.com)" 10 58 "srvCronicle" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$VM_NAME" ]; then exit 1; fi

ROOT_PASS=$(whiptail --title "ROOT PASSWORD" --passwordbox "Set Root Password (needed for root ssh access)" 10 58 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$ROOT_PASS" ]; then exit 1; fi

VM_CORES=$(whiptail --title "CPU CORES" --inputbox "Allocate CPU Cores" 10 58 "2" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$VM_CORES" ]; then exit 1; fi

VM_MEM=$(whiptail --title "RAM SIZE" --inputbox "Allocate RAM in MiB" 10 58 "2048" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$VM_MEM" ]; then exit 1; fi

DISK_SIZE=$(whiptail --title "DISK SIZE" --inputbox "Set Disk Size in GB" 10 58 "20" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$DISK_SIZE" ]; then exit 1; fi

mapfile -t AVAILABLE_STORAGES < <(pvesm status -content images | awk 'NR>1 {print $1}')
if [ ${#AVAILABLE_STORAGES[@]} -eq 0 ]; then whiptail --msgbox "Nenhum storage compatível encontrado." 10 58; exit 1; fi
MENU_OPTIONS=()
for st in "${AVAILABLE_STORAGES[@]}"; do MENU_OPTIONS+=("$st" "" "OFF"); done
MENU_OPTIONS[2]="ON"
STORAGE_NAME=$(whiptail --title "STORAGE POOLS" --radiolist "Which storage pool for VM disk?\n(Spacebar to select)" 15 60 5 "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$STORAGE_NAME" ]; then exit 1; fi

BRIDGE_NET=$(whiptail --title "NETWORK BRIDGE" --inputbox "Select network bridge:" 10 58 "vmbr0" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$BRIDGE_NET" ]; then exit 1; fi

MTU_SIZE=$(whiptail --title "MTU SIZE" --inputbox "Set Interface MTU Size\n(leave blank for default 1500)" 10 58 "" 3>&1 1>&2 2>&3)
if [ $? != 0 ]; then exit 1; fi

IP_METHOD=$(whiptail --title "IPv4 CONFIGURATION" --menu "Select IPv4 Address Assignment:" 15 58 3 "dhcp" "Automatic (DHCP)" "static" "Static (manual entry)" 3>&1 1>&2 2>&3)
if [ $? != 0 ]; then exit 1; fi

if [ "$IP_METHOD" = "static" ]; then
    IPV4_STATIC=$(whiptail --title "STATIC IPv4 ADDRESS" --inputbox "Enter Static IPv4 CIDR Address\n(e.g. 192.168.0.110/21)" 10 58 "" 3>&1 1>&2 2>&3)
    if [ $? != 0 ] || [ -z "$IPV4_STATIC" ]; then exit 1; fi

    GW_ADDR=$(whiptail --title "GATEWAY IP" --inputbox "Enter Gateway IP address\n(e.g. 192.168.0.2)" 10 58 "" 3>&1 1>&2 2>&3)
    if [ $? != 0 ] || [ -z "$GW_ADDR" ]; then exit 1; fi
fi

DOMAIN_SRCH=$(whiptail --title "DNS SEARCH DOMAIN" --inputbox "Set DNS Search Domain\n(leave blank to use host setting)" 10 58 "" 3>&1 1>&2 2>&3)
if [ $? != 0 ]; then exit 1; fi

DNS_ADDR=$(whiptail --title "DNS SERVER" --inputbox "Set DNS Server IP\n(leave blank to use host setting)" 10 58 "" 3>&1 1>&2 2>&3)
if [ $? != 0 ]; then exit 1; fi

DISABLE_IPV6=$(whiptail --title "IPv6 CONFIGURATION" --menu "Select IPv6 Address Management:" 15 65 3 "auto" "SLAAC/AUTO (recommended)" "disable" "Fully Disabled" 3>&1 1>&2 2>&3)
if [ $? != 0 ]; then exit 1; fi

TZ_SET=$(whiptail --title "CONTAINER TIMEZONE" --inputbox "Set VM timezone.\nLeave empty to inherit from host." 10 58 "America/Sao_Paulo" 3>&1 1>&2 2>&3)
if [ $? != 0 ]; then exit 1; fi

whiptail --title "SSH ACCESS" --yesno "Enable root SSH access?" 10 58
# CORREÇÃO 1: YAML booleans precisam ser "true" ou "false"
if [ $? -eq 0 ]; then SSH_ENABLE="true"; else SSH_ENABLE="false"; fi

CRONICLE_URL=$(whiptail --title "CRONICLE BASE URL" --inputbox "Set the Base URL for the Cronicle Web UI" 10 58 "http://cronicle.local" 3>&1 1>&2 2>&3)
if [ $? != 0 ] || [ -z "$CRONICLE_URL" ]; then exit 1; fi

# ==========================================================
# 3. PREPARAÇÃO DOS DADOS E TRATAMENTO DE VARIÁVEIS YAML
# ==========================================================

HASH_PASS=$(openssl passwd -6 "$ROOT_PASS")

NET_STR="virtio,bridge=$BRIDGE_NET"
if [ -n "$MTU_SIZE" ]; then NET_STR="$NET_STR,mtu=$MTU_SIZE"; fi

if [ "$IP_METHOD" = "dhcp" ]; then
    IP_CONF="ip=dhcp"
    IP_DISP="DHCP"
else
    IP_CONF="ip=$IPV4_STATIC,gw=$GW_ADDR"
    IP_DISP="$IPV4_STATIC"
fi

# CORREÇÃO 2: Força o SSH criando arquivo definitivo na pasta .d
if [ "$SSH_ENABLE" = "true" ]; then
    CMD_SSH1="- sh -c 'echo \"PermitRootLogin yes\" > /etc/ssh/sshd_config.d/99-root.conf'"
    CMD_SSH2="- sh -c 'echo \"PasswordAuthentication yes\" >> /etc/ssh/sshd_config.d/99-root.conf'"
    CMD_SSH3="- systemctl restart ssh"
else
    CMD_SSH1="# SSH desativado"
    CMD_SSH2="# SSH desativado"
    CMD_SSH3="# SSH desativado"
fi

# CORREÇÃO 3: Nomes de arquivos de sysctl corrigidos para não se sobrescreverem
if [ "$DISABLE_IPV6" = "disable" ]; then
    CMD_IPV6_GRUB="- sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"ipv6.disable=1 quiet loglevel=3 /' /etc/default/grub"
    CMD_IPV6_SYS1="- sh -c 'echo \"net.ipv6.conf.all.disable_ipv6 = 1\" > /etc/sysctl.d/99-disable-ipv6.conf'"
    CMD_IPV6_SYS2="- sh -c 'echo \"net.ipv6.conf.default.disable_ipv6 = 1\" >> /etc/sysctl.d/99-disable-ipv6.conf'"
    CMD_IPV6_SYS3="- sh -c 'echo \"net.ipv6.conf.lo.disable_ipv6 = 1\" >> /etc/sysctl.d/99-disable-ipv6.conf'"
    CMD_IPV6_SYS4="- sysctl --system"
else
    CMD_IPV6_GRUB="- sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet loglevel=3 /' /etc/default/grub"
    CMD_IPV6_SYS1="# IPv6 Mantido"
    CMD_IPV6_SYS2="# IPv6 Mantido"
    CMD_IPV6_SYS3="# IPv6 Mantido"
    CMD_IPV6_SYS4="# IPv6 Mantido"
fi

CRONICLE_DIR="/opt/cronicle"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
IMAGE_FILE="debian-13-generic-amd64.qcow2"

C_GREEN_BOLD="\e[1;32m"
C_BLUE_BOLD="\e[1;34m"
C_YELLOW_BOLD="\e[1;33m"
C_BLUE_BOLD_UNDER="\e[1;34;4m"
C_WHITE_BOLD="\e[1;37m"
C_RESET="\e[0m"

# ==========================================================
# 4. TELA DE RESUMO (VISUAL TTECK)
# ==========================================================
clear
printf "${C_GREEN_BOLD}✔ Using Advanced Install on node %s${C_RESET}\n\n" "$(hostname)"
printf " 💡 PVE Version: ${C_GREEN_BOLD}%s${C_RESET}\n" "$(pveversion | cut -d' ' -f1)"
printf " 🖥️  Operating System: ${C_GREEN_BOLD}Debian 13${C_RESET}\n"
printf " 📦 Type: ${C_GREEN_BOLD}Virtual Machine (QEMU)${C_RESET}\n"
printf " 🆔 VM ID: ${C_GREEN_BOLD}%s${C_RESET}\n" "$VM_ID"
printf " 🏠 Hostname: ${C_GREEN_BOLD}%s${C_RESET}\n" "$VM_NAME"
printf " 💾 Disk Size: ${C_GREEN_BOLD}%s GB${C_RESET}\n" "$DISK_SIZE"
printf " 🧠 CPU Cores: ${C_GREEN_BOLD}%s${C_RESET}\n" "$VM_CORES"
printf " 🛠️  RAM Size: ${C_GREEN_BOLD}%s MiB${C_RESET}\n" "$VM_MEM"
printf " 🌉 Bridge: ${C_GREEN_BOLD}%s${C_RESET}\n" "$BRIDGE_NET"
printf " 📡 IPv4: ${C_GREEN_BOLD}%s${C_RESET}\n" "$IP_DISP"
printf " 📡 IPv6: ${C_GREEN_BOLD}%s${C_RESET}\n" "$DISABLE_IPV6"
printf " 🌍 DNS Domain: ${C_GREEN_BOLD}%s${C_RESET}\n" "${DOMAIN_SRCH:-Host Default}"
printf " 🌍 DNS Server: ${C_GREEN_BOLD}%s${C_RESET}\n" "${DNS_ADDR:-Host Default}"
printf " 💡 Timezone: ${C_GREEN_BOLD}%s${C_RESET}\n" "${TZ_SET:-Host Default}"
printf " 🌐 Base URL: ${C_GREEN_BOLD}%s${C_RESET}\n" "$CRONICLE_URL"
printf "\n"
printf " 🚀 Creating VM of Cronicle-Edge Master using the above advanced settings...\n\n"

# ==========================================================
# 5. DEPLOY NO PROXMOX
# ==========================================================
if [ ! -f "$IMAGE_FILE" ]; then wget -q --show-progress -O "$IMAGE_FILE" "$IMAGE_URL"; fi

qm create "$VM_ID" --name "$VM_NAME" --memory "$VM_MEM" --cores "$VM_CORES" --net0 "$NET_STR" > /dev/null 2>&1
qm importdisk "$VM_ID" "$IMAGE_FILE" "$STORAGE_NAME" > /dev/null 2>&1
qm set "$VM_ID" --scsihw virtio-scsi-single \
                --scsi0 "$STORAGE_NAME:vm-$VM_ID-disk-0,iothread=1,discard=on" \
                --boot c --bootdisk scsi0 --tablet 0 --agent enabled=1 --cpu host --onboot 1 --ostype l26 > /dev/null 2>&1

qm set "$VM_ID" --ipconfig0 "$IP_CONF" > /dev/null 2>&1
if [ -n "$DNS_ADDR" ]; then qm set "$VM_ID" --nameserver "$DNS_ADDR" > /dev/null 2>&1; fi
if [ -n "$DOMAIN_SRCH" ]; then qm set "$VM_ID" --searchdomain "$DOMAIN_SRCH" > /dev/null 2>&1; fi

qm set "$VM_ID" --ciuser "root" --cipassword "$ROOT_PASS" > /dev/null 2>&1

SNIPPET_PATH="/var/lib/vz/snippets/edge-master-$VM_ID.yaml"
mkdir -p /var/lib/vz/snippets

cat <<EOF > "$SNIPPET_PATH"
#cloud-config
hostname: $VM_NAME
fqdn: $VM_NAME.$DOMAIN_SRCH
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
  - curl
  - git
  - build-essential
  - jq
  - procps
  - nodejs
  - npm

write_files:
  - path: /root/install_cronicle.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      export HOME=/root
      exec > /var/log/cronicle_install.log 2>&1
      set -x
      git clone https://github.com/cronicle-edge/cronicle-edge.git /tmp/cronicle-edge
      cd /tmp/cronicle-edge
      ./bundle $CRONICLE_DIR
      cd $CRONICLE_DIR
      if [ -f "bin/control.sh" ]; then
          ./bin/control.sh setup
      fi
      jq '.WebServer.http_port = 80 | .base_app_url = "$CRONICLE_URL"' conf/config.json > conf/config.json.tmp
      mv conf/config.json.tmp conf/config.json
      ./bin/control.sh start
      echo "$CRONICLE_DIR/bin/control.sh start" >> /etc/rc.local
      chmod +x /etc/rc.local

runcmd:
  - sh -c 'echo "kernel.printk = 3 4 1 3" > /etc/sysctl.d/20-quiet.conf'
  - sysctl -p /etc/sysctl.d/20-quiet.conf
  - dmesg -n 1
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - usermod -U root
  $CMD_IPV6_GRUB
  $CMD_IPV6_SYS1
  $CMD_IPV6_SYS2
  $CMD_IPV6_SYS3
  $CMD_IPV6_SYS4
  - update-grub
  $CMD_SSH1
  $CMD_SSH2
  $CMD_SSH3
  - /root/install_cronicle.sh
EOF

qm set "$VM_ID" --ide2 "$STORAGE_NAME:cloudinit" > /dev/null 2>&1
qm set "$VM_ID" --cicustom "user=local:snippets/edge-master-$VM_ID.yaml" > /dev/null 2>&1
qm resize "$VM_ID" scsi0 "${DISK_SIZE}G" > /dev/null 2>&1

# ==========================================================
# 6. INICIALIZAÇÃO E VALIDAÇÃO SÍNCRONA
# ==========================================================

printf "\n ⚙️  ${C_BLUE_BOLD}Starting the Virtual Machine and validating installation...${C_RESET}\n"
qm start "$VM_ID" > /dev/null 2>&1

printf "      ⏳ Starting the VM and updating...\n"
while ! qm agent "$VM_ID" ping >/dev/null 2>&1; do sleep 5; done

printf "      ⏳ Waiting for Cloud-Init installation...\n"
while true; do
    CI_STATUS=$(qm guest exec "$VM_ID" -- cloud-init status 2>/dev/null)
    if echo "$CI_STATUS" | grep -q "status: done"; then
        break
    elif echo "$CI_STATUS" | grep -q "status: error"; then
        printf "      ❌ Critical Cloud-Init failure on the VM. Check /var/log/cloud-init-output.log \n"
        exit 1
    fi
    sleep 5
done

printf "      ⏳ Validating Cronicle-Edge...\n"
while true; do
    CURL_TEST=$(qm guest exec "$VM_ID" -- bash -c "ss -tulpn | grep :80" 2>/dev/null)
    if echo "$CURL_TEST" | grep -q "LISTEN"; then
        break
    fi
    sleep 3
done

# ==========================================================
# 7. CONCLUSÃO CIRÚRGICA E PERSONALIZADA
# ==========================================================
CLEAN_URL=$(echo "$CRONICLE_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
CLEAN_IP="${IPV4_STATIC%/*}"

printf "\n${C_GREEN_BOLD}✔ Done!${C_RESET}\n"
printf "\n🌐 Acesse: ${C_BLUE_BOLD_UNDER}%s${C_RESET}\n" "$CRONICLE_URL"
printf "\n⚠️  ${C_YELLOW_BOLD}Lembre-se:${C_RESET} Aponte o DNS local de ${C_BLUE_BOLD}%s${C_RESET} para ${C_GREEN_BOLD}%s${C_RESET}.\n\n" "$CLEAN_URL" "$CLEAN_IP"
