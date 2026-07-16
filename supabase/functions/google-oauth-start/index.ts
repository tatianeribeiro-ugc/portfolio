// Redireciona o navegador para a tela de autorização do Google.
// Não precisa de login no Supabase pra rodar (JWT verification desligado).
Deno.serve(async (_req) => {
  const clientId = Deno.env.get('GOOGLE_CLIENT_ID')!;
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const redirectUri = `${supabaseUrl}/functions/v1/google-oauth-callback`;

  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: 'code',
    scope: 'https://www.googleapis.com/auth/calendar.events',
    access_type: 'offline',
    prompt: 'consent',
  });

  const url = `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;
  return Response.redirect(url, 302);
});
