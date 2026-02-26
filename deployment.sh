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
  echo "📦 Uploading Artifacts to MinIO..."

  # ตรวจสอบว่ามีคำสั่ง mc หรือไม่
  if ! command -v mc &> /dev/null; then
    echo "⚠️  mc command not found, skipping upload."
    return
  fi
  
  # 1. อัปโหลดไฟล์ EXE แยกโฟลเดอร์ตามเวอร์ชัน
  mc cp dist/main.exe "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/$VERSION/tax_app.exe"
  
  # 2. อัปโหลด Metadata (latest.json) เพื่อให้เครื่องลูกเช็คเพื่อ Automation Update
  echo "{\"version\": \"$VERSION\", \"url\": \"/$BUCKET_NAME/$PROJECT_NAME/$VERSION/tax_app.exe\"}" > latest.json
  mc cp latest.json "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/latest.json"

  # 3. ตั้งสิทธิ์ Public เพื่อให้เครื่องลูกโหลดได้สะดวก
  mc anonymous set public "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME"

  echo "  ✓ Uploaded to MinIO successfully"
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