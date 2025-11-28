*backup* database (DB) GenieACS Anda sangat penting untuk keamanan data, terutama setelah Anda berhasil menginstal *instance* baru.

Karena GenieACS menggunakan **MongoDB**, proses *backup* melibatkan perintah khusus dari MongoDB, yaitu `mongodump`.

Berikut adalah panduan lengkap cara *backup* database GenieACS Anda ke dalam sebuah folder *dump* yang siap disimpan atau dipindahkan.

-----

## Prosedur *Backup* Database GenieACS

Kita akan membuat skrip sederhana yang otomatis menjalankan `mongodump` dan mengompres hasilnya.

### 1\. Tentukan Nama *Instance* Anda

Pastikan Anda tahu nama *instance* GenieACS yang ingin Anda *backup*. Berdasarkan skrip Anda, nama database Anda adalah `genieacs-<INSTANCE_NAME>`.

Misalnya, jika Anda menggunakan nama *instance* **`riski`**:

  * Nama Database: `genieacs-riski`

### 2\. Jalankan Perintah *Backup*

Gunakan perintah `mongodump` untuk membuat salinan database Anda.

#### A. Backup Database ke Folder

Jalankan perintah ini di *terminal* VPS Anda:

```bash
# Ganti 'riski' dengan Nama Instance Anda
INSTANCE_NAME="riski"
DB_NAME="genieacs-${INSTANCE_NAME}"

# Tentukan folder output
OUTPUT_DIR="/home/backup_genieacs/${DB_NAME}_$(date +%Y%m%d_%H%M%S)"

echo "Membuat folder backup: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Jalankan mongodump
# --db: Database yang akan di backup
# --out: Direktori tempat backup akan disimpan
mongodump --db "$DB_NAME" --out "$OUTPUT_DIR"

echo "Backup database '$DB_NAME' selesai dan disimpan di:"
echo "$OUTPUT_DIR"

# Contoh struktur folder:
# /home/backup_genieacs/genieacs-riski_20251129_023000/genieacs-riski/
# ├── cache.bson
# ├── devices.bson
# └── ... (file data lainnya)
```

#### B. Mengompres Hasil *Backup* (Opsional, tapi Direkomendasikan)

Untuk memudahkan penyimpanan dan transfer, kompres folder hasil *dump* menjadi satu file `.zip` atau `.tar.gz`:

```bash
# Kembali ke direktori backup utama
cd /home/backup_genieacs/

# Kompres folder hasil dump
BACKUP_FILE="${DB_NAME}_$(date +%Y%m%d).tar.gz"
tar -czvf "$BACKUP_FILE" "${OUTPUT_DIR}"

echo "File backup terkompresi: /home/backup_genieacs/$BACKUP_FILE"

# Hapus folder dump asli (setelah berhasil dikompres)
rm -rf "${OUTPUT_DIR}"

echo "Folder dump asli dihapus. Backup siap dipindahkan."
```

## 3\. Skrip *Backup* Otomatis (Direkomendasikan)

Untuk efisiensi, Anda dapat menggabungkan langkah-langkah di atas ke dalam satu skrip Bash, misalnya **`backup_genieacs.sh`**, dan menjalankannya secara berkala (misalnya, melalui **Cron Job**).

Saya membuatkan skrip ini untuk Anda:

https://github.com/heruhendri/Installer-GenieACS/blob/main/backup/auto-backup.sh

### Langkah Penggunaan Skrip

1.  **Simpan Skrip:** Simpan kode di atas sebagai `backup_genieacs.sh` di direktori seperti `/usr/local/bin/`.
2.  **Berikan Izin Eksekusi:**
    ````bash
    chmod +x /usr/local/bin/backup_genieacs.sh
    3.  **Jalankan Manual (Uji Coba):**
    ```bash
    /usr/local/bin/backup_genieacs.sh
    4.  **Otomatisasi dengan Cron Job (Untuk *Daily Backup*):**
    Untuk menjalankan backup setiap hari pada pukul 03:00 pagi (ketika trafik rendah), tambahkan baris ke Cron:
    ```bash
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/backup_genieacs.sh > /dev/null 2>&1") | crontab -

    ````

Dengan cara ini, database GenieACS Anda akan ter-backup secara otomatis dan terjaga keamanannya.