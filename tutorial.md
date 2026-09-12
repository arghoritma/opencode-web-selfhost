# Menjalankan OpenCode Web dengan systemd per Repository

Panduan ini menjalankan OpenCode sebagai layanan Linux yang selalu aktif melalui `systemd`. Setiap layanan diarahkan ke satu repository dan dibatasi agar tidak dapat menulis ke lokasi lain selain repository tersebut dan direktori konfigurasi OpenCode yang diperlukan.

## Hasil Akhir

Setelah selesai, Anda akan memiliki:

- OpenCode Web yang berjalan otomatis di server.
- Satu layanan untuk satu repository.
- Akses web aman melalui SSH tunnel.
- Pembatasan filesystem menggunakan sandbox `systemd`.
- Kemampuan menambahkan repository lain melalui service dan port terpisah.

Contoh pada panduan ini:

| Nilai                 | Contoh                     |
| --------------------- | -------------------------- |
| User Linux            | `opencode`                 |
| Repository utama      | `/srv/repos/project-utama` |
| Port repository utama | `4096`                     |
| Repository kedua      | `/srv/repos/project-kedua` |
| Port repository kedua | `4097`                     |

Ganti nilai contoh tersebut sesuai lingkungan Anda.

## Prasyarat

- Server Linux yang memakai `systemd`.
- OpenCode sudah terpasang dan bisa dijalankan oleh user service.
- Repository Git sudah tersedia di server.
- Akses SSH ke server.
- Hak `sudo` untuk membuat user, direktori, dan file unit systemd.

Periksa lokasi executable OpenCode:

```bash
command -v opencode
```

Simpan hasilnya. Contoh panduan ini menggunakan `/usr/local/bin/opencode`; gunakan hasil perintah Anda pada `ExecStart` bila berbeda.

## 1. Buat User Khusus Service

Gunakan user tanpa akses login untuk mengurangi cakupan akses OpenCode:

```bash
sudo useradd --system --create-home --home-dir /var/lib/opencode --shell /usr/sbin/nologin opencode
```

Jika `opencode` perlu mengakses repository yang sudah ada, pastikan user tersebut menjadi pemilik atau setidaknya memiliki izin baca-tulis ke repository itu.

```bash
sudo mkdir -p /srv/repos
sudo chown -R opencode:opencode /srv/repos/project-utama
```

Jika repository belum tersedia, clone menggunakan user service:

```bash
sudo -u opencode git clone https://example.com/organisasi/project-utama.git /srv/repos/project-utama
```

## 2. Siapkan Direktori Data OpenCode

OpenCode memerlukan direktori home dan konfigurasi yang dapat ditulis.

```bash
sudo install -d -o opencode -g opencode -m 700 /var/lib/opencode/.config/opencode
sudo install -d -o opencode -g opencode -m 700 /var/lib/opencode/.local/share/opencode
```

Login atau konfigurasikan provider/model OpenCode menggunakan user service. Jalankan perintah sesuai metode autentikasi provider yang digunakan:

```bash
sudo -u opencode -H opencode providers
```

Jangan menaruh API key langsung di file unit `systemd`. Gunakan secret manager, credential systemd, atau file environment dengan permission ketat bila provider membutuhkan environment variable.

## 3. Buat Service untuk Repository Utama

Buat file `/etc/systemd/system/opencode-project-utama.service`:

```ini
[Unit]
Description=OpenCode Web - project-utama
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=opencode
Group=opencode
WorkingDirectory=/srv/repos/project-utama
Environment=HOME=/var/lib/opencode
Environment=XDG_CONFIG_HOME=/var/lib/opencode/.config
Environment=XDG_DATA_HOME=/var/lib/opencode/.local/share
ExecStart=/usr/local/bin/opencode serve --hostname 127.0.0.1 --port 4096
Restart=on-failure
RestartSec=5

# Sandbox filesystem: root filesystem read-only, kecuali path yang diperlukan.
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/srv/repos/project-utama
ReadWritePaths=/var/lib/opencode/.config/opencode
ReadWritePaths=/var/lib/opencode/.local/share/opencode

[Install]
WantedBy=multi-user.target
```

Penting:

- Gunakan `opencode serve`, bukan `opencode web`. Opsi `web` mencoba membuka browser pada mesin server, sedangkan `serve` cocok untuk layanan tanpa antarmuka grafis.
- `WorkingDirectory` menentukan repository yang menjadi project awal service.
- `--hostname 127.0.0.1` membuat server hanya bisa diakses dari server itu sendiri. Jangan menggantinya menjadi `0.0.0.0` kecuali Anda menambahkan autentikasi dan TLS pada reverse proxy.
- `ReadWritePaths` membatasi lokasi yang dapat ditulis. Tambahkan hanya direktori yang benar-benar dibutuhkan.

Muat ulang konfigurasi dan aktifkan service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now opencode-project-utama.service
sudo systemctl status opencode-project-utama.service
```

Lihat log jika service gagal berjalan:

```bash
sudo journalctl -u opencode-project-utama.service -f
```

## 4. Akses UI dengan SSH Tunnel

Dari komputer lokal Anda, buat tunnel menuju port loopback pada server:

```bash
ssh -N -L 4096:127.0.0.1:4096 USER_SSH@NAMA_ATAU_IP_SERVER
```

Biarkan terminal tersebut tetap berjalan, kemudian buka di browser lokal:

```text
http://127.0.0.1:4096
```

Untuk tunnel di background:

```bash
ssh -fN -L 4096:127.0.0.1:4096 USER_SSH@NAMA_ATAU_IP_SERVER
```

SSH tunnel mengenkripsi koneksi dan tidak mengekspos OpenCode langsung ke jaringan publik.

## 5. Publikasikan melalui Domain dengan Caddy dan Basic Auth

Bagian ini adalah alternatif SSH tunnel apabila OpenCode harus dapat diakses melalui domain. Caddy bertindak sebagai reverse proxy, menerbitkan HTTPS otomatis, dan meminta username serta password sebelum request diteruskan ke OpenCode.

### 5.1. Siapkan DNS dan firewall

Buat DNS record `A` untuk domain, misalnya `opencode.example.com`, yang mengarah ke IP publik server. Pastikan port TCP `80` dan `443` dibuka pada firewall atau security group server. Caddy memerlukan port tersebut untuk menerbitkan dan memperbarui sertifikat TLS secara otomatis.

Contoh firewall UFW:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Jangan membuka port `4096` atau `4097` ke internet. Service OpenCode tetap memakai `--hostname 127.0.0.1`, sehingga hanya Caddy pada server yang dapat menjangkaunya.

### 5.2. Instal Caddy

Instal Caddy menggunakan paket resmi untuk distribusi Linux Anda. Pada Debian atau Ubuntu, ikuti repositori paket resmi Caddy agar versi dan pembaruan keamanan dikelola oleh sistem paket:

```bash
sudo apt update
sudo apt install -y caddy
```

Setelah terinstal, periksa service Caddy:

```bash
sudo systemctl status caddy
```

### 5.3. Buat hash password

Direktif Caddy `basic_auth` tidak menerima password plaintext. Buat hash password dengan perintah berikut, lalu simpan seluruh hasilnya termasuk awalan seperti `$2a$...`:

```bash
caddy hash-password --plaintext 'GANTI_DENGAN_PASSWORD_KUAT'
```

Gunakan password unik dan panjang. Jangan masukkan password plaintext ke `Caddyfile`, riwayat shell, Git, atau dokumentasi.

### 5.4. Konfigurasikan Caddyfile

Edit `/etc/caddy/Caddyfile` dan gunakan konfigurasi berikut. Ganti domain, username, dan hash password:

```caddyfile
opencode.example.com {
	encode gzip zstd

	# Seluruh UI OpenCode memerlukan username dan password.
	basic_auth {
		admin GANTI_DENGAN_HASH_PASSWORD_CADDY
	}

	# OpenCode hanya mendengar pada loopback server.
	reverse_proxy 127.0.0.1:4096
}
```

Keterangan:

- Caddy otomatis meminta dan memperbarui sertifikat HTTPS ketika domain mengarah ke server serta port `80` dan `443` dapat dijangkau dari internet.
- `basic_auth` meminta browser menampilkan dialog username/password. Password yang disimpan adalah hash, bukan plaintext.
- Setelah autentikasi berhasil, Caddy meneruskan request ke `127.0.0.1:4096` dan OpenCode tidak diekspos secara langsung.
- Gunakan Caddy versi 2.8 atau lebih baru, yang memakai nama direktif `basic_auth`. Pada versi lama, nama direktifnya adalah `basicauth`.

Validasi konfigurasi sebelum menerapkannya:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

Jika valid, reload Caddy tanpa memutus koneksi yang sedang aktif:

```bash
sudo systemctl reload caddy
sudo systemctl status caddy
```

Buka:

```text
https://opencode.example.com
```

Masukkan username `admin` dan password plaintext yang digunakan ketika membuat hash.

### 5.5. Domain untuk Repository Kedua

Jika service `opencode-project-kedua.service` berjalan pada port `4097`, tambahkan site block terpisah dalam `/etc/caddy/Caddyfile`:

```caddyfile
opencode-project-kedua.example.com {
	encode gzip zstd

	basic_auth {
		admin GANTI_DENGAN_HASH_PASSWORD_PROJECT_KEDUA
	}

	reverse_proxy 127.0.0.1:4097
}
```

Buat DNS record `A` untuk `opencode-project-kedua.example.com`, lalu validasi dan reload:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo systemctl reload caddy
```

Gunakan password terpisah untuk setiap domain atau repository agar akses dapat dicabut secara independen.

### 5.6. Pemeriksaan keamanan reverse proxy

Pastikan hal-hal berikut tetap berlaku setelah Caddy diaktifkan:

| Pemeriksaan | Kondisi yang diharapkan                                                   |
| ----------- | ------------------------------------------------------------------------- |
| OpenCode    | Menggunakan `--hostname 127.0.0.1`, tidak memakai `0.0.0.0`.              |
| Firewall    | Hanya TCP `22`, `80`, dan `443` dibuka secara publik sesuai kebutuhan.    |
| Caddyfile   | Memuat hash password, tidak pernah password plaintext.                    |
| HTTPS       | URL domain menggunakan `https://` dan sertifikat valid.                   |
| systemd     | `ReadWritePaths` setiap instance hanya menunjuk repository masing-masing. |
| Caddyfile   | Permission root-only, karena berisi hash kredensial.                      |

Atur permission Caddyfile agar hanya root yang dapat mengubah atau membacanya:

```bash
sudo chown root:caddy /etc/caddy/Caddyfile
sudo chmod 640 /etc/caddy/Caddyfile
```

Basic Auth cocok untuk akses pribadi atau tim kecil. Untuk kebutuhan organisasi, SSO, audit user yang lebih baik, MFA, atau pencabutan akses per user, gunakan identity-aware proxy atau autentikasi perusahaan di depan Caddy.

## 6. Menambahkan Repository Lain

Cara paling aman untuk membuka project lain adalah menjalankan instance OpenCode terpisah. Ini membuat setiap instance punya working directory, port, dan batas filesystem sendiri.

Siapkan repository kedua:

```bash
sudo chown -R opencode:opencode /srv/repos/project-kedua
```

Buat `/etc/systemd/system/opencode-project-kedua.service`:

```ini
[Unit]
Description=OpenCode Web - project-kedua
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=opencode
Group=opencode
WorkingDirectory=/srv/repos/project-kedua
Environment=HOME=/var/lib/opencode
Environment=XDG_CONFIG_HOME=/var/lib/opencode/.config
Environment=XDG_DATA_HOME=/var/lib/opencode/.local/share
ExecStart=/usr/local/bin/opencode serve --hostname 127.0.0.1 --port 4097
Restart=on-failure
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/srv/repos/project-kedua
ReadWritePaths=/var/lib/opencode/.config/opencode
ReadWritePaths=/var/lib/opencode/.local/share/opencode

[Install]
WantedBy=multi-user.target
```

Aktifkan instance kedua:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now opencode-project-kedua.service
sudo systemctl status opencode-project-kedua.service
```

Buat SSH tunnel kedua dari komputer lokal:

```bash
ssh -N -L 4097:127.0.0.1:4097 USER_SSH@NAMA_ATAU_IP_SERVER
```

Buka repository kedua pada browser:

```text
http://127.0.0.1:4097
```

## 7. Memahami Batasan "Project Terkunci"

`WorkingDirectory` hanya menentukan project awal, bukan mekanisme keamanan penuh. Penguncian akses dicapai dengan beberapa lapisan berikut:

| Lapisan                | Fungsi                                                       |
| ---------------------- | ------------------------------------------------------------ |
| User `opencode`        | User hanya diberi permission pada repository yang diizinkan. |
| `ProtectSystem=strict` | Membuat filesystem sistem menjadi read-only untuk service.   |
| `ProtectHome=true`     | Menyembunyikan direktori home biasa dari service.            |
| `ReadWritePaths`       | Hanya path yang terdaftar yang dapat ditulis.                |
| `WorkingDirectory`     | Menetapkan repository awal untuk masing-masing instance.     |
| SSH tunnel             | Menghindari paparan server OpenCode ke jaringan publik.      |

Perhatikan bahwa pembatasan tulis tidak selalu berarti pembatasan baca. Jika repository bersifat rahasia, pastikan permission user `opencode` hanya memberikan akses ke repository yang memang boleh dibuka. Hindari menambahkan `ReadOnlyPaths` secara luas tanpa memahami data mana yang akan ikut dapat dibaca.

## 8. Operasi Service

Mulai service:

```bash
sudo systemctl start opencode-project-utama.service
```

Hentikan service:

```bash
sudo systemctl stop opencode-project-utama.service
```

Restart setelah mengubah unit file:

```bash
sudo systemctl daemon-reload
sudo systemctl restart opencode-project-utama.service
```

Periksa status:

```bash
sudo systemctl status opencode-project-utama.service
```

Lihat log terbaru:

```bash
sudo journalctl -u opencode-project-utama.service -n 100 --no-pager
```

Nonaktifkan saat boot:

```bash
sudo systemctl disable --now opencode-project-utama.service
```

## Troubleshooting

### Service gagal dengan `status=203/EXEC`

Lokasi executable pada `ExecStart` salah atau tidak dapat dieksekusi. Periksa dengan:

```bash
command -v opencode
sudo -u opencode -H command -v opencode
```

Ganti `/usr/local/bin/opencode` pada file service dengan path yang benar, lalu jalankan `sudo systemctl daemon-reload` dan restart service.

### OpenCode tidak dapat menulis file atau menyimpan sesi

Periksa log service dan pastikan direktori repository serta direktori `/var/lib/opencode` dimiliki oleh user `opencode`:

```bash
sudo chown -R opencode:opencode /srv/repos/project-utama /var/lib/opencode
```

Pastikan lokasi yang dibutuhkan juga tercantum di `ReadWritePaths`.

### Browser tidak dapat membuka `http://127.0.0.1:4096`

Pastikan service aktif dan SSH tunnel berjalan pada komputer lokal:

```bash
sudo systemctl status opencode-project-utama.service
```

Pastikan port lokal yang dipakai tunnel belum digunakan aplikasi lain. Jika sudah digunakan, gunakan port lokal lain, misalnya:

```bash
ssh -N -L 14096:127.0.0.1:4096 USER_SSH@NAMA_ATAU_IP_SERVER
```

Kemudian buka `http://127.0.0.1:14096`.

### Domain Caddy menampilkan `502 Bad Gateway`

Pastikan service OpenCode target aktif dan port yang dikonfigurasi sesuai:

```bash
sudo systemctl status opencode-project-utama.service
sudo journalctl -u caddy -n 100 --no-pager
```

Untuk `opencode.example.com`, Caddy harus meneruskan ke `127.0.0.1:4096`. Untuk domain repository kedua, gunakan `127.0.0.1:4097`.

### HTTPS belum terbit atau domain tidak dapat diakses

Pastikan DNS record domain sudah mengarah ke IP publik yang benar, port `80` dan `443` dapat dijangkau dari internet, serta Caddyfile valid:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo journalctl -u caddy -n 100 --no-pager
```

## Catatan Keamanan

- Jangan menjalankan service sebagai `root`.
- Jangan gunakan `--auto` kecuali Anda memahami konsekuensi persetujuan otomatis terhadap aksi agent.
- Jangan mengekspos port OpenCode ke internet secara langsung; publikasikan hanya melalui Caddy dengan HTTPS dan autentikasi.
- Gunakan SSH key dan nonaktifkan password login SSH jika memungkinkan.
- Tinjau permission repository dan secret seperti `.env` sebelum memberikan akses kepada user service.
- Pisahkan service per repository untuk menjaga batas akses tetap sederhana dan dapat diaudit.
