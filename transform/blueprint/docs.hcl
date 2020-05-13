docs "docs" {
  path  = "./docs"
  port  = 8080
  open_in_browser = true

  network {
    name = "network.local"
  }

  index_title = "Transform"
  index_pages = ["index"]
}