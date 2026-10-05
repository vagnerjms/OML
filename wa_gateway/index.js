/**
 * wa_gateway - Gateway de Orquestração WhatsApp Meta, OMNiLeads e n8n
 * Referência: DB_UNG/docs/arquitetura/gateway-orquestracao.md
 */

const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const mysql = require('mysql2/promise');
const axios = require('axios');
const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const crypto = require('crypto');
require('dotenv').config();

const app = express();

// ============================================================================
// 1. MIDDLEWARES & BODY PARSER COM RAW BODY PARA VALIDAÇÃO META
// ============================================================================
app.use(cors());
app.use(
  express.json({
    limit: '25mb',
    verify: (req, res, buf) => {
      req.rawBody = buf.toString('utf8');
    },
  })
);
app.use(express.urlencoded({ extended: true, limit: '25mb' }));

// ============================================================================
// 2. CONFIGURAÇÃO E VARIÁVEIS DE AMBIENTE
// ============================================================================
const PORT = Number(process.env.PORT || 8088);
const VERIFY_TOKEN = process.env.VERIFY_TOKEN || 'usf_verify_token_seguro_2026';
const N8N_BOT_URL = process.env.N8N_BOT_URL || '';
const N8N_STATUS_URL = process.env.N8N_STATUS_URL || '';
const OML_HANDOFF_URL = process.env.OML_HANDOFF_URL || 'https://nginx/webhooks/whatsapp/incoming/';
const OML_API_BASE_URL = process.env.OML_API_BASE_URL || 'https://nginx';
const OML_USERNAME = process.env.OML_USERNAME || 'admin';
const OML_PASSWORD = process.env.OML_PASSWORD || 'admin';
const OML_TRUNK_CAMPAIGN_ID = Number(process.env.OML_TRUNK_CAMPAIGN_ID || 111);
const META_TOKEN = process.env.META_TOKEN || '';
const META_GRAPH_VERSION = process.env.META_GRAPH_VERSION || 'v20.0';
const META_WABA_ID = process.env.META_WABA_ID || '1156659843285011';
const META_APP_ID = process.env.META_APP_ID || '1937257670036344';
const PUBLIC_WEBHOOK_BASE_URL = process.env.PUBLIC_WEBHOOK_BASE_URL || `http://localhost:${PORT}`;

const MEDIA_CACHE_DIR = path.resolve(process.env.MEDIA_CACHE_DIR || path.join(__dirname, 'media-cache'));
const MEDIA_LINK_TTL_HOURS = Number(process.env.MEDIA_LINK_TTL_HOURS || 168); // 7 dias
const MEDIA_MAX_BYTES = Number(process.env.MEDIA_MAX_BYTES || 26214400); // 25MB
const MEDIA_PUBLIC_PREFIX = process.env.MEDIA_PUBLIC_PREFIX || '/meta/media';
const WEBHOOK_WATCHDOG_ENABLED = process.env.WEBHOOK_WATCHDOG_ENABLED === 'true';
const WEBHOOK_WATCHDOG_INTERVAL_MS = Number(process.env.WEBHOOK_WATCHDOG_INTERVAL_MS || 60000);

// Cria diretório de cache se não existir
if (!fs.existsSync(MEDIA_CACHE_DIR)) {
  fs.mkdirSync(MEDIA_CACHE_DIR, { recursive: true });
}

// Configuração de ignorar certificados autoassinados para conexões internas OML
const httpsAgent = new (require('https').Agent)({
  rejectUnauthorized: process.env.NODE_TLS_REJECT_UNAUTHORIZED === '1',
});

// ============================================================================
// 3. CAMADA DE BANCOS DE DADOS (POSTGRESQL & MYSQL)
// ============================================================================
const pgPool = new Pool({
  host: process.env.PGHOST || 'unifag_bot_postgres',
  port: Number(process.env.PGPORT || 5432),
  database: process.env.PGDATABASE || 'unifag_bot',
  user: process.env.PGUSER || 'unifag_admin',
  password: process.env.PGPASSWORD || 'unifag_bot_pass_2026',
  max: 10,
  idleTimeoutMillis: 30000,
});

let mysqlPool = null;
try {
  mysqlPool = mysql.createPool({
    host: process.env.MYSQL_HOST || 'bot_control_mysql',
    port: Number(process.env.MYSQL_PORT || 3306),
    database: process.env.MYSQL_DATABASE || 'bot_control',
    user: process.env.MYSQL_USER || 'bot_user',
    password: process.env.MYSQL_PASSWORD || 'bot_control_pass_2026',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0,
  });
} catch (err) {
  console.warn('[wa-gateway] Aviso: MySQL pool não inicializado:', err.message);
}

// ============================================================================
// 4. ENGINE DE TRAVAS DE ATENDIMENTO (humanLocks)
// ============================================================================
// Memória rápida: Map(wa_id => lockState)
const humanLocks = new Map();

/**
 * Carrega travas persistentes ativas dos bancos na inicialização
 */
async function loadPersistentHumanLocks() {
  try {
    const res = await pgPool.query(
      `SELECT wa_id, destination_type, oml_campaign_id, oml_campaign_name, oml_agent_id, oml_agent_name, campaign_key, template, routed
       FROM unifag_bot.roteamento_oml_humano
       WHERE routed = FALSE OR updated_at > NOW() - INTERVAL '24 hours'`
    );
    for (const row of res.rows) {
      humanLocks.set(row.wa_id, {
        destination_type: row.destination_type || 'campaign',
        oml_campaign_id: row.oml_campaign_id,
        oml_campaign_name: row.oml_campaign_name,
        oml_agent_id: row.oml_agent_id,
        oml_agent_name: row.oml_agent_name,
        campaign_key: row.campaign_key,
        template: row.template,
        routed: row.routed,
        timestamp: Date.now(),
      });
    }
    console.log(`[wa-gateway] ${humanLocks.size} travas humanas carregadas na memória.`);
  } catch (err) {
    console.error('[wa-gateway] Erro ao carregar travas persistentes do PostgreSQL:', err.message);
  }
}

/**
 * Ativa trava de atendimento humano para um número
 */
async function setHumanLock(waId, data = {}) {
  const cleanId = String(waId).replace(/\D/g, '');
  const lockInfo = {
    destination_type: data.destination_type || 'campaign',
    oml_campaign_id: data.oml_campaign_id ? Number(data.oml_campaign_id) : null,
    oml_campaign_name: data.oml_campaign_name || null,
    oml_agent_id: data.oml_agent_id ? Number(data.oml_agent_id) : null,
    oml_agent_name: data.oml_agent_name || null,
    campaign_key: data.campaign_key || null,
    template: data.template || null,
    lock_reason: data.lock_reason || 'atendimento_humano',
    source: data.source || 'n8n_flow',
    routed: false,
    timestamp: Date.now(),
  };

  // 1. Memória em menos de 1ms
  humanLocks.set(cleanId, lockInfo);

  // 2. Persistência no PostgreSQL
  try {
    await pgPool.query(
      `INSERT INTO unifag_bot.roteamento_oml_humano (
        wa_id, campaign_key, campanha_nome, template, destination_type, oml_campaign_id, oml_campaign_name, oml_agent_id, oml_agent_name, routed, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, FALSE, NOW())
      ON CONFLICT (wa_id) DO UPDATE SET
        campaign_key = COALESCE(EXCLUDED.campaign_key, unifag_bot.roteamento_oml_humano.campaign_key),
        destination_type = EXCLUDED.destination_type,
        oml_campaign_id = EXCLUDED.oml_campaign_id,
        oml_campaign_name = EXCLUDED.oml_campaign_name,
        oml_agent_id = EXCLUDED.oml_agent_id,
        oml_agent_name = EXCLUDED.oml_agent_name,
        routed = FALSE,
        updated_at = NOW()`,
      [
        cleanId,
        lockInfo.campaign_key,
        lockInfo.oml_campaign_name,
        lockInfo.template,
        lockInfo.destination_type,
        lockInfo.oml_campaign_id,
        lockInfo.oml_campaign_name,
        lockInfo.oml_agent_id,
        lockInfo.oml_agent_name,
      ]
    );

    await pgPool.query(
      `UPDATE unifag_bot.sessoes_atendimento 
       SET status = 'humano', atualizado_em = NOW() 
       WHERE telefone = $1 AND status = 'ativo'`,
      [cleanId]
    );
  } catch (err) {
    console.error(`[wa-gateway] Erro ao persistir trava PG para ${cleanId}:`, err.message);
  }

  // 3. Persistência no MySQL (bot_contact_control)
  if (mysqlPool) {
    try {
      await mysqlPool.query(
        `INSERT INTO bot_control.bot_contact_control (wa_id, bot_locked, lock_reason, source, session_status, updated_at)
         VALUES (?, 1, ?, ?, 'humano', NOW())
         ON DUPLICATE KEY UPDATE bot_locked = 1, lock_reason = VALUES(lock_reason), source = VALUES(source), session_status = 'humano', updated_at = NOW()`,
        [cleanId, lockInfo.lock_reason, lockInfo.source]
      );
    } catch (err) {
      console.warn(`[wa-gateway] Erro ao sincronizar trava no MySQL para ${cleanId}:`, err.message);
    }
  }

  return lockInfo;
}

/**
 * Remove trava de atendimento humano (devolve para o bot)
 */
async function removeHumanLock(waId) {
  const cleanId = String(waId).replace(/\D/g, '');
  humanLocks.delete(cleanId);

  // PostgreSQL
  try {
    await pgPool.query(
      `UPDATE unifag_bot.roteamento_oml_humano SET routed = TRUE, updated_at = NOW() WHERE wa_id = $1`,
      [cleanId]
    );
    await pgPool.query(
      `UPDATE unifag_bot.sessoes_atendimento SET status = 'ativo', atualizado_em = NOW() WHERE telefone = $1 AND status = 'humano'`,
      [cleanId]
    );
  } catch (err) {
    console.error(`[wa-gateway] Erro ao liberar trava PG para ${cleanId}:`, err.message);
  }

  // MySQL
  if (mysqlPool) {
    try {
      await mysqlPool.query(
        `UPDATE bot_control.bot_contact_control 
         SET bot_locked = 0, lock_reason = NULL, session_status = 'ativo', updated_at = NOW() 
         WHERE wa_id = ?`,
        [cleanId]
      );
    } catch (err) {
      console.warn(`[wa-gateway] Erro ao liberar trava no MySQL para ${cleanId}:`, err.message);
    }
  }
}

// ============================================================================
// 5. CLIENTE DE INTEGRAÇÃO COM O OMNILEADS (omlClient)
// ============================================================================
class OMLClient {
  constructor() {
    this.sessionCookies = null;
    this.csrfToken = null;
    this.lastLogin = 0;
  }

  async ensureLogin() {
    // Reutiliza sessão por até 30 minutos
    if (this.sessionCookies && Date.now() - this.lastLogin < 30 * 60 * 1000) {
      return;
    }

    try {
      const loginUrl = `${OML_API_BASE_URL}/accounts/login/`;
      // 1. GET para pegar o csrftoken inicial
      const initialRes = await axios.get(loginUrl, {
        httpsAgent,
        timeout: 10000,
        validateStatus: () => true,
      });

      const setCookies = initialRes.headers['set-cookie'] || [];
      let initialCsrf = '';
      for (const cookie of setCookies) {
        const match = cookie.match(/csrftoken=([^;]+)/);
        if (match) initialCsrf = match[1];
      }

      // 2. POST login com credenciais
      const params = new URLSearchParams();
      params.append('username', OML_USERNAME);
      params.append('password', OML_PASSWORD);
      params.append('csrfmiddlewaretoken', initialCsrf);

      const loginRes = await axios.post(loginUrl, params.toString(), {
        httpsAgent,
        timeout: 15000,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          Referer: loginUrl,
          Cookie: `csrftoken=${initialCsrf}`,
        },
        maxRedirects: 0,
        validateStatus: (status) => status === 200 || status === 302,
      });

      const loginCookies = loginRes.headers['set-cookie'] || [];
      const cookieJar = {};
      cookieJar['csrftoken'] = initialCsrf;

      for (const cookie of [...setCookies, ...loginCookies]) {
        const parts = cookie.split(';')[0].split('=');
        if (parts.length === 2) {
          cookieJar[parts[0].trim()] = parts[1].trim();
        }
      }

      this.csrfToken = cookieJar['csrftoken'];
      this.sessionCookies = Object.entries(cookieJar)
        .map(([k, v]) => `${k}=${v}`)
        .join('; ');
      this.lastLogin = Date.now();

      console.log('[wa-gateway] Autenticado com sucesso no OMNiLeads Django.');
    } catch (err) {
      console.error('[wa-gateway] Falha ao autenticar no OMNiLeads:', err.message);
    }
  }

  async getHeaders() {
    await this.ensureLogin();
    return {
      Cookie: this.sessionCookies || '',
      'X-CSRFToken': this.csrfToken || '',
      Referer: OML_API_BASE_URL,
    };
  }

  async filterChats(phone, campaignId = OML_TRUNK_CAMPAIGN_ID) {
    try {
      const headers = await this.getHeaders();
      const url = `${OML_API_BASE_URL}/api/v1/whatsapp/chat/${campaignId}/filter_chats/`;
      const res = await axios.post(url, { phone }, { headers, httpsAgent, timeout: 10000 });
      return res.data;
    } catch (err) {
      console.warn(`[wa-gateway] Erro em filterChats (${phone}):`, err.response?.data || err.message);
      return null;
    }
  }

  async transferToCampaign(conversationId, targetCampaignId) {
    try {
      const headers = await this.getHeaders();
      const url = `${OML_API_BASE_URL}/api/v1/whatsapp/transfer/to_campaign/`;
      const res = await axios.post(
        url,
        { conversation_id: conversationId, to: targetCampaignId },
        { headers, httpsAgent, timeout: 10000 }
      );
      return res.data;
    } catch (err) {
      console.error(`[wa-gateway] Erro ao transferir chat ${conversationId} para campanha ${targetCampaignId}:`, err.response?.data || err.message);
      throw err;
    }
  }

  async transferToAgent(conversationId, campaignId, targetAgentId) {
    try {
      const headers = await this.getHeaders();
      const url = `${OML_API_BASE_URL}/api/v1/whatsapp/transfer/${campaignId}/agents/`;
      const res = await axios.post(
        url,
        { conversation_id: conversationId, agent_id: targetAgentId },
        { headers, httpsAgent, timeout: 10000 }
      );
      return res.data;
    } catch (err) {
      console.error(`[wa-gateway] Erro ao transferir chat ${conversationId} para agente ${targetAgentId}:`, err.response?.data || err.message);
      throw err;
    }
  }

  async listCampaigns() {
    try {
      const headers = await this.getHeaders();
      const url = `${OML_API_BASE_URL}/api/v1/campaigns/`;
      const res = await axios.get(url, { headers, httpsAgent, timeout: 10000 });
      return res.data;
    } catch (err) {
      console.warn('[wa-gateway] Erro ao listar campanhas OML:', err.message);
      return [];
    }
  }

  async forwardIncomingMessage(payload) {
    try {
      const headers = await this.getHeaders();
      headers['Content-Type'] = 'application/json';
      const res = await axios.post(OML_HANDOFF_URL, payload, { headers, httpsAgent, timeout: 10000 });
      return res.data;
    } catch (err) {
      console.error('[wa-gateway] Erro ao encaminhar webhook para OMNiLeads:', err.response?.data || err.message);
      throw err;
    }
  }
}

const omlClient = new OMLClient();

// ============================================================================
// 6. PONTE DE MÍDIA COM CACHE LOCAL (mediaBridge)
// ============================================================================
const mediaTokens = new Map(); // token => { filepath, mimeType, createdAt }

async function downloadMetaMedia(mediaId, mimeType = 'application/octet-stream') {
  if (!META_TOKEN) return null;

  try {
    // 1. Obter URL temporária da Meta
    const metaUrl = `https://graph.facebook.com/${META_GRAPH_VERSION}/${mediaId}`;
    const infoRes = await axios.get(metaUrl, {
      headers: { Authorization: `Bearer ${META_TOKEN}` },
      timeout: 10000,
    });

    const fileDownloadUrl = infoRes.data?.url;
    if (!fileDownloadUrl) return null;

    // 2. Download do binário
    const binaryRes = await axios.get(fileDownloadUrl, {
      headers: { Authorization: `Bearer ${META_TOKEN}` },
      responseType: 'arraybuffer',
      maxContentLength: MEDIA_MAX_BYTES,
      timeout: 30000,
    });

    const token = crypto.randomBytes(24).toString('hex');
    const ext = mimeType.split('/')[1] ? mimeType.split('/')[1].split(';')[0] : 'bin';
    const filename = `${token}.${ext}`;
    const filepath = path.join(MEDIA_CACHE_DIR, filename);

    await fsp.writeFile(filepath, binaryRes.data);

    mediaTokens.set(token, {
      filepath,
      mimeType,
      createdAt: Date.now(),
    });

    return `${PUBLIC_WEBHOOK_BASE_URL}${MEDIA_PUBLIC_PREFIX}/${token}`;
  } catch (err) {
    console.error(`[wa-gateway] Erro no download da mídia Meta (${mediaId}):`, err.message);
    return null;
  }
}

// Limpeza de arquivos expirados
function cleanupExpiredMedia() {
  const maxAgeMs = MEDIA_LINK_TTL_HOURS * 3600 * 1000;
  const now = Date.now();

  for (const [token, info] of mediaTokens.entries()) {
    if (now - info.createdAt > maxAgeMs) {
      if (fs.existsSync(info.filepath)) {
        try {
          fs.unlinkSync(info.filepath);
        } catch (_) {}
      }
      mediaTokens.delete(token);
    }
  }
}
setInterval(cleanupExpiredMedia, 3600 * 1000); // Roda a cada 1 hora

// ============================================================================
// 7. WATCHDOG DE SUBSCRIÇÃO DA META (runWebhookOwnershipWatchdog)
// ============================================================================
async function runWebhookOwnershipWatchdog() {
  if (!WEBHOOK_WATCHDOG_ENABLED || !META_TOKEN) return;

  try {
    const url = `https://graph.facebook.com/${META_GRAPH_VERSION}/${META_WABA_ID}/subscribed_apps`;
    const res = await axios.get(url, {
      headers: { Authorization: `Bearer ${META_TOKEN}` },
      timeout: 10000,
    });

    const apps = res.data?.data || [];
    const isSubscribed = apps.some((app) => String(app.whatsapp_business_api_data?.id || app.id) === String(META_APP_ID));

    if (!isSubscribed) {
      console.warn(`[wa-gateway] Watchdog: App ${META_APP_ID} desinscrito! Executando auto-reparo...`);
      await axios.post(url, {}, { headers: { Authorization: `Bearer ${META_TOKEN}` }, timeout: 10000 });
      console.log(`[wa-gateway] Watchdog: App ${META_APP_ID} reinscrito com sucesso.`);
    }
  } catch (err) {
    console.warn('[wa-gateway] Watchdog: Falha na verificação de subscrição:', err.response?.data || err.message);
  }
}

if (WEBHOOK_WATCHDOG_ENABLED) {
  setInterval(runWebhookOwnershipWatchdog, WEBHOOK_WATCHDOG_INTERVAL_MS);
}

// ============================================================================
// 8. ROTAS HTTP / API REST DO GATEWAY
// ============================================================================

// --- Health Check ---
app.get('/health', async (req, res) => {
  let dbOk = false;
  try {
    const r = await pgPool.query('SELECT 1');
    dbOk = r.rowCount === 1;
  } catch (_) {}

  res.json({
    status: 'ok',
    service: 'wa_gateway',
    uptime_seconds: Math.floor(process.uptime()),
    active_human_locks: humanLocks.size,
    db_postgres: dbOk ? 'connected' : 'disconnected',
    oml_authenticated: Boolean(omlClient.sessionCookies),
    watchdog_enabled: WEBHOOK_WATCHDOG_ENABLED,
    timestamp: new Date().toISOString(),
  });
});

// --- Validação Webhook Meta (GET) ---
app.get('/webhook/unifag-meta', (req, res) => {
  const mode = req.query['hub.mode'];
  const token = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];

  if (mode === 'subscribe' && token === VERIFY_TOKEN) {
    console.log('[wa-gateway] Webhook Meta verificado com sucesso!');
    return res.status(200).send(challenge);
  }
  return res.status(403).send('Forbidden: Token incorreto.');
});

// --- Ingestão de Webhooks Meta (POST) ---
app.post('/webhook/unifag-meta', async (req, res) => {
  const payload = req.body;

  // Responder 200 imediatamente para a Meta não reenviar
  res.status(200).json({ status: 'received' });

  try {
    const entry = payload?.entry?.[0];
    const changes = entry?.changes?.[0];
    const value = changes?.value;

    if (!value) return;

    // 1. Tratamento de Statuses (enviado, entregue, lido) -> Encaminha para Fluxo 2 do n8n
    if (value.statuses && value.statuses.length > 0) {
      if (N8N_STATUS_URL) {
        axios.post(N8N_STATUS_URL, payload).catch((err) => {
          console.warn('[wa-gateway] Falha ao entregar status no n8n:', err.message);
        });
      }
      return;
    }

    // 2. Tratamento de Mensagens Inbound
    if (value.messages && value.messages.length > 0) {
      for (const msg of value.messages) {
        const waId = msg.from;
        const isLocked = humanLocks.has(waId);

        if (isLocked) {
          // --- MODO HUMANO: Encaminha para OMNiLeads ---
          const lockInfo = humanLocks.get(waId);
          console.log(`[wa-gateway] Mensagem de ${waId} em MODO HUMANO. Encaminhando para OMNiLeads...`);

          // Processar mídias se houver
          const mediaType = ['image', 'audio', 'video', 'document', 'sticker'].find((t) => msg[t]);
          if (mediaType && msg[mediaType]?.id) {
            const cachedUrl = await downloadMetaMedia(msg[mediaType].id, msg[mediaType].mime_type);
            if (cachedUrl) {
              msg[mediaType].link = cachedUrl;
            }
          }

          // Enviar ao OMNiLeads
          try {
            await omlClient.forwardIncomingMessage(payload);
          } catch (omlErr) {
            console.error(`[wa-gateway] Falha ao entregar mensagem no OMNiLeads:`, omlErr.message);
          }

          // Executar transferência de chat se ainda não foi roteado
          if (!lockInfo.routed && (lockInfo.oml_campaign_id || lockInfo.oml_agent_id)) {
            try {
              const chats = await omlClient.filterChats(waId);
              const conversation = chats?.conversations?.[0] || chats?.[0];
              if (conversation && conversation.id) {
                if (lockInfo.destination_type === 'campaign' && lockInfo.oml_campaign_id) {
                  await omlClient.transferToCampaign(conversation.id, lockInfo.oml_campaign_id);
                  lockInfo.routed = true;
                } else if (lockInfo.destination_type === 'agent' && lockInfo.oml_agent_id) {
                  await omlClient.transferToAgent(conversation.id, lockInfo.oml_campaign_id || OML_TRUNK_CAMPAIGN_ID, lockInfo.oml_agent_id);
                  lockInfo.routed = true;
                }

                if (lockInfo.routed) {
                  await pgPool.query(
                    `UPDATE unifag_bot.roteamento_oml_humano SET routed = TRUE, routed_at = NOW(), conversation_id = $1 WHERE wa_id = $2`,
                    [conversation.id, waId]
                  );
                }
              }
            } catch (transErr) {
              console.warn(`[wa-gateway] Erro ao transferir chat OML para ${waId}:`, transErr.message);
            }
          }

          // Notificação assíncrona ao n8n se for primeira resposta da campanha humana (solicitar nome/CPF)
          if (N8N_BOT_URL && lockInfo.source === 'campanha_humana' && !lockInfo.promptSent) {
            lockInfo.promptSent = true;
            axios.post(N8N_BOT_URL, {
              type: 'human_campaign_first_response',
              wa_id: waId,
              message: msg,
            }).catch(() => {});
          }
        } else {
          // --- MODO BOT: Encaminha para o n8n (Fluxo 4) ---
          console.log(`[wa-gateway] Mensagem de ${waId} em MODO BOT. Encaminhando para n8n...`);
          if (N8N_BOT_URL) {
            axios.post(N8N_BOT_URL, payload).catch((err) => {
              console.error(`[wa-gateway] Falha ao encaminhar mensagem para o n8n (${N8N_BOT_URL}):`, err.message);
            });
          } else {
            console.warn('[wa-gateway] N8N_BOT_URL não configurada; mensagem descartada do bot.');
          }
        }
      }
    }
  } catch (err) {
    console.error('[wa-gateway] Erro no processamento de webhook:', err);
  }
});

// --- Servir Mídia em Cache ---
app.get('/meta/media/:token', (req, res) => {
  const { token } = req.params;
  const info = mediaTokens.get(token);

  if (!info || !fs.existsSync(info.filepath)) {
    return res.status(404).send('Mídia não encontrada ou expirada.');
  }

  res.setHeader('Content-Type', info.mimeType);
  res.sendFile(info.filepath);
});

// --- Controle de Travas (Lock ON / Lock OFF) ---
app.post('/control/lock/:wa_id/on', async (req, res) => {
  const { wa_id } = req.params;
  try {
    const lockInfo = await setHumanLock(wa_id, req.body);
    res.json({ success: true, wa_id, locked: true, details: lockInfo });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/control/lock/:wa_id/off', async (req, res) => {
  const { wa_id } = req.params;
  try {
    await removeHumanLock(wa_id);
    res.json({ success: true, wa_id, locked: false });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.get('/control/lock/:wa_id', (req, res) => {
  const { wa_id } = req.params;
  const cleanId = String(wa_id).replace(/\D/g, '');
  const isLocked = humanLocks.has(cleanId);
  res.json({ wa_id: cleanId, locked: isLocked, details: humanLocks.get(cleanId) || null });
});

app.get('/control/locks', (req, res) => {
  const result = [];
  for (const [wa_id, data] of humanLocks.entries()) {
    result.push({ wa_id, ...data });
  }
  res.json({ total: result.length, locks: result });
});

// --- Handoff do n8n para OMNiLeads ---
app.post('/webhook/whatsapp/handoff', async (req, res) => {
  const { wa_id, destination_type, oml_campaign_id, oml_agent_id, oml_campaign_name, summary } = req.body;

  if (!wa_id) {
    return res.status(400).json({ error: 'wa_id obrigatório' });
  }

  try {
    await setHumanLock(wa_id, {
      destination_type: destination_type || 'campaign',
      oml_campaign_id,
      oml_agent_id,
      oml_campaign_name,
      lock_reason: 'handoff_ia_triagem',
      source: 'n8n_flow_4',
    });

    // Se informou summary de triagem, salvar no histórico de mensagens do Postgres
    if (summary) {
      await pgPool.query(
        `INSERT INTO unifag_bot.historico_mensagens (sessao_id, papel, conteudo, metadata)
         SELECT id, 'sistema', $2, jsonb_build_object('evento', 'handoff', 'resumo', $2)
         FROM unifag_bot.sessoes_atendimento WHERE telefone = $1 ORDER BY criado_em DESC LIMIT 1`,
        [wa_id, `[RESUMO TRIAGEM IA]: ${summary}`]
      ).catch(() => {});
    }

    res.json({ success: true, message: `Handoff executado para ${wa_id}` });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/webhook/whatsapp/release', async (req, res) => {
  const { wa_id } = req.body;
  if (!wa_id) return res.status(400).json({ error: 'wa_id obrigatório' });
  await removeHumanLock(wa_id);
  res.json({ success: true, message: `Trava liberada para ${wa_id}` });
});

// --- Consultas OMNiLeads ---
app.get('/control/oml/campaigns', async (req, res) => {
  try {
    const data = await omlClient.listCampaigns();
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// --- Disparo Manual do Watchdog ---
app.get('/control/meta-watchdog', async (req, res) => {
  await runWebhookOwnershipWatchdog();
  res.json({ success: true, message: 'Watchdog executado com sucesso.' });
});

// ============================================================================
// 9. INICIALIZAÇÃO DO SERVIDOR
// ============================================================================
app.listen(PORT, '0.0.0.0', async () => {
  console.log(`================================================================`);
  console.log(`  wa_gateway ativo e escutando na porta ${PORT}`);
  console.log(`  Meta Webhook URL: http://0.0.0.0:${PORT}/webhook/unifag-meta`);
  console.log(`  Health Check:     http://0.0.0.0:${PORT}/health`);
  console.log(`================================================================`);

  // Carregar travas persistentes
  await loadPersistentHumanLocks();

  // Testar login no OMNiLeads
  omlClient.ensureLogin().catch(() => {});
});
