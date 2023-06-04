config_version = 2

name = "basedflare"

mode = "single"

dataplaneapi {
  host       = "127.0.0.1"
  port       = 2001
  advertised = {}

  scheme = ["http"]

  transaction {
    transaction_dir = "/tmp/haproxy"
  }

  resources {
    maps_dir      = "/etc/haproxy/map"
    ssl_certs_dir = "/etc/haproxy/ssl"
  }

  user "admin" {
    insecure = true
    password = "admin"
  }
}

haproxy {
  config_file = "/etc/haproxy/haproxy.cfg"
  haproxy_bin = "/usr/local/sbin/haproxy"

  reload {
    reload_delay    = 5
    reload_cmd      = "service haproxy reload"
    restart_cmd     = "service haproxy restart"
    reload_strategy = "custom"
  }
}
