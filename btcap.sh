#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# btcap.sh — Pull Android BT HCI snoop via adb bugreport (wireless debugging)
# and convert with btsnoop_parser + tshark GATT dump.
#
# Designed to run ON the phone (Termux) against itself over Wireless Debugging,
# or from another machine on the LAN. Authorized use on YOUR devices only.
# =============================================================================
set -euo pipefail

OUT_BASE="${HOME}/storage/downloads/btcap"
[[ -d "${HOME}/storage/downloads" ]] || OUT_BASE="${HOME}/btcap-out"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="${OUT_BASE}/${STAMP}"
ADB_SERIAL=""
PAIR_ONLY=0
CONNECT_HOST=""
SKIP_BUGREPORT=0
EXISTING_BUGREPORT=""
EXISTING_LOG=""

# ---- colors -----------------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  C_RESET="$(tput sgr0)"; C_BOLD="$(tput bold)"
  C_RED="$(tput setaf 1)"; C_GREEN="$(tput setaf 2)"
  C_YELLOW="$(tput setaf 3)"; C_CYAN="$(tput setaf 6)"
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""
fi
log()  { echo -e "${C_CYAN}[*]${C_RESET} $*"; }
ok()   { echo -e "${C_GREEN}[+]${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}[!]${C_RESET} $*"; }
err()  { echo -e "${C_RED}[x]${C_RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
  cat <<EOF
${C_BOLD}btcap.sh${C_RESET} — Bluetooth HCI capture via adb bugreport → btsnoop_parser → tshark

${C_BOLD}ONE-TIME: enable HCI snoop on the phone${C_RESET}
  Settings → Developer options → Enable Bluetooth HCI snoop log  (ON)
  (On some Motos: *#*#3646633#*#* → Bluetooth → HCI log, or
   Developer options → Bluetooth HCI snoop log)
  Then toggle Bluetooth OFF/ON so logging starts.

${C_BOLD}ONE-TIME: Wireless debugging (phone talking to itself)${C_RESET}
  1. Settings → Developer options → Wireless debugging → ON
  2. Tap "Pair device with pairing code"
  3. Note IP:pairing_port and the 6-digit code
  4. In Termux:
       adb pair <IP>:<PAIR_PORT>
       # enter the pairing code when prompted
  5. Back on Wireless debugging screen, note IP:PORT (connection port)
       adb connect <IP>:<PORT>
       adb devices    # should show that serial as "device"

${C_BOLD}Usage${C_RESET}
  btcap.sh                          # bugreport from default/only adb device
  btcap.sh --connect IP:PORT        # adb connect first, then capture
  btcap.sh --serial SERIAL          # pick a specific adb device
  btcap.sh --from-bugreport FILE    # parse an existing bugreport(.zip)
  btcap.sh --from-log FILE          # parse an existing btsnoop_hci.log
  btcap.sh --pair IP:PAIR_PORT      # only run adb pair (then exit)

${C_BOLD}Outputs${C_RESET} (under ${OUT_BASE}/<timestamp>/)
  bugreport.zip                     raw adb bugreport (unless --from-*)
  btsnoop_hci.log                   extracted HCI snoop
  report.txt                        btsnoop_parser --report
  capture.pcap                      btsnoop_parser --pcap (link type 201)
  gatt_writes.tsv                   tshark GATT Write* dump
  gatt_notifications.tsv            tshark GATT Handle Value Notification/Indication

${C_BOLD}btsnoop_parser CLI${C_RESET} (verified against PyPI 0.10.x)
  btsnoop_parser FILE --report
  btsnoop_parser FILE --pcap OUTPUT.pcap
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --serial) ADB_SERIAL="$2"; shift 2 ;;
    --connect) CONNECT_HOST="$2"; shift 2 ;;
    --pair) CONNECT_HOST="$2"; PAIR_ONLY=1; shift 2 ;;
    --from-bugreport) EXISTING_BUGREPORT="$2"; SKIP_BUGREPORT=1; shift 2 ;;
    --from-log) EXISTING_LOG="$2"; SKIP_BUGREPORT=1; shift 2 ;;
    --out) OUT_BASE="$2"; OUT_DIR="${OUT_BASE}/${STAMP}"; shift 2 ;;
    *) die "Unknown arg: $1 (try --help)" ;;
  esac
done

adb_bin() {
  if command -v adb >/dev/null 2>&1; then
    echo adb
  else
    die "adb not found — install android-tools in Termux (pkg install android-tools)"
  fi
}

ADB=""
ensure_adb() {
  if [[ -z "${ADB}" ]]; then
    ADB="$(adb_bin)"
  fi
}
adb_cmd() {
  ensure_adb
  if [[ -n "${ADB_SERIAL}" ]]; then
    "${ADB}" -s "${ADB_SERIAL}" "$@"
  else
    "${ADB}" "$@"
  fi
}

find_btsnoop_parser() {
  if command -v btsnoop_parser >/dev/null 2>&1; then
    echo btsnoop_parser
    return 0
  fi
  # Termux user install
  if [[ -x "${HOME}/.local/bin/btsnoop_parser" ]]; then
    echo "${HOME}/.local/bin/btsnoop_parser"
    return 0
  fi
  # Via Kali NetHunter
  if command -v nh >/dev/null 2>&1; then
    if nh -r bash -lc 'command -v btsnoop_parser' >/dev/null 2>&1; then
      echo "__NH__"
      return 0
    fi
  elif command -v nethunter >/dev/null 2>&1; then
    if nethunter -r bash -lc 'command -v btsnoop_parser' >/dev/null 2>&1; then
      echo "__NH__"
      return 0
    fi
  fi
  return 1
}

run_parser() {
  local parser="$1"; shift
  if [[ "${parser}" == "__NH__" ]]; then
    if command -v nh >/dev/null 2>&1; then
      nh -r btsnoop_parser "$@"
    else
      nethunter -r btsnoop_parser "$@"
    fi
  else
    "${parser}" "$@"
  fi
}

find_tshark() {
  if command -v tshark >/dev/null 2>&1; then
    echo tshark
    return 0
  fi
  if command -v nh >/dev/null 2>&1 && nh -r bash -lc 'command -v tshark' >/dev/null 2>&1; then
    echo "__NH_TSHARK__"
    return 0
  fi
  if command -v nethunter >/dev/null 2>&1 && nethunter -r bash -lc 'command -v tshark' >/dev/null 2>&1; then
    echo "__NH_TSHARK__"
    return 0
  fi
  return 1
}

run_tshark() {
  local ts="$1"; shift
  if [[ "${ts}" == "__NH_TSHARK__" ]]; then
    # Copy pcap into a path visible from chroot if needed — nh shares $HOME via proot often.
    if command -v nh >/dev/null 2>&1; then
      nh -r tshark "$@"
    else
      nethunter -r tshark "$@"
    fi
  else
    "${ts}" "$@"
  fi
}

# ---- pair / connect ---------------------------------------------------------
if [[ "${PAIR_ONLY}" -eq 1 ]]; then
  [[ -n "${CONNECT_HOST}" ]] || die "--pair needs IP:PAIR_PORT"
  ensure_adb
  log "adb pair ${CONNECT_HOST}"
  "${ADB}" pair "${CONNECT_HOST}"
  ok "Paired. Now: adb connect <IP>:<PORT>  (connection port from Wireless debugging screen)"
  exit 0
fi

if [[ -n "${CONNECT_HOST}" ]]; then
  ensure_adb
  log "adb connect ${CONNECT_HOST}"
  "${ADB}" connect "${CONNECT_HOST}"
  # Prefer this serial going forward
  ADB_SERIAL="${CONNECT_HOST}"
fi

mkdir -p "${OUT_DIR}"
ok "Output directory: ${OUT_DIR}"

# ---- obtain btsnoop log -----------------------------------------------------
SNOOP_LOG="${OUT_DIR}/btsnoop_hci.log"

if [[ -n "${EXISTING_LOG}" ]]; then
  [[ -f "${EXISTING_LOG}" ]] || die "Log not found: ${EXISTING_LOG}"
  cp -f "${EXISTING_LOG}" "${SNOOP_LOG}"
  ok "Using existing log → ${SNOOP_LOG}"
elif [[ -n "${EXISTING_BUGREPORT}" ]]; then
  [[ -f "${EXISTING_BUGREPORT}" ]] || die "Bugreport not found: ${EXISTING_BUGREPORT}"
  cp -f "${EXISTING_BUGREPORT}" "${OUT_DIR}/bugreport.zip"
elif [[ "${SKIP_BUGREPORT}" -eq 0 ]]; then
  log "Checking adb devices…"
  adb_cmd devices -l | tee "${OUT_DIR}/adb-devices.txt"
  local_state="$(adb_cmd devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  [[ -n "${local_state}" || -n "${ADB_SERIAL}" ]] || die "No adb device in 'device' state. Pair/connect first (see --help)."

  log "Generating bugreport (this can take 1–3 minutes)…"
  # adb bugreport writes a zip next to CWD or to given path depending on version
  BUG_OUT="${OUT_DIR}/bugreport.zip"
  if adb_cmd bugreport "${BUG_OUT}" 2>"${OUT_DIR}/bugreport.stderr"; then
    ok "bugreport → ${BUG_OUT}"
  else
    # Older adb writes bugreport-*.zip into CWD
    warn "adb bugreport PATH form failed; trying CWD capture…"
    (
      cd "${OUT_DIR}"
      adb_cmd bugreport
    ) 2>>"${OUT_DIR}/bugreport.stderr" || die "adb bugreport failed — see ${OUT_DIR}/bugreport.stderr"
    # Normalize name
    found="$(find "${OUT_DIR}" -maxdepth 1 -type f \( -name 'bugreport*.zip' -o -name 'bugreport*.zip' \) | head -1)"
    [[ -n "${found}" ]] || die "No bugreport zip produced"
    [[ "${found}" == "${BUG_OUT}" ]] || mv -f "${found}" "${BUG_OUT}"
    ok "bugreport → ${BUG_OUT}"
  fi
  EXISTING_BUGREPORT="${OUT_DIR}/bugreport.zip"
fi

if [[ ! -f "${SNOOP_LOG}" && -n "${EXISTING_BUGREPORT:-}" ]]; then
  log "Extracting btsnoop_hci.log* from bugreport…"
  EXTRACT_DIR="${OUT_DIR}/_extract"
  mkdir -p "${EXTRACT_DIR}"
  # bugreport is a zip; FS/ path varies slightly by OEM
  if command -v unzip >/dev/null 2>&1; then
    unzip -l "${EXISTING_BUGREPORT}" 2>/dev/null | grep -iE 'btsnoop|bluetooth/logs' \
      | tee "${OUT_DIR}/zip-bt-listing.txt" || true
    # Extract matching members (may be nested)
    unzip -o "${EXISTING_BUGREPORT}" -d "${EXTRACT_DIR}" \
      '*/btsnoop_hci.log*' \
      'FS/data/misc/bluetooth/logs/*' \
      'data/misc/bluetooth/logs/*' \
      '*/bluetooth/logs/btsnoop*' \
      2>/dev/null || true
    # Some bugreports nest another zip
    find "${EXTRACT_DIR}" -type f -name '*.zip' | while read -r z; do
      unzip -o "${z}" -d "${EXTRACT_DIR}/nested" \
        '*/btsnoop_hci.log*' 'FS/data/misc/bluetooth/logs/*' 2>/dev/null || true
    done
  else
    # Python fallback
    python - "${EXISTING_BUGREPORT}" "${EXTRACT_DIR}" <<'PY'
import sys, zipfile, os, io
src, dest = sys.argv[1], sys.argv[2]
os.makedirs(dest, exist_ok=True)
want = ("btsnoop_hci.log", "bluetooth/logs")
with zipfile.ZipFile(src) as z:
    for name in z.namelist():
        low = name.lower()
        if any(w in low for w in want):
            z.extract(name, dest)
            # nested zip?
            path = os.path.join(dest, name)
            if path.endswith(".zip"):
                try:
                    with zipfile.ZipFile(path) as z2:
                        for n2 in z2.namelist():
                            if any(w in n2.lower() for w in want):
                                z2.extract(n2, os.path.join(dest, "nested"))
                except zipfile.BadZipFile:
                    pass
print("extract done")
PY
  fi

  candidate="$(find "${EXTRACT_DIR}" -type f \( -name 'btsnoop_hci.log' -o -name 'btsnoop_hci.log.*' \) 2>/dev/null | sort | tail -1 || true)"
  if [[ -z "${candidate}" ]]; then
    # Last-ditch: any file with btsnoop in the name
    candidate="$(find "${EXTRACT_DIR}" -type f -iname '*btsnoop*' 2>/dev/null | sort | tail -1 || true)"
  fi
  [[ -n "${candidate}" ]] || die "No btsnoop_hci.log found in bugreport.
Is 'Bluetooth HCI snoop log' enabled in Developer options? Toggle BT after enabling, reproduce traffic, then re-run."
  cp -f "${candidate}" "${SNOOP_LOG}"
  ok "Extracted $(basename "${candidate}") → ${SNOOP_LOG} ($(wc -c < "${SNOOP_LOG}") bytes)"
fi

[[ -s "${SNOOP_LOG}" ]] || die "Snoop log empty or missing: ${SNOOP_LOG}"

# ---- parse ------------------------------------------------------------------
PARSER="$(find_btsnoop_parser)" || die "btsnoop_parser not found.
Install: pip install btsnoop-parser
  (or re-run setup.sh so Kali gets it)"

PCAP="${OUT_DIR}/capture.pcap"
REPORT="${OUT_DIR}/report.txt"

log "btsnoop_parser --report → ${REPORT}"
run_parser "${PARSER}" "${SNOOP_LOG}" --report 2>&1 | tee "${REPORT}" || warn "report exited non-zero"

log "btsnoop_parser --pcap ${PCAP}"
run_parser "${PARSER}" "${SNOOP_LOG}" --pcap "${PCAP}" 2>&1 | tee -a "${OUT_DIR}/parser.log" || die "pcap export failed"
if [[ -s "${PCAP}" ]]; then
  ok "PCAP written: ${PCAP} ($(wc -c < "${PCAP}") bytes)"
else
  warn "PCAP missing/empty"
fi

# Also keep a stats dump for quick triage
run_parser "${PARSER}" "${SNOOP_LOG}" --stats > "${OUT_DIR}/stats.txt" 2>&1 || true

# ---- GATT TSV via tshark ----------------------------------------------------
if TS="$(find_tshark)"; then
  log "Dumping GATT writes / notifications with tshark…"
  # Writes (Request/Command/Prepare/Execute)
  run_tshark "${TS}" -r "${PCAP}" -Y 'btatt.opcode == 0x12 || btatt.opcode == 0x52 || btatt.opcode == 0x16 || btatt.opcode == 0x18' \
    -T fields -E header=y -E separator=$'\t' \
    -e frame.number -e frame.time_relative -e bthci_acl.dst.bd_addr -e bthci_acl.src.bd_addr \
    -e btatt.opcode -e btatt.handle -e btatt.value \
    > "${OUT_DIR}/gatt_writes.tsv" 2>"${OUT_DIR}/tshark_writes.err" || warn "GATT writes dump had issues"

  # Notifications (0x1b) and Indications (0x1d)
  run_tshark "${TS}" -r "${PCAP}" -Y 'btatt.opcode == 0x1b || btatt.opcode == 0x1d' \
    -T fields -E header=y -E separator=$'\t' \
    -e frame.number -e frame.time_relative -e bthci_acl.dst.bd_addr -e bthci_acl.src.bd_addr \
    -e btatt.opcode -e btatt.handle -e btatt.value \
    > "${OUT_DIR}/gatt_notifications.tsv" 2>"${OUT_DIR}/tshark_notif.err" || warn "GATT notifications dump had issues"

  ok "GATT TSVs: ${OUT_DIR}/gatt_writes.tsv , ${OUT_DIR}/gatt_notifications.tsv"
else
  warn "tshark not found — skipped GATT TSV. Install tshark in Termux (root-repo) or Kali."
fi

# ---- summary ----------------------------------------------------------------
echo
ok "Done."
echo -e "${C_BOLD}Artifacts:${C_RESET}"
ls -lah "${OUT_DIR}" | sed 's/^/  /'
echo
echo "Open capture.pcap in Wireshark/termshark, or read report.txt"
