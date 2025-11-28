#!/bin/bash
set -u
# installer-multi-genieacs-fixed.sh
# Multi GenieACS + Multi GUI installer (fixed)
# - Clean install
# - Auto remove installer file on exit
# - Robust handling for Redis/Mongo and existing dirs
# - Uses node dist/bin scripts for backend
# Run as root

SELF="$(readlink -f "$0")"

cleanup() {
  # try remove installer (best-effort)
  if [ -f "$SELF" ]; then
    rm -f "$SELF" || echo "Warning: cannot remove installer $SELF"
  fi
}
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
  echo "Jalankan script ini sebagai root (sudo)." >&2
  exit 1
fi

echo "============================================"
echo "   INSTALLER MULTI GENIEACS + MULTI GUI FIX"
echo "         CLEAN INSTALL - NO MORE ERROR"
echo "============================================"

# update & minimal tools
apt update -y
apt install -y curl wget git build-essential gnupg ca-certificates

# node (18.x)
if ! command -v node >/dev/null 2>&1 || [ "$(node -v 2>/dev/null | cut -d. -f1 | tr -d 'v')" -lt 18 ]; then
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt install -y nodejs
fi

# redis install (if not present)
if ! systemctl list-units --full -all | grep -qE '^redis(-| ).*loaded'; then
  apt install -y redis-server || true
fi
systemctl enable --now redis-server 2>/dev/null || true

# mongodb install fallback (try mongodb-org, mongodb-server, mongodb)
if ! systemctl list-units --full -all | grep -qE '^mongod|mongodb'; then
  apt install -y mongodb-org || apt install -y mongodb-server || apt install -y mongodb || true
fi
# try enable/start possible service names
systemctl enable --now mongod 2>/dev/null || systemctl enable --now mongodb 2>/dev/null || true

echo
read -p "Berapa instance GenieACS yang ingin dibuat? " INSTANCES
if ! [[ "$INSTANCES" =~ ^[0-9]+$ ]] || [ "$INSTANCES" -le 0 ]; then
  echo "Input salah — masukkan angka > 0." >&2
  exit 1
fi

# default starting ports
CWMP_PORT=7547
NBI_PORT=7557
FS_PORT=7567
GUI_PORT=3000
REDIS_PORT=6380

# location of global temp GUI build (build once to speed up)
TMP_GUI_BUILD="/opt/genieacs-gui-build"
if [ -d "$TMP_GUI_BUILD" ]; then
  rm -rf "$TMP_GUI_BUILD"
fi
echo "Mempersiapkan GUI source build di $TMP_GUI_BUILD ..."
git clone https://github.com/genieacs/genieacs-gui "$TMP_GUI_BUILD"
cd "$TMP_GUI_BUILD" || exit 1
# install/build GUI once (use legacy-peer-deps if needed)
npm install --legacy-peer-deps || npm install || true
# produce distributable (some versions expose dist)
if npm run build; then
  echo "GUI build success"
else
  echo "GUI build gagal — lanjutkan namun GUI mungkin tidak berfungsi." >&2
fi
cd /root || true

for i in $(seq 1 "$INSTANCES"); do
  echo
  echo "============================================"
  echo "  MEMBUAT / MEMBERSIHKAN INSTANSI #$i"
  echo "============================================"

  INSTALL_DIR="/opt/genieacs${i}"
  SERVICE_NAME="genieacs${i}"
  GUI_SERVICE="genieacs-gui${i}"
  REDIS_SERVICE="redis-${SERVICE_NAME}"
  DB_NAME="genieacs${i}db"

  # stop & remove old services if exists
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  systemctl stop "$GUI_SERVICE" 2>/dev/null || true
  systemctl disable "$GUI_SERVICE" 2>/dev/null || true
  systemctl stop "$REDIS_SERVICE" 2>/dev/null || true
  systemctl disable "$REDIS_SERVICE" 2>/dev/null || true

  # remove old files
  rm -rf "$INSTALL_DIR"
  rm -f /etc/systemd/system/"$SERVICE_NAME".service
  rm -f /etc/systemd/system/"$GUI_SERVICE".service
  rm -f /etc/systemd/system/"$REDIS_SERVICE".service
  rm -f /etc/redis/redis-"$SERVICE_NAME".conf

  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR" || exit 1

  echo "Cloning genieacs backend into $INSTALL_DIR ..."
  git clone https://github.com/genieacs/genieacs "$INSTALL_DIR" 2>/dev/null || {
    # sometimes clone into same dir fails; if so, try init + remote
    git init
    git remote add origin https://github.com/genieacs/genieacs
    git fetch --depth=1 origin main || git fetch --depth=1 origin master || true
    git pull origin main || git pull origin master || true
  }

  # install dependencies & build backend
  cd "$INSTALL_DIR" || exit 1
  npm install --legacy-peer-deps || npm install || true
  if npm run build 2>/dev/null; then
    echo "Backend build OK"
  else
    echo "Backend build mungkin gagal — periksa logs." >&2
  fi

  # create config
  mkdir -p "$INSTALL_DIR/config"
  cat > "$INSTALL_DIR/config/config.json" <<EOF
{
  "cwmp": { "port": $CWMP_PORT },
  "nbi": { "port": $NBI_PORT },
  "fs": { "port": $FS_PORT },
  "db": { "mongoUrl": "mongodb://localhost:27017/${DB_NAME}" },
  "redis": { "port": $REDIS_PORT }
}
EOF

  # prepare redis config for this instance
  REDIS_CONF="/etc/redis/redis-${SERVICE_NAME}.conf"
  if [ -f /etc/redis/redis.conf ]; then
    cp /etc/redis/redis.conf "$REDIS_CONF"
    sed -i "s/^port .*/port $REDIS_PORT/" "$REDIS_CONF"
    sed -i "s|^pidfile .*|pidfile /var/run/redis-${SERVICE_NAME}.pid|" "$REDIS_CONF"
  else
    # create minimal redis conf
    cat >"$REDIS_CONF" <<EOF
bind 127.0.0.1
port $REDIS_PORT
dir /var/lib/redis
pidfile /var/run/redis-${SERVICE_NAME}.pid
timeout 0
tcp-keepalive 300
loglevel notice
EOF
  fi

  # create systemd unit for redis instance
  cat >/etc/systemd/system/"$REDIS_SERVICE".service <<EOF
[Unit]
Description=Redis Instance for ${SERVICE_NAME}
After=network.target

[Service]
ExecStart=/usr/bin/redis-server ${REDIS_CONF}
ExecStop=/usr/bin/redis-cli -p ${REDIS_PORT} shutdown
User=redis
Group=redis
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$REDIS_SERVICE"

  # create backend systemd unit that starts cwmp, nbi, fs and waits
  # using a shell wrapper so systemd can track the combined process
  cat >/etc/systemd/system/"$SERVICE_NAME".service <<EOF
[Unit]
Description=GenieACS Backend Instance ${i}
After=network.target ${REDIS_SERVICE}.service mongod.service mongodb.service

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=/bin/bash -c "exec /usr/bin/node ${INSTALL_DIR}/dist/bin/genieacs-cwmp --config ${INSTALL_DIR}/config/config.json & /usr/bin/node ${INSTALL_DIR}/dist/bin/genieacs-nbi --config ${INSTALL_DIR}/config/config.json & /usr/bin/node ${INSTALL_DIR}/dist/bin/genieacs-fs --config ${INSTALL_DIR}/config/config.json; wait"
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME" || {
    echo "Perhatian: gagal enable/start $SERVICE_NAME. Cek journalctl -u $SERVICE_NAME" >&2
  }

  # GUI: copy pre-built GUI into instance gui folder (clean)
  GUI_DIR="${INSTALL_DIR}/gui"
  rm -rf "$GUI_DIR"
  mkdir -p "$GUI_DIR"
  # prefer built output in TMP_GUI_BUILD/dist or TMP_GUI_BUILD/build
  if [ -d "${TMP_GUI_BUILD}/dist" ]; then
    cp -r "${TMP_GUI_BUILD}/dist/." "$GUI_DIR/"
  elif [ -d "${TMP_GUI_BUILD}/build" ]; then
    cp -r "${TMP_GUI_BUILD}/build/." "$GUI_DIR/"
  else
    # fallback: clone and build per-instance
    git clone https://github.com/genieacs/genieacs-gui "${GUI_DIR}"
    cd "${GUI_DIR}" || true
    npm install --legacy-peer-deps || true
    npm run build || true
  fi

  # create systemd unit for GUI
  # Many releases include server.js for GUI server; if not present, use simple static server (http-server)
  GUI_START_CMD="/usr/bin/node ${GUI_DIR}/server.js --port ${GUI_PORT}"
  if [ ! -f "${GUI_DIR}/server.js" ]; then
    # install http-server globally if needed
    if ! command -v http-server >/dev/null 2>&1; then
      npm install -g http-server || true
    fi
    GUI_START_CMD="/usr/bin/http-server ${GUI_DIR} -p ${GUI_PORT} -a 127.0.0.1"
  fi

  cat >/etc/systemd/system/"$GUI_SERVICE".service <<EOF
[Unit]
Description=GenieACS GUI Instance ${i}
After=network.target ${SERVICE_NAME}.service

[Service]
Type=simple
WorkingDirectory=${GUI_DIR}
ExecStart=/bin/bash -c "${GUI_START_CMD}"
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$GUI_SERVICE" || {
    echo "Perhatian: gagal enable/start $GUI_SERVICE. Cek journalctl -u $GUI_SERVICE" >&2
  }

  echo
  echo "===== INSTANCE #${i} BERHASIL DIBUAT (atau dipicu start) ====="
  echo "GUI    : http://<IP_VPS>:${GUI_PORT}"
  echo "CWMP   : ${CWMP_PORT}"
  echo "NBI    : ${NBI_PORT}"
  echo "FS     : ${FS_PORT}"
  echo "Redis  : ${REDIS_PORT} (service: ${REDIS_SERVICE})"
  echo "DB     : ${DB_NAME}"
  echo "============================================================"

  # increment ports for next instance
  CWMP_PORT=$((CWMP_PORT + 100))
  NBI_PORT=$((NBI_PORT + 100))
  FS_PORT=$((FS_PORT + 100))
  GUI_PORT=$((GUI_PORT + 100))
  REDIS_PORT=$((REDIS_PORT + 1))

done

echo
echo "============================================"
echo "   INSTALASI MULTI GENIEACS + MULTI GUI DONE"
echo "============================================"
# cleanup TMP build
rm -rf "$TMP_GUI_BUILD" || true

# cleanup will be run via trap on exit and remove installer file
exit 0
