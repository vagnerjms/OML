# Catálogo de Consultas, Buscas & Infraestrutura de Dados — UNIFAG

Este documento cataloga exaustivamente **todas as consultas a bancos de dados relacionais (SQL), buscas em planilhas, consultas a Data Tables internas e chamadas de API** executadas pelos 4 fluxos n8n da UNIFAG.

As credenciais e senhas sensíveis foram devidamente **anonimizadas** em conformidade com as boas práticas de segurança da informação.

---

## 1. Mapeamento da Infraestrutura de Servidores & Containers

Abaixo está a correlação entre os servidores/containers da infraestrutura e as bases de dados lógicas consumidas pelas automações:

| Servidor / Container | Tecnologia & Portas | Usuário | Senha | Bancos Lógicos / Schemas | Papel no Ecossistema UNIFAG |
|---|---|---|---|---|---|
| **`mysql_mysql`** | MySQL 8.0<br/>Portas: `3306 / 33060` | `root` / `bot_user` | `[PROTEGIDO / ENV]` | **`bot_control`** | **Banco de Dados Principal de Campanhas e Controle**.<br/>Armazena resumos de disparos, auditoria da Meta, agendamentos médicos atribuídos, travas de contatos e históricos consolidados. |
| **`unifag-omnihub_mysql`** | MySQL 8.0<br/>Portas: `3306 / 33060` | `root` | `[PROTEGIDO / ENV]` | **`omnihub`** / **`omnihub_core`** | **Banco Operacional do OmniHub**.<br/>Armazena instâncias, configurações de canais e tabelas internas do hub de integração. Conecta-se aos fluxos indiretamente através do gateway. |
| **`postgres_postgres`** | PostgreSQL 16<br/>Porta: `5432` | `unifag_admin` / `oml_user` | `[PROTEGIDO / ENV]` | **1. `unifag_bot`**<br/>**2. `ominicontacto` (OmniLeads)** | **Banco de Sessões do Bot & Atendimento OML**.<br/>- Schema `unifag_bot`: máquinas de estado do robô, histórico de chat e deduplicação de mensagens.<br/>- Schema `ominicontacto`: leitura analítica das conversas e agentes do contact center. |
| **`redis_redis`** | Redis<br/>Porta: `6379` | Default | *(Sem senha / Interno)* | DB `0` a `15` | **Cache Geral & Filas do n8n**.<br/>Armazenamento volátil de alta velocidade para controle de taxa (*rate limiting*), locks atômicos e filas de execução. |
| **`unifag-omnihub_redis`** | Redis<br/>Porta: `6379` | Default | *(Sem senha / Interno)* | DB `0` a `15` | **Broker de Eventos do OmniHub**.<br/>Gerenciamento de eventos de socket, filas BullMQ de mensageria em tempo real e buffer de webhooks. |

---

## 2. Inventário de Consultas SQL por Fluxo

### 📂 Fluxo 1: UNIFAG - Sincroniza Agenda OML - OTIMIZADO (`1yuqoeWSRkcq1fM2`)
* **Base de Destino**: `mysql_mysql:3306` ➔ Banco: `bot_control`
* **Credencial n8n**: `Douv0MMoaoiQSOUc` (`bot_control`)

#### Consulta 1.1 — Inserção de Novo Agendamento com Atribuição
* **Nó n8n**: `Gravar Conversao Nova`
* **Tipo**: `INSERT ... SELECT ... ON DUPLICATE KEY UPDATE`
* **Finalidade**: Grava agendamento detectado com novo ID gerado na planilha, vinculando-o à última campanha de atração recebida pelo paciente.
```sql
INSERT INTO campanha_agendamentos (
  agenda_id, agenda_fingerprint, source_sheet, source_row,
  participante_nome, telefone_original, wa_id, data_consulta,
  horario_consulta, medico, via_entrada, tipo_consulta,
  como_ficou_sabendo, agendado_por, status_pasta_pp,
  confirmacao_presenca, status_presenca, status_consulta,
  atendido_por, observacao, campaign_key, campanha_contato_id,
  campanha_nome, respondeu_cliente, primeira_resposta_em,
  attribution_status, attribution_method, attributed_at
)
SELECT
  '{{ $json.agenda_id }}',
  SHA2(CONVERT(FROM_BASE64('{{ $json.fingerprint_raw_b64 }}') USING utf8mb4), 256),
  CONVERT(FROM_BASE64('{{ $json.source_sheet_b64 }}') USING utf8mb4),
  NULLIF({{ Number($json.source_row || 0) }}, 0),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.participante_nome_b64 }}') USING utf8mb4), ''),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.telefone_original_b64 }}') USING utf8mb4), ''),
  '{{ $json.wa_id }}',
  NULLIF('{{ $json.data_consulta }}', ''),
  NULLIF('{{ $json.horario_consulta }}', ''),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.medico_b64 }}') USING utf8mb4), ''),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.via_entrada_b64 }}') USING utf8mb4), ''),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.tipo_consulta_b64 }}') USING utf8mb4), ''),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.como_ficou_sabendo_b64 }}') USING utf8mb4), ''),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.agendado_por_b64 }}') USING utf8mb4), ''),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.status_pasta_pp_b64 }}') USING utf8mb4), ''),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.confirmacao_presenca_b64 }}') USING utf8mb4), ''),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.status_presenca_b64 }}') USING utf8mb4), ''),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.status_consulta_b64 }}') USING utf8mb4), ''),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.atendido_por_b64 }}') USING utf8mb4), ''),
  NULLIF(CONVERT(FROM_BASE64('{{ $json.observacao_b64 }}') USING utf8mb4), ''),
  cc.campaign_key,
  cc.id,
  cc.campanha_nome,
  COALESCE(cc.respondeu_cliente, 0),
  cc.primeira_resposta_em,
  CASE WHEN cc.id IS NULL THEN 'sem_campanha' ELSE 'atribuido' END,
  CASE WHEN cc.id IS NULL THEN 'sem_campanha_antes_deteccao_agenda' ELSE 'ultima_campanha_antes_deteccao_agenda' END,
  CASE WHEN cc.id IS NULL THEN NULL ELSE NOW() END
FROM (SELECT 1 AS dummy) seed
LEFT JOIN campanha_contatos_resumo cc
  ON cc.id = (
    SELECT c2.id
    FROM campanha_contatos_resumo c2
    WHERE c2.wa_id = '{{ $json.wa_id }}'
      AND c2.enviado_em IS NOT NULL
      AND c2.enviado_em <= NOW()
      AND c2.campaign_key IS NOT NULL
      AND TRIM(c2.campaign_key) <> ''
      AND c2.campaign_key <> 'campaign_key'
      AND c2.campaign_key NOT LIKE '%$json.campaign_key%'
      AND LOWER(TRIM(SUBSTRING_INDEX(c2.campaign_key, '__', -1))) NOT IN (
        'confirmacao_de_agenda_consulta',
        'ausente',
        'confirmacao_coleta_pos'
      )
    ORDER BY c2.enviado_em DESC, c2.id DESC
    LIMIT 1
  )
ON DUPLICATE KEY UPDATE
  source_sheet = VALUES(source_sheet),
  source_row = VALUES(source_row),
  participante_nome = VALUES(participante_nome),
  telefone_original = VALUES(telefone_original),
  wa_id = VALUES(wa_id),
  data_consulta = VALUES(data_consulta),
  horario_consulta = VALUES(horario_consulta),
  medico = VALUES(medico),
  via_entrada = VALUES(via_entrada),
  tipo_consulta = VALUES(tipo_consulta),
  como_ficou_sabendo = VALUES(como_ficou_sabendo),
  agendado_por = VALUES(agendado_por),
  status_pasta_pp = VALUES(status_pasta_pp),
  confirmacao_presenca = VALUES(confirmacao_presenca),
  status_presenca = VALUES(status_presenca),
  status_consulta = VALUES(status_consulta),
  atendido_por = VALUES(atendido_por),
  observacao = VALUES(observacao),
  last_seen_at = CURRENT_TIMESTAMP,
  updated_at = CURRENT_TIMESTAMP;
```

#### Consulta 1.2 — Inserção e Atualização em Lotes (100 Itens via `JSON_TABLE`)
* **Nó n8n**: `Gravar Conversao na Agenda`
* **Tipo**: `INSERT ... SELECT FROM JSON_TABLE(...) ON DUPLICATE KEY UPDATE`
* **Finalidade**: Processa lotes de até 100 agendamentos já existentes de forma atômica e performática, decodificando o JSON Base64 e atualizando os status clínicos e comparecimento.

---

### 📂 Fluxo 2: UNIFAG - Campanhas WhatsApp - Controle 24h e Relatórios (`wpwQBe7OIUvzGvRZ`)
* **Base de Destino**: `mysql_mysql:3306` ➔ Banco: `bot_control`
* **Credencial n8n**: `Douv0MMoaoiQSOUc` (`bot_control`)

#### Consulta 2.1 — Verificação Preventiva da Janela de 24 Horas
* **Nó n8n**: `MYSQL - Verificar Janela 24h`
* **Tipo**: `SELECT (CTE com parâmetros)`
* **Finalidade**: Avalia se o contato já recebeu mensagem nas últimas 24 horas antes de invocar a Meta Send API.
```sql
WITH entrada AS (
  SELECT
    $1 AS campaign_key, $2 AS wa_id, $3 AS modo_disparo,
    $4 AS template_label, $5 AS template_name, $6 AS template_language_code,
    $7 AS message_text, $8 AS texto_personalizado, $9 AS indice_destinatario,
    $10 AS total_destinatarios, $11 AS config_phone_number_id,
    $12 AS config_delay_segundos, $13 AS config_lock_expiration_minutes
),
contato_atual AS (
  SELECT e.*,
    CASE
      WHEN REGEXP_REPLACE(COALESCE(e.wa_id, ''), '[^0-9]', '') REGEXP '^55[0-9]{10,11}$'
      THEN SUBSTRING(REGEXP_REPLACE(e.wa_id, '[^0-9]', ''), 3)
      ELSE REGEXP_REPLACE(COALESCE(e.wa_id, ''), '[^0-9]', '')
    END AS telefone_normalizado
  FROM entrada e
),
ultimo_envio AS (
  SELECT c.id, c.campaign_key, c.enviado_em
  FROM campanha_contatos_resumo c
  CROSS JOIN contato_atual a
  WHERE a.telefone_normalizado <> ''
    AND c.meta_message_id IS NOT NULL
    AND c.enviado_em IS NOT NULL
    AND c.enviado_em >= NOW() - INTERVAL 24 HOUR
    AND c.enviado_em <= NOW()
    AND (
      CASE
        WHEN REGEXP_REPLACE(COALESCE(c.wa_id, ''), '[^0-9]', '') REGEXP '^55[0-9]{10,11}$'
        THEN SUBSTRING(REGEXP_REPLACE(c.wa_id, '[^0-9]', ''), 3)
        ELSE REGEXP_REPLACE(COALESCE(c.wa_id, ''), '[^0-9]', '')
      END
    ) = a.telefone_normalizado
  ORDER BY c.enviado_em DESC, c.id DESC
  LIMIT 1
)
SELECT
  a.campaign_key, a.wa_id, a.modo_disparo, a.template_label, a.template_name,
  a.template_language_code, a.message_text, a.texto_personalizado, a.indice_destinatario,
  a.total_destinatarios, a.config_phone_number_id, a.config_delay_segundos,
  a.config_lock_expiration_minutes,
  CASE WHEN u.id IS NOT NULL THEN 1 ELSE 0 END AS bloqueado_24h,
  u.campaign_key AS campanha_anterior_key,
  u.enviado_em AS ultimo_envio_em,
  CASE WHEN u.id IS NOT NULL THEN DATE_ADD(u.enviado_em, INTERVAL 24 HOUR) ELSE NULL END AS liberado_em
FROM contato_atual a
LEFT JOIN ultimo_envio u ON TRUE;
```

#### Consulta 2.2 — Registro de Bloqueio Preventivo 24h
* **Nó n8n**: `MYSQL - Registrar Bloqueio 24h`
* **Tipo**: `INSERT ... ON DUPLICATE KEY UPDATE`
* **Finalidade**: Registra o contato como `blocked_24h` sem chamar a Meta API.
```sql
INSERT INTO campanha_contatos_resumo (
  campaign_key, wa_id, modo_disparo, campanha_nome,
  template_name, template_language_code, message_text,
  meta_message_id, status_envio, enviado_em, observacoes
) VALUES (
  $1, $2, $3, $4, $5, $6, $7, NULL, 'blocked_24h', NOW(),
  CONCAT(
    'BLOQUEADO_JANELA_24H | campanha_anterior=', COALESCE($8,''),
    ' | ultimo_envio_em=', COALESCE($9,''),
    ' | liberado_em=', COALESCE($10,'')
  )
)
ON DUPLICATE KEY UPDATE
  updated_at = IF(meta_message_id IS NULL, CURRENT_TIMESTAMP, updated_at),
  enviado_em = IF(meta_message_id IS NULL, NOW(), enviado_em),
  observacoes = IF(meta_message_id IS NULL, VALUES(observacoes), observacoes),
  status_envio = IF(meta_message_id IS NULL, 'blocked_24h', status_envio);
```

#### Consulta 2.3 — Inserção de Disparo Efetivo (Humano ou Bot)
* **Nós n8n**: `MYSQL - Upsert Resumo Campanha Humano` e `MYSQL - Upsert Resumo Campanha Bot`
* **Tipo**: `INSERT ... ON DUPLICATE KEY UPDATE`
* **Finalidade**: Persiste o envio com `meta_message_id` (`wamid`) retornado pela Meta Send API.
```sql
INSERT INTO campanha_contatos_resumo (
  campaign_key, wa_id, modo_disparo, campanha_nome,
  template_name, template_language_code, message_text,
  meta_message_id, status_envio, enviado_em
) VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $9, NOW()
)
ON DUPLICATE KEY UPDATE
  modo_disparo = VALUES(modo_disparo),
  campanha_nome = VALUES(campanha_nome),
  template_name = VALUES(template_name),
  template_language_code = VALUES(template_language_code),
  message_text = VALUES(message_text),
  meta_message_id = VALUES(meta_message_id),
  status_envio = VALUES(status_envio),
  enviado_em = VALUES(enviado_em),
  updated_at = CURRENT_TIMESTAMP;
```

#### Consulta 2.4 — Atualização de Callback de Status Meta ou Resposta Humana
* **Nó n8n**: `MYSQL - Atualizar Status Meta`
* **Tipo**: `UPDATE (Condicional Dinâmico)`
* **Finalidade**: Atualiza progressão de estados (`sent` ➔ `delivered` ➔ `read` ➔ `failed`) e computa entrega via `FROM_UNIXTIME()` no fuso de São Paulo. Se o evento for `human_campaign_reply`, incrementa `quantidade_interacoes` e registra `respondeu_cliente = 1`.

#### Consulta 2.5 — Inserção de Auditoria de Faturamento Meta
* **Nó n8n**: `MYSQL - Gravar Auditoria Meta`
* **Tipo**: `INSERT INTO meta_eventos_auditoria ... ON DUPLICATE KEY UPDATE`
* **Finalidade**: Grava o evento de webhook com pricing (`pricing_billable`, `pricing_category`, etc.) para reconciliação financeira.

#### Consulta 2.6 — Consolidação de Fechamento da Campanha
* **Nó n8n**: `MYSQL - Resumo Final Campanha`
* **Tipo**: `SELECT ... GROUP BY campaign_key`
* **Finalidade**: Apura o total processado, % de entrega, % de leitura e taxa de respostas 2 minutos após o término do disparo.

---

### 📂 Fluxo 3: UNIFAG - Dashboard Original + Relatórios 24h V5 (`vETUs2AnPvfrSHSU`)

#### Consultas em MySQL (`bot_control` via `mysql_mysql:3306`):

1. **`Execute a SQL query`**:
   * **Finalidade**: Relatório individual da campanha selecionada (`?campaign_key=...`), unindo `campanha_contatos_resumo` com `campanha_agendamentos` (calculando convertidos, presentes e aptos).
2. **`Execute a SQL query1`**:
   * **Finalidade**: Listagem geral das campanhas dos últimos 90 dias com taxas de saúde para alimentar a tabela da Visão Geral.
3. **`Consultar Erros da Campanha`**:
   * **Finalidade**: Busca paginada (50 itens por página) dos contatos com erro (`failed`/`error`) e totalizadores via *window functions* (`COUNT(*) OVER()`).
4. **`Consultar Contatos do Indicador`**:
   * **Finalidade**: `UNION ALL` de alta complexidade que unifica a listagem de contatos da campanha (`sent`, `delivered`, `read`, `replied`) e agendamentos médicos atribuídos (`appointments`, `converted`, `present`, `apt`), permitindo exportação e inspeção nominal.
5. **`Consultar BI Meta e Janela 24h`**:
   * **Finalidade**: Cruzamento analítico entre `campanha_contatos_resumo`, a view `vw_meta_janela_24h` e `meta_eventos_auditoria`. Identifica reaberturas após 24h com cobrança (`pricing_billable = 1`) e calcula o histórico estimado V7.
6. **`MYSQL - Relatórios Bloqueios 24h`**:
   * **Finalidade**: Unifica as tentativas bloqueadas pela janela de 24h (`blocked_24h`), apura a campanha anterior e calcula os minutos restantes para liberação.
7. **`MYSQL - Excluir Campanha`**:
   * **Query**: `DELETE FROM campanha_contatos_resumo WHERE campaign_key = '...';`
   * **Finalidade**: Exclusão segura de campanhas executada apenas por administradores.
8. **`MYSQL - Salvar Validação WhatsApp`**:
   * **Query**: `UPDATE campanha_contatos_resumo SET whatsapp_validacao_status = '...', whatsapp_validado_em = CURRENT_TIMESTAMP, whatsapp_validado_por = '...' WHERE id = ...;`
   * **Finalidade**: Saneamento de números sem WhatsApp (erro 131026).

#### Consultas em PostgreSQL (`ominicontacto` / OmniLeads via `postgres_postgres:5432`):
* **Credencial n8n**: `OML_Postgres_RO` (`2bKvTQOQHDE6NZCM`)

1. **`Consultar OML Atendimento`**:
   * **Tabelas Consultadas**:
     * `whatsapp_app_conversacionwhatsapp`: dados da conversa, expiração e fechamento.
     * `whatsapp_app_mensajewhatsapp`: histórico de mensagens trocadas.
     * `ominicontacto_app_campana`: nome e habilitação de WhatsApp da campanha OML.
     * `ominicontacto_app_historicalcalificacioncliente`: registro de qualificação do operador.
     * `ominicontacto_app_opcioncalificacion`: motivos de encerramento cadastrados.
   * **Finalidade**: Apurar conversas encerradas no período, contatos recebidos (inbound), tempo de resposta dos agentes humanos e conversas perdidas sem atendimento após 24h.
2. **`POSTGRES - Relatórios Atendimento 24h`**:
   * **Finalidade**: Classifica cada conversa como `ATENDIDA_PELO_AGENTE`, `SEM_ATENDIMENTO_APOS_24H` ou `AGUARDANDO_JANELA_24H`.

---

### 📂 Fluxo 4: UNIFAG - Bot com Registro de Respostas da Campanha (`mtbFAvtEk3YwcsAB`)

#### Consultas em MySQL (`bot_control` via `mysql_mysql:3306`):
1. **`MYSQL - Buscar Contexto Campanha`**:
   ```sql
   SELECT id, wa_id, campanha_nome, template_name, message_text, modo_disparo,
          respondeu_cliente, primeira_mensagem_cliente, ultima_mensagem_cliente,
          quantidade_interacoes, primeira_resposta_em, ultima_resposta_bot, enviado_em,
          solicitacao_nome_cpf_status, solicitacao_nome_cpf_em,
          CASE WHEN LOWER(COALESCE(modo_disparo, '')) IN ('human', 'humano')
                AND enviado_em IS NOT NULL AND enviado_em >= NOW() - INTERVAL 7 DAY
               THEN 1 ELSE 0 END AS campanha_human_ativa
   FROM campanha_contatos_resumo
   WHERE wa_id = $1
   ORDER BY enviado_em DESC LIMIT 1;
   ```
2. **`MYSQL - Check Bot Lock`**:
   ```sql
   SELECT wa_id, bot_locked, lock_reason, source, session_status, updated_at
   FROM bot_contact_control
   WHERE wa_id = '{{ $node["Edit Fields"].json["wa_id"] }}'
     AND bot_locked = 1
     AND updated_at >= (NOW() - INTERVAL 30 MINUTE)
   ORDER BY updated_at DESC LIMIT 1;
   ```
3. **`MYSQL - Marcar Resposta Cliente Campanha`**:
   * Atualiza `respondeu_cliente = 1`, primeira e última mensagem do cliente e incrementa `quantidade_interacoes`.
4. **`MYSQL - Claim Primeira Resposta Human`**:
   * Trava atômica com `UPDATE campanha_contatos_resumo SET solicitacao_nome_cpf_status = 'processando'` para evitar disparos concorrentes.
5. **`MYSQL - Registrar Solicitação Nome CPF Human`**:
   * Atualiza `solicitacao_nome_cpf_status = 'enviada'` após o envio da pergunta inicial no modo humano.
6. **`MYSQL - Atualizar Interação Human`**:
   * Atualiza `ultima_mensagem_cliente` nas respostas seguintes da campanha humana.
7. **`MYSQL - Set Human Lock`**:
   * Grava `bot_locked = 1`, `source = 'agent'` e `session_status = 'human'` em `bot_contact_control` no momento do handoff.
8. **`MYSQL - Upsert Atendimento Resumo`**:
   * Insere em `bot_atendimento_resumo` o texto consolidado da triagem do voluntário.
9. **`MYSQL - Upsert Atendimento Historico`**:
   * Insere linha por linha cada pergunta e resposta da sessão em `bot_atendimento_historico`.
10. **`MYSQL - Registrar Resposta Bot na Campanha`**:
    * Salva o texto enviado pelo bot em `campanha_contatos_resumo.ultima_resposta_bot`.

#### Consultas em PostgreSQL (`unifag_bot` via `postgres_postgres:5432`):
* **Credencial n8n**: `Unifag_Bot` (`RLZJxPIN5hWeeHIB`)
* **Tabelas**:
  1. `unifag_bot.processed_messages`:
     * `DB - Check Processed Message`: `SELECT EXISTS (SELECT 1 FROM unifag_bot.processed_messages WHERE message_id = $1);`
     * `DB - Insert Processed Message`: `INSERT INTO unifag_bot.processed_messages (message_id, created_at) VALUES ($1, NOW());`
  2. `unifag_bot.sessoes_atendimento`:
     * `DB - Get Session`: Recupera sessão ativa nos últimos 30 min ou sessão humana.
     * `DB - Check Recent Closed Session`: Checa se a sessão encerrou há menos de 1 minuto para bloqueio anti-loop.
     * `DB - Create Session`: Cria nova sessão com `etapa_atual = 'entrada'` e armazena contexto de campanha.
     * `DB - Update Session Stage` (nós `Stage`, `Stage1`, `Stage2`): Atualiza etapa da FSM, array JSONB `historico_qa` e timestamp.
     * `DB - Set Session Human`: Atualiza `status = 'humano'` e registra `motivo_handoff`.
     * `DB - Close Session After Form Leads`: Atualiza para `status = 'encerrado'`.
  3. `unifag_bot.historico_mensagens`:
     * `DB - Save User Message`: Grava mensagens de entrada do paciente.
     * `DB - Save Bot Message`: Grava mensagens enviadas pelo bot.
  4. `public.n8n_chat_histories` / `unifag_bot.n8n_chat_histories`:
     * `Postgres Chat Memory`: Nó de memória do LangChain para o modelo Google Gemini.
  5. `unifag_bot.roteamento_oml_humano` (Gerenciado pelo `wa_gateway:8088`):
     * **Upsert de Roteamento Humano**:
       ```sql
       INSERT INTO unifag_bot.roteamento_oml_humano (
         wa_id, campaign_key, campanha_nome, template, destination_type,
         oml_campaign_id, oml_campaign_name, oml_agent_id, oml_agent_name,
         routed, updated_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, FALSE, NOW())
       ON CONFLICT (wa_id) DO UPDATE SET
         campaign_key = EXCLUDED.campaign_key,
         campanha_nome = EXCLUDED.campanha_nome,
         template = EXCLUDED.template,
         destination_type = EXCLUDED.destination_type,
         oml_campaign_id = EXCLUDED.oml_campaign_id,
         oml_campaign_name = EXCLUDED.oml_campaign_name,
         oml_agent_id = EXCLUDED.oml_agent_id,
         oml_agent_name = EXCLUDED.oml_agent_name,
         routed = FALSE,
         updated_at = NOW();
       ```
     * **Busca de Roteamento Pendente**:
       ```sql
       SELECT * FROM unifag_bot.roteamento_oml_humano 
       WHERE wa_id = $1 AND routed = FALSE 
       LIMIT 1;
       ```
     * **Marcação de Transferência Concluída**:
       ```sql
       UPDATE unifag_bot.roteamento_oml_humano
       SET routed = TRUE, conversation_id = $2, routed_at = NOW(), updated_at = NOW()
       WHERE wa_id = $1;
       ```

---

## 3. Inventário de Buscas Não-SQL (Planilhas, Data Tables & APIs)

### 3.1. Google Sheets API
* **Nó**: `Ler Agenda 2026 - OMNILEADS` (Fluxo 1)
  * **Documento**: `1PhwJbwwvQQyYEgla2s8U_s8YgcPGFt2jd1c3vv4-9v4`
  * **Aba**: `AGENDA 2026` (`gid=327726699`)
  * **Filtro**: `VIA DE ENTRADA = OMNILEADS`
* **Nó**: `Gravar ID novo na Agenda` (Fluxo 1)
  * **Operação**: Atualização de célula da coluna S (`ID_AGENDA_OML`) pelo número físico da linha (`row_number`).

### 3.2. n8n Data Tables (Armazenamento Interno de Alta Performance)

| Data Table | ID | Finalidade nos Fluxos |
|---|---|---|
| **`wa_automation_config`** | `3nQw8DRKimYrWwZb` | **1. Autenticação do Painel de Disparo**:<br/>- `auth.user.{email}`: perfil, salt e hash SHA-512 da senha.<br/>- `auth.session.{token}`: tokens de 8 horas.<br/>**2. Catálogo de Modelos Meta**:<br/>- `template.{name}.{language}`: status na Meta (`APPROVED`), texto e parâmetros.<br/>**3. Parâmetros de Disparo**:<br/>- `phone_number_id`, `delay_segundos`, `lock_expiration_minutes`. |
| **`dashboard_usuarios`** | `oE3mO5aUWr2pIC40` | **Autenticação do Dashboard Executivo (`/webhook/whasoml`)**:<br/>- Controle de usuários, perfis (`admin` / `visualizador`), salt/hash SHA-256 e obrigatoriedade de troca de senha no primeiro login. |

### 3.3. Meta WhatsApp Cloud API (Graph API)
* **Endpoints Consumidos**:
  1. `POST https://graph.facebook.com/v20.0/{phone_number_id}/messages`:
     * Disparo de templates ativos (Fluxo 2) e respostas do Bot de triagem (Fluxo 4).
  2. `GET/POST https://graph.facebook.com/v20.0/1156659843285011/message_templates`:
     * Criação de novos modelos, validação prévia antes de campanhas e sincronização de catálogo.
  3. `GET https://graph.facebook.com/v25.0/1156659843285011/template_analytics`:
     * Extração de métricas oficiais de custo em USD (`amount_spent`, `cost_per_delivered`) com granularidade diária.

### 3.4. APIs de Borda & Gateways Locais

#### A. Gateway de Orquestração (`wa_gateway:8088` — `/opt/wa-gateway/index.js` em `DCNTXRDSTATION`):
* **Roteamento & Ingress**: Traefik em `webhook.usf.edu.br` roteando `/meta` e `/webhook/unifag-meta`.
* **Endpoints Expostos**:
  * `POST /control/lock/{wa_id}/on`: Ativa trava de atendimento humano e grava intenção de roteamento em `unifag_bot.roteamento_oml_humano`.
  * `POST /control/lock/{wa_id}/off`: Liberação imediata da trava de atendimento humano.
  * `GET /control/oml/campaigns`: Proxy autenticado que lista campanhas/filas ativas do OmniLeads.
  * `GET /control/oml/campaigns/{id}/agents`: Proxy autenticado que lista agentes membros de uma fila OML.
  * `POST /webhook/whatsapp/handoff`: Recebe o payload com resumo formatado de triagem do bot e insere na fila do OML (`X-Handoff-Secret: [PROTEGIDO]`).
  * `POST /webhook/whatsapp/transcript`: Envio de transcrições completas da conversa.
* **Bridge de Mídia & Cache Local**:
  * Armazenamento em `/app/media-cache` com TTL de 7 dias (168h) e limite de 25MB por mídia.
  * Traefik Middleware `wa-gateway-meta-strip` reescreve `/meta/media/:token` ➔ `/webhook/media/:token`.
* **Meta WABA Webhook Ownership Watchdog**:
  * Rotina em background executada a cada 60 segundos inspecionando e garantindo que o Webhook do WABA está assinado pelo App ID `1937257670036344`.

#### B. API Interna do OmniLeads (`OML 2.5.6` — Podman / Ansible):
* `POST /accounts/login/`: Autenticação Django com extração de cookie de sessão (`sessionid`) e CSRF token (obrigatório para contornar `SessionAuthentication` do OML 2.5.6).
* `POST /api/v1/whatsapp/filter_chats/`: Busca a conversa aberta no tronco de entrada `111` (`UNIFAG_WHATSAPPV1`) filtrada por `customer_phone`.
* `POST /api/v1/whatsapp/transfer/to_campaign/`: Transfere a conversa para a fila/campanha OML especificada em `campaign_id`.
* `POST /api/v1/whatsapp/transfer/to_agent/`: Transfere a conversa diretamente para o operador humano em `agent_id`.

#### C. Evolution API (quando utilizada):
* `POST http://179.197.231.106:8085/message/sendText/Disparo` e `/sendMedia/Disparo`:
  Disparo de mensagens de texto e mídias via instância Baileys/Evolution com autenticação via header `apikey`.

