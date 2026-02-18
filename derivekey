#!/usr/bin/env zsh
set -euo pipefail

# ============================================================
# derive-key.zsh
#
# Usage:
#   derive-key.zsh <secret> <salt>
#
# Output (single line):
#   <ENC_KEY_HEX>|||<MAC_KEY_HEX>
#
# Each key:
#   - 256-bit (32 bytes)
#   - hex-encoded (64 hex chars)
#
# Design:
#   ENC_KEY = SHA256( Argon2id(secret, salt | "enc") )
#   MAC_KEY = SHA256( Argon2id(secret, salt | "mac") )
# ============================================================

die() { echo "Error: $*" >&2; exit 1; }

[[ $# -eq 2 ]] || die "Usage: $0 <secret> <salt>"

SECRET="$1"
SALT="$2"

derive_one() {
  local context="$1"
  printf '%s' "$SECRET" \
    | argon2 "${SALT}|${context}" -id -m 23 -t 3 -p 1 -r \
    | openssl dgst -sha256 -binary \
    | xxd -p -c 256
}

ENC_KEY_HEX="$(derive_one enc)"
MAC_KEY_HEX="$(derive_one mac)"

[[ ${#ENC_KEY_HEX} -eq 64 ]] || die "encryption key derivation failed"
[[ ${#MAC_KEY_HEX} -eq 64 ]] || die "MAC key derivation failed"

printf '%s|||%s\n' "$ENC_KEY_HEX" "$MAC_KEY_HEX"