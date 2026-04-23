
<p align="center">
  <img src="https://raw.githubusercontent.com/heruhendri/Installer-GenieACS/main/ss.png" width="1800" />
</p>

<h1 align="center">🚀 Installer GenieACS — NATVPS / Multi Instance / Auto Restore DB</h1>

<p align="center">
  <b>Full Installer • Multi Client Support • Auto Recovery DB • Menu CLI</b>
</p>

<p align="center">
  <!-- Shields / Badges -->
  <img src="https://img.shields.io/badge/Ubuntu-22.04-orange?logo=ubuntu" />
  <img src="https://img.shields.io/badge/GenieACS-1.2+-blue?logo=genie" />
  <img src="https://img.shields.io/badge/Multi%20Instance-Supported-success" />
  <img src="https://img.shields.io/badge/License-MIT-green" />
  <img src="https://img.shields.io/github/stars/heruhendri/Installer-GenieACS?style=social" />
</p>

---

# 🎥 Demo Video

> Klik untuk melihat proses instalasi lengkap

[![Demo Video](https://img.youtube.com/vi/9h2hS8cYb2k/0.jpg)](https://www.youtube.com/watch?v=9h2hS8cYb2k)

---

# 📦 Installer Tersedia

### **🟢 Installer 1 — Single Instance**

Instalasi default GenieACS (UI port 3000)

```bash
wget https://raw.githubusercontent.com/heruhendri/Installer-GenieACS/main/install-genieacs.sh
chmod +x install-genieacs.sh
./install-genieacs.sh
````

---

### **🔵 Installer 2 — Multi Instance (client1, client2, dst.)**

Mendukung banyak client pada satu server (isolasi penuh)

```bash
wget https://raw.githubusercontent.com/heruhendri/Installer-GenieACS/main/installer-multi-genieacs.sh
chmod +x installer-multi-genieacs.sh
./installer-multi-genieacs.sh
```

---

# 🧩 Perbedaan Installer

| Fitur                       | Installer 1 | Installer 2 |
| --------------------------- | ----------- | ----------- |
| Single Instance             | ✅           | ❌           |
| Multi Instance              | ❌           | ✅           |
| Database Per Instance       | ❌           | ✅           |
| Port Unik Per Client        | ❌           | ✅           |
| Auto Restore DB dari GitHub | ❌           | ✅           |
| Menu CLI `genieacs-menu`    | ❌           | ✅           |
| NATVPS Support              | ⚠️          | ✅           |
| Auto Service Builder        | ⚠️          | ✅           |

---

# 🧱 Struktur Folder Multi Instance

```
/opt/genieacs-<instance>/
│── genieacs.env
│── ext/
/var/log/genieacs-<instance>/
│── ui.log, fs.log, nbi.log, cwmp.log
MongoDB:
  genieacs-<instance>
Service:
  genieacs-<instance>-ui
  genieacs-<instance>-nbi
  genieacs-<instance>-fs
  genieacs-<instance>-cwmp
```

---

# 🔧 Port Default

| Port | Fungsi      |
| ---- | ----------- |
| 3000 | GenieACS UI |
| 7547 | CWMP        |
| 7557 | NBI         |
| 7567 | File Server |

---

# 🧭 Instalasi Multi Instance

```mermaid
flowchart TD

A[Start Installer] --> B{Dependencies Installed?}
B -->|No| C[Install NodeJS, MongoDB, Core Packages]
B -->|Yes| D[Continue]

D --> E[Input Instance Name & Ports]
E --> F{Instance Exists?}
F -->|Yes| X[Error: Instance Already Exists]
F -->|No| G[Create Directory /opt/genieacs-INSTANCE_NAME]

G --> H[Create Environment File]
H --> I[Build systemd Services per Component]

I --> J[Start & Enable Services]
J --> K{Restore DB from GitHub?}
K -->|Yes| L[Fetch DB → mongorestore]
K -->|No| M[Skip]

L --> N[Restart Services]
M --> N

N --> O[Install genieacs-menu CLI]
O --> P{Delete Installer Script?}
P -->|Yes| Q[rm *.sh]
P -->|No| R[Finish]

Q --> R

```

---

# 🏗 Arsitektur Sistem GenieACS

```mermaid
flowchart LR

subgraph A["GenieACS Instance"]
    UI["UI Service"]
    CWMP["CWMP Service"]
    NBI["NBI Service"]
    FS["File Server"]
end

A --> DB["MongoDB Database"]
A --> LOG["Log Directory (var/log/genieacs-INSTANCE_NAME)"]
A --> CFG["Config File (opt/genieacs-INSTANCE_NAME/genieacs.env)"]

```

---

# 🛠 Menu CLI — `genieacs-menu`

Setelah instalasi, cukup jalankan:

```
genieacs-menu
```

Menu meliputi:

* Start/Stop/Restart Semua Service
* Reset Database (Auto download DB default dari GitHub)
* Ganti Port Instance
* Cek Log Realtime
* Backup Database
* Tambah Instance Baru

---

# 🗃 Restore Database Default

Installer otomatis mengambil DB preset dari:

```
https://github.com/heruhendri/Installer-GenieACS/tree/main/db
```

Perintah manual:

```bash
genieacs-menu → Reset Database
```

---

# 🗑 Uninstall Semua Instance

```bash
systemctl stop genieacs-* 
systemctl disable genieacs-*
rm -rf /opt/genieacs*
rm -rf /var/log/genieacs*
rm /etc/systemd/system/genieacs-*.service
systemctl daemon-reload
```

---

# 📜 Changelog

## **v2.5 — 2025**

* Menambahkan auto-restore DB via GitHub
* Menu CLI lengkap (`genieacs-menu`)
* Auto service builder
* Support total multi instance tanpa batas
* Perbaikan struktur folder
* Perbaikan auto-start service setelah reset DB
* Compatible NATVPS

## **v2.1 — 2024**

* Multi instance awal
* Port custom
* Database per instance

## **v1.0 — 2023**

* Installer single instance

---

# 📄 License

MIT License 

---

# 💬 Support

Telegram: **@GbtTapiPngnSndiri**

---

<p align="center">
  ⭐ Jika project ini membantu, silakan beri bintang di GitHub!
</p>

