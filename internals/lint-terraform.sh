#!/usr/bin/env bash
# Format-check, validate, and lint Terraform under internals/terraform/.
# Usage: ./lint-terraform.sh
# Requires: terraform, tflint (see https://github.com/terraform-linters/tflint#installation).
# Config: internals/terraform/.tflint.hcl.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${ROOT}/terraform"
CONFIG="${TF_DIR}/.tflint.hcl"

command -v terraform >/dev/null || {
  echo "FAIL: terraform not found" >&2
  exit 1
}

command -v tflint >/dev/null || {
  echo "FAIL: tflint not found (https://github.com/terraform-linters/tflint#installation)" >&2
  exit 1
}

[[ -f "${CONFIG}" ]] || {
  echo "FAIL: missing ${CONFIG}" >&2
  exit 1
}

cd "${TF_DIR}"

echo "==> terraform fmt -check -recursive"
terraform fmt -check -recursive

echo "==> terraform init -backend=false"
terraform init -backend=false -input=false >/dev/null

echo "==> terraform validate"
terraform validate

echo "==> tflint --init"
tflint --init --config "${CONFIG}"

echo "==> tflint --recursive"
tflint --recursive --config "${CONFIG}"

echo "OK: terraform lint clean"
