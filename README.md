# Afya Nyumbani PWA — Setup Guide

**What you get:** A Progressive Web App that installs on any Android phone from a browser. Works offline. Submits outbreak signals. Syncs to Postgres via PowerSync. CHA verification tasks auto-created by a database trigger.

**Cost:** Free. No credit card. Three services:
| Service | What it does | Free tier |
|---|---|---|
| **Supabase** | Hosted Postgres database | 500MB, no credit card |
| **PowerSync Cloud** | Postgres → SQLite sync engine | Free tier, no credit card |
| **Vercel** | Hosts the PWA | Unlimited static sites |

**Time to complete:** 15–20 minutes.

---

## Step 1 — Supabase (hosted Postgres)

### 1a. Create account and project
1. Go to **[supabase.com](https://supabase.com)** → Sign Up (GitHub or email)
2. Click **New project**
3. Name it `afya-nyumbani-poc`
4. Choose a region — **Europe (Frankfurt)** or **US East** both work fine
5. Set a database password — save it, you'll need it for PowerSync
6. Click **Create new project** — takes about 60 seconds

### 1b. Run the setup SQL
1. In your project dashboard, click **SQL Editor** (left sidebar)
2. Click **New query**
3. Open the file `supabase-setup.sql` from this folder
4. Paste the entire contents into the editor
5. Click **Run** (or Ctrl+Enter)
6. You should see at the bottom:
   ```
   status          | chp_areas | forms_loaded
   Setup complete ✓ | 3         | 1
   ```

That created all the tables, the signal→task trigger, seeded 3 CHP areas, and loaded the CEBS signal form schema.

### 1c. Create test users
1. In Supabase dashboard → **Authentication** → **Users** → **Add user**
2. Create these users (Invite user → set email + password):

| Email | Password | Role |
|---|---|---|
| wanjiku@kiharu.test | Test1234! | chp |
| grace@kiharu.test | Test1234! | cha |

3. After creating each user, go to **SQL Editor** and run:
```sql
-- After creating wanjiku (replace the UUID with the actual one shown in Auth → Users)
insert into profiles (id, username, role, chp_area_id, display_name)
values (
  'PASTE_WANJIKU_UUID_HERE',
  'wanjiku',
  'chp',
  'd0000001-0000-0000-0000-000000000001',  -- Zone A
  'Wanjiku Kamau'
);

-- After creating grace
insert into profiles (id, username, role, display_name)
values (
  'PASTE_GRACE_UUID_HERE',
  'grace',
  'cha',
  'Grace Mwangi'
);
```

### 1d. Get your Supabase credentials
1. In your project → **Settings** → **API**
2. Copy:
   - **Project URL** → this is your `SUPABASE_URL`
   - **anon / public** key → this is your `SUPABASE_ANON_KEY`
3. Also go to **Settings** → **Database** → copy the **Connection string** (URI format) — needed for PowerSync

---

## Step 2 — PowerSync Cloud (sync engine)

### 2a. Create account and project
1. Go to **[powersync.com](https://powersync.com)** → Sign Up (free, no credit card)
2. Click **New project** → name it `afya-nyumbani`
3. Click **Create instance** → choose the free tier

### 2b. Connect to your Supabase database
1. In your PowerSync project → **Database Connections** → **Connect to Source Database**
2. Select **Postgres** tab
3. Paste the Supabase connection URI (from Step 1d)
   - It looks like: `postgresql://postgres:[YOUR-PASSWORD]@db.xxxx.supabase.co:5432/postgres`
   - Replace `[YOUR-PASSWORD]` with your actual database password from Step 1a
4. Click **Test connection** — should show green ✓
5. Click **Save**

### 2c. Configure sync rules
1. In your PowerSync instance → **Sync Rules**
2. Delete the default content
3. Open `powersync-rules.yaml` from this folder
4. Paste the contents into the editor
5. Click **Save & Deploy** — takes about 10 seconds

### 2d. Get your PowerSync URL
1. In your PowerSync instance → **Overview**
2. Copy the **Instance URL** — looks like:
   `https://xxxxxxxxxxxxxxxx.powersync.journeyapps.com`

---

## Step 3 — Deploy to Vercel

### 3a. Put the files on GitHub
1. Go to **[github.com](https://github.com)** → New repository
2. Name it `afya-nyumbani-pwa` → Public → Create
3. Upload all the files from the `afya-pwa` folder:
   - `index.html`
   - `vercel.json`
   - `public/` (folder with `manifest.json`, `sw.js`, `config.js`, `icons/`)

   Easiest way: drag and drop files into the GitHub repository page.

### 3b. Edit config.js with your credentials
Before uploading (or edit on GitHub after):

Open `public/config.js` and replace the three placeholder values:
```javascript
window.__CONFIG__ = {
  SUPABASE_URL:  'https://xxxxxxxxxxxx.supabase.co',
  SUPABASE_ANON: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
  POWERSYNC_URL: 'https://xxxxxxxxxxxx.powersync.journeyapps.com',
};
```

### 3c. Deploy on Vercel
1. Go to **[vercel.com](https://vercel.com)** → Sign up with GitHub (free)
2. Click **Add New Project** → Import your `afya-nyumbani-pwa` repository
3. **Framework Preset**: select `Other` (no framework)
4. **Root Directory**: leave as `/` (default)
5. **Build Command**: leave empty
6. **Output Directory**: leave as `public` — wait, actually set it to blank/default
7. Click **Deploy**

Vercel will deploy in about 30 seconds. You'll get a URL like:
`https://afya-nyumbani-pwa-xxxx.vercel.app`

> **Important:** Vercel automatically applies the headers in `vercel.json`
> (COOP/COEP). These are required for PowerSync's SharedArrayBuffer.
> Without them, the sync will not work. The `vercel.json` file handles this automatically.

---

## Step 4 — Install on your Android phone

1. Open Chrome on your Android phone
2. Navigate to your Vercel URL
3. Sign in with `wanjiku@kiharu.test` / `Test1234!`
4. Once the app loads, Chrome will show a banner: **"Add Afya Nyumbani to Home screen"**
   - If the banner doesn't appear: tap the **⋮ menu** → **Add to Home screen**
5. Tap **Add** — the app icon appears on your home screen
6. Open from the home screen — it now runs like a native app, full screen, no browser bar

---

## Step 5 — Test the full sync loop

### Test 1: Submit a signal online
1. Open the app → sign in as Wanjiku
2. Tap **Report** (bottom tab)
3. Select **Suspected outbreak (fever + bleeding)**
4. Fill in the date, number of people (e.g. 3), location ("Kiharu village near school")
5. In the Outbreak Details section: Fever = Yes, Bleeding = Vomiting blood
6. Tap **Submit signal**
7. You should see the success screen: "Signal submitted"

**Verify in Supabase:**
- Go to Supabase → **Table Editor** → `events`
- You should see your signal row
- Go to `tasks` — you should see an **URGENT: Verify outbreak signal** row
  created automatically by the database trigger

### Test 2: Submit offline
1. On your phone → turn on **Airplane mode**
2. Open the app (it should load from cache)
3. Submit a signal — it should work exactly the same
4. Turn Airplane mode off
5. Within 60 seconds, the signal appears in Supabase `events` table
6. The CHA verification task is created automatically

### Test 3: CHA sees the task
1. In a second browser tab (or incognito), sign in as `grace@kiharu.test`
2. The Home screen should show the pending task in the **My pending tasks** section
3. If it's not there yet, wait 30 seconds for PowerSync to sync

---

## What each file does

```
afya-pwa/
├── index.html              The entire PWA — UI, form engine, sync logic
├── vercel.json             COOP/COEP headers (required for PowerSync)
├── supabase-setup.sql      Run once in Supabase SQL Editor
├── powersync-rules.yaml    Paste into PowerSync Dashboard → Sync Rules
├── public/
│   ├── config.js           ← EDIT THIS with your credentials
│   ├── manifest.json       Makes it installable as a PWA
│   ├── sw.js               Service worker — offline caching
│   └── icons/              App icons (192px and 512px)
```

---

## What this proves

| What you see | What it proves |
|---|---|
| Form works with Airplane mode on | SQLite-first write — no network dependency |
| Signal appears in Supabase after reconnect | PowerSync upload path working |
| Task row auto-created in `tasks` table | Postgres trigger = the "missing middle" |
| App loads from home screen with no browser bar | Installed PWA behaviour |
| CHA sees task in their home screen | PowerSync sync-down path working |

---

## Troubleshooting

**"Demo mode" banner on login screen**
→ `config.js` still has placeholder values. Edit it and redeploy.

**Sync not working (dot stays orange)**
→ Check that `vercel.json` is in the root of your repo (not inside `public/`)
→ The COOP/COEP headers are required for PowerSync's SharedArrayBuffer

**"Cannot read properties of undefined" in console**
→ The Supabase credentials in `config.js` are wrong. Double-check the URL and anon key.

**Tasks not appearing after signal submission**
→ Check Supabase → SQL Editor → run: `SELECT * FROM tasks ORDER BY created_at DESC LIMIT 5;`
→ If no tasks: check the trigger exists: `SELECT routine_name FROM information_schema.routines WHERE routine_name = 'create_signal_task';`
→ If trigger missing: re-run `supabase-setup.sql`

**PowerSync "Connection refused"**
→ In PowerSync Dashboard → Database Connections → verify the test shows green
→ Check the Supabase connection string includes your actual password (not `[YOUR-PASSWORD]`)
