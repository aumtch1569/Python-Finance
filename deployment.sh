#!/bin/bash
set -e

###############################################################################
#             UNIVERSAL PYTHON DEPLOYMENT (BUILD-TO-ZIP)                      #
###############################################################################

### CONFIG ###
PROJECT_NAME="TAX"
DEPLOY_DIR="${WORKSPACE:-$(pwd)}"
MINIO_ALIAS="myminio"      
BUCKET_NAME="deployments"   

# 1. จัดการ Version (Git Tag + Timestamp)
GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
TIMESTAMP=$(date +%Y%m%d-%H%M)
VERSION="${GIT_TAG}-${TIMESTAMP}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Deploying $PROJECT_NAME"
echo "📌 Version        : $VERSION"
echo "📌 Workspace      : $DEPLOY_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

###############################################################################
#                          BUILD PROCESS (AUTO-COLLECT)                       #
###############################################################################

build_exe() {
  echo "🔨 Building Windows Application Structure..."
  cd "$DEPLOY_DIR"

  # สร้าง Container สำหรับ Build Windows
  local container_id=$(docker run -d -it cdrx/pyinstaller-windows bash)

  echo "▶ Copying source code to container..."
  docker cp . "${container_id}:/src"

  echo "▶ Running Environment Setup & Build..."
  docker exec -t "${container_id}" bash -c "
    cd /src && \
    
    # 🔍 เช็คและติดตั้ง zip เฉพาะเมื่อจำเป็น
    if ! command -v zip &> /dev/null; then
        echo '📦 Installing zip...' && \
        apt-get update && apt-get install -y zip;
    fi && \
    
    python -m pip install --upgrade pip && \
    if [ -f requirements.txt ]; then 
        sed -i 's/==.*//' requirements.txt && \
        pip install -r requirements.txt; 
    fi && \
    
    # 🔍 ดึง Path และล้าง Newline ให้สะอาด
    CTK_PATH=\$(python -c 'import customtkinter; import os; print(os.path.dirname(customtkinter.__file__))' 2>/dev/null | tr -d '\r\n') && \
    
    echo \"Debug: CTK_PATH is [\$CTK_PATH]\" && \
    
    # Build แบบ --onedir
    if [ -n \"\$CTK_PATH\" ]; then
        pyinstaller --onedir --windowed --add-data \"\$CTK_PATH;customtkinter\" --add-data '.;.' main.py
    else
        pyinstaller --onedir --windowed --add-data '.;.' main.py
    fi && \
    
    # บีบอัดไฟล์ทั้งหมดในโฟลเดอร์ผลลัพธ์ (กวาดทุกอย่างใน dist/main)
    if [ -d \"dist/main\" ]; then
        cd dist/main && zip -r ../../app_package.zip *
    else
        echo '❌ Error: Build directory not found!' && exit 1
    fi
  "

  # ดึงไฟล์ Zip กลับมาที่ Jenkins
  mkdir -p dist_final
  docker cp "${container_id}:/src/app_package.zip" ./dist_final/app_package.zip

  # ลบคอนเทนเนอร์
  docker rm -f "${container_id}"

  if [ ! -f "dist_final/app_package.zip" ]; then
    echo "❌ Error: Zip package not found!"
    exit 1
  fi
  echo "  ✓ Build & Zip completed successfully"
}

###############################################################################
#                          STORE TO MINIO                                     #
###############################################################################

upload_to_minio() {
  echo "📦 Checking MinIO Client (mc)..."

  if ! command -v mc &> /dev/null; then
    mkdir -p "$HOME/bin"
    curl -L https://dl.min.io/client/mc/release/linux-amd64/mc -o "$HOME/bin/mc"
    chmod +x "$HOME/bin/mc"
    export PATH="$PATH:$HOME/bin"
  fi

  local MINIO_URL="http://10.1.194.51:9000"
  local ACCESS_KEY="${MINIO_ACCESS_KEY:-minioadmin}"
  local SECRET_KEY="${MINIO_SECRET_KEY:-minioadmin}"

  echo "▶ Connecting to MinIO..."
  mc alias set "$MINIO_ALIAS" "$MINIO_URL" "$ACCESS_KEY" "$SECRET_KEY"

  echo "▶ Uploading Package: $VERSION"
  mc cp dist_final/app_package.zip "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/$VERSION/app_package.zip"
  
  echo "▶ Updating latest.json..."
  cat <<EOF > latest.json
{
  "version": "$VERSION",
  "tag": "$GIT_TAG",
  "timestamp": "$TIMESTAMP",
  "url": "/$BUCKET_NAME/$PROJECT_NAME/$VERSION/app_package.zip",
  "filename": "app_package.zip"
}
EOF

  mc cp latest.json "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/latest.json"
  mc anonymous set public "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME"

  echo "  ✓ Deployment completed!"
}

main() {
  build_exe
  upload_to_minio
}

main