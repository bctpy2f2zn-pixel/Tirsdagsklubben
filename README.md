# Tirsdagsklubben

Web-app til tirsdagsgolf: live leaderboard, scoreindtastning (2 pr. bold), tilmelding, bolde og sæsonstilling.

- `index.html` er hele appen. `config.js` peger på Supabase-projektet.
- `supabase/schema.sql` opretter tabellen og adgangsreglerne.
- Login: DGU-nummer + adgangskode (første gang fødselsdato DDMMÅÅ).
