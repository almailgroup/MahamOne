#!/bin/bash
# Runs one of these Python scripts with the App Store Connect key from the
# workflow's secrets (RAW_KEY_ID, RAW_ISSUER_ID, KEY): trimmed, masked in the
# log, in a file only this job reads, removed afterwards.
#
# usage: with-asc-key.sh <script.py> [arguments…]
set -u
KEY_ID=$(printf '%s' "${RAW_KEY_ID:-}" | tr -d '[:space:]')
ISSUER_ID=$(printf '%s' "${RAW_ISSUER_ID:-}" | tr -d '[:space:]')
if [ -z "$KEY_ID" ] || [ -z "$ISSUER_ID" ] || [ -z "${KEY:-}" ]; then
  echo "::error::The App Store Connect secrets are missing. See ios/README.md, \"Getting it to TestFlight\"."
  exit 1
fi
echo "::add-mask::$KEY_ID"
echo "::add-mask::$ISSUER_ID"
AUTH_KEY_PATH="${RUNNER_TEMP:-/tmp}/AuthKey_$KEY_ID.p8"
( umask 077; printf '%s\n' "$KEY" > "$AUTH_KEY_PATH" )
export KEY_ID ISSUER_ID AUTH_KEY_PATH TEAM_ID="${TEAM_ID:-}"
venv="${RUNNER_TEMP:-/tmp}/asc-venv"
python3 -m venv "$venv"
"$venv/bin/pip" install --quiet --disable-pip-version-check pyjwt cryptography
script="$1"
shift
PYTHONDONTWRITEBYTECODE=1 "$venv/bin/python" "$script" "$@"
status=$?
rm -f "$AUTH_KEY_PATH"
exit $status
