# Wizard OpenCode Web Self-Host

`wizard.sh` adalah wizard interaktif untuk menjalankan OpenCode Web di server
Linux melalui `opencode serve`, kemudian menghasilkan site block Caddy dengan
Basic Auth. OpenCode hanya mendengar di `127.0.0.1`; akses publik dilakukan
melalui Caddy dengan HTTPS.

Wizard membuat dan langsung mengaktifkan service `systemd --user`. Wizard tidak
mengubah, memvalidasi, atau me-reload konfigurasi Caddy yang sudah aktif.

## Prasyarat

Jalankan wizard sebagai user Linux non-root yang akan menjalankan OpenCode dan
yang memiliki akses ke project yang akan dibuka.

- Server Linux yang memakai `systemd` dan Bash 4 atau lebih baru.
- Akses terminal interaktif, misalnya melalui SSH. Wizard tidak dapat dijalankan
  pada session tanpa TTY.
- OpenCode sudah terpasang dan tersedia pada `PATH`.
- Caddy sudah terpasang. Wizard memakai `caddy hash-password` untuk membuat
  hash password, tetapi tidak mengubah service atau konfigurasi Caddy.
- Untuk akses melalui domain: DNS `A` atau `AAAA` domain sudah mengarah ke IP
  publik server, serta port TCP `80` dan `443` terbuka.

Instal OpenCode bila belum tersedia:

```bash
curl -fsSL https://opencode.ai/install | bash
opencode --version
```

Instal Caddy pada Ubuntu/Debian bila belum tersedia:

```bash
sudo apt update
sudo apt install -y caddy
caddy version
```

## Menjalankan Wizard

Jalankan langsung dari GitHub tanpa clone repository:

```bash
curl -fsSL https://raw.githubusercontent.com/arghoritma/opencode-web-selfhost/main/wizard.sh | bash
```

Atau setelah repository di-clone:

```bash
bash wizard.sh
```

Perintah `curl | bash` tetap interaktif karena wizard mengambil jawaban dari
`/dev/tty`, bukan dari standard input pipe. Jalankan hanya setelah memeriksa
isi script dari sumber yang dipercaya.

## Pertanyaan Wizard

Wizard meminta nilai berikut:

| Pertanyaan | Keterangan |
| --- | --- |
| Mode project | `multi-project` atau `single-project`. |
| Full path project | Hanya untuk mode single, harus merupakan direktori absolut yang sudah ada, misalnya `/home/admin/project/myproject`. |
| Port OpenCode | Port antara `1024` sampai `65535`. Port ini hanya dibuka di loopback server. |
| Domain | Domain Caddy, misalnya `opencode.example.com`, tanpa `https://` atau path. |
| Username Basic Auth | Username untuk login browser. Hanya huruf, angka, `.`, `_`, dan `-`. |
| Password Basic Auth | Password diminta dua kali, lalu diubah menjadi hash oleh Caddy. Password plaintext tidak disimpan dalam file hasil wizard. |

### Mode Single-Project

OpenCode dijalankan dengan `WorkingDirectory` pada project yang dipilih. Contoh:

```text
/home/admin/project/myproject
```

Mode ini cocok untuk satu repository atau satu direktori kerja utama.

### Mode Multi-Project

OpenCode dijalankan dengan home directory user sebagai `WorkingDirectory`.
Pilih mode ini apabila user service harus membuka beberapa project yang berada
di bawah permission user tersebut. Pastikan user hanya memiliki akses ke
repository dan secret yang memang boleh dibuka dari OpenCode.

## File Yang Dibuat

Setelah semua jawaban valid, wizard membuat:

| File | Fungsi |
| --- | --- |
| `~/.config/systemd/user/opencode-web.service` | Service OpenCode yang menjalankan `opencode serve --hostname 127.0.0.1 --port <port>`. Service langsung di-enable dan dijalankan. |
| `~/<domain>.opencode.Caddyfile` | Satu site block Caddy untuk domain dan port yang dipilih. File memiliki permission `600` karena memuat hash Basic Auth. |

Jika file dengan nama yang sama sudah ada, wizard meminta konfirmasi sebelum
menimpanya.

Contoh lokasi output untuk domain `opencode.example.com`:

```text
~/.config/systemd/user/opencode-web.service
~/opencode.example.com.opencode.Caddyfile
```

## Menerapkan Caddyfile

Wizard sengaja hanya menghasilkan file Caddy agar Anda dapat memilih struktur
konfigurasi Caddy yang dipakai server.

### Opsi 1: Caddyfile Utama

Salin isi file hasil wizard ke `/etc/caddy/Caddyfile`, dengan tetap menjaga
site block dan global options yang sudah ada:

```bash
sudo nano /etc/caddy/Caddyfile
```

### Opsi 2: Folder Sites

Jika Caddyfile utama sudah mengimpor folder sites, salin file hasil wizard ke
folder tersebut:

```bash
sudo install -d -m 755 /etc/caddy/sites
sudo install -o root -g caddy -m 640 "$HOME/opencode.example.com.opencode.Caddyfile" /etc/caddy/sites/opencode.example.com
```

Pastikan `/etc/caddy/Caddyfile` memiliki import berikut jika belum ada:

```caddyfile
import /etc/caddy/sites/*
```

Sebelum menerapkan perubahan, validasi kemudian reload Caddy:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo systemctl reload caddy
```

Buka `https://opencode.example.com` dan masukkan username serta password yang
Anda masukkan ke wizard.

## Service Management

Periksa status service:

```bash
systemctl --user status opencode-web
```

Lihat log:

```bash
journalctl --user -u opencode-web -f
```

Restart service setelah diperlukan:

```bash
systemctl --user restart opencode-web
```

Hentikan atau jalankan kembali service:

```bash
systemctl --user stop opencode-web
systemctl --user start opencode-web
```

Agar service user tetap berjalan setelah logout dan saat server boot, aktifkan
linger sekali untuk user tersebut:

```bash
loginctl enable-linger "$(whoami)"
```

## Keamanan

- Jangan menjalankan OpenCode sebagai root.
- Jangan membuka port OpenCode yang dipilih ke internet. Service hanya perlu
  mendengar di `127.0.0.1`; yang dibuka secara publik hanyalah TCP `80` dan
  `443` untuk Caddy.
- Basic Auth cocok untuk akses pribadi atau tim kecil. Gunakan autentikasi yang
  lebih kuat seperti SSO atau identity-aware proxy untuk kebutuhan organisasi.
- Review permission repository dan file rahasia seperti `.env`, terutama saat
  memilih mode multi-project.
- Password plaintext tidak disimpan wizard, tetapi hash Basic Auth pada
  Caddyfile tetap merupakan data sensitif. Jangan commit file hasil wizard ke
  Git atau membagikannya.

## Troubleshooting

### `opencode` atau `caddy` tidak ditemukan

Pastikan kedua command tersedia untuk user yang menjalankan wizard:

```bash
command -v opencode
command -v caddy
```

### Service gagal dimulai

Periksa status dan log service:

```bash
systemctl --user status opencode-web
journalctl --user -u opencode-web -n 100 --no-pager
```

Periksa juga apakah port yang dipilih sudah dipakai proses lain:

```bash
ss -tlnp | grep '<port>'
```

Ganti `<port>` dengan port yang dimasukkan ke wizard.

### Domain menampilkan `502 Bad Gateway`

Pastikan service OpenCode aktif dan Caddy meneruskan ke port yang sama:

```bash
systemctl --user status opencode-web
sudo journalctl -u caddy -n 100 --no-pager
```

### HTTPS belum diterbitkan

Pastikan domain mengarah ke IP publik server, port `80` dan `443` dapat diakses
dari internet, dan Caddyfile valid:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo journalctl -u caddy -n 100 --no-pager
```
