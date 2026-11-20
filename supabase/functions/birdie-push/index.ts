// Tirsdagsklubben: send push-besked når en spiller laver birdie eller bedre.
// Kaldes af databasen (trigger docs_birdie i supabase/push.sql) hver gang en score gemmes.
// Funktionen stoler ikke på det, den får tilsendt: den læser selv runden og sender kun nye birdies.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

// Samme par som i appen (index.html, COURSES_DEFAULT). Et dokument courses/<id> med par overstyrer.
const PAR: Record<string, number[]> = {
  old: [4, 5, 4, 4, 3, 4, 4, 3, 5, 5, 4, 3, 4, 3, 4, 3, 5, 5],
  new: [5, 3, 4, 5, 3, 4, 5, 4, 3, 4, 4, 5, 3, 4, 4, 4, 3, 5],
};
const SITE = "https://bctpy2f2zn-pixel.github.io/Tirsdagsklubben/";
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { "Content-Type": "application/json" } });

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

async function keys() {
  const { data } = await sb.from("push_keys").select("public_key,private_key").eq("id", 1).maybeSingle();
  if (data) return data;
  const k = webpush.generateVAPIDKeys();
  await sb.from("push_keys").upsert({ id: 1, public_key: k.publicKey, private_key: k.privateKey }, { onConflict: "id", ignoreDuplicates: true });
  const { data: again } = await sb.from("push_keys").select("public_key,private_key").eq("id", 1).single();
  return again!;
}

function word(v: number, d: number) {
  return v === 1 ? "hole-in-one" : d <= -3 ? "albatros" : d === -2 ? "eagle" : "birdie";
}

Deno.serve(async (req) => {
  const k = await keys();
  if (req.method !== "POST") return json({ ok: true, publicKey: k.public_key });
  const { rid } = await req.json().catch(() => ({}));
  if (typeof rid !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(rid)) return json({ error: "bad rid" }, 400);

  const { data: rd } = await sb.from("docs").select("data").eq("path", `rounds/${rid}`).maybeSingle();
  const r = rd?.data;
  if (!r || r.status !== "live") return json({ ok: true, skipped: "not live" });
  const { data: cd } = await sb.from("docs").select("data").eq("path", `courses/${r.course}`).maybeSingle();
  const par: number[] = cd?.data?.par || PAR[r.course] || PAR.old;
  const { data: es } = await sb.from("docs").select("data").like("path", `rounds/${rid}/entries/%`);
  const entries = (es || []).map((x) => x.data);

  // Samme regel som appen: hullet tæller, når alle der har tastet det, har tastet det samme.
  const found: { rid: string; pid: string; hole: number; score: number; d: number }[] = [];
  for (const pid of r.players || []) {
    const fl = r.flights?.[pid];
    // Markører: de to første i bolden, der har meldt sig og ikke er meldt ude (Skift markør). Kun deres tal tæller (som i appen).
    const cand = entries.filter((e) => e.flight === fl && e.marker);
    const out = new Set<string>();
    cand.forEach((e) => (e.drop || []).forEach((p: string) => { if (p !== e.by) out.add(p); }));
    const mk = cand.filter((e) => !out.has(e.by))
      .sort((a, b) => (a.markerAt || 0) - (b.markerAt || 0)).slice(0, 2).map((e) => e.by);
    const mine = entries.filter((e) => e.flight === fl && e.scores && e.scores[pid] && (!mk.length || mk.includes(e.by)));
    for (let h = 0; h < 18; h++) {
      const vals = mine.map((e) => Number(e.scores[pid][h])).filter((v) => v > 0);
      if (!vals.length || !vals.every((v) => v === vals[0])) continue;
      const d = vals[0] - par[h];
      if (d <= -1) found.push({ rid, pid, hole: h + 1, score: vals[0], d });
    }
  }
  if (!found.length) return json({ ok: true, sent: 0 });

  // Kun dem der ikke er sendt før (to markører = stadig én besked)
  const { data: fresh, error } = await sb.from("birdie_sent")
    .upsert(found.map(({ d: _d, ...f }) => f), { onConflict: "rid,pid,hole", ignoreDuplicates: true })
    .select("pid,hole,score");
  if (error) return json({ error: error.message }, 500);
  if (!fresh?.length) return json({ ok: true, sent: 0 });

  const { data: subs } = await sb.from("push_subs").select("endpoint,pid,sub");
  const { data: ps } = await sb.from("docs").select("path,data").in("path", fresh.map((f) => `players/${f.pid}`));
  const name = (pid: string) => ps?.find((p) => p.path === `players/${pid}`)?.data?.name || "En spiller";
  webpush.setVapidDetails(SITE, k.public_key, k.private_key);

  let sent = 0;
  for (const f of fresh) {
    const d = f.score - par[f.hole - 1];
    const icon = f.score === 1 ? "🎯" : d <= -2 ? "🦅" : "🐦";
    const payload = JSON.stringify({
      title: "Tirsdagsklubben",
      body: `${icon} ${name(f.pid)} har lavet ${word(f.score, d)} på hul ${f.hole}`,
      tag: `${rid}-${f.pid}-${f.hole}`,
    });
    // Man får ikke besked om sin egen birdie
    await Promise.all((subs || []).filter((s) => s.pid !== f.pid).map(async (s) => {
      try {
        await webpush.sendNotification(s.sub, payload, { TTL: 3600, urgency: "high" });
        sent++;
      } catch (e) {
        const code = (e as { statusCode?: number }).statusCode;
        if (code === 404 || code === 410) await sb.from("push_subs").delete().eq("endpoint", s.endpoint);
        else console.error("push fejl", code, (e as Error).message);
      }
    }));
  }
  return json({ ok: true, birdies: fresh.length, sent });
});
