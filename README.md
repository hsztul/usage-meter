# UsageMeter

A macOS menu bar app showing remaining subscription usage for **Claude Code** and
**OpenAI Codex** — the same numbers as Claude Code's `/usage` and Codex's `/status`.

The menu bar shows the selected service's remaining percentage of the 5-hour
window and when it resets (e.g. `✳ 72% · 3pm`). Click it to see both services
with their 5-hour and weekly windows, switch which service is shown (checkmark),
refresh, or toggle launch-at-login.

## Build & install

```sh
make install     # builds, bundles, copies to /Applications, launches
```

Other targets: `make run` (launch from `build/` without installing),
`make bundle`, `make clean`.

Requires Xcode command line tools (`swift`) and macOS 13+. No dependencies.

## How it gets the data

No extra login — it reuses the credentials the CLIs already store:

- **Claude**: reads the Claude Code OAuth token from the macOS keychain
  (`Claude Code-credentials`) and calls `api.anthropic.com/api/oauth/usage`.
- **Codex**: reads the token from `~/.codex/auth.json` and calls
  `chatgpt.com/backend-api/codex/usage`.

It refreshes every 5 minutes and whenever the menu is opened.

## Troubleshooting

```sh
/Applications/UsageMeter.app/Contents/MacOS/UsageMeter --check
```

prints what it would display, with error details.

- **A service shows `—`** with "Token expired": open that CLI (`claude` or
  `codex`) once so it refreshes its token, then Refresh Now.
- **Keychain prompt** on first run: click "Always Allow" so the Claude token
  can be read on every refresh.
- **No login found**: sign in to the CLI on this machine first.
