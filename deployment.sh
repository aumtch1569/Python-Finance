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
  docker cp . "${container_id}:/src"

  docker exec -t "${container_id}" bash -c "
    cd /src && \
    if ! command -v tar &> /dev/null; then apt-get update && apt-get install -y tar; fi && \
    python -m pip install --upgrade pip && \
    if [ -f requirements.txt ]; then sed -i 's/==.*//' requirements.txt && pip install -r requirements.txt; fi && \
    
    CTK_PATH=\$(python -c 'import customtkinter; import os; print(os.path.dirname(customtkinter.__file__))' 2>/dev/null | tr -d '\r\n') && \
    
    pyinstaller --onedir --windowed --add-data \"\$CTK_PATH;customtkinter\" --add-data '.;.' main.py && \
    
    # 📦 จัดโครงสร้างให้ Flat เหมือนภาพ image_ccd479.png
    mkdir -p /tmp/package_root && \
    cp -r . /tmp/package_root/ && \
    cd /tmp/package_root && \
    if [ -d \"dist/main\" ]; then cp -r dist/main/* .; fi && \
    rm -rf venv .git __pycache__ build dist *.spec && \
    
    tar -czf /src/app_package.tar.gz . 
  "

  mkdir -p dist_final
  docker cp "${container_id}:/src/app_package.tar.gz" ./dist_final/app_package.tar.gz
  docker rm -f "${container_id}"
}

upload_to_minio() {
  echo "📦 Configuring MinIO Public Access..."
  if ! command -v mc &> /dev/null; then
    mkdir -p "$HOME/bin"
    curl -L https://dl.min.io/client/mc/release/linux-amd64/mc -o "$HOME/bin/mc"
    chmod +x "$HOME/bin/mc"
    export PATH="$PATH:$HOME/bin"
  fi

  local MINIO_URL="http://10.1.194.51:9000"
  mc alias set "$MINIO_ALIAS" "$MINIO_URL" "${MINIO_ACCESS_KEY:-minioadmin}" "${MINIO_SECRET_KEY:-minioadmin}"

  echo "▶ Uploading..."
  mc cp dist_final/app_package.tar.gz "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/$VERSION/app_package.tar.gz"
  
  # 🔓 ปรับ Access จาก CUSTOM เป็น DOWNLOAD (Public)
  echo "▶ Setting Policy to Public Download..."
  mc anonymous set download "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME"

  # สร้างลิงก์ที่พร้อมใช้สำหรับเครื่องอื่น
  local PUBLIC_URL="$MINIO_URL/$BUCKET_NAME/$PROJECT_NAME/$VERSION/app_package.tar.gz"
  
  cat <<EOF > latest.json
{
  "version": "$VERSION",
  "url": "$PUBLIC_URL",
  "filename": "app_package.tar.gz"
}
EOF
  mc cp latest.json "$MINIO_ALIAS/$BUCKET_NAME/$PROJECT_NAME/latest.json"
  echo "✅ Success! ลิงก์โหลด: $PUBLIC_URL"
}

main() {
  build_and_package
  upload_to_minio
}

main