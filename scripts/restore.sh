#!/usr/bin/env bash
# ═══════════════════════════════════════════
# 记忆架构恢复 (Stable)
# ═══════════════════════════════════════════
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

if [ $# -lt 1 ]; then
    echo "用法: $0 <备份文件>"
    echo ""
    echo "可用备份 (最近 10 个):"
    ls -lt backups/memory-*.tar.gz 2>/dev/null | head -10 || echo "  (无)"
    exit 1
fi

BACKUP_FILE="$1"
if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ 文件不存在: $BACKUP_FILE"
    exit 1
fi

echo "⚠️  即将恢复记忆架构，这将覆盖当前数据"
echo "   备份文件: $BACKUP_FILE"
echo ""
read -p "确认恢复? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "📦 解压备份..."
if ! tar xzf "$BACKUP_FILE" -C "$TEMP_DIR" 2>/dev/null; then
    echo "❌ 解压失败"
    exit 1
fi

RESTORED_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "memory-*" | head -1)
if [ -z "$RESTORED_DIR" ]; then
    echo "❌ 备份文件格式错误"
    exit 1
fi

echo "🔄 开始恢复..."

# 1. Markdown 记忆
{
    [ -f "$RESTORED_DIR/MEMORY.md" ] && cp "$RESTORED_DIR/MEMORY.md" "$PROJECT_ROOT/MEMORY.md"
    [ -d "$RESTORED_DIR/memory" ] && rsync -a "$RESTORED_DIR/memory/" "$PROJECT_ROOT/memory/"
    echo "  ✅ Markdown 记忆"
} || echo "  ⚠️ Markdown 恢复部分失败"

# 2. 向量库
{
    if [ -d "$RESTORED_DIR/semantic_index" ]; then
        STAGED_INDEX_DIR="$TEMP_DIR/semantic_index.restored"
        CURRENT_INDEX_DIR="$PROJECT_ROOT/semantic_index"
        SAFETY_BACKUP_DIR="$PROJECT_ROOT/semantic_index.pre-restore.$(date +%Y%m%d_%H%M%S)"

        cp -R "$RESTORED_DIR/semantic_index" "$STAGED_INDEX_DIR"

        if [ ! -d "$STAGED_INDEX_DIR" ]; then
            echo "  ❌ 向量库暂存失败"
            false
        fi

        if [ -d "$CURRENT_INDEX_DIR" ]; then
            mv "$CURRENT_INDEX_DIR" "$SAFETY_BACKUP_DIR"
        else
            SAFETY_BACKUP_DIR=""
        fi

        if mv "$STAGED_INDEX_DIR" "$CURRENT_INDEX_DIR"; then
            echo "  ✅ LanceDB 向量库"
            if [ -n "$SAFETY_BACKUP_DIR" ]; then
                echo "  ℹ️ 旧向量库已备份到: $SAFETY_BACKUP_DIR"
            fi
        else
            [ -n "$SAFETY_BACKUP_DIR" ] && mv "$SAFETY_BACKUP_DIR" "$CURRENT_INDEX_DIR"
            echo "  ❌ 向量库切换失败，已回滚"
            false
        fi
    else
        echo "  ⏭️ 跳过 (备份中无向量库)"
    fi
} || echo "  ⚠️ 向量库恢复失败"

# 3. Memos 数据
{
    if [ -f "$RESTORED_DIR/memos-data.tar.gz" ]; then
        if docker ps --filter name=openclaw-memos -q 2>/dev/null | grep -q .; then
            docker cp "$RESTORED_DIR/memos-data.tar.gz" openclaw-memos:/tmp/memos-restore.tar.gz
            docker exec openclaw-memos bash -c "cd /var/opt/memos && tar xzf /tmp/memos-restore.tar.gz && rm -f /tmp/memos-restore.tar.gz"
            echo "  ✅ Memos 数据"
        else
            echo "  ⏭️ Memos 未运行，跳过"
        fi
    else
        echo "  ⏭️ 跳过 (备份中无 Memos 数据)"
    fi
} || echo "  ⚠️ Memos 恢复失败"

# 4. MySQL 数据
{
    if [ -f "$RESTORED_DIR/mysql-dump.sql" ]; then
        if docker ps --filter name=openclaw-mysql -q 2>/dev/null | grep -q .; then
            # 加载 .env
            if [ -f ".env" ]; then
                while IFS='=' read -r key value; do
                    [[ "$key" =~ ^#.*$ ]] && continue
                    [[ -z "$key" ]] && continue
                    export "$key"="${value%%#*}"
                done < .env
            fi
            docker exec -i openclaw-mysql \
                mysql -u "${MYSQL_USER:-openclaw}" -p"${MYSQL_PASSWORD:-}" \
                "${MYSQL_DATABASE:-openclaw_business}" \
                < "$RESTORED_DIR/mysql-dump.sql"
            echo "  ✅ MySQL 数据"
        else
            echo "  ⏭️ MySQL 未运行，跳过"
        fi
    else
        echo "  ⏭️ 跳过 (备份中无 MySQL 数据)"
    fi
} || echo "  ⚠️ MySQL 恢复失败"

echo ""
echo "✅ 恢复完成!"
echo ""
echo "建议验证:"
echo "  1. bash scripts/health-check.sh"
echo "  2. cat MEMORY.md | head -20"
