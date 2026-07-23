-- =========================================================
-- NETO SPORT — SCHEMA SUPABASE
-- Rode este arquivo inteiro no SQL Editor do seu projeto Supabase
-- (Project > SQL Editor > New query > colar tudo > Run)
-- =========================================================

-- ---------------------------------------------------------
-- EXTENSÕES
-- ---------------------------------------------------------
create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------
-- PERFIS (estende auth.users do Supabase Auth)
-- ---------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text,
  telefone text,
  cpf text,
  asaas_customer_id text,
  is_admin boolean not null default false,
  criado_em timestamptz not null default now()
);

-- Cria automaticamente um profile quando alguém se cadastra
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, nome, cpf)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', new.email), new.raw_user_meta_data->>'cpf');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------------------------------------------------------
-- CATEGORIAS
-- ---------------------------------------------------------
create table if not exists public.categories (
  id uuid primary key default uuid_generate_v4(),
  nome text not null,
  slug text not null unique
);

-- ---------------------------------------------------------
-- PRODUTOS
-- ---------------------------------------------------------
create table if not exists public.products (
  id uuid primary key default uuid_generate_v4(),
  nome text not null,
  slug text not null unique,
  descricao text,
  preco_centavos integer not null check (preco_centavos >= 0),
  preco_promocional_centavos integer check (preco_promocional_centavos >= 0),
  categoria_id uuid references public.categories(id) on delete set null,
  imagem_url text,
  galeria jsonb not null default '[]'::jsonb,
  tamanhos jsonb not null default '[]'::jsonb, -- ex: ["P","M","G","GG"]
  estoque integer not null default 0 check (estoque >= 0),
  sku text unique,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists idx_products_ativo on public.products(ativo);
create index if not exists idx_products_categoria on public.products(categoria_id);

create or replace function public.set_atualizado_em()
returns trigger as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_products_atualizado on public.products;
create trigger trg_products_atualizado
  before update on public.products
  for each row execute procedure public.set_atualizado_em();

-- ---------------------------------------------------------
-- ENDEREÇOS (opcional, um cliente pode ter vários)
-- ---------------------------------------------------------
create table if not exists public.addresses (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  destinatario text,
  cep text,
  rua text,
  numero text,
  complemento text,
  bairro text,
  cidade text,
  estado text,
  criado_em timestamptz not null default now()
);

-- ---------------------------------------------------------
-- PEDIDOS
-- ---------------------------------------------------------
create table if not exists public.orders (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pendente'
    check (status in ('pendente','pago','em_preparo','enviado','entregue','cancelado','estornado')),
  total_centavos integer not null check (total_centavos >= 0),
  endereco jsonb,
  metodo_pagamento text default 'pix',
  asaas_payment_id text,
  pix_copia_cola text,
  pix_qrcode_base64 text,
  pix_expira_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

drop trigger if exists trg_orders_atualizado on public.orders;
create trigger trg_orders_atualizado
  before update on public.orders
  for each row execute procedure public.set_atualizado_em();

create index if not exists idx_orders_user on public.orders(user_id);
create index if not exists idx_orders_status on public.orders(status);
create index if not exists idx_orders_criado_em on public.orders(criado_em);

-- ---------------------------------------------------------
-- ITENS DO PEDIDO
-- ---------------------------------------------------------
create table if not exists public.order_items (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  nome_produto text not null,      -- snapshot do nome no momento da compra
  tamanho text,
  quantidade integer not null check (quantidade > 0),
  preco_unit_centavos integer not null check (preco_unit_centavos >= 0)
);

create index if not exists idx_order_items_order on public.order_items(order_id);

-- =========================================================
-- ROW LEVEL SECURITY
-- =========================================================
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.addresses enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

-- Função auxiliar: o usuário logado é admin?
create or replace function public.is_admin()
returns boolean as $$
  select coalesce(
    (select is_admin from public.profiles where id = auth.uid()),
    false
  );
$$ language sql stable security definer;

-- ---------- PROFILES ----------
drop policy if exists "usuario ve o proprio perfil" on public.profiles;
create policy "usuario ve o proprio perfil"
  on public.profiles for select
  using (auth.uid() = id or public.is_admin());

drop policy if exists "usuario atualiza o proprio perfil" on public.profiles;
create policy "usuario atualiza o proprio perfil"
  on public.profiles for update
  using (auth.uid() = id);

-- ---------- CATEGORIES ----------
drop policy if exists "categorias sao publicas" on public.categories;
create policy "categorias sao publicas"
  on public.categories for select
  using (true);

drop policy if exists "somente admin gerencia categorias" on public.categories;
create policy "somente admin gerencia categorias"
  on public.categories for all
  using (public.is_admin())
  with check (public.is_admin());

-- ---------- PRODUCTS ----------
drop policy if exists "produtos ativos sao publicos" on public.products;
create policy "produtos ativos sao publicos"
  on public.products for select
  using (ativo = true or public.is_admin());

drop policy if exists "somente admin gerencia produtos" on public.products;
create policy "somente admin gerencia produtos"
  on public.products for insert
  with check (public.is_admin());

drop policy if exists "somente admin atualiza produtos" on public.products;
create policy "somente admin atualiza produtos"
  on public.products for update
  using (public.is_admin());

drop policy if exists "somente admin remove produtos" on public.products;
create policy "somente admin remove produtos"
  on public.products for delete
  using (public.is_admin());

-- ---------- ADDRESSES ----------
drop policy if exists "usuario ve os proprios enderecos" on public.addresses;
create policy "usuario ve os proprios enderecos"
  on public.addresses for select
  using (auth.uid() = user_id or public.is_admin());

drop policy if exists "usuario gerencia os proprios enderecos" on public.addresses;
create policy "usuario gerencia os proprios enderecos"
  on public.addresses for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------- ORDERS ----------
drop policy if exists "usuario ve os proprios pedidos" on public.orders;
create policy "usuario ve os proprios pedidos"
  on public.orders for select
  using (auth.uid() = user_id or public.is_admin());

drop policy if exists "usuario cria os proprios pedidos" on public.orders;
create policy "usuario cria os proprios pedidos"
  on public.orders for insert
  with check (auth.uid() = user_id);

drop policy if exists "admin atualiza pedidos" on public.orders;
create policy "admin atualiza pedidos"
  on public.orders for update
  using (public.is_admin());

-- ---------- ORDER ITEMS ----------
drop policy if exists "usuario ve os itens dos proprios pedidos" on public.order_items;
create policy "usuario ve os itens dos proprios pedidos"
  on public.order_items for select
  using (
    public.is_admin()
    or exists (
      select 1 from public.orders o
      where o.id = order_items.order_id and o.user_id = auth.uid()
    )
  );

drop policy if exists "usuario cria itens do proprio pedido" on public.order_items;
create policy "usuario cria itens do proprio pedido"
  on public.order_items for insert
  with check (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id and o.user_id = auth.uid()
    )
  );

-- =========================================================
-- MIGRAÇÃO (só faz algo se você já tinha rodado uma versão
-- antiga deste schema com Mercado Pago; em projeto novo é
-- inofensivo rodar de novo, pois é tudo "if exists/if not exists")
-- =========================================================
alter table public.profiles add column if not exists cpf text;
alter table public.profiles add column if not exists asaas_customer_id text;

alter table public.orders add column if not exists asaas_payment_id text;
alter table public.orders add column if not exists pix_copia_cola text;
alter table public.orders add column if not exists pix_qrcode_base64 text;
alter table public.orders add column if not exists pix_expira_em timestamptz;
alter table public.orders alter column metodo_pagamento set default 'pix';

do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='orders' and column_name='mp_preference_id') then
    alter table public.orders drop column mp_preference_id;
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='orders' and column_name='mp_payment_id') then
    alter table public.orders drop column mp_payment_id;
  end if;
end $$;

-- =========================================================
-- PARTE 2 — FUNCIONÁRIOS, VENDA DE BALCÃO E CLIQUES NO WHATSAPP
-- (pode rodar este arquivo inteiro de novo com segurança, é tudo
-- "if not exists" / "or replace" / "drop ... if exists")
-- =========================================================

-- ---------- Papel de funcionário ----------
alter table public.profiles add column if not exists is_funcionario boolean not null default false;

create or replace function public.is_funcionario()
returns boolean as $$
  select coalesce(
    (select is_funcionario from public.profiles where id = auth.uid()),
    false
  );
$$ language sql stable security definer;

-- ---------- Pedidos: venda de balcão feita por atendente ----------
-- Um pedido pode não ter cliente cadastrado (venda no balcão) e passa
-- a poder guardar qual atendente fez/deu baixa na venda.
alter table public.orders alter column user_id drop not null;
alter table public.orders add column if not exists atendente_id uuid references auth.users(id) on delete set null;
alter table public.orders add column if not exists origem text not null default 'loja'
  check (origem in ('loja','atendente'));
alter table public.orders add column if not exists cliente_nome text;

create index if not exists idx_orders_atendente on public.orders(atendente_id);

-- ---------- Cliques em "Finalizar no WhatsApp" ----------
create table if not exists public.whatsapp_clicks (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid references public.orders(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now()
);
create index if not exists idx_whatsapp_clicks_criado_em on public.whatsapp_clicks(criado_em);

alter table public.whatsapp_clicks enable row level security;

drop policy if exists "usuario registra o proprio clique" on public.whatsapp_clicks;
create policy "usuario registra o proprio clique"
  on public.whatsapp_clicks for insert
  with check (auth.uid() = user_id);

drop policy if exists "admin e funcionario veem os cliques" on public.whatsapp_clicks;
create policy "admin e funcionario veem os cliques"
  on public.whatsapp_clicks for select
  using (public.is_admin() or public.is_funcionario());

-- ---------- PRODUCTS: agora funcionário também gerencia ----------
drop policy if exists "somente admin gerencia produtos" on public.products;
drop policy if exists "admin ou funcionario cadastram produtos" on public.products;
create policy "admin ou funcionario cadastram produtos"
  on public.products for insert
  with check (public.is_admin() or public.is_funcionario());

drop policy if exists "somente admin atualiza produtos" on public.products;
drop policy if exists "admin ou funcionario atualizam produtos" on public.products;
create policy "admin ou funcionario atualizam produtos"
  on public.products for update
  using (public.is_admin() or public.is_funcionario());

drop policy if exists "somente admin remove produtos" on public.products;
drop policy if exists "admin ou funcionario removem produtos" on public.products;
create policy "admin ou funcionario removem produtos"
  on public.products for delete
  using (public.is_admin() or public.is_funcionario());

-- ---------- ORDERS: admin e funcionário enxergam/atualizam tudo ----------
drop policy if exists "usuario ve os proprios pedidos" on public.orders;
create policy "usuario ve os proprios pedidos"
  on public.orders for select
  using (auth.uid() = user_id or public.is_admin() or public.is_funcionario());

drop policy if exists "usuario cria os proprios pedidos" on public.orders;
drop policy if exists "cliente ou atendente cria pedido" on public.orders;
create policy "cliente ou atendente cria pedido"
  on public.orders for insert
  with check (
    auth.uid() = user_id
    or ((public.is_admin() or public.is_funcionario()) and atendente_id = auth.uid())
  );

drop policy if exists "admin atualiza pedidos" on public.orders;
drop policy if exists "admin ou funcionario atualiza pedidos" on public.orders;
create policy "admin ou funcionario atualiza pedidos"
  on public.orders for update
  using (public.is_admin() or public.is_funcionario());

-- ---------- ORDER ITEMS: acompanha as novas regras de orders ----------
drop policy if exists "usuario ve os itens dos proprios pedidos" on public.order_items;
create policy "usuario ve os itens dos proprios pedidos"
  on public.order_items for select
  using (
    public.is_admin() or public.is_funcionario()
    or exists (
      select 1 from public.orders o
      where o.id = order_items.order_id and o.user_id = auth.uid()
    )
  );

drop policy if exists "usuario cria itens do proprio pedido" on public.order_items;
drop policy if exists "usuario ou atendente cria itens do pedido" on public.order_items;
create policy "usuario ou atendente cria itens do pedido"
  on public.order_items for insert
  with check (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and (o.user_id = auth.uid() or o.atendente_id = auth.uid())
    )
  );

-- =========================================================
-- PARTE 3 — PERMITIR QUE O ADMIN APAGUE PEDIDOS/CLIQUES
-- (necessário para o botão "Reiniciar todas as operações"
-- do admin/dashboard.html). Só o admin pode apagar; funcionário
-- não tem essa permissão. Pode rodar de novo com segurança.
-- =========================================================
drop policy if exists "admin remove pedidos" on public.orders;
create policy "admin remove pedidos"
  on public.orders for delete
  using (public.is_admin());

drop policy if exists "admin remove itens de pedidos" on public.order_items;
create policy "admin remove itens de pedidos"
  on public.order_items for delete
  using (public.is_admin());

drop policy if exists "admin remove cliques whatsapp" on public.whatsapp_clicks;
create policy "admin remove cliques whatsapp"
  on public.whatsapp_clicks for delete
  using (public.is_admin());

-- =========================================================
-- PARTE 4 — LOGÍSTICA (retirada na loja / preparação p/ Correios)
-- Por enquanto só existe retirada na loja (sem frete). Estas colunas
-- deixam o banco pronto para quando outros métodos de entrega forem
-- ativados (entrega própria, Correios etc.) — não muda nada do que
-- já funciona hoje.
-- =========================================================
alter table public.orders add column if not exists metodo_frete text not null default 'retirada'
  check (metodo_frete in ('retirada','entrega_local','correios'));
alter table public.orders add column if not exists frete_centavos integer not null default 0 check (frete_centavos >= 0);

-- A tabela public.addresses (definida acima) já existe e não é usada no
-- checkout ainda — fica pronta para quando um método com entrega for
-- ativado (o site vai gravar o endereço do cliente nela e também salvar
-- uma cópia congelada em orders.endereco no momento da compra).

-- =========================================================
-- Primeiro admin: depois de criar sua conta pelo site,
-- rode este UPDATE trocando o e-mail pelo seu:
--
-- update public.profiles set is_admin = true
-- where id = (select id from auth.users where email = 'seuemail@exemplo.com');
--
-- Para dar acesso ao Painel do Atendente para um funcionário
-- (sem torná-lo admin), rode trocando pelo e-mail dele:
--
-- update public.profiles set is_funcionario = true
-- where id = (select id from auth.users where email = 'funcionario@exemplo.com');
-- =========================================================
