#!/bin/bash
set -euo pipefail

echo "=== Multi-Instance Installer: GenieACS + MongoDB ==="
read -p "Masukkan nama instance (contoh: riski): " INST

echo ""
echo "===> 1. Install MongoDB-org (jika belum ada)"
if ! command -v mongod &>/dev/null; then
  wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -
  echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc)/mongodb-org/6.0 multiverse" \
   | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
  sudo apt update
  sudo apt install -y mongodb-org
fi

echo ""
echo "===> 2. Membuat MongoDB Instance: $INST"

DBPORT=$(shuf -i 27020-27999 -n 1)
mkdir -p /var/lib/mongodb-$INST
mkdir -p /var/log/mongodb-$INST
chown -R mongodb:mongodb /var/lib/mongodb-$INST /var/log/mongodb-$INST

cat <<EOF >/etc/mongod-$INST.conf
systemLog:
  destination: file
  path: /var/log/mongodb-$INST/mongod.log
  logAppend: true
storage:
  dbPath: /var/lib/mongodb-$INST
  journal:
    enabled: true
processManagement:
  fork: false
net:
  port: $DBPORT
  bindIp: 0.0.0.0
EOF

cat <<EOF >/etc/systemd/system/mongod-$INST.service
[Unit]
Description=MongoDB Server for GenieACS $INST
After=network.target

[Service]
User=mongodb
Group=mongodb
ExecStart=/usr/bin/mongod --config /etc/mongod-$INST.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mongod-$INST
systemctl start mongod-$INST


echo ""
echo "===> 3. Install NodeJS + PM2 (jika belum ada)"
if ! command -v node &>/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt install -y nodejs
fi

if ! command -v pm2 &>/dev/null; then
  npm install pm2 -g
fi

echo ""
echo "===> 4. Membuat GenieACS Instance: $INST"

mkdir -p /opt/genieacs-$INST
cd /opt/genieacs-$INST

npm install genieacs --unsafe-perm

UI_PORT=$(shuf -i 3000-3999 -n 1)
NBI_PORT=$(shuf -i 7000-7999 -n 1)
CWMP_PORT=$(shuf -i 7547-7999 -n 1)

cat <<EOF >config.json
{
  "GENIEACS_EXT_DIR": "/opt/genieacs-$INST/ext",
  "MONGODB_URL": "mongodb://localhost:$DBPORT/genieacs-$INST",
  "CWMP_PORT": $CWMP_PORT,
  "NBI_PORT": $NBI_PORT,
  "UI_PORT": $UI_PORT
}
EOF

mkdir -p ext

echo ""
echo "===> 5. Membuat service PM2"
pm2 start node_modules/genieacs/dist/bin/genieacs-cwmp --name genieacs-$INST-cwmp -- \
  --config config.json
pm2 start node_modules/genieacs/dist/bin/genieacs-nbi --name genieacs-$INST-nbi -- \
  --config config.json
pm2 start node_modules/genieacs/dist/bin/genieacs-ui --name genieacs-$INST-ui -- \
  --config config.json

pm2 save
pm2 startup systemd -u root --hp /root

echo ""
echo "=== INSTALASI SELESAI ==="
echo "Instance: $INST"
echo "MongoDB Port  : $DBPORT"
echo "GenieACS UI   : http://IP-SERVER:$UI_PORT"
echo "GenieACS NBI  : http://IP-SERVER:$NBI_PORT"
echo "GenieACS CWMP : http://IP-SERVER:$CWMP_PORT"
echo ""
echo "File config GenieACS: /opt/genieacs-$INST/config.json"
echo "Service MongoDB    : mongod-$INST"
echo ""
echo "=== SEMUA BERHASIL TANPA ERROR ==="
