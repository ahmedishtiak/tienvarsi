# Tienvarsi

A community map for drivers in Finland: fuel prices, EV charging, free and cheap parking, car washes and drive-throughs. English, Finnish and Swedish. One HTML file, free map and data services, and a free Supabase database for the reports people send.

## Files

| File | What it is |
|---|---|
| `index.html` | The whole site. |
| `supabase-setup.sql` | Creates the database tables and rules. Run once in Supabase. |
| `README.md` | This guide. |

## 1. Put the site online (GitHub Pages)

1. Create a new public repository on GitHub, for example `tienvarsi`.
2. Upload the three files.
3. Go to **Settings > Pages**, choose **Deploy from a branch**, branch `main`, folder `/ (root)`, and save.
4. After a minute or two the site is live at `https://<your-username>.github.io/tienvarsi/`.

Until you connect the database, the site runs in **demo mode**: reports are saved only in the browser that sent them. A note on the site says so.

## 2. Connect the database (Supabase, free plan)

1. Sign in at [supabase.com](https://supabase.com) and create a new project. Pick an EU region close to Finland.
2. Open **SQL Editor**, start a new query, paste all of `supabase-setup.sql` and click **Run**.
3. In the project's API settings, copy the **Project URL** and the **publishable key** (starts with `sb_publishable_`). The older `anon` key also works. Never use the secret key or `service_role` key in the site.
4. Open `index.html`, find `const CONFIG` near the top of the script, and paste them:

   ```js
   SUPABASE_URL: 'https://abcdefgh.supabase.co',
   SUPABASE_KEY: 'sb_publishable_...',
   ```

5. Commit the change. Reports are now shared by everyone who uses the site.

## What the database allows

- Anyone can read reports and add new ones. Nobody can edit or delete from the site.
- Each browser can send at most 6 reports in 10 minutes.
- Prices outside sensible ranges are rejected (fuel 0.50 to 4.50 €/l, charging up to 2 €/kWh, parking up to 30 €/h, washes up to 300 €).
- Only coordinates inside Finland are accepted. Offer links must start with `https://`.
- One vote per report per browser. A report with two more "Wrong" votes than "Still right" votes stops counting on the map.

To remove a bad report, open **Table Editor > reports** in Supabase and delete the row.

## Where the data comes from

- **Places** (stations, chargers, parking, washes, fast food): OpenStreetMap through the Overpass API. Missing or wrong places are best fixed in OpenStreetMap itself; every place page links there.
- **Helsinki street parking** (free, disc, paid zones): City of Helsinki open data, CC BY 4.0. Loads when you zoom in to street level in Helsinki.
- **Map**: OpenFreeMap vector tiles, recoloured in the page. If a browser can't show vector maps, the site falls back to standard OpenStreetMap tiles.
- **Address search**: Nominatim. The site searches only when you press Enter, which keeps within its usage policy.
- **Fuel and charging prices**: only from reports on this site. Tankille and similar apps have no public data feed, so nothing is copied from them.
- **Chain offers**: checked by hand against each company's own site on 12 Oct 2026. They live in `const SEED` in `index.html`; edit the text and the `checked` date when deals change.

## Good to know

- **Teboil** closed its Finnish stations in November 2025, and St1 began rebranding Finland's **Shell** stations as St1 in 2025. OpenStreetMap may still list old names, so the site shows a notice on those stations.
- Free Supabase projects pause after about a week with no activity. If reports stop saving, open the Supabase dashboard and restore the project.
- The public map and search services are free and shared. If the site becomes popular, consider your own tile hosting or a paid tile plan.
- Shared links keep the view: the address bar holds the category, zoom and position, for example `#parking/16/60.17150/24.93800`.
