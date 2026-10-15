# KindleDeDRM

Turn the Kindle books you own into DRM-free EPUB files on Windows 11. You install it once, then run `KindleDeDRM` in any terminal.

```
Kindle for Windows --> MSIXKFXArchiver --> Calibre (DeDRM + KFX Input) --> EPUB
   (downloads)        (extract + decrypt)     (import, convert)           (export)
```

It's written in plain Windows PowerShell 5.1, so you don't need to install anything to run it.

> [!WARNING]
> **Keep Kindle for Windows at version 1.0.25218.** The book extractor (`MSIXKFXArchiver_x64_1_25218.exe` from Satsuoni's DeDRM tools v10.0.32) works with this one Kindle build only.
>
> - **Don't update Kindle, and don't uninstall and reinstall it.** The Microsoft Store always installs the newest version and can't go back to an older one.
> - On a newer build, extraction stops working until Satsuoni releases a matching extractor.
> - To stop the Store updating Kindle by itself, turn **Store auto-updates off** in menu 4 (Settings). Removing book downloads inside Kindle is fine.

## Install

Paste this into PowerShell:

```powershell
irm https://raw.githubusercontent.com/jokot/KindleDeDRM/main/install.ps1 | iex
```

It downloads the latest version from this repository and:

- copies the app to `%LOCALAPPDATA%\Programs\KindleDeDRM`
- adds that folder to **your** PATH (no admin rights needed)
- adds a **KindleDeDRM** Start-menu shortcut

Then open a **new** terminal and run `KindleDeDRM`, or use the Start-menu shortcut.

**Update:** run the same command again.

**From a clone:** `git clone https://github.com/jokot/KindleDeDRM.git`, then run `install.cmd` in the repository folder. That installs your local copy instead of downloading one.

**Uninstall:**

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\KindleDeDRM\uninstall.ps1"
```

This removes the app, the PATH entry and the shortcut. It keeps your extracted books, keys, settings and title list in `%LOCALAPPDATA%\kindle-dedrm`, and it doesn't touch your Calibre library, Calibre or Kindle.

## Using the menu

```
  ██╗  ██╗██╗███╗   ██╗██████╗ ██╗     ███████╗██████╗ ███████╗██████╗ ██████╗ ███╗   ███╗
  ...
  Unlock the Kindle books you own  v1.0  github.com/jokot/KindleDeDRM

  Kindle 1.0.25218  .  27 books  .  all prerequisites OK
  ------------------------------------------------------------
  1) Check prerequisites
  2) Install prerequisites
  3) DeDRM books
  4) Settings
  5) Clean temp files
  0) Exit
```

1. **Check prerequisites** shows a table of what's needed and what's installed.
2. **Install prerequisites** installs only what's missing. For each item it explains why it's needed and where it comes from, then asks before installing. If everything is already installed, you can reinstall one part or switch Microsoft Store auto-updates on or off.
3. **DeDRM books**:
   - **Refresh:** it first offers to extract any newly downloaded Kindle books (`s` skips this).
   - **List:** every book downloaded in Kindle is shown straight away, unconverted ones first.
   - **One prompt does the rest:**
     - **Pick** books by their `#` number: `3` (book 3), `1,3` (books 1 and 3), `2-5` (books 2 to 5), `all` (every book listed), or `new` (every book not converted to EPUB yet).
     - **Search** by typing part of a title or author. The list narrows and the numbers restart from 1. To search for a number or a keyword such as `new`, start with a slash: `/1984`.
     - **Blank** clears the search.
     - `a` shows or hides Calibre-only books (ones no longer downloaded in Kindle, or sideloaded). They're hidden by default.
     - `0` goes back.
   - **Choose an action:**
     - **Convert:** does whatever each book still needs (extract, import, EPUB, export).
     - **Re-convert:** rebuilds the EPUB, for example after you fix a title or author in Calibre.
     - **Re-export:** copies the EPUB to your EPUB folder again.
     - **Open folder:** opens Explorer on the book's newest file: the exported EPUB, else the EPUB or KFX in Calibre, else the extracted `.kfx-zip`, else the Kindle download folder.
4. **Settings** lets you change the EPUB folder, the Calibre library, the stall timeout and Microsoft Store auto-updates. They're saved and remembered.
5. **Clean temp files** deletes the extractor's temporary `C:\Data` folder (about 400 MB).

Book statuses:

| Status | Meaning |
|---|---|
| `incomplete` | Download is missing its `.azw` file. Remove the download in Kindle and download it again. |
| `new` | Downloaded, not extracted yet |
| `extracted` | Extracted, not in Calibre yet |
| `in Calibre` | Imported, no EPUB yet |
| `EPUB done` | Converted |
| `not downloaded` | In Calibre but no longer downloaded in Kindle. You can still re-convert or re-export it. |

### Before converting new books

1. In Kindle, download the books, **a few at a time**. Bulk downloads can be missing images.
2. Open each new book once and page to the end.
3. Close Kindle. KindleDeDRM offers to do this for you.

## Command line

```
KindleDeDRM                    open the menu
KindleDeDRM check              requirements table
KindleDeDRM install [parts]    vcredist calibre kindle dedrm-tools dedrm-plugin kfx-input
                               store-updates-off store-updates-on
KindleDeDRM convert            convert every new book
KindleDeDRM clean              delete extractor temp files
KindleDeDRM help
```

Options (apply to this run only): `-OutDir <path>`, `-Library <path>`, `-StallSeconds <n>`, `-Yes`, `-Force`.

## Requirements

| Component | Version | Source |
|---|---|---|
| Windows 11 | build 22000+ | |
| Microsoft Visual C++ runtime x64 | 14.20+ | <https://aka.ms/vs/17/release/vc_redist.x64.exe> |
| Calibre | 9.16.0 (min 6.0) | <https://github.com/kovidgoyal/calibre/releases/tag/v9.16.0> |
| Kindle for Windows | 1.0.25218 (tested) | Microsoft Store, ID `9P8JQ0JJSTLL` |
| DeDRM tools (Satsuoni) | v10.0.32 | <https://github.com/Satsuoni/DeDRM_tools/releases/tag/v10.0.32> |
| DeDRM Calibre plugin | 10.0.32 | `DeDRM_plugin.zip` in the DeDRM tools |
| KFX Input Calibre plugin | 2.34.2+ | <https://plugins.calibre-ebook.com/291290.zip> |

**The extractor must match your Kindle build exactly.** For example, `MSIXKFXArchiver_x64_1_25218.exe` only works with Kindle 1.0.25218.

- Downloads are verified: files from GitHub against the SHA-256 that GitHub lists, and the VC++ installer by its Microsoft signature.
- Installing Calibre or the VC++ runtime, and changing Store updates, shows a Windows admin prompt.

## Files

| Path | Contents |
|---|---|
| `%LOCALAPPDATA%\Programs\KindleDeDRM` | The installed app |
| `%LOCALAPPDATA%\kindle-dedrm\settings.json` | Your settings |
| `%LOCALAPPDATA%\kindle-dedrm\index.json` | Book titles and where each EPUB was exported |
| `%LOCALAPPDATA%\kindle-dedrm\work\archived_kfx` | Extracted books (`.kfx-zip`) |
| `%LOCALAPPDATA%\kindle-dedrm\work\*.k4i`, `*.keyfile` | **Your book keys. Keep them private.** |
| `%LOCALAPPDATA%\kindle-dedrm\work\logs` | Extractor and conversion logs |
| `%LOCALAPPDATA%\kindle-dedrm\tools`, `downloads` | DeDRM tools and installers |

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Extractor for your Kindle: none for build N" | Kindle updated past the supported build. Find a matching extractor in Satsuoni's releases, change `DeDrmTag` in `lib\Config.ps1`, run `install.cmd`, then `KindleDeDRM install dedrm-tools dedrm-plugin -Force`. |
| A book "hung and was skipped" | In Kindle: Remove download, download again, open it, then Convert again. |
| "imported as KFX-ZIP - DRM was not removed" | Delete the book in Calibre, download it again in Kindle, then Convert. |
| `VCRUNTIME140_1.dll was not found` | Menu 2 (or `KindleDeDRM install vcredist`). |
| `KindleDeDRM` not found after install | Open a new terminal. PATH changes only reach new windows. |

## Repository layout

| Path | Contents |
|---|---|
| `KindleDeDRM.ps1`, `KindleDeDRM.cmd` | Entry point: argument parsing and the menu |
| [`lib/`](lib) | The app's modules (prerequisites, library index, pipeline, menu, banner) |
| [`tests/`](tests) | Pester tests |
| `install.ps1`, `install.cmd`, `uninstall.ps1`, `uninstall.cmd` | Installer and uninstaller |
| [`Kindle-DeDRM-Guide.md`](Kindle-DeDRM-Guide.md) | Manual step-by-step guide (the process the app automates) |
| [`docs/superpowers/`](docs/superpowers) | Design spec and implementation plan |

Run the tests with `Invoke-Pester .\tests` (Pester 3.4, included with Windows).

## Notes

- This repository contains no DRM-removal tools or keys. The app downloads Satsuoni's DeDRM tools and the Calibre plugins from their upstream releases, and checks each download against its published checksum.
- Use it only for books you've bought, for personal backup. Removing DRM isn't legal in every country, so check your local law.
