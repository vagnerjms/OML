-- ====================================================================
-- BANCO DE DADOS: unifag_bot (PostgreSQL)
-- Dados semente (Seed Data) para simulação e testes do fluxo n8n
-- ====================================================================

SET search_path TO unifag_bot, public;

-- Inserir sessão de teste para 5511974605594 (Eduardo Souza)
INSERT INTO unifag_bot.sessoes_atendimento (
    id,
    canal,
    telefone,
    phone_number_id,
    nome_contato,
    conversation_id,
    etapa_atual,
    status,
    criado_em,
    atualizado_em,
    contexto
) VALUES (
    '5faf2c7d-971a-4b39-8832-68000bed1a81',
    'whatsapp',
    '5511974605594',
    '897759766750800',
    'Eduardo Souza',
    'conv_5511974605594',
    'handoff',
    'ativo',
    NOW() - INTERVAL '10 minutes',
    NOW() - INTERVAL '2 minutes',
    jsonb_build_object(
        'wa_id', '5511974605594',
        'campanha_nome', 'Coleta Pool',
        'template', 'coleta_pool',
        'message_text', 'Olá Aqui é da UNIFAG, devido a sua recente participação no estudo, estamos com um procedimento disponível com ajuda de custo, tem interesse? Clique em falar agora',
        'pergunta_atual', 'Você será direcionado para atendimento humano.\n\nTransferindo agora, um momento por favor.',
        'historico_qa', jsonb_build_array(
            jsonb_build_object('etapa', 'sem_etapa', 'pergunta', '', 'resposta', 'oi', 'registrado_em', (NOW() - INTERVAL '5 minutes')::text),
            jsonb_build_object('etapa', 'SOLICITAR_NOME', 'pergunta', 'Para prosseguirmos, por favor informe o seu nome completo.', 'resposta', 'Eduardo', 'registrado_em', (NOW() - INTERVAL '4 minutes')::text),
            jsonb_build_object('etapa', 'SOLICITAR_CPF', 'pergunta', 'Digite agora o seu CPF.', 'resposta', '11111111111', 'registrado_em', (NOW() - INTERVAL '3 minutes')::text),
            jsonb_build_object('etapa', 'MENU_PRINCIPAL', 'pergunta', 'Menu de opções:\n\n1 - Quero participar do estudo\n2 - Estou participando\n99 - Encerrar', 'resposta', '2', 'registrado_em', (NOW() - INTERVAL '2 minutes')::text)
        )
    )
) ON CONFLICT (id) DO NOTHING;

-- Inserir histórico de mensagens para a sessão
INSERT INTO unifag_bot.historico_mensagens (
    sessao_id,
    autor,
    mensagem,
    metadata,
    criado_em
) VALUES
(
    '5faf2c7d-971a-4b39-8832-68000bed1a81',
    'usuario',
    'oi',
    jsonb_build_object('tipo', 'mensagem_entrada', 'wa_id', '5511974605594', 'message_id', 'wamid.seed_001', 'timestamp', EXTRACT(EPOCH FROM NOW())::text),
    NOW() - INTERVAL '5 minutes'
),
(
    '5faf2c7d-971a-4b39-8832-68000bed1a81',
    'bot',
    'Seja bem-vindo(a) a UNIFAG.\n\nPara prosseguirmos, por favor informe o seu nome completo.',
    jsonb_build_object('tipo', 'mensagem_saida', 'etapa', 'SOLICITAR_NOME', 'handoff', false),
    NOW() - INTERVAL '4 minutes 50 seconds'
);

-- Inserir sessão para 5511934366104 (utilizada para testar o nó REMOVE HUMAM)
INSERT INTO unifag_bot.sessoes_atendimento (
    id,
    canal,
    telefone,
    phone_number_id,
    nome_contato,
    conversation_id,
    etapa_atual,
    status,
    criado_em,
    atualizado_em,
    contexto
) VALUES (
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    'whatsapp',
    '5511934366104',
    '897759766750800',
    'Contato Teste Remocao',
    'conv_5511934366104',
    'handoff',
    'humano',
    NOW() - INTERVAL '20 minutes',
    NOW() - INTERVAL '15 minutes',
    jsonb_build_object(
        'wa_id', '5511934366104',
        'motivo_handoff', 'atendente_humano'
    )
) ON CONFLICT (id) DO NOTHING;

INSERT INTO unifag_bot.historico_mensagens (
    sessao_id,
    autor,
    mensagem,
    metadata,
    criado_em
) VALUES (
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    'usuario',
    'preciso de atendente humano',
    jsonb_build_object('tipo', 'mensagem_entrada', 'wa_id', '5511934366104', 'message_id', 'wamid.seed_remove_001'),
    NOW() - INTERVAL '15 minutes'
);

INSERT INTO unifag_bot.processed_messages (
    message_id,
    created_at
) VALUES (
    'wamid.seed_remove_001',
    NOW() - INTERVAL '15 minutes'
) ON CONFLICT (message_id) DO NOTHING;
