#!/bin/bash
set -e

### CONFIG ###
PROJECT_NAME="TAX"
DEPLOY_DIR="${WORKSPACE:-$(pwd)}"
MINIO_ALIAS="myminio"      
BUCKET_NAME="deployments"   

GIT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
TIMESTAMP=$(date +%Y%m%d-%H%M)
VERSION="${GIT_TAG}-${TIMESTAMP}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Deploying $PROJECT_NAME"
echo "📌 Version        : $VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

build_and_package() {
  echo "🔨 Building Windows Application..."
  cd "$DEPLOY_DIR"

  local container_id=$(docker run -d -it cdrx/pyinstaller-windows bash)

  echo "▶ Copying source code to container..."
  docker cp . "${container_id}:/src"

  echo "▶ Running Environment Setup & Build..."
  docker exec -t "${container_id}" bash -c "
    cd /src && \
    
    # 🔍 เช็คและติดตั้งเครื่องมือที่จำเป็น (ถ้าไม่มี)
    if ! command -v tar &> /dev/null; then
        apt-get update && apt-get install -y tar;
    fi && \
    
    python -m pip install --upgrade pip && \
    if [ -f requirements.txt ]; then 
        sed -i 's/==.*//' requirements.txt && \
        pip install -r requirements.txt; 
    fi && \
    
    # ดึง Path customtkinter เพื่อจัดการ Assets
    CTK_PATH=\$(python -c 'import customtkinter; import os; print(os.path.dirname(customtkinter.__file__))' 2>/dev/null | tr -d '\r\n') && \
    
    pyinstaller --onedir --windowed --add-data \"\$CTK_PATH;customtkinter\" --add-data '.;.' main.py && \
    
    # 📦 วิธีแก้ Tar Error: สร้างโฟลเดอร์แยกสำหรับเตรียมไฟล์บีบอัด
    echo '📦 Preparing package folder...' && \
    mkdir -p /tmp/package_root && \
    
    # ก๊อปปี้ทุกอย่างยกเว้นสิ่งที่ไม้ต้องการไปที่โฟลเดอร์ชั่วคราว
    cp -r . /tmp/package_root/ && \
    cd /tmp/package_root && \
    
    # ย้ายไฟล์จาก dist/main มาไว้ที่ root เพื่อให้รันง่าย
    if [ -d \"dist/main\" ]; then
        cp -r dist/main/* .
    fi && \
    
    # ลบโฟลเดอร์ที่ไม่จำเป็นทิ้งก่อนบีบอัด
    rm -rf venv .git __pycache__ build dist *.spec && \
    
    echo '📦 Creating Tar Archive...' && \
    tar -czf /src/app_package.tar.gz . 
  "

  # ดึงไฟล์ Tar กลับมาที่ Jenkins
  mkdir -p dist_final
  docker cp "${container_id}:/src/app_package.tar.gz" ./dist_final/app_package.tar.gz

  docker rm -f "${container_id}"

  if [ ! -f "dist_final/app_package.tar.gz" ]; then
    echo "❌ Error: Tar package not found!"
    exit 1
  fi
  echo "  ✓ Project Packaged successfully"
}

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
  "url": "/$BUCKET_NAME/$PROJECT_NAME/$VERSION/app_package.tar.gz",
  "filename": "app_package.tar.gz"
}
EOF
  mc cp latest.json "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/latest.json"
  mc anonymous set public "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME"
}

main() {
  build_and_package
  upload_to_minio
}

main