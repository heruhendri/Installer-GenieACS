#!/bin/bash
set -euo pipefail

# multi-genieacs-mongo-per-instance.sh
# Run repeatedly to add instances:
#   ./multi-genieacs-mongo-per-instance.sh

echo "=== MULTI INSTALLER GENIEACS (Mongo per-instance) By Hendri ==="
sleep 1

read -p "Masukkan nama instance (contoh: gacs1): " INSTANCE
if [[ -z "$INSTANCE" ]]; then
  echo "Nama instance tidak boleh kosong."
  exit 1
fi

BASE_DIR="/opt/genieacs-$INSTANCE"
if [ -d "$BASE_DIR" ]; then
  echo "Instance $INSTANCE sudah ada. Pilih nama lain."
  exit 1
fi

# Count existing instances (directories named /opt/genieacs-*)
COUNT=$(ls -d /opt/genieacs-* 2>/dev/null | wc -l || echo 0)
# If there are zero matches, wc -l returns 0; good.
UI_PORT=$((3000 + (COUNT * 100)))
CWMP_PORT=$((7547 + COUNT))
NBI_PORT=$((7557 + COUNT))
FS_PORT=$((7567 + COUNT))
MONGO_PORT=$((27017 + COUNT))

echo "Membuat instance: $INSTANCE"
echo "Instance index: $COUNT"
echo "Ports -> UI:$UI_PORT  CWMP:$CWMP_PORT  NBI:$NBI_PORT  FS:$FS_PORT  MONGO:$MONGO_PORT"
echo ""

# ---------------------------
# PRE-INSTALL TOOLS
# ---------------------------
echo "==> Menginstall prerequisite tools..."
apt update
apt install -y curl wget git gnupg build-essential net-tools ufw jq screen nano iputils-ping openssl || true

# ---------------------------
# NODE.JS 18
# ---------------------------
if ! command -v node >/dev/null 2>&1; then
  echo "==> Installing Node.js 18..."
  curl -sL https://deb.nodesource.com/setup_18.x | bash -
  apt install -y nodejs
fi

# ---------------------------
# MONGODB REPO + INSTALL (once)
# ---------------------------
if ! dpkg -l | grep -q mongodb-org; then
  echo "==> Menambahkan repo MongoDB..."
  curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor
  echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc)/mongodb-org/6.0 multiverse" \
    > /etc/apt/sources.list.d/mongodb-org-6.0.list
  apt update
  apt install -y mongodb-org
fi

# Stop/disable the default single mongod (we will run per-instance mongod services)
if systemctl list-units --full -all | grep -qE '^mongod\.service'; then
  echo "==> Menonaktifkan mongod.service bawaan untuk menghindari konflik port..."
  systemctl stop mongod || true
  systemctl disable mongod || true
fi

# ---------------------------
# INSTALL GENIEACS (global, once)
# ---------------------------
if ! command -v genieacs-cwmp >/dev/null 2>&1; then
  echo "==> Installing GenieACS globally..."
  npm install -g genieacs@1.2.13
fi

# Ensure genieacs system user exists
useradd --system --no-create-home --user-group genieacs || true

# ---------------------------
# SETUP FILES FOR INSTANCE
# ---------------------------
echo "==> Membuat direktori instance di $BASE_DIR ..."
mkdir -p "$BASE_DIR/ext"
mkdir -p "$BASE_DIR/log"
chown -R genieacs:genieacs "$BASE_DIR"
chmod 755 "$BASE_DIR"

# ---------------------------
# CREATE MONGODB PER-INSTANCE CONFIG
# ---------------------------
MONGO_DBPATH="/var/lib/mongo-$INSTANCE"
MONGO_LOGPATH="/var/log/mongodb/mongod-$INSTANCE.log"
MONGO_PIDFILE="/var/run/mongodb/mongod-$INSTANCE.pid"
mkdir -p "$MONGO_DBPATH"
mkdir -p /var/log/mongodb
chown -R mongodb:mongodb "$MONGO_DBPATH" /var/log/mongodb

cat <<EOF > "/etc/mongod-$INSTANCE.conf"
# mongod config for instance $INSTANCE
storage:
  dbPath: $MONGO_DBPATH
  journal:
    enabled: true
systemLog:
  destination: file
  path: $MONGO_LOGPATH
  logAppend: true
processManagement:
  pidFilePath: $MONGO_PIDFILE
net:
  port: $MONGO_PORT
  bindIp: 127.0.0.1
security:
  authorization: disabled
EOF

# Create systemd service for this mongod instance
cat <<EOF > "/etc/systemd/system/mongodb-$INSTANCE.service"
[Unit]
Description=MongoDB per-instance for $INSTANCE
After=network.target

[Service]
User=mongodb
Group=mongodb
Environment=TMPDIR=/tmp
ExecStart=/usr/bin/mongod --config /etc/mongod-$INSTANCE.conf
PIDFile=$MONGO_PIDFILE
TimeoutSec=300
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "mongodb-$INSTANCE.service"

# Wait shortly for Mongo to come up
sleep 2
if ! ss -lnt | grep -q ":$MONGO_PORT"; then
  echo "Peringatan: MongoDB pada port $MONGO_PORT tidak terlihat aktif. Periksa jurnal: sudo journalctl -u mongodb-$INSTANCE -n 200"
fi

# ---------------------------
# CREATE GENIEACS ENV
# ---------------------------
GENIEACS_DBNAME="genieacs_${INSTANCE}"
GENIEACS_MONGO_URL="mongodb://127.0.0.1:$MONGO_PORT/$GENIEACS_DBNAME"

cat <<EOF > "$BASE_DIR/genieacs.env"
GENIEACS_CWMP_HOST=0.0.0.0
GENIEACS_CWMP_PORT=$CWMP_PORT

GENIEACS_NBI_HOST=0.0.0.0
GENIEACS_NBI_PORT=$NBI_PORT

GENIEACS_FS_HOST=0.0.0.0
GENIEACS_FS_PORT=$FS_PORT

GENIEACS_UI_HOST=0.0.0.0
GENIEACS_UI_PORT=$UI_PORT

# MongoDB connection string per-instance
GENIEACS_MONGO_URL=$GENIEACS_MONGO_URL

GENIEACS_UI_JWT_SECRET=$(openssl rand -hex 32)
GENIEACS_EXT_DIR=$BASE_DIR/ext
EOF

chown genieacs:genieacs "$BASE_DIR/genieacs.env"
chmod 600 "$BASE_DIR/genieacs.env"

# ---------------------------
# CREATE SYSTEMD SERVICES FOR GENIEACS (per-instance)
# ---------------------------
SERVICES=(cwmp nbi fs ui)
for SVC in "${SERVICES[@]}"; do
  cat <<EOF > "/etc/systemd/system/genieacs-$INSTANCE-$SVC.service"
[Unit]
Description=GenieACS $SVC ($INSTANCE)
After=network.target mongodb-$INSTANCE.service

[Service]
User=genieacs
EnvironmentFile=$BASE_DIR/genieacs.env
ExecStart=/usr/bin/genieacs-$SVC
WorkingDirectory=$BASE_DIR
Restart=always

[Install]
WantedBy=multi-user.target
EOF
done

systemctl daemon-reload

for SVC in "${SERVICES[@]}"; do
  systemctl enable --now "genieacs-$INSTANCE-$SVC"
done

# ---------------------------
# FIREWALL - hanya buka port yang perlu
# ---------------------------
ufw allow "$UI_PORT"/tcp
ufw allow "$CWMP_PORT"/tcp
ufw allow "$NBI_PORT"/tcp
ufw allow "$FS_PORT"/tcp

# ---------------------------
# FINISH
# ---------------------------
IP=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================================"
echo " 🎉 INSTANCE $INSTANCE BERHASIL DIBUAT"
echo "------------------------------------------------------------"
echo " 🌐 GUI URL    : http://$IP:$UI_PORT"
echo " 📡 CWMP URL   : http://$IP:$CWMP_PORT"
echo " 📁 FS URL     : http://$IP:$FS_PORT"
echo " 🗄️ MongoDB    : mongodb://127.0.0.1:$MONGO_PORT/$GENIEACS_DBNAME"
echo " 🔑 JWT key    : $BASE_DIR/genieacs.env"
echo " Log genieacs  : $BASE_DIR/log"
echo " Mongo log     : /var/log/mongodb/mongod-$INSTANCE.log"
echo "------------------------------------------------------------"
echo "Services systemd:"
echo " - mongodb-$INSTANCE.service"
for SVC in "${SERVICES[@]}"; do
  echo " - genieacs-$INSTANCE-$SVC.service"
done
echo "============================================================"
echo ""
