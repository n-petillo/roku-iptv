# FedSmokerTV (Roku + Android TV)

Simple live-TV player for Xtream Codes accounts, for **Roku** and **Google TV / Android TV**
(the Android app lives in [`android/`](android/); jump to [Install on Google TV](#install-on-google-tv--android-tv)). Sign in once, then browse in three panels:
**categories | channels | preview + EPG** (now / next). Star your go-to channels and the app opens
on a **Favorites** grid.

---

## Install on a Roku

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

Go to this repo's **[Releases](../../releases)** page, open the newest **FedSmokerTV v…** release (not the *Android TV* ones)
and download **`fedsmokertv.zip`**.
Don't unzip it.

### 3. Upload it to the TV

1. In a browser on the same network, open the Roku's IP: `http://192.168.1.50`
2. Log in with username **`rokudev`** and the password from step 1.
3. Click **Upload**, pick `fedsmokertv.zip`, then click **Install with zip**.
4. The app launches on the TV. It now also appears on the Roku home screen as **FedSmokerTV**.

### 4. Sign in

The **Server URL** is prefilled with `http://ipservz.net` (select it to change it). Enter your **Username** and **Password**,
then select **Sign in**. They're saved on that TV, so next time it opens straight to Live TV.

### Updating

Download the newer `fedsmokertv.zip` from Releases and repeat **step 3**. Your login is kept.

### Good to know

- A Roku can only have **one** developer (sideloaded) app at a time.
- The app survives restarts, but a **factory reset** or disabling Developer Mode removes it, so just install it again.
- Your server login is stored only on the TV, never in this repo.

---

## Install on Google TV / Android TV

The Android app isn't in the Play Store, so you sideload it once per TV. Updates install over the top and keep
your login and favorites.

### Option A: Downloader app (no computer needed)

1. **Enable Developer options:** on the TV open **Settings → System → About**, scroll to **Android TV OS build**
   (or **Build**) and press **OK** on it 7 times until it says you're a developer.
2. Install **Downloader** by AFTVnews from the Play Store (search "Downloader").
3. Allow it to install apps: **Settings → Apps → Security & restrictions → Unknown sources** (on some TVs
   **Settings → Privacy → Security & restrictions → Unknown sources**) and turn on **Downloader**.
4. Get the APK link: this repo is private, so on a phone or computer open the
   **[Releases](../../releases)** page, find the newest **FedSmokerTV for Android TV** release and copy the
   download link of **`fedsmokertv.apk`**. Downloader needs a public link, so either put the APK somewhere you can
   download it without signing in (Google Drive "anyone with the link", Dropbox, …) or use Option B.
5. In Downloader, type the URL, download, then choose **Install**.
6. FedSmokerTV now shows up in your apps row (Google TV: **Apps → Your apps**; you can move it to Favorites).

### Option B: `adb` from a computer

1. Enable **Developer options** (step 1 above), then **Settings → System → Developer options → USB debugging** /
   **Network debugging** on.
2. Find the TV's IP: **Settings → Network & Internet → (your network)**.
3. On a computer with [platform-tools](https://developer.android.com/tools/releases/platform-tools) installed:
   ```bash
   gh release download --repo n-petillo/roku-iptv --pattern fedsmokertv.apk    # newest Android release
   adb connect 192.168.1.60:5555          # your TV's IP; accept the prompt on the TV
   adb install -r fedsmokertv.apk
   ```
   (Android 11+ TVs may ask you to pair first: Developer options → **Wireless debugging → Pair device with code**,
   then `adb pair <ip>:<pair-port>` and `adb connect <ip>:<port>` with the ports shown on the TV.)

### Sign in

Same as Roku: the **Server URL** is prefilled with `http://ipservz.net`. Select **Username** and **Password**,
type them with the on-screen keyboard, press **Done**, then **Sign in**. They're saved on that TV only.

### Android remote controls

Same layout as Roku, adapted for remotes without ▶‖ or `*` keys:

| Where       | Key                      | Action                                         |
|-------------|--------------------------|------------------------------------------------|
| Channels / Favorites / Fullscreen | **Hold OK** (or ▶‖) | Add / remove favorite             |
| Fullscreen  | Up/Down or CH+/CH−       | Previous / next channel                        |
| Fullscreen  | OK                       | Show / hide now-next card                      |
| Panels      | Back                     | Back to Favorites (or exit if you have none)   |
| Favorites   | Back                     | Exit, **Refresh** or **Log out**               |
| Anywhere    | Menu (if your remote has one) | **Refresh** / Log out / change account    |

---

## Remote controls (Roku)

| Where       | Key        | Action                                              |
|-------------|------------|-----------------------------------------------------|
| Login       | Up/Down    | Move between fields                                 |
| Login       | OK         | Edit field / Sign in                                |
| Favorites   | Arrows     | Move between tiles; Up from the top row = tabs      |
| Favorites   | OK         | Watch fullscreen                                    |
| Favorites   | ▶‖         | Remove favorite                                     |
| Panels      | Left/Right | Switch between Categories and Channels              |
| Channels    | OK         | Play in preview; OK again = fullscreen              |
| Channels    | ▶‖         | Add / remove favorite                               |
| Anywhere    | `*`        | **Refresh channels & guide** / Log out              |
| Panels      | Back       | Back to Favorites (or exit if you have none)        |
| Fullscreen  | Up/Down    | Previous / next channel (in that list)              |
| Fullscreen  | OK / `*`   | Show / hide now-next card                           |
| Fullscreen  | ▶‖         | Add / remove favorite                               |
| Fullscreen  | Back       | Return to where you came from                       |

Favorites are saved on each TV, per account.

**Refresh** reloads the channel list and programme guide from the provider and reconnects the channel
that's playing. What's on screen stays put until the new list arrives; if the server can't be reached
you get a message and keep the old data.

## Troubleshooting

- **Channels missing, renamed or stuck, guide out of date**: use **Refresh** (`*` on Roku; Menu or Back from
  Favorites on Android).
- **"Wrong username or password" / "Cannot reach server"**: check the server URL includes the port (`:8080` etc.) and `http://` vs `https://`.
- **A channel won't play**: the app tries HLS (`.m3u8`) then MPEG-TS (`.ts`). Some channels are just down at the provider.
- **No programme info**: the provider has no EPG for that channel.
- **Debug log**: from a computer, `telnet <roku-ip> 8085` while the app runs.

---

## Development

### Roku

Requires `make`, `zip`, `curl`; `npx` for tests and lint.

```bash
echo 192.168.1.50 > .roku_ip         # your Roku's IP (gitignored)
echo yourdevpassword > .roku_pass    # dev web password (gitignored)
make install                         # zip + sideload to the Roku
make unit                            # utils tests locally (brs-node)
make lint                            # BrighterScript static check
make test                            # same tests on the device (see telnet 8085)
```

#### Releasing (Roku)

Bump `major_version` / `minor_version` / `build_version` in `manifest`, then:

```bash
git tag v1.1.1 && git push origin v1.1.1
```

GitHub Actions lints, tests, builds `fedsmokertv.zip` and attaches it to a new Release.

#### Layout (Roku)

```
manifest                 app metadata
source/main.brs          entry point
source/utils.brs         pure helpers (URLs, EPG parsing, time), unit tested in source/tests.brs
components/MainScene     switches between Login, Live and Error screens
components/LoginScreen   Xtream sign-in form, saves credentials to the device registry
components/ErrorScreen   "Cannot reach server" with Retry / Edit account
components/LiveScreen    favorites grid, 3-panel UI, preview/fullscreen player, EPG, favorites
components/ApiTask       background HTTP + JSON for player_api.php
components/*Item, FavTile list rows / tiles; FormField, PillButton, KeyHints shared controls
components/ui.brs        palette + font helpers (Runway ink, white opacity ladder, ABC Normal)
fonts/, images/          ABC Normal, 9-patch shapes and icons (regenerate: tools/make_images.py)
```

### Android app

Kotlin + Jetpack Compose (D-pad driven, 1920×1080 design canvas scaled to the screen), Media3 ExoPlayer
(HLS then MPEG-TS), OkHttp + kotlinx.serialization, DataStore. Needs JDK 17 and the Android SDK
(`brew install openjdk@17 android-commandlinetools`, then `sdkmanager "platforms;android-35" "build-tools;35.0.0" platform-tools`).

```bash
cd android
echo "sdk.dir=/opt/homebrew/share/android-commandlinetools" > local.properties   # gitignored
./gradlew :app:testDebugUnitTest      # helper tests (port of source/tests.brs)
./gradlew :app:installDebug           # build + install on a connected TV / emulator (adb)
adb logcat -s FedSmokerTV             # debug log
```

Release: `git tag android-v1.0.1 && git push origin android-v1.0.1`. The `android-release` workflow runs the
tests, builds a signed `fedsmokertv.apk` (versionName from the tag) and attaches it to a GitHub Release.
Signing uses repo secrets `FST_KEYSTORE_B64` (base64 of the `.jks`) and `FST_KEYSTORE_PASSWORD`; the keystore
itself is never committed. **Keep a backup of the keystore**: an APK signed with a different key can't update
the installed app (you'd have to uninstall, losing login and favorites).

```
android/app/src/main/java/com/npetillo/fedsmokertv/
  Utils.kt        pure helpers (URLs, EPG parsing, time, favorites), unit tested in src/test
  Api.kt          player_api.php client         Store.kt   DataStore: creds + per-account favorites
  AppVm.kt        Login / Live / Error switching, login form state, the one ExoPlayer
  LiveState.kt    live TV logic: modes, categories, channels, EPG queue, favorites, playback, keys
  MainActivity.kt remote key mapping (incl. hold-OK)
  ui/             Theme (palette, ABC Normal + fallback), Screens (login, error), LiveScreen
```
Launcher icon and TV banner: `python3 tools/make_images.py android` (needs Pillow).
