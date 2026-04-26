# OpenClaw Memory DL

> 可部署的 AI Agent 混合记忆架构 — OpenClaw 编排层 + Markdown 记忆 + Memos + LanceDB 向量库 + MySQL 结构化数据
>
> **版本**: 1.0.0 | **最后更新**: 2026-04-26

## 架构概览

```
┌─────────────────────────────────────────────────┐
│              OpenClaw Agent (编排层)              │
│  会话上下文 → Skills → 子代理 → 工具调用            │
└────┬────────┬────────┬────────┬─────────────────┘
     │        │        │        │
     ▼        ▼        ▼        ▼
┌────────┐┌────────┐┌────────┐┌────────┐
│Markdown││ Memos  ││LanceDB ││ MySQL  │
│  Memory││(轻量)  ││(语义)  ││(结构化) │
└────────┘└────────┘└────────┘└────────┘
 文件/目录   REST API   向量检索    SQL 查询
MEMORY.md  localhost   BGE-M3    业务数据
daily.md   :5230       Hybrid    ERP/报表
```

## 五层记忆体系

| 层级 | 组件 | 用途 | 检索方式 |
|------|------|------|----------|
| **L1 会话上下文** | OpenClaw Session | 当前任务、临时推理 | 会话内直接访问 |
| **L2 Markdown 记忆** | `MEMORY.md` + `memory/*.md` | 长期规则、偏好、每日事件 | 全文搜索 |
| **L3 Memos** | Memos 服务 (`:5230`) | 轻量事件记录、AI 自动沉淀 | REST API |
| **L4 向量库** | LanceDB + BGE-M3 | 语义检索、RAG 召回 | 向量相似度 + BM25 混合 |
| **L5 MySQL** | MySQL 数据库 | 结构化业务数据、时序分析 | SQL 查询 |

## 快速开始

```bash
# 1. 克隆
git clone https://github.com/<your-org>/openclaw-memory-dl.git
cd openclaw-memory-dl

# 2. 配置
cp .env.example .env
vim .env  # ⚠️ 必须修改所有默认密码，否则等于裸奔

# 3. 一键启动
bash scripts/setup.sh

# 4. 验证
npm run health
```

## 常用命令

```bash
# 健康检查
npm run health              # bash scripts/health-check.sh

# 向量化
npm run vectorize           # 全量向量化
npm run vectorize:today     # 仅向量化今日文件

# 备份/恢复
npm run backup              # 全量备份
bash scripts/restore.sh ./backups/memory-20260426.tar.gz

# 语义检索
python3 scripts/rag_search.py -q "之前怎么定的领星API"
python3 scripts/rag_search.py -q "广告优化策略" --hybrid --json
```

## 配置参考

| 文件 | 用途 |
|------|------|
| `config/rag-config.json` | RAG 检索参数 (模型、权重、分块) |
| `config/openclaw-memory.json` | OpenClaw 记忆层配置模板 |
| `.env.example` | 环境变量模板 |
| `docker-compose.yml` | Docker 服务编排 |

## 目录结构

```
openclaw-memory-dl/
├── README.md
├── docker-compose.yml          # Memos + MySQL + Adminer
├── .env.example                # 环境变量模板
├── .gitignore
├── package.json                # npm scripts
├── requirements.txt            # Python 依赖 (兼容范围约束)
├── config/
│   ├── rag-config.json         # RAG 配置
│   └── openclaw-memory.json    # OpenClaw 配置模板
├── scripts/
│   ├── setup.sh                # 一键初始化
│   ├── health-check.sh         # 健康检查
│   ├── backup.sh               # 备份 (含自动清理)
│   ├── restore.sh              # 恢复
│   ├── vectorize.js            # 向量化入口 (Node)
│   ├── embed_chunks.py         # BGE-M3 嵌入 (Python)
│   ├── rag_search.py           # 语义检索 (Python)
│   └── init-mysql.sql          # MySQL 表结构
├── docs/
│   ├── architecture.md         # 架构设计
│   ├── deployment.md           # 部署指南
│   ├── config-reference.md     # 配置参考
│   └── memory-lifecycle.md     # 记忆生命周期
├── memory/                     # Markdown 记忆 (gitignore)
├── semantic_index/             # LanceDB 向量库 (gitignore)
└── backups/                    # 备份文件 (gitignore)
```

## 技术栈

- **编排**: OpenClaw
- **向量库**: LanceDB (嵌入式)
- **嵌入模型**: BAAI/bge-m3 (1024 维)
- **重排序**: BAAI/bge-reranker-v2-m3
- **轻量记忆**: Memos (自托管, `neosmemo/memos:stable`)
- **结构化数据**: MySQL 8.0 (`mysql:8.0`)
- **混合检索**: 向量 (0.6) + BM25 (0.4) + Reranker

## License

Apache License 2.0
