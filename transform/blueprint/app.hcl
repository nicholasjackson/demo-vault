container "payments_go" {
  image {
    name = "nicholasjackson/transform-demo:go"
  }

  command = ["/app/server"]
  
  port {
    local = 9090
    remote = 9090
    host = 9091
  }

  env {
    key = "POSTGRES_HOST"
    value = "postgres.container.shipyard.run"
  }
  
  env {
    key = "POSTGRES_PORT"
    value = "5432"
  }
  
  env {
    key = "VAULT_TOKEN"
    value = "root"
  }
  
  env {
    key = "VAULT_ADDR"
    value = "http://vault.container.shipyard.run:8200"
  }
  
  network {
    name = "network.local"
  }
}

container "payments_java" {
  image {
    name = "nicholasjackson/transform-demo:java"
  }

  command = [
    "java", 
    "-jar", 
    "/app/spring-boot-payments-0.1.0.jar",
  ]
  
  port {
    local = 9090
    remote = 9090
    host = 9092
  }
  
  env {
    key = "spring_datasource_url"
    value = "jdbc:postgresql://postgres.container.shipyard.run:5432/payments"
  }
  
  env {
    key = "vault_token"
    value = "root"
  }
  
  env {
    key = "vault_addr"
    value = "http://vault.container.shipyard.run:8200"
  }
  
  network {
    name = "network.local"
  }
}