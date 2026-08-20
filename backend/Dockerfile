FROM python:3.14-slim

WORKDIR /app

# 仅后端：依赖优先缓存
COPY pyproject.toml ./
RUN pip install --no-cache-dir --upgrade pip && pip install --no-cache-dir .

COPY app ./app

EXPOSE 8000

# 容器通过环境变量注入 DATABASE_URL / SECRET_KEY / LLM_*，不依赖 .env 文件
CMD ["fastapi", "run", "--host", "0.0.0.0", "--port", "8000"]
