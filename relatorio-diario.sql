-- OPCIONAL: relatorio diario por e-mail (Supabase + Resend)
-- Requer as extensoes pg_cron e pg_net (Database > Extensions) e uma conta Resend.

create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function public.enviar_relatorio_remar()
returns void language plpgsql security definer as $$
declare corpo text; r record;
begin
  select * into r from public.resumo_validacao;
  corpo := format(
    '<h2>re.mar · validacao Premium</h2>
     <p>Visitantes: %s<br>Cliques Premium: %s<br>Cliques conta gratuita: %s<br>
     Leads Premium: %s (mensal %s / anual %s)<br>Leads gratuitos: %s<br>
     <b>Conversao Premium: %s%%</b></p>',
    r.visitantes, r.cliques_premium, r.cliques_gratuito,
    r.leads_premium, r.preferem_mensal, r.preferem_anual, r.leads_gratuito,
    coalesce(r.conversao_premium_pct, 0));

  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer SUA_RESEND_API_KEY'),
    body := jsonb_build_object(
      'from', 're.mar <relatorio@seudominio.com>',
      'to', jsonb_build_array('voce@seudominio.com'),
      'subject', 're.mar · relatorio diario da landing',
      'html', corpo)
  );
end; $$;

-- Todo dia as 9h (UTC-3 = 12:00 UTC)
select cron.schedule('remar-relatorio-diario', '0 12 * * *', $$select public.enviar_relatorio_remar();$$);
