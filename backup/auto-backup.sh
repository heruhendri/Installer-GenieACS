#!/bin/bash

# ==========================================================
# SKRIP OTOMATIS BACKUP GENIEACS MONGODB
# ==========================================================

# --- KONFIGURASI ---
# Ganti 'riski' dengan Nama Instance GenieACS Anda
INSTANCE_NAME="riski" 
DB_NAME="genieacs-${INSTANCE_NAME}"

# Direktori utama untuk menyimpan semua file backup
BACKUP_BASE_DIR="/home/backup_genieacs"

# Jumlah hari file backup akan disimpan sebelum dihapus (untuk menghemat ruang)
RETENTION_DAYS=7 
# --------------------

DATE_TIME=$(date +%Y%m%d_%H%M%S)
TEMP_DUMP_DIR="${BACKUP_BASE_DIR}/${DB_NAME}_${DATE_TIME}/"
FINAL_TAR_FILE="${BACKUP_BASE_DIR}/${DB_NAME}_${DATE_TIME}.tar.gz"

echo "=========================================================="
echo " Starting GenieACS Database Backup for: ${DB_NAME}"
echo "----------------------------------------------------------"

# 1. Pastikan folder utama backup ada
mkdir -p "${BACKUP_BASE_DIR}"

# 2. Hentikan layanan GenieACS sementara (Opsional, tapi disarankan untuk konsistensi data)
echo "Menghentikan layanan GenieACS untuk backup yang konsisten..."
systemctl stop --now genieacs-${INSTANCE_NAME}-cwmp genieacs-${INSTANCE_NAME}-nbi genieacs-${INSTANCE_NAME}-fs genieacs-${INSTANCE_NAME}-ui

# 3. Jalankan Mongodump
echo "Memulai mongodump ke: ${TEMP_DUMP_DIR}"
mongodump --db "${DB_NAME}" --out "${TEMP_DUMP_DIR}"

# Cek status mongodump
if [ $? -ne 0 ]; then
    echo "ERROR: Mongodump gagal!"
    # Mulai layanan kembali meskipun backup gagal
    systemctl start --now genieacs-${INSTANCE_NAME}-cwmp genieacs-${INSTANCE_NAME}-nbi genieacs-${INSTANCE_NAME}-fs genieacs-${INSTANCE_NAME}-ui
    exit 1
fi

# 4. Kompres hasil dump
echo "Mengompres hasil dump ke: ${FINAL_TAR_FILE}"
tar -czvf "${FINAL_TAR_FILE}" -C "${TEMP_DUMP_DIR}" .

# Cek status kompresi
if [ $? -ne 0 ]; then
    echo "ERROR: Kompresi file gagal!"
    # Mulai layanan kembali meskipun kompresi gagal
    systemctl start --now genieacs-${INSTANCE_NAME}-cwmp genieacs-${INSTANCE_NAME}-nbi genieacs-${INSTANCE_NAME}-fs genieacs-${INSTANCE_NAME}-ui
    exit 1
fi

# 5. Bersihkan (Hapus folder dump sementara dan mulai layanan kembali)
echo "Membersihkan folder dump sementara..."
rm -rf "${TEMP_DUMP_DIR}"

echo "Memulai kembali layanan GenieACS..."
systemctl start --now genieacs-${INSTANCE_NAME}-cwmp genieacs-${INSTANCE_NAME}-nbi genieacs-${INSTANCE_NAME}-fs genieacs-${INSTANCE_NAME}-ui

# 6. Bersihkan file backup lama
echo "Menghapus file backup yang lebih tua dari ${RETENTION_DAYS} hari..."
find "${BACKUP_BASE_DIR}" -type f -name "*.tar.gz" -mtime +"${RETENTION_DAYS}" -delete

echo "----------------------------------------------------------"
echo "Backup ${DB_NAME} berhasil disimpan sebagai:"
echo "${FINAL_TAR_FILE}"
echo "=========================================================="