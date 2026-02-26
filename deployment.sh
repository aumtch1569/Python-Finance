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
# สร้าง Version จากวันที่และเวลา (เช่น 1.0.2602261115)
VERSION="1.0.$(date +%y%m%d%H%M)" 

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Deploying $PROJECT_NAME (Version: $VERSION)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

###############################################################################
#                          BUILD EXE (DOCKER COPY METHOD)                     #
###############################################################################

build_exe() {
  echo "🔨 Building Windows EXE using Docker (cdrx)..."
  cd "$DEPLOY_DIR"

  # 1. สร้าง Container แบบ Detached (รันค้างไว้)
  # ใช้ cdrx/pyinstaller-windows เพราะมั่นใจว่ามีภาพนี้ในระบบ
  local container_id=$(docker run -d -it cdrx/pyinstaller-windows bash)

  echo "▶ Copying files to container..."
  # 2. Copy ไฟล์จาก Root ไปที่ /src ใน Container
  docker cp . "${container_id}:/src"

  echo "▶ Starting PyInstaller process..."
  # 3. สั่งรันคำสั่งข้างใน (ลบเวอร์ชันใน requirements เพื่อลดปัญหา Python 3.7)
  docker exec -t "${container_id}" bash -c "
    cd /src && \
    python -m pip install --upgrade pip && \
    if [ -f requirements.txt ]; then 
      sed -i 's/==.*//' requirements.txt && \
      pip install -r requirements.txt; 
    fi && \
    pyinstaller --onefile --windowed main.py
  "

  # 4. Copy ไฟล์ที่ได้กลับออกมา
  mkdir -p dist
  docker cp "${container_id}:/src/dist/main.exe" ./dist/main.exe

  # 5. ลบคอนเทนเนอร์ทิ้งเพื่อคืนพื้นที่
  docker rm -f "${container_id}"

  if [ ! -f "dist/main.exe" ]; then
    echo "❌ Build failed: dist/main.exe not found"
    exit 1
  fi
  echo "  ✓ Build completed: dist/main.exe"
}

###############################################################################
#                          STORE TO MINIO (FOR CLIENTS)                       #
###############################################################################

upload_to_minio() {
  echo "📦 Checking MinIO Client (mc)..."

  # 1. ตรวจสอบและติดตั้ง mc
  if ! command -v mc &> /dev/null; then
    echo "⚠️  mc not found. Starting automatic installation..."
    mkdir -p "$HOME/bin"
    curl -s https://dl.min.io/client/mc/release/linux-amd64/mc -o "$HOME/bin/mc"
    chmod +x "$HOME/bin/mc"
    export PATH="$PATH:$HOME/bin"
    echo "  ✓ mc installed successfully at $HOME/bin/mc"
  else
    echo "  ✓ mc is already installed."
  fi

  # 2. ตั้งค่าการเชื่อมต่อ (Auto-Alias)
  # ใช้ IP และค่า Default (minioadmin) ตามที่คุณระบุว่าไม่ได้ตั้งรหัสไว้
  local MINIO_URL="http://10.1.194.51:9000"
  local ACCESS_KEY="${MINIO_ACCESS_KEY:-minioadmin}"
  local SECRET_KEY="${MINIO_SECRET_KEY:-minioadmin}"

  echo "▶ Connecting to MinIO at $MINIO_URL..."
  # บังคับตั้งค่า Alias ใหม่เพื่อให้มั่นใจว่าข้อมูลอัปเดต
  mc alias set "$MINIO_ALIAS" "$MINIO_URL" "$ACCESS_KEY" "$SECRET_KEY" > /dev/null

  # 3. เช็คไฟล์ .exe ก่อนอัปโหลด
  if [ ! -f "dist/main.exe" ]; then
    echo "❌ Error: dist/main.exe not found. Build might have failed."
    exit 1
  fi
  
  echo "▶ Uploading TAX app version $VERSION..."
  # ส่งไฟล์ .exe ขึ้น MinIO
  mc cp dist/main.exe "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/$VERSION/tax_app.exe"
  
  echo "▶ Updating latest.json metadata..."
  # สร้างไฟล์ metadata เพื่อให้เครื่องลูกเช็คเวอร์ชัน
  echo "{\"version\": \"$VERSION\", \"url\": \"/$BUCKET_NAME/$PROJECT_NAME/$VERSION/tax_app.exe\"}" > latest.json
  mc cp latest.json "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/latest.json"

  echo "▶ Setting Public Policy for Client Access..."
  # ตั้งค่า Public เพื่อให้เครื่องลูกดาวน์โหลดได้โดยตรง
  mc anonymous set public "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME"

  echo "  ✓ Upload completed successfully!"
}

###############################################################################
#                               MAIN EXECUTION                                #
###############################################################################

main() {
  build_exe
  upload_to_minio

  echo ""
  echo "✅ Deployment Process Finished!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Latest Version: $VERSION"
  echo ""
}

main