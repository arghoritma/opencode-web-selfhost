# Wizard OpenCode Web Self-Host

`wizard.sh` mangrupikeun wizard interaktif kanggo ngajalankeun OpenCode Web di
server Linux ngalangkungan `opencode serve`, teras ngadamel site block Caddy
kalayan Basic Auth. OpenCode ngan ngadangukeun di `127.0.0.1`; aksés umum
ngalangkungan Caddy kalayan HTTPS.

Wizard ngadamel sareng langsung ngaktipkeun service `systemd --user`. Wizard
teu ngarobih, ngavalidasi, atanapi ngamuat ulang konfigurasi Caddy nu parantos
aktip.

## Sarat Samemeh Ngajalankeun

Mangga jalankeun wizard ku user Linux non-root anu badé ngajalankeun OpenCode
sareng anu ngagaduhan idin aksés kana project nu badé dibuka.

- Server Linux anu nganggo `systemd` sareng Bash 4 atanapi nu langkung énggal.
- Aksés terminal interaktif, upamana ngalangkungan SSH. Wizard teu tiasa
  dijalankeun dina sési tanpa TTY.
- OpenCode parantos dipasang sareng sayogi dina `PATH`.
- Caddy parantos dipasang. Wizard nganggo `caddy hash-password` kanggo ngadamel
  hash password, tapi teu ngarobih service atanapi konfigurasi Caddy.
- Pikeun aksés ngalangkungan domain: DNS `A` atanapi `AAAA` domain parantos
  nuju ka IP publik server, sareng port TCP `80` sareng `443` parantos kabuka.

Pasang OpenCode upami tacan sayogi:

```bash
curl -fsSL https://opencode.ai/install | bash
opencode --version
```

Pasang Caddy dina Ubuntu/Debian upami tacan sayogi:

```bash
sudo apt update
sudo apt install -y caddy
caddy version
```

## Ngajalankeun Wizard

Mangga jalankeun langsung tina GitHub tanpa kedah clone repository:

```bash
curl -fsSL https://raw.githubusercontent.com/arghoritma/opencode-web-selfhost/main/wizard.sh | bash
```

Atanapi saatos repository di-clone:

```bash
bash wizard.sh
```

Paréntah `curl | bash` tetep interaktif margi wizard nyandak jawaban tina
`/dev/tty`, sanes tina standard input pipe. Mangga jalankeun ngan saatos
mariksa eusi script tina sumber anu dipikantenang.

## Patarosan Dina Wizard

Wizard badé naroskeun nilai-nilai di handap:

| Patarosan | Katerangan |
| --- | --- |
| Mode project | `multi-project` atanapi `single-project`. |
| Path lengkep project | Ngan pikeun mode single, kedah diréktori absolut anu parantos aya, contona `/home/admin/project/myproject`. |
| Port OpenCode | Port antara `1024` dugi ka `65535`. Port ieu ngan kabuka dina loopback server. |
| Domain | Domain Caddy, contona `opencode.example.com`, tanpa `https://` atanapi path. |
| Username Basic Auth | Username kanggo login browser. Ngan hurup, angka, `.`, `_`, sareng `-`. |
| Password Basic Auth | Password dipénta dua kali, teras dirobih janten hash ku Caddy. Password plaintext teu disimpen dina file hasil wizard. |

### Mode Single-Project

OpenCode dijalankeun kalayan `WorkingDirectory` dina project anu dipilih.
Contona:

```text
/home/admin/project/myproject
```

Mode ieu merenah kanggo hiji repository atanapi hiji diréktori gawé utama.

### Mode Multi-Project

OpenCode dijalankeun kalayan home directory user janten `WorkingDirectory`.
Pilih mode ieu upami user service kedah muka sababaraha project anu aya dina
idin aksés user éta. Mangga pastikeun user ngan ngagaduhan aksés kana
repository sareng secret anu memang kenging dibuka tina OpenCode.

## File Nu Didamel

Saatos sadaya jawaban leres, wizard ngadamel:

| File | Kagunaan |
| --- | --- |
| `~/.config/systemd/user/opencode-web.service` | Service OpenCode anu ngajalankeun `opencode serve --hostname 127.0.0.1 --port <port>`. Service langsung di-enable sareng dijalankeun. |
| `~/<domain>.opencode.Caddyfile` | Hiji site block Caddy kanggo domain sareng port anu dipilih. File miboga permission `600` margi ngamuat hash Basic Auth. |

Upami file kalayan nami anu sami parantos aya, wizard badé naroskeun
konfirmasi samemeh nimpa file éta.

Conto lokasi hasil kanggo domain `opencode.example.com`:

```text
~/.config/systemd/user/opencode-web.service
~/opencode.example.com.opencode.Caddyfile
```

## Nerapkeun Caddyfile

Wizard ngahaja ngan nyiptakeun file Caddy sangkan anjeun tiasa milih struktur
konfigurasi Caddy anu dianggo ku server.

### Pilihan 1: Caddyfile Utama

Salin eusi file hasil wizard ka `/etc/caddy/Caddyfile`, bari tetep ngajaga site
block sareng global options anu parantos aya:

```bash
sudo nano /etc/caddy/Caddyfile
```

### Pilihan 2: Folder Sites

Upami Caddyfile utama parantos ngimpor folder sites, salin file hasil wizard ka
folder éta:

```bash
sudo install -d -m 755 /etc/caddy/sites
sudo install -o root -g caddy -m 640 "$HOME/opencode.example.com.opencode.Caddyfile" /etc/caddy/sites/opencode.example.com
```

Pastikeun `/etc/caddy/Caddyfile` ngagaduhan import di handap upami tacan aya:

```caddyfile
import /etc/caddy/sites/*
```

Samemeh nerapkeun parobihan, mangga validasi teras muat ulang Caddy:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo systemctl reload caddy
```

Bukakeun `https://opencode.example.com`, teras lebetkeun username sareng
password anu diasupkeun kana wizard.

## Ngatur Service

Pariksa status service:

```bash
systemctl --user status opencode-web
```

Tingalkeun log:

```bash
journalctl --user -u opencode-web -f
```

Ulang mimitian service upami diperyogikeun:

```bash
systemctl --user restart opencode-web
```

Eureunkeun atanapi jalankeun deui service:

```bash
systemctl --user stop opencode-web
systemctl --user start opencode-web
```

Sangkan service user tetep jalan saatos logout sareng nalika server boot,
aktipkeun linger sakali kanggo user éta:

```bash
loginctl enable-linger "$(whoami)"
```

## Kaamanan

- Ulah ngajalankeun OpenCode janten root.
- Ulah muka port OpenCode anu dipilih ka internet. Service ngan peryogi
  ngadangukeun di `127.0.0.1`; anu dibuka kanggo umum ngan TCP `80` sareng
  `443` kanggo Caddy.
- Basic Auth merenah kanggo aksés pribadi atanapi tim alit. Anggo auténtikasi
  anu langkung kuat sapertos SSO atanapi identity-aware proxy kanggo kabutuhan
  organisasi.
- Mangga pariksa idin repository sareng file rusiah sapertos `.env`, utamina
  nalika milih mode multi-project.
- Password plaintext teu disimpen ku wizard, nanging hash Basic Auth dina
  Caddyfile tetep data sénsitip. Ulah commit file hasil wizard kana Git atanapi
  ngabagikeunana.

## Milarian Pasualan

### `opencode` atanapi `caddy` teu kapendak

Pastikeun kadua paréntah sayogi kanggo user anu ngajalankeun wizard:

```bash
command -v opencode
command -v caddy
```

### Service teu tiasa dimimitian

Pariksa status sareng log service:

```bash
systemctl --user status opencode-web
journalctl --user -u opencode-web -n 100 --no-pager
```

Pariksa ogé naha port anu dipilih parantos dianggo ku prosés sanés:

```bash
ss -tlnp | grep '<port>'
```

Gentos `<port>` ku port anu diasupkeun kana wizard.

### Domain nembongkeun `502 Bad Gateway`

Pastikeun service OpenCode aktip sareng Caddy neraskeun ka port anu sami:

```bash
systemctl --user status opencode-web
sudo journalctl -u caddy -n 100 --no-pager
```

### HTTPS tacan diterbitkeun

Pastikeun domain nuju ka IP publik server, port `80` sareng `443` tiasa
diaksés tina internet, sareng Caddyfile valid:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo journalctl -u caddy -n 100 --no-pager
```
