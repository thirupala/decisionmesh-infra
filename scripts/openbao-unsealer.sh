#!/bin/sh
# openbao-unsealer.sh
#
# Keeps OpenBao unsealed across VM / daemon / container restarts.
#
# Runs as the `openbao-unsealer` compose sidecar. It loops forever; whenever the
# vault reports SEALED it re-runs `bao operator unseal` with the key mounted at
# $KEY_FILE. Because it watches state continuously (rather than firing once at
# boot) it recovers all three cases: VM restart, docker daemon restart, and a
# lone openbao container restart.
#
# Decision logic uses `bao status` EXIT CODES, so there is no JSON to parse:
#   0 = reachable and unsealed   -> do nothing
#   2 = reachable but sealed     -> unseal
#   other = not reachable yet    -> wait and retry
#
# Expected compose service (sibling of `openbao`):
#
#   openbao-unsealer:
#     image: openbao/openbao:2
#     depends_on: [openbao]
#     restart: unless-stopped
#     environment:
#       BAO_ADDR: http://openbao:8200
#     entrypoint: ["/bin/sh", "/usr/local/bin/unsealer.sh"]
#     volumes:
#       - ./scripts/openbao-unsealer.sh:/usr/local/bin/unsealer.sh:ro
#       - /opt/decisionmesh/secrets/openbao-unseal.key:/unseal.key:ro

: "${BAO_ADDR:=http://openbao:8200}"; export BAO_ADDR
KEY_FILE="${KEY_FILE:-/unseal.key}"
INTERVAL="${INTERVAL:-10}"

if [ ! -r "$KEY_FILE" ]; then
  echo "$(date -Iseconds) FATAL: unseal key file not readable at $KEY_FILE" >&2
  # keep the container alive so it's obvious in `docker ps`, but do nothing useful
  while true; do sleep 3600; done
fi

echo "$(date -Iseconds) openbao-unsealer started (addr=$BAO_ADDR, interval=${INTERVAL}s)"

while true; do
  bao status >/dev/null 2>&1
  case $? in
    0) : ;;                                   # already unsealed
    2)                                        # sealed -> unseal
      if bao operator unseal "$(cat "$KEY_FILE")" >/dev/null 2>&1; then
        echo "$(date -Iseconds) openbao unsealed"
      else
        echo "$(date -Iseconds) unseal attempt failed (vault not ready or wrong key)" >&2
      fi
      ;;
    *) : ;;                                    # unreachable yet; retry next loop
  esac
  sleep "$INTERVAL"
done