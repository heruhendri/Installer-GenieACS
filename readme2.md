
# 🚀 Installer GenieACS untuk NATVPS / VPS Ubuntu 22.04

Repository ini berisi **dua installer lengkap** untuk GenieACS:

### ✅ Installer 1  
Instalasi standar (single instance) — cocok untuk 1 server GenieACS.

### ✅ Installer 2  
Mendukung **multi-instance GenieACS** pada satu VPS (client1, client2, dst).  
Setiap instance punya:
- Port berbeda  
- Database MongoDB berbeda  
- Folder isolasi berbeda  
- Service systemd berbeda  

---

## 📸 Screenshot Dashboard
![Screnshoot Dashboard](https://github.com/heruhendri/Installer-GenieACS/blob/main/ss.png)

---

# ⚡ 1. Cara Instalasi

## **Installer 1 (Single Instance – Port Default 3000)**

```bash
wget https://raw.githubusercontent.com/heruhendri/Installer-GenieACS/main/install-genieacs.sh
chmod +x install-genieacs.sh
./install-genieacs.sh
````

---

## **Installer 2 (Multi Instance — Client1, Client2, dst.)**

```bash
wget https://raw.githubusercontent.com/heruhendri/Installer-GenieACS/tambah-menu/installer-multi-genieacs.sh
chmod +x installer-multi-genieacs.sh
./installer-multi-genieacs.sh
```

---

# 🧩 2. Perbedaan Installer 1 & 2

| Fitur                             | Installer 1 | Installer 2 |
| --------------------------------- | ----------- | ----------- |
| Single Instance                   | ✅           | ❌           |
| Multi Instance (client1, client2) | ❌           | ✅           |
| Database terpisah                 | ❌           | ✅           |
| Port per instance                 | ❌           | ✅           |
| Service systemd unik              | ❌           | ✅           |
| Restore preset DB dari GitHub     | ❌           | ✅           |
| Menu CLI (genieacs-menu)          | ❌           | ✅           |

---

# 🧱 3. Struktur Folder Instansi (Installer 2)

Setiap instance memiliki direktori tersendiri:

```
/opt/genieacs-<instance>/
│── genieacs.env
│── ext/
│
/var/log/genieacs-<instance>/
│── cwmp.log
│── ui.log
│── fs.log
│── nbi.log
```

Contoh untuk instance `client1`:

```
/opt/genieacs-client1/
/var/log/genieacs-client1/
Database: genieacs-client1
Service:
  - genieacs-client1-cwmp
  - genieacs-client1-ui
  - genieacs-client1-nbi
  - genieacs-client1-fs
```

---

# 🏗 **4. Flowchart Arsitektur Installer Multi-Instance**

GitHub otomatis merender diagram berikut:

```mermaid
flowchart TD

A[Start Installer] --> B{Dependencies Sudah Terinstal?}
B -->|Belum| C[Install NodeJS, MongoDB, GenieACS Core]
B -->|Sudah| D[Lanjut]

D --> E[Input Nama Instance & Port]
E --> F{Folder Instance Sudah Ada?}
F -->|Ya| X[Error: Instance Sudah Ada → Stop]
F -->|Tidak| G[Buat Direktori Instance]

G --> H[Buat File Environment (.env)]
H --> I[Buat Service Systemd (cwmp/ui/fs/nbi)]

I --> J[Reload dan Start Service]
J --> K{Install Preset DB GitHub?}
K -->|Ya| L[Download Folder db dari GitHub → mongorestore]
K -->|Tidak| M[Lewati]

L --> N[Start ulang service instance]
M --> N

N --> O[Install genieacs-menu CLI]
O --> P{Hapus Installer?}
P -->|Ya| Q[rm installer.sh]
P -->|Tidak| R[Selesai]

Q --> R
```

---

# 🗃 5. Arsitektur Sistem (High Level)

```mermaid
flowchart LR

subgraph INSTANCE["Instance GenieACS"]
    A1[genieacs-cwmp] 
    A2[genieacs-ui]
    A3[genieacs-nbi]
    A4[genieacs-fs]
end

INSTANCE --> DB[(MongoDB: genieacs-<instance>)]
INSTANCE --> LOG[/var/log/genieacs-<instance>/]
INSTANCE --> CFG[/opt/genieacs-<instance>/genieacs.env]
```

---

# 🌐 6. Port Default

| Komponen | Port |
| -------- | ---- |
| CWMP     | 7547 |
| NBI      | 7557 |
| FS       | 7567 |
| UI       | 3000 |

Untuk NAT VPS:

```
3000 → Public Port NAT
7547 → TR-069 WAN management
```

---

# 🔧 7. Akses UI

```
http://IP-VPS:3000
```

---

# 🗑 8. Uninstall Semua Instance

```bash
systemctl stop genieacs-* 
systemctl disable genieacs-*
rm -rf /opt/genieacs*
rm -rf /var/log/genieacs*
rm /etc/systemd/system/genieacs-*.service
systemctl daemon-reload
```

---

# ⭐ 9. Raw Link Installer

```
https://raw.githubusercontent.com/heruhendri/Installer-GenieACS/main/install-genieacs.sh
```

---

# ✨ 10. Fitur Tambahan

* Auto JWT Secret
* NATVPS Ready
* Preset Recovery Database from GitHub
* Multi Instance Build
* Menu Command `genieacs-menu`

