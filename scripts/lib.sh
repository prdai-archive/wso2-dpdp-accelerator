#!/usr/bin/env bash
# Shared helpers for the data-centre install scripts. Sourced, never executed.
#
# Everything here runs on the operator's machine and drives the VMs over SSH.
# VM-side logic lives in scripts/remote/, which is copied across and executed
# rather than piped into a shell, so both sides remain independently lintable.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"

# accept-new trusts a host on first contact but refuses a changed key, which
# neither the `no` default (interactive prompt) nor `yes` (silently trusts a
# swapped host) gives us.
SSH_OPTS=()

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() {
  printf '\nWARN: %s\n' "$*" >&2
}

# --- configuration ------------------------------------------------------------

load_env() {
  [ -f "${ENV_FILE}" ] || die "no ${ENV_FILE} - copy .env.example to .env and fill it in"

  set -a
  # shellcheck source=/dev/null
  . "${ENV_FILE}"
  set +a

  SSH_USER="${SSH_USER:-ubuntu}"
  SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519}"
  [ -f "${SSH_KEY}" ] || die "SSH_KEY '${SSH_KEY}' does not exist"

  IS_VERSION="${IS_VERSION:-7.3.0}"
  IS_HOME="${IS_HOME:-/opt/wso2/wso2is-${IS_VERSION}}"
  IS_HOSTNAME="${IS_HOSTNAME:-${IS_VM_IP:-}}"
  MYSQL_CONNECTOR_VERSION="${MYSQL_CONNECTOR_VERSION:-8.3.0}"

  DB_PORT="${DB_PORT:-3306}"
  DB_APP_USER="${DB_APP_USER:-wso2carbon}"
  IDENTITY_DB="${IDENTITY_DB:-WSO2IDENTITY_DB}"
  SHARED_DB="${SHARED_DB:-WSO2SHARED_DB}"
  AGENT_DB="${AGENT_DB:-WSO2AGENTIDENTITY_DB}"
  DPDP_DB="${DPDP_DB:-WSO2DPDP_DB}"

  local required
  for required in IS_VM_IP DB_VM_IP DB_APP_PASSWORD IS_ADMIN_USERNAME IS_ADMIN_PASSWORD; do
    [ -n "${!required:-}" ] || die "${required} is not set in ${ENV_FILE}"
  done
  [ -n "${IS_HOSTNAME}" ] || die "IS_HOSTNAME is empty (and IS_VM_IP unset) - the portal's OAuth redirects depend on it"

  SSH_OPTS=(-i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new -o BatchMode=yes)
}

# The env file copied to each VM. Generated rather than checked in so no secret
# ever reaches git, and so both VMs are driven from one source of truth.
render_remote_env() {
  cat <<EOF
DPDP_DB_HOST='${DB_VM_IP}'
DPDP_DB_PORT='${DB_PORT}'
DPDP_DB_USER='${DB_APP_USER}'
DPDP_DB_PASSWORD='${DB_APP_PASSWORD}'
DPDP_IDENTITY_DB='${IDENTITY_DB}'
DPDP_SHARED_DB='${SHARED_DB}'
DPDP_AGENT_DB='${AGENT_DB}'
DPDP_DPDP_DB='${DPDP_DB}'
DPDP_IS_VM_IP='${IS_VM_IP}'
DPDP_IS_HOSTNAME='${IS_HOSTNAME}'
DPDP_IS_VERSION='${IS_VERSION}'
DPDP_IS_HOME='${IS_HOME}'
DPDP_ADMIN_USERNAME='${IS_ADMIN_USERNAME}'
DPDP_ADMIN_PASSWORD='${IS_ADMIN_PASSWORD}'
DPDP_MYSQL_CONNECTOR_VERSION='${MYSQL_CONNECTOR_VERSION}'
EOF
}

# --- ssh plumbing -------------------------------------------------------------

ssh_run() {
  local host="$1"
  shift
  # Arguments are deliberately expanded on the operator machine before SSH.
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "$@"
}

scp_to() {
  local src="$1" host="$2" dst="$3"
  scp "${SSH_OPTS[@]}" -q "${src}" "${SSH_USER}@${host}:${dst}"
}

# Copies a script into a private temp dir on the VM and runs it there. The env
# file is streamed over stdin rather than passed as argv, and the whole command
# runs as one ssh session that deletes the directory on the way out, so the
# database password never appears in the remote process list or on disk.
remote_run() {
  local host="$1" script="$2"
  local dir name

  name="$(basename "${script}")"
  dir="$(ssh_run "${host}" 'umask 077 && mktemp -d')"

  scp_to "${script}" "${host}" "${dir}/${name}"
  render_remote_env | ssh_run "${host}" "cat > '${dir}/dpdp-env.sh'"
  ssh_run "${host}" "bash '${dir}/${name}' '${dir}/dpdp-env.sh'; rc=\$?; rm -rf '${dir}'; exit \$rc"
}

accelerator_zip() {
  local -a matches=("${REPO_ROOT}"/dpdp-accelerator/accelerators/dpdp-is/target/wso2-dpdp-is-accelerator-*.zip)

  if [ "${#matches[@]}" -eq 0 ] || [ ! -e "${matches[0]}" ]; then
    die "no accelerator zip under dpdp-accelerator/accelerators/dpdp-is/target/ - run 'mvn clean install' from the repository root first"
  fi
  if [ "${#matches[@]}" -gt 1 ]; then
    die "found ${#matches[@]} accelerator zips under dpdp-accelerator/accelerators/dpdp-is/target/ - run 'mvn clean' and rebuild so there is exactly one"
  fi
  printf '%s' "${matches[0]}"
}
