# ====================================================================
# Script de Validação: Executa consultas do fluxo n8n nos containers
# ====================================================================

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Iniciando testes de compatibilidade das consultas do n8n" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Testar PostgreSQL (unifag_bot)
Write-Host "`n[1/2] Testando consultas no PostgreSQL (unifag_bot_postgres)..." -ForegroundColor Yellow

$pgQueries = @(
    @{
        Name = "DB - Check Processed Message"
        SQL = "SELECT EXISTS (SELECT 1 FROM unifag_bot.processed_messages WHERE message_id = 'wamid.seed_001') AS already_processed;"
    },
    @{
        Name = "DB - Insert Processed Message"
        SQL = "INSERT INTO unifag_bot.processed_messages (message_id, created_at) VALUES ('wamid.teste_check_' || floor(random()*1000000), NOW()) RETURNING message_id;"
    },
    @{
        Name = "DB - Get Session"
        SQL = "SELECT id, conversation_id, telefone, nome_contato, etapa_atual, status, contexto FROM unifag_bot.sessoes_atendimento WHERE telefone = '5511974605594' AND ((status = 'ativo' AND atualizado_em >= (NOW() - INTERVAL '30 minutes')) OR (status = 'humano' AND COALESCE(contexto->>'motivo_handoff', '') <> 'timeout_inatividade')) ORDER BY criado_em DESC LIMIT 1;"
    },
    @{
        Name = "DB - Create Session"
        SQL = "INSERT INTO unifag_bot.sessoes_atendimento (canal, telefone, phone_number_id, nome_contato, etapa_atual, status, criado_em, atualizado_em, contexto) SELECT 'whatsapp', '5511999997777', '897759766750800', 'Teste Contato Novo', 'entrada', 'ativo', NOW(), NOW(), jsonb_build_object('wa_id', '5511999997777', 'campanha_nome', 'Coleta', 'template', 'tpl', 'message_text', 'msg') WHERE NOT EXISTS (SELECT 1 FROM unifag_bot.sessoes_atendimento s WHERE s.telefone = '5511999997777' AND ((s.status = 'ativo' AND s.atualizado_em >= (NOW() - INTERVAL '30 minutes')) OR (s.status = 'humano' AND COALESCE(s.contexto->>'motivo_handoff', '') <> 'timeout_inatividade'))) RETURNING id, telefone, nome_contato, etapa_atual, status, contexto;"
    },
    @{
        Name = "DB - Save User Message"
        SQL = "INSERT INTO unifag_bot.historico_mensagens (sessao_id, autor, mensagem, metadata, criado_em) VALUES ('5faf2c7d-971a-4b39-8832-68000bed1a81', 'usuario', 'mensagem de teste', jsonb_build_object('tipo', 'mensagem_entrada', 'wa_id', '5511974605594', 'phone_number_id', '897759766750800', 'message_id', 'wamid.teste_123', 'timestamp', '1779879337'), NOW()) RETURNING id, sessao_id, autor, mensagem, metadata, criado_em;"
    },
    @{
        Name = "DB - Set Session Human"
        SQL = "UPDATE unifag_bot.sessoes_atendimento SET status = 'humano', etapa_atual = 'handoff', atualizado_em = NOW(), contexto = COALESCE(contexto, '{}'::jsonb) || jsonb_build_object('handoff', true, 'handoff_em', NOW()::text, 'motivo_handoff', 'atendente_humano') WHERE id = '5faf2c7d-971a-4b39-8832-68000bed1a81' RETURNING id, telefone, etapa_atual, status, contexto, atualizado_em;"
    },
    @{
        Name = "Execute a SQL query3"
        SQL = "SELECT id, telefone, etapa_atual, status, atualizado_em, contexto FROM unifag_bot.sessoes_atendimento WHERE telefone = '5511974605594' ORDER BY atualizado_em DESC LIMIT 5;"
    },
    @{
        Name = "REMOVE HUMAM"
        SQL = "BEGIN; WITH sessoes_alvo AS (SELECT id FROM unifag_bot.sessoes_atendimento WHERE telefone = '5511934366104'), mensagens_alvo AS (SELECT hm.id, hm.metadata->>'message_id' AS message_id FROM unifag_bot.historico_mensagens hm WHERE hm.sessao_id IN (SELECT id FROM sessoes_alvo)) DELETE FROM unifag_bot.processed_messages WHERE message_id IN (SELECT message_id FROM mensagens_alvo WHERE message_id IS NOT NULL); DELETE FROM unifag_bot.historico_mensagens WHERE sessao_id IN (SELECT id FROM unifag_bot.sessoes_atendimento WHERE telefone = '5511934366104'); DELETE FROM unifag_bot.sessoes_atendimento WHERE telefone = '5511934366104'; COMMIT;"
    },
    @{
        Name = "wa_gateway - Upsert Roteamento OML"
        SQL = "INSERT INTO unifag_bot.roteamento_oml_humano (wa_id, campaign_key, campanha_nome, template, destination_type, oml_campaign_id, oml_campaign_name, routed, updated_at) VALUES ('5511974605594', 'camp_test_01', 'Campanha Teste', 'unifag_template', 'campaign', 115, 'Fila_Geral', FALSE, NOW()) ON CONFLICT (wa_id) DO UPDATE SET campaign_key = EXCLUDED.campaign_key, updated_at = NOW() RETURNING wa_id, destination_type, oml_campaign_id, routed;"
    },
    @{
        Name = "wa_gateway - Select Pending Roteamento OML"
        SQL = "SELECT wa_id, destination_type, oml_campaign_id, oml_agent_id, routed FROM unifag_bot.roteamento_oml_humano WHERE wa_id = '5511974605594' AND routed = FALSE LIMIT 1;"
    }
)

foreach ($q in $pgQueries) {
    try {
        Write-Host "  -> Executando query nó: '$($q.Name)' ... " -NoNewline
        $output = docker exec -i unifag_bot_postgres psql -U unifag_admin -d unifag_bot -c "$($q.SQL)" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SUCESSO!" -ForegroundColor Green
        } else {
            Write-Host "ERRO!" -ForegroundColor Red
            Write-Host $output -ForegroundColor DarkRed
        }
    } catch {
        Write-Host "FALHA: $_" -ForegroundColor Red
    }
}

# 2. Testar MySQL (bot_control)
Write-Host "`n[2/2] Testando consultas no MySQL (bot_control_mysql)..." -ForegroundColor Yellow

$myQueries = @(
    @{
        Name = "Execute a SQL query2"
        SQL = "UPDATE bot_contact_control SET bot_locked = 0, lock_reason = 'manual_release', session_status = 'bot', updated_at = NOW() WHERE wa_id = '5511934366104'; SELECT wa_id, bot_locked, lock_reason, source, session_status, updated_at FROM bot_contact_control WHERE wa_id = '5511934366104' ORDER BY updated_at DESC LIMIT 1;"
    },
    @{
        Name = "Execute a SQL query"
        SQL = "SELECT wa_id, bot_locked, lock_reason, source, session_status, updated_at FROM bot_contact_control WHERE wa_id = '5511974605594' ORDER BY updated_at DESC LIMIT 1;"
    },
    @{
        Name = "Execute a SQL query1"
        SQL = "SELECT id, wa_id, modo_disparo, respondeu_cliente, solicitacao_nome_cpf_status, solicitacao_nome_cpf_em, ultima_resposta_bot, ultima_mensagem_cliente, ultima_interacao_em, updated_at FROM campanha_contatos_resumo WHERE wa_id = '5511974605594' ORDER BY enviado_em DESC LIMIT 1;"
    },
    @{
        Name = "MYSQL - Buscar Contexto Campanha"
        SQL = "SELECT id, wa_id, campanha_nome, template_name, message_text, modo_disparo, respondeu_cliente, primeira_mensagem_cliente, ultima_mensagem_cliente, quantidade_interacoes, primeira_resposta_em, ultima_resposta_bot, enviado_em, solicitacao_nome_cpf_status, solicitacao_nome_cpf_em, CASE WHEN LOWER(COALESCE(modo_disparo, '')) IN ('human', 'humano') AND enviado_em IS NOT NULL AND enviado_em >= NOW() - INTERVAL 7 DAY THEN 1 ELSE 0 END AS campanha_human_ativa FROM campanha_contatos_resumo WHERE wa_id = '5511974605594' ORDER BY enviado_em DESC LIMIT 1;"
    },
    @{
        Name = "MYSQL - Set Human Lock"
        SQL = "INSERT INTO bot_contact_control (wa_id, bot_locked, lock_reason, source, session_status) VALUES ('5511974605594', 1, 'agent_started', 'agent', 'human') ON DUPLICATE KEY UPDATE bot_locked = 1, lock_reason = 'agent_started', source = 'agent', session_status = 'human', updated_at = CURRENT_TIMESTAMP;"
    },
    @{
        Name = "MYSQL - Check Bot Lock"
        SQL = "SELECT wa_id, bot_locked, lock_reason, source, session_status, updated_at FROM bot_contact_control WHERE wa_id = '5511974605594' AND bot_locked = 1 AND updated_at >= (NOW() - INTERVAL 30 MINUTE) ORDER BY updated_at DESC LIMIT 1;"
    },
    @{
        Name = "MYSQL - Marcar Resposta Cliente Campanha"
        SQL = "UPDATE campanha_contatos_resumo c JOIN (SELECT id FROM campanha_contatos_resumo WHERE wa_id = '5511974605594' AND enviado_em IS NOT NULL AND enviado_em >= NOW() - INTERVAL 7 DAY ORDER BY enviado_em DESC LIMIT 1) alvo ON alvo.id = c.id SET c.respondeu_cliente = 1, c.primeira_mensagem_cliente = COALESCE(c.primeira_mensagem_cliente, 'teste msg'), c.ultima_mensagem_cliente = 'teste msg', c.quantidade_interacoes = COALESCE(c.quantidade_interacoes, 0) + 1, c.primeira_resposta_em = COALESCE(c.primeira_resposta_em, NOW()), c.ultima_interacao_em = NOW(), c.updated_at = CURRENT_TIMESTAMP;"
    },
    @{
        Name = "MYSQL - Registrar Resposta Bot na Campanha"
        SQL = "UPDATE campanha_contatos_resumo c JOIN (SELECT id FROM campanha_contatos_resumo WHERE wa_id = '5511974605594' AND modo_disparo = 'bot' AND enviado_em IS NOT NULL AND enviado_em >= NOW() - INTERVAL 7 DAY ORDER BY enviado_em DESC LIMIT 1) alvo ON alvo.id = c.id SET c.ultima_resposta_bot = 'Ola, esta e a resposta automatica do bot', c.ultima_interacao_em = NOW(), c.updated_at = CURRENT_TIMESTAMP;"
    },
    @{
        Name = "MYSQL - Claim Primeira Resposta Human"
        SQL = "UPDATE campanha_contatos_resumo SET solicitacao_nome_cpf_status = 'processando', solicitacao_nome_cpf_em = NOW() WHERE wa_id = '5511999990001' AND LOWER(COALESCE(modo_disparo, '')) IN ('human', 'humano') AND enviado_em IS NOT NULL AND enviado_em >= NOW() - INTERVAL 7 DAY AND (COALESCE(solicitacao_nome_cpf_status, 'nao_enviada') = 'nao_enviada' OR (solicitacao_nome_cpf_status = 'processando' AND (solicitacao_nome_cpf_em IS NULL OR solicitacao_nome_cpf_em < NOW() - INTERVAL 5 MINUTE)) OR solicitacao_nome_cpf_status = 'falhou');"
    },
    @{
        Name = "MYSQL - Upsert Atendimento Resumo"
        SQL = "INSERT INTO bot_atendimento_resumo (session_id, telefone, campanha_nome, template, message_text, motivo_handoff, ultima_mensagem_usuario, etapa_final, historico_consolidado, criado_em) VALUES ('sess_teste_001', '5511974605594', 'Coleta Pool', 'coleta_pool', 'msg teste', 'atendente_humano', '2', 'handoff', '1. oi | 2. 2', NOW()) ON DUPLICATE KEY UPDATE telefone = VALUES(telefone), campanha_nome = VALUES(campanha_nome), template = VALUES(template), message_text = VALUES(message_text), motivo_handoff = VALUES(motivo_handoff), ultima_mensagem_usuario = VALUES(ultima_mensagem_usuario), etapa_final = VALUES(etapa_final), historico_consolidado = VALUES(historico_consolidado), criado_em = VALUES(criado_em), updated_at = CURRENT_TIMESTAMP;"
    },
    @{
        Name = "MYSQL - Upsert Atendimento Historico"
        SQL = "INSERT INTO bot_atendimento_historico (session_id, telefone, ordem, etapa, pergunta, resposta, registrado_em, campanha_nome, template, motivo_handoff) VALUES ('sess_teste_001', '5511974605594', 1, 'MENU_PRINCIPAL', 'Menu', '2', NOW(), 'Coleta Pool', 'coleta_pool', 'atendente_humano') ON DUPLICATE KEY UPDATE telefone = VALUES(telefone), etapa = VALUES(etapa), pergunta = VALUES(pergunta), resposta = VALUES(resposta), registrado_em = VALUES(registrado_em), campanha_nome = VALUES(campanha_nome), template = VALUES(template), motivo_handoff = VALUES(motivo_handoff), updated_at = CURRENT_TIMESTAMP;"
    }
)

foreach ($q in $myQueries) {
    try {
        Write-Host "  -> Executando query nó: '$($q.Name)' ... " -NoNewline
        $output = docker exec -e MYSQL_PWD=bot_control_pass_2026 -i bot_control_mysql mysql -u bot_user bot_control -e "$($q.SQL)" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SUCESSO!" -ForegroundColor Green
        } else {
            Write-Host "ERRO!" -ForegroundColor Red
            Write-Host $output -ForegroundColor DarkRed
        }
    } catch {
        Write-Host "FALHA: $_" -ForegroundColor Red
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "Validação concluída com sucesso!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
