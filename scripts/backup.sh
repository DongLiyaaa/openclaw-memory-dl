#!/usr/bin/env bash
# ═══════════════════════════════════════════
# 记忆架构全量备份 (Stable)
# ═══════════════════════════════════════════
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

BACKUP_DIR="${PROJECT_ROOT}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="memory-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

mkdir -p "$BACKUP_DIR" "$BACKUP_PATH"

echo "📦 OpenClaw Memory Backup"
echo "   目标: $BACKUP_PATH"
echo ""

ERRORS=0

# 1. Markdown 记忆
echo "  [1/4] Markdown 记忆..."
{
    [ -f "MEMORY.md" ] && cp MEMORY.md "$BACKUP_PATH/"
    [ -d "memory" ] && cp -r memory "$BACKUP_PATH/"
    info "完成"
} || { error "失败"; ERRORS=$((ERRORS+1)); }

# 2. 向量库
echo "  [2/4] LanceDB 向量库..."
{
    if [ -d "semantic_index" ]; then
        cp -r semantic_index "$BACKUP_PATH/"
        info "完成"
    else
        warn "跳过 (不存在)"
    fi
} || { error "失败"; ERRORS=$((ERRORS+1)); }

# 3. Memos 数据
echo "  [3/4] Memos 数据..."
{
    if docker ps --filter name=openclaw-memos -q 2>/dev/null | grep -q .; then
        docker exec openclaw-memos tar czf /tmp/memos-backup.tar.gz -C /var/opt/memos . 2>/dev/null
        docker cp openclaw-memos:/tmp/memos-backup.tar.gz "$BACKUP_PATH/memos-data.tar.gz" 2>/dev/null
        docker exec openclaw-memos rm -f /tmp/memos-backup.tar.gz 2>/dev/null
        info "完成 (Docker)"
    elif [ -d "${HOME}/.memos" ]; then
        cp -r "${HOME}/.memos" "$BACKUP_PATH/"
        info "完成 (本地)"
    else
        warn "跳过 (Memos 不可达)"
    fi
} || { error "失败"; ERRORS=$((ERRORS+1)); }

# 4. MySQL 数据
echo "  [4/4] MySQL 数据..."
{
    dump_mysql() {
        local host="${MYSQL_HOST:-localhost}"
        local port="${MYSQL_PORT:-3306}"
        local user="${MYSQL_USER:-openclaw}"
        local pass="${MYSQL_PASSWORD:-}"
        local db="${MYSQL_DATABASE:-openclaw_business}"
        MYSQL_PWD="$pass" mysqldump -h "$host" -P "$port" -u "$user" "$db" 2>/dev/null > "$BACKUP_PATH/mysql-dump.sql"
    }

    if docker ps --filter name=openclaw-mysql -q 2>/dev/null | grep -q .; then
        docker exec -i openclaw-mysql \
            mysqldump -u "${MYSQL_USER:-openclaw}" -p"${MYSQL_PASSWORD:-}" \
            "${MYSQL_DATABASE:-openclaw_business}" \
            > "$BACKUP_PATH/mysql-dump.sql" 2>/dev/null
        info "完成 (Docker)"
    elif command -v mysqldump &>/dev/null; then
        # 安全加载 .env
        if [ -f ".env" ]; then
            while IFS='=' read -r key value; do
                [[ "$key" =~ ^#.*$ ]] && continue
                [[ -z "$key" ]] && continue
                export "$key"="${value%%#*}"
            done < .env
        fi
        dump_mysql
        info "完成 (本地)"
    else
        warn "跳过 (MySQL 不可达)"
    fi
} || { error "失败"; ERRORS=$((ERRORS+1)); }

# 压缩
echo ""
echo "🗜️  压缩备份..."
cd "$BACKUP_DIR"
tar czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME" 2>/dev/null
rm -rf "$BACKUP_NAME"

BACKUP_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" 2>/dev/null | cut -f1)
echo ""

if [ "$ERRORS" -eq 0 ]; then
    echo "✅ 备份完成: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz (${BACKUP_SIZE})"
else
    echo "⚠️  备份完成但有 $ERRORS 个错误: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz (${BACKUP_SIZE})"
fi

# 清理 30 天前的备份
echo "🧹 清理旧备份 (>30天)..."
find "$BACKUP_DIR" -name "memory-*.tar.gz" -mtime +30 -delete 2>/dev/null
info "完成"
