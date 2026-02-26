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

# เขียน build script แยกเป็นไฟล์ → copy เข้า container
# แก้ปัญหา: docker exec bash -c "multiline" parse if/fi ไม่ครบ → syntax error
write_build_script() {
  cat > /tmp/_build_inside.sh << 'BUILD_SCRIPT'
#!/bin/bash
set -euo pipefail
cd /src

echo "▶ Installing system tools..."
command -v tar &>/dev/null || (apt-get update -qq && apt-get install -y -qq tar)

echo "▶ Upgrading pip..."
python -m pip install --upgrade pip --quiet

if [ -f requirements.txt ]; then
  echo "▶ Installing dependencies (pinned)..."
  if ! pip install -r requirements.txt --quiet 2>/dev/null; then
    echo "⚠ Pinned install failed — retrying without version pins..."
    sed 's/[>=<!][^ ]*//' requirements.txt \
      | grep -v '^\s*$' \
      > /tmp/requirements_unpinned.txt
    pip install -r /tmp/requirements_unpinned.txt --quiet
  fi
fi

echo "▶ Locating customtkinter..."
CTK_PATH=$(python -c 'import customtkinter, os; print(os.path.dirname(customtkinter.__file__))' | tr -d '\r\n')
echo "  Path: $CTK_PATH"

echo "▶ Running PyInstaller..."
# cdrx/pyinstaller-windows ใช้ Wine + Windows Python
# → --add-data ต้องใช้ ; (Windows style) ไม่ใช่ : (Linux style)
pyinstaller --onedir --windowed --name main \
  --add-data "${CTK_PATH};customtkinter" \
  --add-data ".;." \
  main.py

[ -d dist/main ] || { echo "❌ Build failed: dist/main not found"; exit 1; }

echo "▶ Packaging..."
tar -czf /src/app_package.tar.gz -C dist/main .
echo "✅ Package ready"
BUILD_SCRIPT
}

build_and_package() {
  section "BUILD — Windows Application"
  cd "$DEPLOY_DIR"

  local container_id
  container_id=$(docker run -d -it "$BUILD_IMAGE" bash)
  log "Container: $container_id"

  trap "docker rm -f '$container_id' &>/dev/null || true" EXIT

  # copy source + build script เข้า container
  write_build_script
  docker cp . "${container_id}:/src"
  docker cp /tmp/_build_inside.sh "${container_id}:/src/_build_inside.sh"

  # รัน script ไฟล์ตรงๆ — ไม่ใช้ bash -c multiline
  docker exec -t "$container_id" bash /src/_build_inside.sh

  mkdir -p "$DIST_DIR"
  docker cp "${container_id}:/src/${PACKAGE_NAME}" "${DIST_DIR}/${PACKAGE_NAME}"
  success "Build complete → ${DIST_DIR}/${PACKAGE_NAME}"
}

# ══════════════════════════════════════════════
#  UPLOAD
# ══════════════════════════════════════════════
generate_latest_json() {
  cat > latest.json << JSONEOF
{
  "version":  "$VERSION",
  "url":      "$PUBLIC_URL",
  "filename": "$PACKAGE_NAME"
}
JSONEOF
}

upload_to_minio() {
  section "UPLOAD — MinIO @ ${MINIO_HOST}:${MINIO_PORT}"

  generate_latest_json
  docker cp "${DIST_DIR}/${PACKAGE_NAME}" "${MINIO_CONTAINER}:/tmp/${PACKAGE_NAME}"
  docker cp latest.json                   "${MINIO_CONTAINER}:/tmp/latest.json"

  # แยก exec ทีละ command — หลีกเลี่ยง multiline ใน mc container ด้วย
  docker exec -t "$MINIO_CONTAINER" mc alias set local "http://localhost:9000" "$MINIO_USER" "$MINIO_PASS" --quiet
  docker exec -t "$MINIO_CONTAINER" mc mb --ignore-existing "local/${BUCKET_NAME}"
  docker exec -t "$MINIO_CONTAINER" mc anonymous set download "local/${BUCKET_NAME}"
  docker exec -t "$MINIO_CONTAINER" mc cp "/tmp/${PACKAGE_NAME}" "local/${UPLOAD_PATH}"
  docker exec -t "$MINIO_CONTAINER" mc cp "/tmp/latest.json"     "local/${LATEST_PATH}"
  docker exec -t "$MINIO_CONTAINER" sh -c "rm -f /tmp/${PACKAGE_NAME} /tmp/latest.json"

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