#!/bin/bash

LOG_FILE="/var/log/app_access.log"
MAX_SIZE=10485760   # 10MB

# 1) Rotação de logs
if [ -f "$LOG_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$LOG_FILE")
    if (( FILE_SIZE > MAX_SIZE )); then
        mv "$LOG_FILE" "$LOG_FILE.$(date +%s).gz"
        touch "$LOG_FILE"
        echo "$(date) - Log rotacionado" >> /var/log/selfheal.log
    fi
fi

# 2) Teste de saúde da aplicação
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000)

if [ "$STATUS_CODE" != "200" ]; then
    echo "$(date) - Aplicação não responde, reiniciando container" >> /var/log/selfheal.log
    docker restart phoenix-app
fi
