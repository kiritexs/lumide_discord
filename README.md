# Discord Presence for Lumide

Shows what you're working on in Lumide in your Discord status, like the
Rich Presence extensions for VS Code:

```
Playing Lumide
Editing main.dart
In my_app
🕒 01:23:45 elapsed
```

The file's language (Dart, Flutter, Kotlin, …) is the large image, with the
Lumide logo in the small circle. Under it, **Get Lumide** and **Join Lumide
Discord** buttons let others find Lumide; you can [hide them or add your
own](#buttons).

- Shows the open file, the project, the language and the time since Lumide
  was opened. Each of these can be hidden, or all names at once with
  [privacy mode](#privacy-mode).
- Says **Editing** once you type in a file and **Viewing** before that.
- Shows **Running**, **Debugging** or **Testing** while you run your app
  from Run and Debug.
- Shows **Flutter** instead of Dart in Flutter projects.
- Goes **Idle**, or hides your status, after a few minutes without activity,
  but never while your app is running.
- Waits for Discord when it isn't running and reconnects when Discord
  restarts.
- Stays within Discord's update limit.

## Setup

1. In Lumide, open **Plugins** and search for **Discord Presence**, or click
   **Load Local Plugin** and choose this folder.
2. Keep the Discord desktop app open. Your status appears within a few
   seconds.

In Discord, **User Settings → Activity Privacy → Share your detected
activities with others** must be on for others to see it.

## Statuses

| You're | Discord shows | Large image |
|---|---|---|
| Typing in a file | Editing main.dart | The language |
| Reading a file | Viewing main.dart | The language |
| Running or testing your app | Running main.dart, Testing main.dart | The language |
| Debugging your app | Debugging main.dart | A bug |
| Away for a few minutes | Idle | A moon |
| Without a file open | No file open | The Lumide logo |

The second line is the project ("In my_app") and the elapsed time follows.

## Privacy mode

Turn on **Privacy Mode** in the settings, or run **Discord Presence: Turn
Privacy Mode On/Off**, to hide file and project names at once, for example
while screen sharing or working on a client's code. Discord then shows
"Editing a Dart file" without the project. The status bar says
**Discord: private** while it's on.

## Buttons

Two buttons under your status open links for whoever views your profile:

- **Get Lumide** opens [lumide.dev](https://lumide.dev);
- **Join Lumide Discord** opens [Lumide's Discord server](https://discord.gg/VP6p5JQdgt).

To link your own page instead of Lumide's Discord, for example your
project on GitHub, fill in **Custom Button Text** and **Custom Button
Link** (starting with `https://`). Turn off **Show Buttons** to hide both.

Discord shows the buttons to others only: on your own profile, clicking
them does nothing.

## Settings

| Setting | Default | |
|---|---|---|
| Show on Discord | on | Turns the plugin on or off. |
| Privacy Mode | off | Hides file and project names. |
| Show Buttons | on | The [buttons](#buttons) under your status. |
| Custom Button Text | (empty) | Your own button in place of "Join Lumide Discord", up to 32 characters. |
| Custom Button Link | (empty) | The address it opens, starting with `https://`. |
| Discord Application ID | (empty) | Empty shows "Playing Lumide". See [Your own Discord application](#your-own-discord-application). |
| Show File Name | on | Off shows only the language: "Editing a Dart file". |
| Show Project Name | on | The workspace folder's name. |
| Show Language | on | The language image and name. |
| Show Elapsed Time | on | Time since Lumide was opened. |
| Idle After (Minutes) | 5 | Shows "Idle" after this long without typing, moving the cursor or switching files. 0 never goes idle. |
| Hide When Idle | off | Removes your status while idle instead of showing "Idle". |

## Commands and status bar

The **Discord** item in the status bar shows the connection: blue when
your status is shown, grey while turned off, connecting or waiting for
Discord. Click it to turn the plugin on or off.

| Command | |
|---|---|
| Discord Presence: Turn On/Off | Same as clicking the status bar item. |
| Discord Presence: Turn Privacy Mode On/Off | See [Privacy mode](#privacy-mode). |
| Discord Presence: Reconnect | Connects now instead of waiting for the next retry (every 20 s). |

## Your own Discord application

By default your status belongs to the plugin's Discord application:
"Playing Lumide", with its images. To show another name or your own images:

1. Open the [Discord Developer Portal](https://discord.com/developers/applications),
   click **New Application** and give it the name to show after "Playing".
2. Copy its **Application ID** into **Settings → Plugins → Discord
   Presence → Discord Application ID**.
3. Under **Rich Presence → Art Assets**, upload images (at least
   512 × 512 px) named after these keys:

| Key | Shown for |
|---|---|
| `lumide` | Small circle; large image without a file |
| `idle`, `debugging` | Idle; debugging |
| `dart`, `flutter` | Dart; Dart in a Flutter project |
| `javascript`, `typescript`, `react`, `vue`, `svelte` | .js, .ts, .jsx/.tsx, .vue, .svelte |
| `python`, `java`, `kotlin`, `gradle`, `swift`, `go`, `rust` | .py, .java, .kt/.kts, .gradle, .swift, .go, .rs |
| `c`, `cpp`, `csharp`, `php`, `ruby`, `lua` | .c/.h, .cpp/.cc/.cxx/.hpp, .cs, .php, .rb, .lua |
| `html`, `css`, `sass` | .html, .css, .scss/.sass |
| `json`, `yaml`, `toml`, `xml`, `markdown`, `sql` | Data and docs |
| `shell`, `powershell`, `docker`, `makefile` | .sh/.bash/.zsh, .ps1, Dockerfile, Makefile |
| `file` | Any other file |

Clear the field to go back to the plugin's application.

## Privacy and permissions

Lumide's permission system covers file, network and shell access, and
`plugin.yaml` declares the only one this plugin uses: reading
`pubspec.yaml` files in your workspace, to tell Flutter projects from Dart
ones.

**The connection to Discord isn't covered by Lumide's permissions.** The
plugin talks to the Discord app on your computer over Discord's local
connection (a named pipe on Windows, a Unix socket on macOS and Linux),
which is neither file, network nor shell access, so Lumide doesn't ask
about it and can't limit it. You can read exactly what is sent in
[`lib/src/activity.dart`](lib/src/activity.dart) and
[`lib/src/discord_link.dart`](lib/src/discord_link.dart):

- the "Editing …" / "Viewing …" / "Running …" / "Debugging …" / "Idle"
  line, with the file's name only (never its folder or contents);
- "In" and the workspace folder's name;
- the language's name and image name;
- when Lumide was opened.

The settings above turn each of these off, and privacy mode turns off both
names at once. The plugin itself doesn't connect to the internet; Discord
shares your status with others the way it shares any activity, under your
Activity Privacy settings.

## Troubleshooting

- **Status bar says "Discord: waiting"**: the Discord desktop app isn't
  running, or isn't reachable. Discord in a browser doesn't work. On Linux,
  Flatpak and Snap versions of Discord can hide the connection from other
  apps.
- **Nothing shows in Discord** although the status bar is blue: check
  **Activity Privacy → Share your detected activities with others**.
- **No images with your own application**: upload them under **Rich
  Presence → Art Assets** with the names in
  [Your own Discord application](#your-own-discord-application), then wait
  a few minutes.

## Credits

The language, idle and debugging images come from
[VSCord](https://github.com/leonardssh/vscord) (MIT License, © iCrawl).
Dart, Flutter and the other language logos are trademarks of their owners;
this plugin isn't affiliated with or endorsed by them.

## License

GPL-3.0, because the plugin uses
[dart_discord_presence](https://pub.dev/packages/dart_discord_presence),
which is GPL-3.0. See [LICENSE](LICENSE).
