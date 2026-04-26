# 架构设计详解

## 五层记忆体系

### L1: 会话上下文 (Session Context)

- **生命周期**: 单次对话
- **存储**: OpenClaw 内存
- **用途**: 当前任务、临时推理、工具调用链
- **检索**: 直接访问，无需查询

### L2: Markdown 记忆 (Markdown Memory)

- **文件**: `MEMORY.md` (长期) + `memory/YYYY-MM-DD.md` (每日)
- **生命周期**: 永久，人工 + AI 维护
- **更新策略**:
  - 每日事件 → `memory/YYYY-MM-DD.md`
  - 长期规则/偏好 → `MEMORY.md`
  - 心跳周期压缩 → `autollmse-dl`
- **查询方式**: 全文搜索、关键词匹配、正则
- **优势**: 人类可读、Git 版本控制、零依赖

### L3: Memos (轻量记忆)

- **服务**: 自托管 Memos (`http://localhost:5230`)
- **API**: REST API v1
- **生命周期**: 永久
- **用途**: AI 自动记录、轻量事件、对话摘要
- **特点**: 快速写入、标签系统、Markdown 支持
- **心跳监控**: 每小时检查服务状态，异常自动重启

### L4: 向量库 (Vector DB - LanceDB)

- **引擎**: LanceDB (嵌入式，无服务器)
- **嵌入模型**: BAAI/bge-m3 (1024 维)
- **检索**: 向量相似度 + BM25 混合 + Reranker 重排序
- **权重**: 向量 0.6 + 关键词 0.4
- **优势**: 本地运行、无需外部服务、隐私安全

#### 检索流程

```
查询文本
  → BGE-M3 嵌入 (1024 维向量)
  → 向量检索 (top_k × overfetch)
  → BM25 关键词检索
  → 归一化合并 (0.6/0.4 权重)
  → BGE Reranker 重排序
  → 返回 top_k 结果
```

### L5: MySQL (结构化数据)

- **服务**: MySQL 8.0 (Docker 或本地)
- **用途**: 广告指标、业务数据、时序分析
- **表结构**:
  - `ad_campaigns` — 广告活动
  - `ad_metrics_daily` — 广告日指标
  - `products` — 产品/ASIN
  - `business_metrics_daily` — 业务日指标
  - `keywords` — 关键词库
  - `system_logs` — 系统日志

## 查询优先级

| 场景 | 优先级 |
|------|--------|
| "之前怎么定的" | Markdown → Memos → 向量库 |
| "有没有类似方案" | 向量库 → docs/ → Markdown |
| "ASIN 表现如何" | MySQL → ERP 数据 → 向量库 |
| "今天做了什么" | memory/YYYY-MM-DD.md → Memos |

## 数据流

```
用户请求
  ↓
OpenClaw Agent
  ├─ 会话上下文 (L1)
  ├─ memory_search() → L2 (Markdown)
  ├─ vector_search() → L4 (LanceDB)
  ├─ memos_query()   → L3 (Memos)
  └─ mysql_query()   → L5 (MySQL)
  ↓
综合结果 → 回答
```

## 备份策略

- **频率**: 按需手动执行 `backup.sh`
- **内容**: Markdown + 向量库 + Memos + MySQL
- **保留**: 30 天
- **恢复**: `restore.sh <备份文件>`
