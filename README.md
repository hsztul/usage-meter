# UsageMeter

A macOS menu bar app that shows your remaining subscription usage for
**Claude Code** and **OpenAI Codex** — the same numbers as Claude Code's
`/usage` and Codex's `/status`, always a glance away.

![menu bar example](https://img.shields.io/badge/menubar-%E2%9C%B3%2072%25%20%C2%B7%203pm-informational)

The menu bar shows the selected service's remaining percentage of its 5-hour
window and when that window resets (e.g. `✳ 72% · 3pm`). Click the icon to:

- See **both** services with their 5-hour **and** weekly windows and reset times.
- Switch which service appears in the menu bar — click a name, the checkmark
  moves, and the choice persists across restarts.
- **Refresh Now** (⌘R), toggle **Launch at Login**, or **Quit** (⌘Q).

It refreshes automatically every 5 minutes and whenever you open the menu.

## Requirements

- macOS 13 (Ventura) or later
- Xcode command line tools (`xcode-select --install` provides `swift`)
- Signed in to the CLIs whose usage you want to track (`claude` and/or `codex`)

No third-party dependencies — standard library + AppKit only.

## Install

```sh
make install
```

This builds a release binary, assembles `UsageMeter.app`, ad-hoc code-signs it,
copies it to `/Applications`, and launches it. The icon appears in your menu bar.

On first run macOS may prompt for keychain access (to read the Claude Code
token). Click **Always Allow** so it can refresh without prompting.

To start it automatically on login, open the menu and toggle **Launch at Login**.

## How it gets the data

No separate login — UsageMeter reuses the credentials the CLIs already store on
your machine and calls the same usage endpoints they do:

| Service | Token source | Endpoint |
| --- | --- | --- |
| Claude | macOS keychain entry `Claude Code-credentials` | `api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` | `chatgpt.com/backend-api/codex/usage` |

Tokens are read fresh on every refresh, so re-logging into a CLI is picked up
automatically. Nothing is stored or sent anywhere else.

## Development

### Project layout

```
usage-meter/
  Package.swift                 SwiftPM manifest — one executable target, macOS 13+
  Makefile                      build / bundle / install / run / clean
  Sources/UsageMeter/
    App.swift                   @main, NSApplicationDelegate, status item, menu, timer, --check
    UsageService.swift          ServiceKind, data models, Claude + Codex fetchers
    Formatting.swift            menu-bar title and reset-time strings
```

The whole app is ~4 small Swift files. The pieces:

- **`UsageService.swift`** — the data layer. `ServiceKind` (claude/codex),
  the `Window`/`UsageSnapshot` models, and a fetcher per service. Each fetcher
  reads its token, calls its endpoint, and maps the JSON into the common model.
  Failures become a `ServiceState.error(message)` rather than crashing, so a
  logged-out or changed-API service just shows `—`. `fetchUsage(for:)` is the
  entry point both fetchers funnel through.
- **`Formatting.swift`** — pure functions turning a snapshot into display
  strings (`✳ 72% · 3pm`, `resets 3:00 PM`). Respects the system 12/24-hour
  clock preference.
- **`App.swift`** — the AppKit shell. Creates the `NSStatusItem`, builds the
  `NSMenu` on each refresh, runs the 5-minute `Timer`, refreshes on
  `menuWillOpen`, and persists the selected service in `UserDefaults`. The app
  uses `.accessory` activation policy so there's no Dock icon.

### Iterate

```sh
swift build                 # debug build
make run                    # bundle + launch from build/ (doesn't touch /Applications)
```

`make run` and `make install` both `pkill` any running instance first, so you
can just re-run after a change.

### Inspect the data without the UI

The binary has a headless self-check that fetches both services once and prints
exactly what the menu bar and dropdown would show, with full error detail:

```sh
.build/release/UsageMeter --check
# or, on an installed copy:
/Applications/UsageMeter.app/Contents/MacOS/UsageMeter --check
```

This is the fastest way to confirm auth and endpoint behavior when changing a
fetcher.

### Notes

- **Launch at Login** uses `SMAppService.mainApp`, which only works from a real
  `.app` bundle with a bundle identifier — it's a no-op when running the bare
  binary. Use `make run`/`make install` to test it.
- The bundle is **ad-hoc signed** (`codesign --sign -`). A rebuilt binary has a
  new signature, so macOS may re-prompt for keychain access after each rebuild;
  fine for a personal tool.
- Endpoint shapes are parsed defensively. If Anthropic or OpenAI change a field,
  the affected service degrades to `—` + an error line instead of crashing —
  start from `UsageService.swift` to map the new shape.

## Troubleshooting

- **A service shows `—`** ("Token expired"): open that CLI (`claude` or `codex`)
  once so it refreshes its token, then **Refresh Now**.
- **"No login found"**: sign in to that CLI on this machine first.
- **Keychain prompt keeps appearing**: click **Always Allow** (it reappears once
  per rebuild because of ad-hoc signing).
- Run `… --check` (above) to see the underlying error message.

## License

Personal project — use it however you like.
