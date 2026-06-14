# NaiveClient

Menu bar client for [NaiveProxy](https://github.com/klzgrad/naiveproxy) on macOS.

Paste a `naive://` link, click **Connect**, and macOS routes traffic through local SOCKS `127.0.0.1:1080`.

## Download and install (recommended)

1. Open [Releases](https://github.com/YOUR_USERNAME/vpn_client/releases).
2. Download the DMG for your Mac:
   - **Apple Silicon (M1/M2/M3/M4):** `NaiveClient-x.x.x-macOS-arm64.dmg`
   - **Intel Mac:** `NaiveClient-x.x.x-macOS-x86_64.dmg`
3. Open the DMG and drag **NaiveClient** to **Applications**.
4. Launch **NaiveClient** from **Applications** (not from inside the DMG).
5. If macOS blocks the app:
   - Right-click the app → **Open** → **Open** again, or
   - Run in Terminal:
     ```bash
     xattr -cr /Applications/NaiveClient.app
     ```

No Xcode or Homebrew is required for end users.

### App opens but nothing appears?

NaiveClient shows **an icon in the Dock** and **in the menu bar** (top-right). On launch it also **opens the control panel automatically**.

1. Look for **NaiveClient** in the Dock, or the **network icon** in the menu bar.
2. Click either one to open Import / Connect.

If nothing happens:

```bash
pkill NaiveClient
xattr -cr /Applications/NaiveClient.app
open /Applications/NaiveClient.app
```

Run from Terminal to see crash output:

```bash
/Applications/NaiveClient.app/Contents/MacOS/NaiveClient
```

## Usage

1. Click the menu bar icon (network icon in the top bar).
2. Paste your link, for example:
   ```
   naive://user:password@example.com:8443#my-server
   ```
3. Click **Import**.
4. Click **Connect**.

When connected, macOS system proxy is enabled for active network interfaces (Wi‑Fi / Ethernet).

Click **Disconnect** before quitting if you want to restore direct internet access immediately. The app also disables proxy on exit.

## Supported URL formats

| Format | Example |
|--------|---------|
| Simple | `naive://user:pass@host:8443#name` |
| HTTPS | `naive+https://user:pass@host:443#name` |
| QUIC | `naive+quic://user:pass@host:443#name` |

Password special characters must be URL-encoded (`!` → `%21`).

## Publish a release on GitHub

Push a version tag — GitHub Actions builds DMG files automatically:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Workflow: `.github/workflows/release.yml`

Artifacts:
- `NaiveClient-1.0.0-macOS-arm64.dmg`
- `NaiveClient-1.0.0-macOS-x86_64.dmg`

You can also run the workflow manually from the **Actions** tab.

## Build locally on Mac

Requirements: macOS 13+, Xcode 15+

```bash
git clone https://github.com/YOUR_USERNAME/vpn_client.git
cd vpn_client
chmod +x scripts/*.sh
bash scripts/build-dmg.sh
```

Output: `dist/NaiveClient-1.0.0-macOS-<arch>.dmg`

To pin a specific naiveproxy core version:

```bash
NAIVE_VERSION=v149.0.7827.114-1 bash scripts/build-dmg.sh
```

## Project layout

```
NaiveClient/          SwiftUI menu bar app
scripts/
  download-naive.sh   Downloads naive core from GitHub releases
  build-dmg.sh        Builds signed .app and packages .dmg
.github/workflows/    CI release pipeline
```

## How it works

```
naive:// URL  →  config.json  →  naive process  →  SOCKS :1080  →  system proxy
```

This is the same model as v2rayN with NaiveProxy on Windows: local SOCKS proxy + system proxy, not a kernel TUN VPN.

## Security notes

- Profile credentials are stored in macOS UserDefaults on your Mac.
- Do not commit real server URLs or passwords to the repository.
- Rotate server password if it was shared in chat or issue trackers.

## License

MIT
