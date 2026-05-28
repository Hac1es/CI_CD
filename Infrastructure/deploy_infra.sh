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

# 0. Kiểm tra môi trường có đủ công cụ cần thiết không
function check_requirements() {
    local missing_tools=()
    for tool in terraform ansible-playbook checkov jq ssh; do
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
    
    bastion_ip=$(ansible-inventory -i "$INVENTORY_FILE" --host bastion | jq -r '.ansible_host')
    ansible_user=$(ansible-inventory -i "$INVENTORY_FILE" --host bastion | jq -r '.ansible_user // "ubuntu"')

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

# MAIN FLOW RUN

# Bước 0: Kiểm tra môi trường
check_requirements

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
wait_for_bastion_ssh

# Bước 4: Cấu hình phần mềm bên trong bằng Ansible
echo "Running Ansible Playbook..."
ansible-playbook -i "$INVENTORY_FILE" "$ANSIBLE_DIR/playbook.yml"