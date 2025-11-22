#!/bin/bash
# Installer GenieACS untuk Ubuntu 22.04 / NATVPS

echo "=== Update sistem ==="
apt update -y && apt upgrade -y

echo "=== Install dependency dasar ==="
apt install -y curl gnupg build-essential redis-server

echo "=== Install Node.js 20 ==="
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

echo "=== Install MongoDB Community Edition (versi Ubuntu default) ==="
apt install -y mongodb

echo "=== Enable & Start MongoDB ==="
systemctl enable mongodb
systemctl start mongodb

echo "=== Clone GenieACS ==="
mkdir -p /opt/genieacs
cd /opt/genieacs
wget https://github.com/genieacs/genieacs/archive/refs/tags/v1.2.15.tar.gz
tar -xzvf v1.2.15.tar.gz --strip 1

echo "=== Install dependency GenieACS ==="
npm install --production

echo "=== Membuat user genieacs ==="
useradd -r -s /bin/false genieacs || true

echo "=== Membuat direktori log ==="
mkdir -p /var/log/genieacs
chown -R genieacs:genieacs /var/log/genieacs

echo "=== Membuat Environment Config ==="
cat >/etc/genieacs.env <<EOF
GENIEACS_CWMP_PORT=7547
GENIEACS_NBI_PORT=7557
GENIEACS_FS_PORT=7567
GENIEACS_UI_PORT=10000
GENIEACS_UI_JWT_SECRET=$(openssl rand -hex 32)
GENIEACS_EXT_DIR=/opt/genieacs/ext
GENIEACS_DEBUG_FILE=/var/log/genieacs/genieacs-debug.yaml
EOF

echo "=== Membuat service systemd ==="

# CWMP
cat >/etc/systemd/system/genieacs-cwmp.service <<EOF
[Unit]
Description=GenieACS CWMP
After=network.target mongodb.service redis-server.service

[Service]
EnvironmentFile=/etc/genieacs.env
User=genieacs
ExecStart=/usr/bin/node /opt/genieacs/bin/genieacs-cwmp
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# NBI
cat >/etc/systemd/system/genieacs-nbi.service <<EOF
[Unit]
Description=GenieACS NBI
After=network.target mongodb.service redis-server.service

[Service]
EnvironmentFile=/etc/genieacs.env
User=genieacs
ExecStart=/usr/bin/node /opt/genieacs/bin/genieacs-nbi
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# FS
cat >/etc/systemd/system/genieacs-fs.service <<EOF
[Unit]
Description=GenieACS FS
After=network.target mongodb.service redis-server.service

[Service]
EnvironmentFile=/etc/genieacs.env
User=genieacs
ExecStart=/usr/bin/node /opt/genieacs/bin/genieacs-fs
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# UI
cat >/etc/systemd/system/genieacs-ui.service <<EOF
[Unit]
Description=GenieACS UI
After=network.target

[Service]
EnvironmentFile=/etc/genieacs.env
User=genieacs
ExecStart=/usr/bin/node /opt/genieacs/bin/genieacs-ui
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "=== Reload service & start ==="
systemctl daemon-reload
systemctl enable genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui
systemctl start genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui

echo "=== Instalasi selesai ==="
echo "Akses GenieACS UI melalui http://IP-VPS:10000"
