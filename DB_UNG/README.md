# Simulador de Bancos de Dados — Bot UNIFAG (n8n)

Ambiente Docker completo para simular todas as operações e consultas de banco de dados do fluxo n8n **"UNIFAG - Bot com Registro de Respostas da Campanha"**, sem qualquer necessidade de alterar nós ou consultas do fluxo original.

> 📚 **Sistema de Documentação dos 4 Fluxos Core**:  
> A documentação técnica, arquitetura, manuais e dicionário de dados completos de todos os fluxos estão organizados em [**`docs/README.md`**](docs/README.md).

---

## 🚀 Como Iniciar os Bancos

No terminal do diretório do projeto:

```powershell
# Subir os containers em segundo plano
docker compose up -d

# Verificar se estão saudáveis (healthy)
docker compose ps

# Parar os containers quando desejar
docker compose down
```

---

## ⚙️ Configuração das Credenciais no n8n

O fluxo possui dois conjuntos de credenciais configurados nos nós. Abaixo estão os parâmetros exatos para configurar cada um deles no seu n8n:

### 1. PostgreSQL (Credencial: `Unifag_Bot` / ID: `RLZJxPIN5hWeeHIB`)

| Parâmetro | Se o n8n rodar no Host / Desktop | Se o n8n rodar na mesma rede Docker |
|---|---|---|
| **Host** | `localhost` ou `127.0.0.1` | `unifag_bot_postgres` |
| **Port** | `5434` *(mapeada no host)* | `5432` *(porta interna)* |
| **Database** | `unifag_bot` | `unifag_bot` |
| **User** | `unifag_admin` | `unifag_admin` |
| **Password** | `****` | `***` |
| **Schema** | `unifag_bot` | `unifag_bot` |
| **SSL** | Disable | Disable |

> **Nota:** A porta externa `5434` foi escolhida para evitar conflito com a porta `5432` do host. O search_path do banco já está configurado para `unifag_bot, public`.

### 2. MySQL (Credencial: `bot_control` / ID: `Douv0MMoaoiQSOUc`)

| Parâmetro | Se o n8n rodar no Host / Desktop | Se o n8n rodar na mesma rede Docker |
|---|---|---|
| **Host** | `localhost` ou `127.0.0.1` | `bot_control_mysql` |
| **Port** | `3306` | `3306` |
| **Database** | `bot_control` | `bot_control` |
| **User** | `bot_user` *(ou `root`)* | `bot_user` *(ou `root`)* |
| **Password** | ****` | `**** |
| **Connect Timeout** | `10000` | `10000` |

---

## 🗄️ Estrutura dos Bancos e Tabelas Mapeadas

### PostgreSQL (`unifag_bot`)
* **`unifag_bot.processed_messages`**: Deduplicação de mensagens recebidas pelo webhook (nós `DB - Check Processed Message`, `DB - Insert Processed Message` e `REMOVE HUMAM`).
* **`unifag_bot.sessoes_atendimento`**: Gestão do ciclo de vida das conversas, etapas da máquina de estados, handoff e encerramento (nós `DB - Get Session`, `DB - Create Session`, `DB - Update Session Stage`, `DB - Set Session Human`, etc.).
* **`unifag_bot.historico_mensagens`**: Histórico detalhado de entrada/saída com JSONB de metadados (nós `DB - Save User Message`, `DB - Save Bot Message`, etc.).
* **`unifag_bot.roteamento_oml_humano`**: Tabela de persistência e transferência gerenciada pelo `wa_gateway` para direcionar voluntários para filas/agentes do OmniLeads.
* **`public.n8n_chat_histories` / `unifag_bot.n8n_chat_histories`**: Tabela necessária para o nó de memória do agente de IA (`Postgres Chat Memory`).

### MySQL (`bot_control`)
* **`bot_contact_control`**: Trava do bot para contatos em atendimento humano e motivo de bloqueio (nós `MYSQL - Check Bot Lock`, `MYSQL - Set Human Lock`, `Execute a SQL query2`, etc.).
* **`campanha_contatos_resumo`**: Contexto do envio ativo de campanha, contagem de interações e controle do fluxo humano (nós `MYSQL - Buscar Contexto Campanha`, `MYSQL - Marcar Resposta Cliente Campanha`, `MYSQL - Claim Primeira Resposta Human`, etc.).
* **`bot_atendimento_resumo`**: Resumo consolidado do atendimento após handoff (nó `MYSQL - Upsert Atendimento Resumo`).
* **`bot_atendimento_historico`**: Histórico de perguntas e respostas gravado individualmente por ordem (nó `MYSQL - Upsert Atendimento Historico`).

---

## 🧪 Teste Automatizado de Todas as Consultas

Para validar que 100% das consultas SQL do fluxo n8n executam sem erros:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test_queries.ps1
```

O script executa cada query do fluxo simulando os nós e exibe `SUCESSO!` para todas as operações em ambos os bancos.
