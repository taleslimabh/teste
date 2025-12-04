FROM python:3.11-slim


ENV PYTHONUNBUFFERED=1


WORKDIR /app


RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .


RUN mkdir -p /var/log && \
    touch /var/log/app_access.log && \
    chmod 666 /var/log/app_access.log


RUN useradd -ms /bin/bash appuser
USER appuser

EXPOSE 5000

CMD ["python", "app.py"]
