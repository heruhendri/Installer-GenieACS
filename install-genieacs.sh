#!/bin/bash

echo "=== INSTALLER GENIEACS FOR NATVPS (TR-069) By Hendri ==="
sleep 1

# ---------------------------------------------------------------------
# UPDATE SYSTEM
# ---------------------------------------------------------------------
apt update && apt upgrade -y

# ---------------------------------------------------------------------
# INSTALL DEPENDENCIES
# ---------------------------------------------------------------------
apt install -y curl wget git gnupg build-essential

# ---------------------------------------------------------------------
# INSTALL NODE.JS 18 (Stable for GenieACS)
# ---------------------------------------------------------------------
curl -sL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

# ---------------------------------------------------------------------
# INSTALL MONGODB 5.0 (Compatibility for Ubuntu 20–24)
# ---------------------------------------------------------------------
wget -qO - https://www.mongodb.org/static/pgp/server-5.0.asc | apt-key add -
echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/5.0 multiverse" \
    | tee /etc/apt/sources.list.d/mongodb-org-5.0.list

apt update
apt install -y mongodb-org

systemctl enable --now mongod

# ---------------------------------------------------------------------
# INSTALL GENIEACS
# ---------------------------------------------------------------------
npm install -g genieacs@1.2.13

useradd --system --no-create-home --user-group genieacs || true
mkdir -p /opt/genieacs/ext
mkdir -p /var/log/genieacs
chown -R genieacs:genieacs /opt/genieacs /var/log/genieacs
chmod 755 /opt/genieacs

# ---------------------------------------------------------------------
# CREATE ENV CONFIG
# ---------------------------------------------------------------------
cat <<EOF > /opt/genieacs/genieacs.env
GENIEACS_CWMP_HOST=0.0.0.0
GENIEACS_CWMP_PORT=7547

GENIEACS_NBI_HOST=0.0.0.0
GENIEACS_NBI_PORT=7557

GENIEACS_FS_HOST=0.0.0.0
GENIEACS_FS_PORT=7567

GENIEACS_UI_HOST=0.0.0.0
GENIEACS_UI_PORT=10000

GENIEACS_UI_JWT_SECRET=$(openssl rand -hex 32)
GENIEACS_EXT_DIR=/opt/genieacs/ext
EOF

chown genieacs:genieacs /opt/genieacs/genieacs.env
chmod 600 /opt/genieacs/genieacs.env

# ---------------------------------------------------------------------
# CREATE SYSTEMD SERVICE FILES
# ---------------------------------------------------------------------
cat <<EOF > /etc/systemd/system/genieacs-cwmp.service
[Unit]
Description=GenieACS CWMP
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs.env
ExecStart=/usr/bin/genieacs-cwmp

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/genieacs-nbi.service
[Unit]
Description=GenieACS NBI
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs.env
ExecStart=/usr/bin/genieacs-nbi

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/genieacs-fs.service
[Unit]
Description=GenieACS File Server
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs.env
ExecStart=/usr/bin/genieacs-fs

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/genieacs-ui.service
[Unit]
Description=GenieACS User Interface
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs.env
ExecStart=/usr/bin/genieacs-ui

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now genieacs-cwmp genieacs-nbi genieacs-fs genieacs-ui

# ---------------------------------------------------------------------
# NAT VPS FRIENDLY FIREWALL OPEN PORTS
# ---------------------------------------------------------------------
ufw allow 7547/tcp
ufw allow 7557/tcp
ufw allow 7567/tcp
ufw allow 10000/tcp

# ---------------------------------------------------------------------
# INSTALL COMPLETE
# ---------------------------------------------------------------------
IP=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================================"
echo " 🎉 INSTALL GENIEACS BERHASIL"
echo "------------------------------------------------------------"
echo " 🌐 GUI URL  : http://$IP:10000"
echo " 📡 CWMP URL : http://$IP:7547"
echo " 📁 FS URL   : http://$IP:7567"
echo " 🔑 JWT key  : disimpan di /opt/genieacs/genieacs.env"
echo "------------------------------------------------------------"
echo " Jalankan di NAT VPS:"
echo "  - Forward port 10000 → 10000"
echo "  - Forward port 7547 → 7547"
echo "============================================================"
