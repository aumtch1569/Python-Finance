#!/bin/bash
set -e

### CONFIG ###
PROJECT_NAME="TAX"
DEPLOY_DIR="${WORKSPACE:-$(pwd)}"
MINIO_ALIAS="myminio"
BUCKET_NAME="deployments"
VERSION="1.0.$(date +%y%m%d%H%M)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Deploying $PROJECT_NAME via Docker Builder"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. ข้ามการสร้าง venv ในเครื่อง Jenkins และใช้ Docker Build แทน
build_exe() {
  echo "🔨 Building Windows EXE using Docker (cdrx)..."
  cd "$DEPLOY_DIR"
  
  # เพิ่ม "cd /src" เข้าไปในคำสั่ง Docker
  docker run --rm -v "$(pwd):/src" cdrx/pyinstaller-windows \
    "cd /src && \
     python -m pip install --upgrade pip && \
     if [ -f requirements.txt ]; then sed -i 's/==.*//' requirements.txt && pip install -r requirements.txt; fi && \
     pyinstaller --onefile --windowed main.py"

  # เช็คไฟล์หลัง build เสร็จ
  if [ ! -f "dist/main.exe" ]; then
    echo "❌ Build failed: dist/main.exe not found"
    # ลองลิสต์ไฟล์ดูว่ามันไปงอกที่ไหน
    ls -R dist/ || echo "No dist folder found"
    exit 1
  fi
  echo "  ✓ Build completed successfully"
}

# 2. การ Upload ขึ้น MinIO (ใช้เครื่อง Jenkins สั่ง)
upload_to_minio() {
  echo "📦 Uploading to MinIO..."
  
  # อัปโหลดไฟล์ EXE
  mc cp dist/main.exe "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/$VERSION/tax_app.exe"
  
  # สร้างและอัปโหลด metadata เพื่อให้เครื่องลูกเช็คเวอร์ชัน
  echo "{\"version\": \"$VERSION\", \"url\": \"/$BUCKET_NAME/$PROJECT_NAME/$VERSION/tax_app.exe\"}" > latest.json
  mc cp latest.json "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/latest.json"
  
  # เปิด public เผื่อไว้
  mc anonymous set public "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME"
  
  echo "  ✓ Version $VERSION is now live on MinIO"
}

main() {
  build_exe
  upload_to_minio
  echo "✅ Done!"
}

main