#!/bin/bash

# ==========================================================
# MULTI-INSTANCE GENIEACS INSTALLER FOR NAT VPS
# Modified by Gemini
# Original Logic by Hendri
# ==========================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== MULTI-INSTANCE GENIEACS INSTALLER ===${NC}"
echo -e "${YELLOW}Script ini memungkinkan Anda menginstall banyak GenieACS dalam satu VPS.${NC}"
sleep 1

# ---------------------------------------------------------------------
# 1. INPUT CONFIGURATION
# ---------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[ INPUT KONFIGURASI INSTANCE ]${NC}"
read -p "Masukkan Nama Instance (misal: client1, vps2): " INSTANCE_NAME

if [[ -z "$INSTANCE_NAME" ]]; then
    echo -e "${RED}Error: Nama Instance tidak boleh kosong!${NC}"
    exit 1
fi

# Cek apakah folder instance sudah ada
if [ -d "/opt/genieacs-${INSTANCE_NAME}" ]; then
    echo -e "${RED}Error: Instance dengan nama '${INSTANCE_NAME}' sudah ada!${NC}"
    exit 1
fi

echo -e "Masukkan Port untuk Instance '${INSTANCE_NAME}' (Tekan Enter untuk default)"
read -p "UI Port (Default 3000): " PORT_UI
PORT_UI=${PORT_UI:-3000}

read -p "CWMP Port (Default 7547): " PORT_CWMP
PORT_CWMP=${PORT_CWMP:-7547}

read -p "NBI Port (Default 7557): " PORT_NBI
PORT_NBI=${PORT_NBI:-7557}

read -p "FS Port (Default 7567): " PORT_FS
PORT_FS=${PORT_FS:-7567}

echo ""
echo -e "${GREEN}Ringkasan Instalasi:${NC}"
echo "Instance : $INSTANCE_NAME"
echo "Database : genieacs-${INSTANCE_NAME}"
echo "UI Port  : $PORT_UI"
echo "CWMP Port: $PORT_CWMP"
echo "NBI Port : $PORT_NBI"
echo "FS Port  : $PORT_FS"
echo ""
read -p "Lanjut install? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Instalasi dibatalkan."
    exit 0
fi

# ---------------------------------------------------------------------
# 2. SYSTEM UPDATE & DEPENDENCIES (SKIP IF INSTALLED)
# ---------------------------------------------------------------------
echo ""
echo -e "${YELLOW}[ MEMERIKSA DEPENDENCIES ]${NC}"

if ! command -v node &> /dev/null; then
    echo "Menginstall Node.js & Dependencies..."
    apt update && apt upgrade -y
    apt install -y curl wget git gnupg build-essential
    curl -sL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
else
    echo "Node.js sudah terinstall. Skip."
fi

if ! command -v mongod &> /dev/null; then
    echo "Menginstall MongoDB 6.0..."
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc | \
        gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor

    echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] \
    https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc)/mongodb-org/6.0 multiverse" \
        > /etc/apt/sources.list.d/mongodb-org-6.0.list

    apt update
    apt install -y mongodb-org
    systemctl enable --now mongod
else
    echo "MongoDB sudah terinstall. Skip."
fi

# Install GenieACS Global Package jika belum ada
if ! npm list -g genieacs | grep genieacs &> /dev/null; then
    echo "Menginstall Core GenieACS..."
    npm install -g genieacs@1.2.13
else
    echo "Core GenieACS sudah terinstall. Skip."
fi

# ---------------------------------------------------------------------
# 3. SETUP USER & DIRECTORIES
# ---------------------------------------------------------------------
# Buat user genieacs jika belum ada
id -u genieacs &>/dev/null || useradd --system --no-create-home --user-group genieacs

# Folder khusus per instance
INSTALL_DIR="/opt/genieacs-${INSTANCE_NAME}"
LOG_DIR="/var/log/genieacs-${INSTANCE_NAME}"

mkdir -p "$INSTALL_DIR/ext"
mkdir -p "$LOG_DIR"

chown -R genieacs:genieacs "$INSTALL_DIR" "$LOG_DIR"
chmod 755 "$INSTALL_DIR"

# ---------------------------------------------------------------------
# 4. CREATE ENV CONFIG (SPECIFIC DB & PORTS)
# ---------------------------------------------------------------------
# Kita menambahkan GENIEACS_MONGODB_CONNECTION_URL untuk memisahkan database

cat <<EOF > "$INSTALL_DIR/genieacs.env"
GENIEACS_CWMP_HOST=0.0.0.0
GENIEACS_CWMP_PORT=$PORT_CWMP

GENIEACS_NBI_HOST=0.0.0.0
GENIEACS_NBI_PORT=$PORT_NBI

GENIEACS_FS_HOST=0.0.0.0
GENIEACS_FS_PORT=$PORT_FS

GENIEACS_UI_HOST=0.0.0.0
GENIEACS_UI_PORT=$PORT_UI

GENIEACS_MONGODB_CONNECTION_URL=mongodb://127.0.0.1:27017/genieacs-${INSTANCE_NAME}

GENIEACS_UI_JWT_SECRET=$(openssl rand -hex 32)
GENIEACS_EXT_DIR=$INSTALL_DIR/ext
EOF

chown genieacs:genieacs "$INSTALL_DIR/genieacs.env"
chmod 600 "$INSTALL_DIR/genieacs.env"

# ---------------------------------------------------------------------
# 5. CREATE SYSTEMD SERVICE FILES (NAMED BY INSTANCE)
# ---------------------------------------------------------------------
echo "Membuat Service Systemd untuk $INSTANCE_NAME..."

# CWMP Service
cat <<EOF > /etc/systemd/system/genieacs-${INSTANCE_NAME}-cwmp.service
[Unit]
Description=GenieACS CWMP (${INSTANCE_NAME})
After=network.target

[Service]
User=genieacs
EnvironmentFile=$INSTALL_DIR/genieacs.env
ExecStart=/usr/bin/genieacs-cwmp
StandardOutput=append:$LOG_DIR/cwmp.log
StandardError=append:$LOG_DIR/cwmp-error.log

[Install]
WantedBy=multi-user.target
EOF

# NBI Service
cat <<EOF > /etc/systemd/system/genieacs-${INSTANCE_NAME}-nbi.service
[Unit]
Description=GenieACS NBI (${INSTANCE_NAME})
After=network.target

[Service]
User=genieacs
EnvironmentFile=$INSTALL_DIR/genieacs.env
ExecStart=/usr/bin/genieacs-nbi
StandardOutput=append:$LOG_DIR/nbi.log
StandardError=append:$LOG_DIR/nbi-error.log

[Install]
WantedBy=multi-user.target
EOF

# FS Service
cat <<EOF > /etc/systemd/system/genieacs-${INSTANCE_NAME}-fs.service
[Unit]
Description=GenieACS File Server (${INSTANCE_NAME})
After=network.target

[Service]
User=genieacs
EnvironmentFile=$INSTALL_DIR/genieacs.env
ExecStart=/usr/bin/genieacs-fs
StandardOutput=append:$LOG_DIR/fs.log
StandardError=append:$LOG_DIR/fs-error.log

[Install]
WantedBy=multi-user.target
EOF

# UI Service
cat <<EOF > /etc/systemd/system/genieacs-${INSTANCE_NAME}-ui.service
[Unit]
Description=GenieACS UI (${INSTANCE_NAME})
After=network.target

[Service]
User=genieacs
EnvironmentFile=$INSTALL_DIR/genieacs.env
ExecStart=/usr/bin/genieacs-ui
StandardOutput=append:$LOG_DIR/ui.log
StandardError=append:$LOG_DIR/ui-error.log

[Install]
WantedBy=multi-user.target
EOF

# Reload & Start Services
systemctl daemon-reload
systemctl enable --now genieacs-${INSTANCE_NAME}-cwmp genieacs-${INSTANCE_NAME}-nbi genieacs-${INSTANCE_NAME}-fs genieacs-${INSTANCE_NAME}-ui

# ---------------------------------------------------------------------
# 6. FIREWALL
# ---------------------------------------------------------------------
if command -v ufw &> /dev/null; then
    ufw allow $PORT_UI/tcp
    ufw allow $PORT_CWMP/tcp
    ufw allow $PORT_NBI/tcp
    ufw allow $PORT_FS/tcp
fi

# ---------------------------------------------------------------------
# 7. SUMMARY
# ---------------------------------------------------------------------
IP=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================================"
echo -e " 🎉 INSTALASI GENIEACS INSTANCE: ${GREEN}$INSTANCE_NAME${NC} BERHASIL"
echo "============================================================"
echo " 🌐 GUI URL  : http://$IP:$PORT_UI"
echo " 📡 CWMP URL : http://$IP:$PORT_CWMP"
echo " 📁 FS URL   : http://$IP:$PORT_FS"
echo ""
echo " 💾 Config   : $INSTALL_DIR/genieacs.env"
echo " 📝 Logs     : $LOG_DIR"
echo " 🗄️  Database : genieacs-${INSTANCE_NAME}"
echo "============================================================"
echo " Commands untuk mengelola instance ini:"
echo " Stop  : systemctl stop genieacs-${INSTANCE_NAME}-*"
echo " Start : systemctl start genieacs-${INSTANCE_NAME}-*"
echo "============================================================"