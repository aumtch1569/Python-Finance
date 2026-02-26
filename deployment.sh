#!/bin/bash
set -euo pipefail

# ══════════════════════════════════════════════
#  CONFIG
# ══════════════════════════════════════════════
readonly PROJECT_NAME="TAX"
readonly DEPLOY_DIR="${WORKSPACE:-$(pwd)}"
readonly DIST_DIR="dist_final"

readonly MINIO_HOST="10.1.194.51"
readonly MINIO_PORT="9000"
readonly MINIO_USER="minioadmin"
readonly MINIO_PASS="minioadmin"
readonly MINIO_CONTAINER="minio_artifacts"
readonly BUCKET_NAME="deployments"

readonly BUILD_IMAGE="cdrx/pyinstaller-windows"
readonly PACKAGE_NAME="app_package.tar.gz"

# ══════════════════════════════════════════════
#  VERSION
# ══════════════════════════════════════════════
GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
TIMESTAMP=$(date +%Y%m%d-%H%M)
readonly VERSION="${GIT_TAG}-${TIMESTAMP}"

readonly UPLOAD_PATH="${BUCKET_NAME}/${PROJECT_NAME}/${VERSION}/${PACKAGE_NAME}"
readonly LATEST_PATH="${BUCKET_NAME}/${PROJECT_NAME}/latest.json"
readonly PUBLIC_URL="http://${MINIO_HOST}:${MINIO_PORT}/${UPLOAD_PATH}"

# ══════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════
log()     { echo "  $*"; }
section() { echo; echo "━━━  $*  ━━━"; }
success() { echo "  ✅ $*"; }
error()   { echo "  ❌ $*" >&2; exit 1; }

# ══════════════════════════════════════════════
#  BUILD
# ══════════════════════════════════════════════
build_and_package() {
  section "BUILD — Windows Application"
  cd "$DEPLOY_DIR"

  local container_id
  container_id=$(docker run -d -it "$BUILD_IMAGE" bash)
  log "Container: $container_id"

  # ทำความสะอาด container เมื่อ script จบหรือ error
  trap "docker rm -f '$container_id' &>/dev/null || true" EXIT

  docker cp . "${container_id}:/src"

  docker exec -t "$container_id" bash -c "
    set -euo pipefail
    cd /src

    # ติดตั้ง tar หากไม่มี
    command -v tar &>/dev/null || (apt-get update -qq && apt-get install -y -qq tar)

    # Upgrade pip และติดตั้ง dependencies
    python -m pip install --upgrade pip --quiet
    [ -f requirements.txt ] && pip install -r requirements.txt --quiet

    # หา path ของ customtkinter
    CTK_PATH=\$(python -c 'import customtkinter, os; print(os.path.dirname(customtkinter.__file__))' | tr -d '\r\n')

    # Build ด้วย PyInstaller
    pyinstaller --onedir --windowed --name main \
      --add-data \"\${CTK_PATH}:customtkinter\" \
      --add-data '.:'  \
      main.py

    # ตรวจสอบผลลัพธ์
    [ -d dist/main ] || { echo 'Build failed: dist/main not found'; exit 1; }

    # Package เฉพาะ build output
    tar -czf /src/${PACKAGE_NAME} -C dist/main .
  "

  mkdir -p "$DIST_DIR"
  docker cp "${container_id}:/src/${PACKAGE_NAME}" "${DIST_DIR}/${PACKAGE_NAME}"

  success "Build complete → ${DIST_DIR}/${PACKAGE_NAME}"
}

# ══════════════════════════════════════════════
#  UPLOAD
# ══════════════════════════════════════════════
generate_latest_json() {
  cat > latest.json <<EOF
{
  "version":  "$VERSION",
  "url":      "$PUBLIC_URL",
  "filename": "$PACKAGE_NAME"
}
EOF
}

upload_to_minio() {
  section "UPLOAD — MinIO @ ${MINIO_HOST}:${MINIO_PORT}"

  generate_latest_json

  # ส่งไฟล์เข้า container
  docker cp "${DIST_DIR}/${PACKAGE_NAME}" "${MINIO_CONTAINER}:/tmp/${PACKAGE_NAME}"
  docker cp latest.json                   "${MINIO_CONTAINER}:/tmp/latest.json"

  docker exec -t "$MINIO_CONTAINER" bash -c "
    set -euo pipefail

    mc alias set local http://localhost:9000 ${MINIO_USER} ${MINIO_PASS} --quiet

    # สร้าง bucket และเปิด public download ทั้ง bucket
    mc mb --ignore-existing local/${BUCKET_NAME}
    mc anonymous set download local/${BUCKET_NAME}

    # Upload
    mc cp /tmp/${PACKAGE_NAME} local/${UPLOAD_PATH}
    mc cp /tmp/latest.json     local/${LATEST_PATH}

    # ล้างไฟล์ชั่วคราว
    rm -f /tmp/${PACKAGE_NAME} /tmp/latest.json
  "

  success "Upload complete"
  log "🔗 Download URL : $PUBLIC_URL"
  log "📋 latest.json  : http://${MINIO_HOST}:${MINIO_PORT}/${LATEST_PATH}"
}

# ══════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════
main() {
  echo
  echo "╔══════════════════════════════════════════╗"
  echo "║   🚀  $PROJECT_NAME  Deploy Pipeline"
  echo "║   📌  Version : $VERSION"
  echo "╚══════════════════════════════════════════╝"

  build_and_package
  upload_to_minio

  echo
  echo "╔══════════════════════════════════════════╗"
  echo "║   ✅  Deploy สำเร็จ!"
  echo "║   🔗  $PUBLIC_URL"
  echo "╚══════════════════════════════════════════╝"
  echo
}

main