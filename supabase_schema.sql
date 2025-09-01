-- Supabase ERP Contas a Pagar - schema setup
-- Este script cria todas as tabelas, índices, views, políticas RLS e funções
-- descritas no documento "prompt sistema.txt". Execute -o no SQL Editor do Supabase
-- para provisionar a base de dados completa. Cada bloco utiliza CREATE IF NOT EXISTS
-- para evitar duplicidade.

-- -----------------------------------------------------------------------------
-- Camada de domínio (tabelas canônicas)
-- Empresas e filiais
create table if not exists public.empresas (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  cnpj text unique,
  created_at timestamptz not null default now()
);

create table if not exists public.filiais (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  nome text not null,
  codigo text,
  cnpj text unique,
  created_at timestamptz not null default now()
);

-- Fornecedores (unificados)
create table if not exists public.fornecedores (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  cnpj text unique,
  inscricao_estadual text,
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

-- Categorias e produtos
create table if not exists public.categorias (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  tipo text check (tipo in ('despesa','receita','imposto','outros')) default 'despesa',
  created_at timestamptz not null default now()
);

create table if not exists public.produtos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  sku text,
  categoria_id uuid references public.categorias(id),
  created_at timestamptz not null default now()
);

-- Contas bancárias
create table if not exists public.contas_bancarias (
  id uuid primary key default gen_random_uuid(),
  filial_id uuid references public.filiais(id),
  banco text not null,
  agencia text,
  numero text,
  nome_conta text,
  moeda text default 'BRL',
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists idx_contas_bancarias_filial on public.contas_bancarias(filial_id);

-- -----------------------------------------------------------------------------
-- Fatos financeiros (AP - contas a pagar)
-- Cabeçalho da fatura (nota/conta)
create table if not exists public.ap_faturas (
  id uuid primary key default gen_random_uuid(),
  fornecedor_id uuid not null references public.fornecedores(id),
  filial_id uuid references public.filiais(id),
  categoria_id uuid references public.categorias(id),
  numero_doc text,
  emissao date,
  competencia date,
  observacoes text,
  created_at timestamptz not null default now()
);
create index if not exists idx_ap_faturas_fornecedor on public.ap_faturas(fornecedor_id);
create index if not exists idx_ap_faturas_filial on public.ap_faturas(filial_id);

-- Parcelas da fatura (único lugar do valor e vencimento)
create table if not exists public.ap_parcelas (
  id uuid primary key default gen_random_uuid(),
  fatura_id uuid not null references public.ap_faturas(id) on delete cascade,
  numero_parcela int not null default 1,
  vencimento date not null,
  valor numeric(14,2) not null check (valor >= 0),
  status text not null default 'aberta' check (status in ('aberta','paga','parcial','cancelada','atrasada')),
  pago_em date,
  desconto numeric(14,2) default 0,
  juros numeric(14,2) default 0,
  multa numeric(14,2) default 0,
  created_at timestamptz not null default now()
);
create unique index if not exists uq_ap_parcelas_fatura_numero on public.ap_parcelas(fatura_id, numero_parcela);
create index if not exists idx_ap_parcelas_vencimento on public.ap_parcelas(vencimento);
create index if not exists idx_ap_parcelas_status on public.ap_parcelas(status);

-- Pagamentos (liquidação parcial possível)
create table if not exists public.ap_pagamentos (
  id uuid primary key default gen_random_uuid(),
  parcela_id uuid not null references public.ap_parcelas(id) on delete cascade,
  conta_bancaria_id uuid references public.contas_bancarias(id),
  pago_em date not null,
  valor_pago numeric(14,2) not null check (valor_pago >= 0),
  metodo text,
  observacoes text,
  created_at timestamptz not null default now()
);
create index if not exists idx_ap_pagamentos_parcela on public.ap_pagamentos(parcela_id);

-- Lançamentos bancários (conciliação futura)
create table if not exists public.lancamentos_bancarios (
  id uuid primary key default gen_random_uuid(),
  conta_bancaria_id uuid not null references public.contas_bancarias(id),
  data_mov date not null,
  historico text,
  valor numeric(14,2) not null,
  documento text,
  conciliado boolean not null default false,
  origem text,
  created_at timestamptz not null default now()
);
create index if not exists idx_lcto_bancario_conta_data on public.lancamentos_bancarios(conta_bancaria_id, data_mov);

-- -----------------------------------------------------------------------------
-- Recorrentes
-- Definição de recorrência (plano)
create table if not exists public.ap_recorrentes (
  id uuid primary key default gen_random_uuid(),
  fornecedor_id uuid not null references public.fornecedores(id),
  filial_id uuid references public.filiais(id),
  categoria_id uuid references public.categorias(id),
  nome text not null,
  dia_fechamento int check (dia_fechamento between 1 and 31),
  dia_vencimento int not null check (dia_vencimento between 1 and 31),
  valor_estimado numeric(14,2) default 0,
  inicio date not null default current_date,
  fim date,
  ativo boolean not null default true,
  open_ended boolean not null default true,
  created_at timestamptz not null default now()
);

-- Ocorrência por mês (idempotente por (recorrente_id, ano_mes))
create table if not exists public.ap_recorrencias_mes (
  id uuid primary key default gen_random_uuid(),
  recorrente_id uuid not null references public.ap_recorrentes(id) on delete cascade,
  ano_mes text not null check (ano_mes ~ '^\d{4}-\d{2}$'),
  data_fechamento date,
  data_vencimento date not null,
  valor_estimado numeric(14,2) default 0,
  gerado boolean not null default false,
  unique (recorrente_id, ano_mes),
  created_at timestamptz not null default now()
);
create index if not exists idx_rec_mes_ano_mes on public.ap_recorrencias_mes(ano_mes);

-- -----------------------------------------------------------------------------
-- Comercial (opcional)
create table if not exists public.pedidos (
  id uuid primary key default gen_random_uuid(),
  fornecedor_id uuid references public.fornecedores(id),
  filial_id uuid references public.filiais(id),
  numero text,
  emissao date,
  created_at timestamptz not null default now()
);

create table if not exists public.pedido_itens (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null references public.pedidos(id) on delete cascade,
  produto_id uuid references public.produtos(id),
  quantidade numeric(14,3) not null default 1,
  valor_unitario numeric(14,2) not null default 0,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Suporte
-- Anexos
create table if not exists public.anexos (
  id uuid primary key default gen_random_uuid(),
  entidade text not null check (entidade in ('ap_faturas','ap_parcelas','pedidos')),
  entidade_id uuid not null,
  storage_path text not null,
  mime_type text,
  created_at timestamptz not null default now()
);

-- Auditoria simples
create table if not exists public.auditoria (
  id uuid primary key default gen_random_uuid(),
  tabela text not null,
  registro_id uuid,
  acao text not null,
  diff jsonb,
  actor uuid,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Views analíticas
-- Fato unificado para BI/gráficos
create or replace view public.vw_ap_fato as
select
  pf.id              as fatura_id,
  pp.id              as parcela_id,
  pf.fornecedor_id,
  f.nome             as fornecedor_nome,
  pf.filial_id,
  fi.nome            as filial_nome,
  pf.categoria_id,
  c.nome             as categoria_nome,
  pf.numero_doc,
  pf.emissao,
  pf.competencia,
  pp.numero_parcela,
  pp.vencimento,
  pp.valor,
  pp.status,
  coalesce((
    select sum(pg.valor_pago)
    from public.ap_pagamentos pg
    where pg.parcela_id = pp.id
  ), 0) as total_pago
from public.ap_parcelas pp
join public.ap_faturas pf on pf.id = pp.fatura_id
left join public.fornecedores f on f.id = pf.fornecedor_id
left join public.filiais fi on fi.id = pf.filial_id
left join public.categorias c on c.id = pf.categoria_id;

-- Total por fornecedor por mês (facilita teu gráfico)
create or replace view public.vw_fornecedor_totais as
select
  fornecedor_id,
  max(fornecedor_nome) as fornecedor_nome,
  date_trunc('month', vencimento)::date as mes,
  sum(valor) as total_parcelas,
  sum(case when status = 'paga' then valor else 0 end) as total_pagas
from public.vw_ap_fato
group by fornecedor_id, date_trunc('month', vencimento);

-- -----------------------------------------------------------------------------
-- Índices adicionais (performance)
create index if not exists idx_parcelas_fornecedor on public.ap_parcelas(fatura_id);
create index if not exists idx_faturas_fornecedor_via_cab on public.ap_faturas(fornecedor_id, emissao, competencia);
create index if not exists idx_parcelas_venc_fornecedor on public.ap_parcelas(vencimento, status);

-- -----------------------------------------------------------------------------
-- RLS (Row Level Security) - habilitação e políticas mínimas
alter table public.ap_faturas         enable row level security;
alter table public.ap_parcelas        enable row level security;
alter table public.fornecedores        enable row level security;
-- a tabela public.messages pode não existir ainda; habilite RLS nela quando for criada
alter table public.ap_recorrentes      enable row level security;
alter table public.ap_recorrencias_mes enable row level security;

-- As cláusulas IF NOT EXISTS não são suportadas em CREATE POLICY, portanto
-- descartamos as políticas caso já existam antes de recriá‑las. Isso torna
-- a execução idempotente.
drop policy if exists ap_faturas_select on public.ap_faturas;
create policy ap_faturas_select on public.ap_faturas for select using (true);

drop policy if exists ap_faturas_ins on public.ap_faturas;
create policy ap_faturas_ins    on public.ap_faturas for insert with check (true);

drop policy if exists ap_parcelas_select on public.ap_parcelas;
create policy ap_parcelas_select on public.ap_parcelas for select using (true);

drop policy if exists ap_parcelas_ins on public.ap_parcelas;
create policy ap_parcelas_ins    on public.ap_parcelas for insert with check (true);

drop policy if exists forn_select on public.fornecedores;
create policy forn_select        on public.fornecedores for select using (true);

-- Políticas para messages devem ser criadas quando a tabela existir
drop policy if exists recorr_select on public.ap_recorrentes;
create policy recorr_select      on public.ap_recorrentes for select using (true);

drop policy if exists recorr_mes_select on public.ap_recorrencias_mes;
create policy recorr_mes_select  on public.ap_recorrencias_mes for select using (true);

-- -----------------------------------------------------------------------------
-- Função para materializar recorrência (DB function)
create or replace function public.criar_parcela_recorrente(p_recorrencia_mes_id uuid)
returns uuid
language plpgsql
as $$
declare v_rec record; v_fatura uuid; v_parcela uuid;
begin
  select * into v_rec from public.ap_recorrencias_mes where id = p_recorrencia_mes_id;
  if not found then raise exception 'recorrencia_mes não encontrada'; end if;

  insert into public.ap_faturas (fornecedor_id, filial_id, categoria_id, emissao, competencia, numero_doc)
  select r.fornecedor_id, r.filial_id, r.categoria_id, v_rec.data_fechamento, v_rec.data_fechamento, r.nome
  from public.ap_recorrentes r where r.id = v_rec.recorrente_id
  returning id into v_fatura;

  insert into public.ap_parcelas (fatura_id, numero_parcela, vencimento, valor)
  values (v_fatura, 1, v_rec.data_vencimento, coalesce(v_rec.valor_estimado,0))
  returning id into v_parcela;

  update public.ap_recorrencias_mes set gerado = true where id = p_recorrencia_mes_id;
  return v_parcela;
end $$;
