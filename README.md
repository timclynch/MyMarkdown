# MarkPad

MarkPad is a small, native Mac writing app for people who want the ease of a
notes app and the durability of plain files. Write comfortably, then use the
same Markdown or HTML files with Claude, Codex, Copilot, Finder, or any other
editor.

This replaces the earlier **MyMarkdown 0.1.0** app that used to live in this
repo (still available in the git history and old releases).

## Download and use it

1. Download the latest [MarkPad release](https://github.com/timclynch/MyMarkdown/releases/latest).
2. Double-click the downloaded ZIP, then drag `MarkPad.app` to your Applications folder.
3. Open the app. On first launch it creates `Documents/MyMarkdown` and adds a
   short welcome note.

Because this is an independently built app, macOS may ask for confirmation the
first time. If it does, Control-click `MarkPad.app`, choose **Open**, and confirm.

## What it does

- **File tree sidebar** over `Documents/MyMarkdown` with nested project folders
  (right-click for rename, delete, new-file-here; deletes go to the Trash)
- **Plain-text editor** with smart quotes disabled (safe for Markdown), undo,
  find (⌘F), and spell check
- **Live preview** pane with GitHub-style rendering, light and dark mode
- **Formatting toolbar and shortcuts**: ⌘B bold, ⌘I italic, ⌘K link, headings,
  bullet lists, quotes, and code blocks
- **Markdown / HTML toggle** per document — the toolbar and preview adapt
- **Autosave** about one second after you stop typing (⌘S also works)
- **Apple Notes import**: File → Import from Apple Notes… converts your notes
  to Markdown files organized by their Notes folders
- Edits `.md`, `.markdown`, `.txt`, `.html`, and `.htm` files

## Build from source

Requires Xcode (or the Command Line Tools) on macOS 14 or later:

```bash
./build.sh
```

This compiles `Sources/*.swift`, generates the icon, and produces a signed
`MarkPad.app` in the repo folder. To install it:

```bash
ditto MarkPad.app /Applications/MarkPad.app
```

## License

[MIT](LICENSE)
