#!/usr/bin/env node
// ═══════════════════════════════════════════
// 向量化: Markdown 记忆 → LanceDB (Stable)
// ═══════════════════════════════════════════

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const PROJECT_ROOT = path.resolve(__dirname, "..");
const CONFIG_PATH = path.join(PROJECT_ROOT, "config", "rag-config.json");

// ─── 参数解析 ───
const args = process.argv.slice(2);
const today = new Date().toISOString().split("T")[0];

let targetFiles = [];
let todayOnly = args.includes("--today") || args.includes("-t");

if (args.includes("--help") || args.includes("-h")) {
  console.log(`用法: node vectorize.js [选项] [文件...]

选项:
  --today, -t    仅向量化今日新增/修改文件
  --help, -h     显示帮助

示例:
  node vectorize.js --today
  node vectorize.js memory/2026-04-26.md
`);
  process.exit(0);
}

// ─── 配置 ───
function loadConfig() {
  try {
    return JSON.parse(fs.readFileSync(CONFIG_PATH, "utf-8"));
  } catch {
    return {
      lancedb_path: path.join(PROJECT_ROOT, "semantic_index"),
      table_name: "openclaw_memory",
      chunk_size: 500,
      overlap: 50,
    };
  }
}
const config = loadConfig();

// ─── 确定文件列表 ───
function findTodayFiles() {
  const memoryDir = path.join(PROJECT_ROOT, "memory");
  if (!fs.existsSync(memoryDir)) return [];

  const todayFile = path.join(memoryDir, `${today}.md`);
  if (fs.existsSync(todayFile)) return [todayFile];

  // 找 24h 内修改的文件
  const now = Date.now();
  const dayMs = 86400000;
  const files = fs.readdirSync(memoryDir).filter((f) => f.endsWith(".md"));
  return files
    .map((f) => path.join(memoryDir, f))
    .filter((f) => {
      try {
        return now - fs.statSync(f).mtimeMs < dayMs;
      } catch {
        return false;
      }
    });
}

function findAllFiles() {
  const result = [];
  const memoryMd = path.join(PROJECT_ROOT, "MEMORY.md");
  if (fs.existsSync(memoryMd)) result.push(memoryMd);

  const memoryDir = path.join(PROJECT_ROOT, "memory");
  if (fs.existsSync(memoryDir)) {
    fs.readdirSync(memoryDir)
      .filter((f) => f.endsWith(".md"))
      .forEach((f) => result.push(path.join(memoryDir, f)));
  }
  return result;
}

if (args.filter((a) => !a.startsWith("-")).length > 0) {
  // 用户指定了文件
  targetFiles = args
    .filter((a) => !a.startsWith("-"))
    .map((f) => path.resolve(PROJECT_ROOT, f))
    .filter((f) => fs.existsSync(f));
} else if (todayOnly) {
  targetFiles = findTodayFiles();
} else {
  targetFiles = findAllFiles();
}

console.log(`📄 待向量化文件: ${targetFiles.length} 个`);
if (targetFiles.length === 0) {
  console.log("无文件需要向量化");
  process.exit(0);
}

// ─── 文本分块 ───
function chunkText(text, size = config.chunk_size || 500, overlap = config.overlap || 50) {
  if (text.length <= size) return [text];
  const chunks = [];
  let i = 0;
  while (i < text.length) {
    chunks.push(text.slice(i, i + size));
    i += size - overlap;
  }
  return chunks;
}

// ─── 提取内容 ───
const allChunks = [];

for (const filePath of targetFiles) {
  try {
    const content = fs.readFileSync(filePath, "utf-8");
    const relativePath = path.relative(PROJECT_ROOT, filePath);
    const stat = fs.statSync(filePath);
    const chunks = chunkText(content);

    chunks.forEach((chunk, idx) => {
      allChunks.push({
        text: chunk,
        source: relativePath,
        chunk_idx: idx,
        total_chunks: chunks.length,
        timestamp: Math.floor(stat.mtimeMs / 1000),
        filename: path.basename(filePath),
      });
    });

    console.log(`  ✓ ${relativePath} → ${chunks.length} 块`);
  } catch (err) {
    console.warn(`  ✗ ${filePath}: ${err.message}`);
  }
}

if (allChunks.length === 0) {
  console.log("无可向量化内容");
  process.exit(0);
}

console.log(`\n📊 总计: ${allChunks.length} 块`);

// ─── 写入临时文件供 Python 处理 ───
const tempFile = path.join(PROJECT_ROOT, ".vectorize_temp.json");
fs.writeFileSync(tempFile, JSON.stringify({ chunks: allChunks, config }, null, 2));

const embedScript = path.join(__dirname, "embed_chunks.py");

try {
  execSync(`python3 "${embedScript}" "${tempFile}"`, {
    cwd: PROJECT_ROOT,
    stdio: "inherit",
    env: { ...process.env },
  });
  console.log("\n✅ 向量化完成");
} catch (err) {
  console.error(`\n❌ 向量化失败: ${err.message}`);
  process.exit(1);
} finally {
  try {
    fs.unlinkSync(tempFile);
  } catch {
    /* ignore */
  }
}
