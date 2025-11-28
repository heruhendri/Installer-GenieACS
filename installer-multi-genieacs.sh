#!/bin/bash

echo "=== AUTO MULTI INSTALL GENIEACS BY HENDRI ==="
echo ""

read -p "Masukkan jumlah instance yang ingin diinstall: " TOTAL

if ! [[ "$TOTAL" =~ ^[0-9]+$ ]]; then
    echo "Input harus angka!"
    exit 1
fi

if [ "$TOTAL" -lt 1 ]; then
    echo "Jumlah minimal 1!"
    exit 1
fi

# BASE CONFIG
BASE_DIR="/opt"
LOG_DIR="/var/log"
PORT_BASE_CWMP=7500
PORT_BASE_NBI=7600
PORT_BASE_FS=7700
PORT_BASE_UI=7800

### -------------------------------------------
###  Install Dependency sekali saja
### -------------------------------------------
echo "[1/5] Install dependencies..."
apt update -y
apt install -y curl wget git gnupg build-essential ufw

if ! command -v node >/dev/null; then
    curl -sL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
fi

if ! systemctl is-active --quiet mongod; then
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc \
        | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor

    echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] \
https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc)/mongodb-org/6.0 multiverse" \
        > /etc/apt/sources.list.d/mongodb-org-6.0.list

    apt update
    apt install -y mongodb-org
    systemctl enable --now mongod
fi

if ! command -v genieacs-cwmp >/dev/null; then
    npm install -g genieacs@1.2.13
fi

### -------------------------------------------
### START INSTALL MULTI INSTANCE
### -------------------------------------------
echo ""
echo "[2/5] Membuat $TOTAL instance GenieACS..."
echo ""

for i in $(seq 1 $TOTAL); do
    INSTANCE="genieacs$i"

    CWMP_PORT=$((PORT_BASE_CWMP + i))
    NBI_PORT=$((PORT_BASE_NBI + i))
    FS_PORT=$((PORT_BASE_FS + i))
    UI_PORT=$((PORT_BASE_UI + i))

    echo "→ Install $INSTANCE ..."

    mkdir -p $BASE_DIR/$INSTANCE/ext
    mkdir -p $LOG_DIR/$INSTANCE

    useradd --system --no-create-home --user-group $INSTANCE 2>/dev/null
    chown -R $INSTANCE:$INSTANCE $BASE_DIR/$INSTANCE $LOG_DIR/$INSTANCE

    # ENV FILE
    cat <<EOF > $BASE_DIR/$INSTANCE/$INSTANCE.env
GENIEACS_CWMP_HOST=0.0.0.0
GENIEACS_CWMP_PORT=$CWMP_PORT

GENIEACS_NBI_HOST=0.0.0.0
GENIEACS_NBI_PORT=$NBI_PORT

GENIEACS_FS_HOST=0.0.0.0
GENIEACS_FS_PORT=$FS_PORT

GENIEACS_UI_HOST=0.0.0.0
GENIEACS_UI_PORT=$UI_PORT

GENIEACS_UI_JWT_SECRET=$(openssl rand -hex 32)
GENIEACS_EXT_DIR=$BASE_DIR/$INSTANCE/ext
EOF

    chmod 600 $BASE_DIR/$INSTANCE/$INSTANCE.env
    chown $INSTANCE:$INSTANCE $BASE_DIR/$INSTANCE/$INSTANCE.env

    ### SYSTEMD SERVICES ###
    create_service() {
        SERVICE=$1
        EXEC=$2
        cat <<EOF > /etc/systemd/system/${INSTANCE}-${SERVICE}.service
[Unit]
Description=$INSTANCE $SERVICE
After=network.target

[Service]
User=$INSTANCE
EnvironmentFile=$BASE_DIR/$INSTANCE/$INSTANCE.env
ExecStart=/usr/bin/genieacs-$EXEC

[Install]
WantedBy=multi-user.target
EOF
    }

    create_service cwmp cwmp
    create_service nbi nbi
    create_service fs fs
    create_service ui ui

    systemctl daemon-reload
    systemctl enable --now ${INSTANCE}-cwmp ${INSTANCE}-nbi ${INSTANCE}-fs ${INSTANCE}-ui

    ### OPEN PORT ###
    ufw allow $CWMP_PORT/tcp
    ufw allow $NBI_PORT/tcp
    ufw allow $FS_PORT/tcp
    ufw allow $UI_PORT/tcp

    echo "✓ $INSTANCE selesai dibuat"
    echo ""
done

IP=$(hostname -I | awk '{print $1}')

echo ""
echo "=============================================================="
echo " 🎉 SELESAI! $TOTAL INSTANCE BERHASIL DIINSTALL"
echo "=============================================================="
for i in $(seq 1 $TOTAL); do
    INSTANCE="genieacs$i"
    UI_PORT=$((PORT_BASE_UI + i))
    CWMP_PORT=$((PORT_BASE_CWMP + i))
    FS_PORT=$((PORT_BASE_FS + i))

    echo "📦 $INSTANCE:"
    echo "   🌐 UI  : http://$IP:$UI_PORT"
    echo "   📡 CWMP: http://$IP:$CWMP_PORT"
    echo "   📁 FS  : http://$IP:$FS_PORT"
    echo "--------------------------------------------------------------"
done
echo "=============================================================="
echo "Mapping NAT VPS otomatis bisa dibuat berdasarkan angka instance"
echo "=============================================================="
