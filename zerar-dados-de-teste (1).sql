-- =====================================================================
-- RE.MAR · apagar SOMENTE os registros de teste (começar a validação do zero)
--
-- Apaga apenas LINHAS de 3 tabelas: eventos, leads e conversas_whatsapp.
-- NÃO apaga nem altera tabelas, views, funções, colunas, políticas de
-- segurança (RLS) ou permissões. NÃO mexe nas views (funil_por_dia,
-- funil_por_plano, funil_por_origem_cta, resumo_validacao): elas são só
-- cálculos em cima das tabelas e ficam zeradas sozinhas.
--
-- Como usar: Supabase > SQL Editor > New query > cole TUDO > Run.
-- O Supabase vai avisar que a consulta é "destrutiva" (tem DELETE sem
-- WHERE): é esperado, confirme. Rode UMA vez, ANTES de divulgar o site.
-- =====================================================================

begin;

-- Trava de segurança: só continua se as 3 forem TABELAS de verdade
-- (se alguma faltar ou for uma view, aborta tudo e NADA é apagado).
do $$
declare t text;
begin
  foreach t in array array['eventos', 'leads', 'conversas_whatsapp'] loop
    if not exists (select 1
                   from pg_class c join pg_namespace n on n.oid = c.relnamespace
                   where n.nspname = 'public' and c.relname = t and c.relkind = 'r') then
      raise exception 'public.% não existe ou não é uma tabela. Nada foi apagado.', t;
    end if;
  end loop;
end $$;

delete from public.conversas_whatsapp;   -- conversas de teste registradas à mão
delete from public.leads;                -- leads de teste (conta gratuita)
delete from public.eventos;              -- page_view, plan_selected, trial_cta_clicked, whatsapp_opened...

commit;

-- Conferência: tudo deve aparecer 0 (as taxas ficam vazias = "sem dados")
select
  (select count(*) from public.eventos)            as linhas_eventos,
  (select count(*) from public.leads)              as linhas_leads,
  (select count(*) from public.conversas_whatsapp) as linhas_conversas,
  r.*
from public.resumo_validacao r;
