Parte 1: Avaliação Teórica (Cenários)
No seu repositório, crie um arquivo chamado RESPOSTAS.md. Responda às 12 perguntas abaixo de forma sucinta. Foque no "porquê" das suas escolhas.

1) Cenário de Escala: Uma aplicação de e-commerce está sofrendo com lentidão na leitura do catálogo de produtos (PostgreSQL), mas a escrita (pedidos) é moderada. Qual estratégia você adotaria primeiro: Sharding ou Read Replicas? Justifique sua escolha considerando complexidade e custo.

Eu adotaria Read Replicas primeiro. Porque read replicas é de menor complexidade pois exigem praticamente zero mudança na lógica da aplicação, basta direcionar as consultas de leituras para réplicas, além do custo ser mais baixo pois são escaláveis horizontalmente de forma simples e você paga por instâncias adicionais.


2) Consistência: Você precisa armazenar dados de sessão de usuário (carrinho de compras temporário) que precisam de altíssima velocidade de escrita/leitura e expiram em 30 minutos. Você escolheria um banco SQL (ex: MySQL) ou NoSQL (ex: Redis/DynamoDB)? Por quê? Explique o conceito de CAP Theorem aplicado à sua escolha.

Eu escolheria o NoSQL (Redis). Porque a velocidade é bem maior que um banco relacional, ele trabalha em memória oferece latências de microssegundos, é melhor para sessões e carrinhos temporários. O cap theorem diz que um sistema distribuído pode otimizar apenas dois dos três: c - consistência, a - disponibilidade, p - tolerância a partição e o redis prioriza alta disponibilidade e tolência a partições que são essenciais para uma aplicação web de e-commerce. 

3) Métrica vs Log: O uso de CPU de um servidor subiu para 95%, mas a aplicação continua respondendo 200 OK. O time de desenvolvimento diz que não mudou nada. Que tipo de dado (Métrica, Log ou Trace) seria mais útil para diagnosticar a causa raiz imediata desse comportamento (ex: um loop infinito ou Garbage Collection) e por quê?

Logs. Porque métricas(exemplo cpu = 95%) mostram o que está acontecendo, mas não o porque. Logs já revelam eventos internos da aplicação como: loops inesperados, erros silenciosos, threads travadas entre outros detalhes que não aparecem em métricas. 


4) Alertas: Em um plantão anterior, você recebeu 500 emails de alerta durante a noite informando que a "Latência estava alta", mas o sistema se recuperou sozinho em segundos. Isso gerou fadiga de alerta. Como você reestruturaria essa política de alertas usando conceitos de SRE (SLO/SLA/Error Budget)?

Eu reorganizaria os alertas para serem orientados a SLO, não a métricas isoladas, para alertar só quando há risco real de violar o SLO, e não quando a latência sobe por alguns segundos.


5) Autenticação Unificada: A empresa possui um Active Directory (AD) Windows on-premise e está subindo 50 servidores Linux na nuvem. O time de segurança exige que o login nos Linux seja feito com as mesmas credenciais do AD. Quais ferramentas ou protocolos você utilizaria para integrar o Linux ao AD (ex: SSSD, LDAP, Kerberos)?

Eu integraria os servidores Linux ao AD usando SSSD + Kerberos + LDAP (AD), porque SSSD é o padrão moderno para autenticação centralizada no linux e trabalha nativamente com o AD e suporta o kerberos. Kerberos(para autenticação real) o ad usa kerberos como protocolo principal de autenticação e garante login seguro e o LDAP para consulta de atributos do usuário. Isso garante conformidade com segurança, unifica credenciais e é a forma mais simples e robusta de conectar Linux ao AD.

6) Automação Cross-Platform: Precisamos de um script que verifique espaço em disco e status de serviços tanto em servidores Windows Server quanto em Ubuntu. Qual linguagem ou ferramenta de configuração você escolheria para manter uma base de código única (ou o mais unificada possível) para gerir ambos?

Em vez de script eu utilizaria a ferramenta Zabbix pois é altamente superior a scripts personalizados mas scripts para esses tipos de monitoramento a melhor linguaguem seria o powershell core para unificar o código entre windows e linux.

7) Otimização de Imagem: Um desenvolvedor entregou uma imagem Docker de 2GB para uma aplicação Node.js simples. Isso está deixando o deploy lento. Cite 3 técnicas que você aplicaria no Dockerfile para reduzir drasticamente esse tamanho (ex: Multi-stage build).

Multi-stage Build porque separa o ambiente de build(cheio de dependencias, compilers, etc) do ambiente final, que fica muito menor. Usar imagens base minimalistas(Alpine,Slim ou distroless) porque imagens como alpine ou distroless reduzem centenas de MB removendo ferramentas, libs e camadas desnecessárias. Outra técnica seria o .dockerignore bem configurado porque ele evita enviar para dentro da build arquivos inúteis o que reduz o contexto de build, o tamanho final e acelera o processo.

8) Troubleshooting Kubernetes: Um Pod está em status CrashLoopBackOff. O comando kubectl logs não retorna nada útil porque o container morre antes de escrever no stdout. Que outros comandos ou estratégias você usaria para descobrir por que o container não está subindo?

Se o container morre antes de gerar logs, uso comandos que inspecionam eventos, spec, imagem, e status internos do Pod, uso describe, logs --previous, kubectl debug, análise de probes, validação de ENTRYPOINT e checagem de OOM para descobrir por que o container sequer chega a rodar.

9) Segurança de Rede: Qual a diferença prática entre um Security Group e uma Network ACL (NACL) na AWS? Em qual cenário você precisaria bloquear explicitamente um IP malicioso?

Security group se você permite entrada, a saída automaticamente é permitida, são regras mais simples e seguras (somente "allow") já a Network ACL precisa criar regras de entrada e saída, é aplicado no nível da subnet e suporta "allow" e "deny". Em um cenário que um ip misterioso estiver atacando com scan uma porta por exemplo eu bloqueria via NACL pois permite bloquear IPS e também porque no Security Group não tem regra de deny.

10) Gerenciamento de Custos: Um ambiente de desenvolvimento fica ligado 24/7, mas os devs só trabalham das 9h às 18h. Além de desligar as máquinas (schedule), que modelo de compra de instâncias (On-Demand, Savings Plan, Spot) você recomendaria para os ambientes de Produção vs. Desenvolvimento/CI para otimizar custos?

Para produção recomendaria Savings Plan porque é estável, previsível e exige alta disponibilidade que é o melhor custo/benefício sem risco, para o ambiente de desenvolvimento recomendaria o Spot porque são ambientes não críticos que podem ser interrompidos sem afetar o negócio e maximiza a economia.

11) Storage: Diferencie Block Storage (EBS) de Object Storage (S3). Se sua aplicação precisa processar uploads de fotos de usuários e depois servir essas fotos em um site estático, qual você usaria e por quê?

EBS funciona como um disco ligado a uma EC2, tem baixa latência, leitura/escrita como filesystem e não é compartilhado entre múltiplas máquinas, ideal para banco de dados, sistemas de arquivos, etc. Já S3 armazena os arquivos via API/HTTP, é altamente escalável, barato e durável, também pode servidor conteúdo diretamente ao usuário, logo para fazer upload servir essas fotos em um site estático o ideal é o S3 porque fotos são arquivos estáticos, precisam ser servidas globalmente, com baixo custo e alta escalabilidade.

12) IaC State: Por que é considerado uma má prática manter o arquivo de estado do Terraform (terraform.tfstate) na máquina local do engenheiro? Como você resolveria isso em um time de 5 pessoas?

É uma má prática porque existem risco de corrupção e conflito, falta de confiabilidade(se notebook quebrar, formatar ou perder o arquivo você perde o histórico do ambiente inteiro) e sem falta de "lock" duas pessoas podem rodar o terraform apply ao mesmo tempo causando corrupção de estado. Para resolver em um time de 5 pessoas usaria o terraform remote state + locking ou terraform cloud.


