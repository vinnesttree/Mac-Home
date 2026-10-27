# MacHome

A TV home screen for a Mac, styled after the Apple TV and driven by a game controller. It is built for a
Late 2014 Mac mini on macOS 12 Monterey connected to a TV, but runs on any Mac with macOS 12 or later.

- **Home screen:** a row of app tiles under a large "top shelf" banner for the focused app. The focused tile
  lifts, glows and tilts with the left stick, as on tvOS.
- **YouTube** runs inside MacHome using YouTube's own TV interface (the one smart TVs and consoles get).
- **Jellyfin** runs inside MacHome using your server's web interface.
- **Netflix** opens in Safari, and the controller works as a mouse.
- **Safari** is the general web browser backup.
- **Desktop** hides MacHome and shows the normal Mac desktop. Press Home on the controller to come back.

Tiles are listed in a plain text file, so you can add Kodi, Plex, Firefox or any other app.

## Why it works this way on a 2014 Mac mini

- **Video formats:** the Mac mini's Intel Haswell graphics decode only H.264 in hardware. VP9, AV1 and
  HEVC have to be decoded by the CPU, which stutters on this machine. MacHome tells YouTube and Jellyfin that
  those formats aren't supported, so YouTube serves H.264 (up to 1080p) and Jellyfin converts files on the
  server. This is the same trick as the h264ify browser extension.
- **Netflix:** there is no Netflix app for Mac. Safari is the best browser for Netflix on Monterey and supports
  its copy protection, so Netflix opens there.
- **Display:** the Mac mini sends 4K to a TV at only 30 Hz over HDMI, which makes animation and 60 fps video
  choppy. For the smoothest result, set **System Preferences › Displays** to 1920 × 1080 at 60 Hz and let the
  TV upscale. MacHome scales its layout to any resolution.

## Install

You need Apple's free **Command Line Tools**. They don't need Xcode or an Apple ID. In Terminal:

```sh
xcode-select --install          # once; click Install in the dialog
git clone https://github.com/vinnesttree/Mac-Home.git
cd Mac-Home
./scripts/install.sh
```

`install.sh` builds the app, copies it to `~/Applications/MacHome.app`, starts it, and sets it to start at
every login. To only build it, run `./scripts/build.sh`; the app appears in `build/`.

Every push to GitHub also builds an Intel copy of the app. It's on the repository's **Actions** tab, under
**MacHome-intel**. A downloaded copy isn't signed by Apple, so the first time, right-click it and choose
**Open**.

### One-time setup (have a keyboard and mouse handy)

1. **Pair the controller** in **System Preferences › Bluetooth**. Xbox One S / Series and PlayStation 4 / 5
   controllers work.
2. **Allow Accessibility access.** MacHome needs this to control Safari, other apps and the desktop with the
   controller. The first time it needs it, macOS asks. Otherwise go to **System Preferences › Security &
   Privacy › Privacy › Accessibility** and tick **MacHome**. YouTube and Jellyfin inside MacHome work without
   it. After rebuilding MacHome, remove it from that list and add it again, because each build has a new
   signature.
3. **Add your Jellyfin server.** Press **⌘,** on the home screen to open `apps.json`, put your server's
   address in the Jellyfin tile's `"url"` (for example `"http://192.168.1.20:8096"`), and save. Then, in
   Jellyfin, open **Settings › Display** and set **Display mode** to **TV** for remote-style navigation.
4. **Sign in.** YouTube shows a code to enter at youtube.com/activate on your phone. Netflix signs in in
   Safari.
5. **Optional, for a dedicated TV box:**
   - Turn on automatic login in **Users & Groups › Login Options**.
   - Turn on the on-screen keyboard for typing with the controller: **System Preferences › Accessibility ›
     Keyboard › Accessibility Keyboard**.

## Controls

Xbox names are shown first, PlayStation names in brackets.

**Everywhere:** press **Home** (Xbox [PS]) to go back to the home screen. While another app is in front,
macOS also opens Launchpad when Home is pressed. Pressing **View + Menu** together [Share + Options] does the
same without Launchpad.

| Home screen | |
|---|---|
| D-pad or left stick | Move between tiles |
| Small left-stick movements | Tilt the focused tile |
| A [Cross] | Open |

| YouTube and Jellyfin | |
|---|---|
| D-pad or left stick | Arrow keys |
| A [Cross] | Select |
| B [Circle] | Back |
| X [Square] | Play / pause |
| Right stick | Scroll |
| View [Share] | Switch to pointer mode |

| Safari, Netflix, other apps and the desktop | |
|---|---|
| Left stick | Move the pointer |
| A [Cross] | Click (hold to drag, press twice to double-click) |
| RT [R2] | Right-click |
| D-pad | Arrow keys (on Netflix: skip back / forward) |
| B [Circle] | Escape |
| X [Square] | Space (play / pause) |
| Y [Triangle] | Full screen on / off |
| LB / RB [L1 / R1] | Browser back / forward |
| Right stick | Scroll |
| View [Share] | Switch between pointer and arrow-key mode |

With a keyboard: arrow keys and Return work on the home screen, **⌘W** goes home, **⌘D** shows the desktop,
**⌘R** reloads `apps.json`, and **⌘Q** quits.

## apps.json

The tiles live in `~/Library/Application Support/MacHome/apps.json`, created with the defaults on first run.
MacHome rereads it each time you return to the home screen. If you edit it in TextEdit, turn off
**Edit › Substitutions › Smart Quotes**.

| Field | Meaning |
|---|---|
| `title` | Name on the tile and the banner. |
| `subtitle` | Line of text under the name in the banner. |
| `kind` | `web` (shown inside MacHome), `browser` (opens `url` in a browser app), `app` (opens a Mac app) or `desktop`. |
| `url` | Web address for `web` and `browser` tiles. |
| `app` | For `app` tiles: a bundle ID (`com.apple.Safari`), an app name (`Kodi.app`) or a full path. |
| `browser` | For `browser` tiles: which browser, written like `app`. Leave it out to use the default browser. |
| `arguments` | Command-line arguments passed to an `app`. |
| `input` | What the controller does: `keys` (arrow keys), `pointer` (mouse), or `native` (the app reads the controller itself; MacHome only listens for Home). Defaults to `keys` for `web` tiles and `pointer` for the rest. |
| `userAgent` | For `web` tiles: the browser identity sent to the site. |
| `blockCodecs` | For `web` tiles: video formats to hide from the site, such as `"vp9"`, `"av01"`, `"hvc1"`. |
| `symbol` | An SF Symbol name for the tile art, such as `"film.fill"`. |
| `colors` | Two hex colours for the tile gradient, such as `["#E50914", "#2B0000"]`. |
| `image` | A picture to use as the tile and banner art instead (a path, or a file name next to apps.json). |

Examples:

```json
{ "title": "Kodi", "kind": "app", "app": "Kodi.app", "input": "native" }
{ "title": "Plex", "kind": "app", "app": "Plex HTPC.app", "input": "keys" }
{ "title": "Firefox", "kind": "app", "app": "Firefox.app" }
{ "title": "Twitch", "kind": "browser", "url": "https://www.twitch.tv", "symbol": "play.rectangle",
  "colors": ["#9146FF", "#2A0F5C"] }
```

Firefox is a good choice for the browser tile: it still gets updates on Monterey, while Safari stopped at
17.6 and Chrome stopped at version 150.

## Limits and things to know

- **Not yet tested on real hardware.** It compiles in CI for Intel with macOS 12 as the minimum, but it
  hasn't been run on a Mac mini yet.
- **YouTube's TV interface** is only served to TV and console browsers, so MacHome identifies itself as a
  PlayStation 4 YouTube app (the same identity the open-source YouTubeTV app uses). If YouTube stops
  accepting it, change the YouTube tile's `userAgent`, or install
  [YouTubeTV](https://github.com/marcosrg9/YouTubeTV) and point the tile at it with `"kind": "app"` and
  `"input": "keys"`.
- **Netflix inside MacHome** (a `web` tile) hasn't been tested and may not play protected video, which is
  why it opens in Safari.
- **Built for Monterey.** On newer macOS (for example through OpenCore Legacy Patcher), Apple has restricted
  apps from bringing themselves to the front and changed background controller input, so the Home button may
  be less reliable.

## Uninstall

```sh
launchctl unload ~/Library/LaunchAgents/local.machome.launcher.plist
rm ~/Library/LaunchAgents/local.machome.launcher.plist
rm -rf ~/Applications/MacHome.app ~/Library/"Application Support"/MacHome
```
