-- =====================================================================
-- RE.MAR · métricas de validação do MVP
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run.
--
-- Este script NÃO apaga dados e NÃO mexe nos eventos já gravados.
-- Pode ser executado mais de uma vez sem problema.
-- Rode ANTES de enviar o novo analytics.js/index.html ao GitHub.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) Identificador anônimo do visitante (coluna nova em "eventos")
--    Os eventos antigos ficam com visitor_id vazio (NULL) e continuam
--    valendo para as contagens de visualizações, cliques etc.
-- ---------------------------------------------------------------------
alter table public.eventos add column if not exists visitor_id uuid;


-- ---------------------------------------------------------------------
-- 2) Conversas realmente recebidas no WhatsApp (registro manual)
--    Tabela separada de propósito: "eventos" aceita gravação pública
--    (chave anon), então qualquer pessoa poderia forjar uma "conversa
--    recebida" lá. Esta tabela fica trancada: só você (dashboard/SQL
--    Editor) consegue inserir e ler. Não guarde nome nem telefone.
-- ---------------------------------------------------------------------
create table if not exists public.conversas_whatsapp (
  id          bigint generated always as identity primary key,
  recebida_em timestamptz not null default now(),
  plano       text check (plano in ('mensal', 'anual')),  -- o que a mensagem informa; pode ficar vazio
  observacao  text                                        -- opcional, sem dados pessoais
);

alter table public.conversas_whatsapp enable row level security;
revoke all on public.conversas_whatsapp from anon, authenticated;


-- ---------------------------------------------------------------------
-- 3) A view antiga "resumo_validacao" só conhece nomes de eventos
--    antigos (visita, clique_premium) e mostra zeros. Em vez de apagá-la,
--    ela é apenas RENOMEADA para "resumo_validacao_legado"; o nome
--    "resumo_validacao" passa a ser o resumo novo (passo 5).
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'resumo_validacao'
               and column_name = 'cliques_premium')
     and not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                     where n.nspname = 'public' and c.relname = 'resumo_validacao_legado') then
    alter view public.resumo_validacao rename to resumo_validacao_legado;
  end if;
end $$;


-- ---------------------------------------------------------------------
-- 4) Funções de consulta (todas aceitam período opcional: data inicial e
--    final, no horário de Brasília; vazio = tudo)
--    "security invoker": rodam com as permissões de quem consulta, então
--    a chave pública do site continua sem conseguir ler nada.
-- ---------------------------------------------------------------------

-- 4a) Funil resumido do período
create or replace function public.resumo_periodo(p_inicio date default null, p_fim date default null)
returns table (
  visualizacoes                     bigint,   -- total de page_view
  visitantes_unicos_aprox           bigint,   -- ids anônimos diferentes nos page_view
  selecoes_mensal                   bigint,
  selecoes_anual                    bigint,
  selecoes_plano_total              bigint,
  cliques_cta                       bigint,   -- trial_cta_clicked
  aberturas_whatsapp                bigint,   -- whatsapp_opened
  conversas_recebidas               bigint,   -- registradas manualmente
  aberturas_sem_conversa_confirmada bigint,   -- diferença AGREGADA (não identifica pessoas)
  visitantes_que_escolheram_plano   bigint,
  visitantes_que_clicaram_cta       bigint,
  taxa_visitante_para_plano_pct     numeric,
  taxa_visitante_para_cta_pct       numeric,
  taxa_cta_para_whatsapp_pct        numeric,
  taxa_whatsapp_para_conversa_pct   numeric
)
language sql stable security invoker
set search_path = public, pg_temp
as $$
  with e as (
    select tipo, origem, visitor_id
    from public.eventos
    where (p_inicio is null or (criado_em at time zone 'America/Sao_Paulo')::date >= p_inicio)
      and (p_fim    is null or (criado_em at time zone 'America/Sao_Paulo')::date <= p_fim)
  ),
  a as (
    select
      count(*) filter (where tipo = 'page_view')                                   as vis,
      count(distinct visitor_id) filter (where tipo = 'page_view')                 as uniq,
      count(*) filter (where tipo = 'plan_selected' and origem = 'mensal')         as sm,
      count(*) filter (where tipo = 'plan_selected' and origem = 'anual')          as sa,
      count(*) filter (where tipo = 'plan_selected')                               as st,
      count(*) filter (where tipo = 'trial_cta_clicked')                           as cta,
      count(*) filter (where tipo = 'whatsapp_opened')                             as wa,
      count(distinct visitor_id) filter (where tipo = 'plan_selected')             as u_plano,
      count(distinct visitor_id) filter (where tipo = 'trial_cta_clicked')         as u_cta
    from e
  ),
  c as (
    select count(*) as n
    from public.conversas_whatsapp
    where (p_inicio is null or (recebida_em at time zone 'America/Sao_Paulo')::date >= p_inicio)
      and (p_fim    is null or (recebida_em at time zone 'America/Sao_Paulo')::date <= p_fim)
  )
  select
    a.vis, a.uniq, a.sm, a.sa, a.st, a.cta, a.wa, c.n,
    greatest(a.wa - c.n, 0),
    a.u_plano, a.u_cta,
    round(100.0 * a.u_plano / nullif(a.uniq, 0), 1),
    round(100.0 * a.u_cta   / nullif(a.uniq, 0), 1),
    round(100.0 * a.wa      / nullif(a.cta, 0), 1),
    round(100.0 * c.n       / nullif(a.wa, 0), 1)
  from a, c;
$$;

-- 4b) Resultados por dia
create or replace function public.resultados_por_dia(p_inicio date default null, p_fim date default null)
returns table (
  dia                     date,
  visualizacoes           bigint,
  visitantes_unicos_aprox bigint,
  selecoes_mensal         bigint,
  selecoes_anual          bigint,
  cliques_cta             bigint,
  aberturas_whatsapp      bigint,
  conversas_recebidas     bigint
)
language sql stable security invoker
set search_path = public, pg_temp
as $$
  with e as (
    select (criado_em at time zone 'America/Sao_Paulo')::date as d, tipo, origem, visitor_id
    from public.eventos
  ),
  ed as (
    select d,
      count(*) filter (where tipo = 'page_view')                           as vis,
      count(distinct visitor_id) filter (where tipo = 'page_view')         as uniq,
      count(*) filter (where tipo = 'plan_selected' and origem = 'mensal') as sm,
      count(*) filter (where tipo = 'plan_selected' and origem = 'anual')  as sa,
      count(*) filter (where tipo = 'trial_cta_clicked')                   as cta,
      count(*) filter (where tipo = 'whatsapp_opened')                     as wa
    from e
    group by d
  ),
  cd as (
    select (recebida_em at time zone 'America/Sao_Paulo')::date as d, count(*) as n
    from public.conversas_whatsapp
    group by 1
  )
  select coalesce(ed.d, cd.d),
         coalesce(ed.vis, 0), coalesce(ed.uniq, 0),
         coalesce(ed.sm, 0), coalesce(ed.sa, 0),
         coalesce(ed.cta, 0), coalesce(ed.wa, 0),
         coalesce(cd.n, 0)
  from ed full join cd on cd.d = ed.d
  where (p_inicio is null or coalesce(ed.d, cd.d) >= p_inicio)
    and (p_fim    is null or coalesce(ed.d, cd.d) <= p_fim)
  order by 1;
$$;

-- 4c) Resultados por plano (mensal / anual / nao_informado)
create or replace function public.resultados_por_plano(p_inicio date default null, p_fim date default null)
returns table (
  plano               text,
  selecoes_plano      bigint,
  cliques_cta         bigint,
  aberturas_whatsapp  bigint,
  conversas_recebidas bigint
)
language sql stable security invoker
set search_path = public, pg_temp
as $$
  with e as (
    select tipo,
           case when tipo = 'plan_selected' then nullif(origem, '')
                else nullif(split_part(origem, ':', 2), '') end as pl
    from public.eventos
    where tipo in ('plan_selected', 'trial_cta_clicked', 'whatsapp_opened')
      and (p_inicio is null or (criado_em at time zone 'America/Sao_Paulo')::date >= p_inicio)
      and (p_fim    is null or (criado_em at time zone 'America/Sao_Paulo')::date <= p_fim)
  ),
  ea as (
    select coalesce(pl, 'nao_informado') as pl,
           count(*) filter (where tipo = 'plan_selected')     as s,
           count(*) filter (where tipo = 'trial_cta_clicked') as c,
           count(*) filter (where tipo = 'whatsapp_opened')   as w
    from e
    group by 1
  ),
  ca as (
    select coalesce(plano, 'nao_informado') as pl, count(*) as n
    from public.conversas_whatsapp
    where (p_inicio is null or (recebida_em at time zone 'America/Sao_Paulo')::date >= p_inicio)
      and (p_fim    is null or (recebida_em at time zone 'America/Sao_Paulo')::date <= p_fim)
    group by 1
  )
  select coalesce(ea.pl, ca.pl),
         coalesce(ea.s, 0), coalesce(ea.c, 0), coalesce(ea.w, 0), coalesce(ca.n, 0)
  from ea full join ca on ca.pl = ea.pl
  order by 1;
$$;

-- 4d) Resultados por origem do botão (hero, planos, barra_fixa, cta_final, separar_...)
create or replace function public.resultados_por_origem_cta(p_inicio date default null, p_fim date default null)
returns table (
  origem_cta                 text,
  cliques_cta                bigint,
  aberturas_whatsapp         bigint,
  taxa_cta_para_whatsapp_pct numeric
)
language sql stable security invoker
set search_path = public, pg_temp
as $$
  select coalesce(nullif(split_part(origem, ':', 1), ''), 'desconhecida') as origem_cta,
         count(*) filter (where tipo = 'trial_cta_clicked') as cliques_cta,
         count(*) filter (where tipo = 'whatsapp_opened')   as aberturas_whatsapp,
         round(100.0 * count(*) filter (where tipo = 'whatsapp_opened')
               / nullif(count(*) filter (where tipo = 'trial_cta_clicked'), 0), 1)
  from public.eventos
  where tipo in ('trial_cta_clicked', 'whatsapp_opened')
    and (p_inicio is null or (criado_em at time zone 'America/Sao_Paulo')::date >= p_inicio)
    and (p_fim    is null or (criado_em at time zone 'America/Sao_Paulo')::date <= p_fim)
  group by 1
  order by 2 desc, 1;
$$;

-- 4e) Relatório final em texto (uma linha por linha do relatório)
--     Uso: select * from relatorio_validacao();                       -- tudo
--          select * from relatorio_validacao('2026-09-19','2026-09-21');  -- período
create or replace function public.relatorio_validacao(p_inicio date default null, p_fim date default null)
returns setof text
language plpgsql stable security invoker
set search_path = public, pg_temp
as $$
declare
  r record;
  x record;
  sem text := 'sem dados';
begin
  select * into r from public.resumo_periodo(p_inicio, p_fim);

  return next 'RE.MAR — Relatório de Validação';
  return next format('Período: %s a %s',
                     coalesce(to_char(p_inicio, 'DD/MM/YYYY'), 'início'),
                     coalesce(to_char(p_fim, 'DD/MM/YYYY'), 'hoje'));
  return next '';
  return next format('%s visualizações', r.visualizacoes);
  return next format('%s visitantes únicos (aproximado)', r.visitantes_unicos_aprox);
  return next format('%s seleções de plano', r.selecoes_plano_total);
  return next format('   %s Mensal · %s Anual', r.selecoes_mensal, r.selecoes_anual);
  return next format('%s cliques em "Quero testar grátis"', r.cliques_cta);
  return next format('%s aberturas do WhatsApp', r.aberturas_whatsapp);
  return next format('%s conversas realmente recebidas', r.conversas_recebidas);
  return next format('%s aberturas sem conversa confirmada (diferença agregada)', r.aberturas_sem_conversa_confirmada);
  return next '';
  return next 'Taxas de conversão';
  return next format('   visitante → seleção de plano: %s', coalesce(r.taxa_visitante_para_plano_pct::text || '%', sem));
  return next format('   visitante → clique no CTA: %s', coalesce(r.taxa_visitante_para_cta_pct::text || '%', sem));
  return next format('   clique no CTA → WhatsApp aberto: %s', coalesce(r.taxa_cta_para_whatsapp_pct::text || '%', sem));
  return next format('   WhatsApp aberto → conversa recebida: %s', coalesce(r.taxa_whatsapp_para_conversa_pct::text || '%', sem));
  return next '';

  return next 'Por dia';
  for x in select * from public.resultados_por_dia(p_inicio, p_fim) loop
    return next format('   %s: %s visualizações · %s visitantes · %s Mensal · %s Anual · %s cliques · %s WhatsApp · %s conversas',
                       to_char(x.dia, 'DD/MM'), x.visualizacoes, x.visitantes_unicos_aprox,
                       x.selecoes_mensal, x.selecoes_anual, x.cliques_cta, x.aberturas_whatsapp, x.conversas_recebidas);
  end loop;
  return next '';

  return next 'Por plano';
  for x in select * from public.resultados_por_plano(p_inicio, p_fim) loop
    return next format('   %s: %s seleções · %s cliques · %s WhatsApp · %s conversas',
                       x.plano, x.selecoes_plano, x.cliques_cta, x.aberturas_whatsapp, x.conversas_recebidas);
  end loop;
  return next '';

  return next 'Por origem do botão';
  for x in select * from public.resultados_por_origem_cta(p_inicio, p_fim) loop
    return next format('   %s: %s cliques · %s WhatsApp',
                       x.origem_cta, x.cliques_cta, x.aberturas_whatsapp);
  end loop;
  return next '';

  return next 'Como ler:';
  return next '   • Visitantes únicos são aproximados (um identificador anônimo por navegador); eventos anteriores';
  return next '     ao identificador contam nas visualizações e cliques, mas não nos visitantes únicos.';
  return next '   • "WhatsApp aberto" só mostra que a pessoa iniciou a conversa pelo site. "Conversa recebida" é';
  return next '     registrada manualmente. A diferença é um número agregado: não indica quem deixou de enviar.';
  return;
end;
$$;


-- ---------------------------------------------------------------------
-- 5) Views para consultar direto no Supabase (Table Editor / SQL Editor)
--    Ficam "trancadas": a chave pública do site não lê nada delas.
-- ---------------------------------------------------------------------
create or replace view public.resumo_validacao
  with (security_invoker = true) as
  select * from public.resumo_periodo(null, null);

create or replace view public.funil_por_dia
  with (security_invoker = true) as
  select * from public.resultados_por_dia(null, null);

create or replace view public.funil_por_plano
  with (security_invoker = true) as
  select * from public.resultados_por_plano(null, null);

create or replace view public.funil_por_origem_cta
  with (security_invoker = true) as
  select * from public.resultados_por_origem_cta(null, null);


-- ---------------------------------------------------------------------
-- 6) Trancar o acesso público (mesma regra das demais tabelas)
-- ---------------------------------------------------------------------
revoke all on public.resumo_validacao, public.funil_por_dia,
              public.funil_por_plano, public.funil_por_origem_cta
  from anon, authenticated;

revoke execute on function
  public.resumo_periodo(date, date),
  public.resultados_por_dia(date, date),
  public.resultados_por_plano(date, date),
  public.resultados_por_origem_cta(date, date),
  public.relatorio_validacao(date, date)
  from public, anon, authenticated;
