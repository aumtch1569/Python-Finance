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
  echo "🔨 Building Windows EXE using Docker (tobix)..."
  cd "$DEPLOY_DIR"
  
  # ใช้ Docker ตัวเดียวจบ: ลง lib, เทส และ build
  docker run --rm -v "$(pwd):/src" tobix/pyinstaller-windows \
    "pip install --upgrade pip && \
     pip install -r requirements.txt && \
     pyinstaller --onefile --windowed main.py"

  if [ ! -f "dist/main.exe" ]; then
    echo "❌ Build failed: dist/main.exe not found"
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