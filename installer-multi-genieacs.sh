#!/bin/bash
echo "============================================"
echo "   INSTALLER MULTI GENIEACS + MULTI GUI FIX"
echo "         CLEAN INSTALL - NO MORE ERROR"
echo "============================================"

INSTALLER_FILE="$(basename "$0")"

apt update -y
apt install -y curl wget git build-essential gnupg redis-server

curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# MongoDB fallback
apt install -y mongodb-org || apt install -y mongodb

systemctl enable redis-server
systemctl start redis-server
systemctl enable mongod || systemctl enable mongodb
systemctl start mongod || systemctl start mongodb

echo ""
read -p "Berapa instance GenieACS yang ingin dibuat? " INSTANCES

CWMP_PORT=7547
NBI_PORT=7557
FS_PORT=7567
GUI_PORT=3000
REDIS_PORT=6380

for i in $(seq 1 $INSTANCES)
do
    echo ""
    echo "============================================"
    echo " MEMBERSIHKAN INSTANSI LAMA #$i"
    echo "============================================"

    INSTALL_DIR="/opt/genieacs$i"

    # HAPUS FOLDER LAMA JIKA ADA
    rm -rf $INSTALL_DIR

    # HAPUS SERVICE LAMA JIKA ADA
    systemctl stop genieacs$i 2>/dev/null
    systemctl disable genieacs$i 2>/dev/null
    rm -f /etc/systemd/system/genieacs$i.service

    systemctl stop genieacs-gui$i 2>/dev/null
    systemctl disable genieacs-gui$i 2>/dev/null
    rm -f /etc/systemd/system/genieacs-gui$i.service

    systemctl stop redis-genieacs$i 2>/dev/null
    systemctl disable redis-genieacs$i 2>/dev/null
    rm -f /etc/systemd/system/redis-genieacs$i.service
    rm -f /etc/redis/redis-genieacs$i.conf

    systemctl daemon-reload

    echo ""
    echo "============================================"
    echo " MEMBUAT GENIEACS INSTANCE #$i"
    echo "============================================"

    DB_NAME="genieacs${i}db"
    SERVICE_NAME="genieacs$i"
    GUI_SERVICE="genieacs-gui$i"

    # CLONE FRESH GENIEACS
    git clone https://github.com/genieacs/genieacs $INSTALL_DIR

    cd $INSTALL_DIR
    npm install --legacy-peer-deps

    mkdir -p $INSTALL_DIR/config

    cat > $INSTALL_DIR/config/config.json <<EOF
{
  "cwmp": { "port": $CWMP_PORT },
  "nbi": { "port": $NBI_PORT },
  "fs": { "port": $FS_PORT },
  "db": { "mongoUrl": "mongodb://localhost:27017/${DB_NAME}" },
  "redis": { "port": $REDIS_PORT }
}
EOF

    # REDIS PER INSTANCE
    REDIS_CONF="/etc/redis/redis-${SERVICE_NAME}.conf"

    cp /etc/redis/redis.conf $REDIS_CONF
    sed -i "s/^port .*/port $REDIS_PORT/g" $REDIS_CONF
    sed -i "s|pidfile .*|pidfile /var/run/redis-${SERVICE_NAME}.pid|" $REDIS_CONF

    cat > /etc/systemd/system/redis-${SERVICE_NAME}.service <<EOF
[Unit]
Description=Redis Instance for ${SERVICE_NAME}
After=network.target

[Service]
ExecStart=/usr/bin/redis-server ${REDIS_CONF}
ExecStop=/usr/bin/redis-cli -p ${REDIS_PORT} shutdown
User=redis
Group=redis

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable redis-${SERVICE_NAME}
    systemctl start redis-${SERVICE_NAME}

    # BACKEND SERVICE
    cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=GenieACS Backend Instance ${i}
After=network.target redis-${SERVICE_NAME}.service mongod.service mongodb.service

[Service]
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/genieacs-cwmp --config config/config.json
ExecStartPost=/usr/bin/genieacs-nbi --config config/config.json
ExecStartPost=/usr/bin/genieacs-fs --config config/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable ${SERVICE_NAME}
    systemctl start ${SERVICE_NAME}

    # GUI
    echo "Membuat GUI Baru..."
    rm -rf $INSTALL_DIR/gui

    git clone https://github.com/genieacs/genieacs-gui $INSTALL_DIR/gui
    cd $INSTALL_DIR/gui
    npm install --legacy-peer-deps

    rm -rf build node_modules/.cache
    npm run build

    cat > /etc/systemd/system/${GUI_SERVICE}.service <<EOF
[Unit]
Description=GenieACS GUI Instance ${i}
After=network.target

[Service]
User=root
WorkingDirectory=${INSTALL_DIR}/gui
ExecStart=/usr/bin/node server.js --port ${GUI_PORT}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable ${GUI_SERVICE}
    systemctl start ${GUI_SERVICE}

    echo ""
    echo "===== INSTANCE #$i BERHASIL DIBUAT ====="
    echo "GUI     : http://IP-VPS:$GUI_PORT"
    echo "CWMP    : $CWMP_PORT"
    echo "NBI     : $NBI_PORT"
    echo "FS      : $FS_PORT"
    echo "Redis   : $REDIS_PORT"
    echo "DB      : $DB_NAME"
    echo "========================================="

    # Increment Port For Next Instance
    CWMP_PORT=$((CWMP_PORT+100))
    NBI_PORT=$((NBI_PORT+100))
    FS_PORT=$((FS_PORT+100))
    GUI_PORT=$((GUI_PORT+100))
    REDIS_PORT=$((REDIS_PORT+1))

done

echo ""
echo "============================================"
echo "   INSTALASI MULTI GENIEACS + MULTI GUI DONE"
echo "============================================"

rm -f "$INSTALLER_FILE"
echo "Installer dihapus otomatis!"
