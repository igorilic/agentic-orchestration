#!/usr/bin/env bash
# push-to-github.sh — Initialize git repo and push to GitHub
# Run this AFTER downloading the tdd-workflow installer into this directory
#
# Usage:
#   1. Download tdd-workflow-installer from the Claude chat
#   2. Move it to this directory: mv ~/Downloads/tdd-workflow-installer ./tdd-workflow
#   3. Run: bash push-to-github.sh
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_NAME="agentic-orchestration"

cd "$REPO_DIR"

# ── Verify the installer is present ────────────────────────────────
if [ ! -f "tdd-workflow" ]; then
  echo "⚠️  tdd-workflow installer not found in this directory."
  echo ""
  echo "Download it from the Claude chat, then:"
  echo "  mv ~/Downloads/tdd-workflow-installer ./tdd-workflow"
  echo "  chmod +x tdd-workflow"
  echo "  bash push-to-github.sh"
  exit 1
fi

chmod +x tdd-workflow
chmod +x hooks/*.sh 2>/dev/null || true

echo "🚀 Pushing agentic-orchestration to GitHub..."
echo ""

# ── Verify gh CLI is authenticated ─────────────────────────────────
if ! gh auth status &>/dev/null; then
  echo "❌ gh CLI not authenticated. Run: gh auth login"
  exit 1
fi

GH_USER=$(gh api user --jq '.login' 2>/dev/null)
echo "  GitHub user: $GH_USER"
echo ""

# ── Initialize git ─────────────────────────────────────────────────
if [ ! -d ".git" ]; then
  git init
fi

git add -A

git commit -m "feat: initial release — multi-agent TDD pipeline v2.1.0

5 agents: architect (Opus), tdd-developer (Sonnet), qa (Haiku), reviewer (Sonnet), troubleshooter (Opus)
8 skills: plan, tdd, ticket, skip-tdd, session-report, adr, pr, clusters
2 hooks: session-start (context loader), tdd-gate (commit blocker)
CLI installer with polyglot stack detection (.NET, Go, Rust, Python, React, Swift)
Cross-tool support: Claude Code + GitHub Copilot CLI
Multi-cluster troubleshooting: EMEA / APAC / NAM via ArgoCD + Azure App Insights
Scientific paper: PAPER.md"

# ── Create GitHub repo and push ────────────────────────────────────
if gh repo view "$GH_USER/$REPO_NAME" &>/dev/null; then
  echo "  Repo already exists, setting remote..."
  git remote remove origin 2>/dev/null || true
  git remote add origin "git@github.com:$GH_USER/$REPO_NAME.git"
  git branch -M main
  git push -u origin main --force
else
  gh repo create "$REPO_NAME" \
    --public \
    --description "Multi-agent TDD pipeline for Claude Code and GitHub Copilot CLI — architect, tdd-developer, qa, reviewer, troubleshooter" \
    --source . \
    --remote origin \
    --push
fi

echo ""
echo "✅ Done!"
echo ""
echo "   Repo: https://github.com/$GH_USER/$REPO_NAME"
echo ""
echo "   Next steps:"
echo "   1. Edit skills/clusters/SKILL.md with your actual cluster details"
echo "   2. Install globally: ./tdd-workflow install global"
echo "   3. Install per project: cd ~/code/my-project && tdd-workflow install project ."
