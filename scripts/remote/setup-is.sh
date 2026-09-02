#!/usr/bin/env bash
# Runs ON the Identity Server VM (copied there and executed by
# scripts/setup-all.sh).
#
# Installs WSO2 IS 7.3.0 plus the DPDP accelerator, repoints every datasource at
# the MySQL VM, and registers the server with systemd. Idempotent: re-running
# redeploys the accelerator (which is what merge.sh is for) without ever
# re-applying a database schema, so re-provisioning a running system is safe.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: %s <env-file>\n' "$(basename "$0")" >&2
  exit 2
fi
# shellcheck source=/dev/null
. "$1"

IS_HOME="${DPDP_IS_HOME}"
ACC_DIR=/opt/wso2/dpdp-accelerator
ACC_ZIP=/tmp/dpdp-accelerator.zip
PATCHER=/tmp/dpdp-patch-datasources.py
SERVICE=wso2is

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() {
  printf '\nWARN: %s\n' "$*" >&2
}
die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

# --- 1. packages and service account ------------------------------------------

step "Installing packages"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
# mysql-client to apply the IS schema over the network, python3 for the
# deployment.toml patcher below.
sudo apt-get install -y -qq openjdk-21-jdk unzip curl mysql-client python3

step "Creating the wso2 service account"
if ! id -u wso2 >/dev/null 2>&1; then
  sudo useradd --system --home-dir /opt/wso2 --shell /usr/sbin/nologin wso2
fi

# --- 2. WSO2 Identity Server ---------------------------------------------------

step "Installing WSO2 Identity Server ${DPDP_IS_VERSION}"
if [ -x "${IS_HOME}/bin/wso2server.sh" ]; then
  info "already unpacked at ${IS_HOME}, skipping download"
else
  tmp="$(mktemp -d)"
  base="https://github.com/wso2/product-is/releases/download/v${DPDP_IS_VERSION}"
  curl -fL --retry 3 -o "${tmp}/wso2is.zip" "${base}/wso2is-${DPDP_IS_VERSION}.zip"
  curl -fL --retry 3 -o "${tmp}/wso2is.zip.sha256" "${base}/wso2is-${DPDP_IS_VERSION}.zip.sha256"
  # Fail here on a truncated download rather than at first startup, where it
  # would surface as an unrelated bootstrap error.
  (cd "${tmp}" && echo "$(cut -d' ' -f1 wso2is.zip.sha256)  wso2is.zip" | sha256sum -c -)
  sudo mkdir -p /opt/wso2
  sudo unzip -q "${tmp}/wso2is.zip" -d /opt/wso2
  rm -rf "${tmp}"
  [ -x "${IS_HOME}/bin/wso2server.sh" ] || die "no ${IS_HOME}/bin/wso2server.sh after unpacking - did the pack layout change?"
fi

step "Installing MySQL Connector/J ${DPDP_MYSQL_CONNECTOR_VERSION}"
# Pinned to the version the repository itself builds against
# (mysql.connector.version in pom.xml) so the deployed driver matches the one
# the tests exercise.
connector="mysql-connector-j-${DPDP_MYSQL_CONNECTOR_VERSION}.jar"
if [ -f "${IS_HOME}/repository/components/lib/${connector}" ]; then
  info "already installed"
else
  sudo curl -fsSL -o "${IS_HOME}/repository/components/lib/${connector}" \
    "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/${DPDP_MYSQL_CONNECTOR_VERSION}/${connector}"
fi

# --- 3. accelerator ------------------------------------------------------------

step "Installing the DPDP accelerator"
[ -f "${ACC_ZIP}" ] || die "no ${ACC_ZIP} - it should have been uploaded by scripts/setup-all.sh"
[ -f "${PATCHER}" ] || die "no ${PATCHER} - it should have been uploaded by scripts/setup-all.sh"

# Extracted fresh every run rather than over the top: merge.sh deletes stale
# artifacts from the product, but it cannot know about files the accelerator
# itself stopped shipping.
sudo rm -rf "${ACC_DIR}"
sudo mkdir -p "${ACC_DIR}.tmp" "${ACC_DIR}"
sudo unzip -q "${ACC_ZIP}" -d "${ACC_DIR}.tmp"
# The zip carries a versioned top-level directory; hoist its contents so the
# paths below don't change on every release.
inner="$(sudo find "${ACC_DIR}.tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
[ -n "${inner}" ] || die "unexpected accelerator zip layout - no top-level directory"
sudo cp -a "${inner}/." "${ACC_DIR}/"
sudo rm -rf "${ACC_DIR}.tmp"

# --- 4. configure.properties ---------------------------------------------------

# These are the values configure.sh substitutes into the shipped deployment.toml
# and reads to decide which schema steps to run. Both migration flags are off
# because configure.sh can only apply them to the bundled H2 database - the
# MySQL equivalents are applied directly in step 7 below.
step "Setting configure.properties"
PROPS="${ACC_DIR}/repository/conf/configure.properties"

set_prop() {
  local key="$1" value="$2" escaped
  escaped="$(printf '%s' "${value}" | sed -e 's/[\\&|]/\\&/g')"
  if sudo grep -q "^${key}=" "${PROPS}"; then
    sudo sed -i "s|^${key}=.*|${key}=${escaped}|" "${PROPS}"
  else
    printf '%s=%s\n' "${key}" "${value}" | sudo tee -a "${PROPS}" >/dev/null
  fi
}

# IS_HOSTNAME is what the portal's OAuth redirects and the consent-portal base
# path are built from, so it has to be the address users actually reach.
set_prop IS_HOSTNAME "${DPDP_IS_HOSTNAME}"
set_prop IS_PORT 9443
set_prop IS_ADMIN_USERNAME "${DPDP_ADMIN_USERNAME}"
set_prop IS_ADMIN_PASSWORD "${DPDP_ADMIN_PASSWORD}"
set_prop DB_TYPE mysql
# dbscripts/consent/mysql.sql below creates the v2 schema outright; the
# migration is an upgrade path for a database that already has v1 tables, and
# applying it here would collide with that script.
set_prop APPLY_IS_CONSENT_MGT_V2_MIGRATION false
set_prop APPLY_DPDP_DB_MIGRATION false

info "IS_HOSTNAME=${DPDP_IS_HOSTNAME}, DB_TYPE=mysql"

# --- 5. merge and configure ----------------------------------------------------

# configure.sh replaces deployment.toml and refuses to run against a live
# server, so the service has to be down before this point.
step "Stopping ${SERVICE} (if running)"
sudo systemctl stop "${SERVICE}" 2>/dev/null || true

step "Merging the accelerator into ${IS_HOME}"
sudo bash "${ACC_DIR}/bin/merge.sh" "${IS_HOME}"

step "Configuring ${IS_HOME}"
sudo bash "${ACC_DIR}/bin/configure.sh" "${IS_HOME}"

# --- 6. database connectivity --------------------------------------------------

# Credentials in a 0600 defaults file instead of -p on the command line, which
# is visible to every process on the box via /proc.
MY_CNF="$(mktemp)"
chmod 600 "${MY_CNF}"
cleanup() { rm -f "${MY_CNF}"; }
trap cleanup EXIT

cat >"${MY_CNF}" <<EOF
[client]
host=${DPDP_DB_HOST}
port=${DPDP_DB_PORT}
user=${DPDP_DB_USER}
password=${DPDP_DB_PASSWORD}
EOF

step "Checking MySQL reachability at ${DPDP_DB_HOST}:${DPDP_DB_PORT}"
mysql --defaults-extra-file="${MY_CNF}" -e 'SELECT 1;' >/dev/null ||
  die "cannot reach MySQL - check that setup-mysql.sh ran, that ${DPDP_DPDP_DB}'s grant is for this VM's address (${DPDP_IS_VM_IP}), and that nothing between the VMs blocks 3306"

# --- 7. schema -----------------------------------------------------------------

# Applied per database, not per script: the identity database takes two scripts,
# so a per-script "does it have tables yet" check would skip the second one on
# a first run. Skipping a populated database is what makes re-provisioning safe.
db_has_tables() {
  [ "$(mysql --defaults-extra-file="${MY_CNF}" -N -B \
    -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${1}';")" -gt 0 ]
}

apply_group() {
  local db="$1"
  shift

  if db_has_tables "${db}"; then
    info "skipping ${db} - it already has tables (schema applied previously)"
    return
  fi

  local script
  for script in "$@"; do
    info "applying ${script} -> ${db}"
    mysql --defaults-extra-file="${MY_CNF}" "${db}" <"${script}"
  done
}

step "Applying the Identity Server schema"
SHARED_SCRIPT="${IS_HOME}/dbscripts/mysql.sql"
IDENTITY_SCRIPT="${IS_HOME}/dbscripts/identity/mysql.sql"
CONSENT_SCRIPT="${IS_HOME}/dbscripts/consent/mysql.sql"
AGENT_SCRIPT="${IS_HOME}/dbscripts/identity/agent/mysql.sql"

[ -f "${SHARED_SCRIPT}" ] || die "missing ${SHARED_SCRIPT} - unexpected IS pack layout"
[ -f "${IDENTITY_SCRIPT}" ] || die "missing ${IDENTITY_SCRIPT} - unexpected IS pack layout"

# Consent v2 is the API the whole portal runs on, so a missing script is worth
# shouting about rather than silently degrading into a broken portal later.
if [ -f "${CONSENT_SCRIPT}" ]; then
  apply_group "${DPDP_IDENTITY_DB}" "${IDENTITY_SCRIPT}" "${CONSENT_SCRIPT}"
else
  warn "no ${CONSENT_SCRIPT} - the consent-mgt v2 schema will be missing and the portal will fail"
  apply_group "${DPDP_IDENTITY_DB}" "${IDENTITY_SCRIPT}"
fi

apply_group "${DPDP_SHARED_DB}" "${SHARED_SCRIPT}"

if [ -f "${AGENT_SCRIPT}" ]; then
  apply_group "${DPDP_AGENT_DB}" "${AGENT_SCRIPT}"
else
  warn "no ${AGENT_SCRIPT} - skipping the agent identity database"
fi

step "Applying the DPDP accelerator schema"
dpdp_scripts=()
for script in "${ACC_DIR}"/carbon-home/dbscripts/dpdp-accelerator/*/mysql.sql; do
  [ -f "${script}" ] && dpdp_scripts+=("${script}")
done
[ "${#dpdp_scripts[@]}" -gt 0 ] || die "no per-feature mysql.sql under ${ACC_DIR}/carbon-home/dbscripts/dpdp-accelerator/"
apply_group "${DPDP_DPDP_DB}" "${dpdp_scripts[@]}"

# --- 8. point the server at MySQL ----------------------------------------------

step "Repointing deployment.toml at MySQL"
sudo python3 "${PATCHER}" \
  --deployment-toml "${IS_HOME}/repository/conf/deployment.toml" \
  --host "${DPDP_DB_HOST}" \
  --port "${DPDP_DB_PORT}" \
  --user "${DPDP_DB_USER}" \
  --password "${DPDP_DB_PASSWORD}" \
  --identity-db "${DPDP_IDENTITY_DB}" \
  --shared-db "${DPDP_SHARED_DB}" \
  --agent-db "${DPDP_AGENT_DB}" \
  --dpdp-db "${DPDP_DPDP_DB}"

rm -f "${PATCHER}" "${ACC_ZIP}"

# --- 9. systemd ----------------------------------------------------------------

step "Installing the ${SERVICE} systemd unit"
JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"

# Type=forking rather than Type=simple so the product's own `wso2server.sh
# start|stop` keeps working alongside systemctl: with Type=simple, an operator
# who starts the server by hand leaves systemd unaware and a later
# `systemctl start` launches a second instance against the same database.
#
# The trade-off is that `ExecStart` returns as soon as the process backgrounds,
# so `systemctl start` succeeding says nothing about readiness - hence the
# explicit wait for the startup log line below.
sudo tee "/etc/systemd/system/${SERVICE}.service" >/dev/null <<EOF
[Unit]
Description=WSO2 Identity Server ${DPDP_IS_VERSION}
After=network.target

[Service]
Type=forking
User=wso2
Group=wso2
Environment=JAVA_HOME=${JAVA_HOME}
WorkingDirectory=${IS_HOME}
PIDFile=${IS_HOME}/wso2carbon.pid
ExecStart=${IS_HOME}/bin/wso2server.sh start
ExecStop=${IS_HOME}/bin/wso2server.sh stop
Restart=on-failure
RestartSec=15
TimeoutStopSec=120
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo chown -R wso2:wso2 "${IS_HOME}"
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE}"

# --- 10. start -----------------------------------------------------------------

# Compared against the log from this point on: a previous run's "started" line
# would otherwise satisfy the wait before this start has done anything.
log="${IS_HOME}/repository/logs/wso2carbon.log"
offset="$(sudo stat -c %s "${log}" 2>/dev/null || echo 0)"

step "Starting ${SERVICE}"
sudo systemctl restart "${SERVICE}"

step "Waiting for startup"
deadline=$((SECONDS + 600))
until sudo tail -c "+$((offset + 1))" "${log}" 2>/dev/null | grep -q "WSO2 Identity Server started in"; do
  if [ "${SECONDS}" -ge "${deadline}" ]; then
    sudo journalctl -u "${SERVICE}" -n 100 --no-pager || true
    die "${SERVICE} did not report startup within 10 minutes"
  fi
  sleep 10
done

step "Identity Server is up"
info "https://${DPDP_IS_HOSTNAME}:9443/consent-portal/"
info "Next: assign the dpdp-consent-user / dpdp-consent-admin roles - see docs/configuration-guide.md"
