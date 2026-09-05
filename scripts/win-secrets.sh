#!/bin/bash
# Wrapper para Windows: o Git Bash reinicializa o PATH pelo /etc/profile e perde
# o diretório do AWS CLI. Este script o injeta antes de chamar set-github-secrets.sh.
# Uso (no cmd ou PowerShell):  bash scripts/win-secrets.sh
export PATH="/c/Program Files/Amazon/AWSCLIV2:$PATH"
export GITHUB_REPO="${GITHUB_REPO:-Maic2018/tech_challenge_3}"
echo ">>> aws:  $(command -v aws || echo 'NAO ENCONTRADO')"
echo ">>> gh:   $(command -v gh || echo 'NAO ENCONTRADO')"
exec bash "$(dirname "${BASH_SOURCE[0]}")/set-github-secrets.sh"
