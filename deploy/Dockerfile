FROM python:3.12-slim AS build
WORKDIR /workspace
COPY backend/requirements-lock.txt ./requirements-lock.txt
RUN pip install --no-cache-dir --prefix=/install -r requirements-lock.txt
COPY deploy/build_dashboard.py ./deploy/build_dashboard.py
COPY dashboard/src ./dashboard/src
COPY dashboard/public/beacon-logo.png ./dashboard/public/beacon-logo.png
RUN python deploy/build_dashboard.py

FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 AB_ENVIRONMENT=production AB_DASHBOARD_DEV_AUTH=false
RUN useradd --uid 10001 --create-home beacon
COPY --from=build /install /usr/local
WORKDIR /app/backend
COPY backend/app ./app
COPY backend/migrations ./migrations
COPY backend/alembic.ini ./alembic.ini
COPY --from=build /workspace/dashboard/dist /app/dashboard/dist
USER beacon
EXPOSE 8080
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log", "--no-proxy-headers"]
