# Cart Corral — setup guide

A mobile-first, installable web app for reporting stray Target shopping carts
around town. Real accounts, GPS-verified confirmations, leaderboard, and a
CSV export for you. Independent/unofficial — not affiliated with Target.

This is a **static front end + Supabase backend**. There's no server to run —
you create a free Supabase project (handles login + database), fill in two
values, and put the files on any static host (GitHub Pages works great,
same as your other tools).

---

## 1. Create the Supabase project

1. Go to https://supabase.com → sign up / log in → **New project**.
2. Pick any name/region, set a database password (save it somewhere — you
   likely won't need it again, but keep it).
3. Wait ~2 minutes for it to finish provisioning.

## 2. Run the database schema

1. In your new project, open **SQL Editor** (left sidebar) → **New query**.
2. Open `schema.sql` from this folder, copy the whole thing, paste it in.
3. Click **Run**. You should see "Success. No rows returned."
   - This creates the `profiles`, `sightings`, and `flags` tables, turns on
     Row Level Security, and creates the `submit_sighting` /
     `flag_sighting` functions the app calls.
   - If it errors on `create extension`, your project may already have it —
     that's fine, ignore that specific error and re-run; the rest still works.

## 3. Turn on email login

1. Left sidebar → **Authentication** → **Providers**.
2. Make sure **Email** is enabled (it is by default).
3. Optional but recommended: **Authentication** → **Settings** → turn OFF
   "Confirm email" if you want people to be able to sign up and use the app
   immediately without clicking a confirmation link first. Leave it ON if
   you'd rather verify real emails.

## 4. Get your API keys

1. Left sidebar → **Project Settings** → **API**.
2. Copy the **Project URL**.
3. Copy the **anon public** key (NOT the `service_role` key — never put that
   one in client-side code).

## 5. Configure the app

1. In this folder, copy `config.sample.js` to a new file named `config.js`.
2. Paste in your Project URL and anon key.
3. (Optional) Set `ADMIN_EMAIL` to the email you'll sign up with — that
   account will see an "Export CSV" button in the app header. See the
   security note below about what this button does and doesn't protect.

## 6. Deploy the files

Upload everything in this folder to a static host:
- `index.html`
- `terms.html`
- `config.js` (the one you just created — **not** `config.sample.js`)
- `manifest.json`
- `sw.js`
- `icons/` folder

**GitHub Pages** (same pattern as your other tools): create a repo, push
these files to it, turn on Pages for the repo pointing at the root (or a
`/docs` folder), done. Any static host works too (Netlify, Cloudflare Pages,
even just your own web server) — nothing here needs a Node server.

## 7. Try it

Open the deployed URL on your phone. Sign up, allow location access when
prompted, tap the ⊕ button to drop a test pin. Tap the "📲 Add to home
screen" hint for install steps.

---

## How the anti-gaming logic works

- Reporting near an **existing** unconfirmed pin (within ~30 ft) confirms it
  instead of creating a duplicate — this is the core dedupe + confirm
  mechanic, and it's the same action (`submit_sighting`) either way.
- A pin earns **zero points** until a second, different account confirms it.
- You can't confirm your own pin — reporting near your own existing pin is a
  no-op.
- The confirmer's GPS location has to actually be within range at the
  moment they submit, since the distance check runs server-side in
  `submit_sighting()` using their real current coordinates — there's no
  "confirm from your couch" button.
- Any user can flag a pin; 3 unique flags auto-hides it from the map.

This is all enforced in the database (`schema.sql`), not just in the app's
JavaScript — so it holds even if someone opens dev tools and pokes at the
Supabase API directly.

## Honest limitations, so nothing surprises you later

- **No photo verification.** Whether a cart is actually Target's is on the
  honor system, same as whether it's still there. The flagging system is
  the backstop.
- **The CSV export button isn't real security.** It's just hidden from
  everyone except the `ADMIN_EMAIL` account in the app's UI. Because the
  map has to be readable by any logged-in user for the app to work at all,
  a technically savvy user could query the same data directly from
  Supabase's API with their own login. If you need to keep the underlying
  data genuinely private to only you, that requires a server-side
  export/API layer instead of a fully static site — happy to build that
  next if it matters to you.
- **Confirming requires a second real person nearby.** In a low-traffic
  town this means pins may sit "unconfirmed" (and worth 0 points) for a
  while until someone else walks by and reports the same spot. That's
  intentional — it's the tradeoff for making the points hard to fake.
- **Terms & Privacy Notice** (`terms.html`) is plain-language, not
  lawyer-reviewed. It's honest about the fact that location data may be
  shared with retailers like Target to help recover carts — that's stated
  up front and users check a box agreeing to it at signup, rather than it
  being hidden.

## Restoring a wrongly-hidden pin

If a pin gets auto-hidden by 3 flags and shouldn't have been: Supabase
dashboard → **Table Editor** → `sightings` table → find the row → change
`status` back to `unconfirmed` or `verified`. There's no in-app admin panel
for this yet — it's a two-click manual fix for now.
