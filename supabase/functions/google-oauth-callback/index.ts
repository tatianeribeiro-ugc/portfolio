// Recebe o "code" do Google, troca por access_token + refresh_token, e
// guarda os dois em google_calendar_tokens (só a service_role enxerga essa
// tabela). Também não precisa de login no Supabase pra rodar.
import { createClient } from 'jsr:@supabase/supabase-js@2';

function paginaHtml(titulo: string, corpo: string) {
  return `<!doctype html><html lang="pt-BR"><head><meta charset="UTF-8">
    <title>${titulo}</title></head>
    <body style="font-family:sans-serif; text-align:center; padding:60px; background:#F5F3EF; color:#1A1816;">
      ${corpo}
    </body></html>`;
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const code = url.searchParams.get('code');
  const erroGoogle = url.searchParams.get('error');

  if (erroGoogle) {
    return new Response(paginaHtml('Erro', `<h1>Erro na autorização</h1><p>${erroGoogle}</p>`), {
      headers: { 'Content-Type': 'text/html; charset=utf-8' },
    });
  }
  if (!code) {
    return new Response(paginaHtml('Erro', '<h1>Código não encontrado</h1>'), {
      status: 400,
      headers: { 'Content-Type': 'text/html; charset=utf-8' },
    });
  }

  const clientId = Deno.env.get('GOOGLE_CLIENT_ID')!;
  const clientSecret = Deno.env.get('GOOGLE_CLIENT_SECRET')!;
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const redirectUri = `${supabaseUrl}/functions/v1/google-oauth-callback`;

  const tokenResp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: redirectUri,
      grant_type: 'authorization_code',
    }),
  });
  const tokens = await tokenResp.json();

  if (!tokenResp.ok) {
    return new Response(paginaHtml('Erro', `<h1>Erro ao trocar o código por token</h1><pre>${JSON.stringify(tokens, null, 2)}</pre>`), {
      status: 400,
      headers: { 'Content-Type': 'text/html; charset=utf-8' },
    });
  }

  const db = createClient(supabaseUrl, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const expiresAt = new Date(Date.now() + (tokens.expires_in ?? 3600) * 1000).toISOString();

  const payload: Record<string, unknown> = {
    id: 1,
    access_token: tokens.access_token,
    access_token_expires_at: expiresAt,
    updated_at: new Date().toISOString(),
  };
  // O Google só manda refresh_token na primeira autorização (por isso o
  // prompt=consent no google-oauth-start, pra garantir que sempre venha).
  if (tokens.refresh_token) {
    payload.refresh_token = tokens.refresh_token;
  }

  const { error: dbError } = await db.from('google_calendar_tokens').upsert(payload);
  if (dbError) {
    return new Response(paginaHtml('Erro', `<h1>Erro ao salvar o token</h1><pre>${dbError.message}</pre>`), {
      status: 500,
      headers: { 'Content-Type': 'text/html; charset=utf-8' },
    });
  }

  return new Response(
    paginaHtml('Conectado', '<h1>✅ Google Calendar conectado!</h1><p>Pode fechar esta aba e voltar para o painel.</p>'),
    { headers: { 'Content-Type': 'text/html; charset=utf-8' } }
  );
});
