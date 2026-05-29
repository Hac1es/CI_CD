#!/bin/bash
set -euo pipefail

# Địa chỉ thư mục code
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TERRAFORM_DIR="Terraform"
ANSIBLE_DIR="Ansible"
HASH_FILE=".terraform_hash"
INVENTORY_FILE="$ANSIBLE_DIR/inventory.ini"
export ANSIBLE_CONFIG="$SCRIPT_DIR/$ANSIBLE_DIR/ansible.cfg"
export ANSIBLE_LOCAL_TEMP="$SCRIPT_DIR/.ansible/tmp"
VAULT_PASS_FILE=""
ANSIBLE_VAULT_ARGS=()

# 0. Kiểm tra môi trường có đủ công cụ cần thiết không
function check_requirements() {
    local missing_tools=()
    for tool in terraform ansible ansible-playbook ansible-inventory checkov jq ssh; do
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

# 0.5 Chuẩn bị vault secret cho mọi lệnh ansible (prompt 1 lần)
function setup_vault_secret() {
    if [ -n "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ] && [ -f "${ANSIBLE_VAULT_PASSWORD_FILE}" ]; then
        ANSIBLE_VAULT_ARGS=(--vault-password-file "${ANSIBLE_VAULT_PASSWORD_FILE}")
        return 0
    fi

    local vault_password
    read -rsp "Vault password: " vault_password
    echo

    if [ -z "$vault_password" ]; then
        echo "Vault password cannot be empty."
        exit 1
    fi

    VAULT_PASS_FILE="$(mktemp)"
    chmod 600 "$VAULT_PASS_FILE"
    printf '%s' "$vault_password" > "$VAULT_PASS_FILE"
    unset vault_password

    ANSIBLE_VAULT_ARGS=(--vault-password-file "$VAULT_PASS_FILE")
}

function cleanup_vault_secret() {
    if [ -n "$VAULT_PASS_FILE" ] && [ -f "$VAULT_PASS_FILE" ]; then
        rm -f "$VAULT_PASS_FILE"
    fi
}

# 1. Tính mã hash của thư mục Terraform để phát hiện thay đổi
function calculate_hash() {
    find "$TERRAFORM_DIR" -type f \
        \( -name "*.tf" -o -name "*.tfvars" -o -name "*.tftpl" -o -name ".terraform.lock.hcl" \) \
        -exec sha256sum {} \; | sort -k 2 | sha256sum | awk '{print $1}'
}

# 2. SECURITY GATE: Chạy Checkov để quét Ansible và Terraform trước khi apply
function checkgate() {
    echo "Running Security Scan via Checkov..."

    # Quét Ansible
    echo "[1/2] Scanning Ansible Playbooks..."
    checkov -d "$ANSIBLE_DIR" --framework ansible --quiet
    local ANSIBLE_STATUS=$?

    # Quét Terraform
    echo "[2/2] Scanning Terraform Infrastructure..."
    checkov -d "$TERRAFORM_DIR" --framework terraform --quiet
    local TERRAFORM_STATUS=$?

    # Đánh giá kết quả (Security Gate)
    if [ $ANSIBLE_STATUS -eq 0 ] && [ $TERRAFORM_STATUS -eq 0 ]; then
        echo "SUCCESS: All infrastructure code passed Checkov security checks."
    else
        echo "FAILED: Checkov found security issues above!"
        echo "Please review the FAILED rules and fix them (or add #checkov:skip if you know what you're doing) before proceeding."
        echo "=================================================="
        exit 1
    fi
}

# 3. Chờ SSH trên bastion sẵn sàng
function wait_for_bastion_ssh() {
    echo "Extracting Bastion connection info via Ansible..."
    
    # Dùng chính ansible-inventory + jq để lấy IP và User, không sợ lỗi cú pháp file ini
    local bastion_ip
    local ansible_user
    
    bastion_ip=$(ansible-inventory -i "$INVENTORY_FILE" --host bastion "${ANSIBLE_VAULT_ARGS[@]}" | jq -r '.ansible_host')
    ansible_user=$(ansible-inventory -i "$INVENTORY_FILE" --host bastion "${ANSIBLE_VAULT_ARGS[@]}" | jq -r '.ansible_user // "ubuntu"')

    if [ -z "$bastion_ip" ] || [ "$bastion_ip" == "null" ]; then
        echo "Cannot extract bastion IP from inventory."
        exit 1
    fi

    echo "Waiting for SSH on bastion ($ansible_user@$bastion_ip)..."
    for _ in $(seq 1 30); do
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
            -i /home/tung/.ssh/google_compute_engine "$ansible_user@$bastion_ip" exit >/dev/null 2>&1; then
            echo "Bastion SSH is ready."
            return 0
        fi
        sleep 10
    done

    echo "Timed out waiting for bastion SSH."
    exit 1
}

# 3.5 Chờ SSH tới các máy private qua bastion sẵn sàng
function wait_for_private_ssh() {
    echo "Waiting for SSH on private hosts through bastion..."
    for _ in $(seq 1 30); do
        if ansible -i "$INVENTORY_FILE" private \
            -m ansible.builtin.wait_for_connection \
            -a "timeout=20 sleep=2" \
            --forks 1 \
            "${ANSIBLE_VAULT_ARGS[@]}" >/dev/null 2>&1; then
            echo "Private hosts SSH is ready."
            return 0
        fi
        sleep 10
    done

    echo "Timed out waiting for private hosts SSH through bastion."
    echo "Debug with: ansible -i $INVENTORY_FILE private -m ping -vvv"
    exit 1
}

# MAIN FLOW RUN

# Bước 0: Kiểm tra môi trường
check_requirements
setup_vault_secret
trap cleanup_vault_secret EXIT

# Bước 1: Chạy Security Gate
checkgate

# Bước 2: Kiểm tra thay đổi hạ tầng và Apply Terraform
if [ ! -f "$HASH_FILE" ] || [ "$(calculate_hash)" != "$(cat "$HASH_FILE")" ]; then
    echo "Infrastructure changes detected. Applying Terraform..."
    pushd "$TERRAFORM_DIR" >/dev/null
    terraform init
    terraform plan -out=tfplan
    terraform apply -auto-approve tfplan
    popd >/dev/null
else
    echo "No changes detected. Fast-applying Terraform..."
    pushd "$TERRAFORM_DIR" >/dev/null
    terraform apply -auto-approve
    popd >/dev/null
fi

# Lưu lại trạng thái mã hash mới
calculate_hash > "$HASH_FILE"

# Bước 3: Chờ mạng Bastion thông suốt
mkdir -p "$ANSIBLE_LOCAL_TEMP"
wait_for_bastion_ssh
wait_for_private_ssh

# Bước 4: Cấu hình phần mềm bên trong bằng Ansible
echo "Running Ansible Playbook..."
ansible-playbook -i "$INVENTORY_FILE" "$ANSIBLE_DIR/playbook.yml" "${ANSIBLE_VAULT_ARGS[@]}"
