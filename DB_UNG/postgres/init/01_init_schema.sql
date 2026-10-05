-- ====================================================================
-- BANCO DE DADOS: unifag_bot (PostgreSQL)
-- Schema e tabelas necessários para o fluxo n8n Bot UNIFAG
-- ====================================================================

-- Habilitar extensão para geração de UUID
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Criar schema unifag_bot
CREATE SCHEMA IF NOT EXISTS unifag_bot;

-- Definir search_path padrão para unifag_bot e public
SET search_path TO unifag_bot, public;
ALTER DATABASE unifag_bot SET search_path TO unifag_bot, public;

-- --------------------------------------------------------------------
-- 1. Tabela: processed_messages
-- Utilizada pelos nós:
--   - DB - Check Processed Message
--   - DB - Insert Processed Message
--   - REMOVE HUMAM
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS unifag_bot.processed_messages (
    id BIGSERIAL PRIMARY KEY,
    message_id VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_processed_messages_id ON unifag_bot.processed_messages(message_id);
CREATE INDEX IF NOT EXISTS idx_processed_messages_created ON unifag_bot.processed_messages(created_at);

-- --------------------------------------------------------------------
-- 2. Tabela: sessoes_atendimento
-- Utilizada pelos nós:
--   - DB - Get Session
--   - DB - Create Session
--   - DB - Update Session Stage
--   - DB - Update Session Stage1
--   - DB - Update Session Stage2
--   - DB - Set Session Human
--   - DB - Close Session After Form Leads
--   - DB - Check Recent Closed Session
--   - Execute a SQL query3
--   - REMOVE HUMAM
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS unifag_bot.sessoes_atendimento (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    canal VARCHAR(50) NOT NULL DEFAULT 'whatsapp',
    telefone VARCHAR(50) NOT NULL,
    phone_number_id VARCHAR(50),
    nome_contato VARCHAR(255),
    conversation_id VARCHAR(255),
    etapa_atual VARCHAR(100) NOT NULL DEFAULT 'entrada',
    status VARCHAR(50) NOT NULL DEFAULT 'ativo', -- 'ativo', 'humano', 'encerrado'
    criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    contexto JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_sessoes_telefone_status ON unifag_bot.sessoes_atendimento(telefone, status, atualizado_em);
CREATE INDEX IF NOT EXISTS idx_sessoes_criado_em ON unifag_bot.sessoes_atendimento(criado_em DESC);
CREATE INDEX IF NOT EXISTS idx_sessoes_atualizado_em ON unifag_bot.sessoes_atendimento(atualizado_em DESC);

-- --------------------------------------------------------------------
-- 3. Tabela: historico_mensagens
-- Utilizada pelos nós:
--   - DB - Save User Message
--   - DB - Save User Message Existing Session
--   - DB - Save Bot Message
--   - DB - Save Bot Message Form Leads
--   - REMOVE HUMAM
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS unifag_bot.historico_mensagens (
    id BIGSERIAL PRIMARY KEY,
    sessao_id UUID NOT NULL REFERENCES unifag_bot.sessoes_atendimento(id) ON DELETE CASCADE,
    autor VARCHAR(50) NOT NULL, -- 'usuario', 'bot'
    mensagem TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_historico_sessao_id ON unifag_bot.historico_mensagens(sessao_id);
CREATE INDEX IF NOT EXISTS idx_historico_criado_em ON unifag_bot.historico_mensagens(criado_em DESC);

-- --------------------------------------------------------------------
-- 4. Tabela: n8n_chat_histories (LangChain Postgres Chat Memory)
-- Utilizada pelo nó:
--   - Postgres Chat Memory (@n8n/n8n-nodes-langchain.memoryPostgresChat)
-- Criamos tanto em public quanto em unifag_bot para garantir compatibilidade total.
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.n8n_chat_histories (
    id SERIAL PRIMARY KEY,
    session_id VARCHAR(255) NOT NULL,
    message JSONB NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_n8n_chat_histories_session_id ON public.n8n_chat_histories(session_id);

CREATE TABLE IF NOT EXISTS unifag_bot.n8n_chat_histories (
    id SERIAL PRIMARY KEY,
    session_id VARCHAR(255) NOT NULL,
    message JSONB NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_unifag_chat_histories_session_id ON unifag_bot.n8n_chat_histories(session_id);

-- --------------------------------------------------------------------
-- 5. Tabela: roteamento_oml_humano (Gerenciado por wa_gateway)
-- Utilizada para roteamento de campanhas humanas e transferência no OML
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS unifag_bot.roteamento_oml_humano (
    wa_id VARCHAR(50) PRIMARY KEY,
    campaign_key VARCHAR(120),
    campanha_nome VARCHAR(255),
    template VARCHAR(255),
    destination_type VARCHAR(50),
    oml_campaign_id INT,
    oml_campaign_name VARCHAR(255),
    oml_agent_id INT,
    oml_agent_name VARCHAR(255),
    conversation_id INT,
    routed BOOLEAN NOT NULL DEFAULT FALSE,
    routed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_roteamento_oml_routed ON unifag_bot.roteamento_oml_humano(routed, updated_at);
