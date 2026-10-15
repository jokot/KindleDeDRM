# kindle-dedrm

A command-line tool for Windows 11 that turns Kindle books you own into DRM-free EPUB files.

```
Kindle for Windows ──► MSIXKFXArchiver ──► Calibre (DeDRM + KFX Input) ──► EPUB
   (downloads)          (extract + decrypt)     (import, convert)           (export)
```

It's a single PowerShell 5.1 script (included with Windows), with nothing else to install first.

## Usage

```
kindle-dedrm check        1. show requirements and what is installed
kindle-dedrm install      2. install what is missing, one component at a time
kindle-dedrm prepare      3. check your downloaded books before converting
kindle-dedrm convert      4. extract, remove DRM, convert to EPUB, export
kindle-dedrm clean        delete the extractor's temporary files
kindle-dedrm help
```

Run it from this folder, or add the folder to your `PATH`. `kindle-dedrm.cmd` starts the script with `-ExecutionPolicy Bypass`, so no PowerShell policy changes are needed.

Options:

| Option | Default | Meaning |
|---|---|---|
| `-OutDir <path>` | `Documents\Kindle EPUBs` | Where EPUBs are exported |
| `-Library <path>` | `~\Calibre Library` | Calibre library to import into |
| `-StallSeconds <n>` | `300` | Skip a book whose extraction hangs this long |
| `-Yes` | | Answer yes to every prompt |
| `-Force` | | Reinstall components that are already installed |

## 1. Requirements

| Component | Version | Source | `install` name |
|---|---|---|---|
| Windows 11 | build 22000+ | | |
| Microsoft Visual C++ runtime x64 | 14.20+ | <https://aka.ms/vs/17/release/vc_redist.x64.exe> | `vcredist` |
| Calibre | 9.16.0 (minimum 6.0) | <https://github.com/kovidgoyal/calibre/releases/tag/v9.16.0> | `calibre` |
| Kindle for Windows | 1.0.25218 (tested) | Microsoft Store, ID `9P8JQ0JJSTLL` | `kindle` |
| DeDRM tools (Satsuoni) | v10.0.32 | <https://github.com/Satsuoni/DeDRM_tools/releases/tag/v10.0.32> | `dedrm-tools` |
| DeDRM Calibre plugin | 10.0.32 | `DeDRM_plugin.zip` inside the DeDRM tools | `dedrm-plugin` |
| KFX Input Calibre plugin | 2.34.2+ | <https://plugins.calibre-ebook.com/291290.zip> | `kfx-input` |

**The extractor must match your Kindle build exactly.** For example, `MSIXKFXArchiver_x64_1_25218.exe` works only with Kindle 1.0.25218. `check` shows whether yours matches.

## 2. Install

```
kindle-dedrm install                    # everything, asking before each step
kindle-dedrm install calibre kfx-input  # only these components
kindle-dedrm install store-updates-off  # optional: stop Store app auto-updates
```

For each component, the tool explains why it's needed and where it comes from, then asks before installing. If you answer no, it prints the steps to do it yourself.

- **Downloads are verified.**
  - GitHub downloads (Calibre, DeDRM tools) are checked against the SHA-256 that GitHub publishes.
  - The VC++ installer is checked for a valid Microsoft signature.
- **Some steps need admin rights.** Calibre, the VC++ runtime and the Store policy change each show a Windows admin prompt.
- **Kindle is installed with winget.** If winget isn't available, the tool opens the Microsoft Store page instead.

`store-updates-off` sets the policy that turns off automatic updates for **all** Microsoft Store apps. It stops Kindle from updating to a build that no extractor supports yet. `store-updates-on` undoes it.

## 3. Prepare

1. Open Kindle, sign in, and download your books **a few at a time**. Bulk downloads can be missing images.
2. Open each new book once and page to the end.
3. Run `kindle-dedrm prepare`. It lists:
   - books that are ready to convert,
   - books already extracted by an earlier run,
   - incomplete downloads, which have no `.azw` file.

## 4. Convert

`kindle-dedrm convert`:

1. Closes Kindle and Calibre, asking you first.
2. Runs the extractor on every downloaded book. Output goes to `%LOCALAPPDATA%\kindle-dedrm\work\archived_kfx`.
   - If a book hangs for `-StallSeconds`, it's skipped and the remaining books continue.
   - Books extracted in earlier runs are skipped.
3. Imports new books into Calibre. Books are matched by Amazon ASIN, so books already in the library are skipped even if you've edited their title or author. DeDRM runs during import, and any book that stays KFX-ZIP is reported.
4. Converts every KFX book that doesn't have an EPUB yet, adds the EPUB to the library, and exports it to `-OutDir`.

You can run it again whenever you buy new books. Only new books are processed.

## Files

| Path | Contents |
|---|---|
| `%LOCALAPPDATA%\kindle-dedrm\downloads` | Downloaded installers and zips |
| `%LOCALAPPDATA%\kindle-dedrm\tools\<tag>` | Unpacked DeDRM tools |
| `%LOCALAPPDATA%\kindle-dedrm\work\archived_kfx` | Extracted books (`.kfx-zip`) |
| `%LOCALAPPDATA%\kindle-dedrm\work\*.k4i`, `*.keyfile` | **Your book keys. Keep them private.** |
| `%LOCALAPPDATA%\kindle-dedrm\work\logs` | Extractor and conversion logs |
| `C:\Data` | Extractor temp folder, about 400 MB (`clean` removes it) |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `check` shows "Extractor for your Kindle: none for build N" | Kindle updated past the supported build. Check Satsuoni's releases for a matching extractor, then update `DeDrmTag` at the top of the script and run `install dedrm-tools dedrm-plugin -Force`. |
| A book "hung and was skipped" | In Kindle, choose Remove download, download it again, open it, then run `convert` again. |
| A book is reported as "imported as KFX-ZIP" | DRM wasn't removed. Delete the book in Calibre, download it again in Kindle, then run `convert` again. |
| `VCRUNTIME140_1.dll was not found` | Run `kindle-dedrm install vcredist`. |
| Help with DRM issues | <https://github.com/Satsuoni/DeDRM_tools/discussions> |

## Updating versions

Versions are pinned in the `$Pinned` block at the top of `kindle-dedrm.ps1`. Change them there when new releases come out.

---

Use this only for books you have bought, for personal backup. Removing DRM is not legal in every country, so check your local law.
