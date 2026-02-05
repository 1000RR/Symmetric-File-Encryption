#!/usr/bin/env zsh
set -euo pipefail

log(){ echo "[encrypt] $*"; }
die(){ echo "Error: $*" >&2; exit 1; }

usage() {
  cat >&2 <<EOF
Usage:
  $(basename "$0") <secret> <salt> <input> <output|outdir>
  $(basename "$0") -k <ENVVAR> <input> <output|outdir>

Notes:
  - In -k mode, \$ENVVAR must be: <ENC_HEX>|||<MAC_HEX> (each 64 hex chars), e.g. from derive-key.zsh
  - output|outdir:
      * if an existing directory path: output becomes <dir>/<input_basename>.enc
      * if ends with '/': output becomes <that_dir>/<input_basename>.enc (dir will be created)
      * otherwise: treated as output file path (or filename in CWD)
EOF
  exit 1
}

# ---- reject unknown flags ----
if [[ "${1-}" == -* && "${1-}" != "-k" ]]; then
  die "unknown option '$1' (only supported option is: -k <ENVVAR>)"
fi

USE_DERIVED_KEYS=0
ENV_KEY_NAME=""

if [[ "${1-}" == "-k" ]]; then
  [[ $# -eq 4 ]] || usage
  USE_DERIVED_KEYS=1
  ENV_KEY_NAME="$2"
  INPUT="$3"
  OUTSPEC="$4"
else
  [[ $# -eq 4 ]] || usage
  SECRET="$1"
  SALT="$2"
  INPUT="$3"
  OUTSPEC="$4"
fi

log "Validating input..."
[[ -f "$INPUT" ]] || die "input file not found: $INPUT"

IN_BASENAME="$(basename -- "$INPUT")"

# ---- resolve output path ----
if [[ -d "$OUTSPEC" ]]; then
  OUT="$OUTSPEC/$IN_BASENAME.enc"
elif [[ "$OUTSPEC" == */ ]]; then
  mkdir -p "$OUTSPEC"
  OUT="$OUTSPEC/$IN_BASENAME.enc"
else
  case "$OUTSPEC" in
    */*) OUT="$OUTSPEC" ;;
    *)   OUT="$(pwd)/$OUTSPEC" ;;
  esac
fi

[[ ! -e "$OUT" && ! -e "$OUT.iv" && ! -e "$OUT.hmac" ]] || die "output already exists: $OUT"

# ---- keys ----
if [[ "$USE_DERIVED_KEYS" -eq 1 ]]; then
  log "Using derived ENC|||MAC keys from \$${ENV_KEY_NAME}"
  RAW="${(P)ENV_KEY_NAME}"
  [[ "$RAW" == *"|||"* ]] || die "ENVVAR must contain ENC_HEX|||MAC_HEX"

  ENC_KEY="${RAW%%|||*}"
  MAC_KEY="${RAW##*|||}"

  [[ "$ENC_KEY" =~ ^[0-9a-fA-F]{64}$ ]] || die "invalid ENC key format"
  [[ "$MAC_KEY" =~ ^[0-9a-fA-F]{64}$ ]] || die "invalid MAC key format"
else
  log "Deriving keys via Argon2"
  ENC_KEY="$(printf '%s' "$SECRET" \
    | argon2 "${SALT}|enc" -id -m 23 -t 3 -p 1 -r \
    | openssl dgst -sha256 -binary | xxd -p -c 256)"
  MAC_KEY="$(printf '%s' "$SECRET" \
    | argon2 "${SALT}|mac" -id -m 23 -t 3 -p 1 -r \
    | openssl dgst -sha256 -binary | xxd -p -c 256)"
fi

# ---- encrypt ----
log "Encrypting (AES-256-CTR)..."
IV="$(openssl rand -hex 16)"

openssl enc -aes-256-ctr \
  -K "$ENC_KEY" \
  -iv "$IV" \
  -in "$INPUT" \
  -out "$OUT"

log "Computing HMAC..."
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
printf '%s' "$IV" | xxd -r -p > "$TMP"
cat "$OUT" >> "$TMP"
HMAC="$(openssl dgst -sha256 -mac HMAC -macopt hexkey:"$MAC_KEY" "$TMP" | awk '{print $NF}')"

echo "$IV"   > "$OUT.iv"
echo "$HMAC" > "$OUT.hmac"

log "Done."
echo "Encrypted: $OUT"