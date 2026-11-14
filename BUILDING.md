# Mockfy desktop (Windows and Mac)

An Electron window on https://mockfy.uz. The site itself is the app, so new features reach the desktop
app without a new installer. Only change and rebuild this when the window itself changes.

## How sign-in works
Google does not allow sign-in inside an app's own window, so the app signs in through the browser:
the app opens `/auth/desktop/start` in the browser → the learner signs in as usual →
`/auth/desktop/done` opens `mockfy://auth?code=...` → the app loads `/auth/desktop/claim?code=...`,
which starts the session in the app. Codes work once, for 2 minutes (`desktop.py`).

## Run locally
```
cd desktop
npm install
npm start                                   # opens mockfy.uz
set MOCKFY_URL=http://localhost:5000 && npm start   # against the local server (Windows cmd)
```

## Build
- Windows (on Windows): `npm run dist:win` → `dist/Mockfy-Setup.exe`
- Mac (on a Mac): `npm run dist:mac` → `dist/Mockfy.dmg`

## Publishing the installers
The main repository is private, so its releases cannot be downloaded by visitors. The installers live in a
small **public** repository, `mockfy-download`, that holds only this folder (nothing secret: it just opens
mockfy.uz):

1. Create the public repository `mockfy-download` on GitHub (empty).
2. Copy this folder's contents into it (with `.github/workflows/build.yml`) and push.
3. Tag a version: `git tag v1.0.0 && git push --tags`. GitHub Actions builds `Mockfy-Setup.exe` (Windows)
   and `Mockfy.dmg` (Mac) and attaches them to the release.

The /download page links to `https://github.com/<owner>/mockfy-download/releases/latest/download/Mockfy-Setup.exe`
and `.../Mockfy.dmg` (fixed names, so the newest release is always the one downloaded). To host them
somewhere else, set `DESKTOP_WIN_URL`, `DESKTOP_MAC_URL` (and `DESKTOP_VERSION`) on Render.

## Unsigned builds
The installers are not code-signed (that needs a paid Windows certificate and an Apple Developer account).
Windows SmartScreen shows "Windows protected your PC" → More info → Run anyway; macOS asks to open it with
right-click → Open. The /download page says so. With certificates, add them as GitHub secrets
(`CSC_LINK`, `CSC_KEY_PASSWORD`, and for Mac `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`).
