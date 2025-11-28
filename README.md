
# GenieACS Installer untuk NATVPS (Ubuntu 22.04)

Script ini digunakan untuk **menginstall GenieACS lengkap** pada **VPS / NATVPS Ubuntu 22.04**, termasuk:

* Node.js 20
* MongoDB
* Redis
* Konfigurasi environment
* Service systemd
* Port default GenieACS
* Otomatis berjalan saat boot
---

### Screnshoot Dashboard GenieACS
---
![Screnshoot Dashboard](https://github.com/heruhendri/Installer-GenieACS/blob/main/ss.png)

## 🚀 Cara Instalasi (Installer 1 Menggunakan Port 3000. Installer 2 Menginstall Multi GenieACS)

### 1. Download dan jalankan installer 1

```bash
wget https://raw.githubusercontent.com/heruhendri/Installer-GenieACS/main/install-genieacs.sh
chmod +x install-genieacs.sh
./install-genieacs.sh
```

### 2. Download dan jalankan installer 2
```bash
wget https://raw.githubusercontent.com/heruhendri/Installer-GenieACS/main/installer-multi-genieacs.sh
chmod +x installer-multi-genieacs.sh
./installer-multi-genieacs.sh
```
---


## 📌 Perbedaan Installer 2
1.  **Dependencies (NodeJS/MongoDB)** hanya perlu diinstall sekali.
2.  Setiap instance akan memiliki **Nama Instance** unik (misal: `client1`, `client2`).
3.  Setiap instance akan memiliki **Port** yang berbeda (agar tidak bentrok).
4.  Setiap instance akan memiliki **Database MongoDB** yang terpisah.
5.  Setiap instance akan memiliki **Service Systemd** yang unik.


### Apa yang berubah di script ini?

1.  **Input Interaktif:**
    Script sekarang akan meminta **Nama Instance** dan **Port** di awal. Ini krusial untuk NAT VPS di mana port sering kali acak atau terbatas.

      * Jika Anda menginstall pertama kali, Anda bisa menekan Enter untuk menggunakan port default (3000, 7547, dll).
      * Jika Anda menginstall instance kedua, Anda **WAJIB** memasukkan port yang berbeda (misal: UI 3001, CWMP 7548, dll).

2.  **Direktori Terisolasi:**
    Alih-alih semuanya masuk ke `/opt/genieacs`, sekarang file config masuk ke:
    `/opt/genieacs-<nama_instance>`
    Ini mencegah instance A membaca config instance B.

3.  **Database Terpisah:**
    Script menambahkan baris ini ke file env:
    `GENIEACS_MONGODB_CONNECTION_URL=mongodb://127.0.0.1:27017/genieacs-${INSTANCE_NAME}`
    Ini membuat MongoDB membuat database baru khusus untuk instance tersebut. Data pelanggan instance A tidak akan tercampur dengan instance B.

4.  **Service Systemd Unik:**
    Nama service diubah menjadi `genieacs-<nama_instance>-cwmp`, dst. Ini memungkinkan Anda me-restart satu instance tanpa mematikan instance lainnya.

5.  **Cek Dependensi Pintar:**
    Script mengecek apakah Node.js, MongoDB, dan core GenieACS sudah terinstall. Jika sudah ada (karena instalasi instance sebelumnya), script akan melewati langkah download/install berat dan langsung ke konfigurasi instance baru. Ini membuat instalasi instance kedua, ketiga, dst, berjalan sangat cepat (kurang dari 10 detik).

### Cara Menggunakan

1.  Jalankan perintah, misal `installer-multi-genieacs.sh`.
2.  Beri izin eksekusi:
    ````bash
    chmod +x installer-multi-genieacs.sh
    3.  Jalankan script:
    ```bash
    .installer-multi-genieacs.sh
    4.  Ikuti petunjuk di layar (masukkan nama instance dan port yang dialokasikan oleh provider NAT VPS Anda).
    ````

## 🎯 Port default yang digunakan

| Komponen | Port  |
| -------- | ----- |
| CWMP     | 7547  |
| NBI      | 7557  |
| FS       | 7567  |
| UI       | 3000 |

Untuk NATVPS, port **3000** wajib di-port-forward dari panel.

---

## 🔧 Akses GenieACS UI

```
http://IP-VPS:3000
```

---

## 🗑 Uninstall / Hapus Semua

```bash
systemctl stop genieacs-* 
systemctl disable genieacs-*
rm -rf /etc/genieacs.env
rm -rf /opt/genieacs
rm -rf /var/log/genieacs
rm /etc/systemd/system/genieacs-*.service
systemctl daemon-reload
```

---

# ⭐ Fitur Tambahan

* Auto generate JWT secret
* Support NATVPS/Virtuozzo
* Semua service auto start

---

# 🔗 **3. LINK RAW INSTALLER**

Setelah upload ke GitHub, format link raw:

```
https://raw.githubusercontent.com/heruhendri/Installer-GenieACS/main/installer.sh
```

