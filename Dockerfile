FROM python:3.11-slim

COPY --from=ghcr.io/astral-sh/uv:0.11.32 /uv /usr/local/bin/uv

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_PYTHON_DOWNLOADS=never \
    PATH="/app/.venv/bin:$PATH"

COPY pyproject.toml uv.lock README.md ./
RUN uv sync --frozen --no-dev --no-cache

COPY main.py database.py storage.py schemas.py errors.py dashboard.py dashboard.html worker.py ./

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
