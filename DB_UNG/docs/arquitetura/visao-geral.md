# Arquitetura Global do Sistema — UNIFAG

Este documento detalha a topologia de microsserviços, componentes de infraestrutura, barramentos de comunicação e o ciclo de vida ponta a ponta dos dados no ecossistema de automações WhatsApp da **UNIFAG**.

---

## 1. Topologia de Microsserviços e Integração

O ecossistema opera em uma arquitetura orientada a eventos e microsserviços conteinerizados, orquestrada pelo **n8n** e interligada à infraestrutura de telefonia e mensageria corporativa:

```mermaid
flowchart TB
    subgraph Meta_Cloud["Nuvem Meta (WhatsApp Cloud API)"]
        WABA["WABA: 1156659843285011<br/>Phone ID: 897759766750800"]
        Meta_Webhook["Webhook de Eventos & Status<br/>(messages, delivery, read, errors)"]
        Meta_Send["Graph API v20 / v25<br/>(Disparo de Templates & Mensagens)"]
        Meta_Analytics["Graph API /template_analytics<br/>(Custos Oficiais em USD)"]
    end

    subgraph Ingress_Tier["Borda & Roteamento Reverso"]
        Traefik["Traefik Reverse Proxy (Let's Encrypt)<br/>https://webhook.usf.edu.br<br/>Reescrita: /meta/* ➔ /webhook/*"]
    end

    subgraph Gateway_Tier["Orquestração de Borda (Host DCNTXRDSTATION)"]
        WAGateway["wa_gateway:8088 (/opt/wa-gateway)<br/>- Trava de Contatos (Memória + Postgres)<br/>- Transferência OML (Campanha 111 ➔ Destino)<br/>- Ponte de Mídia (/app/media-cache, TTL 7d)<br/>- Watchdog de Inscrição WABA (60s)"]
    end

    subgraph N8N_Core["Orquestrador de Automação (n8n Engine)"]
        F1["Fluxo 1: Sincroniza Agenda<br/>(1yuqoeWSRkcq1fM2)"]
        F2["Fluxo 2: Campanhas & Controle 24h<br/>(wpwQBe7OIUvzGvRZ)"]
        F3["Fluxo 3: Dashboard & BI Meta<br/>(vETUs2AnPvfrSHSU)"]
        F4["Fluxo 4: Bot IA com FSM<br/>(mtbFAvtEk3YwcsAB)"]
    end

    subgraph Data_Tier["Camada de Dados & Persistência"]
        MySQL_DB[("MySQL: bot_control (mysql_mysql:3306)<br/>- campanha_contatos_resumo<br/>- campanha_agendamentos<br/>- bot_contact_control<br/>- meta_eventos_auditoria")]
        PG_Bot[("PostgreSQL: unifag_bot (postgres_postgres:5432)<br/>- sessoes_atendimento<br/>- historico_mensagens<br/>- roteamento_oml_humano<br/>- processed_messages")]
        PG_OML[("PostgreSQL: OmniLeads (RO)<br/>- whatsapp_app_conversacionwhatsapp<br/>- whatsapp_app_mensajewhatsapp<br/>- ominicontacto_app_campana")]
        GSheets[("Google Sheets<br/>Planilha 'AGENDA 2026'")]
    end

    subgraph OmniLeads_Tier["Atendimento Humano (OmniLeads via Podman / Ansible)"]
        OML_Trunk["Tronco Entrada Fixo: Campanha 111"]
        OML_Core["OmniLeads Contact Center<br/>Filas e Agentes UNIFAG"]
    end

    %% Conexões Meta <-> Traefik <-> Gateway
    Meta_Webhook -->|HTTPS Callback| Traefik
    Traefik -->|Roteia /webhook/unifag-meta| WAGateway
    WAGateway -->|POST /webhook/wa-bot-in| F4
    WAGateway -->|POST /webhook/unifag-meta-status| F2
    F2 -->|Envio de Disparo| Meta_Send
    F4 -->|Envio de Respostas do Bot| Meta_Send
    F3 -->|Consulta Custos Oficiais| Meta_Analytics

    %% Conexões Gateway <-> OML / N8N
    F2 -->|"Ativar Lock Humano + Destino OML"| WAGateway
    F4 -->|"Handoff de Conversa"| WAGateway
    WAGateway -->|"1. Consulta Chat em 111"| OML_Trunk
    WAGateway -->|"2. Transfere Campanha ou Agente"| OML_Core

    %% Conexões de Dados
    F1 <--> GSheets
    F1 --> MySQL_DB
    F2 <--> MySQL_DB
    F3 <--> MySQL_DB
    F3 <--> PG_OML
    F4 <--> PG_Bot
    F4 <--> MySQL_DB
    WAGateway <--> PG_Bot
```

---

## 2. Componentes e Portas de Rede

| Componente | Endereço / Porta | Função no Ecossistema |
|---|---|---|
| **Traefik Reverse Proxy** | `https://webhook.usf.edu.br` (443) | Ponto único de entrada HTTPS seguro com certificado Let's Encrypt automático. Aplica reescrita de `/meta/(.*)` para `/webhook/$1`. |
| **`wa_gateway`** | `http://wa_gateway:8088` (`/opt/wa-gateway`) | Microsserviço Node.js orquestrado como serviço **Docker Swarm** (`node_meta_wa_gateway` na stack `node_meta`). Gerencia travas, cache de mídia (7d), watchdog WABA e transferência no OML. Veja o [**Guia Completo do Gateway**](gateway-orquestracao.md). |
| **n8n Workflow Engine** | Host / Porta configurada (padrão 5678) | Hospeda os webhooks, telas web interativas e regras de negócio de todos os fluxos. |
| **OmniLeads (OML 2.5.6)** | `https://oml.usf.edu.br` | Plataforma de Contact Center implantada via **Podman** (orquestrada por **Ansible**). Gerencia agentes humanos, campanhas e filas. |
| **MySQL (`bot_control`)** | `mysql_mysql:3306` | Banco relacional onde residem os resumos das campanhas, a tabela de agendamentos atribuídos, a auditoria de faturamento Meta e as travas de contato. |
| **PostgreSQL (`unifag_bot`)** | `postgres_postgres:5432` | Banco relacional do bot e gateway: sessões da FSM, histórico Q&A, deduplicação (`processed_messages`) e roteamento humano (`roteamento_oml_humano`). |
| **PostgreSQL OmniLeads** | Credencial `OML_Postgres_RO` (`5432`) | Banco analítico em leitura (RO) do OmniLeads para auditar tempo de resposta dos operadores e conversas sem atendimento. |
| **Google Sheets API** | OAuth2 / Google Cloud | Planilha colaborativa utilizada pela recepção médica e coordenação de estudos clínicos. |
| **Meta Graph API** | `https://graph.facebook.com/v20.0` e `v25.0` | API oficial da Meta para submissão de modelos, envio de mensagens e extração de métricas de cobrança (`template_analytics`). |

---

## 3. Ciclo de Vida Ponta a Ponta: Da Campanha à Conversão

O fluxo a seguir ilustra a jornada completa de um contato desde o disparo até o comparecimento na clínica:

```mermaid
sequenceDiagram
    autonumber
    actor Operador as Operador / Supervisor
    participant N8N_Camp as n8n (Campanhas)
    participant MySQL as MySQL (bot_control)
    participant Gateway as wa_gateway:8088
    participant Meta as Meta WhatsApp API
    actor Paciente as Paciente / Voluntário
    participant N8N_Bot as n8n (Bot Receptivo)
    participant PG_Bot as PostgreSQL (unifag_bot)
    participant OML as OmniLeads (Agente)
    participant Sheets as Google Sheets
    participant N8N_Agenda as n8n (Sincroniza Agenda)

    %% 1. Disparo de Campanha
    Operador->>N8N_Camp: Upload CSV & Seleção de Modelo (Humano ou Bot)
    N8N_Camp->>MySQL: Verifica Janela Preventiva de 24h (MYSQL - Verificar Janela 24h)
    alt Contato dentro das 24h de envio anterior
        N8N_Camp->>MySQL: Grava status = 'blocked_24h' (Envio impedido)
    else Contato Liberado (> 24h)
        alt Modo = Humano
            N8N_Camp->>Gateway: Ativa Lock Humano (/control/lock/{wa_id}/on) com fila/agente OML
        end
        N8N_Camp->>Meta: POST /messages (Disparo do Template)
        Meta-->>N8N_Camp: Retorna wamid (Message ID)
        N8N_Camp->>MySQL: Insere registro em campanha_contatos_resumo
    end

    %% 2. Notificação de Status
    Meta->>N8N_Camp: Webhook Status (delivered / read / failed)
    N8N_Camp->>MySQL: Atualiza status_envio e grava meta_eventos_auditoria

    %% 3. Resposta do Voluntário
    Paciente->>Meta: Responde à mensagem no WhatsApp
    Meta->>Gateway: Webhook mensagem recebida (inbound)
    Gateway->>N8N_Bot: POST /webhook/wa-bot-in

    %% 4. Tratamento Receptivo (Bot vs Humano)
    N8N_Bot->>PG_Bot: Deduplica message_id em processed_messages
    N8N_Bot->>MySQL: Checa trava em bot_contact_control
    alt Contato Travado em Modo Humano
        N8N_Bot-->>N8N_Bot: Interrompe execução do bot (Atendimento pertence ao OML)
    else Contato em Campanha Humana Recente
        N8N_Bot->>Meta: Envia "Por favor, informe seu nome completo e CPF"
        N8N_Bot->>MySQL: Atualiza solicitacao_nome_cpf_status = 'enviada'
    else Contato em Modo Bot
        N8N_Bot->>PG_Bot: Busca/Cria Sessão e Histórico (FSM determinística)
        N8N_Bot->>N8N_Bot: Executa Agente IA (Google Gemini)
        N8N_Bot->>Meta: Envia Próxima Pergunta / Mídia (Vídeo ou Link Form)
        alt Voluntário conclui triagem e solicita falar com atendente
            N8N_Bot->>Gateway: POST /webhook/whatsapp/handoff (Resumo de Triagem)
            Gateway->>OML: Envia lead para fila de atendimento humano
            N8N_Bot->>MySQL: Trava bot_contact_control (bot_locked = 1)
        end
    end

    %% 5. Agendamento e Conversão
    Paciente->>OML: Conclui conversa com agente humano e agenda consulta
    OML->>Sheets: Recepção insere linha na planilha AGENDA 2026
    Note over Sheets: Colunas: DATA, HORÁRIO, VIA=OMNILEADS, TELEFONE, PARTICIPANTE...

    %% 6. Sincronização e Atribuição
    loop A cada 15 minutos
        N8N_Agenda->>Sheets: Lê linhas com VIA DE ENTRADA = OMNILEADS
        N8N_Agenda->>N8N_Agenda: Normaliza telefone (DDI 55) e data/hora
        N8N_Agenda->>Sheets: Escreve ID_AGENDA_OML novo na coluna S (se ausente)
        N8N_Agenda->>MySQL: UPSERT em campanha_agendamentos com LEFT JOIN na última campanha válida
        Note over MySQL: Se achou envio anterior: attribution_status = 'atribuido'<br/>Se não achou: attribution_status = 'sem_campanha'
    end
```

---

## 4. Mecanismos de Proteção e Isolamento de Tráfego

Para garantir integridade operacional e segurança de dados, o ecossistema implementa três barreiras de proteção fundamentais:

### A. Prevenção Preventiva de Janela de 24 Horas (`blocked_24h`)
* **Problema evitado**: Reenvio acidental para contatos que já receberam mensagem nas últimas 24 horas, evitando custos desnecessários com a Meta e rejeições por política de frequência.
* **Mecanismo**: Antes de invocar a Meta Send API, o Fluxo 2 executa uma query analítica no MySQL verificando se existe registro para o mesmo telefone com `enviado_em >= NOW() - INTERVAL 24 HOUR`.
* **Ação**: Caso exista, o contato é inserido diretamente com `status_envio = 'blocked_24h'` e o loop pula o envio, salvando no campo de observação o ID da campanha anterior e o horário exato em que o contato será liberado.

### B. Trava de Colisão Bot vs. Humano (`bot_contact_control`)
* **Problema evitado**: O Bot de IA responder mensagens enquanto um operador humano do OmniLeads está em atendimento ativo com o paciente.
* **Mecanismo**:
  1. No disparo humano ou no momento do handoff, o `wa_gateway` e o MySQL registram `bot_locked = 1` com `source = 'agent'` e validade de 30 minutos renováveis por interação.
  2. No webhook de entrada (`wa-bot-in`), o nó `MYSQL - Check Bot Lock` valida a trava. Se `bot_locked = 1` e `updated_at >= NOW() - 30 MIN`, o fluxo encerra imediatamente no nó `BOT BLOQUEADO - STOP`.
  3. Sessões no PostgreSQL com `status = 'humano'` também desviam para o nó terminal `SESSÃO HUMANA - STOP`.

### C. Idempotência e Deduplicação de Mensagens (`processed_messages`)
* **Problema evitado**: Webhooks duplicados enviados pela Meta ou retentativas de rede gerando múltiplas respostas do bot para a mesma mensagem.
* **Mecanismo**: Toda mensagem recebida possui um `wamid` exclusivo. O nó `DB - Check Processed Message` consulta a tabela `unifag_bot.processed_messages`. Se já existir, a execução é descartada instantaneamente. Caso contrário, o ID é inserido e o processamento prossegue.
