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
# ดึง Tag ล่าสุด (ถ้าไม่มีใช้ v0.0.0)
GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
# สร้าง Timestamp (ปีเดือนวัน-ชั่วโมงนาที)
TIMESTAMP=$(date +%Y%m%d-%H%M)
# รวมร่างเป็น Version ใหม่
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
  docker exec -t "${container_id}" bash -c "
    cd /src && \
    python -m pip install --upgrade pip && \
    if [ -f requirements.txt ]; then 
      sed -i 's/==.*//' requirements.txt && \
      pip install -r requirements.txt; 
    fi && \
    pyinstaller --onefile --windowed main.py
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

  # ติดตั้ง mc อัตโนมัติถ้ายังไม่มี
  if ! command -v mc &> /dev/null; then
    echo "⚠️  mc not found. Installing..."
    mkdir -p "$HOME/bin"
    curl -s https://dl.min.io/client/mc/release/linux-amd64/mc -o "$HOME/bin/mc"
    chmod +x "$HOME/bin/mc"
    export PATH="$PATH:$HOME/bin"
  fi

  # ตั้งค่าการเชื่อมต่อ
  local MINIO_URL="http://10.1.194.51:9000"
  local ACCESS_KEY="${MINIO_ACCESS_KEY:-minioadmin}"
  local SECRET_KEY="${MINIO_SECRET_KEY:-minioadmin}"

  echo "▶ Connecting to MinIO at $MINIO_URL..."
  mc alias set "$MINIO_ALIAS" "$MINIO_URL" "$ACCESS_KEY" "$SECRET_KEY" > /dev/null

  echo "▶ Uploading to folder: $VERSION"
  # อัปโหลดไฟล์ EXE เข้าโฟลเดอร์ Tag-Timestamp
  mc cp dist/main.exe "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/$VERSION/tax_app.exe"
  
  echo "▶ Updating latest.json metadata..."
  # สร้างไฟล์ metadata เพื่อให้เครื่องลูกโหลดเวอร์ชันล่าสุดเสมอ
  # ใส่ข้อมูลเพิ่มใน JSON เพื่อให้ฝั่ง Client ตรวจสอบได้ง่าย
  cat <<EOF > latest.json
{
  "version": "$VERSION",
  "tag": "$GIT_TAG",
  "timestamp": "$TIMESTAMP",
  "url": "/$BUCKET_NAME/$PROJECT_NAME/$VERSION/tax_app.exe"
}
EOF

  mc cp latest.json "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/latest.json"

  echo "▶ Setting Public Policy..."
  mc anonymous set public "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME"

  echo "  ✓ Upload completed: $VERSION"
}

###############################################################################
#                               MAIN EXECUTION                                #
###############################################################################

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