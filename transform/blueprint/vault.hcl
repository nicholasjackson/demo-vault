container "vault" {
  image {
    name = "hashicorp/vault-enterprise:1.4.0-rc1_ent"
  }

  command = [
    "vault",
    "server",
    "-dev",
    "-dev-root-token-id=root",
    "-dev-listen-address=0.0.0.0:8200",
  ]

  port {
    local = 8200
    remote = 8200
    host = 8200
  }

  # Wait for Vault to start
  health_check {
    timeout = "30s"
    http = "http://localhost:8200/v1/sys/health"
  }

  volume {
    source = "./files"
    destination = "/files"
  }
  
  env {
    key = "VAULT_ADDR"
    value = "http://localhost:8200"
  }
  
  env {
    key = "VAULT_TOKEN"
    value = "root"
  }

  network {
    name = "network.local"
  }
}

#exec_remote "setup" {
#  target = "container.vault"
#
#  cmd = "/files/setup_vault.sh"
#}