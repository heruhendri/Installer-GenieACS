#!/bin/bash
clear
echo "============================================"
echo " GENIEACS MULTI INSTANCE INSTALLER FINAL"
echo "============================================"
echo ""

read -p "Masukkan nama instance (tanpa spasi, contoh: isp1): " INSTANCE

if [ -z "$INSTANCE" ]; then
    echo "ERROR: Nama instance tidak boleh kosong!"
    exit 1
fi

BASE_PORT=3000

# Hitung port berdasarkan jumlah instance yang ada
INDEX=$(ls /opt | grep "genieacs-" | wc -l)
UI_PORT=$((BASE_PORT + (INDEX * 100)))
CWMP_PORT=$((7547 + INDEX))
NBI_PORT=$((7557 + INDEX))
FS_PORT=$((7567 + INDEX))

DB_NAME="genieacs_${INSTANCE}"
INSTALL_DIR="/opt/genieacs-${INSTANCE}"

echo ""
echo "Instance Details:"
echo "---------------------------------------------"
echo " Instance Name : $INSTANCE"
echo " UI Port       : $UI_PORT"
echo " CWMP Port     : $CWMP_PORT"
echo " NBI Port      : $NBI_PORT"
echo " FS Port       : $FS_PORT"
echo " Database Name : $DB_NAME"
echo " Install Path  : $INSTALL_DIR"
echo "---------------------------------------------"
echo ""
read -p "Lanjutkan instalasi? (y/n): " OK
if [ "$OK" != "y" ]; then
    exit 0
fi

echo ""
echo "[1/7] Update system & install dependencies"
apt update -y
apt install -y git curl build-essential redis-server mongodb nodejs npm

echo ""
echo "[2/7] Clone GenieACS"
git clone https://github.com/genieacs/genieacs.git $INSTALL_DIR

echo ""
echo "[3/7] Install dependencies"
cd $INSTALL_DIR
npm install

echo ""
echo "[4/7] Membuat database MongoDB instance..."
mongo <<EOF
use $DB_NAME
db.createCollection("devices")
EOF

echo "MongoDB database '$DB_NAME' berhasil dibuat!"

echo ""
echo "[5/7] Generate config file"
mkdir -p /etc/genieacs-$INSTANCE

cat <<EOF >/etc/genieacs-$INSTANCE/config.json
{
  "CWMP_PORT": $CWMP_PORT,
  "NBI_PORT": $NBI_PORT,
  "FS_PORT": $FS_PORT,
  "UI_PORT": $UI_PORT,
  "MONGODB_CONNECTION_URL": "mongodb://localhost:27017/$DB_NAME"
}
EOF

echo "Config created: /etc/genieacs-$INSTANCE/config.json"

echo ""
echo "[6/7] Membuat systemd service"

# CWMP
cat <<EOF >/etc/systemd/system/genieacs-cwmp-$INSTANCE.service
[Unit]
Description=GenieACS CWMP ($INSTANCE)
After=network.target mongodb.service redis.service

[Service]
Environment=GENIEACS_CONFIG=/etc/genieacs-$INSTANCE/config.json
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node dist/bin/genieacs-cwmp.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# NBI
cat <<EOF >/etc/systemd/system/genieacs-nbi-$INSTANCE.service
[Unit]
Description=GenieACS NBI ($INSTANCE)
After=network.target mongodb.service redis.service

[Service]
Environment=GENIEACS_CONFIG=/etc/genieacs-$INSTANCE/config.json
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node dist/bin/genieacs-nbi.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# FS
cat <<EOF >/etc/systemd/system/genieacs-fs-$INSTANCE.service
[Unit]
Description=GenieACS FS ($INSTANCE)
After=network.target mongodb.service redis.service

[Service]
Environment=GENIEACS_CONFIG=/etc/genieacs-$INSTANCE/config.json
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node dist/bin/genieacs-fs.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# UI
cat <<EOF >/etc/systemd/system/genieacs-ui-$INSTANCE.service
[Unit]
Description=GenieACS UI ($INSTANCE)
After=network.target mongodb.service redis.service

[Service]
Environment=GENIEACS_CONFIG=/etc/genieacs-$INSTANCE/config.json
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node dist/bin/genieacs-ui.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo ""
echo "[7/7] Enable & start all services"
systemctl daemon-reload
systemctl enable genieacs-cwmp-$INSTANCE
systemctl enable genieacs-nbi-$INSTANCE
systemctl enable genieacs-fs-$INSTANCE
systemctl enable genieacs-ui-$INSTANCE

systemctl start genieacs-cwmp-$INSTANCE
systemctl start genieacs-nbi-$INSTANCE
systemctl start genieacs-fs-$INSTANCE
systemctl start genieacs-ui-$INSTANCE

echo ""
echo "============================================"
echo " INSTALLASI SELESAI!"
echo "============================================"
echo "Instance Name : $INSTANCE"
echo ""
echo " UI   : http://IP-SERVER:$UI_PORT"
echo " CWMP : $CWMP_PORT"
echo " NBI  : $NBI_PORT"
echo " FS   : $FS_PORT"
echo " DB   : $DB_NAME (MongoDB)"
echo ""
echo "Cek status service:"
echo "  systemctl status genieacs-ui-$INSTANCE"
echo ""
echo "============================================"
