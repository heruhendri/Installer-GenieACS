#!/bin/bash
echo "============================================"
echo "      INSTALLER MULTI GENIEACS (TR-069)"
echo "            NATVPS Ubuntu 20/22/24"
echo "        By Hendri - Auto Multi Instance"
echo "============================================"
sleep 2

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
systemctl enable redis-server
systemctl start mongodb
systemctl start redis-server

echo ""
echo "============================================"
echo "Masukkan jumlah instance GenieACS yang ingin diinstall:"
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

    echo "=> Clone GenieACS..."
    git clone https://github.com/genieacs/genieacs $INSTALL_DIR
    cd $INSTALL_DIR
    npm install

    mkdir -p $INSTALL_DIR/config

    echo "=> Membuat config..."
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
    # BUAT REDIS TAMBAHAN
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
    # SYSTEMD SERVICE GENIEACS
    # ---------------------------------------------------------------------
    echo "=> Membuat systemd service..."
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

    echo ""
    echo "=== Instance #$i berhasil dibuat ==="
    echo "CWMP: $CWMP_PORT"
    echo "NBI : $NBI_PORT"
    echo "FS  : $FS_PORT"
    echo "GUI : $GUI_PORT"
    echo "Redis: $REDIS_PORT"
    echo "DB: mongodb://localhost:27017/$DB_NAME"
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
echo "   INSTALLASI MULTI GENIEACS SELESAI!"
echo "============================================"
echo "Setiap instance sudah memiliki:"
echo "✔ Port berbeda"
echo "✔ Redis sendiri"
echo "✔ Database MongoDB sendiri"
echo "✔ Systemd service sendiri"
echo "✔ Lokasi: /opt/genieacsX"
echo ""
echo "Untuk cek status:"
echo "  systemctl status genieacs1"
echo "  systemctl status genieacs2"
echo ""
echo "Untuk restart:"
echo "  systemctl restart genieacs1"
echo ""
