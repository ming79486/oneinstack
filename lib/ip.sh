#!/bin/bash
# Private Nginx-only toolkit.

get_local_ip() {
  ip -4 a show scope global 2>/dev/null | awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}'
}

get_local_ip_ifconfig() {
  ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}'
}

get_public_ip() {
  curl -4fsS --max-time 5 https://ip.sb 2>/dev/null | tr -d '[:space:]'
}

get_ipaddr() {
  local ipaddr
  ipaddr=$(get_local_ip)
  [ -n "${ipaddr}" ] || ipaddr=$(get_local_ip_ifconfig)
  [ -n "${ipaddr}" ] || ipaddr=$(get_public_ip)
  printf '%s\n' "${ipaddr}"
}
