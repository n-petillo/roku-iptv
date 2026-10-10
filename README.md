# IPTV Live (Roku)

Minimal Roku live-TV player for Xtream Codes accounts. Sign in, then browse in three panels:
**categories | channels | preview + EPG** (now/next from `get_short_epg`).

## Install on your Roku (sideload)

1. Enable Developer Mode on the Roku: on the remote press `Home ×3, Up ×2, Right, Left, Right, Left, Right`,
   accept, set a dev password, and note the IP shown.
2. From this folder:
   ```bash
   echo 192.168.1.50 > .roku_ip        # your Roku's IP
   echo yourdevpassword > .roku_pass   # the dev password from step 1
   make install                        # prints "Install Success"
   ```
   (or `make install ROKU_IP=... ROKU_PASS=...`)

The app launches right away and shows up on the home screen as "IPTV Live".

## Remote controls

| Where            | Key          | Action                                   |
|------------------|--------------|------------------------------------------|
| Login            | OK           | Edit field / Sign in                     |
| Panels           | Up/Down      | Move in list                             |
| Panels           | Left/Right   | Switch between Categories and Channels   |
| Channels         | OK           | Play in preview; OK again = fullscreen   |
| Panels           | `*`          | Log out / change account                 |
| Panels           | Back         | Exit app (with confirmation)             |
| Fullscreen       | Up/Down      | Previous / next channel in the category  |
| Fullscreen       | OK / Info    | Show/hide now-next banner                |
| Fullscreen       | Back         | Return to panels                         |

## Development

- `make unit`: run `source/utils.brs` tests locally (brs-engine)
- `make lint`: static check with BrighterScript
- `make test`: run the same tests on the device (output: `telnet <roku-ip> 8085`)
- Debug console while the app runs: `telnet <roku-ip> 8085`

Streams play as HLS (`/live/<user>/<pass>/<id>.m3u8`) and fall back to `.ts` if HLS fails.
