#!/bin/sh
# Keeps HashiCorp Vault (staging) unsealed across restarts.
: "${VAULT_ADDR:=http://openbao:8200}"; export VAULT_ADDR
KEY_FILE="${KEY_FILE:-/unseal.key}"
INTERVAL="${INTERVAL:-10}"

if [ ! -r "$KEY_FILE" ]; then
  echo "$(date -Iseconds) FATAL: unseal key not readable at $KEY_FILE" >&2
  while true; do sleep 3600; done
fi

echo "$(date -Iseconds) vault-unsealer started (addr=$VAULT_ADDR)"

while true; do
  STATUS="$(vault status -format=json 2>/dev/null)"
  if [ -n "$STATUS" ]; then
    if echo "$STATUS" | grep -q '"sealed": true'; then
      if vault operator unseal "$(cat "$KEY_FILE")" >/dev/null 2>&1; then
        echo "$(date -Iseconds) vault unsealed"
      else
        echo "$(date -Iseconds) unseal failed (not ready or wrong key)" >&2
      fi
    fi
  fi
  sleep "$INTERVAL"
done