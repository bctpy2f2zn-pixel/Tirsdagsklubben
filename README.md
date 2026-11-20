# Tirsdagsklubben

Web-app til tirsdagsgolf: live leaderboard, scoreindtastning (2 pr. bold), tilmelding, bolde og sæsonstilling.

- `index.html` er hele appen. `config.js` peger på Supabase-projektet.
- `supabase/schema.sql` opretter tabellen og adgangsreglerne.
- Login: DGU-nummer + adgangskode (første gang fødselsdato DDMMÅÅ).
- Birdie-beskeder: `supabase/push.sql` (tabeller + trigger) og `supabase/functions/birdie-push` (sender push). `sw.js` viser beskeden på telefonen. På iPhone skal appen ligge på hjemmeskærmen.
