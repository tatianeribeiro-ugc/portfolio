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
