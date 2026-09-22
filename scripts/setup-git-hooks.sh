#!/usr/bin/env bash
# Ставит хуки из scripts/git-hooks/ в .git/hooks/ (симлинками).
# Запускать после клонирования репозитория: bash scripts/setup-git-hooks.sh
set -euo pipefail
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"
for h in scripts/git-hooks/*; do
    name=$(basename "$h")
    chmod +x "$h"
    ln -sf "../../scripts/git-hooks/$name" ".git/hooks/$name"
    echo "  → .git/hooks/$name"
done
echo "✓ хуки установлены"
command -v gitleaks >/dev/null 2>&1 || echo "⚠️  gitleaks не найден — установите его, иначе проверка секретов работать не будет"
