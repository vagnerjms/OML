-- ====================================================================
-- BANCO DE DADOS: bot_control (MySQL)
-- Dados semente (Seed Data) para simulação e testes do fluxo n8n
-- ====================================================================

USE bot_control;

-- 1. Dados em bot_contact_control
-- Contato principal do fluxo de teste (5511974605594): desbloqueado para o bot
INSERT INTO bot_contact_control (
    wa_id,
    bot_locked,
    lock_reason,
    source,
    session_status,
    updated_at
) VALUES (
    '5511974605594',
    0,
    'bot_active',
    'bot',
    'bot',
    NOW()
) ON DUPLICATE KEY UPDATE
    bot_locked = 0,
    session_status = 'bot',
    updated_at = NOW();

-- Contato para teste do nó 'Execute a SQL query2' e liberação manual (5511934366104)
INSERT INTO bot_contact_control (
    wa_id,
    bot_locked,
    lock_reason,
    source,
    session_status,
    updated_at
) VALUES (
    '5511934366104',
    1,
    'agent_started',
    'agent',
    'human',
    NOW()
) ON DUPLICATE KEY UPDATE
    bot_locked = 1,
    lock_reason = 'agent_started',
    session_status = 'human',
    updated_at = NOW();


-- 2. Dados em campanha_contatos_resumo
-- Registro de campanha recente para 5511974605594 (modo bot, enviado há 2 horas)
INSERT INTO campanha_contatos_resumo (
    wa_id,
    campanha_nome,
    template_name,
    message_text,
    modo_disparo,
    respondeu_cliente,
    primeira_mensagem_cliente,
    ultima_mensagem_cliente,
    quantidade_interacoes,
    primeira_resposta_em,
    ultima_resposta_bot,
    enviado_em,
    solicitacao_nome_cpf_status,
    solicitacao_nome_cpf_em,
    ultima_interacao_em
) VALUES (
    '5511974605594',
    'Coleta Pool',
    'coleta_pool',
    'Olá Aqui é da UNIFAG, devido a sua recente participação no estudo, estamos com um procedimento disponível com ajuda de custo, tem interesse? Clique em falar agora',
    'bot',
    0,
    NULL,
    NULL,
    0,
    NULL,
    NULL,
    NOW() - INTERVAL 2 HOUR,
    'nao_enviada',
    NULL,
    NULL
);

-- Registro de campanha recente para teste do fluxo Humano (5511999990001)
INSERT INTO campanha_contatos_resumo (
    wa_id,
    campanha_nome,
    template_name,
    message_text,
    modo_disparo,
    respondeu_cliente,
    primeira_mensagem_cliente,
    ultima_mensagem_cliente,
    quantidade_interacoes,
    primeira_resposta_em,
    ultima_resposta_bot,
    enviado_em,
    solicitacao_nome_cpf_status,
    solicitacao_nome_cpf_em,
    ultima_interacao_em
) VALUES (
    '5511999990001',
    'Campanha Atendimento Humano',
    'template_humano',
    'Olá, mensagem da campanha humana de teste.',
    'human',
    0,
    NULL,
    NULL,
    0,
    NULL,
    NULL,
    NOW() - INTERVAL 1 HOUR,
    'nao_enviada',
    NULL,
    NULL
);
