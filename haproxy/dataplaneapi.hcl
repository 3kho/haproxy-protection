config_version = 2

name = "meet_bedbug"

mode = "single"

dataplaneapi {
  user "admin" {
    insecure = true
    password = "adminpwd"
  }

  transaction {
    transaction_dir = "/tmp/haproxy"
  }

  advertised {}
}

haproxy {
  config_file = "/etc/haproxy/haproxy.cfg"
  haproxy_bin = "/usr/local/sbin/haproxy"

  reload {
    reload_delay = 5
    reload_cmd   = "service haproxy reload"
    restart_cmd  = "service haproxy restart"
  }
}
