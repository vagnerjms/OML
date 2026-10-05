INSERT INTO bot_atendimento_resumo (
  session_id,
  telefone,
  campanha_nome,
  template,
  message_text,
  motivo_handoff,
  ultima_mensagem_usuario,
  etapa_final,
  historico_consolidado,
  criado_em
) VALUES (
  '{{ $json.session_id }}',
  '{{ $json.telefone }}',
  '{{ ($json.campanha_nome || "").replace(/'/g, "''") }}',
  '{{ ($json.template || "").replace(/'/g, "''") }}',
  '{{ ($json.message_text || "").replace(/'/g, "''") }}',
  '{{ ($json.motivo_handoff || "").replace(/'/g, "''") }}',
  '{{ ($json.ultima_mensagem_usuario || "").replace(/'/g, "''") }}',
  'handoff',
  '{{ ($json.historico_consolidado || "").replace(/'/g, "''") }}',
  NOW()
)
ON DUPLICATE KEY UPDATE
  telefone = VALUES(telefone),
  campanha_nome = VALUES(campanha_nome),
  template = VALUES(template),
  message_text = VALUES(message_text),
  motivo_handoff = VALUES(motivo_handoff),
  ultima_mensagem_usuario = VALUES(ultima_mensagem_usuario),
  etapa_final = VALUES(etapa_final),
  historico_consolidado = VALUES(historico_consolidado),
  updated_at = CURRENT_TIMESTAMP;
