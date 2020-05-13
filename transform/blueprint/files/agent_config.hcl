auto_auth {
  method {
    type = "approle"
    config = {
      role_id_file_path = "/secrets/role_id"
      secret_id_file_path = "/secrets/secret_id"
      remove_secret_id_file_after_reading = true
    }
  }
}

cache {
  use_auto_auth_token = true
}

listener "tcp" {
  address = "127.0.0.1:8200"
  tls_disable = true
}

vault {
  address = "http://vault.container.shipyard.run:8200"
}