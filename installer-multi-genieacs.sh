#!/bin/bash
set -euo pipefail

# multi-genieacs-fixed.sh
# Multi installer GenieACS - per-instance MongoDB (fixed)
# Jalankan sebagai root

echo "=== MULTI INSTALLER GENIEACS (Mongo per-instance) By Hendri - FIXED ==="
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
# count existing genieacs-* directories
COUNT=$(find /opt -maxdepth 1 -type d -name "genieacs-*" 2>/dev/null | wc -l || echo 0)
COUNT=${COUNT:-0}

# PORTS: UI pattern 3000,3100,3200... (increment +100 per instance)
UI_PORT=$((3000 + (COUNT * 100)))
# CWMP/NBI/FS: offset by (COUNT*10) to avoid direct collisions
CWMP_PORT=$((7547 + (COUNT * 10)))
NBI_PORT=$((7557 + (COUNT * 10)))
FS_PORT=$((7567 + (COUNT * 10)))
# MongoDB per-instance port: 27017,27117,27217,... (+100 per instance)
MONGO_PORT=$((27017 + (COUNT * 100)))

echo "== Instance baru: $INSTANCE =="
echo "Index (existing count): $COUNT"
echo "UI Port  : $UI_PORT"
echo "CWMP Port: $CWMP_PORT"
echo "NBI Port : $NBI_PORT"
echo "FS Port  : $FS_PORT"
echo "MongoDB  : $MONGO_PORT"
echo ""

read -p "Lanjutkan pembuatan instance $INSTANCE ? (y/n): " GO
[ "$GO" != "y" ] && { echo "Dibatalkan."; exit 0; }

# ---------------------------
# PRE INSTALL TOOLS
# ---------------------------
echo "==> Installing prerequisites..."
apt update
apt install -y curl wget git gnupg build-essential net-tools ufw jq screen nano iputils-ping openssl ca-certificates || true

# ---------------------------
# INSTALL NODE (20 recommended)
# ---------------------------
if ! command -v node >/dev/null 2>&1; then
  echo "==> Installing NodeJS 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
fi

# ---------------------------
# INSTALL MONGODB (if not present)
# ---------------------------
if ! command -v mongod >/dev/null 2>&1; then
  echo "==> Installing MongoDB 6.0 (community)..."
  # Import key and add repo (works on Ubuntu)
  curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg
  echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc)/mongodb-org/6.0 multiverse" \
    > /etc/apt/sources.list.d/mongodb-org-6.0.list
  apt update
  apt install -y mongodb-org
fi

# Stop default mongod if active (we create per-instance mongod)
if systemctl is-active --quiet mongod 2>/dev/null; then
  echo "Stopping default mongod (will keep per-instance mongod services)..."
  systemctl stop mongod || true
  systemctl disable mongod || true
fi

# ---------------------------
# INSTALL GENIEACS GLOBAL (if not present)
# ---------------------------
if ! command -v genieacs-cwmp >/dev/null 2>&1; then
  echo "==> Installing GenieACS (global npm package)..."
  npm install -g genieacs@1.2.13
fi

# Ensure genieacs system user exists
if ! id -u genieacs >/dev/null 2>&1; then
  useradd --system --no-create-home --user-group genieacs || true
fi

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
# mongodb package typically uses user 'mongodb'
chown -R mongodb:mongodb "$MONGO_DBPATH" /var/log/mongodb

cat <<EOF > "/etc/mongod-$INSTANCE.conf"
# mongod config for instance $INSTANCE
storage:
  dbPath: "$MONGO_DBPATH"
  journal:
    enabled: true
systemLog:
  destination: file
  path: "$MONGO_LOGPATH"
  logAppend: true
processManagement:
  pidFilePath: "$MONGO_PIDFILE"
net:
  port: ${MONGO_PORT}
  bindIp: 127.0.0.1
security:
  authorization: false
EOF

cat <<'UNIT' > "/etc/systemd/system/mongodb-'"$INSTANCE"'.service"
[Unit]
Description=MongoDB instance for %i
After=network.target

[Service]
Type=simple
User=mongodb
Group=mongodb
ExecStart=/usr/bin/mongod --config /etc/mongod-%i.conf
PIDFile=/var/run/mongodb/mongod-%i.pid
Restart=on-failure
LimitNOFILE=64000

[Install]
WantedBy=multi-user.target
UNIT

# replace %i token usage: we created file with instance name already by above name; easier to create direct service:
# but systemd unit above expects template; we'll create specific service file instead to avoid confusion
# Remove the template and create direct service file:
rm -f "/etc/systemd/system/mongodb-${INSTANCE}.service"
cat > "/etc/systemd/system/mongodb-${INSTANCE}.service" <<EOF
[Unit]
Description=MongoDB instance for ${INSTANCE}
After=network.target

[Service]
Type=simple
User=mongodb
Group=mongodb
ExecStart=/usr/bin/mongod --config /etc/mongod-${INSTANCE}.conf
PIDFile=/var/run/mongodb/mongod-${INSTANCE}.pid
Restart=on-failure
LimitNOFILE=64000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "mongodb-${INSTANCE}.service"

# wait a bit for mongod to start
sleep 2
if ! systemctl is-active --quiet "mongodb-${INSTANCE}.service"; then
  echo "Error: mongodb-${INSTANCE} gagal start. Periksa 'journalctl -u mongodb-${INSTANCE}'."
  exit 1
fi

# ---------------------------
# GENIEACS ENV CONFIG
# ---------------------------
GENIEACS_DBNAME="genieacs_${INSTANCE}"
# Use variable name GenieACS expects:
GENIEACS_MONGO_URL="mongodb://127.0.0.1:${MONGO_PORT}/${GENIEACS_DBNAME}"

cat > "$BASE_DIR/genieacs.env" <<EOF
GENIEACS_CWMP_HOST=0.0.0.0
GENIEACS_CWMP_PORT=${CWMP_PORT}

GENIEACS_NBI_HOST=0.0.0.0
GENIEACS_NBI_PORT=${NBI_PORT}

GENIEACS_FS_HOST=0.0.0.0
GENIEACS_FS_PORT=${FS_PORT}

GENIEACS_UI_HOST=0.0.0.0
GENIEACS_UI_PORT=${UI_PORT}

# GenieACS v1.2 expects GENIEACS_MONGODB_CONNECTION_URL (or GENIEACS_MONGO_URL for older)
GENIEACS_MONGODB_CONNECTION_URL=${GENIEACS_MONGO_URL}
GENIEACS_UI_JWT_SECRET=$(openssl rand -hex 32)
GENIEACS_EXT_DIR=${BASE_DIR}/ext
GENIEACS_DEBUG_FILE=${BASE_DIR}/log/debug.yaml
EOF

chown genieacs:genieacs "$BASE_DIR/genieacs.env"
chmod 600 "$BASE_DIR/genieacs.env"

# ---------------------------
# GENIEACS SERVICES (cwmp,nbi,fs,ui)
# ---------------------------
SERVICES=(cwmp nbi fs ui)

for SVC in "${SERVICES[@]}"; do
  cat > "/etc/systemd/system/genieacs-${INSTANCE}-${SVC}.service" <<EOF
[Unit]
Description=GenieACS ${SVC} (${INSTANCE})
After=network.target mongodb-${INSTANCE}.service redis-server.service

[Service]
EnvironmentFile=${BASE_DIR}/genieacs.env
User=genieacs
ExecStart=/usr/bin/genieacs-${SVC}
WorkingDirectory=${BASE_DIR}
Restart=always
LimitNOFILE=64000

[Install]
WantedBy=multi-user.target
EOF
done

systemctl daemon-reload

# start genieacs services
for SVC in "${SERVICES[@]}"; do
  systemctl enable --now "genieacs-${INSTANCE}-${SVC}.service"
done

# ---------------------------
# FIREWALL
# ---------------------------
ufw allow "${UI_PORT}/tcp"
ufw allow "${CWMP_PORT}/tcp"
ufw allow "${NBI_PORT}/tcp"
ufw allow "${FS_PORT}/tcp"
# DO NOT open mongo to public by default — uncomment only if you really need it:
# ufw allow "${MONGO_PORT}/tcp"

# ---------------------------
# DONE
# ---------------------------
IP=$(hostname -I | awk '{print $1}')

echo ""
echo "============================================================"
echo " 🎉 INSTANCE $INSTANCE BERHASIL DIBUAT"
echo "------------------------------------------------------------"
echo " 🌐 GUI URL    : http://${IP}:${UI_PORT}"
echo " 📡 CWMP URL   : http://${IP}:${CWMP_PORT}"
echo " 📁 FS URL     : http://${IP}:${FS_PORT}"
echo " 🗄️ MongoDB    : ${GENIEACS_MONGO_URL} (local only)"
echo " 🔑 Env file   : ${BASE_DIR}/genieacs.env"
echo "------------------------------------------------------------"
echo "Services:"
echo " - mongodb-${INSTANCE}.service"
for SVC in "${SERVICES[@]}"; do
  echo " - genieacs-${INSTANCE}-${SVC}.service"
done
echo "============================================================"
echo ""
