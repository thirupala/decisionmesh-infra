# vault-staging.hcl — HashiCorp Vault, staging
# Lives at /home/decisionmesh/dm-config/vault-staging.hcl on the host,
# mounted read-only into the container at /vault/config/vault.hcl
#
# THE FIX: storage is "file" (persistent), NOT "inmem".
# With inmem, vault re-initialised empty on every restart — new root
# token, no secrets — which is why the API loaded nothing after a reboot.

storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1        # internal-only network; TLS terminated upstream at the gateway
}

# API address advertised to clients on the compose network.
api_addr = "http://openbao:8200"

# No seal stanza => Shamir seal. Vault comes up SEALED after a restart;
# the openbao-unsealer sidecar unseals it automatically.

ui = true

# Container already has IPC_LOCK (cap_add in compose); keep mlock on.
disable_mlock = false
