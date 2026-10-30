# NetHunter Rootless Toolkit — Moto G Stylus 2024

Polished setup for a **non-rooted** Moto G Stylus 2024 (stock Android 14/15) running **Termux (F-Droid)** + **Kali NetHunter Rootless**.

> **Legal / ethics:** Use this kit **only** on devices and networks you own or have **explicit written permission** to test. Unauthorized access, interception, or disruption of networks/devices is illegal. The authors assume no liability for misuse.

## What you get

| Piece | Purpose |
|-------|---------|
| `setup.sh` | Idempotent Termux → NetHunter Rootless → curated tools installer |
| `btcap.sh` | Pull HCI snoop via `adb bugreport` (wireless debugging), parse with `btsnoop_parser`, dump GATT to TSV |
| `shortcuts/` | Termux:Widget scripts: start KeX, capture BT, quick LAN `/24` ping-scan |
| This README | Limits of rootless, ADB pairing notes, legal reminder |

## One-liner bootstrap (Termux)

Verified tarball (recommended):

```bash
pkg install -y curl tar && \
curl -fsSL -o nethunter-kit.tgz \
  https://github.com/blake2232/nethunter-rootless-kit/releases/download/v1.0.0/nethunter-kit.tgz && \
echo '0dfc52ddf43cf8b1b51d99a7d7e54de443195658114182c641fb88ea6e9f7b7c  nethunter-kit.tgz' | sha256sum -c - && \
tar -xzf nethunter-kit.tgz && cd nethunter-kit && bash setup.sh
```

Clone alternative:

```bash
pkg install -y git && \
git clone https://github.com/blake2232/nethunter-rootless-kit.git ~/nethunter-kit && \
cd ~/nethunter-kit && bash setup.sh
```

Repo: https://github.com/blake2232/nethunter-rootless-kit  
Release: https://github.com/blake2232/nethunter-rootless-kit/releases/tag/v1.0.0  
**SHA256** (`nethunter-kit.tgz`): `0dfc52ddf43cf8b1b51d99a7d7e54de443195658114182c641fb88ea6e9f7b7c`

## Prerequisites

1. **Termux from F-Droid** (not Play Store — different signing/keys).
2. Optional but recommended from [NetHunter Store](https://store.nethunter.com): **NetHunter KeX**, **Hacker’s Keyboard**.
3. Several GB free storage (NetHunter rootfs alone is ~1–2+ GB; heavy tools more).
4. For BT capture: Developer options → **Wireless debugging** + **Bluetooth HCI snoop log**.

## Setup

```bash
bash setup.sh           # interactive; asks about heavy packages
bash setup.sh --light   # skip metasploit/hashcat/john
bash setup.sh --full -y # non-interactive + heavy tools
bash setup.sh --skip-nethunter --only-kali   # tools only
bash setup.sh --only-shortcuts
```

Official NetHunter Rootless method (confirmed against
https://www.kali.org/docs/nethunter/nethunter-rootless/ ):

```bash
termux-setup-storage
pkg install wget
wget -O install-nethunter-termux https://offs.ec/2MceZWr
chmod +x install-nethunter-termux
./install-nethunter-termux
```

`setup.sh` wraps that, then installs tools inside the chroot with `nethunter -r` / `nh -r`.

### Packages installed

**Termux:** `wget`, `git`, `python`, `android-tools`, `root-repo`, then `tshark` / `termshark` / `jq` / `termux-api` when available.

**Kali (core):** `nmap`, `sqlmap`, `hydra`, `nikto`, `gobuster`, `ffuf`, `whatweb`, `tshark`, `wireshark-common`, `bluez` / `bluez-tools`, `python3-pip`, plus pip: `btsnoop-parser`, `bleak`, `scapy`.

**Kali (optional / heavy via `--full`):** `metasploit-framework`, `hashcat` (CPU), `john`.

## KeX (desktop)

```bash
nh kex passwd      # once
nh kex &           # or widget: start-kex
# Open NetHunter KeX app → connect (set resolution under Advanced)
nh kex stop
```

## Bluetooth HCI capture (`btcap.sh`)

### Enable snoop

Settings → **Developer options** → **Enable Bluetooth HCI snoop log** → ON  
Toggle Bluetooth off/on, reproduce the traffic you care about.

### Wireless debugging (phone → itself)

1. Developer options → **Wireless debugging** → ON  
2. **Pair device with pairing code** → note `IP:PAIR_PORT` + 6-digit code  
3. Termux:

```bash
adb pair <IP>:<PAIR_PORT>     # enter code
adb connect <IP>:<PORT>       # connection port from the main Wireless debugging screen
adb devices                   # expect "device"
```

4. Capture:

```bash
~/bin/btcap.sh
# or:  ~/bin/btcap.sh --connect <IP>:<PORT>
# or widget: capture-bt
```

### Outputs

Under `~/storage/downloads/btcap/<timestamp>/` (fallback `~/btcap-out/`):

| File | Contents |
|------|----------|
| `bugreport.zip` | Raw `adb bugreport` |
| `btsnoop_hci.log` | Extracted `FS/data/misc/bluetooth/logs/btsnoop_hci.log*` |
| `report.txt` | `btsnoop_parser LOG --report` |
| `capture.pcap` | `btsnoop_parser LOG --pcap capture.pcap` (DLT 201) |
| `gatt_writes.tsv` | tshark ATT Write* |
| `gatt_notifications.tsv` | tshark ATT Notification/Indication |

Verified CLI (btsnoop-parser ≥0.9 / 0.10):

```bash
btsnoop_parser capture.log --report
btsnoop_parser capture.log --pcap full.pcap
```

## Termux:Widget

Install **Termux:Widget** (F-Droid). `setup.sh` installs into `~/.shortcuts/`:

| Shortcut | Action |
|----------|--------|
| `start-kex` | `nh -r kex` |
| `capture-bt` | runs `btcap.sh` if adb device present |
| `lan-scan` | `nmap -sn` on current `wlan0` address’s `/24` |

## What works without root (Rootless)

| Works | Notes |
|-------|-------|
| Full Kali userspace (proot) | Most CLI pentest tools |
| KeX desktop | Via NetHunter KeX VNC client |
| `nmap` (TCP/UDP connect, scripts) | No raw SYN without capabilities — still very useful |
| Metasploit | Works; **no DB support** in rootless (per Kali docs) |
| sqlmap, hydra, nikto, gobuster/ffuf, whatweb | Fine |
| john / hashcat (CPU) | Fine; GPU/OpenCL on phone is limited/absent |
| tshark / termshark on pcaps | Fine |
| BLE central via `bleak` | App-level BLE from Python |
| BT HCI analysis via bugreport + `btsnoop_parser` | Best-in-class for rootless BT visibility |
| `adb` wireless debugging | Self-debug / bugreport |

## What does **not** work without a custom kernel / root

| Needs custom kernel / NetHunter kernel | Why |
|----------------------------------------|-----|
| Wi-Fi **monitor mode / injection** | Stock `wlan` driver/firmware |
| HID keyboard attacks (USB/BT HID gadgets) | Needs HID gadget / NetHunter kernel patches |
| Internal Wi-Fi frame capture | Same as monitor mode |
| Some raw packet sockets / `top`-like tools | Documented rootless limits |
| Full BlueZ controller mgmt | Partial; HCI snoop via Android is the reliable path |

Moto G Stylus 2024 stock builds do **not** ship a NetHunter kernel. Do **not** unlock/root unless you accept warranty/banking-app risk — this kit is specifically for the rootless path.

## Tips (from Kali docs + field notes)

- After install: `nh -r apt update && nh -r apt full-upgrade -y`
- Backup rootfs from Termux:  
  `tar -cJf kali-arm64.tar.xz kali-arm64 && mv kali-arm64.tar.xz storage/downloads`
- Abbreviation: `nh` ≡ `nethunter`
- Galaxy note in upstream docs about `sudo` does not apply to Motos the same way; prefer `nh -r …`

## Disclaimer

This toolkit is for **education and authorized security testing** of systems you own or are paid/contracted to assess. Do not use it to attack others’ devices, cars, locks, networks, or accounts. Respect local law (US CFAA and equivalents).
