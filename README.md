# re.mar · Landing de validacao do Premium

Landing mobile-first que capta interesse no plano Premium e na conta gratuita, grava os leads no Supabase e publica de graca no GitHub Pages.

## Arquivos

- `index.html` — a landing inteira (abre direto no navegador)
- `config.js` — onde voce cola a URL e a chave publica do Supabase
- `support.js` — runtime que renderiza a pagina
- `assets/` — fotos dos produtos
- `supabase/schema.sql` — tabelas, permissoes e painel de metricas
- `supabase/relatorio-diario.sql` — opcional: e-mail diario com o resumo
- `.github/workflows/deploy-pages.yml` — publica no GitHub Pages a cada push

## WhatsApp (botao QUERO TESTAR GRATIS)

Os botoes Premium abrem direto o WhatsApp com mensagem pronta (Mensal R$ 9,90 ou Anual R$ 159, conforme o plano escolhido).
O numero fica em UM lugar so: `site-config.js` (campo `whatsappNumber`, so digitos: 55 + DDD + numero).
Cada clique Premium tambem e registrado no Supabase (`eventos`, tipo `clique_premium`, origem `secao:plano`) e cada escolha em "Como voce quer separar hoje?" vira um evento `nivel_rapido | nivel_facil | nivel_medio | nivel_avancado`.
A conta gratuita continua usando o formulario (nome + celular) e gravando em `leads`.

## Caminho rapido: Formspree (so leads, sem SQL)

1. Em formspree.io: **New Form**, de um nome (ex.: re.mar leads) e salve.
2. Copie o endpoint `https://formspree.io/f/XXXXXXXX`.
3. Cole em `config.js`, no campo `formspreeUrl`.
4. Abra a landing, faca um cadastro de teste e confirme o e-mail e o registro em **Submissions**.

Cada lead chega por e-mail com nome, celular, tipo (premium/gratuito), ciclo e origem. Limites do plano gratuito (verifique em formspree.io/plans): cerca de 50 envios por mes e sem exportar CSV. O Formspree so recebe leads; visitas e cliques (conversao) continuam dependendo do Supabase.

No GitHub Pages nao precisa cadastrar variaveis: o deploy usa o `config.js` como esta (so chaves publicas).

## 1. Criar o banco no Supabase (opcional se usar so Formspree)

1. Crie um projeto em supabase.com (plano free serve).
2. **SQL Editor > New query**, cole o conteudo de `supabase/schema.sql` e rode.
3. **Settings > API**: copie *Project URL* e a chave *anon public*.

A chave anon pode ficar publica: as politicas de RLS permitem apenas INSERT. Ninguem consegue ler a lista pelo navegador.

## 2. Configurar a landing

Abra `config.js` e preencha:

```js
window.REMAR_CONFIG = {
  supabaseUrl: "https://xxxxxxxx.supabase.co",
  supabaseAnonKey: "eyJhbGciOi..."
};
```

Abra `index.html` no navegador e faca um cadastro de teste. A linha deve aparecer em **Table Editor > leads**.

## 3. Subir para o GitHub e publicar

```bash
git init
git add .
git commit -m "landing re.mar premium"
git branch -M main
git remote add origin https://github.com/SEU-USUARIO/remar-landing.git
git push -u origin main
```

No repositorio: **Settings > Pages > Source: GitHub Actions**.

Para nao versionar as chaves, apague o conteudo de `config.js` e cadastre em **Settings > Secrets and variables > Actions > Variables**: `SUPABASE_URL` e `SUPABASE_ANON_KEY`. O workflow gera o `config.js` no deploy.

O link publico fica `https://SEU-USUARIO.github.io/remar-landing/` — e esse o link para mandar no WhatsApp.

## 4. Ler os resultados

No Supabase, **SQL Editor**:

```sql
select * from resumo_validacao;
select nome, celular, tipo, ciclo, origem, criado_em from leads order by criado_em desc;
```

Metrica principal: `conversao_premium_pct` (leads Premium / visitantes).

Exportar a lista: **Table Editor > leads > Export > CSV**.

## 5. Relatorio por e-mail (opcional)

Rode `supabase/relatorio-diario.sql` depois de ativar as extensoes `pg_cron` e `pg_net` e trocar a chave da Resend e os e-mails. Chega um resumo diario as 9h.

## Observacoes

- O celular e deduplicado pelo campo `telefone_digitos` (unique): o mesmo numero nao entra duas vezes.
- Sem o `config.js` preenchido a landing continua funcionando, so que gravando no proprio navegador (modo demonstracao).
- Nenhuma cobranca acontece nesta pagina: ela registra interesse.
