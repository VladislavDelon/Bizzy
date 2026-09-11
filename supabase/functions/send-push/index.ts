import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.42.0';

interface PushPayload {
  to_user_id: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

const FCM_LEGACY_URL = 'https://fcm.googleapis.com/fcm/send';

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const payload = (await req.json()) as PushPayload;
  const toUserId = payload?.to_user_id;
  const title = payload?.title ?? 'Bizzy';
  const body = payload?.body ?? '';
  const data = payload?.data ?? {};

  if (!toUserId || !title) {
    return new Response(JSON.stringify({ error: 'to_user_id and title are required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  const { data: rows, error } = await supabase
    .from('fcm_tokens')
    .select('token')
    .eq('user_id', toUserId);

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const tokens = (rows ?? []).map((r) => r.token as string);
  if (tokens.length === 0) {
    return new Response(JSON.stringify({ sent: 0, tokens: [] }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const serverKey = Deno.env.get('FCM_SERVER_KEY');
  if (!serverKey) {
    return new Response(JSON.stringify({ error: 'FCM_SERVER_KEY not configured' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // FCM legacy API: up to 500 tokens per request (multicast).
  const results: unknown[] = [];
  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    const fcmPayload =
      chunk.length === 1
        ? {
            to: chunk[0],
            notification: { title, body },
            data: { ...data, title, body },
            priority: 'high',
          }
        : {
            registration_ids: chunk,
            notification: { title, body },
            data: { ...data, title, body },
            priority: 'high',
          };

    const res = await fetch(FCM_LEGACY_URL, {
      method: 'POST',
      headers: {
        'Authorization': `key=${serverKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(fcmPayload),
    });

    const resBody = await res.json().catch(() => ({}));
    results.push({ status: res.status, body: resBody });
  }

  return new Response(JSON.stringify({ sent: tokens.length, results }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
