#!/bin/bash 
set -euo pipefail

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

# port calculation
UI_PORT=$((3000 + (IDX - 1) * 100))
CWMP_PORT=$((7547 + (IDX - 1) * 10))
NBI_PORT=$((7557 + (IDX - 1) * 10))
FS_PORT=$((7567 + (IDX - 1) * 10))
MONGO_PORT=$((27017 + (IDX - 1) * 100))

BASE_DIR="/opt/genieacs-${INST}"
LOG_DIR="/var/log/genieacs-${INST}"
ENV_FILE="${BASE_DIR}/genieacs.env"
MONGO_DBPATH="/var/lib/mongo-${INST}"
MONGO_CONF="/etc/mongod-${INST}.conf"
MONGO_SERVICE="/etc/systemd/system/mongod-${INST}.service"
GENIEACS_USER="genieacs-${INST}"

echo ""
echo "Instansi: $INST"
echo "Index: $IDX"
echo "Ports => UI=$UI_PORT  CWMP=$CWMP_PORT  NBI=$NBI_PORT  FS=$FS_PORT  MONGO=$MONGO_PORT"
echo ""

read -p "Lanjut install? (y/n): " CONF
[ "$CONF" != "y" ] && exit 0

apt update
apt install -y curl wget gnupg build-essential ufw

# install redis
if ! command -v redis-server >/dev/null; then
  apt install -y redis-server
  systemctl enable --now redis-server
fi

# install nodejs
if ! command -v node >/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
fi

# install mongodb 7
if ! command -v mongod >/dev/null; then
  curl -fsSL https://pgp.mongodb.com/server-7.0.asc \
    | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg

  echo "deb [signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] \
https://repo.mongodb.org/apt/ubuntu $(lsb_release -sc)/mongodb-org/7.0 multiverse" \
    > /etc/apt/sources.list.d/mongodb-org-7.0.list

  apt update
  apt install -y mongodb-org
  systemctl disable --now mongod || true
fi

# create user for genieacs
if ! id "$GENIEACS_USER" >/dev/null 2>&1; then
  useradd -r -s /bin/false "$GENIEACS_USER"
fi

mkdir -p "$BASE_DIR" "$LOG_DIR" "$BASE_DIR/ext"
mkdir -p "$MONGO_DBPATH"
chown -R "$GENIEACS_USER":"$GENIEACS_USER" "$BASE_DIR" "$LOG_DIR"
chown -R mongodb:mongodb "$MONGO_DBPATH"

# download genieacs
TMP_TAR="/tmp/genieacs.tar.gz"
if [ ! -f "$TMP_TAR" ]; then
  wget -q -O "$TMP_TAR" \
    "https://codeload.github.com/genieacs/genieacs/tar.gz/refs/heads/master"
fi

tar -xzf "$TMP_TAR" -C "$BASE_DIR" --strip 1

cd "$BASE_DIR"
npm install --production

# ENV FILE
cat > "$ENV_FILE" <<EOF
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
GENIEACS_MONGODB_CONNECTION_URL=mongodb://127.0.0.1:${MONGO_PORT}/genieacs_${INST}
EOF

chown "$GENIEACS_USER":"$GENIEACS_USER" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# === FIX MONGODB CONFIG (RUN AS mongodb USER) ===
mkdir -p /var/log/mongodb
touch "/var/log/mongodb/mongod-${INST}.log"
chown mongodb:mongodb "/var/log/mongodb/mongod-${INST}.log"

cat > "$MONGO_CONF" <<EOF
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

# correct service (RUN AS mongodb)
cat > "$MONGO_SERVICE" <<EOF
[Unit]
Description=MongoDB for GenieACS ${INST}
After=network.target

[Service]
User=mongodb
Group=mongodb
ExecStart=/usr/bin/mongod --config ${MONGO_CONF}
Restart=always
LimitNOFILE=64000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "mongod-${INST}.service"

# genieacs services
for SVC in cwmp nbi fs ui; do
cat > "/etc/systemd/system/genieacs-${INST}-${SVC}.service" <<EOF
[Unit]
Description=GenieACS ${SVC} (${INST})
After=network.target mongod-${INST}.service redis-server.service

[Service]
EnvironmentFile=${ENV_FILE}
User=${GENIEACS_USER}
ExecStart=/usr/bin/node ${BASE_DIR}/bin/genieacs-${SVC}
WorkingDirectory=${BASE_DIR}
Restart=always
LimitNOFILE=64000

[Install]
WantedBy=multi-user.target
EOF
done

systemctl daemon-reload
systemctl enable --now genieacs-${INST}-cwmp.service \
                        genieacs-${INST}-nbi.service \
                        genieacs-${INST}-fs.service \
                        genieacs-${INST}-ui.service

ufw allow "${UI_PORT}/tcp"
ufw allow "${CWMP_PORT}/tcp"
ufw allow "${NBI_PORT}/tcp"
ufw allow "${FS_PORT}/tcp"

echo ""
echo "=============================================="
echo "INSTANSI $INST BERHASIL DIPASANG"
echo "UI : http://$(hostname -I | awk '{print $1}'):${UI_PORT}"
echo "CWMP : ${CWMP_PORT}"
echo "NBI : ${NBI_PORT}"
echo "FS : ${FS_PORT}"
echo "MongoDB Port : ${MONGO_PORT}"
echo "=============================================="
