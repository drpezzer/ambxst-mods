# ambxst-mods

Mods for [Ambxst](https://github.com/Axenide/Ambxst) 1.3+, packaged for its native
mod manager. Each folder under `packages/` is one installable package.

## Installing

Paste a package link into **Settings → Mods** and press *Install*:

```
https://github.com/drpezzer/ambxst-mods/tree/main/packages/tinted-icons
```

Or from a terminal:

```bash
ambxst mods install https://github.com/drpezzer/ambxst-mods/tree/main/packages/tinted-icons
ambxst mods enable drpezzer.tinted-icons
ambxst reload
```

Packages install disabled. Enabling shows the author, license and permissions,
builds a fresh source tree, and takes effect on the next `ambxst reload`. If
the shell fails to start within eight seconds Ambxst rolls back on its own.

## Packages

| Package | What it does |
|---|---|
| [tinted-icons](packages/tinted-icons) | App icons in the bar, dock, workspaces and launcher drawn as solid theme-coloured glyphs |
| [steamdeck-mode](packages/steamdeck-mode) | Quick Controls button that turns the PC into a Steam Deck streaming host: Sunshine + MoonDeck Buddy, a dedicated headless output, dark desk with a password overlay |

More are on the way as they are ported from a long-running personal fork.

## License

MIT.
