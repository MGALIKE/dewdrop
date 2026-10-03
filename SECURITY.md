# Security

Dewdrop runs with your user's privileges, receives Claude Code hook events over a local socket, and can answer permission requests on your behalf — only ever on a click. If you find a way to break any of that, please tell us privately first.

**Report:** use [GitHub's private vulnerability reporting](https://github.com/MGALIKE/dewdrop/security/advisories/new) on this repository. You should hear back within a week.

**In scope:** anything that lets another process or user talk to the hook socket, make the app approve a permission, read a key out of the Keychain through the app, write to `~/.claude/settings.json` without the confirmation flow, or run code through a hook payload, a clipboard entry, a file drop or a window title.

**What the app does on purpose, so you don't have to report it:** it polls the pointer position (no permission needed), reads the pasteboard's change counter once a second when the Clipboard pill is on, runs AppleScript against Music/Spotify/your terminal/Mail with the Automation permission, and talks to exactly the services you configured in Settings.
