FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 AB_ENVIRONMENT=production
WORKDIR /app
COPY requirements-lock.txt ./
RUN pip install --no-cache-dir -r requirements-lock.txt && useradd --uid 10001 --create-home beacon
COPY app ./app
COPY migrations ./migrations
COPY alembic.ini ./
USER beacon
EXPOSE 8000
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-proxy-headers"]
