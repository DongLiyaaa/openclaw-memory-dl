# GitHub 上传指南 — OpenClaw Memory DL

> 本文档是给**执行上传的 Agent** 看的。按步骤走，不要跳。

---

## 前置条件

1. 已有 GitHub 账号且已配置 SSH 或 PAT（Personal Access Token）
2. 目标仓库已创建（空的或已有 .gitignore）
3. 本地项目路径：`projects/openclaw-memory-dl/`

---

## 上传步骤

### Step 1: 确认项目目录结构

进入项目根目录：

```bash
cd projects/openclaw-memory-dl
```

确认以下文件存在：

```
├── .env.example
├── .gitignore
├── README.md
├── package.json
├── requirements.txt
├── docker-compose.yml
├── config/
│   ├── rag-config.json
│   └── openclaw-memory.json
├── scripts/
│   ├── setup.sh
│   ├── health-check.sh
│   ├── backup.sh
│   ├── restore.sh
│   ├── vectorize.js
│   ├── embed_chunks.py
│   ├── rag_search.py
│   └── init-mysql.sql
└── docs/
    ├── architecture.md
    ├── config-reference.md
    ├── deployment.md
    └── memory-lifecycle.md
```

### Step 2: 确认 `.gitignore` 正确

必须确保**以下文件/目录不会上传**：

```
.env                    ← 包含密码，绝对不能提交
memory/*                ← 用户记忆数据，隐私
semantic_index/*        ← 向量库数据，体积大且隐私
backups/*               ← 备份文件
__pycache__/
node_modules/
.DS_Store
```

检查方法：

```bash
git status
```

输出中**不应该出现** `.env`、`memory/` 下的 `.md` 文件、`semantic_index/` 下的内容。

### Step 3: 初始化 Git 仓库（如果是首次上传）

```bash
cd projects/openclaw-memory-dl

# 如果已有 .git 目录，跳过
if [ ! -d ".git" ]; then
    git init
    git add -A
    git commit -m "feat: initial commit - OpenClaw Memory DL (stable)"
fi
```

### Step 4: 添加远程仓库

```bash
# 替换为你的实际仓库地址
git remote add origin git@github.com:<你的用户名>/openclaw-memory-dl.git

# 如果 remote 已存在，先删除旧的
git remote remove origin
git remote add origin git@github.com:<你的用户名>/openclaw-memory-dl.git
```

**HTTPS 方式**（无 SSH key 时）：

```bash
git remote add origin https://github.com/<你的用户名>/openclaw-memory-dl.git
```

### Step 5: 推送

```bash
# 推送到 main 分支
git branch -M main
git push -u origin main

# 如果远端已有内容需要合并
git push -u origin main --force-with-lease
```

---

## ⚠️ 关键注意事项（必读）

### ❌ 绝对不能上传的

| 文件/目录 | 原因 |
|-----------|------|
| `.env` | **包含真实密码**（MySQL、Memos Token），绝对不能提交 |
| `memory/` | 用户的私人记忆数据，含业务信息 |
| `semantic_index/` | 向量库数据，体积大（GB 级）且包含隐私 |
| `backups/` | 备份文件，含全量数据 |
| `__pycache__/` | Python 编译缓存，不应提交 |
| `.vectorize_temp.json` | 临时文件 |

### ✅ 必须包含的

| 文件/目录 | 原因 |
|-----------|------|
| `.env.example` | 环境变量模板（占位符密码） |
| `.gitignore` | 排除规则 |
| `memory/.gitkeep` | 空目录占位 |
| `semantic_index/.gitkeep` | 空目录占位 |
| 所有 `.sh` `.py` `.js` `.json` `.yml` `.sql` `.md` 文件 | 项目源码和文档 |

### 安全相关

1. **密码**：`.env.example` 中的密码必须是占位符（如 `your_password_here`），不能是真实密码
2. **Token**：Memos Token、API Key 等不能出现在任何提交的文件中
3. **检查历史**：如果不小心提交了敏感文件，需要 `git filter-branch` 或 BFG 清理历史，不能只是删除

### 验证清单（推送前检查）

```bash
# 1. 检查是否有不该提交的文件
git ls-files | grep -E "(\.env$|memory/|semantic_index/|backups/)" && echo "❌ 发现不应提交的文件" || echo "✅ 无敏感文件"

# 2. 检查 .env.example 是否有真实密码
grep -E "password|token|secret|key" .env.example | grep -v "#" | grep -v "your_" && echo "❌ .env.example 可能包含真实密码" || echo "✅ .env.example 安全"

# 3. 确认总文件数（应在 20 个左右）
echo "文件数: $(git ls-files | wc -l)"
```

---

## 常见问题

### Q: GitHub 仓库名必须叫 `openclaw-memory-dl` 吗？
A: 不是。可以叫任何名字，但建议保持一致方便查找。

### Q: 需要初始化 issue/label/release 吗？
A: 不需要。核心是上传代码，其他按需设置。

### Q: 如果推送被拒绝怎么办？
A: 常见原因：
- 远端有本地没有的提交 → `git pull --rebase origin main` 再推
- 没有权限 → 检查 SSH key 或 PAT 是否正确
- 文件太大 → 检查是否误传了向量库数据

### Q: `.gitignore` 不生效怎么办？
A: 如果文件之前已经被跟踪，`.gitignore` 不生效。需要先取消跟踪：

```bash
git rm -r --cached memory/
git rm -r --cached semantic_index/
git rm --cached .env
git commit -m "chore: stop tracking sensitive files"
```
