// Tirsdagsklubben: sender en kalenderfil tilbage, så telefonen tilbyder "Føj til kalender".
// Appen laver selve .ics-teksten og sender den base64url-kodet i ?d=. Intet gemmes.
Deno.serve((req: Request) => {
  const u = new URL(req.url);
  const d = u.searchParams.get("d") || "";
  let txt = "";
  try {
    const b64 = d.replace(/-/g, "+").replace(/_/g, "/");
    txt = new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)));
  } catch (_) { /* ugyldig */ }
  if (!txt.startsWith("BEGIN:VCALENDAR") || !txt.trimEnd().endsWith("END:VCALENDAR") || txt.length > 6000 || /<|>/.test(txt)) {
    return new Response("Ugyldig kalenderfil", { status: 400, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  }
  const name = (u.searchParams.get("n") || "tirsdagsklubben").replace(/[^A-Za-z0-9_-]/g, "").slice(0, 60) || "tirsdagsklubben";
  return new Response(txt, {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": `inline; filename="${name}.ics"`,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
});
