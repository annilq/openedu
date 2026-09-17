FROM python:3.14-slim

WORKDIR /app

# 仅后端：依赖优先缓存
COPY pyproject.toml ./
RUN pip install --no-cache-dir --upgrade pip && pip install --no-cache-dir .

COPY app ./app

# 打印导出的中文字体（静态 Regular，由 scripts/build_export_font.py 生成，
# ADR-0052）。容器里没有任何系统中文字体，不带上就是满页豆腐块。
COPY assets ./assets

EXPOSE 8000

# 容器通过环境变量注入 DATABASE_URL / SECRET_KEY / LLM_*，不依赖 .env 文件
CMD ["fastapi", "run", "--host", "0.0.0.0", "--port", "8000"]
