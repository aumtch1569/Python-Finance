#!/bin/bash
set -e

###############################################################################
#                         PYTHON EXE & MINIO DEPLOYMENT                       #
###############################################################################

### CONFIG ###
PROJECT_NAME="TAX"
DEPLOY_DIR="${WORKSPACE:-$(pwd)}"
MINIO_ALIAS="myminio"      
BUCKET_NAME="deployments"   

# 1. ดึง Version จาก Git Tag และเพิ่ม Timestamp
GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
TIMESTAMP=$(date +%Y%m%d-%H%M)
VERSION="${GIT_TAG}-${TIMESTAMP}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Deploying $PROJECT_NAME"
echo "📌 Version (Tag-Time) : $VERSION"
echo "📌 Workspace          : $DEPLOY_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

###############################################################################
#                          BUILD EXE (DOCKER COPY METHOD)                     #
###############################################################################

build_exe() {
  echo "🔨 Building Windows EXE using Docker (cdrx)..."
  cd "$DEPLOY_DIR"

  # สร้าง Container แบบ Detached
  local container_id=$(docker run -d -it cdrx/pyinstaller-windows bash)

  echo "▶ Copying source code to container..."
  docker cp . "${container_id}:/src"

  echo "▶ Running PyInstaller inside container..."
  # เพิ่ม --add-data ".:." เพื่อนำไฟล์และโฟลเดอร์ทั้งหมดใน root เข้าไปใน exe
  # แก้ไขในส่วน docker exec ของฟังก์ชัน build_exe
  docker exec -t "${container_id}" bash -c "
    cd /src && \
    python -m pip install --upgrade pip && \
    if [ -f requirements.txt ]; then 
      sed -i 's/==.*//' requirements.txt && \
      pip install -r requirements.txt; 
    fi && \
    pyinstaller --onefile --add-data '.;.' main.py
  "

  # ดึงไฟล์ .exe กลับมาที่เครื่อง Jenkins
  mkdir -p dist
  docker cp "${container_id}:/src/dist/main.exe" ./dist/main.exe

  # ลบคอนเทนเนอร์
  docker rm -f "${container_id}"

  if [ ! -f "dist/main.exe" ]; then
    echo "❌ Error: Build failed, dist/main.exe not found!"
    exit 1
  fi
  echo "  ✓ Build completed successfully"
}

###############################################################################
#                          STORE TO MINIO (WITH TIMESTAMP)                    #
###############################################################################

upload_to_minio() {
  echo "📦 Checking MinIO Client (mc)..."

  if ! command -v mc &> /dev/null; then
    echo "⚠️  mc not found. Starting installation..."
    mkdir -p "$HOME/bin"
    curl -L https://dl.min.io/client/mc/release/linux-amd64/mc -o "$HOME/bin/mc"
    chmod +x "$HOME/bin/mc"
    export PATH="$PATH:$HOME/bin"
    echo "  ✓ mc installed successfully at $(which mc)"
  fi

  local MINIO_URL="http://10.1.194.51:9000"
  local ACCESS_KEY="${MINIO_ACCESS_KEY:-minioadmin}"
  local SECRET_KEY="${MINIO_SECRET_KEY:-minioadmin}"

  echo "▶ Connecting to MinIO at $MINIO_URL..."
  mc alias set "$MINIO_ALIAS" "$MINIO_URL" "$ACCESS_KEY" "$SECRET_KEY"

  echo "▶ Uploading TAX app version: $VERSION"
  mc cp dist/main.exe "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/$VERSION/tax_app.exe"
  
  echo "▶ Updating latest.json metadata..."
  cat <<EOF > latest.json
{
  "version": "$VERSION",
  "tag": "$GIT_TAG",
  "timestamp": "$TIMESTAMP",
  "url": "/$BUCKET_NAME/$PROJECT_NAME/$VERSION/tax_app.exe"
}
EOF

  mc cp latest.json "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/latest.json"
  mc anonymous set public "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME"

  echo "  ✓ Upload completed: $VERSION"
}

main() {
  build_exe
  upload_to_minio

  echo ""
  echo "✅ Deployment Successful!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Release Name : $VERSION"
  echo "Check JSON   : http://10.1.194.51:9000/deployments/TAX/latest.json"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main