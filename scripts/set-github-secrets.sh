#!/bin/bash
# Publica as credenciais AWS atuais como Secrets do repositório GitHub, para o
# pipeline conseguir logar no ECR. Rode sempre que rotacionar as chaves do IAM
# user usado pelo CI.
# Uso: bash scripts/set-github-secrets.sh        [GITHUB_REPO=owner/repo para forçar]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_cmd aws gh
cd "$REPO_ROOT"
gh auth status >/dev/null 2>&1 || die "Faça login no GitHub primeiro: gh auth login"

REPO="${GITHUB_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
log "Repositório: $REPO"

# Credenciais efetivas do perfil atual
eval "$(aws configure export-credentials --format env)"
[ -n "${AWS_ACCESS_KEY_ID:-}" ] || die "Credenciais AWS não encontradas (configure ~/.aws/credentials)"

# O valor vai pelo stdin, não por --body: no Git Bash (MSYS) um argumento que
# começa com "/" (comum em secret keys) é convertido em caminho do Windows antes
# de chegar ao gh.exe, e o GitHub recebe a chave corrompida. O CR do aws.exe
# no Windows também é removido.
set_secret() { printf '%s' "${2%$'\r'}" | gh secret set "$1" --repo "$REPO"; }

set_secret AWS_ACCESS_KEY_ID     "$AWS_ACCESS_KEY_ID"
set_secret AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"
log "Secrets AWS_* atualizados em $REPO."
log "Opcional: 'gh secret set GITOPS_TOKEN' (PAT) se a branch main for protegida."
