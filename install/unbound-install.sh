#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: wimb0
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/NLnetLabs/unbound
source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Unbound"
# Install dependencies including unbound-anchor for DNSSEC
$STD apt install -y \
  unbound \
  unbound-host \
  unbound-anchor

# Initialize DNSSEC Root Anchor and fix LXC permissions
msg_info "Initializing DNSSEC Trust Anchor"
rm -f /var/lib/unbound/root.key
sudo -u unbound /usr/sbin/unbound-anchor -a "/var/lib/unbound/root.key" || true
chmod 755 /var/lib/unbound
chown unbound:unbound /var/lib/unbound/root.key
chmod 644 /var/lib/unbound/root.key

# Remove default Debian config that causes "trust anchor presented twice" crashes
rm -f /etc/unbound/unbound.conf.d/root-auto-trust-anchor-file.conf

mkdir -p /etc/unbound/unbound.conf.d
cat <<EOF >/etc/unbound/unbound.conf.d/unbound.conf
server:
  interface: 0.0.0.0
  port: 5335
  do-ip6: no
  hide-identity: yes
  hide-version: yes
  harden-referral-path: yes
  cache-min-ttl: 300
  cache-max-ttl: 14400
  serve-expired: yes
  serve-expired-ttl: 3600
  prefetch: yes
  prefetch-key: yes
  target-fetch-policy: "3 2 1 1 1"
  unwanted-reply-threshold: 10000000
  rrset-cache-size: 256m
  msg-cache-size: 128m
  so-rcvbuf: 1m
  private-address: 192.168.0.0/16
  private-address: 169.254.0.0/16
  private-address: 172.16.0.0/12
  private-address: 10.0.0.0/8
  private-address: fd00::/8
  private-address: fe80::/10
  access-control: 192.168.0.0/16 allow
  access-control: 172.16.0.0/12 allow
  access-control: 10.0.0.0/8 allow
  access-control: 127.0.0.1/32 allow
  chroot: ""
  logfile: /var/log/unbound.log
  # Explicitly enable DNSSEC validation
  module-config: "validator iterator"
  auto-trust-anchor-file: "/var/lib/unbound/root.key"
EOF

touch /var/log/unbound.log
chown unbound:unbound /var/log/unbound.log
sleep 5
systemctl restart unbound
msg_ok "Installed Unbound"

msg_info "Configuring Logrotate"
cat <<EOF >/etc/logrotate.d/unbound
/var/log/unbound.log {
  daily
  rotate 7
  missingok
  notifempty
  compress
  delaycompress
  sharedscripts
  create 644
  postrotate
    /usr/sbin/unbound-control log_reopen
  endscript
}
EOF
systemctl restart logrotate
msg_ok "Configured Logrotate"

motd_ssh
customize
cleanup_lxc
