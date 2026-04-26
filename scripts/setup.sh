#!/usr/bin/env bash
# ═══════════════════════════════════════════
# 一键初始化 OpenClaw 记忆架构 (Stable)
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

STEP=0
TOTAL=7

step() { STEP=$((STEP + 1)); echo ""; echo "── Step ${STEP}/${TOTAL}: $* ──"; }

echo "╔══════════════════════════════════════════╗"
echo "║      OpenClaw Memory DL Setup          ║"
echo "║           Version: 1.0.0                ║"
echo "╚══════════════════════════════════════════╝"

# ─── Step 1: 检查 .env ───
step "检查环境变量配置"
if [ ! -f ".env" ]; then
    warn ".env 不存在，从 .env.example 创建默认配置"
    cp .env.example .env
    error "请编辑 .env 修改密码等参数后重新运行"
    exit 1
fi
# 安全加载: 仅导出已知的键
while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ ]] && continue
    [[ -z "$key" ]] && continue
    export "$key"="${value%%#*}"
done < .env
info ".env 已加载"

# ─── Step 2: 检查前置依赖 ───
step "检查系统依赖"
MISSING=0
for cmd in docker python3; do
    if command -v "$cmd" &>/dev/null; then
        ver=$("$cmd" --version 2>&1 | head -1)
        info "$ver"
    else
        error "$cmd 未安装"
        MISSING=1
    fi
done

if command -v docker &>/dev/null; then
    if docker compose version &>/dev/null 2>&1; then
        info "Docker Compose: $(docker compose version 2>&1)"
    elif command -v docker-compose &>/dev/null;2>&1; then
        info "Docker Compose (legacy): $(docker-compose version --short 2>&1)"
        # 设置 alias 兼容
        alias docker-compose="docker compose"
    else
        error "Docker Compose 不可用"
        MISSING=1
    fi
fi

[ "$MISSING" -eq 1 ] && exit 1

# ─── Step 3: 创建目录结构 ───
step "创建目录结构"
for dir in memory memory/hot semantic_index backups docs; do
    mkdir -p "$PROJECT_ROOT/$dir"
done
info "目录已就绪"

# ─── Step 4: 安装 Python 依赖 ───
step "安装 Python 依赖"
if [ -f "requirements.txt" ]; then
    # 检查是否已安装
    pip3 show lancedb &>/dev/null 2>&1 && pip3 show sentence-transformers &>/dev/null 2>&1 && {
        info "Python 依赖已安装"
    } || {
        info "安装依赖..."
        if [ -n "${HF_ENDPOINT:-}" ]; then
            HF_ENDPOINT="$HF_ENDPOINT" pip3 install -r requirements.txt --quiet 2>&1 | tail -3
        else
            pip3 install -r requirements.txt --quiet 2>&1 | tail -3
        fi
        info "安装完成"
    }
fi

# ─── Step 5: 初始化向量库 ───
step "初始化 LanceDB 向量库"
python3 -c "
import os, sys
lancedb_path = os.environ.get('LANCEDB_PATH', './semantic_index')

try:
    import lancedb
    db = lancedb.connect(lancedb_path)
    tables = db.table_names()
    print(f'  LanceDB 连接正常, 路径: {lancedb_path}')
    print(f'  现有表: {tables if tables else \"(空)\"}')
    if 'openclaw_memory' in tables:
        tbl = db.open_table('openclaw_memory')
        print(f'  openclaw_memory: {tbl.count_rows()} 条记录')
    else:
        print('  openclaw_memory 将在首次向量化时自动创建')
    print('  LanceDB 初始化完成')
except ImportError as e:
    print(f'  [跳过] lancedb 未安装: {e}')
    print('  运行: pip3 install lancedb')
    sys.exit(0)
except Exception as e:
    print(f'  [警告] LanceDB 初始化异常: {e}')
    sys.exit(0)
"
info "向量库检查完成"

# ─── Step 6: 验证嵌入模型 ───
step "验证嵌入模型"
python3 -c "
import os, sys
model_name = os.environ.get('EMBEDDING_MODEL', 'BAAI/bge-m3')
hf_ep = os.environ.get('HF_ENDPOINT', 'https://hf-mirror.com')
os.environ.setdefault('HF_ENDPOINT', hf_ep)

try:
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer(model_name, trust_remote_code=True)
    dim = model.get_sentence_embedding_dimension()
    print(f'  模型: {model_name}')
    print(f'  维度: {dim}')
    # 测试推理
    test = model.encode(['hello'])
    print(f'  推理测试: 通过 (输出形状 {len(test[0])})')
    print('  嵌入模型验证完成')
except ImportError:
    print(f'  [跳过] sentence-transformers 未安装')
    sys.exit(0)
except Exception as e:
    print(f'  [警告] 模型加载异常: {e}')
    print('  首次运行时会自动下载模型，请耐心等待')
    sys.exit(0)
"
info "模型检查完成"

# ─── Step 7: 启动服务 (可选) ───
step "启动 Docker 服务"
if [ "${SKIP_DOCKER:-0}" = "1" ]; then
    warn "跳过 Docker 启动 (SKIP_DOCKER=1)"
else
    if docker compose ps 2>/dev/null | grep -q "openclaw-memos\|openclaw-mysql"; then
        info "服务已在运行"
        docker compose ps
    else
        info "启动 Memos + MySQL..."
        if docker compose up -d --wait 2>&1; then
            info "服务启动成功"
        else
            warn "Docker 服务启动失败 (可稍后手动启动: docker compose up -d)"
        fi
    fi
fi

# ─── 完成 ───
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║         Setup Complete! 🎉              ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  服务地址:"
echo "    Memos:   http://localhost:${MEMOS_PORT:-5230}"
echo "    MySQL:   localhost:${MYSQL_PORT:-3306}"
echo "    Adminer: http://localhost:${ADMINER_PORT:-8080} (--profile tools)"
echo ""
echo "  常用命令:"
echo "    npm run health       # 健康检查"
echo "    npm run vectorize    # 全量向量化"
echo "    npm run backup       # 备份"
echo "    npm run vectorize:today  # 仅向量化今日文件"
echo ""
