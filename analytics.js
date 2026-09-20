/* re.mar · analytics simples -> Supabase (tabela public.eventos)
 *
 * Eventos registrados:
 *   page_view          ao abrir/atualizar a pagina        (origem = de onde veio, ou "direto")
 *   plan_selected      ao escolher Mensal ou Anual         (origem = mensal | anual)
 *   trial_cta_clicked  ao clicar em QUERO TESTAR GRATIS    (origem = secao:plano, ex. hero:anual)
 *   whatsapp_opened    quando o WhatsApp e aberto          (origem = secao:plano)
 *   (tambem: clique_gratuito e nivel_* da secao "Como voce quer separar hoje?")
 *
 * Regras: nunca lanca erro e nunca espera resposta (fire-and-forget), entao um problema
 * no registro NAO impede o site nem a abertura do WhatsApp. Usa so o INSERT permitido
 * ao papel anon (Prefer: return=minimal, sem "upsert").
 * Chaves: window.REMAR_CONFIG (config.js).
 */
(function () {
  var W = window;

  function conf() {
    var c = W.REMAR_CONFIG || {};
    return { url: String(c.supabaseUrl || '').replace(/\/$/, ''), key: String(c.supabaseAnonKey || '') };
  }

  function aviso(msg, extra) {
    try { if (W.console && W.console.warn) W.console.warn('[re.mar analytics] ' + msg, extra || ''); } catch (e) {}
  }

  function track(tipo, origem) {
    try {
      var c = conf();
      if (!c.url || !c.key) { aviso('supabaseUrl/supabaseAnonKey ausentes em config.js; evento nao enviado:', tipo); return; }
      var p = fetch(c.url + '/rest/v1/eventos', {
        method: 'POST',
        keepalive: true,
        headers: {
          'Content-Type': 'application/json',
          apikey: c.key,
          Authorization: 'Bearer ' + c.key,
          Prefer: 'return=minimal'
        },
        body: JSON.stringify({ tipo: String(tipo), origem: String(origem == null ? '' : origem).slice(0, 200) })
      });
      if (p && typeof p.then === 'function') {
        p.then(
          function (r) { if (!r.ok) aviso('Supabase respondeu ' + r.status + ' ao registrar ' + tipo); },
          function (e) { aviso('falha de rede ao registrar ' + tipo, e); }
        ).then(null, function () {});
      }
    } catch (e) { aviso('erro ao registrar ' + tipo, e); }
  }

  W.remarTrack = track;

  // page_view: a cada abertura/atualizacao da pagina
  track('page_view', (document.referrer || '').slice(0, 200) || 'direto');
})();
