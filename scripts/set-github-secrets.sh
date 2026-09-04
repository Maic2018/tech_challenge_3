#!/bin/bash
# Publica as credenciais AWS atuais como Secrets do repositório GitHub, para o
# pipeline conseguir logar no ECR. No AWS Academy as credenciais expiram a cada
# sessão do laboratório: rode este script sempre que iniciar o lab.
# (O Academy não permite criar roles OIDC; senão usaríamos role-to-assume.)
# Uso: bash scripts/set-github-secrets.sh        [GITHUB_REPO=owner/repo para forçar]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
require_cmd aws gh
cd "$REPO_ROOT"
gh auth status >/dev/null 2>&1 || die "Faça login no GitHub primeiro: gh auth login"

REPO="${GITHUB_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
log "Repositório: $REPO"

# Credenciais efetivas do perfil atual (inclui o session token do Academy)
eval "$(aws configure export-credentials --format env)"
[ -n "${AWS_ACCESS_KEY_ID:-}" ] || die "Credenciais AWS não encontradas (configure ~/.aws/credentials)"

gh secret set AWS_ACCESS_KEY_ID     --repo "$REPO" --body "$AWS_ACCESS_KEY_ID"
gh secret set AWS_SECRET_ACCESS_KEY --repo "$REPO" --body "$AWS_SECRET_ACCESS_KEY"
if [ -n "${AWS_SESSION_TOKEN:-}" ]; then
  gh secret set AWS_SESSION_TOKEN --repo "$REPO" --body "$AWS_SESSION_TOKEN"
else
  gh secret delete AWS_SESSION_TOKEN --repo "$REPO" >/dev/null 2>&1 || true
fi
log "Secrets AWS_* atualizados em $REPO."
log "Opcional: 'gh secret set GITOPS_TOKEN' (PAT) se a branch main for protegida."
