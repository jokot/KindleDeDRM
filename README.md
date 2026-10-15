# KindleDeDRM

A Windows 11 app that turns Kindle books you own into DRM-free EPUB files.

Install it once and run `KindleDeDRM` to open a menu that:

1. checks the prerequisites (Kindle for Windows, Calibre, DeDRM tools, plugins),
2. installs whatever is missing,
3. lets you search your books and convert, re-convert or re-export them to EPUB.

```
Kindle for Windows --> MSIXKFXArchiver --> Calibre (DeDRM + KFX Input) --> EPUB
```

## Quick start

```bat
git clone https://github.com/jokot/KindleDeDRM.git
KindleDeDRM\KindleDeDRM\install.cmd
```

Open a new terminal and run `KindleDeDRM`, or use the **KindleDeDRM** shortcut in the Start menu.

Full usage, requirements and troubleshooting are in **[KindleDeDRM/README.md](KindleDeDRM/README.md)**.

## Repository layout

| Path | Contents |
|---|---|
| [`KindleDeDRM/`](KindleDeDRM) | The app: entry point, `lib/`, installer, Pester tests |
| [`Kindle-DeDRM-Guide.md`](Kindle-DeDRM-Guide.md) | Manual step-by-step guide (the process the app automates) |
| [`docs/superpowers/`](docs/superpowers) | Design spec and implementation plan |

## Notes

- This repository contains no DRM-removal tools or keys. The app downloads Satsuoni's DeDRM tools and the Calibre plugins from their upstream releases, and checks each download against its published checksum.
- Use it only for books you have bought, as a personal backup. Removing DRM is not legal everywhere, so check your local law.
