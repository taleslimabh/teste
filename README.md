# 🧿 SQL Server DBA Runbook 3.0

> **Runbook completo de monitoramento, diagnóstico e manutenção para SQL Server — pronto para usar no SSMS.**

Desenvolvido e refinado na prática, com foco em ambientes de produção. Cada seção explica **quando usar**, **por que importa**, **onde executar** e **o que analisar** nos resultados.

---

## 📋 O que está incluído

34 seções cobrindo todo o ciclo de vida de um DBA:

| # | Seção | Finalidade |
|---|-------|-----------|
| 01 | Diagnóstico geral (sp_Blitz) | Health check completo do servidor |
| 02 | O que está rodando agora (sp_WhoIsActive) | Sessões ativas em tempo real |
| 03 | Top queries agora (nativo) | Queries mais pesadas sem dependência externa |
| 04 | CPU alta — fluxo completo | Diagnóstico passo a passo de CPU 100% |
| 05 | Wait Stats | Identifica gargalos reais do servidor |
| 06 | Blocking e Deadlocks | Detecção e análise de contenção |
| 07 | Sessões e vazamento de pool | Conexões órfãs e pool esgotado |
| 08 | Missing Indexes | Índices faltantes por impacto estimado |
| 09 | Fragmentação e manutenção | Rebuild/reorganize baseado em dados reais |
| 10 | Índices não utilizados | Candidatos a remoção com custo de escrita |
| 11 | Stored Procedures mais pesadas | Ranking por CPU, I/O e duração |
| 12 | Triggers mais pesadas | Triggers com impacto oculto na escrita |
| 13 | Query Store — histórico | Regressões e comparação de planos |
| 14 | Memory Grants | Queries sofrendo spill para TempDB |
| 15 | TempDB — uso e pressão | Contenção de páginas e uso por sessão |
| 16 | Memória e Buffer Pool | PLE, memory grants e pressão de memória |
| 17 | I/O e latência de disco | Arquivos com latência acima do aceitável |
| 18 | Estatísticas desatualizadas | Tabelas com stats obsoletas |
| 19 | Plan Cache | Planos de baixa qualidade e single-use |
| 20 | Backup e Transaction Log | Último backup, VLFs e risco de perda |
| 21 | Health Check — integridade | CHECKDB, corrupção e estado dos bancos |
| 22 | Jobs com falha | Histórico e frequência de falhas no Agent |
| 23 | Configurações críticas | MAXDOP, Cost Threshold, Max Memory etc. |
| 24 | VLFs e crescimento do log | Log fragmentado e crescimento excessivo |
| 25 | Crescimento de arquivos | Autogrowth inadequado por banco/arquivo |
| 26 | Monitoramento contínuo | Infra de coleta e baseline histórico |
| 27 | Manutenção automatizada | Ola Hallengren: schedule e jobs |
| 28 | Validação de índices | Baseline antes/depois de criação de índice |
| 29 | Playbook de incidente | Roteiro: sistema lento / CPU 100% |
| 30 | Estatísticas e cardinalidade | Histogramas, density e estimativas do otimizador |
| 31 | Histórico de crescimento | Tendência de crescimento por banco |
| 32 | Disponibilidade e reinícios | Detecção de restarts inesperados |
| 33 | Consumo de disco por banco | Tamanho de dados, log e uso real |
| 34 | Top regressões no Query Store | Queries que pioraram entre períodos |

---

## ⚙️ Como usar

**Pré-requisitos:**
- SQL Server 2016+ (recomendado para Query Store)
- SSMS ou Azure Data Studio
- Para seções 01 e 02: instalar [sp_Blitz](https://www.brentozar.com/blitz/) e [sp_WhoIsActive](http://whoisactive.com/) *(gratuitos)*

**Execução:**
1. Abra o arquivo `DBA_Scripts_Completos.sql` no SSMS
2. Navegue até a seção desejada pelo índice no cabeçalho
3. Cada seção indica `[master]` ou `[banco específico]` para conexão
4. Leia o bloco de comentários antes de executar — ele explica o contexto

---

## 🔍 Padrão de cada seção

Todas as seções seguem o mesmo padrão:

```
-- QUANDO USAR   → situação que justifica executar o script
-- IMPORTÂNCIA   → por que esse script é relevante
-- ONDE EXECUTAR → [master] ou [banco específico]
-- O QUE ANALISAR→ explicação das colunas e valores
-- Coluna Status → OK / ATENÇÃO / CRÍTICO
```

---

## 🚨 Avisos importantes

- Seção 35 documenta **o que nunca fazer** em produção
- Scripts de manutenção (rebuild, update stats) devem ser executados fora do horário de pico
- `sp_WhoIsActive` e `sp_Blitz` precisam ser instalados separadamente — links na seção de pré-requisitos
- Teste sempre em homologação antes de aplicar índices ou alterações em produção

---

## 📄 Licença

MIT — livre para usar, adaptar e distribuir. Se ajudou, deixa uma ⭐

---

*Construído com base em cenários reais de produção. Contribuições são bem-vindas.*
