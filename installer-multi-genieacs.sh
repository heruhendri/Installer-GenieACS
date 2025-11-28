#!/bin/bash
set -euo pipefail

# multi-genieacs-mongo-per-instance.sh
# Jalankan berulang untuk menambah instansi baru.
# Contoh: ./multi-genieacs-mongo-per-instance.sh

echo "=== Multi-GenieACS Installer (each instance has own MongoDB) ==="
echo ""

read -p "Masukkan nama instansi (contoh: gacs1): " INST
if [ -z "$INST" ]; then
  echo "Nama instansi tidak boleh kosong."; exit 1
fi

read -p "Masukkan nomor index instansi (1,2,3,...). Dipakai untuk port calc: " IDX
if ! [[ "$IDX" =~ ^[0-9]+$ ]]; then
  echo "Index harus angka."; exit 1
fi

# compute ports
# UI pattern: 3000,3100,3200,... => UI = 3000 + (IDX-1)*100
UI_PORT=$((3000 + (IDX - 1) * 100))
# CWMP base 7547 -> add (IDX-1)*10
CWMP_PORT=$((7547 + (IDX - 1) * 10))
NBI_PORT=$((7557 + (IDX - 1) * 10))
FS_PORT=$((7567 + (IDX - 1) * 10))
# MongoDB port per-instance: 27017 + (IDX-1)*100
MONGO_PORT=$((27017 + (IDX - 1) * 100))

# paths
BASE_DIR="/opt/genieacs-${INST}"
LOG_DIR="/var/log/genieacs-${INST}"
ENV_FILE="${BASE_DIR}/genieacs.env"
MONGO_DBPATH="/var/lib/mongo-${INST}"
MONGO_CONF="/etc/mongod-${INST}.conf"
MONGO_SERVICE="/etc/systemd/system/mongod-${INST}.service"
GENIEACS_USER="genieacs-${INST}"

echo ""
echo "Instalasi instansi: $INST"
echo "Index: $IDX"
echo "Ports: UI=$UI_PORT, CWMP=$CWMP_PORT, NBI=$NBI_PORT, FS=$FS_PORT, MONGO=$MONGO_PORT"
echo ""

read -p "Lanjut install instansi $INST ? (y/n): " CONF
[ "$CONF" != "y" ] && { echo "Dibatalkan."; exit 1; }

# === update & base deps ===
apt update
apt install -y curl wget gnupg build-essential ufw

# install redis (single redis for all instances)
if ! command -v redis-server >/dev/null 2>&1; then
  apt install -y redis-server
  systemctl enable --now redis-server
fi

# install nodejs (if belum)
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
fi

# install MongoDB 7.0 (official repo) jika mongod belum ada
if ! command -v mongod >/dev/null 2>&1; then
  echo "Menginstal MongoDB Community Server 7.0..."

  # Import GPG Key
  curl -fsSL https://pgp.mongodb.com/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg

  # Tambah repo MongoDB
  echo "deb [signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] \
https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc)/mongodb-org/7.0 multiverse" \
  | tee /etc/apt/sources.list.d/mongodb-org-7.0.list

  apt update
  apt install -y mongodb-org

  # Disable default mongod agar tidak bentrok (kita pakai mongod per instance)
  systemctl disable --now mongod || true
fi


# create system user for this instance
if ! id -u "$GENIEACS_USER" >/dev/null 2>&1; then
  useradd -r -s /bin/false "$GENIEACS_USER" || true
fi

# create directories
mkdir -p "$BASE_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$MONGO_DBPATH"
mkdir -p "$BASE_DIR/ext"
chown -R "$GENIEACS_USER":"$GENIEACS_USER" "$BASE_DIR" "$LOG_DIR" "$MONGO_DBPATH"

# download genieacs (correct tar link - FIX)
TMP_TAR="/tmp/genieacs.tar.gz"
if [ ! -f "$TMP_TAR" ]; then
  echo "Downloading GenieACS source..."
  wget -q -O "$TMP_TAR" "https://codeload.github.com/genieacs/genieacs/tar.gz/refs/heads/master"
fi

tar -xzf "$TMP_TAR" -C "$BASE_DIR" --strip 1


# install node deps for this instance
cd "$BASE_DIR"
npm install --production

# create env file for instance
cat > "$ENV_FILE" <<EOF
# GenieACS env for instance $INST
GENIEACS_CWMP_HOST=0.0.0.0
GENIEACS_CWMP_PORT=${CWMP_PORT}

GENIEACS_NBI_HOST=0.0.0.0
GENIEACS_NBI_PORT=${NBI_PORT}

GENIEACS_FS_HOST=0.0.0.0
GENIEACS_FS_PORT=${FS_PORT}

GENIEACS_UI_HOST=0.0.0.0
GENIEACS_UI_PORT=${UI_PORT}

GENIEACS_UI_JWT_SECRET=$(openssl rand -hex 32)
GENIEACS_EXT_DIR=${BASE_DIR}/ext
GENIEACS_DEBUG_FILE=${LOG_DIR}/debug.yaml

# MongoDB connection (per-instance mongod)
GENIEACS_MONGODB_CONNECTION_URL="mongodb://127.0.0.1:${MONGO_PORT}/genieacs_${INST}"
EOF

chown "$GENIEACS_USER":"$GENIEACS_USER" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# create mongod config for this instance
cat > "$MONGO_CONF" <<EOF
# mongod config for instance $INST
storage:
  dbPath: "${MONGO_DBPATH}"
  journal:
    enabled: true
systemLog:
  destination: file
  path: "/var/log/mongodb/mongod-${INST}.log"
  logAppend: true
net:
  bindIp: 127.0.0.1
  port: ${MONGO_PORT}
processManagement:
  fork: false
EOF

mkdir -p /var/log/mongodb
touch "/var/log/mongodb/mongod-${INST}.log"
chown -R "$GENIEACS_USER":"$GENIEACS_USER" "$MONGO_DBPATH" "/var/log/mongodb/mongod-${INST}.log"

# create mongod systemd service for instance
cat > "$MONGO_SERVICE" <<EOF
[Unit]
Description=MongoDB Database Server for GenieACS instance ${INST}
After=network.target

[Service]
User=${GENIEACS_USER}
Group=${GENIEACS_USER}
ExecStart=/usr/bin/mongod --config ${MONGO_CONF}
PIDFile=/var/run/mongod-${INST}.pid
Restart=on-failure
LimitNOFILE=64000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "mongod-${INST}.service"

# create genieacs systemd services (cwmp,nbi,fs,ui)
cat > "/etc/systemd/system/genieacs-${INST}-cwmp.service" <<EOF
[Unit]
Description=GenieACS CWMP (${INST})
After=network.target mongod-${INST}.service redis-server.service

[Service]
EnvironmentFile=${ENV_FILE}
User=${GENIEACS_USER}
ExecStart=/usr/bin/node ${BASE_DIR}/bin/genieacs-cwmp
Restart=always
WorkingDirectory=${BASE_DIR}
LimitNOFILE=64000

[Install]
WantedBy=multi-user.target
EOF

cat > "/etc/systemd/system/genieacs-${INST}-nbi.service" <<EOF
[Unit]
Description=GenieACS NBI (${INST})
After=network.target mongod-${INST}.service redis-server.service

[Service]
EnvironmentFile=${ENV_FILE}
User=${GENIEACS_USER}
ExecStart=/usr/bin/node ${BASE_DIR}/bin/genieacs-nbi
Restart=always
WorkingDirectory=${BASE_DIR}
LimitNOFILE=64000

[Install]
WantedBy=multi-user.target
EOF

cat > "/etc/systemd/system/genieacs-${INST}-fs.service" <<EOF
[Unit]
Description=GenieACS FS (${INST})
After=network.target mongod-${INST}.service redis-server.service

[Service]
EnvironmentFile=${ENV_FILE}
User=${GENIEACS_USER}
ExecStart=/usr/bin/node ${BASE_DIR}/bin/genieacs-fs
Restart=always
WorkingDirectory=${BASE_DIR}
LimitNOFILE=64000

[Install]
WantedBy=multi-user.target
EOF

cat > "/etc/systemd/system/genieacs-${INST}-ui.service" <<EOF
[Unit]
Description=GenieACS UI (${INST})
After=network.target

[Service]
EnvironmentFile=${ENV_FILE}
User=${GENIEACS_USER}
ExecStart=/usr/bin/node ${BASE_DIR}/bin/genieacs-ui
Restart=always
WorkingDirectory=${BASE_DIR}
LimitNOFILE=64000

[Install]
WantedBy=multi-user.target
EOF

# reload & start services
systemctl daemon-reload
systemctl enable --now "genieacs-${INST}-cwmp.service" "genieacs-${INST}-nbi.service" "genieacs-${INST}-fs.service" "genieacs-${INST}-ui.service"

# open ufw ports for this instance
ufw allow "${UI_PORT}/tcp"
ufw allow "${CWMP_PORT}/tcp"
ufw allow "${NBI_PORT}/tcp"
ufw allow "${FS_PORT}/tcp"
ufw allow "${MONGO_PORT}/tcp"    # optional, might not want to expose; keep internal if possible

echo ""
echo "======================================================"
echo "INSTANSI $INST TERPASANG:"
echo " - UI  : http://$(hostname -I | awk '{print $1}'):${UI_PORT}"
echo " - CWMP: ${CWMP_PORT}"
echo " - NBI : ${NBI_PORT}"
echo " - FS  : ${FS_PORT}"
echo " - MongoDB port: ${MONGO_PORT}"
echo ""
echo "Paths:"
echo " - App dir: ${BASE_DIR}"
echo " - Logs   : ${LOG_DIR}"
echo " - Env    : ${ENV_FILE}"
echo ""
echo "Systemd services created:"
echo " - mongod-${INST}.service"
echo " - genieacs-${INST}-cwmp.service"
echo " - genieacs-${INST}-nbi.service"
echo " - genieacs-${INST}-fs.service"
echo " - genieacs-${INST}-ui.service"
echo "======================================================"
echo ""
echo "Catatan penting:"
echo " - Pastikan NATVPS panel mem-forward port UI/CWMP/NBI/FS ke internal VPS"
echo " - Mengekspos MongoDB ke publik tidak aman; jika tidak perlu, jangan forward port MongoDB di panel."
echo " - Jika ingin uninstall instansi, jalankan perintah uninstall yang ada di README."
