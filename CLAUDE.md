# Spotify Dashboard

Local web dashboard + native macOS wrapper that shows which of your playlists contain the currently playing Spotify track, with one-click add/remove.

## Stack & entry points

- **Backend**: Flask (`app.py`), port **8888**, Spotify via `spotipy`. Run: `.venv/bin/python app.py` (system `python3` lacks the deps).
- **Frontend**: vanilla JS — `static/script.js` + `playlists.html` / `tracker.html` / `queue.html` + `styles.css`. No build step; served with no-cache headers.
- **Desktop app**: `desktop/SpotifyDashboard/` (Swift, no Xcode project). Build: `desktop/SpotifyDashboard/build.sh` → installs to `/Applications/Spotify Dashboard.app`. Launch: `desktop/run.sh`.

## Architecture

- `config.json` (gitignored; see `config.example.json`) defines the pages and their playlists; the playlist editor UI writes back to it live.
- Backend caches every playlist's track URIs in background threads at startup (2s/playlist — warm-up takes a couple of minutes; endpoints report it via the `X-Loading-State` header).
- The native app finds `app.py` via `SPOTIFY_DASHBOARD_PATH` env, a saved bookmark, or scanning (rename-proof) — **it always runs the MAIN checkout**, so worktree changes only reach the running app after merging to `main` and restarting the app.
- `/api/open-in-spotify` POSTs run `open spotify:playlist:<id>` locally to open the Spotify desktop app.

## Gotchas

- Secrets/config at repo root: `.env`, `.cache` (Spotify token), `config.json` — all gitignored; never commit or `git add -A`.
- Spotify refresh tokens expire ~6 months (2026-07-20 policy); 401s redirect the UI to `/login`, and `is_authenticated()` clears dead tokens.
- Frontend edits only need a browser/page reload (no-cache headers); `app.py` edits need a backend restart (quit + reopen the app).
- The NAGA NEXT SHOW tiles get a special holographic treatment (`isSpecialPlaylist` in `script.js`) — keep it in any restyle.
- Grid keyboard shortcuts (N/E/S defaults, plus THEME on ⌘⇧L) are stored in `localStorage` (`gridShortcuts.v1`); the native layer swallows only the sidebar shortcut (default ⌘S).
- Dual theme: dark default + "Daybreak" light (`localStorage` `dashTheme`, `body.theme-light`). All colors flow from the token sheet at the top of `styles.css` — never hardcode a surface color outside it; light overrides live in the `body.theme-light` blocks.
- Tracker/Queue divider entries accept an optional `"label"` in `config.json` — labeled dividers render their section as a vertical rail; unlabeled ones stay plain separator lines.
