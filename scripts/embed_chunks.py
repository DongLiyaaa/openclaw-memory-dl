#!/usr/bin/env python3
"""
嵌入脚本 (Stable) - 被 vectorize.js 调用
将文本块向量化并写入 LanceDB
"""

import json
import os
import sys
import time
import hashlib
from pathlib import Path


def load_manifest(manifest_path):
    if not manifest_path.exists():
        return set()

    try:
        with manifest_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return set()

    chunk_ids = data.get("chunk_ids", [])
    return {item for item in chunk_ids if isinstance(item, str)}


def save_manifest(manifest_path, chunk_ids):
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"chunk_ids": sorted(chunk_ids)}
    with manifest_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def main():
    if len(sys.argv) < 2:
        print("用法: python3 embed_chunks.py <temp_json_file>")
        sys.exit(1)

    temp_file = sys.argv[1]
    if not os.path.exists(temp_file):
        print(f"❌ 临时文件不存在: {temp_file}")
        sys.exit(1)

    with open(temp_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    chunks = data.get("chunks", [])
    config = data.get("config", {})

    if not chunks:
        print("无可向量化内容")
        return

    lancedb_path = config.get("lancedb_path", "./semantic_index")
    table_name = config.get("table_name", "openclaw_memory")
    manifest_path = Path(lancedb_path) / ".indexed_chunks.json"

    prepared_records = []
    for chunk in chunks:
        chunk_id = hashlib.md5(
            f"{chunk['source']}:{chunk['chunk_idx']}:{chunk.get('timestamp', 0)}".encode()
        ).hexdigest()[:16]
        prepared_records.append((chunk_id, chunk))

    known_ids = load_manifest(manifest_path)
    pending_records = [(chunk_id, chunk) for chunk_id, chunk in prepared_records if chunk_id not in known_ids]
    skipped = len(prepared_records) - len(pending_records)

    if skipped:
        print(f"⏭️ 跳过已存在 chunk: {skipped} 条")

    if not pending_records:
        print("✅ 无新增 chunk，跳过向量化")
        return

    print(f"🔧 加载嵌入模型...")

    try:
        from sentence_transformers import SentenceTransformer
    except ImportError:
        print("❌ sentence-transformers 未安装")
        print("   运行: pip3 install sentence-transformers")
        sys.exit(1)

    model_name = config.get("model", "BAAI/bge-m3")
    hf_endpoint = config.get("hf_endpoint", "https://hf-mirror.com")
    os.environ.setdefault("HF_ENDPOINT", hf_endpoint)

    try:
        model = SentenceTransformer(model_name, trust_remote_code=True)
        dim = model.get_sentence_embedding_dimension()
        print(f"   模型: {model_name} (维度: {dim})")
    except Exception as e:
        print(f"❌ 模型加载失败: {e}")
        sys.exit(1)

    # 批量嵌入
    texts = [chunk["text"] for _, chunk in pending_records]
    batch_size = 32
    total = len(texts)

    print(f"📊 生成 {total} 个新增嵌入...")
    embeddings = []
    for i in range(0, total, batch_size):
        batch = texts[i : i + batch_size]
        batch_emb = model.encode(batch, show_progress_bar=(i == 0))
        embeddings.extend(batch_emb.tolist())
        done = min(i + batch_size, total)
        print(f"   进度: {done}/{total}")

    # 写入 LanceDB
    print(f"💾 写入 LanceDB ({lancedb_path}/{table_name})...")

    try:
        import lancedb
    except ImportError:
        print("❌ lancedb 未安装")
        print("   运行: pip3 install lancedb")
        sys.exit(1)

    db = lancedb.connect(lancedb_path)
    records = []
    for i, (chunk_id, chunk) in enumerate(pending_records):
        records.append(
            {
                "id": chunk_id,
                "text": chunk["text"],
                "source": chunk["source"],
                "timestamp": chunk.get("timestamp", int(time.time())),
                "embedding": embeddings[i],
                "metadata": json.dumps(
                    {
                        "filename": chunk.get("filename", ""),
                        "chunk_idx": chunk["chunk_idx"],
                        "total_chunks": chunk["total_chunks"],
                    },
                    ensure_ascii=False,
                ),
            }
        )

    try:
        if table_name in db.table_names():
            table = db.open_table(table_name)
            table.add(records)
            print(f"   追加 {len(records)} 条到已有表")
        else:
            db.create_table(table_name, data=records)
            print(f"   创建新表并写入 {len(records)} 条")

        known_ids.update(chunk_id for chunk_id, _ in pending_records)
        save_manifest(manifest_path, known_ids)
        print(f"✅ 完成: {len(records)} 条新增向量已写入")
    except Exception as e:
        print(f"❌ 写入 LanceDB 失败: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
