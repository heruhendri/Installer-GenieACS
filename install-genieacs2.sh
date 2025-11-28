#!/bin/bash
echo "============================================"
echo "      INSTALLER MULTI GENIEACS + MULTI GUI"
echo "            NATVPS Ubuntu 20/22/24"
echo "       AUTO DELETE INSTALLER AFTER FINISH"
echo "============================================"
sleep 2

# SIMPAN NAMA FILE INSTALLER
INSTALLER_FILE="$(basename "$0")"

# ---------------------------------------------------------------------
# 1. UPDATE
# ---------------------------------------------------------------------
apt update -y
apt install -y curl wget git build-essential gnupg

# ---------------------------------------------------------------------
# 2. INSTALL NODEJS 18 (Stable)
# ---------------------------------------------------------------------
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# ---------------------------------------------------------------------
# 3. INSTALL MONGODB & REDIS
# ---------------------------------------------------------------------
apt install -y mongodb redis-server
systemctl enable mongodb
systemctl start mongodb

# ---------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------
echo ""
echo "============================================"
echo "Berapa banyak instance GenieACS yang ingin dibuat?"
echo "Contoh: 2 atau 3 atau 5"
echo "============================================"
read -p "Jumlah instance: " INSTANCES

# PORT AWAL
CWMP_PORT=7547
NBI_PORT=7557
FS_PORT=7567
GUI_PORT=3000
REDIS_PORT=6379

for i in $(seq 1 $INSTANCES)
do
    echo ""
    echo "============================================"
    echo "   MEMBUAT GENIEACS INSTANCE #$i"
    echo "============================================"

    INSTALL_DIR="/opt/genieacs$i"
    DB_NAME="genieacs${i}db"
    SERVICE_NAME="genieacs$i"
    GUI_SERVICE="genieacs-gui$i"

    echo "=> Clone GenieACS..."
    git clone https://github.com/genieacs/genieacs $INSTALL_DIR
    cd $INSTALL_DIR
    npm install

    mkdir -p $INSTALL_DIR/config

    echo "=> Membuat config backend..."
    cat > $INSTALL_DIR/config/config.json <<EOF
{
  "cwmp": { "port": $CWMP_PORT },
  "nbi": { "port": $NBI_PORT },
  "fs": { "port": $FS_PORT },
  "db": { "mongoUrl": "mongodb://localhost:27017/${DB_NAME}" },
  "redis": { "port": $REDIS_PORT }
}
EOF

    # ---------------------------------------------------------------------
    # REDIS INSTANCE
    # ---------------------------------------------------------------------
    echo "=> Membuat Redis instance port $REDIS_PORT"
    REDIS_CONF="/etc/redis/redis-${SERVICE_NAME}.conf"
    cp /etc/redis/redis.conf $REDIS_CONF
    sed -i "s/^port .*/port $REDIS_PORT/" $REDIS_CONF
    sed -i "s|pidfile .*|pidfile /var/run/redis-${SERVICE_NAME}.pid|" $REDIS_CONF

    cat > /etc/systemd/system/redis-${SERVICE_NAME}.service <<EOF
[Unit]
Description=Redis Instance for ${SERVICE_NAME}
After=network.target

[Service]
ExecStart=/usr/bin/redis-server $REDIS_CONF
ExecStop=/usr/bin/redis-cli -p ${REDIS_PORT} shutdown
User=redis
Group=redis

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable redis-${SERVICE_NAME}
    systemctl start redis-${SERVICE_NAME}

    # ---------------------------------------------------------------------
    # BACKEND GENIEACS SERVICE
    # ---------------------------------------------------------------------
    echo "=> Membuat systemd service backend..."
    cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=GenieACS Instance ${i}
After=network.target redis-${SERVICE_NAME}.service mongodb.service

[Service]
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/node dist/bin/genieacs-cwmp --config config/config.json
ExecStartPost=/usr/bin/node dist/bin/genieacs-nbi --config config/config.json
ExecStartPost=/usr/bin/node dist/bin/genieacs-fs --config config/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
    systemctl start ${SERVICE_NAME}

    # ---------------------------------------------------------------------
    # GUI FRONTEND PER INSTANCE
    # ---------------------------------------------------------------------
    echo "=> Install GUI frontend instance #$i..."

    cd ${INSTALL_DIR}
    git clone https://github.com/genieacs/genieacs-gui gui
    cd gui
    npm install
    npm run build

    echo "=> Membuat GUI systemd service..."
    cat > /etc/systemd/system/${GUI_SERVICE}.service <<EOF
[Unit]
Description=GenieACS GUI Instance ${i}
After=network.target ${SERVICE_NAME}.service

[Service]
User=root
WorkingDirectory=${INSTALL_DIR}/gui
ExecStart=/usr/bin/node server.js --port ${GUI_PORT}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${GUI_SERVICE}
    systemctl start ${GUI_SERVICE}

    echo ""
    echo "=== Instance #$i selesai dibuat ==="
    echo "GUI     : http://IP-VPS:$GUI_PORT"
    echo "CWMP    : $CWMP_PORT"
    echo "NBI     : $NBI_PORT"
    echo "FS      : $FS_PORT"
    echo "Redis   : $REDIS_PORT"
    echo "Database: $DB_NAME"
    echo ""

    # NEXT PORT
    CWMP_PORT=$((CWMP_PORT+100))
    NBI_PORT=$((NBI_PORT+100))
    FS_PORT=$((FS_PORT+100))
    GUI_PORT=$((GUI_PORT+100))
    REDIS_PORT=$((REDIS_PORT+1))

done


echo ""
echo "============================================"
echo "   INSTALLASI MULTI GENIEACS + MULTI GUI SELESAI!"
echo "============================================"
echo "Menghapus file installer..."
rm -f "$INSTALLER_FILE"
echo "Installer berhasil dihapus."
echo "============================================"
