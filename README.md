# MyMarkdown

MyMarkdown is a small, native Mac writing app for people who want the ease of a notes app and the durability of plain files. Write comfortably, then use the same Markdown or HTML files with Claude, Codex, Copilot, Finder, or another editor.

## Download and use it

1. Download the latest [MyMarkdown release](https://github.com/timclynch/MyMarkdown/releases/latest).
2. Double-click the downloaded ZIP file, then drag `MyMarkdown.app` to your Applications folder.
3. Open the app. On the first launch, it creates `Documents/MyMarkdown Library` and adds a short welcome note.

Because this is an independently built app, macOS may ask for confirmation the first time. If it does, Control-click `MyMarkdown.app`, choose **Open**, and confirm.

## What it does

- Organizes notes in projects and nested folders you can see in Finder.
- Creates ordinary Markdown (`.md`) and HTML (`.html`) files.
- Offers Write, Preview, and Split views.
- Provides formatting controls for headings, bold, italic, links, lists, checklists, quotes, and code.
- Saves automatically as you write.
- Searches document names and contents.
- Lets you rename, move notes to the Trash, and reveal your library in Finder.
- Lets you choose any folder as your writing library.

Your work remains yours: MyMarkdown does not need an account, a cloud service, or a proprietary database.

## Build from source

MyMarkdown requires macOS 14 or later and Xcode’s command-line tools.

```sh
git clone https://github.com/timclynch/MyMarkdown.git
cd MyMarkdown
./scripts/build-app.sh
```

The build creates `dist/MyMarkdown.app` and `dist/MyMarkdown.zip`.

## Status

This is the first public version. Apple Notes migration is planned but is not included yet.

## License

MyMarkdown is available under the [MIT License](LICENSE).
