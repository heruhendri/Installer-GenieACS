
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
wget https://raw.githubusercontent.com/heruhendri/Installer-GenieACS/main/install-genieacs2.sh
chmod +x install-genieacs2.sh
./install-genieacs2.sh
```
---

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

