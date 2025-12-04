# DECISION LOG #

O problema estava no código da aplicação que era iniciada no localhost (127.0.0.1) que faz a aplicação escutar apenas no loopback do processo. Preferi resolver alterando o código para 0.0.0.0 mas seria também possível executar o app com um WSGI(gunicorn) que faz um bind em 0.0.0.0 sem precisar alterar o código.
Melhorias de segurança que poderia ser feita seria colocar security group restritos ao invés do 0.0.0.0/0 por cidr específico dos devops para acesso ssh, utilizar também usuário não root no container para evitar qualquer tipo de impacto caso algo seja explorado e também poderia utilizar IAM ROLE para a EC2.

Como lidei com o desafio?
O erro na aplicação foi fácil de identificar (127.0.0.1) pois é algo geralmente comum. 
Criei Dockerfile multi-stage/leve e instalei apenas o necessário.
No terraform modelei EC2 t3a.micro com root_block_device.volume_size = 8GB para respeitar a política do exercício
Criei Security Group com portas mínimas (SSH e porta da aplicação)
Implementei logrotate com size 10M, copytruncate para /var/log/app_access.log
Coloquei também script de healthcheck que verifica http://127.0.0.1:5000 e reinicia o systemd/service se necessário
Fiz testes local com Docker (build + run).
Coloquei os arquivos Dockerfile, scripts (selfheal, user_data) e o Terraform (main.tf, variables.tf, ec2.tf) no github
