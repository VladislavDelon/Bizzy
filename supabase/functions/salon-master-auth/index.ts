import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.42.0';

// Салон меняет логин/пароль мастера своей команды.
// Тело: { master_id: string, login?: string, password?: string }
// Требуется JWT салона. Логика логина/пароля повторяет клиентскую:
// ASCII-логин -> login@bizzy.app, иначе u<base64url>@bizzy.app;
// пароль -> 'Bz!9' + sha256(raw) — приложение принимает любые 6+ символов.

const LOGIN_DOMAIN = 'bizzy.app';

function loginToEmail(input: string): string {
  const login = input.trim().toLowerCase();
  if (login.includes('@')) return login;
  if (/^[a-z0-9._-]+$/.test(login)) return `${login}@${LOGIN_DOMAIN}`;
  const bytes = new TextEncoder().encode(login);
  let bin = '';
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  const encoded = btoa(bin).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  return `u${encoded}@${LOGIN_DOMAIN}`;
}

async function hardPassword(raw: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(raw));
  const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
  return `Bz!9${hex}`;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const payload = await req.json().catch(() => null);
  const masterId = payload?.master_id;
  const login = (payload?.login ?? '').trim();
  const password = payload?.password ?? '';
  if (!masterId || (!login && !password)) {
    return json({ error: 'master_id and login or password are required' }, 400);
  }
  if (password && password.length < 6) {
    return json({ error: 'password must be at least 6 characters' }, 400);
  }

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY') ?? '', {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const {
    data: { user },
  } = await caller.auth.getUser();
  if (!user) return json({ error: 'unauthorized' }, 401);

  // Менять можно только мастера, привязанного к этому салону.
  const { data: mp } = await caller
    .from('master_profiles')
    .select('salon_id')
    .eq('user_id', masterId)
    .maybeSingle();
  if (!mp || mp.salon_id !== user.id) {
    return json({ error: 'master is not in your team' }, 403);
  }

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
  const attrs: Record<string, unknown> = {};
  if (login) {
    attrs.email = loginToEmail(login);
    attrs.user_metadata = { login: login.toLowerCase() };
  }
  if (password) attrs.password = await hardPassword(password);

  const { error } = await admin.auth.admin.updateUserById(masterId, attrs);
  if (error) return json({ error: error.message }, 400);
  return json({ ok: true });
});
