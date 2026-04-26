# 配置参考

## RAG 配置 (config/rag-config.json)

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `model` | string | `BAAI/bge-m3` | 嵌入模型名称 |
| `hf_endpoint` | string | `https://hf-mirror.com` | HuggingFace 镜像 |
| `vector_db` | string | `lancedb` | 向量库类型 |
| `lancedb_path` | string | `./semantic_index` | LanceDB 存储路径 |
| `table_name` | string | `openclaw_memory` | 向量表名称 |
| `vector_dim` | int | `1024` | 向量维度 |
| `chunk_size` | int | `500` | 文本分块大小 |
| `overlap` | int | `50` | 分块重叠 |
| `max_length` | int | `512` | 最大输入长度 |
| `search_overfetch_factor` | int | `2` | 检索过取因子 |
| `reranker_enabled` | bool | `true` | 是否启用重排序 |
| `reranker_model` | string | `BAAI/bge-reranker-v2-m3` | 重排序模型 |
| `reranker_batch_size` | int | `16` | 重排序批次 |
| `reranker_top_n` | int | `24` | 重排序返回数量 |
| `hybrid_enabled` | bool | `true` | 是否启用混合检索 |
| `vector_weight` | float | `0.6` | 向量权重 |
| `keyword_weight` | float | `0.4` | 关键词权重 |

## OpenClaw 记忆配置 (config/openclaw-memory.json)

### Markdown 记忆

| 字段 | 说明 |
|------|------|
| `memory.markdown.enabled` | 是否启用 |
| `memory.markdown.long_term` | 长期记忆文件路径 |
| `memory.markdown.daily_pattern` | 每日记忆文件名模式 |
| `memory.markdown.hot_memory` | 热记忆文件 (检查点) |
| `memory.markdown.compact_threshold_percent` | 压缩阈值 (%) |

### Memos

| 字段 | 说明 |
|------|------|
| `memory.memos.enabled` | 是否启用 |
| `memory.memos.url` | Memos 服务地址 |
| `memory.memos.token_env` | Token 环境变量名称 |

### 向量库

| 字段 | 说明 |
|------|------|
| `memory.vector_db.enabled` | 是否启用 |
| `memory.vector_db.type` | 向量库类型 |
| `memory.vector_db.embedding_model` | 嵌入模型 |
| `memory.vector_db.hybrid_search` | 是否混合检索 |

### MySQL

| 字段 | 说明 |
|------|------|
| `memory.mysql.enabled` | 是否启用 |
| `memory.mysql.host` | 主机地址 |
| `memory.mysql.port` | 端口 |
| `memory.mysql.database` | 数据库名 |
| `memory.mysql.user` | 用户名 |
| `memory.mysql.password_env` | 密码环境变量名 |

### 搜索优先级

```json
{
  "search_priority": {
    "historical_decision": ["markdown", "memos", "vector_db"],
    "historical_document": ["vector_db", "markdown"],
    "business_data": ["mysql", "vector_db"]
  }
}
```

| 场景 | 优先级 | 说明 |
|------|--------|------|
| `historical_decision` | Markdown → Memos → 向量库 | 查找历史决策 |
| `historical_document` | 向量库 → Markdown | 查找相似文档 |
| `business_data` | MySQL → 向量库 | 业务数据分析 |
