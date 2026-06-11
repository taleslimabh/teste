-- ============================================================
--  DBA SCRIPTS COMPLETOS — SQL SERVER MONITORAMENTO E MANUTENÇÃO
--  Versão 3.0 | Padronizado e documentado
--
--  PADRÃO DE CADA SEÇÃO:
--    QUANDO USAR   → situação que justifica executar o script
--    IMPORTÂNCIA   → por que esse script é relevante
--    ONDE EXECUTAR → [master] ou [banco específico]
--    O QUE ANALISAR→ explicação das colunas e valores
--    Coluna Status → OK / ATENÇÃO / CRÍTICO em todos os scripts
--
--  ÍNDICE:
--    SEÇÃO 01 — Diagnóstico geral do servidor (sp_Blitz)
--    SEÇÃO 02 — O que está rodando agora (sp_WhoIsActive)
--    SEÇÃO 03 — Top queries agora (nativo)
--    SEÇÃO 04 — CPU alta: fluxo completo de diagnóstico
--    SEÇÃO 05 — Wait Stats: gargalos do servidor
--    SEÇÃO 06 — Blocking e Deadlocks
--    SEÇÃO 07 — Sessões, conexões e vazamento de pool
--    SEÇÃO 08 — Índices faltantes (missing indexes)
--    SEÇÃO 09 — Fragmentação e manutenção de índices
--    SEÇÃO 10 — Índices não utilizados
--    SEÇÃO 11 — Stored Procedures mais pesadas
--    SEÇÃO 12 — Triggers mais pesadas
--    SEÇÃO 13 — Query Store: histórico de performance
--    SEÇÃO 14 — Memory Grants: queries esperando memória
--    SEÇÃO 15 — TempDB: uso e pressão
--    SEÇÃO 16 — Memória e Buffer Pool
--    SEÇÃO 17 — I/O e latência de disco
--    SEÇÃO 18 — Estatísticas desatualizadas
--    SEÇÃO 19 — Plan Cache
--    SEÇÃO 20 — Backup e Transaction Log
--    SEÇÃO 21 — Health Check: integridade dos bancos
--    SEÇÃO 22 — Jobs com falha
--    SEÇÃO 23 — Configurações críticas do servidor
--    SEÇÃO 24 — VLFs e crescimento do log
--    SEÇÃO 25 — Crescimento de arquivos (autogrowth)
--    SEÇÃO 26 — Infraestrutura de monitoramento contínuo
--    SEÇÃO 27 — Manutenção automatizada (Ola Hallengren)
--    SEÇÃO 28 — Validação de índices: baseline antes/depois
--    SEÇÃO 29 — Playbook de incidente: sistema lento / CPU 100%
--    SEÇÃO 30 — Estatísticas e cardinalidade
--    SEÇÃO 31 — Histórico de crescimento do banco
--    SEÇÃO 32 — Disponibilidade e reinícios inesperados
--    SEÇÃO 33 — Consumo de disco por banco
--    SEÇÃO 34 — Top regressões no Query Store
--    SEÇÃO 35 — Avisos críticos: o que nunca fazer
--
--  LEGENDA:
--    [master]   = execute conectado ao banco master
--    [banco]    = execute conectado ao banco de destino
-- ============================================================


-- ============================================================
-- SEÇÃO 01 — DIAGNÓSTICO GERAL DO SERVIDOR (sp_Blitz)
-- ============================================================
-- QUANDO USAR:
--   Ao assumir um servidor novo, após incidentes,
--   semanalmente como rotina, suspeita de problema sem
--   causa óbvia.
--
-- IMPORTÂNCIA:
--   Check-up completo do servidor. Retorna lista priorizada
--   de problemas, riscos e configurações erradas.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   Priority 1-10  → CRÍTICO: ação imediata
--   Priority 11-50 → URGENTE: resolver em breve
--   Priority 51-200→ ATENÇÃO: melhorias recomendadas
--   FindingsGroup  → categoria do problema
--
-- ⚠️ sys.dm_os_wait_stats é ACUMULATIVO desde o último restart.
--   Use sp_BlitzFirst @SinceStartup=1 para visão normalizada.
-- ============================================================

USE master
GO

EXEC sp_Blitz
EXEC sp_Blitz @DatabaseName = 'SRH'
EXEC sp_BlitzFirst @Seconds = 30
EXEC sp_BlitzFirst @SinceStartup = 1

SELECT
    sqlserver_start_time                            AS SQL_Iniciou_Em,
    DATEDIFF(DAY,  sqlserver_start_time, GETDATE()) AS Dias_Rodando,
    CASE
        WHEN DATEDIFF(DAY, sqlserver_start_time, GETDATE()) < 1
        THEN 'ATENÇÃO — waits ainda não acumularam (< 1 dia)'
        WHEN DATEDIFF(DAY, sqlserver_start_time, GETDATE()) < 7
        THEN 'OK — waits confiáveis (< 7 dias)'
        ELSE 'OK — use snapshot ANTES/DEPOIS para análise pontual'
    END                                             AS Status
FROM sys.dm_os_sys_info


-- ============================================================
-- SEÇÃO 02 — O QUE ESTÁ RODANDO AGORA (sp_WhoIsActive)
-- ============================================================
-- QUANDO USAR:
--   Reclamação de lentidão, processos críticos como fechamento
--   de folha, rotina de monitoramento ativo, qualquer incidente
--   onde a primeira pergunta é "o que está acontecendo agora".
--
-- IMPORTÂNCIA:
--   Responde "quem está fazendo o quê" em tempo real.
--   É a primeira ferramenta a usar em qualquer incidente.
--   Mostra sessões, CPU, I/O, waits, locks e planos numa
--   única consulta — o que as DMVs nativas exigiriam 5 queries.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   [blocking_session_id] preenchido → sessão travada por outra
--   [cpu] alto                        → consumindo processador
--   [elapsed_time] longo              → rodando há muito tempo
--   [wait_info] preenchido            → por que está esperando
--   [reads] / [writes] altos          → muito I/O de disco
--   [status] = suspended              → aguardando algum recurso
--   [status] = sleeping               → conexão ociosa (pool)
--
-- PARÂMETROS MAIS IMPORTANTES:
--   @get_plans        → 1 = inclui plano de execução (XML)
--   @get_locks        → 1 = mostra locks detalhados por objeto
--   @get_task_info    → 2 = mostra waits por thread (paralelismo)
--   @find_block_leaders→ 1 = identifica a raiz do bloqueio
--   @get_outer_command → 1 = mostra o comando externo (proc/job)
--   @sort_order       → coluna de ordenação entre colchetes
--   @filter / @filter_type → filtrar por banco, login, host
--   @not_filter / @not_filter_type → excluir da listagem
--   @show_sleeping_spids→ 0=só ativas, 1=inclui dormentes
--   @destination_table → salvar resultado em tabela
-- ============================================================

USE master
GO

-- ─────────────────────────────────────────────────────────────
-- USO 1: Visão básica — o que está rodando agora
-- Usar como primeiro passo em qualquer incidente
-- ─────────────────────────────────────────────────────────────
EXEC sp_WhoIsActive


-- ─────────────────────────────────────────────────────────────
-- USO 2: Completo — com plano, locks e identificação de bloqueio
-- Usar quando o básico mostrar algo suspeito ou em incidentes
-- O @get_task_info=2 mostra waits por thread em queries paralelas
-- ─────────────────────────────────────────────────────────────
EXEC sp_WhoIsActive
    @get_plans         = 1,   -- inclui plano de execução
    @get_locks         = 1,   -- mostra locks por objeto
    @get_task_info     = 2,   -- waits detalhados por thread
    @find_block_leaders = 1,  -- identifica raiz do bloqueio
    @get_outer_command = 1    -- mostra procedure/job que chamou


-- ─────────────────────────────────────────────────────────────
-- USO 3: CPU alta — ordenar por consumo de CPU
-- Usar quando CPU está alta e precisa identificar o responsável
-- ─────────────────────────────────────────────────────────────
EXEC sp_WhoIsActive @sort_order = '[CPU] DESC'


-- ─────────────────────────────────────────────────────────────
-- USO 4: Queries mais antigas — identificar processos travados
-- Usar para encontrar queries que estão rodando há muito tempo
-- ─────────────────────────────────────────────────────────────
EXEC sp_WhoIsActive @sort_order = '[elapsed_time] DESC'


-- ─────────────────────────────────────────────────────────────
-- USO 5: Blocking — quem está bloqueando mais sessões
-- Usar quando há suspeita de deadlock ou travamento em cascata
-- ─────────────────────────────────────────────────────────────
EXEC sp_WhoIsActive
    @get_locks         = 1,
    @find_block_leaders = 1,
    @sort_order        = '[blocked_session_count] DESC'


-- ─────────────────────────────────────────────────────────────
-- USO 6: Filtrar por banco específico
-- Usar durante fechamento de folha para monitorar apenas o SRH
-- ─────────────────────────────────────────────────────────────
EXEC sp_WhoIsActive
    @filter      = 'SRH',     -- nome do banco
    @filter_type = 'database'

-- Filtrar por usuário específico
EXEC sp_WhoIsActive
    @filter      = 'app_srh',  -- login name
    @filter_type = 'login'

-- Filtrar por host (máquina de origem)
EXEC sp_WhoIsActive
    @filter      = 'SRV-APP01', -- hostname
    @filter_type = 'host'


-- ─────────────────────────────────────────────────────────────
-- USO 7: Excluir processos do sistema e focar só na aplicação
-- Usar para reduzir ruído e ver só o que importa
-- ─────────────────────────────────────────────────────────────
EXEC sp_WhoIsActive
    @not_filter      = 'DBADash',  -- excluir processos de monitoramento
    @not_filter_type = 'program',
    @show_sleeping_spids = 0        -- ocultar sessões dormentes


-- ─────────────────────────────────────────────────────────────
-- USO 8: I/O alto — ordenar por leituras lógicas
-- Usar quando o problema é de I/O e não de CPU
-- ─────────────────────────────────────────────────────────────
EXEC sp_WhoIsActive @sort_order = '[reads] DESC'


-- ─────────────────────────────────────────────────────────────
-- USO 9: Incluir sessões dormentes (sleeping)
-- Usar para identificar connection leak — muitas conexões
-- abertas sem atividade real
-- @show_sleeping_spids = 1: inclui dormentes com transação aberta
-- @show_sleeping_spids = 2: inclui TODAS as dormentes
-- ─────────────────────────────────────────────────────────────
EXEC sp_WhoIsActive
    @show_sleeping_spids = 1,  -- dormentes com transação aberta
    @sort_order = '[elapsed_time] DESC'


-- ─────────────────────────────────────────────────────────────
-- USO 10: Salvar histórico em tabela para análise posterior
-- Usar como job agendado a cada 1-5 minutos durante incidentes
-- ou para capturar problemas intermitentes
--
-- PASSO 1: Gerar o DDL da tabela de destino
-- Execute este comando, copie o resultado e execute o CREATE TABLE gerado
EXEC sp_WhoIsActive
    @get_plans         = 1,
    @get_task_info     = 2,
    @find_block_leaders = 1,
    @return_schema     = 1,   -- retorna o DDL do CREATE TABLE
    @schema            = 'CREATE TABLE DBA.dbo.WhoIsActive_Log (<columns>)'
-- Após executar, copie o CREATE TABLE retornado e execute manualmente

-- PASSO 2: Executar para coletar (agendar no SQL Agent a cada 1-5 min)
EXEC sp_WhoIsActive
    @get_plans         = 1,
    @get_task_info     = 2,
    @find_block_leaders = 1,
    @destination_table = 'DBA.dbo.WhoIsActive_Log'

-- PASSO 3: Consultar o histórico coletado
SELECT TOP 100
    collection_time,
    session_id,
    [status],
    [cpu],
    [reads],
    [elapsed_time],
    [wait_info],
    blocking_session_id,
    [database_name],
    [sql_text]
FROM DBA.dbo.WhoIsActive_Log
ORDER BY collection_time DESC


-- ─────────────────────────────────────────────────────────────
-- USO 11: Delta de CPU — quanto cada sessão consumiu
-- entre duas coletas (útil para processos de longa duração)
-- ─────────────────────────────────────────────────────────────
EXEC sp_WhoIsActive
    @get_avg_time  = 1,   -- mostra tempo médio por execução
    @sort_order    = '[CPU] DESC'


-- ─────────────────────────────────────────────────────────────
-- USO 12: Diagnóstico completo durante fechamento de folha
-- Combina os parâmetros mais úteis para monitoramento intensivo
-- ─────────────────────────────────────────────────────────────
EXEC sp_WhoIsActive
    @get_plans         = 1,
    @get_locks         = 1,
    @get_task_info     = 2,
    @get_avg_time      = 1,
    @find_block_leaders = 1,
    @get_outer_command = 1,
    @filter            = 'SRH',
    @filter_type       = 'database',
    @sort_order        = '[elapsed_time] DESC'


-- ============================================================
-- SEÇÃO 03 — TOP QUERIES AGORA (NATIVO)
-- ============================================================
-- QUANDO USAR:
--   sp_WhoIsActive não instalado, automações, resposta
--   imediata em 5 segundos sem dependências externas.
--
-- IMPORTÂNCIA:
--   Query nativa — funciona em qualquer servidor SQL Server
--   sem instalação prévia.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   cpu_time alto          → consumindo CPU
--   logical_reads alto     → muito I/O (índice faltando?)
--   elapsed_seg alto       → rodando há muito tempo
--   blocking_session_id >0 → travada por outra sessão
--   Status                 → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT TOP 20
    r.session_id,
    r.status,
    r.cpu_time,
    r.total_elapsed_time / 1000                 AS elapsed_seg,
    r.logical_reads,
    r.reads                                     AS physical_reads,
    r.writes,
    r.wait_type,
    r.blocking_session_id,
    DB_NAME(r.database_id)                      AS banco,
    s.login_name,
    s.host_name,
    SUBSTRING(st.text,
        (r.statement_start_offset/2)+1,
        ((CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE r.statement_end_offset
          END - r.statement_start_offset)/2)+1) AS statement_atual,
    CASE
        WHEN r.blocking_session_id > 0
        THEN 'CRÍTICO — bloqueada por sessão ' +
              CAST(r.blocking_session_id AS VARCHAR)
        WHEN r.cpu_time > 60000
        THEN 'ATENÇÃO — CPU alta (' +
              CAST(r.cpu_time/1000 AS VARCHAR) + 's)'
        WHEN r.total_elapsed_time/1000 > 300
        THEN 'ATENÇÃO — rodando há ' +
              CAST(r.total_elapsed_time/1000 AS VARCHAR) + 's'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE r.session_id > 50 AND s.is_user_process = 1
ORDER BY r.cpu_time DESC


-- ============================================================
-- SEÇÃO 04 — CPU ALTA: FLUXO COMPLETO DE DIAGNÓSTICO
-- ============================================================
-- QUANDO USAR:
--   CPU acima de 80%, sistema lento. Execute os scripts
--   na ordem — cada um refina o anterior.
--
-- IMPORTÂNCIA:
--   Identifica a causa raiz da CPU alta em minutos,
--   cobrindo queries ad-hoc, procedures e triggers.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   avg_cpu_us alto   → query individualmente pesada
--   total_cpu_us alto → chamada muitas vezes (impacto cumulativo)
--   avg_reads alto    → I/O alto (índice faltando?)
--   Status            → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

-- Top queries por CPU acumulada no cache
SELECT TOP 20
    qs.total_worker_time/qs.execution_count     AS avg_cpu_us,
    qs.total_worker_time                        AS total_cpu_us,
    qs.execution_count,
    qs.total_elapsed_time/qs.execution_count    AS avg_elapsed_us,
    qs.total_logical_reads/qs.execution_count   AS avg_reads,
    qs.last_execution_time,
    DB_NAME(qt.dbid)                            AS banco,
    OBJECT_NAME(qt.objectid, qt.dbid)           AS objeto,
    SUBSTRING(qt.text,
        (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.text)
            ELSE qs.statement_end_offset
          END - qs.statement_start_offset)/2)+1) AS query_text,
    CASE
        WHEN qs.total_worker_time/qs.execution_count > 1000000
        THEN 'CRÍTICO — avg CPU > 1s por execução'
        WHEN qs.total_worker_time/qs.execution_count > 100000
        THEN 'ATENÇÃO — avg CPU > 100ms por execução'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
ORDER BY qs.total_worker_time DESC

-- Top via sp_BlitzCache — diferentes perspectivas
EXEC sp_BlitzCache @SortOrder='cpu',          @Top=10
EXEC sp_BlitzCache @SortOrder='reads',        @Top=10
EXEC sp_BlitzCache @SortOrder='duration',     @Top=10
EXEC sp_BlitzCache @SortOrder='memory grant', @Top=10
EXEC sp_BlitzCache @SortOrder='executions',   @Top=10

-- Top Stored Procedures por CPU
SELECT TOP 20
    OBJECT_NAME(ps.object_id,ps.database_id)    AS proc_name,
    DB_NAME(ps.database_id)                     AS banco,
    ps.total_worker_time/ps.execution_count     AS avg_cpu_us,
    ps.total_worker_time                        AS total_cpu_us,
    ps.execution_count,
    ps.total_elapsed_time/ps.execution_count    AS avg_duration_us,
    ps.total_logical_reads/ps.execution_count   AS avg_reads,
    ps.last_execution_time,
    CASE
        WHEN ps.total_worker_time/ps.execution_count > 1000000
        THEN 'CRÍTICO — avg CPU > 1s'
        WHEN ps.total_worker_time/ps.execution_count > 100000
        THEN 'ATENÇÃO — avg CPU > 100ms'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_exec_procedure_stats ps
WHERE OBJECT_NAME(ps.object_id,ps.database_id) IS NOT NULL
ORDER BY ps.total_worker_time DESC

-- Snapshot ANTES/DEPOIS de uma rotina crítica
-- Execute ANTES do processo:
SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
INTO ##waits_antes
FROM sys.dm_os_wait_stats
WHERE wait_type NOT LIKE 'SLEEP%'
  AND wait_type NOT LIKE '%IDLE%'
  AND wait_type NOT LIKE '%QUEUE%'

-- Execute APÓS o processo terminar:
SELECT
    a.wait_type,
    d.wait_time_ms - a.wait_time_ms               AS delta_wait_ms,
    d.waiting_tasks_count - a.waiting_tasks_count AS delta_tasks,
    CASE
        WHEN (d.wait_time_ms-a.wait_time_ms) > 60000
        THEN 'CRÍTICO — mais de 1min de espera'
        WHEN (d.wait_time_ms-a.wait_time_ms) > 10000
        THEN 'ATENÇÃO — espera relevante'
        ELSE 'OK'
    END                                           AS Status
FROM ##waits_antes a
JOIN sys.dm_os_wait_stats d ON a.wait_type = d.wait_type
WHERE d.wait_time_ms > a.wait_time_ms
ORDER BY delta_wait_ms DESC

DROP TABLE IF EXISTS ##waits_antes

-- ============================================================
-- SEÇÃO 05 — WAIT STATS: GARGALOS DO SERVIDOR
-- ============================================================
-- QUANDO USAR:
--   Sistema lento sem causa óbvia, investigação de gargalos
--   sistêmicos, análise de performance geral.
--
-- IMPORTÂNCIA:
--   Mostra ONDE o SQL Server está gastando tempo. É o
--   diagnóstico mais preciso de gargalo — mais confiável
--   que olhar CPU ou disco isoladamente.
--
-- ONDE EXECUTAR: [master]
--
-- ⚠️ sys.dm_os_wait_stats é ACUMULATIVO desde o último restart.
--   Compare sempre deltas. Use sp_BlitzFirst @SinceStartup=1
--   para visão já normalizada e interpretada.
--
-- O QUE ANALISAR:
--   pct_total > 30%     → esse wait domina os problemas
--   pct_signal > 25%    → pressão de CPU
--   pct_signal < 10%    → pressão de I/O, lock ou memória
--   Causa_Provavel      → orientação de ação para cada tipo
--   Status              → OK / ATENÇÃO / CRÍTICO
--
-- INTERPRETAÇÃO RÁPIDA:
--   PAGEIOLATCH_SH/EX   → disco lento ou índice faltando
--   CXPACKET            → paralelismo excessivo
--   SOS_SCHEDULER_YIELD → CPU sobrecarregada
--   WRITELOG            → disco do .ldf lento
--   RESOURCE_SEMAPHORE  → falta memória para queries
--   LCK_M_*             → blocking / lock contention
--   ASYNC_NETWORK_IO    → cliente não consome dados rápido
-- ============================================================

USE master
GO

SELECT TOP 20
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    max_wait_time_ms,
    signal_wait_time_ms,
    CAST(100.0*wait_time_ms
        /SUM(wait_time_ms) OVER() AS DECIMAL(5,2))  AS pct_total,
    CAST(100.0*signal_wait_time_ms
        /NULLIF(wait_time_ms,0) AS DECIMAL(5,2))     AS pct_signal,
    CASE
        WHEN wait_type IN ('PAGEIOLATCH_SH','PAGEIOLATCH_EX')
        THEN 'Disco lento ou índice faltando → Seção 08/09'
        WHEN wait_type IN ('CXPACKET','CXSYNC_PORT','CXSYNC_CONSUMER')
        THEN 'Paralelismo → ajustar cost threshold for parallelism'
        WHEN wait_type = 'SOS_SCHEDULER_YIELD'
        THEN 'Pressão de CPU → queries com table scan'
        WHEN wait_type = 'WRITELOG'
        THEN 'Log lento → verificar disco do .ldf'
        WHEN wait_type = 'RESOURCE_SEMAPHORE'
        THEN 'Falta memória → Seção 14 e 16'
        WHEN wait_type LIKE 'LCK_M_%'
        THEN 'Blocking → Seção 06'
        WHEN wait_type = 'ASYNC_NETWORK_IO'
        THEN 'Cliente lento consumindo resultado'
        WHEN wait_type = 'BACKUPIO'
        THEN 'Backup em execução (normal)'
        ELSE 'Verificar documentação'
    END                                              AS Causa_Provavel,
    CASE
        WHEN CAST(100.0*wait_time_ms
             /SUM(wait_time_ms) OVER() AS DECIMAL(5,2)) > 30
        THEN 'CRÍTICO — domina os waits do servidor'
        WHEN CAST(100.0*wait_time_ms
             /SUM(wait_time_ms) OVER() AS DECIMAL(5,2)) > 10
        THEN 'ATENÇÃO — wait relevante'
        ELSE 'OK'
    END                                              AS Status
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'SLEEP_TASK','BROKER_TO_FLUSH','BROKER_TASK_STOP',
    'CLR_AUTO_EVENT','DISPATCHER_QUEUE_SEMAPHORE',
    'FT_IFTS_SCHEDULER_IDLE_WAIT','HADR_WORK_QUEUE',
    'LAZYWRITER_SLEEP','LOGMGR_QUEUE','ONDEMAND_TASK_QUEUE',
    'REQUEST_FOR_DEADLOCK_MONITOR','RESOURCE_QUEUE',
    'SERVER_IDLE_CHECK','SLEEP_DBSTARTUP','SLEEP_DBRECOVER',
    'SLEEP_MASTERDBREADY','SLEEP_MASTERMDREADY',
    'SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP',
    'SLEEP_SYSTEMTASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
    'SP_SERVER_DIAGNOSTICS_SLEEP','SQLTRACE_BUFFER_FLUSH',
    'WAITFOR','XE_DISPATCHER_WAIT','XE_TIMER_EVENT',
    'BROKER_EVENTHANDLER','CHECKPOINT_QUEUE',
    'DBMIRROR_EVENTS_QUEUE','SQLTRACE_INCREMENTAL_FLUSH_SLEEP'
)
ORDER BY wait_time_ms DESC


-- ============================================================
-- SEÇÃO 06 — BLOCKING E DEADLOCKS
-- ============================================================
-- QUANDO USAR:
--   Usuários com timeout, sistema lento com CPU baixa,
--   suspeita de travamento em cascata.
--
-- IMPORTÂNCIA:
--   Blocking é silencioso — uma sessão pode travar dezenas
--   de outras sem aparecer no monitoramento de CPU.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   blocker_session    → quem está causando o travamento
--   wait_seconds alto  → há quanto tempo está travado
--   blocker_query      → qual operação segura o lock
--   Status             → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT
    blocking.session_id                         AS blocker_session,
    SUBSTRING(bt.text,1,300)                    AS blocker_query,
    blocked.session_id                          AS blocked_session,
    SUBSTRING(bdt.text,1,300)                   AS blocked_query,
    blocked.wait_type,
    blocked.wait_time/1000                      AS wait_seconds,
    DB_NAME(blocked.database_id)                AS banco,
    CASE
        WHEN blocked.wait_time/1000 > 60
        THEN 'CRÍTICO — bloqueado há mais de 60s'
        WHEN blocked.wait_time/1000 > 10
        THEN 'ATENÇÃO — bloqueado há mais de 10s'
        ELSE 'OK — bloqueio recente'
    END                                         AS Status
FROM sys.dm_exec_requests blocked
JOIN sys.dm_exec_requests blocking
    ON blocked.blocking_session_id = blocking.session_id
CROSS APPLY sys.dm_exec_sql_text(blocked.sql_handle)  bdt
CROSS APPLY sys.dm_exec_sql_text(blocking.sql_handle) bt
WHERE blocked.blocking_session_id > 0
ORDER BY blocked.wait_time DESC

EXEC sp_BlitzLock
EXEC sp_BlitzLock @StartDate='2026-06-01', @EndDate='2026-06-03'


-- ============================================================
-- SEÇÃO 07 — SESSÕES, CONEXÕES E VAZAMENTO DE POOL
-- ============================================================
-- QUANDO USAR:
--   Conexões crescendo sem parar, timeout de conexão,
--   muitas sessões idle, suspeita de connection leak.
--
-- IMPORTÂNCIA:
--   Pools mal configurados e leaks consomem memória e podem
--   derrubar o servidor ao atingir o limite de conexões.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   conexoes alto por grupo    → pool mal configurado ou leak
--   max_min_sem_atividade alto → conexões abandonadas
--   Status                     → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT
    login_name, host_name, program_name, status,
    COUNT(*)                                    AS conexoes,
    SUM(CASE WHEN status='sleeping' THEN 1 ELSE 0 END) AS sleeping,
    SUM(CASE WHEN status='running'  THEN 1 ELSE 0 END) AS running,
    MAX(DATEDIFF(MINUTE,last_request_end_time,GETDATE())) AS max_min_sem_atividade,
    CASE
        WHEN COUNT(*) > 100
        THEN 'CRÍTICO — mais de 100 conexões desse grupo'
        WHEN COUNT(*) > 50
        THEN 'ATENÇÃO — mais de 50 conexões'
        WHEN MAX(DATEDIFF(MINUTE,last_request_end_time,GETDATE())) > 60
        THEN 'ATENÇÃO — inativas há mais de 1 hora'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY login_name, host_name, program_name, status
ORDER BY conexoes DESC

SELECT
    session_id, login_name, host_name, program_name, status,
    last_request_end_time,
    DATEDIFF(MINUTE,last_request_end_time,GETDATE()) AS min_sem_atividade,
    CASE
        WHEN DATEDIFF(MINUTE,last_request_end_time,GETDATE()) > 120
        THEN 'CRÍTICO — inativa há mais de 2 horas'
        WHEN DATEDIFF(MINUTE,last_request_end_time,GETDATE()) > 30
        THEN 'ATENÇÃO — inativa há mais de 30 min'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_exec_sessions
WHERE is_user_process=1 AND status='sleeping'
  AND last_request_end_time < DATEADD(MINUTE,-30,GETDATE())
ORDER BY min_sem_atividade DESC

SELECT
    DB_NAME(r.database_id)                      AS Banco,
    COUNT(*)                                    AS Conexoes,
    CASE
        WHEN COUNT(*) > 200 THEN 'CRÍTICO'
        WHEN COUNT(*) > 100 THEN 'ATENÇÃO'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
WHERE s.is_user_process = 1
  AND r.database_id IS NOT NULL
GROUP BY r.database_id
ORDER BY Conexoes DESC


-- ============================================================
-- SEÇÃO 08 — ÍNDICES FALTANTES (MISSING INDEXES)
-- ============================================================
-- QUANDO USAR:
--   sp_Blitz reportou missing indexes, queries lentas sem
--   causa óbvia, análise periódica de performance.
--
-- IMPORTÂNCIA:
--   O SQL Server registra automaticamente quando uma query
--   precisaria de um índice. Mostra o impacto potencial já
--   com o comando CREATE INDEX pronto.
--
-- ONDE EXECUTAR: [banco específico]
--
-- ⚠️ NUNCA criar índices automaticamente sem verificar:
--   1. Índices já existentes similares
--   2. Duplicatas que seriam criadas
--   3. Custo em INSERT/UPDATE/DELETE
--   4. Testar em homologação primeiro
--
-- O QUE ANALISAR:
--   improvement_score → PRIORIDADE: quanto maior, mais urgente
--   avg_benefit_pct   → % estimada de melhoria (>70% = criar)
--   user_seeks alto   → quantas vezes necessitou do índice
--   Status            → CRIAR / AVALIAR / BAIXA PRIORIDADE
-- ============================================================

USE SRH  -- TROQUE AQUI
GO

SELECT TOP 30
    ROUND(migs.avg_total_user_cost *
          migs.avg_user_impact *
         (migs.user_seeks+migs.user_scans),0)   AS improvement_score,
    migs.avg_user_impact                        AS avg_benefit_pct,
    migs.user_seeks,
    migs.user_scans,
    migs.last_user_seek,
    DB_NAME(mid.database_id)                    AS banco,
    OBJECT_NAME(mid.object_id,mid.database_id)  AS tabela,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns,
    'CREATE NONCLUSTERED INDEX IX_' +
        OBJECT_NAME(mid.object_id,mid.database_id)+'_'+
        REPLACE(REPLACE(ISNULL(mid.equality_columns,''),'[',''),']','')+
        CASE WHEN mid.inequality_columns IS NOT NULL
             THEN '_'+REPLACE(REPLACE(mid.inequality_columns,'[',''),']','')
             ELSE '' END+
    ' ON '+mid.statement+
    ' ('+ISNULL(mid.equality_columns,'')+
        CASE WHEN mid.equality_columns IS NOT NULL
              AND mid.inequality_columns IS NOT NULL THEN ', ' ELSE '' END+
        ISNULL(mid.inequality_columns,'')+')'+
    ISNULL(' INCLUDE ('+mid.included_columns+')','') +
    ' WITH (FILLFACTOR=90, ONLINE=OFF, SORT_IN_TEMPDB=ON)'
                                                AS create_index_command,
    CASE
        WHEN ROUND(migs.avg_total_user_cost*migs.avg_user_impact*
                  (migs.user_seeks+migs.user_scans),0) > 100000
         AND migs.avg_user_impact > 70
        THEN 'CRIAR — alto impacto e benefício'
        WHEN ROUND(migs.avg_total_user_cost*migs.avg_user_impact*
                  (migs.user_seeks+migs.user_scans),0) > 10000
        THEN 'AVALIAR — impacto moderado'
        ELSE 'BAIXA PRIORIDADE'
    END                                         AS Status
FROM sys.dm_db_missing_index_groups   mig
JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle=migs.group_handle
JOIN sys.dm_db_missing_index_details  mid     ON mig.index_handle=mid.index_handle
WHERE mid.database_id = DB_ID()
ORDER BY improvement_score DESC

USE master
GO
EXEC sp_BlitzIndex @DatabaseName='SRH',    @Mode=4
EXEC sp_BlitzIndex @DatabaseName='SRH_HM', @Mode=4


-- ============================================================
-- SEÇÃO 09 — FRAGMENTAÇÃO E MANUTENÇÃO DE ÍNDICES
-- ============================================================
-- QUANDO USAR:
--   Queries lentas sem índice faltando aparente, antes de
--   agendar manutenção, após fechamento de folha, rotina semanal.
--
-- IMPORTÂNCIA:
--   Índices fragmentados causam mais I/O desnecessário.
--   Após rebuild, queries podem melhorar 2x a 5x.
--
-- ONDE EXECUTAR: [banco específico]
--
-- ⚠️ Standard Edition: REBUILD trava a tabela.
--   Execute apenas em janela de manutenção (madrugada).
--   REORGANIZE pode rodar a qualquer hora sem travamento.
--
-- O QUE ANALISAR:
--   Fragmentacao > 30% → REBUILD necessário
--   Fragmentacao 10-30%→ REORGANIZE recomendado
--   Paginas < 100      → ignorar (índice pequeno)
--   Status             → OK / REORGANIZE / REBUILD
-- ============================================================

USE SRH_HM  -- TROQUE AQUI
GO

SELECT
    OBJECT_NAME(ips.object_id)                  AS Tabela,
    i.name                                      AS Indice,
    ROUND(ips.avg_fragmentation_in_percent,1)   AS Fragmentacao_Pct,
    ips.page_count                              AS Paginas,
    ROUND(ips.page_count*8.0/1024,1)            AS Tamanho_MB,
    CASE
        WHEN ips.avg_fragmentation_in_percent > 30
        THEN 'REBUILD — fragmentação crítica'
        WHEN ips.avg_fragmentation_in_percent > 10
        THEN 'REORGANIZE — fragmentação moderada'
        ELSE 'OK — fragmentação aceitável'
    END                                         AS Status
FROM sys.dm_db_index_physical_stats(DB_ID(),NULL,NULL,NULL,'LIMITED') ips
JOIN sys.indexes i ON ips.object_id=i.object_id AND ips.index_id=i.index_id
WHERE ips.avg_fragmentation_in_percent > 10
  AND ips.page_count > 100
  AND i.name IS NOT NULL
ORDER BY ips.avg_fragmentation_in_percent DESC

-- Manutenção automática (agendar no SQL Agent — domingo 01:00)
USE master
GO
EXEC master.dbo.IndexOptimize
    @Databases='SRH_HM,SRH_QA,SRH',
    @FragmentationLow=NULL,
    @FragmentationMedium='INDEX_REORGANIZE',
    @FragmentationHigh='INDEX_REBUILD_OFFLINE',
    @FragmentationLevel1=10,
    @FragmentationLevel2=30,
    @MinNumberOfPages=100,
    @UpdateStatistics='ALL',
    @OnlyModifiedStatistics='Y',
    @LogToTable='Y'

-- Tabelas críticas — rodar após fechamento de folha
EXEC master.dbo.IndexOptimize
    @Databases='SRH_HM',
    @FragmentationLow=NULL,
    @FragmentationMedium='INDEX_REORGANIZE',
    @FragmentationHigh='INDEX_REBUILD_OFFLINE',
    @FragmentationLevel1=10,
    @FragmentationLevel2=30,
    @MinNumberOfPages=100,
    @UpdateStatistics='ALL',
    @LogToTable='Y',
    @Objects='SRH_HM.dbo.ITENS,SRH_HM.dbo.FOLHAS_SERVIDOR,SRH_HM.dbo.PARCELA_CONSIGNACAO,SRH_HM.dbo.PESSOAL'

-- Resultado das últimas manutenções
SELECT TOP 100
    DatabaseName, ObjectName AS Tabela, IndexName AS Indice,
    CommandType AS Acao, StartTime, EndTime,
    DATEDIFF(SECOND,StartTime,EndTime) AS Duracao_seg,
    ErrorNumber, ErrorMessage,
    CASE
        WHEN ErrorNumber IS NOT NULL
        THEN 'CRÍTICO — erro: '+ErrorMessage
        WHEN DATEDIFF(SECOND,StartTime,EndTime) > 3600
        THEN 'ATENÇÃO — manutenção > 1 hora'
        ELSE 'OK'
    END                                         AS Status
FROM master.dbo.CommandLog
ORDER BY StartTime DESC


-- ============================================================
-- SEÇÃO 10 — ÍNDICES NÃO UTILIZADOS
-- ============================================================
-- QUANDO USAR:
--   Análise semestral, INSERT/UPDATE lento sem causa óbvia,
--   auditoria de índices existentes.
--
-- IMPORTÂNCIA:
--   Cada índice tem custo em toda operação de escrita.
--   Índices sem uso só prejudicam.
--
-- ONDE EXECUTAR: [banco específico]
--
-- ⚠️ DMVs resetam ao reiniciar o SQL Server.
--   Só remova com dados de semanas/meses de operação.
--   Verifique stats_validas_desde antes de decidir.
--
-- O QUE ANALISAR:
--   seeks=0 + scans=0 + updates alto → remover candidato
--   ratio_seek_update < 1.0          → custo > benefício
--   Status → OK / ATENÇÃO / REMOVER
-- ============================================================

USE SRH_HM  -- TROQUE AQUI
GO

SELECT
    OBJECT_NAME(i.object_id)                    AS Tabela,
    i.name                                      AS Indice,
    ISNULL(s.user_seeks,0)                      AS seeks,
    ISNULL(s.user_scans,0)                      AS scans,
    ISNULL(s.user_lookups,0)                    AS lookups,
    ISNULL(s.user_updates,0)                    AS updates,
    s.last_user_seek,
    s.last_user_update,
    CAST(ROUND(ISNULL(s.user_seeks,0)*1.0
        /NULLIF(s.user_updates,0),2)
        AS DECIMAL(10,2))                       AS ratio_seek_update,
    (SELECT sqlserver_start_time FROM sys.dm_os_sys_info) AS stats_validas_desde,
    'DROP INDEX '+QUOTENAME(i.name)+
    ' ON '+QUOTENAME(OBJECT_NAME(i.object_id))  AS drop_command,
    CASE
        WHEN s.object_id IS NULL
        THEN 'ATENÇÃO — sem stats desde último restart'
        WHEN ISNULL(s.user_seeks,0)=0
         AND ISNULL(s.user_scans,0)=0
         AND ISNULL(s.user_lookups,0)=0
         AND ISNULL(s.user_updates,0)>10000
        THEN 'REMOVER — só custo de escrita, nunca lido'
        WHEN ISNULL(s.user_lookups,0) > 10000
        THEN 'ATENÇÃO — muitos lookups, avaliar INCLUDE'
        WHEN ISNULL(s.user_seeks,0) > 1000
        THEN 'OK — muito utilizado'
        WHEN ISNULL(s.user_seeks,0) > 100
        THEN 'OK — utilizado'
        ELSE 'ATENÇÃO — pouco uso, monitorar'
    END                                         AS Status
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats s
    ON i.object_id=s.object_id AND i.index_id=s.index_id
    AND s.database_id=DB_ID()
WHERE i.type_desc<>'HEAP' AND i.is_primary_key=0
  AND i.is_unique_constraint=0 AND i.is_disabled=0
ORDER BY ISNULL(s.user_seeks,0), ISNULL(s.user_updates,0) DESC


-- ============================================================
-- SEÇÃO 11 — STORED PROCEDURES MAIS PESADAS
-- ============================================================
-- QUANDO USAR:
--   CPU alta sem query ad-hoc óbvia, tuning de aplicação,
--   análise de processos críticos.
--
-- IMPORTÂNCIA:
--   100ms × 10.000 execuções = 1000 segundos de CPU.
--   Impacto cumulativo é invisível olhando apenas execuções individuais.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   avg_cpu_us alto   → procedure individualmente lenta
--   total_cpu_us alto → chamada com alta frequência
--   Status            → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT TOP 20
    OBJECT_NAME(ps.object_id,ps.database_id)    AS proc_name,
    DB_NAME(ps.database_id)                     AS banco,
    ps.total_worker_time/ps.execution_count     AS avg_cpu_us,
    ps.total_worker_time                        AS total_cpu_us,
    ps.execution_count,
    ps.total_elapsed_time/ps.execution_count    AS avg_duration_us,
    ps.total_logical_reads/ps.execution_count   AS avg_reads,
    ps.last_execution_time,
    CASE
        WHEN ps.total_worker_time/ps.execution_count > 1000000
        THEN 'CRÍTICO — avg CPU > 1s por execução'
        WHEN ps.total_worker_time/ps.execution_count > 100000
        THEN 'ATENÇÃO — avg CPU > 100ms'
        WHEN ps.total_logical_reads/ps.execution_count > 100000
        THEN 'ATENÇÃO — avg reads muito alto'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_exec_procedure_stats ps
WHERE OBJECT_NAME(ps.object_id,ps.database_id) IS NOT NULL
ORDER BY ps.total_worker_time DESC


-- ============================================================
-- SEÇÃO 12 — TRIGGERS MAIS PESADAS
-- ============================================================
-- QUANDO USAR:
--   INSERT/UPDATE/DELETE lentos sem causa óbvia, CPU alta
--   durante operações de escrita.
--
-- IMPORTÂNCIA:
--   Triggers causam lentidão silenciosa. O banco SRH tem
--   246 triggers — monitoramento contínuo é essencial.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   avg_cpu_us alto   → trigger lenta em cada execução
--   total_cpu_us alto → executada com alta frequência
--   Status            → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT TOP 20
    OBJECT_NAME(ts.object_id,ts.database_id)    AS trigger_name,
    OBJECT_NAME(t.parent_id,ts.database_id)     AS tabela_pai,
    DB_NAME(ts.database_id)                     AS banco,
    ts.total_worker_time/ts.execution_count     AS avg_cpu_us,
    ts.total_worker_time                        AS total_cpu_us,
    ts.execution_count,
    ts.total_elapsed_time/ts.execution_count    AS avg_duration_us,
    ts.last_execution_time,
    CASE
        WHEN ts.total_worker_time/ts.execution_count > 500000
        THEN 'CRÍTICO — trigger > 500ms por execução'
        WHEN ts.total_worker_time/ts.execution_count > 100000
        THEN 'ATENÇÃO — trigger > 100ms por execução'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_exec_trigger_stats ts
JOIN sys.triggers t ON ts.object_id=t.object_id
ORDER BY ts.total_worker_time DESC

USE SRH  -- TROQUE AQUI
GO
SELECT
    t.name AS trigger_name, OBJECT_NAME(t.parent_id) AS tabela,
    t.is_disabled, t.create_date, t.modify_date,
    CASE WHEN t.is_disabled=1
         THEN 'ATENÇÃO — trigger desabilitada'
         ELSE 'OK'
    END                                         AS Status
FROM sys.triggers t
WHERE t.parent_class_desc='OBJECT_OR_COLUMN'
ORDER BY OBJECT_NAME(t.parent_id), t.name

-- ============================================================
-- SEÇÃO 13 — QUERY STORE: HISTÓRICO DE PERFORMANCE
-- ============================================================
-- QUANDO USAR:
--   Problema ocorreu horas atrás e já passou (DMVs limpas).
--   Ex: CPU foi a 100% às 10h, você analisa às 14h.
--   Também para detectar regressão de plano.
--
-- IMPORTÂNCIA:
--   Única ferramenta com histórico persistente de performance
--   sem precisar de trace configurado previamente.
--
-- ONDE EXECUTAR: [banco específico]
--
-- O QUE ANALISAR:
--   avg_duration_ms alto   → query individualmente lenta
--   avg_reads alto         → muito I/O (índice faltando?)
--   plan_count > 1         → instabilidade de plano
--   fator_piora > 2        → query piorou 2x ou mais
--   Status                 → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE SRH  -- TROQUE AQUI
GO

SELECT
    actual_state_desc                           AS Estado,
    current_storage_size_mb                     AS Tamanho_MB,
    max_storage_size_mb                         AS Max_MB,
    query_capture_mode_desc                     AS Modo_Captura,
    CASE
        WHEN actual_state_desc='OFF'
        THEN 'CRÍTICO — Query Store desativado'
        WHEN actual_state_desc='READ_ONLY'
        THEN 'ATENÇÃO — armazenamento cheio'
        WHEN current_storage_size_mb > max_storage_size_mb*0.8
        THEN 'ATENÇÃO — acima de 80% da capacidade'
        ELSE 'OK'
    END                                         AS Status
FROM sys.database_query_store_options

-- Top 20 por duração — últimas 24h
SELECT TOP 20
    qt.query_sql_text,
    SUM(rs.count_executions)                    AS execucoes,
    ROUND(AVG(rs.avg_duration)/1000.0,2)        AS avg_duration_ms,
    ROUND(AVG(rs.avg_cpu_time)/1000.0,2)        AS avg_cpu_ms,
    CAST(AVG(rs.avg_logical_io_reads) AS BIGINT) AS avg_reads,
    COUNT(DISTINCT p.plan_id)                   AS plan_count,
    MAX(rs.last_execution_time)                 AS ultima_execucao,
    CASE
        WHEN COUNT(DISTINCT p.plan_id) > 3
        THEN 'CRÍTICO — múltiplos planos, possível regressão'
        WHEN AVG(rs.avg_duration)/1000.0 > 5000
        THEN 'CRÍTICO — duração média > 5s'
        WHEN AVG(rs.avg_duration)/1000.0 > 1000
        THEN 'ATENÇÃO — duração média > 1s'
        ELSE 'OK'
    END                                         AS Status
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id=qt.query_text_id
JOIN sys.query_store_plan p        ON q.query_id=p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id=rs.plan_id
JOIN sys.query_store_runtime_stats_interval rsi
    ON rs.runtime_stats_interval_id=rsi.runtime_stats_interval_id
WHERE rsi.start_time >= DATEADD(HOUR,-24,GETDATE())
GROUP BY qt.query_sql_text, q.query_id
ORDER BY AVG(rs.avg_duration) DESC

-- Detecção de regressão de plano
SELECT TOP 20
    qt.query_sql_text,
    ROUND(r.avg_duration/1000.0,2)              AS recente_ms,
    ROUND(h.avg_duration/1000.0,2)              AS historico_ms,
    ROUND(r.avg_duration*1.0/NULLIF(h.avg_duration,0),2) AS fator_piora,
    r.last_execution_time,
    CASE
        WHEN r.avg_duration > h.avg_duration*5
        THEN 'CRÍTICO — 5x mais lenta que o histórico'
        WHEN r.avg_duration > h.avg_duration*2
        THEN 'ATENÇÃO — 2x mais lenta que o histórico'
        ELSE 'OK'
    END                                         AS Status
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id=qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id=p.query_id
JOIN sys.query_store_runtime_stats r ON p.plan_id=r.plan_id
JOIN sys.query_store_runtime_stats_interval ri
    ON r.runtime_stats_interval_id=ri.runtime_stats_interval_id
   AND ri.start_time >= DATEADD(HOUR,-1,GETDATE())
JOIN sys.query_store_runtime_stats h ON p.plan_id=h.plan_id
JOIN sys.query_store_runtime_stats_interval hi
    ON h.runtime_stats_interval_id=hi.runtime_stats_interval_id
   AND hi.start_time BETWEEN DATEADD(HOUR,-24,GETDATE())
                         AND DATEADD(HOUR,-1,GETDATE())
WHERE r.avg_duration > h.avg_duration*2
ORDER BY fator_piora DESC


-- ============================================================
-- SEÇÃO 14 — MEMORY GRANTS: QUERIES ESPERANDO MEMÓRIA
-- ============================================================
-- QUANDO USAR:
--   CPU baixa, disco normal, sistema ainda lento.
--   Wait RESOURCE_SEMAPHORE nos wait stats.
--
-- IMPORTÂNCIA:
--   Queries esperando memory grant ficam paradas sem
--   consumir CPU — invisíveis para quem monitora só CPU.
--   Um dos problemas mais silenciosos do SQL Server.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   grant_time NULL     → esperando na fila (crítico)
--   wait_time_ms alto   → esperando há muito tempo
--   usado << concedido  → grant desperdiçado (estatísticas velhas)
--   Aguardando_Grant > 5→ fila grande — problema sério
--   Status              → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT
    r.session_id,
    mg.request_time,
    mg.grant_time,
    mg.requested_memory_kb/1024                 AS Solicitado_MB,
    mg.granted_memory_kb/1024                   AS Concedido_MB,
    mg.used_memory_kb/1024                      AS Usado_MB,
    mg.queue_id,
    mg.wait_time_ms,
    DB_NAME(r.database_id)                      AS banco,
    SUBSTRING(qt.text,1,200)                    AS query,
    CASE
        WHEN mg.grant_time IS NULL
        THEN 'CRÍTICO — aguardando memória para iniciar'
        WHEN mg.used_memory_kb < mg.granted_memory_kb*0.3
        THEN 'ATENÇÃO — grant 70%+ desperdiçado (estatísticas velhas?)'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_exec_query_memory_grants mg
JOIN sys.dm_exec_requests r ON mg.session_id=r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) qt
ORDER BY mg.requested_memory_kb DESC

SELECT
    SUM(granted_memory_kb)/1024                 AS Total_Concedido_MB,
    SUM(used_memory_kb)/1024                    AS Total_Em_Uso_MB,
    COUNT(*)                                    AS Grants_Ativos,
    SUM(CASE WHEN grant_time IS NULL THEN 1 ELSE 0 END) AS Aguardando_Grant,
    CASE
        WHEN SUM(CASE WHEN grant_time IS NULL THEN 1 ELSE 0 END) > 5
        THEN 'CRÍTICO — fila de grants grande'
        WHEN SUM(CASE WHEN grant_time IS NULL THEN 1 ELSE 0 END) > 0
        THEN 'ATENÇÃO — há queries esperando memória'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_exec_query_memory_grants


-- ============================================================
-- SEÇÃO 15 — TEMPDB: USO E PRESSÃO
-- ============================================================
-- QUANDO USAR:
--   Lentidão geral, sorts lentos, ETL, relatórios,
--   TempDB crescendo rapidamente.
--
-- IMPORTÂNCIA:
--   TempDB é compartilhado por todas as sessões. Quando sob
--   pressão, afeta todo o servidor simultaneamente.
--
-- ONDE EXECUTAR: [tempdb] / [master]
--
-- O QUE ANALISAR:
--   UserObjects_MB alto     → muitas tabelas #temp
--   InternalObjects_MB alto → sort/hash spill para disco
--   VersionStore_MB alto    → transação longa aberta
--   Status                  → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE tempdb
GO

SELECT
    SUM(user_object_reserved_page_count)*8/1024      AS UserObjects_MB,
    SUM(internal_object_reserved_page_count)*8/1024  AS InternalObjects_MB,
    SUM(version_store_reserved_page_count)*8/1024    AS VersionStore_MB,
    SUM(unallocated_extent_page_count)*8/1024         AS Livre_MB,
    CASE
        WHEN SUM(internal_object_reserved_page_count)*8/1024 > 1000
        THEN 'CRÍTICO — spill detectado, queries sem memória'
        WHEN SUM(version_store_reserved_page_count)*8/1024 > 500
        THEN 'ATENÇÃO — version store alto, transação longa'
        WHEN SUM(user_object_reserved_page_count)*8/1024 > 2000
        THEN 'ATENÇÃO — muitas tabelas temporárias'
        ELSE 'OK'
    END                                              AS Status
FROM sys.dm_db_file_space_usage

USE master
GO

SELECT TOP 20
    tsu.session_id, s.login_name, s.host_name, s.program_name,
    r.wait_type,
    tsu.user_objects_alloc_page_count*8/1024    AS UserObjects_MB,
    tsu.internal_objects_alloc_page_count*8/1024 AS InternalObjects_MB,
    (tsu.user_objects_alloc_page_count+
     tsu.internal_objects_alloc_page_count)*8/1024 AS Total_MB,
    DB_NAME(r.database_id)                      AS banco,
    SUBSTRING(qt.text,1,200)                    AS query,
    CASE
        WHEN tsu.internal_objects_alloc_page_count*8/1024 > 500
        THEN 'CRÍTICO — spill > 500MB'
        WHEN (tsu.user_objects_alloc_page_count+
              tsu.internal_objects_alloc_page_count)*8/1024 > 200
        THEN 'ATENÇÃO — uso alto de TempDB'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_db_task_space_usage tsu
JOIN sys.dm_exec_sessions s ON tsu.session_id=s.session_id
LEFT JOIN sys.dm_exec_requests r ON tsu.session_id=r.session_id
                                 AND tsu.request_id=r.request_id
LEFT JOIN sys.dm_exec_sql_text(r.sql_handle) qt ON 1=1
WHERE tsu.user_objects_alloc_page_count>0
   OR tsu.internal_objects_alloc_page_count>0
ORDER BY Total_MB DESC


-- ============================================================
-- SEÇÃO 16 — MEMÓRIA E BUFFER POOL
-- ============================================================
-- QUANDO USAR:
--   Sistema lento com suspeita de swap de memória,
--   verificação de saúde, após configurar Max Memory.
--
-- IMPORTÂNCIA:
--   Sem limite de memória, SQL Server pode consumir toda
--   a RAM do servidor deixando o Windows instável.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   PLE < 300s          → CRÍTICO: memória insuficiente
--   PLE 300-1000s       → ATENÇÃO: monitorar
--   Max_Memory ilimitado→ CRÍTICO: risco de instabilidade
--   Status              → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT
    physical_memory_in_use_kb/1024          AS Memoria_SQL_MB,
    physical_memory_in_use_kb/1024/1024     AS Memoria_SQL_GB,
    memory_utilization_percentage           AS Utilizacao_Pct,
    CASE
        WHEN memory_utilization_percentage > 95
        THEN 'CRÍTICO — SQL > 95% do limite configurado'
        WHEN memory_utilization_percentage > 80
        THEN 'ATENÇÃO — uso de memória alto'
        ELSE 'OK'
    END                                     AS Status
FROM sys.dm_os_process_memory

SELECT
    cntr_value                              AS PLE_Segundos,
    CASE
        WHEN cntr_value < 300  THEN 'CRÍTICO — memória insuficiente'
        WHEN cntr_value < 1000 THEN 'ATENÇÃO — monitorar'
        ELSE 'OK'
    END                                     AS Status
FROM sys.dm_os_performance_counters
WHERE counter_name='Page life expectancy'
  AND object_name LIKE '%Buffer Manager%'

SELECT
    (SELECT value_in_use FROM sys.configurations
     WHERE name='max server memory (MB)')   AS Max_Memory_MB,
    physical_memory_in_use_kb/1024          AS Em_Uso_MB,
    CASE
        WHEN (SELECT value_in_use FROM sys.configurations
              WHERE name='max server memory (MB)') = 2147483647
        THEN 'CRÍTICO — sem limite, risco de instabilidade'
        ELSE 'OK'
    END                                     AS Status
FROM sys.dm_os_process_memory

SELECT DB_NAME(database_id) AS Banco, COUNT(*)*8/1024 AS MB_Cache,
    CASE WHEN COUNT(*)*8/1024 > 10000
         THEN 'ATENÇÃO — banco usando muito cache'
         ELSE 'OK'
    END                                     AS Status
FROM sys.dm_os_buffer_descriptors
WHERE database_id > 4
GROUP BY database_id
ORDER BY MB_Cache DESC


-- ============================================================
-- SEÇÃO 17 — I/O E LATÊNCIA DE DISCO
-- ============================================================
-- QUANDO USAR:
--   PAGEIOLATCH alto nos wait stats, lentidão em leitura,
--   WRITELOG alto (log lento).
--
-- IMPORTÂNCIA:
--   Latência > 20ms já impacta performance.
--   Identifica qual arquivo específico é o gargalo.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   avg_read_ms > 50ms  → CRÍTICO: leitura muito lenta
--   avg_read_ms > 20ms  → ATENÇÃO: leitura lenta
--   avg_write_ms > 20ms → ATENÇÃO: escrita lenta
--   Status              → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT
    DB_NAME(fs.database_id)                     AS Banco,
    mf.physical_name                            AS Arquivo,
    mf.type_desc,
    CASE WHEN fs.num_of_reads=0 THEN 0
         ELSE CAST(fs.io_stall_read_ms*1.0/fs.num_of_reads AS DECIMAL(10,2))
    END                                         AS avg_read_ms,
    CASE WHEN fs.num_of_writes=0 THEN 0
         ELSE CAST(fs.io_stall_write_ms*1.0/fs.num_of_writes AS DECIMAL(10,2))
    END                                         AS avg_write_ms,
    fs.num_of_reads, fs.num_of_writes,
    CAST(fs.num_of_bytes_read/1048576.0 AS DECIMAL(10,1))   AS MB_Lidos,
    CAST(fs.num_of_bytes_written/1048576.0 AS DECIMAL(10,1)) AS MB_Escritos,
    CASE
        WHEN fs.num_of_reads>0
         AND fs.io_stall_read_ms/fs.num_of_reads > 50
        THEN 'CRÍTICO — leitura > 50ms'
        WHEN fs.num_of_reads>0
         AND fs.io_stall_read_ms/fs.num_of_reads > 20
        THEN 'ATENÇÃO — leitura > 20ms'
        WHEN fs.num_of_writes>0
         AND fs.io_stall_write_ms/fs.num_of_writes > 50
        THEN 'CRÍTICO — escrita > 50ms'
        WHEN fs.num_of_writes>0
         AND fs.io_stall_write_ms/fs.num_of_writes > 20
        THEN 'ATENÇÃO — escrita > 20ms'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_io_virtual_file_stats(NULL,NULL) fs
JOIN sys.master_files mf ON fs.database_id=mf.database_id AND fs.file_id=mf.file_id
ORDER BY CASE WHEN fs.num_of_reads=0 THEN 0
              ELSE fs.io_stall_read_ms/fs.num_of_reads END DESC

-- Espaço em disco — todos os drives com arquivos SQL
-- CROSS APPLY garante que todos os drives (C:, E:, etc.) aparecem
SELECT DISTINCT
    vs.volume_mount_point                       AS Drive,
    vs.total_bytes/1024/1024/1024               AS Total_GB,
    vs.available_bytes/1024/1024/1024           AS Livre_GB,
    CAST(100.0*vs.available_bytes/vs.total_bytes
        AS DECIMAL(5,2))                        AS Pct_Livre,
    CASE
        WHEN vs.available_bytes*1.0/vs.total_bytes < 0.05
        THEN 'CRÍTICO — < 5% livre'
        WHEN vs.available_bytes*1.0/vs.total_bytes < 0.10
        THEN 'CRÍTICO — < 10% livre'
        WHEN vs.available_bytes*1.0/vs.total_bytes < 0.20
        THEN 'ATENÇÃO — < 20% livre'
        ELSE 'OK'
    END                                         AS Status
FROM sys.master_files mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) vs
ORDER BY Pct_Livre ASC


-- ============================================================
-- SEÇÃO 18 — ESTATÍSTICAS DESATUALIZADAS
-- ============================================================
-- QUANDO USAR:
--   Queries lentas com índices corretos, planos com estimativas
--   absurdas, após fechamento de folha de pagamento.
--
-- IMPORTÂNCIA:
--   Em muitos ambientes, estatísticas ruins causam mais
--   problemas que índices ausentes.
--
-- ONDE EXECUTAR: [banco específico]
--
-- O QUE ANALISAR:
--   Pct_Linhas_Alteradas > 20% → CRÍTICO: estatística velha
--   modification_counter alto  → muitas linhas mudaram
--   last_updated antiga        → não atualiza há muito tempo
--   Status                     → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE SRH_HM  -- TROQUE AQUI
GO

SELECT
    OBJECT_NAME(s.object_id)                    AS Tabela,
    s.name                                      AS Estatistica,
    sp.last_updated,
    sp.rows                                     AS Total_Linhas,
    sp.modification_counter                     AS Alteracoes,
    ROUND(100.0*sp.modification_counter/NULLIF(sp.rows,0),1) AS Pct_Linhas_Alteradas,
    'UPDATE STATISTICS '+QUOTENAME(OBJECT_NAME(s.object_id))+
    ' '+QUOTENAME(s.name)+' WITH FULLSCAN'      AS update_command,
    CASE
        WHEN sp.modification_counter > sp.rows*0.20
        THEN 'CRÍTICO — > 20% das linhas alteradas'
        WHEN sp.modification_counter > sp.rows*0.10
        THEN 'ATENÇÃO — > 10% das linhas alteradas'
        WHEN sp.modification_counter > 10000
        THEN 'ATENÇÃO — muitas modificações acumuladas'
        WHEN sp.last_updated < DATEADD(DAY,-7,GETDATE())
        THEN 'ATENÇÃO — não atualizada há mais de 7 dias'
        ELSE 'OK'
    END                                         AS Status
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id,s.stats_id) sp
WHERE OBJECT_NAME(s.object_id) IS NOT NULL AND sp.rows > 0
  AND (sp.modification_counter > 1000
       OR sp.last_updated < DATEADD(DAY,-7,GETDATE()))
ORDER BY sp.modification_counter DESC

EXEC sp_updatestats
EXEC sp_updatestats 'resample'  -- após fechamento de folha


-- ============================================================
-- SEÇÃO 19 — PLAN CACHE
-- ============================================================
-- QUANDO USAR:
--   CPU alta sem query óbvia, muitos planos single-use,
--   queries executadas com alta frequência.
--
-- IMPORTÂNCIA:
--   Queries sem parametrização geram plano novo para cada
--   execução, desperdiçando memória e CPU em compilações.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   Pct_Single_Use > 40% → CRÍTICO: parametrização ruim
--   usecounts alto        → impacto cumulativo alto
--   Status                → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT TOP 50
    cp.usecounts AS Execucoes, cp.size_in_bytes/1024 AS Cache_KB,
    cp.objtype AS Tipo, DB_NAME(qt.dbid) AS Banco,
    SUBSTRING(qt.text,1,200) AS Query,
    CASE
        WHEN cp.usecounts=1 THEN 'ATENÇÃO — single-use'
        WHEN cp.usecounts > 100000 THEN 'ATENÇÃO — alto volume'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) qt
WHERE cp.objtype IN ('Adhoc','Prepared','Proc') AND qt.dbid IS NOT NULL
ORDER BY cp.usecounts DESC

SELECT
    objtype AS Tipo, COUNT(*) AS Total_Planos,
    SUM(CASE WHEN usecounts=1 THEN 1 ELSE 0 END) AS Single_Use,
    CAST(100.0*SUM(CASE WHEN usecounts=1 THEN 1 ELSE 0 END)
        /COUNT(*) AS DECIMAL(5,1))              AS Pct_Single_Use,
    SUM(size_in_bytes)/1024/1024                AS Total_MB,
    CASE
        WHEN CAST(100.0*SUM(CASE WHEN usecounts=1 THEN 1 ELSE 0 END)
             /COUNT(*) AS DECIMAL(5,1)) > 40
        THEN 'CRÍTICO — ativar optimize for ad hoc workloads'
        WHEN CAST(100.0*SUM(CASE WHEN usecounts=1 THEN 1 ELSE 0 END)
             /COUNT(*) AS DECIMAL(5,1)) > 20
        THEN 'ATENÇÃO — muitos planos single-use'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_exec_cached_plans
WHERE objtype IN ('Adhoc','Prepared','Proc')
GROUP BY objtype
ORDER BY Total_Planos DESC


-- ============================================================
-- SEÇÃO 20 — BACKUP E TRANSACTION LOG
-- ============================================================
-- QUANDO USAR:
--   Verificação diária de rotina, investigação de log gigante,
--   auditoria de backup, após incidente de disco.
--
-- IMPORTÂNCIA:
--   Log crescendo sem backup pode encher o disco e derrubar
--   o servidor. Backup é a última linha de defesa.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   Horas_Desde_Full > 24h → backup atrasado
--   log_reuse_wait = LOG_BACKUP → backup de log pendente
--   Log_MB >> Dados_MB     → log crescendo sem controle
--   Status                 → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT
    database_name,
    MAX(CASE WHEN type='D' THEN backup_finish_date END) AS Ultimo_Full,
    MAX(CASE WHEN type='I' THEN backup_finish_date END) AS Ultimo_Diferencial,
    MAX(CASE WHEN type='L' THEN backup_finish_date END) AS Ultimo_Log,
    DATEDIFF(HOUR,MAX(CASE WHEN type='D' THEN backup_finish_date END),
             GETDATE())                             AS Horas_Desde_Full,
    CASE
        WHEN MAX(CASE WHEN type='D' THEN backup_finish_date END) IS NULL
        THEN 'CRÍTICO — nunca teve backup full'
        WHEN DATEDIFF(HOUR,MAX(CASE WHEN type='D' THEN backup_finish_date END),
             GETDATE()) > 48
        THEN 'CRÍTICO — último full > 48 horas'
        WHEN DATEDIFF(HOUR,MAX(CASE WHEN type='D' THEN backup_finish_date END),
             GETDATE()) > 24
        THEN 'ATENÇÃO — último full > 24 horas'
        ELSE 'OK'
    END                                             AS Status
FROM msdb.dbo.backupset
GROUP BY database_name
ORDER BY Horas_Desde_Full DESC

SELECT
    name AS Banco, recovery_model_desc AS Recovery,
    log_reuse_wait_desc AS Log_Aguardando,
    CASE
        WHEN log_reuse_wait_desc='LOG_BACKUP'
        THEN 'ATENÇÃO — backup de log pendente, log vai crescer'
        WHEN log_reuse_wait_desc='ACTIVE_TRANSACTION'
        THEN 'ATENÇÃO — transação longa aberta'
        WHEN log_reuse_wait_desc='NOTHING' THEN 'OK'
        ELSE 'VERIFICAR — '+log_reuse_wait_desc
    END                                             AS Status
FROM sys.databases WHERE state_desc='ONLINE' ORDER BY name

SELECT
    d.name AS Banco,
    SUM(CASE WHEN mf.type=0 THEN mf.size*8/1024 ELSE 0 END) AS Dados_MB,
    SUM(CASE WHEN mf.type=1 THEN mf.size*8/1024 ELSE 0 END) AS Log_MB,
    CASE
        WHEN SUM(CASE WHEN mf.type=1 THEN mf.size ELSE 0 END) >
             SUM(CASE WHEN mf.type=0 THEN mf.size ELSE 0 END)*2
        THEN 'CRÍTICO — log > 2x o tamanho dos dados'
        WHEN SUM(CASE WHEN mf.type=1 THEN mf.size ELSE 0 END) >
             SUM(CASE WHEN mf.type=0 THEN mf.size ELSE 0 END)
        THEN 'ATENÇÃO — log maior que dados'
        ELSE 'OK'
    END                                             AS Status
FROM sys.databases d
JOIN sys.master_files mf ON d.database_id=mf.database_id
WHERE d.state_desc='ONLINE'
GROUP BY d.name ORDER BY Log_MB DESC

-- ============================================================
-- SEÇÃO 21 — HEALTH CHECK: INTEGRIDADE DOS BANCOS
-- ============================================================
-- QUANDO USAR:
--   Mensalmente, após falha de disco, desligamento abrupto,
--   antes de migrations importantes.
--
-- IMPORTÂNCIA:
--   Corrupção silenciosa pode destruir dados sem avisar.
--   DBCC CHECKDB detecta antes que vire desastre.
--
-- ONDE EXECUTAR: [banco específico]
--
-- ⚠️ Pode demorar horas em bancos grandes.
--   Execute em janela de manutenção (madrugada).
--
-- O QUE ANALISAR:
--   Qualquer erro retornado → investigar imediatamente
--   Dias_Desde_CheckDB > 30 → CRÍTICO: verificação pendente
--   Status                  → OK / ATENÇÃO / CRÍTICO
-- ============================================================

DBCC CHECKDB ('SRH') WITH PHYSICAL_ONLY, NO_INFOMSGS
DBCC CHECKDB ('SRH_HM') WITH PHYSICAL_ONLY, NO_INFOMSGS
DBCC CHECKDB ('SRH') WITH NO_INFOMSGS  -- completo, mensal

USE master
GO
SELECT
    name AS Banco,
    CAST(DATABASEPROPERTYEX(name,'LastGoodCheckDbTime') AS DATETIME) AS Ultimo_CheckDB,
    DATEDIFF(DAY,
        CAST(DATABASEPROPERTYEX(name,'LastGoodCheckDbTime') AS DATETIME),
        GETDATE())                              AS Dias_Desde_CheckDB,
    CASE
        WHEN DATABASEPROPERTYEX(name,'LastGoodCheckDbTime') IS NULL
        THEN 'CRÍTICO — CHECKDB nunca executado'
        WHEN DATEDIFF(DAY,CAST(DATABASEPROPERTYEX(name,'LastGoodCheckDbTime')
             AS DATETIME),GETDATE()) > 30
        THEN 'CRÍTICO — mais de 30 dias sem verificação'
        WHEN DATEDIFF(DAY,CAST(DATABASEPROPERTYEX(name,'LastGoodCheckDbTime')
             AS DATETIME),GETDATE()) > 7
        THEN 'ATENÇÃO — mais de 7 dias'
        ELSE 'OK'
    END                                         AS Status
FROM sys.databases
WHERE state_desc='ONLINE' AND database_id>4
ORDER BY Dias_Desde_CheckDB DESC


-- ============================================================
-- SEÇÃO 22 — JOBS COM FALHA
-- ============================================================
-- QUANDO USAR:
--   Verificação diária de rotina.
--
-- IMPORTÂNCIA:
--   Jobs de backup e manutenção falham silenciosamente.
--   Você só descobre quando precisa do backup ou o disco enche.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   run_status=0  → job falhou
--   Mensagem      → descrição do erro
--   Status        → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT
    j.name AS Job, jh.step_name AS Passo,
    msdb.dbo.agent_datetime(jh.run_date,jh.run_time) AS Executado_Em,
    CASE jh.run_status
        WHEN 0 THEN 'FALHOU'
        WHEN 1 THEN 'OK'
        WHEN 2 THEN 'RETRY'
        WHEN 3 THEN 'CANCELADO'
    END                                         AS Resultado,
    LEFT(jh.message,500)                        AS Mensagem,
    CASE jh.run_status
        WHEN 0 THEN 'CRÍTICO — job falhou'
        WHEN 2 THEN 'ATENÇÃO — job fez retry'
        WHEN 3 THEN 'ATENÇÃO — job cancelado'
        ELSE 'OK'
    END                                         AS Status
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory jh ON j.job_id=jh.job_id
WHERE jh.run_status IN (0,2,3)
  AND msdb.dbo.agent_datetime(jh.run_date,jh.run_time)
      >= DATEADD(HOUR,-24,GETDATE())
ORDER BY msdb.dbo.agent_datetime(jh.run_date,jh.run_time) DESC


-- ============================================================
-- SEÇÃO 23 — CONFIGURAÇÕES CRÍTICAS DO SERVIDOR
-- ============================================================
-- QUANDO USAR:
--   Auditoria inicial, após incidentes, verificação mensal.
--
-- IMPORTÂNCIA:
--   Configurações padrão não são otimizadas para produção.
--   Corrigi-las resolve problemas sistêmicos de performance.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   max memory ilimitado   → CRÍTICO: risco de instabilidade
--   cost threshold = 5     → paralelismo excessivo
--   optimize for ad hoc=0  → cache desperdiçado
--   Auto-Shrink/Close = ON → degradação de performance
--   Status                 → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT
    name, value AS Configurado, value_in_use AS Em_Uso,
    CASE name
        WHEN 'max server memory (MB)' THEN
            CASE WHEN value_in_use=2147483647
                 THEN 'CRÍTICO — sem limite, risco de instabilidade'
                 ELSE 'OK' END
        WHEN 'cost threshold for parallelism' THEN
            CASE WHEN value_in_use < 25
                 THEN 'ATENÇÃO — valor baixo causa paralelismo excessivo'
                 ELSE 'OK' END
        WHEN 'optimize for ad hoc workloads' THEN
            CASE WHEN value_in_use=0
                 THEN 'ATENÇÃO — desativado, ativar para economizar cache'
                 ELSE 'OK' END
        WHEN 'xp_cmdshell' THEN
            CASE WHEN value_in_use=1
                 THEN 'ATENÇÃO — habilitado, verificar necessidade'
                 ELSE 'OK' END
        WHEN 'max degree of parallelism' THEN
            CASE WHEN value_in_use=0
                 THEN 'ATENÇÃO — MAXDOP 0, sem limite de paralelismo'
                 ELSE 'OK' END
        ELSE 'OK'
    END                                         AS Status
FROM sys.configurations
WHERE name IN (
    'max server memory (MB)','min server memory (MB)',
    'max degree of parallelism','cost threshold for parallelism',
    'optimize for ad hoc workloads','xp_cmdshell',
    'backup compression default','remote admin connections'
)
ORDER BY name

SELECT
    name AS Banco, recovery_model_desc AS Recovery,
    compatibility_level,
    is_auto_shrink_on AS Auto_Shrink,
    is_auto_close_on  AS Auto_Close,
    page_verify_option_desc AS Page_Verify,
    CASE
        WHEN is_auto_shrink_on=1
        THEN 'CRÍTICO — Auto-Shrink ON causa fragmentação severa'
        WHEN is_auto_close_on=1
        THEN 'CRÍTICO — Auto-Close ON degrada performance'
        WHEN page_verify_option_desc<>'CHECKSUM'
        THEN 'ATENÇÃO — Page Verify não é CHECKSUM'
        ELSE 'OK'
    END                                         AS Status
FROM sys.databases
WHERE database_id>4 ORDER BY name

SELECT
    @@SERVERNAME AS Servidor, cpu_count AS CPUs,
    physical_memory_kb/1024/1024 AS RAM_GB,
    sqlserver_start_time AS SQL_Iniciou_Em,
    DATEDIFF(DAY,sqlserver_start_time,GETDATE()) AS Dias_Uptime,
    CASE
        WHEN DATEDIFF(HOUR,sqlserver_start_time,GETDATE()) < 24
        THEN 'ATENÇÃO — reiniciado nas últimas 24h, DMVs zeradas'
        WHEN DATEDIFF(DAY,sqlserver_start_time,GETDATE()) < 7
        THEN 'ATENÇÃO — reiniciado nos últimos 7 dias'
        ELSE 'OK — uptime saudável'
    END                                         AS Status
FROM sys.dm_os_sys_info


-- ============================================================
-- SEÇÃO 24 — VLFs E CRESCIMENTO DO LOG
-- ============================================================
-- QUANDO USAR:
--   WRITELOG alto, recovery/restore demorado,
--   log crescendo rápido, auditoria inicial.
--
-- IMPORTÂNCIA:
--   Muitos VLFs fragmentam o transaction log, causando lentidão
--   em commits e em operações de recovery.
--
-- ONDE EXECUTAR: [master] / [banco específico]
--
-- O QUE ANALISAR:
--   VLF count > 1000 → CRÍTICO: fragmentação severa
--   VLF count > 200  → ATENÇÃO: monitorar
--   Status           → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT
    DB_NAME(database_id) AS Banco, COUNT(*) AS Total_VLFs,
    SUM(CASE WHEN vlf_active=1 THEN 1 ELSE 0 END) AS VLFs_Ativos,
    CASE
        WHEN COUNT(*) > 1000 THEN 'CRÍTICO — fragmentação severa do log'
        WHEN COUNT(*) > 200  THEN 'ATENÇÃO — VLFs acima do recomendado'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_db_log_info(NULL)
GROUP BY database_id
ORDER BY Total_VLFs DESC

USE SRH  -- TROQUE AQUI
GO
SELECT
    DB_NAME() AS Banco, COUNT(*) AS Total_VLFs,
    CAST(SUM(vlf_size_mb) AS DECIMAL(10,1)) AS Tamanho_Total_MB,
    CASE
        WHEN COUNT(*) > 1000 THEN 'CRÍTICO'
        WHEN COUNT(*) > 200  THEN 'ATENÇÃO'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_db_log_info(DB_ID())


-- ============================================================
-- SEÇÃO 25 — CRESCIMENTO DE ARQUIVOS (AUTOGROWTH)
-- ============================================================
-- QUANDO USAR:
--   Auditoria inicial, disco quase cheio, lentidão pontual
--   durante operações de escrita.
--
-- IMPORTÂNCIA:
--   Autogrowth pequeno ou percentual gera eventos frequentes
--   que travam temporariamente operações de escrita.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   Crescimento % em banco grande → CRÍTICO
--   Crescimento < 256MB para dados → ATENÇÃO
--   Status                         → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

SELECT
    DB_NAME(mf.database_id) AS Banco, mf.name AS Arquivo,
    mf.type_desc, mf.size*8/1024 AS Tamanho_MB,
    CASE mf.is_percent_growth
        WHEN 1 THEN CAST(mf.growth AS VARCHAR)+'%'
        ELSE CAST(mf.growth*8/1024 AS VARCHAR)+' MB'
    END                                         AS Autogrowth,
    mf.physical_name,
    CASE
        WHEN mf.is_percent_growth=1 AND mf.size*8/1024>10240
        THEN 'CRÍTICO — crescimento % em banco > 10GB'
        WHEN mf.is_percent_growth=1
        THEN 'ATENÇÃO — crescimento %, use MB fixo'
        WHEN mf.growth*8/1024<256 AND mf.type=0
        THEN 'ATENÇÃO — crescimento < 256MB para dados'
        WHEN mf.growth*8/1024<512 AND mf.type=1
        THEN 'ATENÇÃO — crescimento < 512MB para log'
        ELSE 'OK'
    END                                         AS Status
FROM sys.master_files mf
WHERE mf.database_id>4
ORDER BY CASE WHEN mf.is_percent_growth=1 THEN 0
              WHEN mf.growth*8/1024<256 THEN 1
              ELSE 2 END, DB_NAME(mf.database_id)


-- ============================================================
-- SEÇÃO 26 — INFRAESTRUTURA DE MONITORAMENTO CONTÍNUO
-- ============================================================
-- QUANDO USAR:
--   Configuração inicial — execute uma única vez.
--   Agende a procedure no SQL Agent a cada 5 minutos.
--
-- IMPORTÂNCIA:
--   Permite análise retroativa de incidentes. Quando o
--   problema já passou, o histórico está disponível.
--
-- ONDE EXECUTAR: [master] para criação, [DBA] para uso
-- ============================================================

USE master
GO
-- Banco DBA criado na Seção 28. Se ainda não existir, criar aqui:
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name='DBA')
    CREATE DATABASE DBA
GO
USE DBA
GO
IF OBJECT_ID('dbo.log_sessoes','U') IS NULL
CREATE TABLE dbo.log_sessoes (
    id INT IDENTITY(1,1) PRIMARY KEY,
    dt_coleta DATETIME2(0) NOT NULL DEFAULT GETDATE(),
    session_id SMALLINT, status NVARCHAR(30),
    blocking_session_id SMALLINT, cpu_time INT, elapsed_seg INT,
    logical_reads BIGINT, writes BIGINT,
    wait_type NVARCHAR(60), wait_seg INT,
    database_name NVARCHAR(128), login_name NVARCHAR(128),
    statement_text NVARCHAR(MAX)
)
GO
IF OBJECT_ID('dbo.log_waits','U') IS NULL
CREATE TABLE dbo.log_waits (
    id INT IDENTITY(1,1) PRIMARY KEY,
    dt_coleta DATETIME2(0) NOT NULL DEFAULT GETDATE(),
    wait_type NVARCHAR(60), waiting_tasks_count BIGINT,
    wait_time_ms BIGINT, signal_wait_time_ms BIGINT, pct_total DECIMAL(5,2)
)
GO
IF OBJECT_ID('dbo.log_bloqueios','U') IS NULL
CREATE TABLE dbo.log_bloqueios (
    id INT IDENTITY(1,1) PRIMARY KEY,
    dt_coleta DATETIME2(0) NOT NULL DEFAULT GETDATE(),
    blocking_session_id SMALLINT, blocked_session_id SMALLINT,
    wait_type NVARCHAR(60), wait_seg INT,
    blocker_query NVARCHAR(MAX), blocked_query NVARCHAR(MAX)
)
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_log_sessoes_dt')
    CREATE INDEX IX_log_sessoes_dt   ON dbo.log_sessoes  (dt_coleta)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_log_waits_dt')
    CREATE INDEX IX_log_waits_dt     ON dbo.log_waits    (dt_coleta,wait_type)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_log_bloqueios_dt')
    CREATE INDEX IX_log_bloqueios_dt ON dbo.log_bloqueios(dt_coleta)
GO

CREATE OR ALTER PROCEDURE dbo.usp_coletar_snapshot AS
BEGIN
    SET NOCOUNT ON
    DECLARE @dt DATETIME2(0)=GETDATE()
    INSERT INTO dbo.log_sessoes(dt_coleta,session_id,status,blocking_session_id,
        cpu_time,elapsed_seg,logical_reads,writes,wait_type,wait_seg,
        database_name,login_name,statement_text)
    SELECT @dt,r.session_id,r.status,r.blocking_session_id,r.cpu_time,
        r.total_elapsed_time/1000,r.logical_reads,r.writes,r.wait_type,
        r.wait_time/1000,DB_NAME(r.database_id),s.login_name,
        SUBSTRING(qt.text,(r.statement_start_offset/2)+1,
            ((CASE WHEN r.statement_end_offset=-1 THEN DATALENGTH(qt.text)
                   ELSE r.statement_end_offset END
              -r.statement_start_offset)/2)+1)
    FROM sys.dm_exec_requests r
    JOIN sys.dm_exec_sessions s ON r.session_id=s.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) qt
    WHERE r.session_id<>@@SPID AND s.is_user_process=1
    INSERT INTO dbo.log_waits(dt_coleta,wait_type,waiting_tasks_count,
        wait_time_ms,signal_wait_time_ms,pct_total)
    SELECT TOP 15 @dt,wait_type,waiting_tasks_count,wait_time_ms,
        signal_wait_time_ms,
        CAST(100.0*wait_time_ms/SUM(wait_time_ms) OVER() AS DECIMAL(5,2))
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN('SLEEP_TASK','LAZYWRITER_SLEEP','LOGMGR_QUEUE',
        'WAITFOR','XE_DISPATCHER_WAIT','CHECKPOINT_QUEUE')
    ORDER BY wait_time_ms DESC
    INSERT INTO dbo.log_bloqueios(dt_coleta,blocking_session_id,
        blocked_session_id,wait_type,wait_seg,blocker_query,blocked_query)
    SELECT @dt,blocking.session_id,blocked.session_id,blocked.wait_type,
        blocked.wait_time/1000,bt.text,bdt.text
    FROM sys.dm_exec_requests blocked
    JOIN sys.dm_exec_requests blocking
        ON blocked.blocking_session_id=blocking.session_id
    CROSS APPLY sys.dm_exec_sql_text(blocked.sql_handle)  bdt
    CROSS APPLY sys.dm_exec_sql_text(blocking.sql_handle) bt
    WHERE blocked.blocking_session_id>0
END
GO

-- Análise de histórico
SELECT CAST(dt_coleta AS DATE) AS Data, DATEPART(HOUR,dt_coleta) AS Hora,
    COUNT(DISTINCT session_id)                  AS Sessoes,
    MAX(cpu_time)                               AS Max_CPU_ms,
    COUNT(CASE WHEN blocking_session_id>0 THEN 1 END) AS Bloqueadas,
    CASE
        WHEN COUNT(CASE WHEN blocking_session_id>0 THEN 1 END) > 10
        THEN 'CRÍTICO — mais de 10 sessões bloqueadas nessa hora'
        WHEN MAX(cpu_time) > 300000
        THEN 'ATENÇÃO — pico de CPU alto nessa hora'
        WHEN COUNT(DISTINCT session_id) > 100
        THEN 'ATENÇÃO — mais de 100 sessões simultâneas'
        ELSE 'OK'
    END                                         AS Status
FROM DBA.dbo.log_sessoes
WHERE dt_coleta >= DATEADD(HOUR,-24,GETDATE())
GROUP BY CAST(dt_coleta AS DATE), DATEPART(HOUR,dt_coleta)
ORDER BY Data, Hora


-- ============================================================
-- SEÇÃO 27 — MANUTENÇÃO AUTOMATIZADA (OLA HALLENGREN)
-- ============================================================
-- QUANDO USAR:
--   Agendar como jobs no SQL Agent para execução automática.
--
-- IMPORTÂNCIA:
--   Decide sozinho REORGANIZE ou REBUILD baseado na
--   fragmentação real, registra em log e notifica em erro.
--
-- ONDE EXECUTAR: [master]
--
-- FREQUÊNCIA RECOMENDADA:
--   IndexOptimize  → todo domingo às 01:00
--   IntegrityCheck → primeiro domingo do mês às 02:00
-- ============================================================

USE master
GO

EXEC master.dbo.IndexOptimize
    @Databases='SRH_HM,SRH_QA,SRH',
    @FragmentationLow=NULL,
    @FragmentationMedium='INDEX_REORGANIZE',
    @FragmentationHigh='INDEX_REBUILD_OFFLINE',
    @FragmentationLevel1=10, @FragmentationLevel2=30,
    @MinNumberOfPages=100, @UpdateStatistics='ALL',
    @OnlyModifiedStatistics='Y', @LogToTable='Y'

EXEC master.dbo.DatabaseIntegrityCheck
    @Databases='USER_DATABASES', @CheckCommands='CHECKDB', @LogToTable='Y'

SELECT TOP 100
    DatabaseName, ObjectName AS Tabela, IndexName AS Indice,
    CommandType AS Acao, StartTime, EndTime,
    DATEDIFF(SECOND,StartTime,EndTime) AS Duracao_seg,
    ErrorNumber, ErrorMessage,
    CASE
        WHEN ErrorNumber IS NOT NULL THEN 'CRÍTICO — erro: '+ErrorMessage
        WHEN DATEDIFF(SECOND,StartTime,EndTime)>3600 THEN 'ATENÇÃO — > 1 hora'
        ELSE 'OK'
    END                                         AS Status
FROM master.dbo.CommandLog ORDER BY StartTime DESC

-- ============================================================
-- SEÇÃO 28 — VALIDAÇÃO DE ÍNDICES: BASELINE ANTES/DEPOIS
-- ============================================================
-- QUANDO USAR:
--   Sempre que criar novos índices em produção.
--   Captura métricas antes e compara depois para provar
--   (ou não) o impacto real dos índices criados.
--
-- IMPORTÂNCIA:
--   Sem baseline, não há como provar que um índice ajudou.
--   Permite decisões baseadas em dados reais, não suposições.
--
-- ONDE EXECUTAR: [master] / [DBA] / [banco específico]
--
-- ORDEM DE EXECUÇÃO:
--   PASSO 1 → Criar infraestrutura (apenas uma vez)
--   PASSO 2 → Baseline de uso dos índices (ANTES)
--   PASSO 3 → Baseline de fragmentação (ANTES)
--   PASSO 4 → Baseline de wait stats (ANTES)
--   >>> CRIAR OS ÍNDICES AQUI <<<
--   PASSO 5 → Snapshot pós-criação (24h e depois 7 dias)
--   PASSO 6 → Comparativo de uso (delta seeks/scans)
--   PASSO 7 → Comparativo de fragmentação
--   PASSO 8 → Comparativo de wait stats
--   PASSO 9 → Query Store — impacto em duração/CPU
--
-- O QUE ANALISAR:
--   delta_seeks alto   → índice sendo usado (bom)
--   delta_scans alto   → varreduras ainda dominam (problema)
--   delta_lookups > 10000 → INCLUDE faltando
--   delta_updates >> seeks → custo maior que benefício
--   Status             → OK / ATENÇÃO / CRÍTICO
-- ============================================================

-- PASSO 1: Criar infraestrutura (execute UMA única vez)
-- ONDE: [master]
USE master
GO
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name='DBA')
    CREATE DATABASE DBA
GO
USE DBA
GO
IF OBJECT_ID('DBA.dbo.baseline_indices','U') IS NULL
CREATE TABLE DBA.dbo.baseline_indices (
    id INT IDENTITY(1,1) PRIMARY KEY,
    fase VARCHAR(10) NOT NULL,  -- 'ANTES', '24H', '7DIAS'
    capturado_em DATETIME NOT NULL DEFAULT GETDATE(),
    tabela SYSNAME NOT NULL, indice SYSNAME NOT NULL,
    seeks BIGINT NOT NULL, scans BIGINT NOT NULL,
    lookups BIGINT NOT NULL, updates BIGINT NOT NULL,
    stats_desde DATETIME NULL
)
GO
IF OBJECT_ID('DBA.dbo.baseline_fragmentacao','U') IS NULL
CREATE TABLE DBA.dbo.baseline_fragmentacao (
    id INT IDENTITY(1,1) PRIMARY KEY,
    fase VARCHAR(10) NOT NULL,
    capturado_em DATETIME NOT NULL DEFAULT GETDATE(),
    tabela SYSNAME NOT NULL, indice SYSNAME NOT NULL,
    fragmentacao_pct DECIMAL(5,1) NOT NULL,
    page_count BIGINT NOT NULL, record_count BIGINT NOT NULL,
    page_splits BIGINT NOT NULL
)
GO
IF OBJECT_ID('DBA.dbo.baseline_waits','U') IS NULL
CREATE TABLE DBA.dbo.baseline_waits (
    id INT IDENTITY(1,1) PRIMARY KEY,
    fase VARCHAR(10) NOT NULL,
    capturado_em DATETIME NOT NULL DEFAULT GETDATE(),
    wait_type NVARCHAR(60) NOT NULL,
    wait_time_ms BIGINT NOT NULL, waiting_tasks BIGINT NOT NULL
)
GO

-- PASSO 2: Baseline de uso dos índices (execute ANTES de criar)
-- ONDE: [banco específico]
USE SRH  -- TROQUE AQUI
GO
INSERT INTO DBA.dbo.baseline_indices
    (fase,tabela,indice,seeks,scans,lookups,updates,stats_desde)
SELECT 'ANTES',OBJECT_NAME(i.object_id),i.name,
    ISNULL(s.user_seeks,0),ISNULL(s.user_scans,0),
    ISNULL(s.user_lookups,0),ISNULL(s.user_updates,0),
    (SELECT sqlserver_start_time FROM sys.dm_os_sys_info)
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats s
    ON i.object_id=s.object_id AND i.index_id=s.index_id
    AND s.database_id=DB_ID()
WHERE i.type_desc<>'HEAP' AND i.is_disabled=0
  AND OBJECT_NAME(i.object_id) IN (
    'ITENS','FOLHAS_SERVIDOR','PESSOAL',
    'PARCELA_CONSIGNACAO','FUNCIONAL'  -- TROQUE PARA SUAS TABELAS
)
SELECT * FROM DBA.dbo.baseline_indices WHERE fase='ANTES' ORDER BY tabela

-- PASSO 3: Baseline de fragmentação (execute ANTES)
-- ONDE: [banco específico]
INSERT INTO DBA.dbo.baseline_fragmentacao
    (fase,tabela,indice,fragmentacao_pct,page_count,record_count,page_splits)
SELECT 'ANTES',OBJECT_NAME(ips.object_id),i.name,
    CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,1)),
    ips.page_count,ips.record_count,ISNULL(os.leaf_allocation_count,0)
FROM sys.dm_db_index_physical_stats(DB_ID(),NULL,NULL,NULL,'SAMPLED') ips
JOIN sys.indexes i ON ips.object_id=i.object_id AND ips.index_id=i.index_id
LEFT JOIN sys.dm_db_index_operational_stats(DB_ID(),NULL,NULL,NULL) os
    ON ips.object_id=os.object_id AND ips.index_id=os.index_id
WHERE OBJECT_NAME(ips.object_id) IN (
    'ITENS','FOLHAS_SERVIDOR','PESSOAL',
    'PARCELA_CONSIGNACAO','FUNCIONAL'
) AND ips.page_count>1000
SELECT * FROM DBA.dbo.baseline_fragmentacao WHERE fase='ANTES' ORDER BY tabela

-- PASSO 4: Baseline de wait stats (execute ANTES)
-- ONDE: [master]
USE master
GO
INSERT INTO DBA.dbo.baseline_waits (fase,wait_type,wait_time_ms,waiting_tasks)
SELECT 'ANTES',wait_type,wait_time_ms,waiting_tasks_count
FROM sys.dm_os_wait_stats
WHERE wait_type IN('PAGEIOLATCH_SH','PAGEIOLATCH_EX','WRITELOG',
    'LCK_M_S','LCK_M_X','LCK_M_U','CXPACKET') AND wait_time_ms>0
SELECT * FROM DBA.dbo.baseline_waits WHERE fase='ANTES' ORDER BY wait_time_ms DESC

-- >>> CRIAR OS ÍNDICES AQUI <<<
-- Aguardar 24h (workload diário) ou 7 dias (ciclo completo de negócio)
-- Para folha de pagamento: aguardar 1 ciclo completo

-- PASSO 5: Snapshot pós-criação
-- Troque @fase: '24H' após 24h, '7DIAS' após 7 dias
-- ONDE: [banco específico]
USE SRH  -- TROQUE AQUI
GO
DECLARE @fase VARCHAR(10)='24H'  -- troque para '7DIAS'
INSERT INTO DBA.dbo.baseline_indices
    (fase,tabela,indice,seeks,scans,lookups,updates,stats_desde)
SELECT @fase,OBJECT_NAME(i.object_id),i.name,
    ISNULL(s.user_seeks,0),ISNULL(s.user_scans,0),
    ISNULL(s.user_lookups,0),ISNULL(s.user_updates,0),
    (SELECT sqlserver_start_time FROM sys.dm_os_sys_info)
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats s
    ON i.object_id=s.object_id AND i.index_id=s.index_id
    AND s.database_id=DB_ID()
WHERE i.type_desc<>'HEAP' AND i.is_disabled=0
  AND OBJECT_NAME(i.object_id) IN(
    'ITENS','FOLHAS_SERVIDOR','PESSOAL','PARCELA_CONSIGNACAO','FUNCIONAL')

-- PASSO 6: Comparativo de uso com delta real
-- ONDE: [DBA]
USE DBA
GO
DECLARE @fase_c VARCHAR(10)='7DIAS'
SELECT d.tabela, d.indice,
    d.seeks-a.seeks   AS delta_seeks,
    d.scans-a.scans   AS delta_scans,
    d.lookups-a.lookups AS delta_lookups,
    d.updates-a.updates AS delta_updates,
    CAST(ROUND((d.seeks-a.seeks)*1.0/NULLIF((d.updates-a.updates),0),2)
        AS DECIMAL(10,2))                       AS ratio_seek_periodo,
    CASE
        WHEN (d.seeks-a.seeks)>1000 AND (d.lookups-a.lookups)<1000
        THEN 'OK — índice funcionando bem'
        WHEN (d.seeks-a.seeks)>100
        THEN 'OK — utilizado, monitorar'
        WHEN (d.lookups-a.lookups)>10000
        THEN 'ATENÇÃO — lookups altos, adicionar INCLUDE'
        WHEN (d.scans-a.scans)>(d.seeks-a.seeks) AND (d.scans-a.scans)>1000
        THEN 'ATENÇÃO — scans dominam, revisar colunas'
        WHEN (d.seeks-a.seeks)=0 AND (d.updates-a.updates)>0
        THEN 'CRÍTICO — só custo de escrita, considerar remoção'
        WHEN (d.seeks-a.seeks)=0 AND (d.updates-a.updates)=0
        THEN 'ATENÇÃO — sem atividade, workload não passou'
        ELSE 'ATENÇÃO — pouco uso, aguardar mais tempo'
    END                                         AS Status
FROM DBA.dbo.baseline_indices d
JOIN DBA.dbo.baseline_indices a
    ON d.tabela=a.tabela AND d.indice=a.indice AND a.fase='ANTES'
WHERE d.fase=@fase_c
ORDER BY delta_seeks DESC
GO

-- PASSO 7: Comparativo de fragmentação
-- ONDE: [DBA]
USE DBA
GO
DECLARE @fase_f VARCHAR(10)='7DIAS'
SELECT d.tabela, d.indice,
    a.fragmentacao_pct AS frag_antes,
    d.fragmentacao_pct AS frag_depois,
    d.fragmentacao_pct-a.fragmentacao_pct AS delta_frag,
    d.page_splits-a.page_splits AS delta_page_splits,
    CASE
        WHEN (d.page_splits-a.page_splits)>10000
        THEN 'CRÍTICO — page splits altos, ajustar fillfactor'
        WHEN d.fragmentacao_pct>30 AND d.page_count>1000
        THEN 'CRÍTICO — REBUILD necessário'
        WHEN d.fragmentacao_pct BETWEEN 10 AND 30
        THEN 'ATENÇÃO — REORGANIZE recomendado'
        ELSE 'OK'
    END                                         AS Status
FROM DBA.dbo.baseline_fragmentacao d
JOIN DBA.dbo.baseline_fragmentacao a
    ON d.tabela=a.tabela AND d.indice=a.indice AND a.fase='ANTES'
WHERE d.fase=@fase_f
ORDER BY delta_page_splits DESC
GO

-- PASSO 8: Comparativo de wait stats
-- ONDE: [DBA]
USE DBA
GO
DECLARE @fase_w VARCHAR(10)='7DIAS'
SELECT d.wait_type,
    a.wait_time_ms AS antes_ms, d.wait_time_ms AS depois_ms,
    d.wait_time_ms-a.wait_time_ms AS delta_ms,
    CAST((d.wait_time_ms-a.wait_time_ms)*100.0
        /NULLIF(a.wait_time_ms,0) AS DECIMAL(8,1)) AS variacao_pct,
    CASE
        WHEN d.wait_type IN('PAGEIOLATCH_SH','PAGEIOLATCH_EX')
         AND (d.wait_time_ms-a.wait_time_ms)<0
        THEN 'OK — I/O melhorou'
        WHEN d.wait_type='CXPACKET'
         AND (d.wait_time_ms-a.wait_time_ms)<0
        THEN 'OK — paralelismo reduziu'
        WHEN d.wait_type IN('PAGEIOLATCH_SH','PAGEIOLATCH_EX')
         AND (d.wait_time_ms-a.wait_time_ms)>0
        THEN 'ATENÇÃO — I/O piorou'
        WHEN d.wait_type='WRITELOG'
         AND (d.wait_time_ms-a.wait_time_ms)>0
        THEN 'ATENÇÃO — log cresceu'
        WHEN d.wait_type LIKE 'LCK_M_%'
         AND (d.wait_time_ms-a.wait_time_ms)>0
        THEN 'ATENÇÃO — contenção de lock aumentou'
        ELSE 'OK — sem variação significativa'
    END                                         AS Status
FROM DBA.dbo.baseline_waits d
JOIN DBA.dbo.baseline_waits a
    ON d.wait_type=a.wait_type AND a.fase='ANTES'
WHERE d.fase=@fase_w
ORDER BY delta_ms DESC

-- PASSO 9: Query Store — impacto real
-- ONDE: [banco específico]
USE SRH  -- TROQUE AQUI
GO
SELECT TOP 20
    qt.query_sql_text,
    SUM(rs.count_executions)                    AS execucoes,
    ROUND(AVG(rs.avg_duration)/1000.0,2)        AS avg_duration_ms,
    ROUND(AVG(rs.avg_cpu_time)/1000.0,2)        AS avg_cpu_ms,
    CAST(AVG(rs.avg_logical_io_reads) AS BIGINT) AS avg_reads,
    COUNT(DISTINCT p.plan_id)                   AS plan_count,
    CASE
        WHEN COUNT(DISTINCT p.plan_id)>3
        THEN 'CRÍTICO — múltiplos planos'
        WHEN AVG(rs.avg_logical_io_reads)<1000  THEN 'OK — reads baixas'
        WHEN AVG(rs.avg_logical_io_reads)<10000 THEN 'ATENÇÃO — reads moderadas'
        ELSE 'CRÍTICO — reads muito altas'
    END                                         AS Status
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id=qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id=p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id=rs.plan_id
JOIN sys.query_store_runtime_stats_interval rsi
    ON rs.runtime_stats_interval_id=rsi.runtime_stats_interval_id
WHERE rsi.start_time>=DATEADD(DAY,-7,GETDATE())
  AND (qt.query_sql_text LIKE '%ITENS%'
    OR qt.query_sql_text LIKE '%FOLHAS_SERVIDOR%'
    OR qt.query_sql_text LIKE '%PESSOAL%'
    OR qt.query_sql_text LIKE '%FUNCIONAL%')
GROUP BY qt.query_sql_text, q.query_id
ORDER BY AVG(rs.avg_logical_io_reads) DESC


-- ============================================================
-- SEÇÃO 29 — PLAYBOOK DE INCIDENTE: SISTEMA LENTO / CPU 100%
-- ============================================================
-- QUANDO USAR:
--   O telefone tocou. Sistema lento, CPU alta, usuários
--   reclamando. Siga os 9 passos na ordem.
--
-- IMPORTÂNCIA:
--   Sequência estruturada que resolve 90% dos incidentes
--   em 5-10 minutos sem improviso.
--
-- ONDE EXECUTAR: Cada passo indica o banco correto.
-- TEMPO ESTIMADO: 5-10 minutos para diagnóstico completo.
-- ============================================================

-- PASSO 1: O que está rodando AGORA?
-- Procurar: cpu_time alto, blocking_session_id preenchido
-- ONDE: [master]
USE master
GO
EXEC sp_WhoIsActive

-- PASSO 2: Ver plano e locks das sessões problemáticas
-- Procurar: table scan no plano, bloqueios em cadeia
-- ONDE: [master]
EXEC sp_WhoIsActive
    @get_plans=1, @get_locks=1,
    @get_task_info=2, @find_block_leaders=1,
    @sort_order='[CPU] DESC'

-- PASSO 3: Diagnóstico rápido do momento (30 segundos)
-- Procurar: Finding Priority 1-10 = problema imediato
-- ONDE: [master]
EXEC sp_BlitzFirst @Seconds=30

-- PASSO 4: Qual query está consumindo mais CPU?
-- Procurar: query no topo com avg_cpu alto
-- ONDE: [master]
EXEC sp_BlitzCache @SortOrder='cpu', @Top=10

-- PASSO 5: Qual query está fazendo mais leitura?
-- Procurar: pode não ser a mesma da CPU
-- ONDE: [master]
EXEC sp_BlitzCache @SortOrder='reads', @Top=10

-- PASSO 6: Alguma query está consumindo muita memória?
-- Procurar: memory grant alto = possível RESOURCE_SEMAPHORE
-- ONDE: [master]
EXEC sp_BlitzCache @SortOrder='memory grant', @Top=10

-- PASSO 7: Há queries esperando memória?
-- Procurar: grant_time NULL = esperando na fila
-- ONDE: [master]
SELECT
    session_id,
    requested_memory_kb/1024    AS Solicitado_MB,
    granted_memory_kb/1024      AS Concedido_MB,
    wait_time_ms,
    queue_id,
    CASE WHEN grant_time IS NULL
         THEN 'CRÍTICO — aguardando memória'
         ELSE 'OK — memória concedida'
    END                         AS Status
FROM sys.dm_exec_query_memory_grants
ORDER BY requested_memory_kb DESC

-- PASSO 8: Qual o wait type dominante?
-- Procurar: wait no topo com pct_total alto
-- ONDE: [master]
SELECT TOP 10
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    CAST(100.0*wait_time_ms/SUM(wait_time_ms) OVER()
        AS DECIMAL(5,2))        AS pct_total,
    CAST(100.0*signal_wait_time_ms/NULLIF(wait_time_ms,0)
        AS DECIMAL(5,2))        AS pct_signal,
    CASE
        WHEN wait_type IN('PAGEIOLATCH_SH','PAGEIOLATCH_EX')
        THEN 'Disco/índice → Seção 08 e 09'
        WHEN wait_type IN('CXPACKET','CXSYNC_PORT')
        THEN 'Paralelismo → ajustar cost threshold=50'
        WHEN wait_type='SOS_SCHEDULER_YIELD'
        THEN 'CPU sobrecarregada → otimizar queries'
        WHEN wait_type='WRITELOG'
        THEN 'Log lento → verificar disco do .ldf'
        WHEN wait_type='RESOURCE_SEMAPHORE'
        THEN 'Falta memória → Seção 14 e 16'
        WHEN wait_type LIKE 'LCK_M_%'
        THEN 'Blocking → repetir Passos 1 e 2'
        WHEN wait_type='ASYNC_NETWORK_IO'
        THEN 'Cliente lento → verificar aplicação'
        ELSE 'Verificar documentação'
    END                         AS Acao_Recomendada,
    CASE
        WHEN CAST(100.0*wait_time_ms/SUM(wait_time_ms) OVER()
             AS DECIMAL(5,2))>30 THEN 'CRÍTICO — domina os waits'
        WHEN CAST(100.0*wait_time_ms/SUM(wait_time_ms) OVER()
             AS DECIMAL(5,2))>10 THEN 'ATENÇÃO'
        ELSE 'OK'
    END                         AS Status
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN(
    'SLEEP_TASK','LAZYWRITER_SLEEP','LOGMGR_QUEUE',
    'WAITFOR','XE_DISPATCHER_WAIT','XE_TIMER_EVENT',
    'BROKER_EVENTHANDLER','CHECKPOINT_QUEUE')
ORDER BY wait_time_ms DESC

-- PASSO 9: Problema já passou? Usar Query Store
-- Usar quando incidente ocorreu horas atrás e DMVs já limparam
-- ONDE: [banco específico da aplicação]
USE SRH  -- TROQUE AQUI
GO
SELECT TOP 20
    qt.query_sql_text,
    SUM(rs.count_executions)                    AS execucoes,
    ROUND(AVG(rs.avg_duration)/1000.0,2)        AS avg_duration_ms,
    ROUND(AVG(rs.avg_cpu_time)/1000.0,2)        AS avg_cpu_ms,
    MAX(rs.last_execution_time)                 AS ultima_execucao,
    CASE
        WHEN AVG(rs.avg_duration)/1000.0>5000 THEN 'CRÍTICO — > 5s'
        WHEN AVG(rs.avg_duration)/1000.0>1000 THEN 'ATENÇÃO — > 1s'
        ELSE 'OK'
    END                                         AS Status
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id=qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id=p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id=rs.plan_id
JOIN sys.query_store_runtime_stats_interval rsi
    ON rs.runtime_stats_interval_id=rsi.runtime_stats_interval_id
WHERE rsi.start_time>=DATEADD(HOUR,-4,GETDATE())
GROUP BY qt.query_sql_text, q.query_id
ORDER BY AVG(rs.avg_duration) DESC


/*
==============================================================
RESUMO RÁPIDO DO PLAYBOOK — COPIE PARA O SSMS
==============================================================

SISTEMA LENTO — EXECUTE NA ORDEM:

Passo 1 → EXEC sp_WhoIsActive
Passo 2 → EXEC sp_WhoIsActive @get_plans=1,@get_locks=1,@find_block_leaders=1
Passo 3 → EXEC sp_BlitzFirst @Seconds=30
Passo 4 → EXEC sp_BlitzCache @SortOrder='cpu',         @Top=10
Passo 5 → EXEC sp_BlitzCache @SortOrder='reads',       @Top=10
Passo 6 → EXEC sp_BlitzCache @SortOrder='memory grant',@Top=10
Passo 7 → SELECT * FROM sys.dm_exec_query_memory_grants
Passo 8 → SELECT TOP 10 wait_type, pct_total ... ORDER BY wait_time_ms DESC
Passo 9 → Query Store (USE banco_aplicacao) — se problema já passou

INTERPRETAÇÃO DO WAIT DOMINANTE:
  PAGEIOLATCH   → Seção 08 (índice) ou Seção 09 (fragmentação)
  CXPACKET      → Ajustar cost threshold for parallelism = 50
  SOS_SCHEDULER → CPU sobrecarregada, Seção 04
  WRITELOG      → Disco do log lento, Seção 17
  RESOURCE_SEMAPHORE → Falta memória, Seção 14 e 16
  LCK_M_*       → Blocking, Seção 06, repetir Passos 1 e 2
  ASYNC_NETWORK → Aplicação lenta consumindo resultado
==============================================================
*/

-- ============================================================
-- FIM DO ARQUIVO — VERSÃO 3.0 FINAL
-- 29 seções | Padrão consistente em todas as seções:
-- QUANDO USAR / IMPORTÂNCIA / ONDE EXECUTAR /
-- O QUE ANALISAR / coluna Status (OK/ATENÇÃO/CRÍTICO)
-- ============================================================


-- ============================================================
-- ============================================================
-- SEÇÃO 30 — ESTATÍSTICAS E CARDINALIDADE
-- ============================================================
-- QUANDO USAR:
--   Query lenta mesmo com índice correto e estatística
--   "atualizada". Plano de execução com estimativa absurda
--   (estimou 1 linha, processou 100.000). Após fechamento
--   de folha ou importação em massa. Quando UPDATE STATISTICS
--   simples não resolve a lentidão.
--
-- IMPORTÂNCIA:
--   Estatísticas são as "estimativas" que o otimizador usa
--   para escolher o plano de execução. Quando erradas, ele
--   toma decisões ruins — escolhe Nested Loop em vez de
--   Hash Join, usa índice errado, faz table scan.
--   No banco SRH (folha de pagamento), dados concentrados
--   por mês/competência/matrícula são o cenário exato onde
--   cardinalidade ruim causa mais dano.
--
-- ONDE EXECUTAR: [banco específico]
--
-- CONCEITOS IMPORTANTES:
--   Cardinalidade → estimativa de quantas linhas uma operação
--                   retorna. Se errada, o plano inteiro é ruim.
--   Histograma    → tabela interna que descreve a distribuição
--                   dos valores de uma coluna (os STEPS).
--   Skew de dados → distribuição desigual: 90% dos registros
--                   têm o mesmo valor. Estatística "atualizada"
--                   mas histograma não representa bem a realidade.
--
-- O QUE ANALISAR:
--   modification_counter alto    → estatística desatualizada
--   Pct_Amostrado baixo          → amostra pequena = imprecisa
--   RANGE_HI_KEY com poucos STEPS→ histograma grosseiro
--   EQ_ROWS / RANGE_ROWS grandes → muitas linhas por bucket
--   Estimado vs Real no plano    → diferença indica cardinalidade ruim
--   Status                       → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE SRH_HM  -- TROQUE AQUI
GO


-- ─────────────────────────────────────────────────────────────
-- 30A — DIAGNÓSTICO GERAL DE ESTATÍSTICAS
-- Identifica as estatísticas mais desatualizadas com contexto
-- completo para decisão de atualização.
-- ─────────────────────────────────────────────────────────────
SELECT
    OBJECT_NAME(s.object_id)                    AS Tabela,
    s.name                                      AS Estatistica,
    s.auto_created                              AS Auto_Criada,
    s.user_created                              AS Criada_Manualmente,
    s.has_filter                                AS Filtrada,
    s.filter_definition                         AS Filtro,
    sp.last_updated                             AS Ultima_Atualizacao,
    sp.rows                                     AS Total_Linhas,
    sp.rows_sampled                             AS Linhas_Amostradas,
    ROUND(100.0 * sp.rows_sampled
        / NULLIF(sp.rows, 0), 1)                AS Pct_Amostrado,
    sp.steps                                    AS Steps_Histograma,
    -- Steps baixos = histograma grosseiro = estimativas ruins
    sp.modification_counter                     AS Modificacoes,
    ROUND(100.0 * sp.modification_counter
        / NULLIF(sp.rows, 0), 1)                AS Pct_Linhas_Alteradas,
    -- Comando de atualização gerado automaticamente
    'UPDATE STATISTICS ' +
    QUOTENAME(OBJECT_NAME(s.object_id)) +
    ' ' + QUOTENAME(s.name)                     AS update_simples,
    'UPDATE STATISTICS ' +
    QUOTENAME(OBJECT_NAME(s.object_id)) +
    ' ' + QUOTENAME(s.name) +
    ' WITH FULLSCAN'                            AS update_fullscan,
    CASE
        WHEN sp.modification_counter > sp.rows * 0.30
        THEN 'CRÍTICO — > 30% das linhas alteradas, atualizar urgente'
        WHEN sp.modification_counter > sp.rows * 0.20
        THEN 'CRÍTICO — > 20% alteradas, atualizar antes do próximo uso'
        WHEN sp.modification_counter > sp.rows * 0.10
        THEN 'ATENÇÃO — > 10% alteradas, monitorar'
        WHEN sp.rows_sampled * 1.0 / NULLIF(sp.rows, 0) < 0.10
         AND sp.rows > 100000
        THEN 'ATENÇÃO — amostra < 10% em tabela grande, considerar FULLSCAN'
        WHEN sp.steps < 10 AND sp.rows > 50000
        THEN 'ATENÇÃO — histograma com poucos steps, distribuição mal representada'
        WHEN sp.last_updated < DATEADD(DAY, -14, GETDATE())
        THEN 'ATENÇÃO — não atualizada há mais de 14 dias'
        ELSE 'OK'
    END                                         AS Status
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECT_NAME(s.object_id) IS NOT NULL
  AND sp.rows > 1000  -- ignora tabelas pequenas
  AND (
    sp.modification_counter > sp.rows * 0.10
    OR sp.rows_sampled * 1.0 / NULLIF(sp.rows, 0) < 0.10
    OR sp.steps < 10
    OR sp.last_updated < DATEADD(DAY, -14, GETDATE())
  )
ORDER BY
    CASE
        WHEN sp.modification_counter > sp.rows * 0.20 THEN 1
        WHEN sp.modification_counter > sp.rows * 0.10 THEN 2
        WHEN sp.rows_sampled * 1.0 / NULLIF(sp.rows,0) < 0.10 THEN 3
        ELSE 4
    END,
    sp.modification_counter DESC


-- ─────────────────────────────────────────────────────────────
-- 30B — LER O HISTOGRAMA (DBCC SHOW_STATISTICS)
-- O diagnóstico mais direto de cardinalidade ruim.
-- Execute para a coluna que aparece no WHERE da query lenta.
--
-- COMO USAR:
--   1. Identifique a query lenta e a coluna do WHERE
--   2. Execute DBCC SHOW_STATISTICS com essa tabela e estatística
--   3. Analise o resultado conforme o guia abaixo
--
-- O QUE ANALISAR NOS 3 RESULTADOS RETORNADOS:
--
--   Resultado 1 — Cabeçalho:
--     Updated        → quando foi atualizada pela última vez
--     Rows           → total de linhas da tabela
--     Rows Sampled   → quantas foram amostradas
--     Steps          → número de buckets no histograma (máx 200)
--     Density        → 1/valores_distintos; baixo = boa seletividade
--
--   Resultado 2 — Density Vector (para índices compostos):
--     All density    → densidade de cada prefixo de colunas
--     Columns        → colunas incluídas nesse prefixo
--     Baixo = seletivo (bom). Alto = pouca distinção (ruim)
--
--   Resultado 3 — Histograma (o mais importante):
--     RANGE_HI_KEY   → valor máximo do bucket
--     RANGE_ROWS     → linhas estimadas NO intervalo
--     EQ_ROWS        → linhas estimadas IGUAIS ao valor
--     DISTINCT_RANGE_ROWS → valores distintos no intervalo
--     AVG_RANGE_ROWS → média de linhas por valor no intervalo
--
--   SINAIS DE CARDINALIDADE RUIM NO HISTOGRAMA:
--     Poucos STEPS com EQ_ROWS/RANGE_ROWS muito altos
--     → muitas linhas comprimidas em poucos buckets
--     → estimativa grosseira para valores intermediários
--
--     AVG_RANGE_ROWS muito alto
--     → SQL assume média para valores não listados no histograma
--     → se o valor real tem distribuição diferente da média = erro
--
--     Valor buscado não aparece como RANGE_HI_KEY
--     → estimativa usa AVG_RANGE_ROWS (pode ser muito errada)
-- ─────────────────────────────────────────────────────────────

-- Exemplo: ver histograma da coluna cod_servidor na tabela ITENS
-- Troque o nome da tabela e da estatística conforme necessário
DBCC SHOW_STATISTICS ('dbo.ITENS', 'IX_ITENS_cod_folha_servidor')
    WITH HISTOGRAM

-- Ver apenas o cabeçalho (resumo rápido)
DBCC SHOW_STATISTICS ('dbo.ITENS', 'IX_ITENS_cod_folha_servidor')
    WITH STAT_HEADER

-- Ver apenas o density vector (para índices compostos)
DBCC SHOW_STATISTICS ('dbo.ITENS', 'IX_ITENS_cod_folha_servidor')
    WITH DENSITY_VECTOR

-- Ver tudo de uma vez (cabeçalho + density + histograma)
DBCC SHOW_STATISTICS ('dbo.ITENS', 'IX_ITENS_cod_folha_servidor')


-- ─────────────────────────────────────────────────────────────
-- 30C — COMPARAR ESTIMADO vs REAL NO PLANO DE EXECUÇÃO
-- Confirma se a cardinalidade está causando o problema.
-- Execute a query suspeita com SET STATISTICS PROFILE ON
-- e compare as colunas EstimateRows vs Rows.
-- ─────────────────────────────────────────────────────────────

-- Habilitar coleta de estimativas vs real
SET STATISTICS PROFILE ON
GO

-- Cole aqui a query suspeita e execute
-- SELECT ... FROM dbo.ITENS WHERE cod_folha_servidor = 12345

SET STATISTICS PROFILE OFF
GO

-- O QUE ANALISAR:
-- EstimateRows muito diferente de Rows = cardinalidade ruim
-- Exemplos de problema:
--   EstimateRows=1,    Rows=50000  → subestimou gravemente
--   EstimateRows=90000, Rows=10    → superestimou gravemente
-- Ambos os casos levam o otimizador a escolher o plano errado.


-- ─────────────────────────────────────────────────────────────
-- 30D — QUANDO UPDATE STATISTICS NÃO RESOLVE
-- E o que fazer em cada situação
-- ─────────────────────────────────────────────────────────────

/*
SITUAÇÃO 1: Estatística "atualizada" mas query ainda lenta
────────────────────────────────────────────────────────────
Causa provável: SKEW DE DADOS
O histograma representa a média da distribuição, mas o valor
específico sendo buscado tem distribuição muito diferente da média.

Exemplo real (folha de pagamento):
  Tabela ITENS com 1 milhão de linhas.
  Coluna mes_referencia: 95% dos registros são do mês atual.
  UPDATE STATISTICS atualiza com amostra de 30% → histograma ok.
  Query filtra WHERE mes_referencia = '2026-06' → SQL estima 300
  linhas (baseado na média), encontra 950.000 → plano errado.

Solução:
  1. UPDATE STATISTICS com FULLSCAN (lê 100% das linhas)
  2. Se ainda não resolver: estatística filtrada (ver 30E)
  3. Se ainda não resolver: OPTION (RECOMPILE) na query
     (força recompilação a cada execução, usando parâmetros reais)

SITUAÇÃO 2: Query com parâmetro — funciona rápido às vezes,
lento outras vezes (parameter sniffing)
────────────────────────────────────────────────────────────
Causa: o plano foi compilado com um valor de parâmetro e está
sendo reutilizado para valores com distribuição totalmente diferente.

Exemplo:
  EXEC usp_busca_itens @cod_servidor = 1    → 5 linhas → plano A
  EXEC usp_busca_itens @cod_servidor = 9999 → 80.000 linhas → plano A
  Plano A foi otimizado para 5 linhas → lento para 9999

Soluções em ordem de impacto:
  a) OPTION (OPTIMIZE FOR UNKNOWN) na query
     → ignora o parâmetro recebido, usa média estatística
  b) OPTION (RECOMPILE) na query
     → compila um plano novo a cada execução (custo de CPU)
  c) Procedure com OPTION (RECOMPILE) no nível da procedure
  d) Splitar em duas procedures: uma para volumes pequenos,
     outra para volumes grandes

SITUAÇÃO 3: Histograma com poucos steps (< 50 para tabela grande)
────────────────────────────────────────────────────────────
Causa: SQL Server limita o histograma a 200 steps máximo.
Em tabelas com muitos valores distintos, cada bucket agrega
muitos valores e a estimativa fica grosseira.

Solução: estatística filtrada (ver 30E) para os subconjuntos
mais consultados (ex: apenas registros do mês atual).
*/


-- ─────────────────────────────────────────────────────────────
-- 30E — ESTATÍSTICAS FILTRADAS
-- Para colunas com distribuição desigual (skew de dados).
-- Cria uma estatística que representa apenas um subconjunto
-- dos dados — muito mais precisa para queries com filtro fixo.
--
-- QUANDO USAR:
--   Coluna com distribuição muito concentrada em poucos valores
--   (ex: 90% dos registros com mes_referencia = mês atual)
--   e UPDATE STATISTICS FULLSCAN ainda não resolve.
--
-- ONDE EXECUTAR: [banco específico]
-- ─────────────────────────────────────────────────────────────

-- Criar estatística filtrada para registros do ano atual
-- ⚠️ O WHERE em CREATE STATISTICS aceita apenas expressões simples
--    (comparações diretas de coluna com valor literal).
--    Subqueries NÃO são suportadas no filtro.
--
-- Exemplo correto: filtrar por coluna com valor direto
CREATE STATISTICS stat_ITENS_ano_2026
ON dbo.ITENS (cod_folha_servidor)
WHERE cod_folha_servidor >= 100000  -- AJUSTE: use o menor cod_folha_servidor do ano
WITH FULLSCAN
GO

-- Outro exemplo: filtrar por coluna de data diretamente na tabela
-- (quando a coluna de filtro existe na própria tabela)
-- CREATE STATISTICS stat_FOLHA_2026
-- ON dbo.FOLHAS_SERVIDOR (cod_servidor)
-- WHERE ano = 2026
-- WITH FULLSCAN
-- GO

-- Verificar estatísticas filtradas existentes
SELECT
    OBJECT_NAME(s.object_id)                    AS Tabela,
    s.name                                      AS Estatistica,
    s.filter_definition                         AS Filtro,
    sp.last_updated,
    sp.rows,
    sp.steps                                    AS Steps_Histograma,
    CASE
        WHEN sp.last_updated < DATEADD(DAY, -7, GETDATE())
        THEN 'ATENÇÃO — estatística filtrada desatualizada'
        ELSE 'OK'
    END                                         AS Status
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.has_filter = 1
  AND OBJECT_NAME(s.object_id) IS NOT NULL
ORDER BY OBJECT_NAME(s.object_id), s.name


-- ─────────────────────────────────────────────────────────────
-- 30F — ATUALIZAÇÃO DE ESTATÍSTICAS: QUANDO E COMO
-- Guia de decisão baseado na situação
-- ─────────────────────────────────────────────────────────────

-- OPÇÃO 1: Atualização rápida — só tabelas com modificações
-- Usa amostragem padrão do SQL Server
-- Impacto baixo. Seguro rodar em horário comercial.
-- ONDE: [banco específico]
EXEC sp_updatestats

-- OPÇÃO 2: Atualização com reamostragem
-- Força nova amostragem em todas as estatísticas
-- Impacto moderado. Preferir fora do horário de pico.
EXEC sp_updatestats 'resample'

-- OPÇÃO 3: Atualização com leitura completa (FULLSCAN)
-- Lê 100% das linhas — mais preciso, mais lento
-- ⚠️ Em tabelas grandes pode demorar minutos e gerar carga
-- Usar após fechamento de folha ou importações em massa
-- Executar tabela por tabela para controlar o impacto
UPDATE STATISTICS dbo.ITENS WITH FULLSCAN
UPDATE STATISTICS dbo.FOLHAS_SERVIDOR WITH FULLSCAN
UPDATE STATISTICS dbo.VALORES_FOLHA WITH FULLSCAN

-- OPÇÃO 4: Tabela específica, estatística específica
-- Mais cirúrgico — atualiza só o que identificou como problema
UPDATE STATISTICS dbo.ITENS IX_ITENS_cod_folha_servidor WITH FULLSCAN

-- OPÇÃO 5: Via Ola Hallengren (recomendado para rotina)
-- Já faz a decisão automática de sample vs fullscan
-- baseado no tamanho da tabela e nas modificações acumuladas
USE master
GO
EXEC master.dbo.IndexOptimize
    @Databases              = 'SRH_HM',
    @UpdateStatistics       = 'ALL',
    @OnlyModifiedStatistics = 'Y',
    @StatisticsSample       = 100,   -- 100 = FULLSCAN
    @LogToTable             = 'Y'


-- ─────────────────────────────────────────────────────────────
-- 30G — CHECKLIST DE DIAGNÓSTICO DE CARDINALIDADE
-- Siga esta ordem quando suspeitar de problema de estatística
-- ─────────────────────────────────────────────────────────────

/*
PASSO 1: Confirmar que é problema de cardinalidade
  → Executar a query com SET STATISTICS PROFILE ON
  → Comparar EstimateRows vs Rows no plano
  → Se diferença > 10x: cardinalidade confirmada

PASSO 2: Verificar status da estatística (script 30A acima)
  → modification_counter / rows > 20% → atualizar primeiro

PASSO 3: Atualizar e testar
  → UPDATE STATISTICS tabela coluna WITH FULLSCAN
  → Executar a query novamente
  → Verificar se EstimateRows melhorou

PASSO 4: Se ainda não resolveu — ler o histograma (script 30B)
  → DBCC SHOW_STATISTICS com HISTOGRAM
  → Verificar se o valor buscado aparece como RANGE_HI_KEY
  → Verificar AVG_RANGE_ROWS — é representativo?

PASSO 5: Se o histograma está ok mas a query ainda é lenta
  → Suspeita de parameter sniffing
  → Testar com OPTION (RECOMPILE) na query
  → Se resolver: implementar solução definitiva (ver 30D)

PASSO 6: Se é problema de skew confirmado
  → Criar estatística filtrada (script 30E)
  → Ou usar OPTION (OPTIMIZE FOR UNKNOWN)

RESULTADOS ESPERADOS:
  Status OK      → estatística saudável, não é o problema
  ATENÇÃO        → atualizar com sp_updatestats resample
  CRÍTICO        → atualizar com FULLSCAN antes da próxima execução
                   da rotina crítica (ex: fechamento de folha)
*/

-- SEÇÃO 31 — HISTÓRICO DE CRESCIMENTO DO BANCO
-- ============================================================
-- QUANDO USAR:
--   Planejamento de capacidade, disco quase cheio sem causa
--   óbvia, previsão de quando será necessário expandir.
--   Ideal para reuniões de infra e relatórios mensais.
--
-- IMPORTÂNCIA:
--   Monitorar o tamanho atual não basta — você precisa saber
--   a velocidade de crescimento para agir antes de uma crise.
--   Um banco que cresce 5GB/mês precisa de ação diferente
--   de um que cresce 5GB/ano.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   BackupGB crescendo rapidamente → planejar expansão de disco
--   Pico em determinado mês        → correlacionar com evento
--                                    (fechamento de folha, importação)
--   Delta_GB alto entre backups    → crescimento acelerado
--   Status                         → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

-- Evolução do tamanho por banco via histórico de backup
-- Cada backup full registra o tamanho real do banco naquele momento
SELECT
    database_name,
    backup_finish_date,
    CAST(backup_size/1024.0/1024/1024 AS DECIMAL(10,2))            AS BackupGB,
    CAST(compressed_backup_size/1024.0/1024/1024 AS DECIMAL(10,2)) AS ComprimidoGB,
    CAST(100.0*(1 - compressed_backup_size*1.0/NULLIF(backup_size,0))
        AS DECIMAL(5,1))                                            AS Compressao_Pct,
    -- Delta em relação ao backup anterior do mesmo banco
    CAST((backup_size -
        LAG(backup_size) OVER (
            PARTITION BY database_name ORDER BY backup_finish_date)
        )/1024.0/1024/1024 AS DECIMAL(10,2))                        AS Crescimento_GB,
    CASE
        WHEN (backup_size -
              LAG(backup_size) OVER (
                  PARTITION BY database_name ORDER BY backup_finish_date)
             )/1024.0/1024/1024 > 10
        THEN 'CRÍTICO — cresceu mais de 10GB desde o último backup'
        WHEN (backup_size -
              LAG(backup_size) OVER (
                  PARTITION BY database_name ORDER BY backup_finish_date)
             )/1024.0/1024/1024 > 5
        THEN 'ATENÇÃO — cresceu mais de 5GB'
        ELSE 'OK'
    END                                                             AS Status
FROM msdb.dbo.backupset
WHERE type = 'D'  -- apenas Full backup
  AND backup_finish_date >= DATEADD(MONTH, -6, GETDATE())
ORDER BY database_name, backup_finish_date DESC

-- Resumo: tamanho médio mensal por banco (últimos 6 meses)
SELECT
    database_name,
    YEAR(backup_finish_date)                    AS Ano,
    MONTH(backup_finish_date)                   AS Mes,
    CAST(MAX(backup_size/1024.0/1024/1024)
        AS DECIMAL(10,2))                       AS MaxGB_no_Mes,
    COUNT(*)                                    AS Qtd_Backups,
    CAST(MAX(backup_size/1024.0/1024/1024) -
        MIN(backup_size/1024.0/1024/1024)
        AS DECIMAL(10,2))                       AS Variacao_GB_no_Mes,
    CASE
        WHEN MAX(backup_size/1024.0/1024/1024) -
             MIN(backup_size/1024.0/1024/1024) > 10
        THEN 'CRÍTICO — variou mais de 10GB no mês'
        WHEN MAX(backup_size/1024.0/1024/1024) -
             MIN(backup_size/1024.0/1024/1024) > 5
        THEN 'ATENÇÃO — variou mais de 5GB no mês'
        ELSE 'OK'
    END                                         AS Status
FROM msdb.dbo.backupset
WHERE type = 'D'
  AND backup_finish_date >= DATEADD(MONTH, -6, GETDATE())
GROUP BY database_name, YEAR(backup_finish_date), MONTH(backup_finish_date)
ORDER BY database_name, Ano DESC, Mes DESC


-- ============================================================
-- SEÇÃO 32 — DISPONIBILIDADE E REINÍCIOS INESPERADOS
-- ============================================================
-- QUANDO USAR:
--   Monitoramento diário de rotina, após reclamação de
--   instabilidade, suspeita de reinício automático,
--   verificação de uptime do servidor.
--
-- IMPORTÂNCIA:
--   Um reinício inesperado do SQL Server zera todas as DMVs
--   (wait stats, index usage, plan cache). Se você não
--   percebeu o reinício, pode tomar decisões erradas baseadas
--   em dados incompletos. Também indica possível problema
--   de hardware, SO ou falha de serviço.
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   HorasLigado baixo      → reinício recente (esperado ou não?)
--   UltimoReinicio recente → correlacionar com incidentes
--   Status                 → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

-- Uptime atual e detecção de reinício inesperado
SELECT
    @@SERVERNAME                                    AS Servidor,
    sqlserver_start_time                            AS UltimoReinicio,
    GETDATE()                                       AS Agora,
    DATEDIFF(HOUR,  sqlserver_start_time, GETDATE()) AS HorasLigado,
    DATEDIFF(DAY,   sqlserver_start_time, GETDATE()) AS DiasLigado,
    CASE
        WHEN DATEDIFF(HOUR, sqlserver_start_time, GETDATE()) < 1
        THEN 'CRÍTICO — SQL reiniciou há menos de 1 hora'
        WHEN DATEDIFF(HOUR, sqlserver_start_time, GETDATE()) < 24
        THEN 'ATENÇÃO — SQL reiniciou nas últimas 24 horas'
        WHEN DATEDIFF(DAY,  sqlserver_start_time, GETDATE()) < 7
        THEN 'ATENÇÃO — SQL reiniciou nos últimos 7 dias'
        ELSE 'OK — uptime saudável'
    END                                             AS Status,
    -- Impacto do reinício: DMVs zeradas
    CASE
        WHEN DATEDIFF(HOUR, sqlserver_start_time, GETDATE()) < 24
        THEN 'ATENÇÃO — wait stats, index usage e plan cache foram zerados. '
           + 'Scripts de diagnóstico baseados em DMVs têm dados incompletos.'
        ELSE 'OK — DMVs com dados suficientes para análise'
    END                                             AS Impacto_DMVs
FROM sys.dm_os_sys_info

-- Histórico de reinícios via log de erros do SQL Server
-- Mostra os últimos reinícios registrados no errorlog
EXEC xp_readerrorlog 0, 1, 'SQL Server is starting'
EXEC xp_readerrorlog 0, 1, 'SQL Server is now ready'


-- ============================================================
-- SEÇÃO 33 — CONSUMO DE DISCO POR BANCO
-- ============================================================
-- QUANDO USAR:
--   Investigar qual banco está gerando mais I/O, disco lento
--   sem causa óbvia, identificar o banco mais ativo no momento.
--
-- IMPORTÂNCIA:
--   A Seção 17 mostra latência por arquivo. Esta seção mostra
--   volume total de leitura e escrita por banco — responde
--   "qual banco está usando mais o disco agora".
--
-- ONDE EXECUTAR: [master]
--
-- O QUE ANALISAR:
--   Reads alto  → banco com muito I/O de leitura (índice faltando?)
--   Writes alto → banco com muito I/O de escrita (log? triggers?)
--   Um banco dominando 80%+ do total → investigar queries nele
--   Status      → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE master
GO

-- Consumo de I/O por banco desde o último restart
SELECT
    DB_NAME(fs.database_id)                     AS Banco,
    SUM(fs.num_of_reads)                        AS Total_Reads,
    SUM(fs.num_of_writes)                       AS Total_Writes,
    CAST(SUM(fs.num_of_bytes_read)/1024.0/1024/1024
        AS DECIMAL(10,2))                       AS GB_Lidos,
    CAST(SUM(fs.num_of_bytes_written)/1024.0/1024/1024
        AS DECIMAL(10,2))                       AS GB_Escritos,
    -- Percentual do total de reads do servidor
    CAST(100.0 * SUM(fs.num_of_reads)
        / NULLIF(SUM(SUM(fs.num_of_reads)) OVER(), 0)
        AS DECIMAL(5,1))                        AS Pct_Reads_Servidor,
    CAST(100.0 * SUM(fs.num_of_writes)
        / NULLIF(SUM(SUM(fs.num_of_writes)) OVER(), 0)
        AS DECIMAL(5,1))                        AS Pct_Writes_Servidor,
    CASE
        WHEN CAST(100.0 * SUM(fs.num_of_reads)
             / NULLIF(SUM(SUM(fs.num_of_reads)) OVER(), 0)
             AS DECIMAL(5,1)) > 70
        THEN 'ATENÇÃO — banco domina > 70% das leituras do servidor'
        WHEN CAST(100.0 * SUM(fs.num_of_writes)
             / NULLIF(SUM(SUM(fs.num_of_writes)) OVER(), 0)
             AS DECIMAL(5,1)) > 70
        THEN 'ATENÇÃO — banco domina > 70% das escritas do servidor'
        ELSE 'OK'
    END                                         AS Status
FROM sys.dm_io_virtual_file_stats(NULL, NULL) fs
WHERE DB_NAME(fs.database_id) IS NOT NULL
GROUP BY fs.database_id
ORDER BY Total_Reads DESC


-- ============================================================
-- SEÇÃO 34 — TOP REGRESSÕES NO QUERY STORE (sp_BlitzQueryStore)
-- ============================================================
-- QUANDO USAR:
--   Após deploy de aplicação, após update de estatísticas em
--   massa, após upgrade do SQL Server, quando usuários
--   reclamam que "estava funcionando ontem e hoje está lento".
--
-- IMPORTÂNCIA:
--   Regressão de plano é uma das causas mais frustrantes de
--   lentidão — a query não mudou, o índice existe, mas o
--   SQL Server escolheu um plano pior. O Query Store guarda
--   o histórico e permite comparar planos antes/depois.
--
-- ONDE EXECUTAR: [banco específico]
--
-- PRÉ-REQUISITO: Query Store habilitado (Seção 13) e
--   sp_BlitzQueryStore instalado (First Responder Kit).
--
-- O QUE ANALISAR:
--   Queries com fator_piora alto    → investigar mudança de plano
--   plan_count > 1                  → múltiplos planos para a query
--   avg_duration_ms crescendo       → degradação progressiva
--   Status                          → OK / ATENÇÃO / CRÍTICO
-- ============================================================

USE SRH  -- TROQUE AQUI
GO

-- Via sp_BlitzQueryStore (mais completo, First Responder Kit)
-- Detecta automaticamente queries que regrediram
-- EXEC sp_BlitzQueryStore @DatabaseName = 'SRH'

-- ─────────────────────────────────────────────────────────────
-- Alternativa nativa com CTEs — versão correta
--
-- ⚠️ POR QUE USAR CTEs AQUI:
-- sys.query_store_runtime_stats tem MÚLTIPLOS registros por
-- plan_id (um por intervalo de coleta). Fazer JOIN direto dos
-- dois períodos contra a mesma tabela gera produto cartesiano,
-- inflando os AVG() e criando falsos positivos de regressão.
-- A solução é agregar CADA período em uma CTE separada primeiro,
-- e só então fazer o JOIN — garantindo um valor por query.
-- ─────────────────────────────────────────────────────────────
;WITH Recente AS (
    -- Agrega performance da ÚLTIMA HORA antes do JOIN
    SELECT
        p.query_id,
        AVG(rs.avg_duration)        AS avg_duration_us,
        AVG(rs.avg_cpu_time)        AS avg_cpu_us,
        AVG(rs.avg_logical_io_reads) AS avg_reads,
        SUM(rs.count_executions)    AS execucoes,
        MAX(rs.last_execution_time) AS ultima_execucao,
        COUNT(DISTINCT p.plan_id)   AS planos_distintos
    FROM sys.query_store_plan p
    JOIN sys.query_store_runtime_stats rs
        ON p.plan_id = rs.plan_id
    JOIN sys.query_store_runtime_stats_interval rsi
        ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time >= DATEADD(HOUR, -1, GETDATE())
    GROUP BY p.query_id
),
Historico AS (
    -- Agrega performance das 24H ANTERIORES antes do JOIN
    SELECT
        p.query_id,
        AVG(rs.avg_duration)        AS avg_duration_us,
        AVG(rs.avg_cpu_time)        AS avg_cpu_us,
        AVG(rs.avg_logical_io_reads) AS avg_reads,
        SUM(rs.count_executions)    AS execucoes
    FROM sys.query_store_plan p
    JOIN sys.query_store_runtime_stats rs
        ON p.plan_id = rs.plan_id
    JOIN sys.query_store_runtime_stats_interval rsi
        ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time BETWEEN DATEADD(HOUR, -24, GETDATE())
                             AND DATEADD(HOUR,  -1, GETDATE())
    GROUP BY p.query_id
)
SELECT TOP 20
    qt.query_sql_text,
    r.query_id,
    -- Durações já agregadas corretamente — sem risco de duplicação
    ROUND(r.avg_duration_us / 1000.0, 2)            AS avg_ms_recente,
    ROUND(h.avg_duration_us / 1000.0, 2)            AS avg_ms_historico,
    ROUND(r.avg_cpu_us / 1000.0, 2)                 AS avg_cpu_ms_recente,
    ROUND(r.avg_reads, 0)                           AS avg_reads_recente,
    ROUND(h.avg_reads, 0)                           AS avg_reads_historico,
    -- Fator de piora: quanto a query degradou
    ROUND(r.avg_duration_us * 1.0
        / NULLIF(h.avg_duration_us, 0), 2)          AS fator_piora,
    r.execucoes                                     AS execucoes_recentes,
    h.execucoes                                     AS execucoes_historico,
    r.planos_distintos,
    r.ultima_execucao,
    CASE
        WHEN r.avg_duration_us > h.avg_duration_us * 5
        THEN 'CRÍTICO — 5x mais lenta, forçar plano anterior'
        WHEN r.avg_duration_us > h.avg_duration_us * 2
        THEN 'ATENÇÃO — 2x mais lenta que o histórico'
        WHEN r.planos_distintos > 3
        THEN 'ATENÇÃO — múltiplos planos, possível instabilidade'
        WHEN r.avg_reads > h.avg_reads * 3
        THEN 'ATENÇÃO — leituras triplicaram (índice? estatística?)'
        ELSE 'OK'
    END                                             AS Status
FROM Recente r
JOIN Historico h
    ON r.query_id = h.query_id
JOIN sys.query_store_query q
    ON r.query_id = q.query_id
JOIN sys.query_store_query_text qt
    ON q.query_text_id = qt.query_text_id
-- Só mostrar queries que pioraram pelo menos 50%
WHERE r.avg_duration_us > h.avg_duration_us * 1.5
ORDER BY fator_piora DESC


-- Forçar plano anterior quando regressão está confirmada
-- 1. Identifique o query_id e plan_id do plano BOM (anterior ao problema)
--    via sys.query_store_plan ordenado por first_execution_time
-- 2. Execute o comando abaixo substituindo os valores:
-- EXEC sys.sp_query_store_force_plan
--     @query_id = 123,   -- id da query com regressão
--     @plan_id  = 456    -- id do plano bom (mais antigo e rápido)

-- Para desfazer o forçamento de plano (se precisar reverter):
-- EXEC sys.sp_query_store_unforce_plan
--     @query_id = 123,
--     @plan_id  = 456

-- Ver planos disponíveis para uma query específica
-- (para identificar qual plan_id era o bom)
-- SELECT p.plan_id, p.engine_version, p.query_plan_hash,
--        p.first_execution_time, p.last_execution_time,
--        p.is_forced_plan
-- FROM sys.query_store_plan p
-- WHERE p.query_id = 123  -- substitua pelo query_id
-- ORDER BY p.first_execution_time


-- ============================================================
-- ⚠️  SEÇÃO 35 — AVISOS CRÍTICOS: O QUE NUNCA FAZER
-- ============================================================
-- Esta seção não tem scripts para executar.
-- É um guia de operações que parecem inofensivas mas
-- causam danos sérios em produção.
-- ============================================================

/*
==============================================================
⚠️  OPERAÇÕES QUE EXIGEM ANÁLISE ANTES DE EXECUTAR
==============================================================

1. UPDATE STATISTICS WITH FULLSCAN
   ─────────────────────────────────
   O que parece: atualização de estatísticas mais precisa.
   O risco real: em tabelas grandes (> 10 milhões de linhas)
   pode gerar carga de leitura intensa e bloquear o servidor
   por minutos ou horas.

   NUNCA executar em produção no horário comercial.
   SEMPRE verificar o tamanho da tabela antes:
     SELECT name, SUM(rows) AS Linhas
     FROM sys.partitions
     WHERE object_id = OBJECT_ID('SuaTabela')
     GROUP BY name

   Para tabelas grandes, prefira:
     UPDATE STATISTICS SuaTabela WITH SAMPLE 30 PERCENT
   ou deixe o Ola Hallengren decidir (IndexOptimize já faz isso).

2. DBCC SHRINKFILE / SHRINKDATABASE
   ──────────────────────────────────
   O que parece: liberar espaço do disco.
   O risco real:
     - Fragmenta TODOS os índices do banco imediatamente
     - O banco vai crescer de volta na próxima operação
     - Você acaba de criar trabalho dobrado: shrink agora +
       rebuild depois + o banco cresce de volta
     - Em produção, o banco pode ficar inutilizável durante o shrink

   A única situação válida para SHRINK é após deletar volumes
   massivos de dados que nunca mais vão crescer de volta,
   e mesmo assim apenas fora do horário comercial.

   Sintoma comum: job "Limpa log ConsultaProcessual" com SHRINKFILE
   detectado no servidor — esse job deve ser desativado.

3. INDEX REBUILD sem janela de manutenção (Standard Edition)
   ──────────────────────────────────────────────────────────
   O que parece: manutenção de índice como qualquer outra.
   O risco real: no SQL Server Standard Edition, REBUILD trava
   a tabela inteira durante toda a operação (ONLINE=OFF é o
   único modo disponível). Em tabelas grandes, isso significa
   minutos ou horas sem acesso.

   SEMPRE usar REORGANIZE durante o horário comercial.
   REBUILD apenas em janela de manutenção (madrugada).
   Ola Hallengren (IndexOptimize) já respeita essa lógica
   automaticamente quando configurado corretamente.

4. DROP INDEX sem validar uso real
   ──────────────────────────────────
   O que parece: remover índice não utilizado (Seção 10).
   O risco real: DMVs de uso de índice são zeradas a cada
   restart do SQL Server. Se o servidor reiniciou há 3 dias,
   um índice que aparece como "nunca usado" pode ser crítico
   para um processo mensal (como fechamento de folha) que
   ainda não rodou desde o restart.

   SEMPRE verificar stats_validas_desde antes de dropar.
   SEMPRE aguardar pelo menos 1 ciclo completo de negócio
   (incluindo fechamento de folha) antes de remover.

5. EXEC sp_updatestats em horário de pico
   ──────────────────────────────────────
   O que parece: atualização rápida de estatísticas.
   O risco real: sp_updatestats executa UPDATE STATISTICS
   em todas as tabelas com modificações. Em bancos com muitas
   tabelas grandes, pode gerar carga inesperada.

   Prefira executar logo após o fechamento de folha ou em
   horário de baixo movimento.

==============================================================
*/

-- ============================================================
-- FIM DO ARQUIVO — VERSÃO 3.2 FINAL
-- 35 seções | 2.500+ linhas
-- Inclui: histórico de crescimento, disponibilidade,
-- consumo por banco, regressões Query Store e
-- guia de operações críticas
-- ============================================================
