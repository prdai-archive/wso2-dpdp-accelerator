#!/usr/bin/env bash
# Installs MySQL and WSO2 Identity Server across the two VMs. Run from the
# repository root, after `make apply` and `mvn clean install`.
#
#   ./scripts/setup-all.sh
#
# Order matters: MySQL has to exist and be reachable before the IS VM applies
# any schema.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "${SCRIPT_DIR}/lib.sh"

load_env

step "Checking SSH access to both VMs"
for host in "${DB_VM_IP}" "${IS_VM_IP}"; do
  ssh_run "${host}" 'true' || die "cannot ssh to ${SSH_USER}@${host} with key ${SSH_KEY}"
  info "${host} ok"
done

step "MySQL VM (${DB_VM_IP})"
remote_run "${DB_VM_IP}" "${SCRIPT_DIR}/remote/setup-mysql.sh"

step "Uploading the accelerator to ${IS_VM_IP}"
zip="$(accelerator_zip)"
info "$(basename "${zip}")"
scp_to "${zip}" "${IS_VM_IP}" /tmp/dpdp-accelerator.zip
scp_to "${SCRIPT_DIR}/remote/patch-datasources.py" "${IS_VM_IP}" /tmp/dpdp-patch-datasources.py

step "Identity Server VM (${IS_VM_IP})"
remote_run "${IS_VM_IP}" "${SCRIPT_DIR}/remote/setup-is.sh"

step "Done"
info "Identity Server : https://${IS_HOSTNAME}:9443/"
info "Consent portal  : https://${IS_HOSTNAME}:9443/consent-portal/"
info "MySQL           : ${DB_VM_IP}:3306"
info "Next            : assign dpdp-consent-user / dpdp-consent-admin - see docs/configuration-guide.md"
