#!/usr/bin/env bash
# Interactive shell on one of the VMs: ./scripts/ssh.sh is|db [-- extra ssh args]
#
# The key is the one named by SSH_KEY in .env, which is the same key Terraform
# injects into the VMs, so no separate credential is involved.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "${SCRIPT_DIR}/lib.sh"

role="${1:-}"
[ -n "${role}" ] || die "usage: $(basename "$0") is|db [-- extra ssh args]"
shift

load_env

case "${role}" in
is | identity | is-vm) host="${IS_VM_IP}" ;;
db | mysql | db-vm) host="${DB_VM_IP}" ;;
*) die "unknown VM '${role}' - expected 'is' or 'db'" ;;
esac

[ -n "${host}" ] || die "${role} VM has no address in ${ENV_FILE} - run 'make ips' and set it"

info "ssh ${SSH_USER}@${host}"
exec ssh "${SSH_OPTS[@]}" -t "${SSH_USER}@${host}" "$@"
