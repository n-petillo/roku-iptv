# IPTV Live (Roku)

Simple Roku live-TV player for Xtream Codes accounts. Sign in once, then browse in three panels:
**categories | channels | preview + EPG** (now / next).

---

## Install on a TV

You do this once per Roku. It takes about 5 minutes and you need a computer or phone on the same Wi-Fi as the TV.

### 1. Enable Developer Mode on the Roku

1. On the Roku remote press, in order:
   **Home ×3, Up ×2, Right, Left, Right, Left, Right**
2. A *Developer Settings* screen appears. Note the IP address shown (e.g. `http://192.168.1.50`).
3. Select **Enable installer and restart**, accept the license.
4. Choose a **web server password**; you'll need it in step 3. The username is always `rokudev`.
5. The Roku restarts.

> Lost the IP later? Roku **Settings → Network → About**.

### 2. Download the app

Go to this repo's **[Releases](../../releases/latest)** page and download **`iptv-live.zip`**.
Don't unzip it.

### 3. Upload it to the TV

1. In a browser on the same network, open the Roku's IP: `http://192.168.1.50`
2. Log in with username **`rokudev`** and the password from step 1.
3. Click **Upload**, pick `iptv-live.zip`, then click **Install with zip**.
4. The app launches on the TV. It now also appears on the Roku home screen as **IPTV Live**.

### 4. Sign in

Enter your **Server URL** (e.g. `http://provider.example:8080`), **Username** and **Password**,
then select **Sign in**. They're saved on that TV, so next time it opens straight to Live TV.

### Updating

Download the newer `iptv-live.zip` from Releases and repeat **step 3**. Your login is kept.

### Good to know

- A Roku can only have **one** developer (sideloaded) app at a time.
- The app survives restarts, but a **factory reset** or disabling Developer Mode removes it, so just install it again.
- Your server login is stored only on the TV, never in this repo.

---

## Remote controls

| Where       | Key        | Action                                  |
|-------------|------------|-----------------------------------------|
| Login       | OK         | Edit field / Sign in                    |
| Panels      | Up/Down    | Move in list                            |
| Panels      | Left/Right | Switch between Categories and Channels  |
| Channels    | OK         | Play in preview; OK again = fullscreen  |
| Panels      | `*`        | Log out / change account                |
| Panels      | Back       | Exit app (asks first)                   |
| Fullscreen  | Up/Down    | Previous / next channel in category     |
| Fullscreen  | OK / `*`   | Show / hide now-next banner             |
| Fullscreen  | Back       | Return to panels                        |

## Troubleshooting

- **"Wrong username or password" / "Cannot reach server"**: check the server URL includes the port (`:8080` etc.) and `http://` vs `https://`.
- **A channel won't play**: the app tries HLS (`.m3u8`) then MPEG-TS (`.ts`). Some channels are just down at the provider.
- **No programme info**: the provider has no EPG for that channel.
- **Debug log**: from a computer, `telnet <roku-ip> 8085` while the app runs.

---

## Development

Requires `make`, `zip`, `curl`; `npx` for tests and lint.

```bash
echo 192.168.1.50 > .roku_ip         # your Roku's IP (gitignored)
echo yourdevpassword > .roku_pass    # dev web password (gitignored)
make install                         # zip + sideload to the Roku
make unit                            # utils tests locally (brs-node)
make lint                            # BrighterScript static check
make test                            # same tests on the device (see telnet 8085)
```

### Releasing

Bump `major_version` / `minor_version` / `build_version` in `manifest`, then:

```bash
git tag v1.0.1 && git push origin v1.0.1
```

GitHub Actions lints, tests, builds `iptv-live.zip` and attaches it to a new Release.

### Layout

```
manifest                 app metadata
source/main.brs          entry point
source/utils.brs         pure helpers (URLs, EPG parsing, time), unit tested in source/tests.brs
components/MainScene     switches between Login and Live screens
components/LoginScreen   Xtream sign-in, saves credentials to the device registry
components/LiveScreen    3-panel UI, preview/fullscreen player, EPG
components/ApiTask       background HTTP + JSON for player_api.php
components/ChannelItem   channel row (number, logo, name)
```
