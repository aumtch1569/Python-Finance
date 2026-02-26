#!/bin/bash
set -e

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
echo "🚀 Deploying $PROJECT_NAME to MinIO Docker"
echo "📌 Version        : $VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

build_and_package() {
  echo "🔨 Building Windows Application..."
  cd "$DEPLOY_DIR"

  local container_id=$(docker run -d -it cdrx/pyinstaller-windows bash)
  docker cp . "${container_id}:/src"

  docker exec -t "${container_id}" bash -c "
    cd /src && \
    # เช็คและติดตั้งเครื่องมือ
    if ! command -v tar &> /dev/null; then apt-get update && apt-get install -y tar; fi && \
    
    python -m pip install --upgrade pip && \
    if [ -f requirements.txt ]; then sed -i 's/==.*//' requirements.txt && pip install -r requirements.txt; fi && \
    
    # ดึง Path customtkinter
    CTK_PATH=\$(python -c 'import customtkinter; import os; print(os.path.dirname(customtkinter.__file__))' 2>/dev/null | tr -d '\r\n') && \
    
    pyinstaller --onedir --windowed --add-data \"\$CTK_PATH;customtkinter\" --add-data '.;.' main.py && \
    
    # 📦 จัดโครงสร้างให้ Flat ตามที่คุณต้องการ
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
  echo "📦 Uploading to MinIO via Docker on 10.1.194.51..."
  
  local MINIO_HOST="10.1.194.51"
  local CONTAINER_NAME="minio_artifacts" # ชื่อคอนเทนเนอร์ MinIO บนเครื่อง .51
  local BUCKET_PATH="$BUCKET_NAME/$PROJECT_NAME/$VERSION"

  # 1. ส่งไฟล์เข้าไปในเครื่อง .51 และโยนเข้า Docker Container
  # (ในกรณีนี้สมมติว่าคุณรันสคริปต์จากเครื่องที่มีสิทธิ์ SSH หรือ Docker Remote)
  # แต่ถ้า Jenkins รันบนเครื่อง .51 อยู่แล้ว จะง่ายมากครับ:
  
  echo "▶ Copying package to MinIO Container..."
  docker cp dist_final/app_package.tar.gz "${CONTAINER_NAME}:/tmp/app_package.tar.gz"

  echo "▶ Moving file to Bucket and setting Public Access..."
  docker exec -t "${CONTAINER_NAME}" bash -c "
    # ใช้ mc ที่มีอยู่แล้วในตัว Docker MinIO
    # ตั้งค่า alias ภายในตัวเอง (ชี้เข้าหาตัวเอง)
    mc alias set local http://localhost:9000 minioadmin minioadmin && \
    
    # ตรวจสอบและสร้าง Bucket
    mc mb local/$BUCKET_NAME --ignore-existing && \
    
    # ย้ายไฟล์จาก /tmp เข้าสู่ Bucket
    mc cp /tmp/app_package.tar.gz local/$BUCKET_PATH/app_package.tar.gz && \
    
    # 🔓 เปลี่ยน Access จาก CUSTOM เป็น DOWNLOAD (Public)
    mc anonymous set download local/$BUCKET_NAME/$PROJECT_NAME && \
    
    # ลบไฟล์ชั่วคราว
    rm /tmp/app_package.tar.gz
  "

  echo "▶ Updating latest.json..."
  # สร้าง latest.json ไว้ที่เครื่อง Jenkins เพื่อบันทึกประวัติ
  cat <<EOF > latest.json
{
  "version": "$VERSION",
  "url": "http://$MINIO_HOST:9000/$BUCKET_NAME/$PROJECT_NAME/$VERSION/app_package.tar.gz",
  "filename": "app_package.tar.gz"
}
EOF

  # ส่ง latest.json เข้าไปที่ MinIO ด้วยวิธีเดียวกัน
  docker cp latest.json "${CONTAINER_NAME}:/tmp/latest.json"
  docker exec -t "${CONTAINER_NAME}" mc cp /tmp/latest.json local/$BUCKET_NAME/$PROJECT_NAME/latest.json

  echo "✅ Done! เครื่องอื่นสามารถโหลดผ่านลิงก์ได้แล้ว (Public Download)"
}

main() {
  build_and_package
  upload_to_minio
}

main