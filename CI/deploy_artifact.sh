#!/bin/bash
set -euo pipefail

# Dia chi thu muc code
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_DIR="nodejs-demoapp"
SRC_DIR="$APP_DIR/src"
SONAR_CONTAINER_NAME="${SONAR_CONTAINER_NAME:-sonarqube}"
SONAR_IMAGE="${SONAR_IMAGE:-sonarqube:lts-community}"
SONAR_HOST_URL="${SONAR_HOST_URL:-http://localhost:9000}"
SONAR_ADMIN_USER="${SONAR_ADMIN_USER:-admin}"
SONAR_ADMIN_PASSWORD="${SONAR_ADMIN_PASSWORD:-admin}"
SONAR_TOKEN_NAME="${SONAR_TOKEN_NAME:-nodejs-demoapp-local-scan}"
SONAR_TOKEN_FILE="${SONAR_TOKEN_FILE:-$SCRIPT_DIR/.sonar_token}"
NODE_IMAGE="${NODE_IMAGE:-node:20-alpine}"
NODE_RUNNER="docker"
SONAR_CONTAINER_STARTED_BY_SCRIPT=0

# 0. Kiem tra moi truong co du cong cu can thiet khong
function check_requirements() {
    local missing_tools=()
    for tool in docker curl jq sonar-scanner; do
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

function setup_node_runtime() {
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        if node -e "const major = Number(process.versions.node.split('.')[0]); process.exit(major >= 20 ? 0 : 1)"; then
            NODE_RUNNER="local"
            echo "Using local Node.js runtime: $(node --version)"
            return 0
        fi

        echo "Local Node.js is too old: $(node --version)"
    else
        echo "Local Node.js/npm not found."
    fi

    NODE_RUNNER="docker"
    echo "Using Docker Node.js runtime: $NODE_IMAGE"
}

function run_node_command() {
    local command="$1"

    if [ "$NODE_RUNNER" = "local" ]; then
        bash -lc "$command"
        return 0
    fi

    docker run --rm \
        -u "$(id -u):$(id -g)" \
        -e HOME=/tmp \
        -e npm_config_cache=/tmp/.npm \
        -v "$SCRIPT_DIR/$SRC_DIR:/app" \
        -w /app \
        "$NODE_IMAGE" \
        sh -lc "$command"
}

function cleanup_sonarqube_container() {
    if [ "$SONAR_CONTAINER_STARTED_BY_SCRIPT" -eq 1 ]; then
        echo "Stopping SonarQube container started by this script..."
        docker stop "$SONAR_CONTAINER_NAME" >/dev/null
    fi
}

function wait_for_sonarqube() {
    echo "Waiting for SonarQube server at $SONAR_HOST_URL..."

    for _ in $(seq 1 60); do
        if curl -fsS "$SONAR_HOST_URL/api/system/status" 2>/dev/null | grep -q '"status":"UP"'; then
            echo "SonarQube server is ready."
            return 0
        fi
        sleep 5
    done

    echo "Timed out waiting for SonarQube server."
    echo "Debug with: docker logs $SONAR_CONTAINER_NAME"
    exit 1
}

function ensure_sonarqube_server() {
    if docker inspect "$SONAR_CONTAINER_NAME" >/dev/null 2>&1; then
        if [ "$(docker inspect -f '{{.State.Running}}' "$SONAR_CONTAINER_NAME")" = "true" ]; then
            echo "SonarQube container '$SONAR_CONTAINER_NAME' is already running."
        else
            echo "Starting existing SonarQube container '$SONAR_CONTAINER_NAME'..."
            docker start "$SONAR_CONTAINER_NAME" >/dev/null
            SONAR_CONTAINER_STARTED_BY_SCRIPT=1
        fi
    else
        echo "SonarQube container '$SONAR_CONTAINER_NAME' not found. Creating and starting it..."
        docker run -d \
            --name "$SONAR_CONTAINER_NAME" \
            -p 9000:9000 \
            "$SONAR_IMAGE" >/dev/null
        SONAR_CONTAINER_STARTED_BY_SCRIPT=1
    fi

    wait_for_sonarqube
}

function ensure_sonar_token() {
    if [ -n "${SONAR_TOKEN:-}" ]; then
        echo "Using SONAR_TOKEN from environment."
        return 0
    fi

    if [ -f "$SONAR_TOKEN_FILE" ]; then
        SONAR_TOKEN="$(tr -d '\n\r' < "$SONAR_TOKEN_FILE")"
        export SONAR_TOKEN

        if [ -n "$SONAR_TOKEN" ]; then
            echo "Using cached SonarQube token from $SONAR_TOKEN_FILE."
            return 0
        fi
    fi

    echo "SONAR_TOKEN is not set. Generating token '$SONAR_TOKEN_NAME' via SonarQube API..."

    # Revoke the old token name first so reruns stay deterministic.
    curl -fsS \
        -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASSWORD" \
        -X POST "$SONAR_HOST_URL/api/user_tokens/revoke" \
        -d "name=$SONAR_TOKEN_NAME" >/dev/null 2>&1 || true

    local token_response
    token_response="$(
        curl -fsS \
            -u "$SONAR_ADMIN_USER:$SONAR_ADMIN_PASSWORD" \
            -X POST "$SONAR_HOST_URL/api/user_tokens/generate" \
            -d "name=$SONAR_TOKEN_NAME"
    )"

    SONAR_TOKEN="$(printf '%s' "$token_response" | jq -r '.token // empty')"
    export SONAR_TOKEN

    if [ -z "$SONAR_TOKEN" ]; then
        echo "Error: Could not generate SonarQube token."
        echo "Check SONAR_ADMIN_USER/SONAR_ADMIN_PASSWORD or create SONAR_TOKEN manually."
        exit 1
    fi

    umask 077
    printf '%s\n' "$SONAR_TOKEN" > "$SONAR_TOKEN_FILE"
    echo "Generated and cached SonarQube token at $SONAR_TOKEN_FILE."
}

# 1. QUALITY GATE: npm build, ESLint va SonarQube phai pass truoc khi build/ship artifact
function checkgate() {
    echo "Running Artifact Quality Gate..."

    echo "[1/7] Checking SonarQube server..."
    ensure_sonarqube_server
    ensure_sonar_token

    echo "[2/7] Installing Node.js dependencies..."
    pushd "$SRC_DIR" >/dev/null
    run_node_command "npm ci"

    echo "[3/7] Applying safe npm audit fixes..."
    run_node_command "npm audit fix; status=\$?; if [ \$status -gt 1 ]; then exit \$status; fi"

    echo "[4/7] Running npm audit..."
    run_node_command "npm audit --audit-level=critical"

    echo "[5/7] Running npm build..."
    run_node_command "npm run build"

    echo "[6/7] Running ESLint..."
    run_node_command "npx eslint ."
    popd >/dev/null

    echo "[7/7] Running SonarQube scan and waiting for Quality Gate..."
    pushd "$APP_DIR" >/dev/null
    sonar-scanner \
        -Dsonar.host.url="$SONAR_HOST_URL" \
        -Dsonar.token="$SONAR_TOKEN" \
        -Dsonar.projectKey="nodejs-demoapp" \
        -Dsonar.projectName="nodejs-demoapp" \
        -Dsonar.sources="src" \
        -Dsonar.exclusions="src/node_modules/**,src/public/**" \
        -Dsonar.qualitygate.wait=true
    popd >/dev/null

    echo "SUCCESS: Artifact passed npm build, ESLint and SonarQube Quality Gate."
}

# MAIN FLOW RUN
check_requirements
setup_node_runtime
trap cleanup_sonarqube_container EXIT
checkgate
