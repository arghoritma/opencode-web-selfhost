# Setup OpenCode Web Server dengan Caddy + Password Auth

Panduan lengkap menjalankan OpenCode web di server dengan akses domain dan password authentication.

---

## Prasyarat

- Server Linux (Ubuntu/Debian)
- Domain sudah di-point ke IP server
- Akses sudo/root

---

## 1. Install OpenCode

```bash
curl -fsSL https://opencode.ai/install | bash
```

Verifikasi instalasi:

```bash
opencode --version
```

---

## 2. Setup OpenCode Web Service (Systemd)

### Buat service file

```bash
mkdir -p ~/.config/systemd/user
```

Buat file `~/.config/systemd/user/opencode-web.service`:

```ini
[Unit]
Description=OpenCode Web Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/$USER
ExecStart=/home/$USER/.opencode/bin/opencode web --port 4096
Restart=always
RestartSec=5
Environment=HOME=/home/$USER
Environment=PATH=/home/$USER/.opencode/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
```

> **Catatan:** Ganti `/home/$USER` dengan path home directory Anda (contoh: `/home/dev`).

### Enable dan jalankan service

```bash
systemctl --user daemon-reload
systemctl --user enable opencode-web
systemctl --user start opencode-web
```

### Pastikan service berjalan

```bash
systemctl --user status opencode-web
```

### Agar service tetap berjalan saat logout

```bash
loginctl enable-linger $(whoami)
```

### Perintah manajemen service

```bash
# Status
systemctl --user status opencode-web

# Stop
systemctl --user stop opencode-web

# Start
systemctl --user start opencode-web

# Restart
systemctl --user restart opencode-web

# Lihat log
journalctl --user -u opencode-web -f
```

---

## 3. Install Caddy

```bash
sudo apt install -y caddy
```

Verifikasi:

```bash
caddy version
```

---

## 4. Generate Password Hash

```bash
caddy hash-password
```

Ketik password yang diinginkan, lalu copy hash yang dihasilkan.

Contoh output:

```
$2a$14$7eZRw5me4Yi9PCzu0TqWQujPpYAaZWE7X8KXBAPUruRA5RWgKXJwu
```

---

## 5. Buat Config Caddy

### Buat folder untuk sites

```bash
sudo mkdir -p /etc/caddy/sites
```

### Buat config untuk domain

Buat file `/etc/caddy/sites/yourdomain.com`:

```caddyfile
yourdomain.com {
    basic_auth {
        opencode $2a$14$HASH_DARI_STEP_4
    }

    reverse_proxy localhost:4096

    @websocket {
        header Connection *Upgrade*
        header Upgrade websocket
    }
    reverse_proxy @websocket localhost:4096
}
```

**Penting:**

- Ganti `yourdomain.com` dengan domain Anda
- Ganti `$2a$14$HASH_DARI_STEP_4` dengan hash dari step 4
- Bagian websocket dibutuhkan agar OpenCode web bisa real-time

---

## 6. Konfigurasi Caddyfile

### Opsi A: Menggunakan Folder Sites (Disarankan)

Cocok untuk server dengan banyak domain.

#### Backup Caddyfile utama terlebih dahulu

```bash
sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak
```

#### Edit Caddyfile utama

```bash
sudo nano /etc/caddy/Caddyfile
```

#### Tambahkan import directive

Tambahkan `import /etc/caddy/sites/*` di akhir Caddyfile:

```caddyfile
{
    email admin@yourdomain.com
}

# Import semua config dari folder sites
import /etc/caddy/sites/*
```

#### Penjelasan

| Bagian                            | Fungsi                                   |
| --------------------------------- | ---------------------------------------- |
| `import /etc/caddy/sites/*`       | Import semua file config di folder sites |
| `/etc/caddy/sites/yourdomain.com` | Config khusus untuk domain OpenCode      |

#### Struktur yang dihasilkan

```
/etc/caddy/
├── Caddyfile              ← Config utama + import directive
└── sites/
    ├── yourdomain.com     ← Config OpenCode web
    └── *.com              ← Config domain lain (jika ada)
```

---

### Opsi B: Langsung di Caddyfile (Sederhana)

Cocok untuk server hanya dengan satu domain.

#### Backup Caddyfile utama

```bash
sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak
```

#### Edit Caddyfile utama

```bash
sudo nano /etc/caddy/Caddyfile
```

#### Tulis config langsung

```caddyfile
{
    email admin@yourdomain.com
}

yourdomain.com {
    basic_auth {
        opencode $2a$14$HASH_DARI_STEP_4
    }

    reverse_proxy localhost:4096

    @websocket {
        header Connection *Upgrade*
        header Upgrade websocket
    }
    reverse_proxy @websocket localhost:4096
}
```

**Penting:**

- Ganti `yourdomain.com` dengan domain Anda
- Ganti `$2a$14$HASH_DARI_STEP_4` dengan hash dari step 4
- Tidak perlu buat folder `/etc/caddy/sites/`

### Backup Caddyfile utama terlebih dahulu

```bash
sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak
```

### Edit Caddyfile utama

```bash
sudo nano /etc/caddy/Caddyfile
```

### Tambahkan import directive

Tambahkan `import /etc/caddy/sites/*` di akhir Caddyfile:

```caddyfile
{
    email admin@yourdomain.com
}

# Import semua config dari folder sites
import /etc/caddy/sites/*
```

### Penjelasan

| Bagian                            | Fungsi                                   |
| --------------------------------- | ---------------------------------------- |
| `import /etc/caddy/sites/*`       | Import semua file config di folder sites |
| `/etc/caddy/sites/yourdomain.com` | Config khusus untuk domain OpenCode      |

### Struktur yang dihasilkan

```
/etc/caddy/
├── Caddyfile              ← Config utama + import directive
└── sites/
    ├── yourdomain.com     ← Config OpenCode web
    └── *.com              ← Config domain lain (jika ada)
```

---

## 7. Reload Caddy

```bash
sudo systemctl reload caddy
```

Jika ada error:

```bash
sudo systemctl restart caddy
```

---

## 8. Pastikan Firewall Terbuka

```bash
sudo ufw allow 80
sudo ufw allow 443
```

---

## 9. Testing

### Cek status semua service

```bash
# OpenCode
systemctl --user status opencode-web

# Caddy
sudo systemctl status caddy
```

### Test dari terminal

```bash
curl -u opencode:passwordAnda https://yourdomain.com
```

### Test dari browser

Buka `https://yourdomain.com`

- **Username:** `opencode`
- **Password:** password yang digunakan saat generate hash

---

## 10. Troubleshooting

### Cek log Caddy

```bash
sudo journalctl -u caddy -f
```

### Cek log OpenCode

```bash
journalctl --user -u opencode-web -f
```

### Validasi config Caddy

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
```

### Cek apakah port terbuka

```bash
ss -tlnp | grep 4096
```

### Restart semua service

```bash
systemctl --user restart opencode-web
sudo systemctl restart caddy
```

---

## Struktur File

```
/etc/caddy/
├── Caddyfile                    # Config utama dengan import
└── sites/
    └── yourdomain.com             # Config untuk domain OpenCode

~/.config/systemd/user/
└── opencode-web.service         # Systemd service untuk OpenCode
```

---

## Perintah Cepat

```bash
# Restart OpenCode
systemctl --user restart opencode-web

# Restart Caddy
sudo systemctl restart caddy

# Lihat log OpenCode
journalctl --user -u opencode-web -f

# Lihat log Caddy
sudo journalctl -u caddy -f

# Cek status semua
systemctl --user status opencode-web && sudo systemctl status caddy
```
