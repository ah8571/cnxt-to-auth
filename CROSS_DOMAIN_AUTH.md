# Cross-Domain Auth Architecture

How a single sign-in on any `*.cnxt.to` tool propagates to all others.

---

## The Problem

Supabase stores sessions in `localStorage`, which is **per-domain**. Signing in on `auth.cnxt.to` creates a session there, but `invoices.cnxt.to` can't see it. Users have to sign in separately on every tool.

## The Solution

A shared cookie on `.cnxt.to` bridges the gap. When a user signs in anywhere, the access token is stored in a cookie visible to all subdomains. Each tool checks this cookie on load and restores the session into its own `localStorage`.

## Flow

```
User signs in on auth.cnxt.to (or any tool with auth)
       │
       ▼
Supabase stores session in localStorage (per-domain, as usual)
       +
cnxt-auth.js sets "cnxt_session" cookie on .cnxt.to
  → document.cookie = "cnxt_session=<token>;domain=.cnxt.to;path=/;SameSite=Lax"
       │
       ▼
User navigates to invoices.cnxt.to / links.cnxt.to / post.cnxt.to
       │
       ▼
That tool's copy of cnxt-auth.js runs on page load:
  1. Reads "cnxt_session" cookie
  2. Calls supabase.auth.setSession() to restore into localStorage
  3. All existing Supabase.auth calls now work normally
       │
       ▼
User is signed in everywhere — one login, all tools
```

## Sign Out Flow

```
User clicks "Sign out" on any tool
       │
       ▼
clearSharedSession() is called:
  1. supabase.auth.signOut() — clears localStorage session
  2. deleteCookie("cnxt_session") — removes the .cnxt.to cookie
       │
       ▼
All other tools on next page load: no cookie found → signed out
```

---

## Shared Utility: `cnxt-auth.js`

Location: `js/cnxt-auth.js` in each project's repo.

Self-contained — no external dependencies except Supabase JS SDK (loaded dynamically from esm.sh). Three exports:

| Export | Purpose |
|---|---|
| `getSharedSession()` | Check cookie, restore into localStorage, return `{ user, accessToken }` or `null` |
| `setSharedSession()` | Read Supabase session from localStorage, persist to `.cnxt.to` cookie |
| `clearSharedSession()` | Sign out from Supabase + delete the `.cnxt.to` cookie |

### Integration pattern for new tools

#### 1. Copy the utility

```bash
cp cnxt-to-auth/js/cnxt-auth.js <new-project>/js/cnxt-auth.js
```

#### 2. On page load — restore session

```js
import { getSharedSession } from "./cnxt-auth.js";

// Run early, before any API calls that need auth
const session = await getSharedSession();
if (session) {
  // User is signed in — use session.accessToken for API calls
  // Supabase localStorage is also populated, so existing supabase-js code works
}
```

#### 3. After sign-in — persist to cookie

```js
import { setSharedSession } from "./cnxt-auth.js";

// After successful supabase.auth.signInWithPassword() or similar
await setSharedSession();
```

#### 4. On sign-out — clear everywhere

```js
import { clearSharedSession } from "./cnxt-auth.js";

// In sign-out handler
await clearSharedSession();
```

---

## Per-Project Integration Summary

| Project | File(s) | Integration |
|---|---|---|
| **auth.cnxt.to** | `js/auth.js` | `setSharedSession()` after sign-in, sign-up, and existing session check |
| **invoices.cnxt.to** | `js/app.js`, `js/auth.js` | `getSharedSession()` on app load; `setSharedSession()` in auth flow; `clearSharedSession()` on sign-out |
| **links.cnxt.to** | `dashboard/js/app.js` | `getSharedSession()` on load → uses Supabase token as `sessionToken` for Worker API; `clearSharedSession()` on logout |
| **post.cnxt.to** | `dashboard/js/dashboard.js` | `getSharedSession()` in `refreshAuth()`; `clearSharedSession()` on sign-out |

---

## Cookie Details

| Property | Value |
|---|---|
| Name | `cnxt_session` |
| Domain | `.cnxt.to` (leading dot = all subdomains) |
| Path | `/` |
| SameSite | `Lax` (allows redirects from auth page) |
| Max Age | 30 days |
| Content | Supabase access token (JWT) |

---

## Supabase Project

All tools share one Supabase project:

- **URL:** `https://jstojewashwoswsskwjk.supabase.co`
- **Auth:** Email + password (with optional email confirmation)
- **JWT Secret:** Used by Workers for server-side validation

---

## Adding a New Tool (checklist)

1. Create the project in its own repo
2. Copy `cnxt-auth.js` into the project's `js/` folder
3. Deploy to `<tool>.cnxt.to` on Cloudflare Pages
4. Add CORS origin to any Worker API that needs it
5. Submit `sitemap.xml` to Google Search Console as a new URL-prefix property
6. Add a "Sign in" link pointing to `https://auth.cnxt.to/?redirect=https://<tool>.cnxt.to/`
