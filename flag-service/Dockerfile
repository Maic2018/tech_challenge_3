# Multi-stage: instala dependências num estágio e copia só o necessário para a
# imagem final (slim, usuário não-root com UID fixo, sem arquivos de dev).
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1     PYTHONUNBUFFERED=1
WORKDIR /app
COPY --from=builder /install /usr/local
COPY app.py ./
RUN useradd --create-home --uid 10001 appuser
USER 10001
EXPOSE 8002
CMD ["gunicorn", "--bind", "0.0.0.0:8002", "--workers", "2", "app:app"]
