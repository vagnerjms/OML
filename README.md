# Ecossistema OMniLeads + WhatsApp Gateway + UNIFAG

Este repositório centraliza a infraestrutura e os microsserviços para a operação integrada do **OMniLeads** com canais de atendimento WhatsApp, microsserviço de mensageria (**`wa_gateway`**), bancos de dados de controle/auditoria (**`DB_UNG`**) e fluxos de automação (**n8n**).

---

## 🏗️ Arquitetura do Sistema

```
                     ┌──────────────────────────────────────────────┐
                     │                Evolution API /               │
                     │                 WhatsApp Cloud               │
                     └──────────────────────┬───────────────────────┘
                                            │ Webhook (Mensagens / Status)
                                            ▼
┌─────────────────┐  REST API       ┌───────────────┐  Notificações   ┌──────────────────┐
│    OMniLeads    │ ◄─────────────► │  wa_gateway   │ ──────────────► │       n8n        │
│ (Contact Center)│                 │ (Porta 8088)  │                 │ (Hospedado na VPS│
└─────────────────┘                 └───────┬───────┘                 └──────────────────┘
                                            │
                                            ├─────────────┐
                                            ▼             ▼
                                     ┌────────────┐ ┌───────────┐
                                     │ PostgreSQL │ │   MySQL   │
                                     │  (UNIFAG)  │ │ (Controle)│
                                     │ Porta 5434 │ │Porta 3306 │
                                     └────────────┘ └───────────┘
```

---

## 📁 Componentes do Projeto

| Diretório / Módulo | Descrição | Status / Porta |
| :--- | :--- | :--- |
| **`omldeploytool/`** | Stack Docker completa do OMniLeads (PBX, Nginx, Django, RTPEngine, Redis, etc.) | `443` (Web HTTPS) / `8008` (WS) |
| **`DB_UNG/`** | Bancos de dados relacionais para o bot e controle de mensagens | Postgres `5434` / MySQL `3306` |
| **`wa_gateway/`** | Gateway em Node.js (Express) que conecta WhatsApp, OMniLeads e n8n | `8088` (HTTP API) |
| **`n8n`** | Orquestrador de fluxos e regras de negócio de atendimento inteligente | Hospedado na VPS remota |

---

## 🚀 Como Iniciar o Ecossistema

### 1. Subir os Bancos de Dados (DB_UNG)
Na raiz de `DB_UNG`:
```bash
cd DB_UNG
docker-compose up -d
```
> **Nota:** Certifique-se de que a rede Docker `unifag_net` foi criada automaticamente pelo compose.

### 2. Subir o OMniLeads
No diretório do ambiente de teste do deploy tool:
```bash
cd omldeploytool/docker-compose/test-env
docker-compose up -d
```
- Acesse a interface web em: `https://localhost` (ou o IP do host).
- Credenciais padrão de administrador:
  - **Usuário:** `admin`
  - **Senha:** `admin`

### 3. Subir o WhatsApp Gateway (wa_gateway)
No diretório `wa_gateway`:
```bash
cd wa_gateway
docker-compose up -d --build
```
Verifique a integridade do gateway:
```bash
curl http://localhost:8088/health
```
Resposta esperada:
```json
{
  "status": "ok",
  "uptime": 12.34,
  "db_postgres": "connected",
  "oml_authenticated": true,
  "timestamp": "2026-10-05T..."
}
```

---

## ⚙️ Configuração do n8n (VPS)

No arquivo `wa_gateway/.env`, configure os endpoints do n8n para onde o gateway deve encaminhar as mensagens e eventos recebidos:

```env
# URL do Webhook do n8n na sua VPS para receber mensagens do bot
N8N_BOT_URL=https://n8n.sua-vps.com/webhook/whatsapp-bot

# URL do Webhook do n8n para eventos de status (mensagens enviadas, entregues, lidas)
N8N_STATUS_URL=https://n8n.sua-vps.com/webhook/whatsapp-status
```

---

## 📡 Endpoints da API do `wa_gateway`

| Método | Rota | Descrição |
| :--- | :--- | :--- |
| `GET` | `/health` | Healthcheck (verifica Postgres, autenticação OML e status) |
| `POST` | `/webhook/evolution` | Webhook receptor para instâncias da Evolution API |
| `POST` | `/send/text` | Disparo de mensagens de texto para WhatsApp |
| `POST` | `/send/media` | Disparo de áudios, imagens, documentos ou vídeos |
| `POST` | `/oml/contact-sync` | Sincroniza / cadastra contato diretamente na API do OMniLeads |
| `GET` | `/media/:filename` | Servidor de cache de mídias transitadas no atendimento |

---

## 🛠️ Manutenção e Utilitários

- **Reiniciar o gateway:**
  ```bash
  cd wa_gateway && docker-compose restart
  ```
- **Ver logs em tempo real do gateway:**
  ```bash
  docker logs -f wa_gateway
  ```
- **Resetar senha de admin do OMniLeads (se necessário):**
  ```bash
  docker exec -it omnileads-django-app python manage.py reset_admin_password
  ```
