# Guia de Troubleshooting & Diagnóstico — UNIFAG

Este guia reúne diagnósticos operacionais, catálogo de erros da Meta WhatsApp Cloud API, procedimentos de destrave de contatos e comandos de verificação de infraestrutura.

---

## 1. Catálogo de Erros da Meta WhatsApp Cloud API

Durante os envios ou recebimentos de callbacks, a Meta pode retornar códigos de falha. Abaixo estão os códigos mais frequentes observados no ecossistema UNIFAG e suas respectivas soluções:

| Código | Mensagem / Categoria | Causa Raiz | Ação Recomendada |
|---|---|---|---|
| **`131026`** | *Message Undeliverable* (Contato) | O número do destinatário não possui conta de WhatsApp ativa ou está desativado na operadora. | No Dashboard (`page=errors`), clique em **"Confirmar sem WhatsApp"** para sanear a base e impedir novos envios desnecessários. |
| **`131047`** | *Re-engagement Message* (Atendimento) | Tentativa de enviar mensagem de texto livre quando a janela de 24 horas de conversação do cliente já expirou. | Utilize um **Template de Mensagem aprovado** para reiniciar o diálogo. Nunca envie texto simples fora da janela. |
| **`131048`** | *Spam Rate Limit* (Frequência) | A Meta limitou o envio para este contato devido ao excesso de mensagens não respondidas em curto intervalo. | Suspenda envios para este número por no mínimo 48 horas e revise a cadência da campanha. |
| **`131049`** | *Engagement Limits* (Capacidade Meta) | A Meta restringiu temporariamente a entrega para preservar a experiência do usuário. | Aguarde 24 horas antes de tentar novo disparo. Não insista no reenvio imediato para não degradar a nota de qualidade do WABA. |
| **`130429`** | *Rate Limit Hit* (Throughput) | O volume de disparos simultâneos ultrapassou a capacidade contratada da conta de WhatsApp Business. | O fluxo n8n possui tratamento com retentativas automáticas (`retryOnFail`). No painel, ajuste `delay_segundos` para espaçar os lotes. |
| **`132000`** | *Template Parameter Error* | A quantidade de variáveis enviadas não corresponde exatamente às chaves do modelo (ex: `{{1}}`, `{{2}}`). | Abra o painel de templates e verifique se todas as variáveis consecutivas foram preenchidas. |
| **`132001`** | *Template Not Found* | O template ou o código de idioma (`template_language_code`) não existem na conta da Meta. | Execute a sincronização no painel `/webhook/envio-unifag-templates-sync`. Certifique-se de usar `pt_BR`. |
| **`132005`** | *Template Paused* | A Meta pausou o modelo automaticamente após voluntários marcarem as mensagens como indesejadas (baixa qualidade). | Pause o uso deste modelo no painel, crie uma nova versão textual com abordagem mais suave e submeta à revisão da Meta. |
| **`190`** | *Invalid / Expired Token* (Crítico) | O token de autorização do Facebook Graph API expirou ou foi revogado. | **Acionar a equipe de TI imediatamente**. É necessário gerar novo Bearer Token permanente no Meta Business Manager e atualizar as credenciais no n8n. |
| **`131031`** | *Account Restricted* (Crítico) | A conta do WhatsApp Business foi suspensa por descumprimento de políticas da Meta. | Acessar o Meta Business Manager para verificar restrições e submeter recurso. |

---

## 2. Resolução de Travas de Contato (Bot vs. Humano)

### 2.1. Sintoma: O Bot não responde determinado voluntário
Se o paciente envia mensagens e o Bot permanece em silêncio, o contato provavelmente está com **trava de atendimento humano ativa** em um dos seguintes pontos:

#### Diagnóstico no MySQL:
Execute a consulta no banco `bot_control`:
```sql
SELECT wa_id, bot_locked, lock_reason, source, session_status, updated_at
FROM bot_contact_control
WHERE wa_id = '5511999998888';
```
Se `bot_locked = 1` e `updated_at` ocorreu há menos de 30 minutos, o bot está bloqueado intencionalmente para não interferir no agente humano.

#### Como destravar o contato manualmente:

**Opção 1: Via comando HTTP no gateway (Recomendado)**
```bash
curl -X POST http://wa_gateway:8088/control/lock/5511999998888/off
```

**Opção 2: Via comando SQL direto no MySQL**
```sql
UPDATE bot_contact_control
SET
  bot_locked = 0,
  lock_reason = 'manual_release',
  session_status = 'bot',
  updated_at = NOW()
WHERE wa_id = '5511999998888';
```

**Opção 3: Reiniciar a sessão do PostgreSQL (`unifag_bot`)**
```sql
UPDATE unifag_bot.sessoes_atendimento
SET status = 'ativo', etapa_atual = 'entrada', atualizado_em = NOW()
WHERE telefone = '5511999998888';
```

---

## 3. Mensagem "Atendimento encerrado recentemente..."

Se o voluntário receber a mensagem:
> *"Seu atendimento foi encerrado recentemente. Por favor, aguarde 24 horas antes de iniciar um novo atendimento."*

* **Causa**: O paciente finalizou um atendimento anterior há menos de 1 minuto (`DB - Check Recent Closed Session`).
* **Objetivo da Regra**: Evitar loops imediatos caso o voluntário continue digitando após a conclusão do fluxo ou recebimento do link de formulário.
* **Ação**: O voluntário poderá iniciar novo fluxo normalmente após o tempo de resfriamento.

---

## 4. Problemas de Sincronização da Planilha Google Sheets

### 4.1. Erro: *"Registro OMNILEADS sem row_number"*
* **Causa**: A API do Google Sheets não retornou o número físico da linha. Isso ocorre quando há linhas em branco entre os registros ou colunas mescladas que quebram o parsing da tabela.
* **Solução**:
  1. Abra a planilha `AGENDA 2026`.
  2. Verifique se existem linhas com conteúdo parcial sem número ou linhas mescladas na aba.
  3. Remova linhas vazias intermediárias e certifique-se de que a coluna `VIA DE ENTRADA` contenha exclusivamente o termo `OMNILEADS` em maiúsculas.

### 4.2. Erro: *"ID_AGENDA_OML duplicado detectado"*
* **Causa**: Dois agendamentos na planilha possuem o mesmo identificador na coluna S.
* **Solução**: O fluxo aborta intencionalmente para não mesclar consultas de pacientes diferentes. Localize o ID duplicado na coluna S da planilha, apague o valor da célula mais recente e reexecute o fluxo para que um novo ID exclusivo seja gerado.

---

## 5. Validação do Ambiente Docker Local

Para rodar e testar os bancos de dados localmente antes de aplicar mudanças em produção:

```powershell
# 1. Subir os containers do MySQL e PostgreSQL
docker compose up -d

# 2. Verificar a integridade dos serviços
docker compose ps

# 3. Executar o script de teste de 100% das consultas SQL do ecossistema
powershell -ExecutionPolicy Bypass -File .\scripts\test_queries.ps1
```

O script `test_queries.ps1` valida sintaxe, tipos de dados e consistência de índices em ambos os bancos sem interferir nos dados de produção.

---

## 6. Diagnóstico do Gateway (`wa_gateway`), Traefik e OmniLeads

### 6.1. Falha de Roteamento ou Webhook 404/502 no Traefik
* **Sintoma**: A Meta reporta falha de entrega de webhooks ou status HTTP 404/502 em `https://webhook.usf.edu.br`.
* **Causas Frequentes**:
  1. O container `wa_gateway` não está na rede `network_public` compartilhada com o Traefik.
  2. O middleware `wa-gateway-meta-strip` foi desconfigurado, impedindo a reescrita de `/meta/(.*)` para `/webhook/$1`.
* **Comando de Verificação no Host `DCNTXRDSTATION` (Docker Swarm)**:
  ```bash
  # Ver logs centralizados do serviço Swarm
  docker service logs --tail 100 node_meta_wa_gateway

  # Ou inspecionar a rede do container ativo
  docker inspect $(docker ps -q --filter "name=node_meta_wa_gateway") --format '{{json .NetworkSettings.Networks}}'
  ```
  *(Dica: No Portainer, acesse **Containers** e clique no ícone 📄 **Logs** ao lado de `node_meta_wa_gateway.1...`).*

### 6.2. Falha de Autenticação na API do OmniLeads (`SessionAuthentication`)
* **Sintoma**: Logs do gateway apresentam erro `403 Forbidden` ou `CSRF Failed` ao tentar consultar `/api/v1/whatsapp/filter_chats/` ou transferir chamadas.
* **Causa**: O OmniLeads versão 2.5.6 (implantado via Podman/Ansible) impõe autenticação via sessão Django em vez de tokens Bearer simples para endpoints de WhatsApp.
* **Solução**:
  1. Inspecione os parâmetros e arquivos de credencial do gateway com:
     ```bash
     head -n 45 /opt/wa-gateway/index.js
     # ou para editar:
     nano /opt/wa-gateway/index.js
     ```
     (Consulte o [Dicionário de Parâmetros do Gateway](../arquitetura/gateway-orquestracao.md#32-dicionário-dos-parâmetros-de-configuração-indexjs) para entender cada variável).
  2. O gateway executa login em `/accounts/login/` para capturar os cookies `csrftoken` e `sessionid`. Caso o serviço OML seja reiniciado, force a renovação imediata reiniciando o serviço Swarm:
     ```bash
     docker service update --force node_meta_wa_gateway
     ```
     *(Ou no Portainer: na página do container `node_meta_wa_gateway.1...`, clique no botão **Restart**).*

### 6.3. Watchdog de Inscrição WABA Desativado ou Falhando
* **Sintoma**: Disparos funcionam, mas mensagens recebidas não geram callbacks.
* **Diagnóstico**: O gateway possui uma rotina que verifica a cada 60s se o WABA `1156659843285011` está vinculado ao App ID `1937257670036344`.
* **Verificação nos Logs**:
  ```bash
  docker logs wa_gateway | grep -i "watchdog"
  ```
  Caso reporte erro de permissão da Meta, verifique a validade do Token de Sistema no Business Manager.

### 6.4. Limpeza ou Falha de Permissão no Cache de Mídia
* **Sintoma**: Imagens ou áudios não carregam no OmniLeads via `/meta/media/:token`.
* **Causa**: O diretório `/app/media-cache` atingiu o limite de armazenamento ou o arquivo tem mais de 25MB (limite máximo por mídia).
* **Ação**: O gateway descarta arquivos com mais de 7 dias (168h) automaticamente. Para forçar a limpeza ou checar espaço no host:
  ```bash
  docker exec -it wa_gateway du -sh /app/media-cache
  ```

