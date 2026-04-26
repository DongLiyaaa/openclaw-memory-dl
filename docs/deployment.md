# 部署指南

## 前置条件

| 组件 | 最低要求 |
|------|----------|
| **Docker** | Docker Desktop (Mac/Win) 或 Docker Engine (Linux) |
| **Python** | 3.10+ |
| **Node.js** | 18+ |
| **内存** | 4GB (不含模型) / 8GB+ (含 bge-m3) |
| **磁盘** | 2GB+ (向量库 + 模型) |

## 方式一: Docker Compose (推荐)

```bash
# 1. 克隆
git clone https://github.com/<org>/openclaw-memory-dl.git
cd openclaw-memory-dl

# 2. 配置
cp .env.example .env
# 编辑 .env 修改密码

# 3. 一键启动
bash scripts/setup.sh
```

## 方式二: 手动部署

### 1. Memos

```bash
docker run -d \
  --name openclaw-memos \
  -p 5230:5230 \
  -v memos-data:/var/opt/memos \
  neosmemo/memos:latest
```

### 2. MySQL

```bash
docker run -d \
  --name openclaw-mysql \
  -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=rootpassword \
  -e MYSQL_DATABASE=openclaw_business \
  -e MYSQL_USER=openclaw \
  -e MYSQL_PASSWORD=openclaw_password \
  -v mysql-data:/var/lib/mysql \
  mysql:8.0 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci
```

### 3. Python 依赖

```bash
pip install lancedb sentence-transformers
```

### 4. 初始化

```bash
mkdir -p memory memory/hot semantic_index backups
bash scripts/health-check.sh
```

## 与 OpenClaw 集成

将记忆架构作为 OpenClaw 的数据底座：

### 1. 复制配置

```bash
cp config/openclaw-memory.json ~/.openclaw/workspace/config/memory.json
```

### 2. 配置 OpenClaw 环境变量

在 `~/.openclaw/openclaw.json` 或 `.env` 中设置：

```json
{
  "agents": {
    "defaults": {
      "memory": {
        "markdown_path": "/path/to/workspace/MEMORY.md",
        "memos_url": "http://localhost:5230",
        "lancedb_path": "/path/to/workspace/semantic_index",
        "mysql": {
          "host": "localhost",
          "port": 3306,
          "database": "openclaw_business",
          "user": "openclaw",
          "password": "your_password"
        }
      }
    }
  }
}
```

### 3. 设置定时任务 (可选)

```bash
# 每天凌晨 2 点自动向量化
crontab -e
0 2 * * * cd /path/to/openclaw-memory-dl && node scripts/vectorize.js --today >> /tmp/vectorize.log 2>&1
```

## 生产环境建议

| 项目 | 建议 |
|------|------|
| **向量库** | 数据量大时考虑 Milvus/Qdrant |
| **Memos** | 配置反向代理 + HTTPS |
| **MySQL** | 配置主从复制 + 定期备份 |
| **备份** | 异地备份 (S3 / NAS) |
| **监控** | 配置健康检查告警 |
