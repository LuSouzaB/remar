-- re.mar · landing de validacao do Premium
-- Rode no Supabase: SQL Editor > New query > cole tudo > Run.

create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  criado_em timestamptz not null default now(),
  nome text not null,
  celular text not null,
  telefone_digitos text not null unique,
  tipo text not null default 'premium',      -- premium | gratuito
  ciclo text,                                 -- mensal | anual | null
  origem text                                 -- hero, planos, cta_final, barra_fixa...
);

create table if not exists public.eventos (
  id bigserial primary key,
  criado_em timestamptz not null default now(),
  tipo text not null,                         -- visita | clique_premium | clique_gratuito
  origem text
);

alter table public.leads enable row level security;
alter table public.eventos enable row level security;

-- A landing so pode INSERIR. Ninguem le os dados com a chave publica.
drop policy if exists "anon insere lead" on public.leads;
create policy "anon insere lead" on public.leads
  for insert to anon with check (true);

drop policy if exists "anon insere evento" on public.eventos;
create policy "anon insere evento" on public.eventos
  for insert to anon with check (true);

-- Painel de validacao (leia no SQL Editor ou no Table Editor, logado)
create or replace view public.resumo_validacao as
select
  (select count(*) from public.eventos where tipo = 'visita')             as visitantes,
  (select count(*) from public.eventos where tipo = 'clique_premium')     as cliques_premium,
  (select count(*) from public.eventos where tipo = 'clique_gratuito')    as cliques_gratuito,
  (select count(*) from public.leads  where tipo = 'premium')             as leads_premium,
  (select count(*) from public.leads  where tipo = 'gratuito')            as leads_gratuito,
  (select count(*) from public.leads  where ciclo = 'mensal')             as preferem_mensal,
  (select count(*) from public.leads  where ciclo = 'anual')              as preferem_anual,
  round(
    100.0 * (select count(*) from public.leads where tipo = 'premium')
    / nullif((select count(*) from public.eventos where tipo = 'visita'), 0)
  , 1) as conversao_premium_pct;
