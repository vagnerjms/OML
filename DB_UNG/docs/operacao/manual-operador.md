# Manual do Operador & Supervisor — UNIFAG

Este manual orienta a equipe de operações, coordenação de estudos clínicos e supervisores de atendimento sobre a utilização diária das ferramentas de disparo, acompanhamento de métricas e exportação de dados do ecossistema WhatsApp da **UNIFAG**.

---

## 1. Acesso ao Sistema e Gestão de Senhas

### 1.1. URLs dos Portais
* **Portal de Disparo de Campanhas**: `/webhook/envio-unifag`
* **Dashboard Executivo & BI**: `/webhook/whasoml`
* **Gestão de Modelos de Mensagem**: `/webhook/envio-unifag-templates` *(Supervisores e Admins)*
* **Gestão de Usuários**: `/webhook/envio-unifag-admin` *(Apenas Administradores)*

### 1.2. Primeiro Acesso e Troca de Senha
1. Acesse o portal com seu e-mail institucional e a senha provisória fornecida pelo administrador.
2. No primeiro login, o sistema detectará a senha provisória e exibirá automaticamente a tela de **Alteração de Senha Obrigatória**.
3. Escolha uma senha pessoal com no mínimo **8 caracteres**, diferente da senha provisória.
4. Após salvar, realize o login com sua nova credencial. A sessão permanece ativa por **8 horas**.

---

## 2. Preparação da Lista de Contatos (Arquivo CSV)

Para realizar um disparo de campanha, prepare o arquivo de contatos seguindo os padrões abaixo:

### 2.1. Estrutura do Arquivo
* **Formato**: Arquivo de texto delimitado por vírgula ou ponto e vírgula (`.csv`).
* **Codificação recomendada**: UTF-8.
* **Coluna Obrigatória**: Deve existir uma coluna intitulada `telefone` (o sistema reconhece em maiúsculas, minúsculas ou com espaços).

### 2.2. Exemplo de CSV Válido
```csv
nome,telefone,cidade
João Silva,11999998888,Campinas
Maria Santos,5519988887777,Bragança Paulista
Carlos Pereira,11977776666,São Paulo
```

> [!TIP]
> **Dica de Formatação**: Não se preocupe com parênteses, traços ou espaços no telefone. O sistema normaliza automaticamente removendo caracteres não numéricos e garantindo o DDI `55`. Números fixos devem ser removidos previamente da lista.

---

## 3. Disparando uma Nova Campanha

Acesse `/webhook/envio-unifag` e preencha as etapas do formulário:

### Passo 1: Selecionar o Tipo de Campanha
* **Modo Humano**: Escolha este modo quando houver operadores logados no OmniLeads para atender imediatamente às respostas dos pacientes.
  * *Encaminhar respostas para*: Escolha entre **Campanha OML** (fila geral) ou **Agente OML** (distribuição nominal).
  * *Campanha OML*: Selecione a campanha de destino no dropdown dinâmico.
  > [!IMPORTANT]
  > A campanha fixa `111 (UNIFAG_WHATSAPPV1)` é o tronco de entrada e **não pode** ser selecionada como destino final de operadores.
* **Modo Bot**: Escolha este modo quando desejar que o robô inteligente faça a triagem prévia, validação de critérios (idade, peso, fumo) e envio de vídeos/formulários.

### Passo 2: Selecionar o Modelo da Mensagem (Template Meta)
* Selecione um template homologado e com status **Aprovado** na Meta.
* Caso o modelo possua variáveis dinâmicas (ex: `{{1}}`), preencha o campo correspondente.
> [!CAUTION]
> **Atenção às Regras da Meta**: O texto preenchido nas variáveis dinâmicas **não pode conter quebras de linha (`Enter`)**, tabulações ou múltiplos espaços consecutivos. Caso seja necessário separar parágrafos, utilize um modelo cujo corpo aprovado na Meta já possua as quebras fixas.

### Passo 3: Enviar o CSV e Confirmar
* Anexe o arquivo CSV preparado.
* Clique em **Iniciar campanha**. A mensagem de confirmação indicará que a solicitação foi enfileirada no n8n. O disparo é realizado em lotes de 5 contatos com intervalo de proteção entre os envios.

---

## 4. Como Interpretar a Janela de 24 Horas (`blocked_24h`)

O sistema conta com um algoritmo inteligente de proteção de envio:

* Se um contato do seu CSV recebeu qualquer mensagem ativa nas **últimas 24 horas**, o sistema **não enviará** a mensagem novamente para evitar cobrança duplicada e denúncias de spam.
* Esse contato é registrado com o status **`blocked_24h`** (Não enviado · proteção 24h).
* No Dashboard (`/webhook/whasoml?page=relatorios_24h&view=bloqueios`), você pode consultar exatamente quais números foram protegidos e o horário exato em que a janela de 24h expira para liberação.

---

## 5. Navegação no Dashboard Executivo (`/webhook/whasoml`)

O Dashboard unificado consolida os resultados em tempo real:

### 5.1. Indicadores da Visão Geral (Overview)
* **Enviadas**: Volume de mensagens aceitas pela Meta API.
* **Entregues**: Mensagens que chegaram ao aparelho do paciente (2 tiques cinzas).
* **Lidas**: Mensagens abertas pelo paciente (2 tiques azuis).
* **Respostas**: Pacientes que interagiram com a mensagem.
* **Convertidos**: Quantidade de pacientes únicos que tiveram agendamento registrado na planilha `AGENDA 2026` após a campanha.
* **Presentes / Aptos**: Pacientes que compareceram à clínica e foram declarados aptos pelo médico coordenador.

### 5.2. Exportação de Relatórios e Listas
* **Baixar Relatório em PDF**: Na tela de detalhes da campanha, clique no botão **📄 Baixar PDF**. O layout se ajusta automaticamente ao formato A4 Paisagem.
* **Exportar Contatos Perdidos do OmniLeads**: No menu **BI Meta**, clique em **⬇ CSV · todos sem atendimento** para baixar a lista de telefones de pessoas que interagiram, mas cuja conversa expirou antes do operador humano responder.
