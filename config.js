// ------------------------------------------------------------
// Rename this file to config.js and fill in your own values.
// You get these from your Supabase project:
//   Dashboard → Project Settings → API
//     - "Project URL"        -> SUPABASE_URL
//     - "anon public" key    -> SUPABASE_ANON_KEY
//
// The anon key is SAFE to put in client-side code / a public repo —
// it's meant to be public. Access is actually controlled by the
// Row Level Security policies in schema.sql, not by hiding this key.
// ------------------------------------------------------------

window.CART_CORRAL_CONFIG = {
  SUPABASE_URL: "https://sdfhbiykcovfqmigdwsv.supabase.co/rest/v1/",
  SUPABASE_ANON_KEY: "sb_publishable_zOqV85kvzDslAQ7oyO99pQ_P5Iw3kB1",

  // Optional: if the logged-in user's email matches this, they'll
  // see an "Export CSV" button in the app header. This is a
  // convenience toggle for you, NOT real security — see README.md
  // for why (any logged-in user can technically read the same data,
  // since the map itself has to be readable to work at all).
  ADMIN_EMAIL: "jamie.cutts@cuttspm.com"
};
