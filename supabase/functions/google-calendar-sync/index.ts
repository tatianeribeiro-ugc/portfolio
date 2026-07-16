// Sincroniza eventos entre a tabela "events" do painel e o Google Calendar.
// Chamada sob demanda (não usa tarefa agendada): o painel chama esta função
// depois de salvar/excluir/arrastar um evento (push) e sempre que abre o
// Calendário (pull). Precisa de login no painel pra rodar (JWT verification
// ligado, ao contrário das duas funções de OAuth).
import { createClient } from 'jsr:@supabase/supabase-js@2';

const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const GOOGLE_CALENDAR_API = 'https://www.googleapis.com/calendar/v3';
const TIME_ZONE = 'America/Sao_Paulo';

function admin() {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );
}

async function getValidAccessToken(db: ReturnType<typeof admin>) {
  const { data: row, error } = await db.from('google_calendar_tokens').select('*').eq('id', 1).maybeSingle();
  if (error) throw error;
  if (!row || !row.refresh_token) {
    throw new Error('NAO_CONECTADO');
  }

  const expiraEm = row.access_token_expires_at ? new Date(row.access_token_expires_at).getTime() : 0;
  if (row.access_token && expiraEm - Date.now() > 60_000) {
    return { accessToken: row.access_token as string, calendarId: row.calendar_id as string, syncToken: row.sync_token as string | null };
  }

  const resp = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: Deno.env.get('GOOGLE_CLIENT_ID')!,
      client_secret: Deno.env.get('GOOGLE_CLIENT_SECRET')!,
      refresh_token: row.refresh_token,
      grant_type: 'refresh_token',
    }),
  });
  const tokens = await resp.json();
  if (!resp.ok) throw new Error('Falha ao renovar token do Google: ' + JSON.stringify(tokens));

  const novaExpiracao = new Date(Date.now() + (tokens.expires_in ?? 3600) * 1000).toISOString();
  await db.from('google_calendar_tokens').update({
    access_token: tokens.access_token,
    access_token_expires_at: novaExpiracao,
    updated_at: new Date().toISOString(),
  }).eq('id', 1);

  return { accessToken: tokens.access_token as string, calendarId: row.calendar_id as string, syncToken: row.sync_token as string | null };
}

function localParaGoogle(evento: Record<string, any>) {
  const corpo: Record<string, any> = {
    summary: evento.title,
    description: evento.description || undefined,
    extendedProperties: {
      private: {
        category: evento.category || '',
        priority: evento.priority || '',
        status: evento.status || '',
      },
    },
  };
  if (evento.all_day) {
    corpo.start = { date: String(evento.start_date).slice(0, 10) };
    corpo.end = { date: String(evento.end_date || evento.start_date).slice(0, 10) };
  } else {
    corpo.start = { dateTime: evento.start_date, timeZone: TIME_ZONE };
    corpo.end = { dateTime: evento.end_date || evento.start_date, timeZone: TIME_ZONE };
  }
  return corpo;
}

function googleParaLocal(gEvento: Record<string, any>) {
  const priv = gEvento.extendedProperties?.private || {};
  const diaTodo = !!gEvento.start?.date;
  const dataInicio = diaTodo ? new Date(gEvento.start.date + 'T00:00:00').toISOString() : gEvento.start?.dateTime;
  const dataFim = diaTodo
    ? new Date((gEvento.end?.date || gEvento.start.date) + 'T00:00:00').toISOString()
    : (gEvento.end?.dateTime || null);

  return {
    title: gEvento.summary || '(sem título)',
    description: gEvento.description || null,
    category: priv.category || 'pessoal',
    priority: priv.priority || 'media',
    status: priv.status || 'agendado',
    start_date: dataInicio,
    end_date: dataFim,
    all_day: diaTodo,
    google_event_id: gEvento.id,
    last_synced_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
}

async function empurrarUm(db: ReturnType<typeof admin>, accessToken: string, calendarId: string, eventId: string) {
  const { data: evento, error } = await db.from('events').select('*').eq('id', eventId).maybeSingle();
  if (error) throw error;
  if (!evento) return { pulado: true };

  const corpo = localParaGoogle(evento);
  const base = `${GOOGLE_CALENDAR_API}/calendars/${encodeURIComponent(calendarId)}/events`;
  const resp = evento.google_event_id
    ? await fetch(`${base}/${evento.google_event_id}`, {
        method: 'PUT',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(corpo),
      })
    : await fetch(base, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(corpo),
      });

  const resultado = await resp.json();
  if (!resp.ok) throw new Error('Erro ao enviar evento pro Google: ' + JSON.stringify(resultado));

  await db.from('events').update({
    google_event_id: resultado.id,
    last_synced_at: new Date().toISOString(),
  }).eq('id', eventId);

  return { ok: true, googleEventId: resultado.id };
}

async function excluirUm(accessToken: string, calendarId: string, googleEventId: string) {
  const resp = await fetch(`${GOOGLE_CALENDAR_API}/calendars/${encodeURIComponent(calendarId)}/events/${googleEventId}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!resp.ok && resp.status !== 404 && resp.status !== 410) {
    throw new Error('Erro ao excluir evento no Google: ' + (await resp.text()));
  }
  return { ok: true };
}

async function puxar(db: ReturnType<typeof admin>, accessToken: string, calendarId: string, syncToken: string | null): Promise<{ ok: true; processados: number }> {
  let url = `${GOOGLE_CALENDAR_API}/calendars/${encodeURIComponent(calendarId)}/events?maxResults=250&singleEvents=true`;
  if (syncToken) {
    url += `&syncToken=${encodeURIComponent(syncToken)}`;
  } else {
    const seisMesesAtras = new Date();
    seisMesesAtras.setMonth(seisMesesAtras.getMonth() - 6);
    url += `&timeMin=${encodeURIComponent(seisMesesAtras.toISOString())}`;
  }

  let proximaPagina: string | undefined;
  let novoSyncToken: string | undefined;
  let processados = 0;

  do {
    const urlPagina = proximaPagina ? `${url}&pageToken=${proximaPagina}` : url;
    const resp = await fetch(urlPagina, { headers: { Authorization: `Bearer ${accessToken}` } });
    const dados = await resp.json();

    if (!resp.ok) {
      if (dados.error?.status === 'GONE') {
        await db.from('google_calendar_tokens').update({ sync_token: null }).eq('id', 1);
        return await puxar(db, accessToken, calendarId, null);
      }
      throw new Error('Erro ao buscar eventos do Google: ' + JSON.stringify(dados));
    }

    for (const gEvento of dados.items || []) {
      processados++;
      if (gEvento.status === 'cancelled') {
        await db.from('events').delete().eq('google_event_id', gEvento.id);
        continue;
      }
      const local = googleParaLocal(gEvento);
      const { data: existente } = await db.from('events').select('id').eq('google_event_id', gEvento.id).maybeSingle();
      if (existente) {
        await db.from('events').update(local).eq('id', existente.id);
      } else {
        await db.from('events').insert(local);
      }
    }

    proximaPagina = dados.nextPageToken;
    if (dados.nextSyncToken) novoSyncToken = dados.nextSyncToken;
  } while (proximaPagina);

  if (novoSyncToken) {
    await db.from('google_calendar_tokens').update({ sync_token: novoSyncToken, updated_at: new Date().toISOString() }).eq('id', 1);
  }

  return { ok: true, processados };
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const db = admin();
    const { action, eventId, googleEventId } = await req.json().catch(() => ({} as Record<string, unknown>));

    let accessToken: string, calendarId: string, syncToken: string | null;
    try {
      ({ accessToken, calendarId, syncToken } = await getValidAccessToken(db));
    } catch (erro) {
      if (String((erro as Error).message) === 'NAO_CONECTADO') {
        return new Response(JSON.stringify({ conectado: false }), { headers: { ...CORS, 'Content-Type': 'application/json' } });
      }
      throw erro;
    }

    let resultado: unknown;
    if (action === 'push_one' && eventId) {
      resultado = await empurrarUm(db, accessToken, calendarId, eventId as string);
    } else if (action === 'delete_one' && googleEventId) {
      resultado = await excluirUm(accessToken, calendarId, googleEventId as string);
    } else if (action === 'pull') {
      resultado = await puxar(db, accessToken, calendarId, syncToken);
    } else if (action === 'full') {
      const pendentes = await db.from('events').select('id').or('last_synced_at.is.null,last_synced_at.lt.updated_at');
      for (const p of pendentes.data || []) {
        await empurrarUm(db, accessToken, calendarId, p.id);
      }
      resultado = await puxar(db, accessToken, calendarId, syncToken);
    } else {
      return new Response(JSON.stringify({ error: 'Ação inválida.' }), { status: 400, headers: { ...CORS, 'Content-Type': 'application/json' } });
    }

    return new Response(JSON.stringify({ conectado: true, ...(resultado as Record<string, unknown>) }), {
      headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  } catch (erro) {
    console.error(erro);
    return new Response(JSON.stringify({ error: String((erro as Error)?.message || erro) }), {
      status: 500,
      headers: { ...CORS, 'Content-Type': 'application/json' },
    });
  }
});
