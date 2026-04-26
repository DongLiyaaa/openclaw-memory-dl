#!/usr/bin/env python3
"""
RAG 语义检索 (Stable)
从 LanceDB 向量库中检索相关记忆
"""

import argparse
import json
import os
import sys
from pathlib import Path


def load_config(config_path=None):
    """加载 RAG 配置"""
    if config_path is None:
        candidates = [
            Path(__file__).parent.parent / "config" / "rag-config.json",
            Path("./config/rag-config.json"),
        ]
        for c in candidates:
            if c.exists():
                config_path = str(c)
                break

    if config_path and os.path.exists(config_path):
        with open(config_path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {
        "model": "BAAI/bge-m3",
        "lancedb_path": "./semantic_index",
        "table_name": "openclaw_memory",
        "search_overfetch_factor": 2,
        "reranker_enabled": False,
        "hybrid_enabled": False,
        "vector_weight": 0.6,
        "keyword_weight": 0.4,
    }


def vector_search(query, table, model, top_k=10, overfetch=2):
    """向量相似度搜索"""
    query_embedding = model.encode([query])[0].tolist()
    n_results = top_k * overfetch
    results = table.search(query_embedding).limit(n_results).to_pandas()
    return results.to_dict("records")


def keyword_search(query, table, top_k=10):
    """BM25/FTS 搜索"""
    try:
        results = table.search(query, query_type="fts").limit(top_k).to_pandas()
        return results.to_dict("records")
    except Exception as e:
        return []


def hybrid_search(query, table, model, config, top_k=10):
    """混合搜索: 向量 + 关键词 + 归一化合并"""
    vec_weight = config.get("vector_weight", 0.6)
    kw_weight = config.get("keyword_weight", 0.4)
    overfetch = config.get("search_overfetch_factor", 2)

    vec_results = vector_search(query, table, model, top_k, overfetch)
    kw_results = keyword_search(query, table, top_k * overfetch)

    def normalize(results, score_key, invert=False):
        if not results:
            return results
        scores = [r.get(score_key, 0) for r in results]
        min_s, max_s = min(scores), max(scores)
        for r in results:
            s = r.get(score_key, 0)
            if max_s == min_s:
                r["_normalized"] = 1.0
            else:
                val = (s - min_s) / (max_s - min_s)
                r["_normalized"] = 1 - val if invert else val
        return results

    vec_results = normalize(vec_results, "_distance", invert=True)
    kw_results = normalize(kw_results, "_score", invert=False)

    # 按 id 合并
    combined = {}
    for r in vec_results:
        rid = r.get("id", r.get("text", "")[:32])
        combined[rid] = {**r, "_combined_score": r.get("_normalized", 0) * vec_weight}

    for r in kw_results:
        rid = r.get("id", r.get("text", "")[:32])
        if rid in combined:
            combined[rid]["_combined_score"] += r.get("_normalized", 0) * kw_weight
        else:
            combined[rid] = {**r, "_combined_score": r.get("_normalized", 0) * kw_weight}

    results = sorted(combined.values(), key=lambda x: x.get("_combined_score", 0), reverse=True)
    return results[:top_k]


def main():
    parser = argparse.ArgumentParser(description="RAG 语义检索")
    parser.add_argument("--query", "-q", required=True, help="查询文本")
    parser.add_argument("--top-k", "-k", type=int, default=10, help="返回结果数")
    parser.add_argument("--hybrid", action="store_true", help="启用混合检索")
    parser.add_argument("--rerank", action="store_true", help="启用重排序")
    parser.add_argument("--config", "-c", help="配置文件路径")
    parser.add_argument("--json", action="store_true", help="JSON 格式输出")
    parser.add_argument("--source", "-s", help="过滤来源文件")
    args = parser.parse_args()

    config = load_config(args.config)

    # 加载模型
    print(f"🔧 加载模型: {config['model']}...")
    try:
        from sentence_transformers import SentenceTransformer
    except ImportError:
        print("❌ sentence-transformers 未安装")
        sys.exit(1)

    hf_endpoint = config.get("hf_endpoint", "https://hf-mirror.com")
    os.environ.setdefault("HF_ENDPOINT", hf_endpoint)

    try:
        model = SentenceTransformer(config["model"], trust_remote_code=True)
    except Exception as e:
        print(f"❌ 模型加载失败: {e}")
        sys.exit(1)

    # 连接 LanceDB
    lancedb_path = config.get("lancedb_path", "./semantic_index")
    table_name = config.get("table_name", "openclaw_memory")

    try:
        import lancedb
    except ImportError:
        print("❌ lancedb 未安装")
        sys.exit(1)

    if not os.path.exists(lancedb_path):
        print(f"❌ 向量库不存在: {lancedb_path}")
        sys.exit(1)

    db = lancedb.connect(lancedb_path)
    if table_name not in db.table_names():
        print(f"❌ 表不存在: {table_name}")
        print(f"   可用表: {db.table_names()}")
        sys.exit(1)

    table = db.open_table(table_name)
    row_count = table.count_rows()
    print(f"📊 向量库: {row_count} 条记录")

    # 搜索
    print(f"🔍 查询: {args.query}")

    if args.hybrid and config.get("hybrid_enabled", False):
        results = hybrid_search(args.query, table, model, config, args.top_k)
        search_type = "混合检索"
    else:
        results = vector_search(args.query, table, model, args.top_k)
        search_type = "向量检索"

    print(f"  [{search_type}]")

    # 重排序
    if args.rerank and config.get("reranker_enabled", False):
        try:
            from sentence_transformers import CrossEncoder
            reranker = CrossEncoder(config.get("reranker_model", "BAAI/bge-reranker-v2-m3"))
            texts = [r.get("text", "") for r in results]
            pairs = [(args.query, t) for t in texts]
            scores = reranker.predict(pairs, batch_size=16)
            for i, s in enumerate(scores):
                results[i]["_rerank_score"] = float(s)
            results.sort(key=lambda x: x.get("_rerank_score", 0), reverse=True)
            results = results[: args.top_k]
            print("  [已重排序]")
        except Exception as e:
            print(f"  [重排序跳过: {e}]")

    # 过滤
    if args.source:
        results = [r for r in results if args.source in r.get("source", "")]

    # 输出
    if args.json:
        output = []
        for r in results:
            output.append(
                {
                    "id": r.get("id"),
                    "text": r.get("text", "")[:500],
                    "source": r.get("source"),
                    "score": round(r.get("_combined_score") or r.get("_distance", 0), 4),
                    "timestamp": r.get("timestamp"),
                    "metadata": r.get("metadata"),
                }
            )
        print(json.dumps(output, ensure_ascii=False, indent=2))
    else:
        print(f"\n找到 {len(results)} 条结果:\n")
        for i, r in enumerate(results, 1):
            source = r.get("source", "unknown")
            score = r.get("_combined_score") or r.get("_distance", 0)
            text = r.get("text", "")
            if len(text) > 300:
                text = text[:300] + "..."
            print(f"  [{i}] {source} (score: {score:.4f})")
            print(f"      {text}")
            print()


if __name__ == "__main__":
    main()
