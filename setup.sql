-- ================================================================================
-- SETUP DO BANCO DE DADOS DO PAINEL
-- Rode este script inteiro no SQL Editor do Supabase (menu lateral "SQL Editor",
-- botão "New query", cole tudo aqui e clique em "Run").
-- ================================================================================

-- Garante a função de gerar UUID automaticamente (já vem habilitada na maioria
-- dos projetos Supabase, mas não custa garantir).
create extension if not exists pgcrypto;

-- --------------------------------------------------------------------------------
-- TABELA: portfolio_events
-- Guarda os eventos do site (visitas, cliques em botões, vídeos assistidos).
-- --------------------------------------------------------------------------------
create table if not exists portfolio_events (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,        -- 'page_view' | 'button_click' | 'video_view'
  event_name text,                 -- nome do evento, ex: 'contact_whatsapp', ou o id do vídeo no YouTube
  session_id text,                 -- identifica um visitante durante a visita, sem usar dados pessoais
  page_path text,                  -- caminho da página onde o evento aconteceu
  metadata jsonb,                  -- dados extras, ex: { "title": "...", "brand": "...", "category": "..." }
  created_at timestamptz not null default now()
);

-- --------------------------------------------------------------------------------
-- TABELA: portfolio_leads
-- Guarda as mensagens recebidas pelo formulário de contato e pelo pop-up.
-- --------------------------------------------------------------------------------
create table if not exists portfolio_leads (
  id uuid primary key default gen_random_uuid(),
  name text,
  email text,
  phone text,
  brand text,
  budget text,
  message text,
  source text,                     -- 'contact' | 'popup'
  created_at timestamptz not null default now()
);

-- Índices simples para acelerar a ordenação por data, que o painel usa sempre.
create index if not exists portfolio_events_created_at_idx on portfolio_events (created_at desc);
create index if not exists portfolio_leads_created_at_idx on portfolio_leads (created_at desc);

-- --------------------------------------------------------------------------------
-- ROW LEVEL SECURITY (RLS)
-- Com o RLS ligado e sem nenhuma policy, ninguém consegue ler nem escrever.
-- Criamos abaixo só a policy de LEITURA para usuários logados (authenticated),
-- que é o papel usado pelo painel depois do login.
-- --------------------------------------------------------------------------------
alter table portfolio_events enable row level security;
alter table portfolio_leads enable row level security;

create policy "Leitura para usuarios autenticados"
  on portfolio_events
  for select
  to authenticated
  using (true);

create policy "Leitura para usuarios autenticados"
  on portfolio_leads
  for select
  to authenticated
  using (true);

-- --------------------------------------------------------------------------------
-- ESCRITA PÚBLICA (papel "anon"): só para GRAVAR eventos novos
--
-- O site do portfólio é 100% estático (GitHub Pages, sem servidor), então é o
-- próprio navegador de quem visita o site que grava os eventos, usando a chave
-- anon (pública). Por isso a policy abaixo libera só o INSERT, nunca SELECT,
-- UPDATE ou DELETE: qualquer visitante consegue adicionar uma linha nova, mas
-- ninguém de fora consegue ler, alterar ou apagar o que já foi gravado.
--
-- Risco aceito conscientemente: alguém com conhecimento técnico poderia, em
-- teoria, mandar eventos falsos pelo console do navegador. Isso poluiria os
-- números, mas não expõe nem compromete nenhum dado real. Se um dia quiser
-- fechar até essa brecha, a alternativa é gravar os eventos através de um
-- servidor (ex: uma função na Vercel) usando a chave "service_role", que
-- nunca fica exposta no navegador.
-- --------------------------------------------------------------------------------
create policy "Insercao publica de eventos"
  on portfolio_events
  for insert
  to anon
  with check (true);

create policy "Insercao publica de leads"
  on portfolio_leads
  for insert
  to anon
  with check (true);
-- ================================================================================

-- --------------------------------------------------------------------------------
-- TABELA: clients
-- Clientes/marcas do calendário de gestão de projetos.
-- --------------------------------------------------------------------------------
create table if not exists clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text,
  phone text,
  instagram text,
  company text,
  created_at timestamptz not null default now()
);

-- --------------------------------------------------------------------------------
-- TABELA: events
-- Eventos do calendário: trabalhos com marcas, prazos, gravações, reuniões,
-- pagamentos, publicações e compromissos pessoais.
-- --------------------------------------------------------------------------------
create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,                 -- também guarda as "observações" do evento
  client_id uuid references clients(id) on delete set null,
  category text not null default 'conteudo', -- 'cliente' | 'financeiro' | 'conteudo' | 'reuniao' | 'pessoal'
  priority text not null default 'media',    -- 'baixa' | 'media' | 'alta'
  status text not null default 'agendado',   -- 'agendado' | 'andamento' | 'concluido' | 'cancelado'
  start_date timestamptz not null,
  end_date timestamptz,
  all_day boolean not null default false,
  color text,                        -- opcional: sobrescreve a cor padrão da categoria
  reminder boolean not null default false,
  attachments jsonb,                 -- reservado para anexos no futuro (ainda sem upload no painel)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists events_start_date_idx on events (start_date);
create index if not exists clients_name_idx on clients (name);

-- --------------------------------------------------------------------------------
-- ROW LEVEL SECURITY: só você (logada no painel) lê e escreve. O site público
-- do portfólio não usa essas tabelas, então não existe policy para "anon" aqui.
-- --------------------------------------------------------------------------------
alter table clients enable row level security;
alter table events enable row level security;

create policy "CRUD completo para usuarios autenticados"
  on clients
  for all
  to authenticated
  using (true)
  with check (true);

create policy "CRUD completo para usuarios autenticados"
  on events
  for all
  to authenticated
  using (true)
  with check (true);
-- ================================================================================

-- --------------------------------------------------------------------------------
-- CRM DE CLIENTES
-- Reaproveita a tabela "clients" que já existe (criada para o calendário) e
-- acrescenta as colunas que o CRM precisa, em vez de criar uma tabela paralela.
-- Assim o cliente cadastrado no CRM é o mesmo que aparece no seletor de
-- cliente dos eventos do calendário.
-- --------------------------------------------------------------------------------
alter table clients
  add column if not exists contact_name text,          -- nome do responsável
  add column if not exists position text,               -- cargo do responsável
  add column if not exists website text,
  add column if not exists city text,
  add column if not exists niche text,
  add column if not exists how_found text,               -- como conheceu
  add column if not exists first_contact_date date,
  add column if not exists average_ticket numeric,
  add column if not exists notes text,
  add column if not exists next_campaign_idea text,       -- diferencial: próxima ideia de campanha
  add column if not exists status text not null default 'ativo', -- ativo | negociacao | aguardando | encerrado | perdido
  add column if not exists updated_at timestamptz not null default now();

-- --------------------------------------------------------------------------------
-- TABELA: client_projects
-- Histórico de trabalhos + projetos em andamento de cada cliente.
-- --------------------------------------------------------------------------------
create table if not exists client_projects (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  title text not null,
  description text,
  value numeric,
  status text not null default 'briefing',        -- briefing | gravacao | edicao | aprovacao | entrega | concluido | cancelado
  payment_status text not null default 'pendente', -- pago | pendente | atrasado
  start_date date,
  delivery_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- --------------------------------------------------------------------------------
-- TABELA: client_interactions
-- Linha do tempo do relacionamento (primeiro contato, orçamento, fechamento,
-- entrega, pagamento, anotações rápidas etc.) e também registra follow-ups.
-- --------------------------------------------------------------------------------
create table if not exists client_interactions (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  type text not null default 'nota',  -- contato | orcamento | fechamento | entrega | pagamento | nota | outro
  description text,
  date timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- --------------------------------------------------------------------------------
-- TABELA: client_files
-- Guarda só o LINK do arquivo (ex: Google Drive), não faz upload de verdade,
-- já que o site é 100% estático e não tem servidor de armazenamento.
-- --------------------------------------------------------------------------------
create table if not exists client_files (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references clients(id) on delete cascade,
  name text not null,
  url text not null,
  type text not null default 'outro', -- briefing | contrato | nota_fiscal | video | outro
  created_at timestamptz not null default now()
);

create index if not exists client_projects_client_id_idx on client_projects (client_id);
create index if not exists client_interactions_client_id_idx on client_interactions (client_id);
create index if not exists client_files_client_id_idx on client_files (client_id);

alter table client_projects enable row level security;
alter table client_interactions enable row level security;
alter table client_files enable row level security;

create policy "CRUD completo para usuarios autenticados"
  on client_projects for all to authenticated using (true) with check (true);

create policy "CRUD completo para usuarios autenticados"
  on client_interactions for all to authenticated using (true) with check (true);

create policy "CRUD completo para usuarios autenticados"
  on client_files for all to authenticated using (true) with check (true);
-- ================================================================================

-- --------------------------------------------------------------------------------
-- MÓDULO DE PROJETOS (KANBAN)
-- Reaproveita a tabela "client_projects" que já existe (criada para o CRM) em
-- vez de criar uma tabela "projects" paralela. Assim um trabalho criado no
-- quadro Kanban é o mesmo que aparece no histórico do cliente no CRM.
--
-- O quadro Kanban usa um vocabulário de status mais rico que o antigo (8
-- colunas em vez de 7 etapas). As linhas abaixo primeiro RENOMEIAM os valores
-- antigos para os novos equivalentes, para não perder nada que você já
-- cadastrou, e só depois trocam o padrão da coluna.
-- --------------------------------------------------------------------------------
update client_projects set status = 'gravar'    where status = 'gravacao';
update client_projects set status = 'editar'    where status = 'edicao';
update client_projects set status = 'entregue'  where status = 'entrega';
update client_projects set status = 'pago'      where status = 'concluido';
update client_projects set status = 'arquivado' where status = 'cancelado';
-- 'briefing' e 'aprovacao' já têm o mesmo nome nos dois vocabulários.

alter table client_projects
  add column if not exists priority text not null default 'media', -- baixa | media | alta | urgente
  add column if not exists content_type text,        -- tipo de conteúdo (ex: Reels, TikTok, YouTube)
  add column if not exists quantity integer,          -- quantidade de conteúdos/vídeos
  add column if not exists briefing text,
  add column if not exists script text,               -- roteiro
  add column if not exists recording_date date,       -- data de gravação
  add column if not exists payment_method text,       -- forma de pagamento
  add column if not exists payment_date date,         -- data prevista de pagamento
  add column if not exists idea_bank text,            -- banco de ideias: hooks, referências, links, observações
  add column if not exists event_recording_id uuid references events(id) on delete set null,
  add column if not exists event_delivery_id uuid references events(id) on delete set null,
  add column if not exists event_payment_id uuid references events(id) on delete set null;

alter table client_projects alter column status set default 'novo_lead';

-- --------------------------------------------------------------------------------
-- TABELA: project_tasks
-- Checklist interno de cada projeto (ex: Gravar cenas, Editar, Entregar).
-- --------------------------------------------------------------------------------
create table if not exists project_tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references client_projects(id) on delete cascade,
  title text not null,
  completed boolean not null default false,
  created_at timestamptz not null default now()
);

-- --------------------------------------------------------------------------------
-- TABELA: project_files
-- Assim como client_files, guarda só o LINK do arquivo (não faz upload real).
-- --------------------------------------------------------------------------------
create table if not exists project_files (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references client_projects(id) on delete cascade,
  name text not null,
  url text not null,
  type text not null default 'outro', -- briefing | video | foto | contrato | nota_fiscal | outro
  created_at timestamptz not null default now()
);

-- --------------------------------------------------------------------------------
-- TABELA: project_comments
-- Serve para DUAS abas do perfil do projeto ao mesmo tempo: "Comentários"
-- (type = 'comentario', escritos por você) e "Histórico" (todos os tipos,
-- incluindo os registros automáticos que o sistema cria quando o status
-- muda, ex: "Status alterado para Gravar").
-- --------------------------------------------------------------------------------
create table if not exists project_comments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references client_projects(id) on delete cascade,
  content text not null,
  type text not null default 'comentario', -- comentario | sistema
  created_at timestamptz not null default now()
);

create index if not exists project_tasks_project_id_idx on project_tasks (project_id);
create index if not exists project_files_project_id_idx on project_files (project_id);
create index if not exists project_comments_project_id_idx on project_comments (project_id);

alter table project_tasks enable row level security;
alter table project_files enable row level security;
alter table project_comments enable row level security;

create policy "CRUD completo para usuarios autenticados"
  on project_tasks for all to authenticated using (true) with check (true);

create policy "CRUD completo para usuarios autenticados"
  on project_files for all to authenticated using (true) with check (true);

create policy "CRUD completo para usuarios autenticados"
  on project_comments for all to authenticated using (true) with check (true);
-- ================================================================================

-- --------------------------------------------------------------------------------
-- MÓDULO FINANCEIRO
-- Uma única tabela para receitas E despesas (campo "type"), o que facilita
-- o gráfico "receitas x despesas" e os relatórios. Permuta é só uma categoria
-- de receita a mais, com 3 colunas extras para não perder o controle dela.
-- --------------------------------------------------------------------------------
create table if not exists financial_transactions (
  id uuid primary key default gen_random_uuid(),
  type text not null default 'receita',      -- receita | despesa
  client_id uuid references clients(id) on delete set null,
  project_id uuid references client_projects(id) on delete set null,
  description text,
  category text not null default 'outros',
  amount numeric not null default 0,
  status text not null default 'a_receber',  -- recebido | a_receber | atrasado (despesas usam "recebido" como "pago")
  due_date date,                              -- data prevista (receita) / data da despesa
  payment_date date,                          -- data de recebimento (ou de pagamento, no caso de despesa)
  payment_method text,
  notes text,
  invoice_url text,                           -- nota fiscal (link)
  receipt_url text,                           -- comprovante (link)
  barter_product text,                        -- permuta: produto recebido
  barter_brand text,                          -- permuta: marca
  barter_delivered boolean not null default false, -- permuta: entrega já realizada
  event_due_id uuid references events(id) on delete set null,
  event_payment_id uuid references events(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- --------------------------------------------------------------------------------
-- TABELA: financial_goals
-- Uma meta por mês/ano. O valor ATUAL não fica salvo aqui: é sempre
-- calculado a partir das receitas recebidas de fato, pra nunca ficar
-- desatualizado.
-- --------------------------------------------------------------------------------
create table if not exists financial_goals (
  id uuid primary key default gen_random_uuid(),
  month integer not null,
  year integer not null,
  goal_amount numeric not null default 0,
  created_at timestamptz not null default now(),
  unique (month, year)
);

-- --------------------------------------------------------------------------------
-- TABELA: recurring_expenses
-- Lista de referência de despesas fixas (Canva Pro, internet, domínio...).
-- Não lança nada sozinha todo mês (o site é estático, sem tarefa agendada);
-- serve para lembrar você e lançar rápido com um clique.
-- --------------------------------------------------------------------------------
create table if not exists recurring_expenses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'outros',
  amount numeric,
  due_day integer,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Liga cada projeto à receita pendente que é criada automaticamente para ele.
alter table client_projects
  add column if not exists financial_transaction_id uuid references financial_transactions(id) on delete set null;

create index if not exists financial_transactions_due_date_idx on financial_transactions (due_date);
create index if not exists financial_transactions_client_id_idx on financial_transactions (client_id);
create index if not exists financial_transactions_project_id_idx on financial_transactions (project_id);

alter table financial_transactions enable row level security;
alter table financial_goals enable row level security;
alter table recurring_expenses enable row level security;

create policy "CRUD completo para usuarios autenticados"
  on financial_transactions for all to authenticated using (true) with check (true);

create policy "CRUD completo para usuarios autenticados"
  on financial_goals for all to authenticated using (true) with check (true);

create policy "CRUD completo para usuarios autenticados"
  on recurring_expenses for all to authenticated using (true) with check (true);
-- ================================================================================

-- --------------------------------------------------------------------------------
-- BANCO CRIATIVO
-- De propósito simples: uma tabela só para os 4 tipos de item (ideia, roteiro,
-- roteiro aprovado, gancho). O rótulo "Nicho" (roteiro) e "Categoria" (gancho)
-- usam a mesma coluna "extra_label", só o texto do rótulo muda no painel
-- conforme o tipo, pra não duplicar duas colunas quase iguais.
-- --------------------------------------------------------------------------------
create table if not exists creative_bank (
  id uuid primary key default gen_random_uuid(),
  type text not null default 'ideia',  -- ideia | roteiro | aprovado | gancho
  title text,
  content text,                         -- descrição (ideia) | roteiro completo (roteiro/aprovado) | texto do gancho
  extra_label text,                     -- nicho (roteiro) | categoria (gancho)
  result text,                          -- resultado obtido (só em "aprovado")
  notes text,                           -- observações (só em "aprovado")
  client_id uuid references clients(id) on delete set null,
  tags text[],
  reference_link text,
  favorite boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- --------------------------------------------------------------------------------
-- TABELA: creative_drafts
-- A seção "Ideias para usar depois": rascunhos soltos, sem título nem
-- categoria, só o texto mesmo. Serve como bloco de notas de ideias futuras.
-- --------------------------------------------------------------------------------
create table if not exists creative_drafts (
  id uuid primary key default gen_random_uuid(),
  content text not null,
  created_at timestamptz not null default now()
);

create index if not exists creative_bank_type_idx on creative_bank (type);

alter table creative_bank enable row level security;
alter table creative_drafts enable row level security;

create policy "CRUD completo para usuarios autenticados"
  on creative_bank for all to authenticated using (true) with check (true);

create policy "CRUD completo para usuarios autenticados"
  on creative_drafts for all to authenticated using (true) with check (true);
-- ================================================================================

-- --------------------------------------------------------------------------------
-- MENU PRINCIPAL: mensagens não lidas
-- Uma coluna simples pra saber quais mensagens você ainda não abriu. Fica
-- marcada como lida sozinha quando você expande a mensagem na aba Portfólio.
-- --------------------------------------------------------------------------------
alter table portfolio_leads
  add column if not exists read boolean not null default false;
-- ================================================================================
