container "postgres" {
  image {
    name = "postgres:11.6"
  }

  port {
    local = 5432
    remote = 5432
    host = 5432
  }

  env {
      key = "POSTGRES_DB"
      value = "payments"
  }

  env {
      key = "POSTGRES_USER"
      value = "root"
  }

  env {
      key = "POSTGRES_PASSWORD"
      value = "password"
  }

  # Mount the volume for the DB setup script which runs when
  # the container starts
  volume {
    source = "./files/db_setup.sql"
    destination = "/docker-entrypoint-initdb.d/db_setup.sql"
  }
  
  network {
    name = "network.local"
  }
}