#!/bin/bash
set -e

###############################################################################
#                         JENKINS DEPLOYMENT SCRIPT                           #
###############################################################################

### PARAMS ###
BRANCH="${1:-main}"
REPO_URL="${2:-}"
BACKUP_TIMESTAMP="${3:-$(date +%Y%m%d_%H%M%S)}"
shift 3 2>/dev/null || true
SERVICES="$@"

### CONFIG ###
PROJECT_NAME="TAX"
DEPLOY_DIR="${WORKSPACE:-$(pwd)}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Deploying $PROJECT_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📌 Branch     : $BRANCH"
echo "📌 Deploy Dir : $DEPLOY_DIR"
echo "📌 Services   : ${SERVICES:-all}"
echo "📌 Backup     : $BACKUP_TIMESTAMP"
echo ""

### ROLLBACK SETUP ###
export BACKUP_DIR="/opt/${PROJECT_NAME}_backup/$BACKUP_TIMESTAMP"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLLBACK_SCRIPT="$SCRIPT_DIR/rollback.sh"
export BRANCH REPO_URL DEPLOY_DIR PROJECT_NAME BACKUP_DIR SERVICES

if [ -f "$ROLLBACK_SCRIPT" ]; then
  source "$ROLLBACK_SCRIPT"
  trap 'rollback $?' ERR
  trap '[[ $? -ne 0 ]] && rollback $?' EXIT
else
  echo "⚠️  Warning: rollback.sh not found at $ROLLBACK_SCRIPT — rollback disabled"
fi

###############################################################################
#                               HELPER FUNCTIONS                              #
###############################################################################

load_env_vars() {
  echo "▶ Validating environment variables..."

  local env_file=".env"

  get_env_val() {
    local key=$1
    if [ -f "$env_file" ]; then
      grep -m1 "^${key}=" "$env_file" | cut -d'=' -f2- \
        | sed -e 's/^"//; s/"$//' -e "s/^'//; s/'$//" || true
    fi
  }

  [ -z "$HOST_SONAR_SCANER_URL" ]  && HOST_SONAR_SCANER_URL=$(get_env_val "HOST_SONAR_SCANER_URL")
  [ -z "$ZAP_HOST_TARGET_DEPLOY" ] && ZAP_HOST_TARGET_DEPLOY=$(get_env_val "ZAP_HOST_TARGET_DEPLOY")
  [ -z "$SONAR_TOKEN_API_QR" ]            && SONAR_TOKEN_API_QR=$(get_env_val "SONAR_TOKEN_API_QR")
  [ -z "$SONAR_PROJECT_KEY_API_QR" ]      && SONAR_PROJECT_KEY_API_QR=$(get_env_val "SONAR_PROJECT_KEY_API_QR")
  [ -z "$ZAP_HOST_API_URL" ]       && ZAP_HOST_API_URL=$(get_env_val "ZAP_HOST_API_URL")
  [ -z "$ZAP_API_KEY" ]            && ZAP_API_KEY=$(get_env_val "ZAP_API_KEY")
  [ -z "$WEBHOOK_URL_HOST" ]       && WEBHOOK_URL_HOST=$(get_env_val "WEBHOOK_URL_HOST")

  [ -n "$HOST_SONAR_SCANER_URL" ]  && echo "  ✓ HOST_SONAR_SCANER_URL=$HOST_SONAR_SCANER_URL"
  [ -n "$ZAP_HOST_API_URL" ]       && echo "  ✓ ZAP_HOST_API_URL=$ZAP_HOST_API_URL"
  [ -n "$ZAP_API_KEY" ]            && echo "  ✓ ZAP_API_KEY is set"
  [ -n "$ZAP_HOST_TARGET_DEPLOY" ] && echo "  ✓ ZAP_HOST_TARGET_DEPLOY is set"
  [ -n "$SONAR_TOKEN_API_QR" ]            && echo "  ✓ SONAR_TOKEN_API_QR is set"
  [ -n "$SONAR_PROJECT_KEY_API_QR" ]      && echo "  ✓ SONAR_PROJECT_KEY_API_QR=$SONAR_PROJECT_KEY_API_QR"
  [ -n "$WEBHOOK_URL_HOST" ]       && echo "  ✓ WEBHOOK_URL_HOST=$WEBHOOK_URL_HOST"
  echo "  ✓ Environment validation complete."
}

###############################################################################
#                         BACKUP (ก่อน deploy)                               #
###############################################################################

create_backup() {
  echo ""
  echo "💾 Creating backup before deploy..."
  echo "   Source : $DEPLOY_DIR"
  echo "   Target : $BACKUP_DIR"

  mkdir -p "$BACKUP_DIR"

  rsync -a \
    --exclude='.git' \
    --exclude='zap_reports' \
    --exclude='test_reports' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    "$DEPLOY_DIR/" "$BACKUP_DIR/" 2>/dev/null || {
    echo "  ⚠️  rsync failed, falling back to cp..."
    cp -rf "$DEPLOY_DIR/." "$BACKUP_DIR/" 2>/dev/null || true
  }

  echo "  ✓ Backup created at: $BACKUP_DIR"
}

###############################################################################
#                         AUTOMATED TESTING                                   #
###############################################################################

run_automated_tests() {
  echo "🧪 Running Pytest INSIDE Docker..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  cd "$DEPLOY_DIR"
  
  # 1. สร้างโฟลเดอร์รอไว้ก่อนเลย
  local test_report_dir="$DEPLOY_DIR/test_reports"
  mkdir -p "$test_report_dir"
  local log_file="$test_report_dir/pytest_result_${BACKUP_TIMESTAMP}.log"

  echo "🐳 Starting Redis..."
  docker compose up -d redis

  set +e
  echo "▶ Executing pytest (Logging to $log_file)..."

  docker compose run --rm qrcode-generator-api pytest tests/ > "$log_file" 2>&1
  
  local test_exit=$?
  set -e

  if [ $test_exit -ne 0 ]; then
    echo ""
    echo "❌ Pytest FAILED (exit code $test_exit)"
    echo "🔍 รายละเอียดความซวยอยู่ในไฟล์: $log_file"
    tail -n 10 "$log_file"
    exit 1
  fi

  echo ""
  echo "✅ All tests passed! Log saved to $log_file"
}

###############################################################################
#                         BUILD & DEPLOY                                      #
###############################################################################

build() {
  cd "$DEPLOY_DIR"

  echo ""
  echo "🔨 Building Docker images..."
  if [ -z "$SERVICES" ]; then
    docker compose build
  else
    docker compose build $SERVICES
  fi
}

deploy() {
  cd "$DEPLOY_DIR"

  echo ""
  echo "🐳 Starting containers..."
  if [ -z "$SERVICES" ]; then
    docker compose up -d
  else
    docker compose up -d --no-deps $SERVICES
  fi

  echo ""
  echo "⏳ Waiting for services to start..."
  sleep 5
  echo "✅ Services started"
}

###############################################################################
#                              ZAP SECURITY SCAN                              #
###############################################################################

ZAP_SLEEP_SPIDER="${ZAP_SLEEP_SPIDER:-2}"
ZAP_SLEEP_ASCAN="${ZAP_SLEEP_ASCAN:-5}"
ZAP_WEBHOOK_TIMEOUT="${ZAP_WEBHOOK_TIMEOUT:-30}"

_zap_api() {
  curl -s "${ZAP_HOST_API_URL}/JSON/${1}&apikey=${ZAP_API_KEY}"
}

_zap_wait_for() {
  # Usage: _zap_wait_for <api_path> <json_field> <done_value> <label> <sleep_sec>
  local api_path="$1" field="$2" done_val="$3" label="$4" sleep_sec="$5"
  while true; do
    local value
    value=$(_zap_api "$api_path" | jq -r ".${field} // empty")
    echo -ne "      ${label}: ${value}\r"
    [ "$value" = "$done_val" ] || [ -z "$value" ] && break
    sleep "$sleep_sec"
  done
  echo -e "\n      ✅ ${label} completed"
}

_count_alerts() {
  jq --arg r "$2" '[.alerts[]? | select(.risk==$r)] | length' "$1" 2>/dev/null || echo 0
}

_get_services_to_scan() {
  if [ -n "$SERVICES" ]; then
    echo "$SERVICES"
    return
  fi

  local running
  running=$(docker compose ps --format '{{.Service}}' 2>/dev/null | tr '\n' ' ' | xargs)
  if [ -z "$running" ]; then
    running=$(docker compose config --services 2>/dev/null | while read -r svc; do
      [ -n "$(docker compose ps -q "$svc" 2>/dev/null)" ] && echo "$svc"
    done | tr '\n' ' ' | xargs)
  fi
  echo "$running"
}

run_zap_scan() {
  echo ""
  echo "🔍 Starting OWASP ZAP Scan"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [ -z "$ZAP_HOST_API_URL" ] || [ -z "$ZAP_API_KEY" ]; then
    echo "⚠️  ZAP configuration not found — skipping security scan"
    return 0
  fi

  local report_dir="$DEPLOY_DIR/zap_reports"
  mkdir -p "$report_dir"

  # Ensure ZAP is running
  echo "▶ Checking ZAP daemon..."
  local zap_status
  set +e
  zap_status=$(curl -s -o /dev/null -w "%{http_code}" \
    "${ZAP_HOST_API_URL}/JSON/core/view/version/?apikey=${ZAP_API_KEY}" 2>/dev/null)
  set -e

  if [ "$zap_status" != "200" ]; then
    echo "⚠️  ZAP not ready — attempting to start via docker-compose.zap.yml..."
    docker compose -f "$DEPLOY_DIR/docker-compose.zap.yml" up -d

    for i in {1..15}; do
      sleep 2
      set +e
      zap_status=$(curl -s -o /dev/null -w "%{http_code}" \
        "${ZAP_HOST_API_URL}/JSON/core/view/version/?apikey=${ZAP_API_KEY}" 2>/dev/null)
      set -e
      [ "$zap_status" = "200" ] && break
    done

    if [ "$zap_status" != "200" ]; then
      echo "❌ ZAP failed to start — aborting"
      exit 1
    fi
  fi
  echo "✓ ZAP ready"

  local services_to_scan
  services_to_scan=$(_get_services_to_scan)

  if [ -z "$services_to_scan" ]; then
    echo "⚠️  No running services found — skipping ZAP scan"
    return 0
  fi

  echo "📋 Scanning services: $services_to_scan"

  local has_critical=false

  for svc in $services_to_scan; do
    echo ""
    echo "🎯 Scanning: $svc"

    local container
    set +e
    container=$(docker compose ps -q "$svc" 2>/dev/null)
    set -e

    if [ -z "$container" ]; then
      echo "   ⚠️  No container — skip"
      continue
    fi

    local port
    set +e
    port=$(docker inspect "$container" 2>/dev/null \
      | jq -r '.[0].HostConfig.PortBindings | to_entries | .[0].value[0].HostPort // empty')
    set -e

    if [ -z "$port" ]; then
      echo "   ⚠️  No exposed port — skip"
      continue
    fi

    local target="http://${ZAP_HOST_TARGET_DEPLOY}:${port}/"
    local json_report="$report_dir/zap_${svc}_${BACKUP_TIMESTAMP}.json"
    local html_report="$report_dir/zap_${svc}_${BACKUP_TIMESTAMP}.html"

    echo "   🎯 Target: $target"

    # Clear session
    _zap_api "core/action/newSession/?overwrite=true" > /dev/null

    # Spider
    echo "   🕷️  Starting Spider..."
    local spider_id
    spider_id=$(_zap_api "spider/action/scan/?url=${target}" | jq -r '.scan // empty')
    [ -n "$spider_id" ] && _zap_wait_for \
      "spider/view/status/?scanId=${spider_id}" \
      "status" "100" "Spider Progress" "$ZAP_SLEEP_SPIDER"

    # Active Scan
    echo "   🚀 Starting Active Scan..."
    local ascan_id
    ascan_id=$(_zap_api "ascan/action/scan/?url=${target}" | jq -r '.scan // empty')
    [ -n "$ascan_id" ] && _zap_wait_for \
      "ascan/view/status/?scanId=${ascan_id}" \
      "status" "100" "Active Scan Progress" "$ZAP_SLEEP_ASCAN"

    # Export reports
    _zap_api "core/view/alerts/?baseurl=${target}" > "$json_report"
    curl -s "${ZAP_HOST_API_URL}/OTHER/core/other/htmlreport/?apikey=${ZAP_API_KEY}" > "$html_report"

    # Parse results
    local high medium low info
    high=$(_count_alerts "$json_report" "High")
    medium=$(_count_alerts "$json_report" "Medium")
    low=$(_count_alerts "$json_report" "Low")
    info=$(_count_alerts "$json_report" "Informational")

    local total_blocking=$(( high + medium ))
    local total_all=$(( high + medium + low + info ))

    echo ""
    echo "   📊 ZAP Results for $svc"
    echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "    🔴 High          : %-4s ← blocks deploy\n" "$high"
    printf "    🟠 Medium        : %-4s ← blocks deploy\n" "$medium"
    printf "    🟡 Low           : %-4s ← warn only\n"     "$low"
    printf "    ℹ️  Informational : %-4s ← warn only\n"    "$info"
    echo "   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "    📈 Total Issues  : %s\n"                   "$total_all"
    printf "    🚫 Blocking      : %s  (Medium + High)\n"  "$total_blocking"
    echo ""

    if [ "$total_blocking" -gt 0 ]; then
      echo "   ❌ MEDIUM/HIGH severity issues found — will block deployment"
      echo "   🔍 Blocking Issues:"
      set +e
      jq -r '.alerts[]? | select(.risk=="High" or .risk=="Medium") | "      • [\(.risk)] \(.name)"' \
        "$json_report" 2>/dev/null
      set -e
      has_critical=true
    else
      echo "   ✅ $svc passed security scan"
    fi

    # Webhook notification
    if [ -n "$WEBHOOK_URL_HOST" ]; then
      set +e
      curl -s -X POST "$WEBHOOK_URL_HOST/webhook/zap-qr-generator" \
        -F "json_data=@$json_report"     \
        -F "html_report=@$html_report"   \
        -F "branch=$BRANCH"              \
        -F "service=$svc"                \
        -F "project=$PROJECT_NAME"       \
        -F "timestamp=$BACKUP_TIMESTAMP" \
        -F "high=$high"                  \
        -F "medium=$medium"              \
        -F "low=$low"                    \
        -F "informational=$info"         \
        -F "total=$total_all"            \
        -m "$ZAP_WEBHOOK_TIMEOUT" > /dev/null 2>&1
      set -e
    fi
  done

  if [ "$has_critical" = true ]; then
    echo ""
    echo "❌ Security issues (Medium or above) found — Deployment failed → Rollback triggered"
    exit 1
  fi

  echo ""
  echo "✅ All ZAP scans passed"
}

###############################################################################
#                        SONARQUBE CODE QUALITY SCAN                          #
###############################################################################

run_sonar_scan() {
  echo ""
  echo "🔍 SonarQube Analysis"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [ -z "$HOST_SONAR_SCANER_URL" ] || [ -z "$SONAR_TOKEN_API_QR" ] || [ -z "$SONAR_PROJECT_KEY_API_QR" ]; then
    echo "⚠️  SonarQube config incomplete — skipping"
    return 0
  fi

  echo "▶ Checking SonarQube at $HOST_SONAR_SCANER_URL..."
  local sonar_status
  set +e
  sonar_status=$(curl -s -o /dev/null -w "%{http_code}" -m 10 \
    "$HOST_SONAR_SCANER_URL/api/system/status")
  set -e

  if [ "$sonar_status" != "200" ]; then
    echo "⚠️  SonarQube not accessible (HTTP $sonar_status) — skipping"
    return 0
  fi

  echo "✓ SonarQube server is accessible"
  cd "$DEPLOY_DIR"

  local sonar_cmd=""
  if [ -f "sonar" ]; then
    sonar_cmd="python3 sonar"
  elif command -v sonar-scanner >/dev/null 2>&1; then
    sonar_cmd="sonar-scanner"
  else
    echo "⚠️  sonar-scanner not found — skipping"
    return 0
  fi

  echo "▶ Running SonarQube analysis ($sonar_cmd)..."
  local sonar_exit
  set +e
  $sonar_cmd \
    -Dsonar.host.url="$HOST_SONAR_SCANER_URL" \
    -Dsonar.token="$SONAR_TOKEN_API_QR" \
    -Dsonar.projectKey="$SONAR_PROJECT_KEY_API_QR" \
    -Dsonar.projectName="$PROJECT_NAME" \
    -Dsonar.projectVersion="$BRANCH" \
    -Dsonar.sources=. \
    -Dsonar.exclusions="**/node_modules/**,**/venv/**,**/__pycache__/**,**/tests/**" \
    > /dev/null 2>&1
  sonar_exit=$?
  set -e

  if [ $sonar_exit -eq 0 ]; then
    echo "✅ SonarQube analysis completed"
  else
    echo "⚠️  SonarQube analysis failed (exit code $sonar_exit) — non-critical, continuing"
  fi
}

###############################################################################
#                              MAIN EXECUTION                                 #
###############################################################################

main() {
  load_env_vars
  create_backup

  build

  if [ -d "$DEPLOY_DIR/tests" ]; then
    run_automated_tests
  else
    echo "⚠️  Tests directory not found — skipping automated tests"
  fi

  deploy

  run_zap_scan
  run_sonar_scan

  # Clear trap — deployment succeeded, no rollback needed
  trap - ERR EXIT

  echo ""
  echo "✅ Deployment Completed Successfully"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Branch    : $BRANCH"
  echo "Deploy Dir: $DEPLOY_DIR"
  echo "Timestamp : $BACKUP_TIMESTAMP"
  echo "Backup    : $BACKUP_DIR"
  echo ""
}

main