-- ====================================================================
-- BANCO DE DADOS: bot_control (MySQL)
-- Schema e tabelas necessários para o fluxo n8n Bot UNIFAG
-- ====================================================================

CREATE DATABASE IF NOT EXISTS bot_control
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE bot_control;

-- --------------------------------------------------------------------
-- 1. Tabela: bot_contact_control
-- Utilizada pelos nós:
--   - Execute a SQL query2
--   - Execute a SQL query
--   - MYSQL - Check Bot Lock
--   - MYSQL - Set Human Lock
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bot_contact_control (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    wa_id VARCHAR(50) NOT NULL,
    bot_locked TINYINT(1) NOT NULL DEFAULT 0,
    lock_reason VARCHAR(255) NULL,
    source VARCHAR(100) NULL,
    session_status VARCHAR(100) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_wa_id (wa_id),
    KEY idx_wa_id_locked_updated (wa_id, bot_locked, updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------------------
-- 2. Tabela: campanha_contatos_resumo
-- Utilizada pelos nós:
--   - Execute a SQL query1
--   - MYSQL - Buscar Contexto Campanha
--   - MYSQL - Marcar Resposta Cliente Campanha
--   - MYSQL - Registrar Resposta Bot na Campanha
--   - MYSQL - Claim Primeira Resposta Human
--   - MYSQL - Registrar Solicitação Nome CPF Human
--   - MYSQL - Atualizar Interação Human
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS campanha_contatos_resumo (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    wa_id VARCHAR(50) NOT NULL,
    campanha_nome VARCHAR(255) NULL,
    template_name VARCHAR(255) NULL,
    message_text TEXT NULL,
    modo_disparo VARCHAR(50) NOT NULL DEFAULT 'bot',
    respondeu_cliente TINYINT(1) NOT NULL DEFAULT 0,
    primeira_mensagem_cliente TEXT NULL,
    ultima_mensagem_cliente TEXT NULL,
    quantidade_interacoes INT NOT NULL DEFAULT 0,
    primeira_resposta_em DATETIME NULL,
    ultima_resposta_bot TEXT NULL,
    enviado_em DATETIME NULL,
    solicitacao_nome_cpf_status VARCHAR(50) NOT NULL DEFAULT 'nao_enviada',
    solicitacao_nome_cpf_em DATETIME NULL,
    ultima_interacao_em DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_wa_id_enviado (wa_id, enviado_em),
    KEY idx_modo_enviado (modo_disparo, enviado_em)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------------------
-- 3. Tabela: bot_atendimento_resumo
-- Utilizada pelo nó:
--   - MYSQL - Upsert Atendimento Resumo
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bot_atendimento_resumo (
    session_id VARCHAR(100) NOT NULL,
    telefone VARCHAR(50) NOT NULL,
    campanha_nome VARCHAR(255) NULL,
    template VARCHAR(255) NULL,
    message_text TEXT NULL,
    motivo_handoff VARCHAR(255) NULL,
    ultima_mensagem_usuario TEXT NULL,
    etapa_final VARCHAR(100) NULL,
    historico_consolidado LONGTEXT NULL,
    criado_em DATETIME NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (session_id),
    KEY idx_resumo_telefone (telefone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------------------
-- 4. Tabela: bot_atendimento_historico
-- Utilizada pelo nó:
--   - MYSQL - Upsert Atendimento Historico
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bot_atendimento_historico (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    session_id VARCHAR(100) NOT NULL,
    telefone VARCHAR(50) NOT NULL,
    ordem INT NOT NULL,
    etapa VARCHAR(100) NULL,
    pergunta TEXT NULL,
    resposta TEXT NULL,
    registrado_em DATETIME NULL,
    campanha_nome VARCHAR(255) NULL,
    template VARCHAR(255) NULL,
    motivo_handoff VARCHAR(255) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_session_ordem (session_id, ordem),
    KEY idx_historico_telefone (telefone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
