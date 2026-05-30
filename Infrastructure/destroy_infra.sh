#!/bin/bash
set -euo pipefail

# Địa chỉ thư mục code
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TERRAFORM_DIR="Terraform"
HASH_FILE=".terraform_hash"

# 0. Kiểm tra môi trường có đủ công cụ cần thiết không
function check_requirements() {
    local missing_tools=()
    for tool in terraform; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "Error: Missing required tools: ${missing_tools[*]}"
        echo "Please install them before running this script."
        exit 1
    fi
}

function cleanup_local_artifacts() {
    rm -f "$HASH_FILE" "$TERRAFORM_DIR/tfplan"
}

check_requirements

echo "Initializing Terraform..."
pushd "$TERRAFORM_DIR" >/dev/null
terraform init
echo "Destroying Terraform-managed infrastructure..."
terraform destroy -auto-approve
popd >/dev/null

cleanup_local_artifacts

echo "Destroy complete. Local plan/hash artifacts removed."
