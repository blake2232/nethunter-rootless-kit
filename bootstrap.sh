#!/data/data/com.termux/files/usr/bin/bash
# One-shot bootstrap: fetch kit if needed, then run setup.sh
set -euo pipefail

KIT_URL="${NETHUNTER_KIT_URL:-}"
KIT_SHA256="${NETHUNTER_KIT_SHA256:-}"
DEST="${HOME}/nethunter-kit"

c_ok()   { echo "[+] $*"; }
c_info() { echo "[*] $*"; }
c_err()  { echo "[x] $*" >&2; exit 1; }

# If we are already inside an extracted kit, just run setup
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SELF_DIR}/setup.sh" && -f "${SELF_DIR}/btcap.sh" ]]; then
  c_info "Running local setup.sh from ${SELF_DIR}"
  exec bash "${SELF_DIR}/setup.sh" "$@"
fi

[[ -n "${KIT_URL}" ]] || c_err "Set NETHUNTER_KIT_URL to the kit tarball URL (or extract the kit and run setup.sh)"

mkdir -p "${HOME}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

c_info "Downloading kit…"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o "${TMP}/kit.tgz" "${KIT_URL}"
elif command -v wget >/dev/null 2>&1; then
  wget -O "${TMP}/kit.tgz" "${KIT_URL}"
else
  pkg install -y curl wget || true
  curl -fsSL -o "${TMP}/kit.tgz" "${KIT_URL}"
fi

if [[ -n "${KIT_SHA256}" ]]; then
  c_info "Verifying SHA256…"
  echo "${KIT_SHA256}  ${TMP}/kit.tgz" | sha256sum -c -
fi

rm -rf "${DEST}"
mkdir -p "${DEST}"
tar -xzf "${TMP}/kit.tgz" -C "${DEST}" --strip-components=1 2>/dev/null \
  || tar -xzf "${TMP}/kit.tgz" -C "${HOME}"
# If tarball contained nethunter-kit/ top folder:
[[ -f "${DEST}/setup.sh" ]] || { [[ -f "${HOME}/nethunter-kit/setup.sh" ]] && DEST="${HOME}/nethunter-kit"; }
[[ -f "${DEST}/setup.sh" ]] || c_err "setup.sh not found after extract"
chmod +x "${DEST}"/*.sh "${DEST}/shortcuts/"* 2>/dev/null || true
c_ok "Kit ready at ${DEST}"
exec bash "${DEST}/setup.sh" "$@"
