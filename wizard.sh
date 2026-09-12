#!/usr/bin/env bash
# Interactive setup for an OpenCode web service and a standalone Caddy site block.
set -euo pipefail

SERVICE_NAME="opencode-web"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/$SERVICE_NAME.service"

die() {
  printf 'Lepat: %s\n' "$*" >&2
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
  [[ -r /dev/tty && -w /dev/tty ]] || die 'Wizard ieu interaktif sareng peryogi terminal. Mangga jalankeun tina sési SSH/terminal.'
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' tidak ditemukan. $2"
}

[[ ${BASH_VERSINFO[0]} -ge 4 ]] || die 'Bash 4 atanapi nu langkung énggal diperyogikeun.'
[[ $(uname -s) == Linux ]] || die 'Wizard ieu ngan ngarojong server Linux.'
require_tty
require_command systemctl 'Mangga pastikeun server nganggo systemd.'
require_command opencode 'Mangga pasang heula: curl -fsSL https://opencode.ai/install | bash'
require_command caddy 'Mangga pasang Caddy heula sangkan password tiasa di-hash.'

OPENCODE_BIN=$(command -v opencode)

info 'Pangaturan OpenCode Web'
printf '%s\n' 'Service badé dijalankeun ku user ayeuna sareng ngan ngadangukeun di 127.0.0.1.'
printf '%s\n' 'Caddyfile badé didamel jadi file misah; konfigurasi Caddy nu aktip moal dirobih.'

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
        PROJECT_PATH=$(read_input 'Path lengkep project (contoh /home/admin/project/myproject): ')
        [[ -n $PROJECT_PATH ]] || { printf '%s\n' 'Path teu kénging kosong.' >/dev/tty; continue; }
        [[ $PROJECT_PATH = /* ]] || { printf '%s\n' 'Mangga anggo path absolut.' >/dev/tty; continue; }
        [[ -d $PROJECT_PATH ]] || { printf '%s\n' 'Diréktori project teu kapendak.' >/dev/tty; continue; }
        [[ $PROJECT_PATH != *$'\n'* ]] || { printf '%s\n' 'Path teu kénging ngandung baris anyar.' >/dev/tty; continue; }
        WORKING_DIRECTORY=$PROJECT_PATH
        break
      done
      break
      ;;
    *) printf '%s\n' 'Mangga pilih 1 atanapi 2.' >/dev/tty ;;
  esac
done

while true; do
  PORT=$(read_input 'Port OpenCode (1024-65535): ')
  if [[ $PORT =~ ^[0-9]+$ ]] && (( PORT >= 1024 && PORT <= 65535 )); then
    break
  fi
  printf '%s\n' 'Port kedah mangrupa angka antara 1024 dugi ka 65535.' >/dev/tty
done

while true; do
  DOMAIN=$(read_input 'Domain (contoh opencode.example.com): ')
  if [[ $DOMAIN =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; then
    break
  fi
  printf '%s\n' 'Mangga lebetkeun domain nu valid tanpa http:// atanapi path.' >/dev/tty
done

while true; do
  AUTH_USERNAME=$(read_input 'Username Basic Auth: ')
  if [[ $AUTH_USERNAME =~ ^[A-Za-z0-9._-]+$ ]]; then
    break
  fi
  printf '%s\n' 'Username ngan kénging hurup, angka, titik, garis handap, atanapi strip.' >/dev/tty
done

while true; do
  AUTH_PASSWORD=$(read_secret 'Password Basic Auth: ')
  [[ -n $AUTH_PASSWORD ]] || { printf '%s\n' 'Password teu kénging kosong.' >/dev/tty; continue; }
  AUTH_PASSWORD_CONFIRM=$(read_secret 'Lebetkeun deui password: ')
  [[ $AUTH_PASSWORD == "$AUTH_PASSWORD_CONFIRM" ]] && break
  printf '%s\n' 'Password henteu sarua, mangga cobian deui.' >/dev/tty
done
unset AUTH_PASSWORD_CONFIRM

CADDY_HASH=$(printf '%s' "$AUTH_PASSWORD" | caddy hash-password)
unset AUTH_PASSWORD
CADDY_FILE="$HOME/${DOMAIN}.opencode.Caddyfile"

if [[ -e $SERVICE_FILE ]] && ! confirm "Service $SERVICE_FILE parantos aya sareng badé ditimpa. Teraskeun?"; then
  die 'Dibatalkeun. Teu aya parobihan nu didamel.'
fi
if [[ -e $CADDY_FILE ]] && ! confirm "Caddyfile $CADDY_FILE parantos aya sareng badé ditimpa. Teraskeun?"; then
  die 'Dibatalkeun. Teu aya parobihan nu didamel.'
fi

info 'Nuju ngadamel service sareng Caddyfile'
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
# Tambihkeun site block ieu ka /etc/caddy/Caddyfile atanapi /etc/caddy/sites/$DOMAIN.
# Ulah muka port $PORT ka internet; OpenCode ngan ngadangukeun di 127.0.0.1.
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

info 'Pangaturan parantos réngsé'
printf 'Mode: %s\nService: %s\nProject awal: %s\nPort loopback: %s\n' "$PROJECT_MODE" "$SERVICE_FILE" "$WORKING_DIRECTORY" "$PORT"
printf 'Caddyfile: %s\n' "$CADDY_FILE"
printf '\nLéngkah salajengna:\n'
printf '1. Pastikeun DNS %s nuju ka IP publik server sareng port 80/443 kabuka.\n' "$DOMAIN"
printf '2. Salin eusi %s ka Caddyfile utama atanapi file /etc/caddy/sites/%s.\n' "$CADDY_FILE" "$DOMAIN"
printf '3. Validasi sareng reload: sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile && sudo systemctl reload caddy\n'
printf '4. Sangkan service user tetep jalan sanggeus logout: loginctl enable-linger %s\n' "$USER"
printf '\nStatus: systemctl --user status %s\nLog: journalctl --user -u %s -f\n' "$SERVICE_NAME" "$SERVICE_NAME"
