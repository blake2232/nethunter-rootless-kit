#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# NetHunter Rootless Toolkit — setup.sh
# Target: NON-rooted Moto G Stylus 2024 (stock Android 14/15) + Termux (F-Droid)
# Idempotent. Safe to re-run. Legitimate testing of YOUR devices/networks only.
# =============================================================================
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NH_INSTALLER_URL="https://offs.ec/2MceZWr"
NH_DOCS_URL="https://www.kali.org/docs/nethunter/nethunter-rootless/"
MARKER_DIR="${HOME}/.nethunter-kit"
MARKER="${MARKER_DIR}/.setup-complete"
LOG_FILE="${MARKER_DIR}/setup.log"

# ---- flags / defaults -------------------------------------------------------
SKIP_NETHUNTER=0
SKIP_HEAVY=0
INSTALL_HEAVY=0
NONINTERACTIVE=0
ONLY_TERMUX=0
ONLY_KALI=0
ONLY_SHORTCUTS=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

  --full              Install heavy Kali packages (metasploit, hashcat, john)
  --light             Skip heavy packages (default if non-interactive)
  --skip-nethunter    Assume NetHunter already installed; only refresh tools
  --only-termux       Only Termux packages + storage
  --only-kali         Only apt/pip installs inside Kali chroot
  --only-shortcuts    Only install Termux:Widget shortcuts
  --yes / -y          Non-interactive (assume --light unless --full given)
  -h / --help         This help

Official NetHunter Rootless docs: ${NH_DOCS_URL}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) INSTALL_HEAVY=1; SKIP_HEAVY=0; shift ;;
    --light) SKIP_HEAVY=1; INSTALL_HEAVY=0; shift ;;
    --skip-nethunter) SKIP_NETHUNTER=1; shift ;;
    --only-termux) ONLY_TERMUX=1; shift ;;
    --only-kali) ONLY_KALI=1; shift ;;
    --only-shortcuts) ONLY_SHORTCUTS=1; shift ;;
    --yes|-y) NONINTERACTIVE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ---- colors / logging -------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  C_RESET="$(tput sgr0)"; C_BOLD="$(tput bold)"
  C_RED="$(tput setaf 1)"; C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"; C_BLUE="$(tput setaf 4)"
  C_CYAN="$(tput setaf 6)"
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

mkdir -p "${MARKER_DIR}"
touch "${LOG_FILE}"

log()   { echo -e "${C_CYAN}[*]${C_RESET} $*" | tee -a "${LOG_FILE}"; }
ok()    { echo -e "${C_GREEN}[+]${C_RESET} $*" | tee -a "${LOG_FILE}"; }
warn()  { echo -e "${C_YELLOW}[!]${C_RESET} $*" | tee -a "${LOG_FILE}"; }
err()   { echo -e "${C_RED}[x]${C_RESET} $*" | tee -a "${LOG_FILE}" >&2; }
step()  { echo -e "\n${C_BOLD}${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}" | tee -a "${LOG_FILE}"; }
die()   { err "$*"; exit 1; }

on_error() {
  local ec=$?
  err "Setup failed at line ${BASH_LINENO[0]} (exit ${ec}). See ${LOG_FILE}"
  exit "${ec}"
}
trap on_error ERR

banner() {
  cat <<'BANNER'
 _   _      _   _             _            _  ___ _
| \ | | ___| |_| |__  _   _ _| |_ ___ _ __| |/ (_) |_
|  \| |/ _ \ __| '_ \| | | / _` |/ _ \ '__| ' /| | __|
| |\  |  __/ |_| | | | |_| | (_| |  __/ |  | . \| | |_
|_| \_|\___|\__|_| |_|\__,_|\__,_|\___|_|  |_|\_\_|\__|
          Rootless Toolkit  ·  Moto G Stylus 2024
BANNER
  echo -e "${C_YELLOW}For authorized testing of YOUR devices and networks only.${C_RESET}\n"
}

require_termux() {
  if [[ "${PREFIX:-}" != *"com.termux"* ]] && [[ ! -d /data/data/com.termux/files/usr ]]; then
    warn "Not detecting Termux PREFIX. Continuing anyway (you may be in a test shell)."
  fi
  command -v pkg >/dev/null 2>&1 || die "pkg not found — run this inside Termux."
}

# ---- helpers ----------------------------------------------------------------
pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }

install_termux_pkg() {
  local p="$1"
  if pkg_installed "$p"; then
    ok "Termux package already installed: ${p}"
    return 0
  fi
  log "Installing Termux package: ${p}"
  pkg install -y "$p" || {
    warn "Failed to install ${p} (may be unavailable on this arch/repo)"
    return 1
  }
  ok "Installed ${p}"
}

nh_cmd() {
  # Prefer nh / nethunter -r for root-in-chroot (proot)
  if command -v nh >/dev/null 2>&1; then
    nh -r "$@"
  elif command -v nethunter >/dev/null 2>&1; then
    nethunter -r "$@"
  else
    die "nethunter/nh not on PATH — install NetHunter Rootless first"
  fi
}

nh_available() {
  command -v nh >/dev/null 2>&1 || command -v nethunter >/dev/null 2>&1
}

choose_heavy() {
  if [[ "${INSTALL_HEAVY}" -eq 1 ]]; then return 0; fi
  if [[ "${SKIP_HEAVY}" -eq 1 ]]; then return 1; fi
  if [[ "${NONINTERACTIVE}" -eq 1 ]]; then
    warn "Non-interactive: skipping heavy packages (use --full to force)"
    return 1
  fi
  echo
  echo -e "${C_BOLD}Heavy Kali packages${C_RESET} (metasploit-framework, hashcat, john)"
  echo "  These can take 1–3+ GB and a long time on phone storage."
  echo "  1) Install heavy tools now"
  echo "  2) Skip heavy tools (recommended first run)"
  local choice
  read -r -p "Choice [2]: " choice || true
  choice="${choice:-2}"
  [[ "${choice}" == "1" ]]
}

# ---- stages -----------------------------------------------------------------
stage_storage() {
  step "Storage access (termux-setup-storage)"
  if [[ -d "${HOME}/storage/shared" ]] || [[ -d "${HOME}/storage/downloads" ]]; then
    ok "Storage already linked"
  else
    log "Requesting storage permission (approve the Android prompt)…"
    termux-setup-storage || warn "termux-setup-storage returned non-zero; continue after granting permission"
    sleep 1
    if [[ -d "${HOME}/storage" ]]; then
      ok "Storage linked"
    else
      warn "storage/ not present yet — re-run after granting permission"
    fi
  fi
}

stage_termux_pkgs() {
  step "Termux packages"
  log "Updating pkg indexes…"
  pkg update -y || warn "pkg update had issues; continuing"

  # root-repo unlocks some packages (tshark etc.) on Termux
  install_termux_pkg root-repo || true
  pkg update -y || true

  local required=(wget git python android-tools jq)
  local optional=(tshark termshark termux-api)

  for p in "${required[@]}"; do
    install_termux_pkg "$p" || die "Required package failed: ${p}"
  done

  for p in "${optional[@]}"; do
    install_termux_pkg "$p" || warn "Optional package skipped: ${p}"
  done

  # Ensure pip exists for Termux-side helpers
  if ! python -m pip --version >/dev/null 2>&1; then
    install_termux_pkg python-pip || warn "python-pip unavailable"
  fi
}

stage_nethunter() {
  step "Kali NetHunter Rootless (official installer)"
  log "Docs: ${NH_DOCS_URL}"
  log "Installer URL (from docs): ${NH_INSTALLER_URL}"

  if [[ "${SKIP_NETHUNTER}" -eq 1 ]]; then
    warn "Skipping NetHunter install (--skip-nethunter)"
    return 0
  fi

  if nh_available; then
    ok "NetHunter already present ($(command -v nh 2>/dev/null || command -v nethunter))"
    return 0
  fi

  local installer="${HOME}/install-nethunter-termux"
  if [[ ! -f "${installer}" ]]; then
    log "Downloading official installer…"
    wget -O "${installer}" "${NH_INSTALLER_URL}" || die "Failed to download NetHunter installer"
  else
    ok "Installer already downloaded: ${installer}"
  fi
  chmod +x "${installer}"

  warn "NetHunter install is LARGE (~1–2+ GB) and interactive (image choice)."
  warn "Running: ${installer}"
  echo -e "${C_YELLOW}Follow on-screen prompts. Prefer the full/kali-arm64 image if storage allows.${C_RESET}"
  "${installer}" || die "NetHunter installer failed"

  # Refresh PATH for current shell
  hash -r 2>/dev/null || true
  # Common install locations
  export PATH="${PATH}:${HOME}/.local/bin:${PREFIX}/bin"
  if ! nh_available; then
    # Source profile snippets if present
    if [[ -f "${HOME}/.bashrc" ]]; then
      # shellcheck disable=SC1091
      source "${HOME}/.bashrc" 2>/dev/null || true
    fi
  fi
  nh_available || die "nethunter/nh still not found after install — open a new Termux session and re-run with --skip-nethunter --only-kali"
  ok "NetHunter Rootless installed"
}

stage_kali_tools() {
  step "Kali chroot tools (via nethunter -r)"
  nh_available || die "NetHunter not available"

  log "Updating Kali apt…"
  nh_cmd bash -lc 'export DEBIAN_FRONTEND=noninteractive; apt-get update -y' \
    || warn "apt-get update had issues"

  # Core set — works without kernel mods / monitor mode
  local CORE=(
    nmap
    sqlmap
    hydra
    nikto
    gobuster
    ffuf
    whatweb
    tshark
    wireshark-common
    python3-pip
    python3-venv
    bluez
    bluez-tools
    curl
    wget
    git
    jq
    net-tools
    iproute2
    dnsutils
    whois
  )

  local HEAVY=(
    metasploit-framework
    hashcat
    john
  )

  log "Installing core Kali packages…"
  nh_cmd bash -lc "export DEBIAN_FRONTEND=noninteractive; apt-get install -y ${CORE[*]}" \
    || warn "Some core packages failed — check free space / apt output"

  if choose_heavy; then
    log "Installing heavy packages (this takes a while)…"
    nh_cmd bash -lc "export DEBIAN_FRONTEND=noninteractive; apt-get install -y ${HEAVY[*]}" \
      || warn "Heavy package install had failures (storage?)"
  else
    ok "Skipped heavy packages (metasploit / hashcat / john). Re-run with --full later."
  fi

  log "Installing Python packages inside Kali: btsnoop-parser, bleak, scapy"
  nh_cmd bash -lc 'python3 -m pip install --break-system-packages -U pip 2>/dev/null || python3 -m pip install -U pip || true'
  nh_cmd bash -lc 'python3 -m pip install --break-system-packages btsnoop-parser bleak scapy \
    || python3 -m pip install btsnoop-parser bleak scapy' \
    || warn "pip installs in Kali had issues"

  ok "Kali tool stage finished"
}

stage_termux_python() {
  step "Termux-side Python helpers (btsnoop-parser for btcap.sh)"
  if command -v pip >/dev/null 2>&1 || python -m pip --version >/dev/null 2>&1; then
    python -m pip install --user -U btsnoop-parser bleak 2>/dev/null \
      || pip install --user -U btsnoop-parser bleak \
      || warn "Could not pip-install btsnoop-parser in Termux (btcap can use Kali copy)"
  else
    warn "pip not available in Termux"
  fi
}

stage_shortcuts() {
  step "Termux:Widget shortcuts → ~/.shortcuts"
  local src="${KIT_DIR}/shortcuts"
  local dest="${HOME}/.shortcuts"
  mkdir -p "${dest}"
  if [[ ! -d "${src}" ]]; then
    warn "No shortcuts/ directory in kit"
    return 0
  fi
  local f
  for f in "${src}"/*; do
    [[ -f "${f}" ]] || continue
    local name
    name="$(basename "${f}")"
    install -m 0755 "${f}" "${dest}/${name}"
    ok "Installed shortcut: ~/.shortcuts/${name}"
  done
  # Also place btcap.sh on PATH-ish location
  mkdir -p "${HOME}/bin"
  if [[ -f "${KIT_DIR}/btcap.sh" ]]; then
    install -m 0755 "${KIT_DIR}/btcap.sh" "${HOME}/bin/btcap.sh"
    # symlink without .sh for widget friendliness
    ln -sfn "${HOME}/bin/btcap.sh" "${HOME}/bin/btcap"
    ok "Installed ~/bin/btcap.sh"
  fi
  # Ensure ~/bin on PATH
  if ! echo "${PATH}" | grep -q "${HOME}/bin"; then
    if ! grep -q 'HOME/bin' "${HOME}/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/bin:$PATH"' >> "${HOME}/.bashrc"
      ok "Added ~/bin to PATH in ~/.bashrc"
    fi
  fi
  warn "Install Termux:Widget from F-Droid, then add widgets that point at ~/.shortcuts scripts."
}

stage_copy_kit() {
  step "Persist kit under ~/nethunter-kit"
  local dest="${HOME}/nethunter-kit"
  mkdir -p "${dest}"
  # Copy scripts (don't clobber user's local edits of log dirs)
  for f in setup.sh btcap.sh README.md; do
    if [[ -f "${KIT_DIR}/${f}" ]]; then
      cp -f "${KIT_DIR}/${f}" "${dest}/${f}"
      chmod +x "${dest}/${f}" 2>/dev/null || true
    fi
  done
  if [[ -d "${KIT_DIR}/shortcuts" ]]; then
    mkdir -p "${dest}/shortcuts"
    cp -f "${KIT_DIR}/shortcuts/"* "${dest}/shortcuts/" 2>/dev/null || true
    chmod +x "${dest}/shortcuts/"* 2>/dev/null || true
  fi
  ok "Kit available at ${dest}"
}

# ---- main -------------------------------------------------------------------
main() {
  banner
  require_termux
  log "Kit dir: ${KIT_DIR}"
  log "Log file: ${LOG_FILE}"

  if [[ "${ONLY_SHORTCUTS}" -eq 1 ]]; then
    stage_shortcuts
    ok "Done (shortcuts only)."
    return 0
  fi

  if [[ "${ONLY_KALI}" -eq 1 ]]; then
    stage_kali_tools
    stage_termux_python
    stage_shortcuts
    date -Iseconds > "${MARKER}"
    ok "Done (kali only)."
    return 0
  fi

  stage_storage
  stage_termux_pkgs

  if [[ "${ONLY_TERMUX}" -eq 1 ]]; then
    stage_shortcuts
    stage_copy_kit
    ok "Done (termux only)."
    return 0
  fi

  stage_nethunter
  stage_kali_tools
  stage_termux_python
  stage_shortcuts
  stage_copy_kit

  date -Iseconds > "${MARKER}"
  echo
  ok "Setup complete."
  echo -e "${C_BOLD}Next steps:${C_RESET}"
  echo "  1) nh kex passwd          # set KeX password"
  echo "  2) nh kex &               # start desktop; open NetHunter KeX app"
  echo "  3) ~/bin/btcap.sh --help  # Bluetooth HCI capture via bugreport"
  echo "  4) Read ~/nethunter-kit/README.md"
  echo
  echo -e "${C_YELLOW}LEGAL: Use only on networks/devices you own or have explicit permission to test.${C_RESET}"
}

main "$@"
