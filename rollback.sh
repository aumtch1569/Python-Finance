#!/bin/bash

rollback() {
  echo ""
  echo "🛑 ERROR OCCURRED — STARTING ROLLBACK"
  echo ""

  ### VALIDATE REQUIRED VARS ###
  : "${DEPLOY_DIR:?❌ DEPLOY_DIR not set}"
  : "${BACKUP_DIR:?❌ BACKUP_DIR not set}"

  echo "📌 Deploy dir : $DEPLOY_DIR"
  echo "📌 Backup dir : $BACKUP_DIR"
  echo ""

  ### STOP CONTAINERS ###
  if [ -d "$DEPLOY_DIR" ]; then
    echo "🛑 Stopping containers..."
    cd "$DEPLOY_DIR"
    docker compose down 2>/dev/null || true
  fi

  ### RESTORE FROM BACKUP ###
  if [ -d "$BACKUP_DIR" ]; then
    echo "📦 Restoring from backup..."

    # ลบไฟล์เดิม (ยกเว้น .git)
    echo "🗑️  Cleaning current deployment..."
    rsync -a --delete \
      --exclude='.git' --exclude='n4.env' \
      "$BACKUP_DIR"/ "$DEPLOY_DIR"/

    echo "✅ Restore completed"
  else
    echo "❌ Backup directory not found: $BACKUP_DIR"
    echo "⚠️  Cannot rollback automatically"
    exit 1
  fi

  ### START CONTAINERS ###
  echo "🚀 Starting containers after rollback..."
  cd "$DEPLOY_DIR"
  
  if [ -z "$SERVICES" ]; then
    echo "🐳 docker compose up -d (all services)"
    docker compose up -d
  else
    echo "🐳 docker compose up -d --no-deps $SERVICES"
    docker compose up -d --no-deps $SERVICES
  fi

  echo ""
  echo "✅ Rollback completed successfully"
  exit 1
}
