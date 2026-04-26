#!/usr/bin/env bash
# ═══════════════════════════════════════════
# 记忆架构健康检查 (Stable)
# ═══════════════════════════════════════════
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# 安全加载 .env
if [ -f ".env" ]; then
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        export "$key"="${value%%#*}"
    done < .env
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✅${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠️${NC} $*"; }
fail() { echo -e "  ${RED}❌${NC} $*"; }
section() { echo -e "\n${BLUE}─── $* ───${NC}"; }

section "OpenClaw 记忆架构健康检查"
STATUS=0

# ─── L2: Markdown Memory ───
section "L2: Markdown 记忆"
if [ -f "MEMORY.md" ]; then
    lines=$(wc -l < MEMORY.md 2>/dev/null || echo "?")
    ok "MEMORY.md 存在 (${lines} 行)"
    if [ "$(uname)" = "Darwin" ]; then
        mod_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" MEMORY.md 2>/dev/null || echo "?")
    else
        mod_time=$(stat -c "%y" MEMORY.md 2>/dev/null | cut -d' ' -f1 || echo "?")
    fi
    ok "最后更新: $mod_time"
else
    warn "MEMORY.md 不存在"
    STATUS=1
fi

daily_count=$(find memory -name "*.md" -not -path "memory/hot/*" 2>/dev/null | wc -l)
ok "每日记忆文件: ${daily_count} 个"

if [ -f "memory/hot/HOT_MEMORY.md" ]; then
    ok "HOT_MEMORY.md 存在"
else
    warn "HOT_MEMORY.md 不存在 (长任务中应存在)"
fi

# ─── L3: Memos ───
section "L3: Memos 服务"
MEMOS_URL="${MEMOS_URL:-http://localhost:5230}"
MEMOS_TOKEN="${MEMOS_TOKEN:-}"

if curl -sf --max-time 5 "$MEMOS_URL/api/v1/status" >/dev/null 2>&1; then
    ok "Memos API 可达 ($MEMOS_URL)"
    if [ -n "$MEMOS_TOKEN" ] && [ "$MEMOS_TOKEN" != "your-memos-token-here" ]; then
        count=$(curl -sf --max-time 5 "$MEMOS_URL/api/v1/memos" \
            -H "Authorization: Bearer $MEMOS_TOKEN" 2>/dev/null | \
            python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('memos',[])))" 2>/dev/null || echo "?")
        ok "Memos 记录数: $count"
    else
        warn "MEMOS_TOKEN 未设置，无法查询记录数"
    fi
    if docker ps --filter name=openclaw-memos --format '{{.Status}}' 2>/dev/null | grep -q up; then
        ok "Memos Docker 运行中"
    elif pgrep -x memos >/dev/null 2>&1; then
        ok "Memos 进程运行中"
    else
        warn "Memos 非 Docker/本地进程 (可能外部部署)"
    fi
else
    fail "Memos 不可达 ($MEMOS_URL)"
    STATUS=1
fi

# ─── L4: LanceDB ───
section "L4: LanceDB 向量库"
LANCEDB_PATH="${LANCEDB_PATH:-./semantic_index}"

if [ -d "$LANCEDB_PATH" ]; then
    ok "向量库目录存在 ($LANCEDB_PATH)"

    tables=$(find "$LANCEDB_PATH" -name "*.lance" -maxdepth 1 -type d 2>/dev/null -exec basename {} .lance \; 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    table_count=$(echo "$tables" | tr ',' '\n' | grep -c . 2>/dev/null || echo "0")
    ok "向量表: ${table_count:-0} 个 (${tables:-无})"

    python3 -c "
import lancedb, os
db = lancedb.connect('${LANCEDB_PATH}')
for name in db.table_names():
    tbl = db.open_table(name)
    print(f'  📊 {name}: {tbl.count_rows()} 条向量')
" 2>/dev/null || warn "LanceDB Python 查询失败 (可能未安装)"
else
    fail "向量库目录不存在 ($LANCEDB_PATH)"
    warn "运行: bash scripts/setup.sh"
    STATUS=1
fi

# ─── L5: MySQL ───
section "L5: MySQL 结构化数据"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-openclaw}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_DATABASE="${MYSQL_DATABASE:-openclaw_business}"

if docker ps --filter name=openclaw-mysql --format '{{.Status}}' 2>/dev/null | grep -q up; then
    ok "MySQL Docker 运行中"
    if command -v mysql &>/dev/null; then
        if MYSQL_PWD="$MYSQL_PASSWORD" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "SELECT 1" "$MYSQL_DATABASE" >/dev/null 2>&1; then
            ok "MySQL 连接正常"
            table_count=$(MYSQL_PWD="$MYSQL_PASSWORD" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$MYSQL_DATABASE'" 2>/dev/null || echo "?")
            ok "数据库表数: $table_count"
        else
            warn "MySQL 容器运行中但连接失败 (检查密码)"
            STATUS=1
        fi
    else
        warn "本地无 mysql 客户端，跳过连接测试"
    fi
else
    if command -v mysql &>/dev/null && MYSQL_PWD="$MYSQL_PASSWORD" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "SELECT 1" "$MYSQL_DATABASE" >/dev/null 2>&1; then
        ok "MySQL 连接正常 (本地)"
    else
        fail "MySQL 不可达 ($MYSQL_HOST:$MYSQL_PORT)"
        STATUS=1
    fi
fi

# ─── 系统资源 ───
section "系统资源"
disk_usage=$(df -h "$PROJECT_ROOT" 2>/dev/null | tail -1 | awk '{print $5}')
ok "磁盘使用: $disk_usage"

if command -v python3 &>/dev/null; then
    ok "Python: $(python3 --version 2>&1)"
fi
if command -v node &>/dev/null; then
    ok "Node.js: $(node --version 2>&1)"
fi
if command -v docker &>/dev/null; then
    ok "Docker: $(docker --version 2>&1)"
fi

# ─── 总结 ───
echo ""
if [ "$STATUS" -eq 0 ]; then
    echo -e "${GREEN}✅ 所有检查通过${NC}"
else
    echo -e "${YELLOW}⚠️  部分检查未通过，请检查上方标记${NC}"
fi
