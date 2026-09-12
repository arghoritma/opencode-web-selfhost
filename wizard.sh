#!/usr/bin/env bash
# Interactive setup for an OpenCode web service and a standalone Caddy site block.
set -euo pipefail

SERVICE_NAME="opencode-web"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/$SERVICE_NAME.service"

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '\n==> %s\n' "$*"
}

read_input() {
  local prompt=$1 value
  printf '%s' "$prompt" >/dev/tty
  IFS= read -r value </dev/tty || die 'Input dibatalkan.'
  printf '%s' "$value"
}

read_secret() {
  local prompt=$1 value
  printf '%s' "$prompt" >/dev/tty
  IFS= read -r -s value </dev/tty || die 'Input dibatalkan.'
  printf '\n' >/dev/tty
  printf '%s' "$value"
}

confirm() {
  local answer
  answer=$(read_input "$1 [y/N]: ")
  [[ $answer =~ ^[Yy]([Ee][Ss])?$ ]]
}

systemd_quote() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  printf '"%s"' "$value"
}

require_tty() {
  [[ -r /dev/tty && -w /dev/tty ]] || die 'Wizard ini interaktif dan membutuhkan terminal. Jalankan dari sesi SSH/terminal.'
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' tidak ditemukan. $2"
}

[[ ${BASH_VERSINFO[0]} -ge 4 ]] || die 'Bash 4 atau lebih baru diperlukan.'
[[ $(uname -s) == Linux ]] || die 'Wizard ini hanya mendukung server Linux.'
require_tty
require_command systemctl 'Pastikan server memakai systemd.'
require_command opencode 'Instal terlebih dahulu: curl -fsSL https://opencode.ai/install | bash'
require_command caddy 'Instal Caddy terlebih dahulu agar password dapat di-hash.'

OPENCODE_BIN=$(command -v opencode)

info 'OpenCode Web setup'
printf '%s\n' 'Service akan berjalan sebagai user saat ini dan hanya mendengar di 127.0.0.1.'
printf '%s\n' 'Caddyfile akan dibuat sebagai file terpisah; konfigurasi Caddy aktif tidak akan diubah.'

while true; do
  mode=$(read_input 'Mode project: [1] multi-project, [2] single-project: ')
  case $mode in
    1)
      PROJECT_MODE=multi
      WORKING_DIRECTORY=$HOME
      break
      ;;
    2)
      PROJECT_MODE=single
      while true; do
        PROJECT_PATH=$(read_input 'Full path project (contoh /home/admin/project/myproject): ')
        [[ -n $PROJECT_PATH ]] || { printf '%s\n' 'Path tidak boleh kosong.' >/dev/tty; continue; }
        [[ $PROJECT_PATH = /* ]] || { printf '%s\n' 'Gunakan path absolut.' >/dev/tty; continue; }
        [[ -d $PROJECT_PATH ]] || { printf '%s\n' 'Direktori project tidak ditemukan.' >/dev/tty; continue; }
        [[ $PROJECT_PATH != *$'\n'* ]] || { printf '%s\n' 'Path tidak boleh berisi baris baru.' >/dev/tty; continue; }
        WORKING_DIRECTORY=$PROJECT_PATH
        break
      done
      break
      ;;
    *) printf '%s\n' 'Pilih 1 atau 2.' >/dev/tty ;;
  esac
done

while true; do
  PORT=$(read_input 'Port OpenCode (1024-65535): ')
  if [[ $PORT =~ ^[0-9]+$ ]] && (( PORT >= 1024 && PORT <= 65535 )); then
    break
  fi
  printf '%s\n' 'Port harus berupa angka antara 1024 dan 65535.' >/dev/tty
done

while true; do
  DOMAIN=$(read_input 'Domain (contoh opencode.example.com): ')
  if [[ $DOMAIN =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; then
    break
  fi
  printf '%s\n' 'Masukkan domain valid tanpa http:// atau path.' >/dev/tty
done

while true; do
  AUTH_USERNAME=$(read_input 'Username Basic Auth: ')
  if [[ $AUTH_USERNAME =~ ^[A-Za-z0-9._-]+$ ]]; then
    break
  fi
  printf '%s\n' 'Username hanya boleh huruf, angka, titik, garis bawah, atau strip.' >/dev/tty
done

while true; do
  AUTH_PASSWORD=$(read_secret 'Password Basic Auth: ')
  [[ -n $AUTH_PASSWORD ]] || { printf '%s\n' 'Password tidak boleh kosong.' >/dev/tty; continue; }
  AUTH_PASSWORD_CONFIRM=$(read_secret 'Ulangi password: ')
  [[ $AUTH_PASSWORD == "$AUTH_PASSWORD_CONFIRM" ]] && break
  printf '%s\n' 'Password tidak sama, coba lagi.' >/dev/tty
done
unset AUTH_PASSWORD_CONFIRM

CADDY_HASH=$(printf '%s' "$AUTH_PASSWORD" | caddy hash-password)
unset AUTH_PASSWORD
CADDY_FILE="$HOME/${DOMAIN}.opencode.Caddyfile"

if [[ -e $SERVICE_FILE ]] && ! confirm "Service $SERVICE_FILE sudah ada dan akan ditimpa. Lanjutkan?"; then
  die 'Dibatalkan. Tidak ada perubahan dibuat.'
fi
if [[ -e $CADDY_FILE ]] && ! confirm "Caddyfile $CADDY_FILE sudah ada dan akan ditimpa. Lanjutkan?"; then
  die 'Dibatalkan. Tidak ada perubahan dibuat.'
fi

info 'Membuat service dan Caddyfile'
mkdir -p "$SERVICE_DIR"
umask 077

cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=OpenCode Web Server ($PROJECT_MODE project)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$(systemd_quote "$WORKING_DIRECTORY")
Environment=HOME=%h
Environment=XDG_CONFIG_HOME=%h/.config
Environment=XDG_DATA_HOME=%h/.local/share
ExecStart=$(systemd_quote "$OPENCODE_BIN") serve --hostname 127.0.0.1 --port $PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

cat >"$CADDY_FILE" <<EOF
# Tambahkan site block ini ke /etc/caddy/Caddyfile atau /etc/caddy/sites/$DOMAIN.
# Jangan expose port $PORT ke internet; OpenCode hanya mendengar di 127.0.0.1.
$DOMAIN {
	encode gzip zstd

	basic_auth {
		$AUTH_USERNAME $CADDY_HASH
	}

	reverse_proxy 127.0.0.1:$PORT
}
EOF
chmod 600 "$CADDY_FILE"

systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME.service"

info 'Setup selesai'
printf 'Mode: %s\nService: %s\nProject awal: %s\nPort loopback: %s\n' "$PROJECT_MODE" "$SERVICE_FILE" "$WORKING_DIRECTORY" "$PORT"
printf 'Caddyfile: %s\n' "$CADDY_FILE"
printf '\nLangkah berikutnya:\n'
printf '1. Pastikan DNS %s mengarah ke IP publik server dan port 80/443 terbuka.\n' "$DOMAIN"
printf '2. Salin isi %s ke Caddyfile utama atau file /etc/caddy/sites/%s.\n' "$CADDY_FILE" "$DOMAIN"
printf '3. Validasi dan reload: sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile && sudo systemctl reload caddy\n'
printf '4. Agar service user tetap berjalan setelah logout: loginctl enable-linger %s\n' "$USER"
printf '\nStatus: systemctl --user status %s\nLog: journalctl --user -u %s -f\n' "$SERVICE_NAME" "$SERVICE_NAME"
