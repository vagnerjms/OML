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

## 🌐 Implantação Rápida no Easypanel / VPS (Docker Compose)

O repositório possui um `docker-compose.yml` na **raiz** preparado para painéis como **Easypanel**, **Coolify** ou **Dokploy**:

1. No Easypanel, clique em **Novo Projeto** ou **Do GitHub / Docker Compose**.
2. Cole a URL do repositório:
   ```
   https://github.com/vagnerjms/OML.git
   ```
3. O Easypanel irá detectar automaticamente o `docker-compose.yml` na raiz e provisionar:
   - **`wa_gateway`**: API Node.js (porta `8088`). Configure um domínio para ele (ex: `gateway.seudominio.com`).
   - **`postgres` (`unifag_bot_postgres`)**: Banco PostgreSQL com schemas e tabelas inicializadas automaticamente.
   - **`mysql` (`bot_control_mysql`)**: Banco MySQL para controle e fila de atendimento.
4. Defina as variáveis de ambiente no painel conforme o `.env.example`.

---

## 📁 Componentes do Projeto

| Diretório / Módulo | Descrição | Status / Porta |
| :--- | :--- | :--- |
| **`docker-compose.yml`** | Compose da raiz unificando `wa_gateway` + `Postgres` + `MySQL` (ideal para Easypanel/VPS) | `8088`, `5434`, `3306` |
| **`wa_gateway/`** | Gateway em Node.js (Express) que conecta WhatsApp, OMniLeads e n8n | `8088` (HTTP API) |
| **`DB_UNG/`** | Bancos de dados relacionais e scripts de inicialização SQL | Postgres `5434` / MySQL `3306` |
| **`omldeploytool/`** | Stack Docker do OMniLeads (PBX, Nginx, Django, RTPEngine, Redis, etc.) | `443` (Web HTTPS) / `8008` (WS) |
| **`n8n`** | Orquestrador de fluxos e regras de negócio de atendimento inteligente | Hospedado na VPS remota |

---

## 🚀 Como Iniciar Manualmente (Desenvolvimento Local)

### 1. Subir a stack completa localmente (Gateway + Bancos)
Na raiz do projeto:
```bash
docker-compose up -d --build
```

### 2. Subir o OMniLeads (se for rodar localmente)
No diretório do ambiente de teste do deploy tool:
```bash
cd omldeploytool/docker-compose/test-env
docker-compose up -d
```
- Acesse a interface web em: `https://localhost` (ou o IP do host).
- Credenciais padrão de administrador:
  - **Usuário:** `admin`
  - **Senha:** `admin`

---

## ⚙️ Configuração do n8n (VPS)

No painel de variáveis de ambiente do seu provedor (ou no `.env` do `wa_gateway`), configure os endpoints do n8n:

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

- **Testar integridade:**
  ```bash
  curl http://localhost:8088/health
  ```
- **Ver logs em tempo real do gateway:**
  ```bash
  docker logs -f wa_gateway
  ```
