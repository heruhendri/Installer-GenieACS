#!/bin/bash
set -euo pipefail

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

# ---------------------------
# HITUNG INSTANCE EXISTING
# ---------------------------
COUNT=$(find /opt -maxdepth 1 -type d -name "genieacs-*" | wc -l || echo 0)
COUNT=${COUNT:-0}

UI_PORT=$((3000 + (COUNT * 100)))
CWMP_PORT=$((7547 + COUNT))
NBI_PORT=$((7557 + COUNT))
FS_PORT=$((7567 + COUNT))
MONGO_PORT=$((27017 + COUNT))

echo "== Instance baru: $INSTANCE =="
echo "Index: $COUNT"
echo "UI Port  : $UI_PORT"
echo "CWMP Port: $CWMP_PORT"
echo "NBI Port : $NBI_PORT"
echo "FS Port  : $FS_PORT"
echo "MongoDB  : $MONGO_PORT"
echo ""

# ---------------------------
# PRE INSTALL TOOLS
# ---------------------------
echo "==> Installing prerequisites..."
apt update
apt install -y curl wget git gnupg build-essential net-tools ufw jq screen nano iputils-ping openssl || true

# ---------------------------
# INSTALL NODE 18 (once)
# ---------------------------
if ! command -v node >/dev/null 2>&1; then
  echo "==> Installing Node.js 18..."
  curl -sL https://deb.nodesource.com/setup_18.x | bash -
  apt install -y nodejs
fi

# ---------------------------
# INSTALL MONGODB (once)
# ---------------------------
if ! dpkg -l | grep -q mongodb-org; then
  echo "==> Menginstall MongoDB..."
  curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor
  echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc)/mongodb-org/6.0 multiverse" \
    > /etc/apt/sources.list.d/mongodb-org-6.0.list
  apt update
  apt install -y mongodb-org
fi

# Disable default single mongod
if systemctl list-units --type=service | grep -q "mongod.service"; then
  systemctl stop mongod || true
  systemctl disable mongod || true
fi

# ---------------------------
# INSTALL GENIEACS (once)
# ---------------------------
if ! command -v genieacs-cwmp >/dev/null 2>&1; then
  echo "==> Installing GenieACS..."
  npm install -g genieacs@1.2.13
fi

# Ensure genieacs user exist
useradd --system --no-create-home --user-group genieacs || true

# ---------------------------
# PREPARE INSTANCE FOLDERS
# ---------------------------
echo "==> Menyiapkan directory instance..."
mkdir -p "$BASE_DIR/ext"
mkdir -p "$BASE_DIR/log"
chown -R genieacs:genieacs "$BASE_DIR"
chmod 755 "$BASE_DIR"

# ---------------------------
# MONGODB PER INSTANCE CONFIG
# ---------------------------
MONGO_DBPATH="/var/lib/mongo-$INSTANCE"
MONGO_LOGPATH="/var/log/mongodb/mongod-$INSTANCE.log"
MONGO_PIDFILE="/var/run/mongodb/mongod-$INSTANCE.pid"

mkdir -p "$MONGO_DBPATH"
mkdir -p /var/log/mongodb
chown -R mongodb:mongodb "$MONGO_DBPATH" /var/log/mongodb

cat <<EOF > "/etc/mongod-$INSTANCE.conf"
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

cat <<EOF > "/etc/systemd/system/mongodb-$INSTANCE.service"
[Unit]
Description=MongoDB instance for $INSTANCE
After=network.target

[Service]
User=mongodb
Group=mongodb
ExecStart=/usr/bin/mongod --config /etc/mongod-$INSTANCE.conf
PIDFile=$MONGO_PIDFILE
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "mongodb-$INSTANCE"

sleep 2

# ---------------------------
# GENIEACS ENV CONFIG
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

GENIEACS_MONGO_URL=$GENIEACS_MONGO_URL
GENIEACS_UI_JWT_SECRET=$(openssl rand -hex 32)
GENIEACS_EXT_DIR=$BASE_DIR/ext
EOF

chown genieacs:genieacs "$BASE_DIR/genieacs.env"
chmod 600 "$BASE_DIR/genieacs.env"

# ---------------------------
# GENIEACS SERVICES
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
# FIREWALL
# ---------------------------
ufw allow "$UI_PORT"/tcp
ufw allow "$CWMP_PORT"/tcp
ufw allow "$NBI_PORT"/tcp
ufw allow "$FS_PORT"/tcp

# ---------------------------
# DONE
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
echo "------------------------------------------------------------"
echo "Services:"
echo " - mongodb-$INSTANCE"
for SVC in "${SERVICES[@]}"; do
  echo " - genieacs-$INSTANCE-$SVC"
done
echo "============================================================"
echo ""
