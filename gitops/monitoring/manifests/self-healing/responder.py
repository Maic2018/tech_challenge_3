"""Self-healing do ToggleMaster (Runbook Automation).

Recebe o webhook do Grafana (contact point "oncall-critico") e executa a ação corretiva
indicada pelo label `remediation` da regra de alerta:

    remediation=rollout-restart  ->  kubectl rollout restart deployment/<label service>

O restart é feito pela API do Kubernetes (mesmo patch que o kubectl aplica), com a
ServiceAccount "self-healing", que só pode ler/alterar Deployments do namespace da
aplicação. Depois acompanha o rollout até os pods novos ficarem prontos e avisa no
Discord. Só usa a biblioteca padrão do Python: roda na imagem oficial, sem build.
"""
import datetime
import hmac
import json
import logging
import os
import ssl
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SA_DIR = os.environ.get("SA_DIR", "/var/run/secrets/kubernetes.io/serviceaccount")
KUBE_API = os.environ.get("KUBE_API_URL", "https://kubernetes.default.svc")
WEBHOOK_TOKEN = os.environ["WEBHOOK_TOKEN"]
NAMESPACE = os.environ.get("TARGET_NAMESPACE", "togglemaster")
ALLOWED = {d.strip() for d in os.environ.get("ALLOWED_DEPLOYMENTS", "").split(",") if d.strip()}
COOLDOWN_SECONDS = int(os.environ.get("COOLDOWN_SECONDS", "300"))
ROLLOUT_TIMEOUT_SECONDS = int(os.environ.get("ROLLOUT_TIMEOUT_SECONDS", "300"))
DISCORD_WEBHOOK_URL = os.environ.get("DISCORD_WEBHOOK_URL", "")
PORT = int(os.environ.get("PORT", "8080"))
MAX_BODY = 1024 * 1024
# Alertas sintéticos do Grafana (falha de consulta) nunca disparam ação
IGNORED_ALERTS = {"DatasourceError", "DatasourceNoData"}

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [self-healing] %(message)s")
log = logging.getLogger("self-healing")

_last_action = {}
_lock = threading.Lock()


def kube(method, path, body=None, content_type="application/json"):
    """Chamada autenticada à API do Kubernetes com o token da ServiceAccount."""
    with open(os.path.join(SA_DIR, "token"), encoding="utf-8") as f:
        token = f.read().strip()
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(KUBE_API + path, data=data, method=method, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": content_type,
        "Accept": "application/json",
    })
    context = None
    if KUBE_API.startswith("https://"):
        context = ssl.create_default_context(cafile=os.path.join(SA_DIR, "ca.crt"))
    with urllib.request.urlopen(req, timeout=10, context=context) as resp:  # nosec B310 - URL fixa da API
        return json.loads(resp.read())


def notify_discord(message):
    if not DISCORD_WEBHOOK_URL.startswith("https://discord.com/api/webhooks/") or "nao-configurado" in DISCORD_WEBHOOK_URL:
        return
    req = urllib.request.Request(DISCORD_WEBHOOK_URL, method="POST",
                                 data=json.dumps({"content": message[:1900], "username": "ToggleMaster Self-Healing"}).encode(),
                                 headers={"Content-Type": "application/json", "User-Agent": "togglemaster-self-healing/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10):  # nosec B310 - URL validada acima
            pass
    except (urllib.error.URLError, OSError) as e:
        log.warning("Falha ao notificar o Discord: %s", e)


def rollout_restart(deployment, alertname):
    """Equivalente a `kubectl rollout restart`: muda uma annotation do template do pod."""
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    patch = {"spec": {"template": {"metadata": {"annotations": {
        "kubectl.kubernetes.io/restartedAt": now,
        "togglemaster.io/restarted-by": "self-healing",
        "togglemaster.io/restart-reason": alertname[:200],
    }}}}}
    dep = kube("PATCH", f"/apis/apps/v1/namespaces/{NAMESPACE}/deployments/{deployment}",
               patch, "application/strategic-merge-patch+json")
    return dep["metadata"]["generation"]


def watch_rollout(deployment, generation, alertname, started):
    """Acompanha o rollout até todas as réplicas novas estarem disponíveis."""
    path = f"/apis/apps/v1/namespaces/{NAMESPACE}/deployments/{deployment}"
    while time.time() - started < ROLLOUT_TIMEOUT_SECONDS:
        time.sleep(5)
        try:
            dep = kube("GET", path)
        except (urllib.error.URLError, OSError) as e:
            log.warning("Erro ao consultar o rollout de %s: %s", deployment, e)
            continue
        status, desired = dep.get("status", {}), dep["spec"].get("replicas", 1)
        log.info("rollout deployment/%s: atualizadas=%s disponíveis=%s desejadas=%s",
                 deployment, status.get("updatedReplicas", 0), status.get("availableReplicas", 0), desired)
        if (status.get("observedGeneration", 0) >= generation
                and status.get("updatedReplicas", 0) == desired
                and status.get("availableReplicas", 0) == desired
                and not status.get("unavailableReplicas")):
            elapsed = int(time.time() - started)
            log.info("RESOLVIDO: deployment/%s com %s réplica(s) nova(s) em %ss", deployment, desired, elapsed)
            notify_discord(f"✅ **Self-healing concluído**: `deployment/{deployment}` reiniciado e saudável "
                           f"({desired} réplica(s), {elapsed}s). Alerta: {alertname}")
            return
    log.error("Timeout: rollout de deployment/%s não terminou em %ss", deployment, ROLLOUT_TIMEOUT_SECONDS)
    notify_discord(f"⚠️ Self-healing: rollout de `deployment/{deployment}` não terminou em "
                   f"{ROLLOUT_TIMEOUT_SECONDS}s. Intervenção humana necessária.")


def handle_alert(alert):
    labels = alert.get("labels", {})
    alertname = labels.get("alertname", "?")
    target = labels.get("service") or labels.get("service_name")

    if alert.get("status") != "firing":
        log.info("Alerta '%s' resolvido (service=%s). Nenhuma ação.", alertname, target)
        return {"alert": alertname, "action": "none", "reason": "resolved"}
    if alertname in IGNORED_ALERTS or labels.get("remediation") != "rollout-restart":
        return {"alert": alertname, "action": "none", "reason": "sem remediação automática"}
    if target not in ALLOWED:
        log.warning("Alerta '%s' pede restart de '%s', que não está na allowlist %s", alertname, target, sorted(ALLOWED))
        return {"alert": alertname, "action": "none", "reason": f"deployment '{target}' fora da allowlist"}

    with _lock:
        last = _last_action.get(target, 0)
        if time.time() - last < COOLDOWN_SECONDS:
            restante = int(COOLDOWN_SECONDS - (time.time() - last))
            log.info("Alerta '%s': deployment/%s reiniciado há pouco, cooldown de mais %ss", alertname, target, restante)
            return {"alert": alertname, "deployment": target, "action": "none", "reason": "cooldown"}
        _last_action[target] = time.time()

    log.info("ALERTA FIRING '%s' (valor: %s) -> executando: kubectl rollout restart deployment/%s -n %s",
             alertname, alert.get("valueString", "-"), target, NAMESPACE)
    started = time.time()
    try:
        generation = rollout_restart(target, alertname)
    except (urllib.error.URLError, OSError, KeyError) as e:
        log.error("Falha no rollout restart de deployment/%s: %s", target, e)
        with _lock:
            _last_action.pop(target, None)
        return {"alert": alertname, "deployment": target, "action": "rollout-restart", "result": f"erro: {e}"}

    log.info("AÇÃO EXECUTADA: deployment/%s reiniciado (generation %s). Acompanhando o rollout...", target, generation)
    notify_discord(f"🤖 **Self-healing acionado** pelo alerta *{alertname}*: executando "
                   f"`kubectl rollout restart deployment/{target} -n {NAMESPACE}`")
    threading.Thread(target=watch_rollout, args=(target, generation, alertname, started), daemon=True).start()
    return {"alert": alertname, "deployment": target, "action": "rollout-restart", "result": "ok"}


class Handler(BaseHTTPRequestHandler):
    def _reply(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            self._reply(200, {"status": "ok"})
        else:
            self._reply(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/hooks/alert":
            self._reply(404, {"error": "not found"})
            return
        if not hmac.compare_digest(self.headers.get("Authorization", ""), f"Bearer {WEBHOOK_TOKEN}"):
            log.warning("Webhook recusado: token inválido (origem %s)", self.client_address[0])
            self._reply(401, {"error": "unauthorized"})
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            self._reply(400, {"error": "corpo ausente ou grande demais"})
            return
        try:
            payload = json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            self._reply(400, {"error": "JSON inválido"})
            return
        alerts = payload.get("alerts", [])
        log.info("Webhook recebido de %s: status=%s, %d alerta(s)", payload.get("receiver", "?"),
                 payload.get("status", "?"), len(alerts))
        self._reply(200, {"actions": [handle_alert(a) for a in alerts]})

    def log_message(self, format, *args):
        pass  # sem access log (as probes /healthz poluiriam o Loki)


if __name__ == "__main__":
    log.info("Escutando na porta %s. Namespace alvo: %s. Allowlist: %s. Cooldown: %ss",
             PORT, NAMESPACE, ",".join(sorted(ALLOWED)), COOLDOWN_SECONDS)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()  # nosec B104 - escuta dentro do pod
