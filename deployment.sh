#!/bin/bash
set -e

###############################################################################
#                         PYTHON EXE & MINIO DEPLOYMENT                       #
###############################################################################

### PARAMS ###
BRANCH="${1:-main}"
REPO_URL="${2:-}"
BACKUP_TIMESTAMP="${3:-$(date +%Y%m%d_%H%M%S)}"
VERSION="1.0.$(date +%y%m%d%H%M)" # สร้างเลขเวอร์ชันจากวันที่

### CONFIG ###
PROJECT_NAME="TAX"
DEPLOY_DIR="${WORKSPACE:-$(pwd)}"
MINIO_ALIAS="myminio"      # ชื่อ alias ที่ตั้งไว้ใน mc
BUCKET_NAME="deployments"   # ชื่อ bucket ใน MinIO

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Deploying $PROJECT_NAME (Build & MinIO Store)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📌 Version    : $VERSION"
echo "📌 Deploy Dir : $DEPLOY_DIR"
echo "📌 Backup     : $BACKUP_TIMESTAMP"
echo ""

# โหลดตัวแปรจาก .env (ถ้ามี)
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
  echo "✓ Environment variables loaded"
fi

###############################################################################
#                              PREPARE & BUILD                                #
###############################################################################

prepare_env() {
  echo "▶ Preparing Virtual Environment..."
  cd "$DEPLOY_DIR"
  
  if [ ! -d "venv" ]; then
    python3 -m venv venv
  fi
  source venv/bin/activate
  
  pip install --upgrade pip
  pip install -r requirements.txt
  pip install pyinstaller
  echo "  ✓ Environment ready"
}

run_tests() {
  echo "🧪 Running Pytest..."
  source venv/bin/activate
  if [ -d "tests" ]; then
    pytest tests/ --doctest-modules --junitxml=test_reports/pytest_result.xml
    echo "  ✓ All tests passed"
  else
    echo "  ⚠️ No tests found, skipping..."
  fi
}

build_exe() {
  echo "🔨 Building Windows Executable (.exe)..."
  source venv/bin/activate

  # หมายเหตุ: หากรันบน Linux และต้องการ .exe สำหรับ Windows 
  # แนะนำให้ใช้คำสั่ง Docker เฉพาะบรรทัดนี้:
  docker run --rm -v "$(pwd):/src" tobix/pyinstaller-windows "pip install -r requirements.txt; pyinstaller --onefile --windowed main.py"
  
  # ตรวจสอบว่าไฟล์ถูกสร้างขึ้นจริง
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
  echo "📦 Uploading to MinIO..."
  
  # 1. อัปโหลดไฟล์ EXE หลักแยกตามเวอร์ชัน
  mc cp dist/main.exe "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/$VERSION/tax_app.exe"
  
  # 2. อัปโหลด config.json (ถ้ามี)
  if [ -f "config.json" ]; then
    mc cp config.json "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/$VERSION/config.json"
  fi

  # 3. อัปโหลด Metadata สำหรับเครื่องลูกมาเช็ค (latest.json)
  echo "{\"version\": \"$VERSION\", \"url\": \"/$BUCKET_NAME/$PROJECT_NAME/$VERSION/tax_app.exe\", \"timestamp\": \"$BACKUP_TIMESTAMP\"}" > latest.json
  mc cp latest.json "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/latest.json"

  # 4. ตั้งค่า Public เพื่อให้เครื่องลูกโหลดได้โดยไม่ต้องใช้ Key (ถ้าต้องการ)
  mc anonymous set public "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME"

  echo "  ✓ Artifacts stored and version updated to $VERSION"
}

###############################################################################
#                               MAIN EXECUTION                                #
###############################################################################

main() {
  prepare_env
  
  # ขั้นตอน Quality Gate
  run_tests
  
  # ขั้นตอน Build
  build_exe
  
  # ขั้นตอน Deploy (ส่งขึ้น MinIO)
  upload_to_minio

  echo ""
  echo "✅ Automation Process Completed!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Clients can now pull version: $VERSION"
  echo ""
}

main