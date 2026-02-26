#!/bin/bash
set -e

###############################################################################
#             UNIVERSAL PYTHON DEPLOYMENT (FULL PROJECT TAR)                  #
###############################################################################

### CONFIG ###
PROJECT_NAME="TAX"
DEPLOY_DIR="${WORKSPACE:-$(pwd)}"
MINIO_ALIAS="myminio"      
BUCKET_NAME="deployments"   

# 1. จัดการ Version
GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
TIMESTAMP=$(date +%Y%m%d-%H%M)
VERSION="${GIT_TAG}-${TIMESTAMP}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Deploying $PROJECT_NAME (Full Project Tar)"
echo "📌 Version        : $VERSION"
echo "📌 Workspace      : $DEPLOY_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

###############################################################################
#                          BUILD & PACKAGE PROCESS                            #
###############################################################################

build_and_package() {
  echo "🔨 Building Windows Executable and Packaging Project..."
  cd "$DEPLOY_DIR"

  # สร้าง Container สำหรับ Build Windows
  local container_id=$(docker run -d -it cdrx/pyinstaller-windows bash)

  echo "▶ Copying source code to container..."
  docker cp . "${container_id}:/src"

  echo "▶ Running Environment Setup & Build..."
  docker exec -t "${container_id}" bash -c "
    cd /src && \
    python -m pip install --upgrade pip && \
    if [ -f requirements.txt ]; then 
        sed -i 's/==.*//' requirements.txt && \
        pip install -r requirements.txt; 
    fi && \
    
    # 🔍 ดึง Path ของ customtkinter เพื่อรวม assets
    CTK_PATH=\$(python -c 'import customtkinter; import os; print(os.path.dirname(customtkinter.__file__))' 2>/dev/null | tr -d '\r\n') && \
    
    # สั่ง Build .exe เข้าไปไว้ในตัวโปรเจกต์เลย
    pyinstaller --onedir --windowed --add-data \"\$CTK_PATH;customtkinter\" --add-data '.;.' main.py && \
    
    # ย้ายไฟล์จาก dist/main มาไว้ที่ root ของ project เพื่อความง่ายในการรัน
    cp -r dist/main/* . && \
    
    # 📦 บีบอัดทุกอย่าง ยกเว้นโฟลเดอร์ที่ไม่จำเป็น
    echo '📦 Creating Tar Archive (Excluding Junk)...' && \
    tar -czf app_package.tar.gz \
        --exclude='venv' \
        --exclude='.git' \
        --exclude='__pycache__' \
        --exclude='build' \
        --exclude='dist' \
        --exclude='*.pyc' \
        --exclude='.pytest_cache' \
        .
  "

  # ดึงไฟล์ Tar กลับมาที่ Jenkins
  mkdir -p dist_final
  docker cp "${container_id}:/src/app_package.tar.gz" ./dist_final/app_package.tar.gz

  # ลบคอนเทนเนอร์
  docker rm -f "${container_id}"

  if [ ! -f "dist_final/app_package.tar.gz" ]; then
    echo "❌ Error: Tar package not found!"
    exit 1
  fi
  echo "  ✓ Project Packaged successfully"
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
  mc cp dist_final/app_package.tar.gz "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/$VERSION/app_package.tar.gz"
  
  echo "▶ Updating latest.json..."
  cat <<EOF > latest.json
{
  "version": "$VERSION",
  "tag": "$GIT_TAG",
  "timestamp": "$TIMESTAMP",
  "url": "/$BUCKET_NAME/$PROJECT_NAME/$VERSION/app_package.tar.gz",
  "filename": "app_package.tar.gz"
}
EOF

  mc cp latest.json "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/latest.json"
  mc anonymous set public "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME"

  echo "  ✓ Deployment completed!"
}

main() {
  build_and_package
  upload_to_minio
}

main