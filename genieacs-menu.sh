#!/bin/bash
clear

BASE_DIR="/opt"

get_instances() {
    ls -1 $BASE_DIR | grep "genieacs-" | sed 's/genieacs-//'
}

manage_instance() {
    INSTANCE="$1"
    DB="genieacs-$INSTANCE"

    while true; do
        clear
        echo "========================================="
        echo "   GENIEACS MENU — INSTANCE: $INSTANCE"
        echo "========================================="
        echo "1) Start semua service"
        echo "2) Stop semua service"
        echo "3) Restart semua service"
        echo "4) Status service"
        echo "5) Restore Database"
        echo "6) Backup Database"
        echo "7) Info Instance"
        echo "8) Kembali"
        echo "========================================="
        read -p "Pilih menu: " M

        case $M in
            1)
                systemctl start genieacs-$INSTANCE-cwmp
                systemctl start genieacs-$INSTANCE-nbi
                systemctl start genieacs-$INSTANCE-fs
                systemctl start genieacs-$INSTANCE-ui
                echo "Service berhasil dinyalakan."; read -p "Enter..."
                ;;
            2)
                systemctl stop genieacs-$INSTANCE-cwmp
                systemctl stop genieacs-$INSTANCE-nbi
                systemctl stop genieacs-$INSTANCE-fs
                systemctl stop genieacs-$INSTANCE-ui
                echo "Service berhasil dimatikan."; read -p "Enter..."
                ;;
            3)
                systemctl restart genieacs-$INSTANCE-cwmp
                systemctl restart genieacs-$INSTANCE-nbi
                systemctl restart genieacs-$INSTANCE-fs
                systemctl restart genieacs-$INSTANCE-ui
                echo "Service berhasil direstart."; read -p "Enter..."
                ;;
            4)
                systemctl status genieacs-$INSTANCE-* | less
                ;;
            5)
                echo "=== RESTORE DATABASE ==="
                read -p "Masukkan path dump folder (contoh /root/db): " DUMP

                if [[ ! -d "$DUMP" ]]; then
                    echo "Error: Folder dump tidak ditemukan!"; read -p "Enter..."; continue
                fi

                echo "Menghentikan service instance..."
                systemctl stop genieacs-$INSTANCE-*

                echo "Restore database..."
                mongorestore --drop --db $DB "$DUMP"

                echo "Menyalakan service..."
                systemctl start genieacs-$INSTANCE-*

                echo "Restore selesai!"; read -p "Enter..."
                ;;
            6)
                echo "=== BACKUP DATABASE ==="
                BK_DIR="/root/backup-genieacs-$INSTANCE-$(date +%Y%m%d-%H%M)"
                mkdir -p "$BK_DIR"

                mongodump --db="$DB" --out="$BK_DIR"

                echo "Backup tersimpan di: $BK_DIR"
                read -p "Enter..."
                ;;
            7)
                clear
                echo "========== INFO INSTANCE =========="
                ENV="$BASE_DIR/genieacs-$INSTANCE/genieacs.env"
                if [[ -f "$ENV" ]]; then
                    cat "$ENV"
                else
                    echo "File ENV tidak ditemukan!"
                fi
                echo "==================================="
                read -p "Enter..."
                ;;
            8)
                break
                ;;
            *)
                echo "Pilihan tidak valid"; sleep 1
                ;;
        esac
    done
}

main_menu() {
    while true; do
        clear
        echo "========================================="
        echo "           GENIEACS MAIN MENU"
        echo "========================================="

        INSTANCES=($(get_instances))
        if [[ ${#INSTANCES[@]} -eq 0 ]]; then
            echo "Tidak ada instance ditemukan."
        else
            echo "Instance tersedia:"
            for i in "${!INSTANCES[@]}"; do
                echo "$((i+1))) ${INSTANCES[$i]}"
            done
        fi

        echo "========================================="
        echo "Pilih nomor instance atau ketik 0 untuk exit"
        read -p "Pilihan: " CH

        if [[ "$CH" == "0" ]]; then
            exit 0
        fi

        IDX=$((CH-1))
        if [[ -n "${INSTANCES[$IDX]}" ]]; then
            manage_instance "${INSTANCES[$IDX]}"
        else
            echo "Pilihan tidak valid"; sleep 1
        fi
    done
}

main_menu
