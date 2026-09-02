#!/usr/bin/env bash
# Runs ON the MySQL VM (copied there and executed by scripts/setup-all.sh).
#
# Installs MySQL and creates the four databases the deployment needs, then
# grants the Identity Server VM access to them. Idempotent: re-running it
# converges rather than re-applying, and it never drops a database - the schema
# apply step in setup-is.sh skips any database that already has tables, so real
# data survives a re-provision.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: %s <env-file>\n' "$(basename "$0")" >&2
  exit 2
fi
# shellcheck source=/dev/null
. "$1"

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() {
  printf '\nWARN: %s\n' "$*" >&2
}

DB_HOST_IP="$(hostname -I | awk '{print $1}')"

# --- 1. install ----------------------------------------------------------------

step "Installing MySQL Server"
if command -v mysqld >/dev/null 2>&1; then
  info "already installed, skipping"
else
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -qq
  sudo apt-get install -y -qq mysql-server
fi

# --- 2. listen on the tenant network ------------------------------------------

# A drop-in rather than an edit to mysqld.cnf, so package upgrades keep working.
# The zz- prefix matters: MySQL reads mysql.conf.d/*.cnf alphabetically, and
# mysqld.cnf (which binds 127.0.0.1) has to be read first for these to win.
#
# Bound to this VM's own address rather than 0.0.0.0 - the IS VM reaches it on
# the tenant VLAN, and every other interface stays closed.
step "Binding MySQL to ${DB_HOST_IP}"
sudo tee /etc/mysql/mysql.conf.d/zz-dpdp-overrides.cnf >/dev/null <<EOF
[mysqld]
bind-address = ${DB_HOST_IP}

# Stock is 128M, which leaves an 8 GiB VM almost entirely idle. Half of RAM is
# the usual starting point for a dedicated database host.
innodb_buffer_pool_size = $(awk '/MemTotal/ {printf "%d", $2 * 0.5 / 1024 / 1024}' /proc/meminfo)G
EOF

sudo systemctl enable --now mysql
sudo systemctl restart mysql

# --- 3. databases --------------------------------------------------------------

step "Creating databases"
# ubuntu's mysql-server leaves root on auth_socket, so `sudo mysql` is the
# supported way in and no root password has to exist anywhere.
for db in "${DPDP_IDENTITY_DB}" "${DPDP_SHARED_DB}" "${DPDP_AGENT_DB}" "${DPDP_DPDP_DB}"; do
  sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`${db}\` CHARACTER SET utf8mb4;"
  info "${db}"
done

# --- 4. application user -------------------------------------------------------

# The account is locked to the IS VM's address: granting 'user'@'%' would hand
# every other tenant on the VLAN a login to our data.
step "Granting ${DPDP_DB_USER}@${DPDP_IS_VM_IP} access"

# mysql_native_password because the JDBC url is useSSL=false: Connector/J cannot
# complete caching_sha2_password's RSA key exchange over a plaintext connection
# without allowPublicKeyRetrieval. On MySQL 8.4+, where this plugin is gone,
# switch to caching_sha2_password and add that flag to the url in
# scripts/remote/patch-datasources.py.
sudo mysql <<SQL
CREATE USER IF NOT EXISTS '${DPDP_DB_USER}'@'${DPDP_IS_VM_IP}'
  IDENTIFIED WITH mysql_native_password BY '${DPDP_DB_PASSWORD}';
ALTER USER '${DPDP_DB_USER}'@'${DPDP_IS_VM_IP}'
  IDENTIFIED WITH mysql_native_password BY '${DPDP_DB_PASSWORD}';

CREATE USER IF NOT EXISTS '${DPDP_DB_USER}'@'localhost'
  IDENTIFIED WITH mysql_native_password BY '${DPDP_DB_PASSWORD}';
ALTER USER '${DPDP_DB_USER}'@'localhost'
  IDENTIFIED WITH mysql_native_password BY '${DPDP_DB_PASSWORD}';
SQL

for db in "${DPDP_IDENTITY_DB}" "${DPDP_SHARED_DB}" "${DPDP_AGENT_DB}" "${DPDP_DPDP_DB}"; do
  sudo mysql -e "GRANT ALL PRIVILEGES ON \`${db}\`.* TO '${DPDP_DB_USER}'@'${DPDP_IS_VM_IP}';"
  sudo mysql -e "GRANT ALL PRIVILEGES ON \`${db}\`.* TO '${DPDP_DB_USER}'@'localhost';"
done
sudo mysql -e 'FLUSH PRIVILEGES;'

# Non-destructive: a rebuilt IS VM leases a new address, which would otherwise
# leave a stale account behind. Reported, not deleted, so nothing is removed on
# the strength of a guess about who owns it.
stray_hosts="$(sudo mysql -N -B -e "SELECT GROUP_CONCAT(host) FROM mysql.user WHERE user='${DPDP_DB_USER}' AND host NOT IN ('${DPDP_IS_VM_IP}','localhost');" || true)"
if [ -n "${stray_hosts}" ]; then
  warn "${DPDP_DB_USER} also exists at: ${stray_hosts} - drop these if the IS VM was rebuilt with a new address."
fi

step "MySQL ready on ${DB_HOST_IP}:3306"
info "databases: ${DPDP_IDENTITY_DB}, ${DPDP_SHARED_DB}, ${DPDP_AGENT_DB}, ${DPDP_DPDP_DB}"
