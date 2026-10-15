# KindleDeDRM app: design

- **Date:** 2026-10-15
- **Status:** approved in chat. Waiting for review of this written spec.
- **Replaces:** `kindle-dedrm/` (the single-script command-line tool)

## 1. Purpose

Make the existing `kindle-dedrm` command-line tool into one app called **KindleDeDRM**. You install it once and then start it from any terminal with `KindleDeDRM`. It works much like KindleFetch: a menu leads you through:

1. checking the prerequisites,
2. installing the prerequisites,
3. removing DRM: searching your books, then converting them.

**Who it's for:** one person on Windows 11 making personal backups of Kindle books they have bought. It uses the pipeline that has already been proven on this PC:

> Kindle for Windows 1.0.25218 → Satsuoni `MSIXKFXArchiver` → Calibre 9.16.0 (DeDRM 10.0.32 + KFX Input 2.34.2) → EPUB

**Success means:**

- After running `install.cmd` once, `KindleDeDRM` opens the menu from any new terminal, and the app also appears in the Start menu.
- Every task can be done from the menu, with no need to remember commands.
- You can search across all your books: books downloaded in Kindle and books already in Calibre. You can pick some of them and convert, re-convert or re-export just those.
- Existing data in `%LOCALAPPDATA%\kindle-dedrm\` (27 extracted books, their keys and logs) keeps working with no migration.
- The old commands (`check`, `install [parts]`, `convert`, `clean`) still work as command-line arguments, so they can be scripted.

### Decisions made in the design discussion

| Topic | Decision |
|---|---|
| What search covers | Downloaded books **and** books already converted in Calibre |
| How it's packaged | A setup script (`install.cmd`). It stays PowerShell 5.1: no .exe, no rewrite |
| How the menu works | Numbered menus. Books are picked by typing `1,3`, `2-5`, `all` or `new` |
| Overall approach | Split the code into focused files plus an installer (approach A) |

## 2. Out of scope

- Downloading books from Amazon. There is no API for this, so books must still be downloaded in the Kindle app.
- An arrow-key or full-screen terminal interface.
- Building a single `.exe`.
- macOS, Windows 10, or Kindle for PC 2.x.
- Removing DRM from anything other than Kindle for Windows books.

## 3. Install and launch

### `install.cmd`

1. Copies `KindleDeDRM.cmd`, `KindleDeDRM.ps1`, `lib\`, and `README.md` to `%LOCALAPPDATA%\Programs\KindleDeDRM\`, overwriting anything already there. Running it again updates the app in place.
2. Adds that folder to the **user** `PATH` if it isn't there yet. Because it's the user PATH, no admin rights are needed. The change is written with `[Environment]::SetEnvironmentVariable(..., 'User')`.
3. Creates the Start-menu shortcut `%APPDATA%\Microsoft\Windows\Start Menu\Programs\KindleDeDRM.lnk`. The shortcut runs `powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "<install dir>\KindleDeDRM.ps1"`.
4. Prints "Installed. Open a new terminal and run: KindleDeDRM".

`install.cmd` only launches PowerShell. The actual work is done in `install.ps1`, which sits next to it.

### `uninstall.cmd`

Removes the install folder, the PATH entry, and the shortcut. It **never** touches:

- `%LOCALAPPDATA%\kindle-dedrm\` (your extracted books, keys, settings and title list),
- the Calibre library,
- Calibre itself or Kindle.

### Launching

| Command | Result |
|---|---|
| `KindleDeDRM` | Opens the interactive menu |
| `KindleDeDRM check` | Prints the requirements table and exits |
| `KindleDeDRM install [parts…] [-Yes] [-Force]` | Same as the current `install` command |
| `KindleDeDRM convert [-Yes]` | Converts every new book without asking which ones, then exits |
| `KindleDeDRM clean` | Same as the current `clean` command |
| `KindleDeDRM help` | Prints usage |

`KindleDeDRM.cmd` contains `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0KindleDeDRM.ps1" %*`.

## 4. Main menu

```
  KindleDeDRM 1.0          Kindle 1.0.25218  ·  27 books  ·  all prerequisites OK
  ------------------------------------------------------------
  1) Check prerequisites
  2) Install prerequisites
  3) DeDRM books
  4) Settings
  5) Clean temp files
  0) Exit
  >
```

- **Status line:** worked out each time the menu is shown. When something is missing it reads `N missing – choose 2`.
- **1) Check prerequisites:** shows the requirements table (same contents as today's `check`).
- **2) Install prerequisites:** lists only what's missing, numbered, plus `a) install all missing`. Each item explains why it's needed, says where it comes from, and asks Y/n, then installs exactly as today's installers do. If nothing is missing, it says so and offers `f) force reinstall a part` and `s) Store auto-updates off/on`.
- **3) DeDRM books:** see section 5. If a requirement is missing, it names the missing items and tells you to use menu 2 instead of starting.
- **4) Settings:** change the EPUB output folder, the Calibre library folder, or the stall timeout, and turn Store auto-updates off or on. Settings are saved to `%LOCALAPPDATA%\kindle-dedrm\settings.json`.
- **5) Clean temp files:** same as today's `clean`.
- After each action you're asked to "Press Enter to return to the menu". An invalid choice shows the menu again with a short hint.

## 5. DeDRM books (menu 3)

### 5.1 Book list

Built by `Get-BookIndex` in `lib\Library.ps1`. It combines records from three sources, matched on **ASIN**:

| Source | Fields it supplies |
|---|---|
| Kindle content folder (`…\LocalState\Classic\Content\*_EBOK`) | `Asin`, `Downloaded = $true`, `Complete` (the `<ASIN>_EBOK.azw` file exists), `KindlePath` |
| `%LOCALAPPDATA%\kindle-dedrm\work\archived_kfx\*.kfx-zip` | `Extracted = $true`, `KfxZipPath` |
| `%LOCALAPPDATA%\kindle-dedrm\index.json` | `Title`, `Authors`, cached from `ebook-meta` on the `.kfx-zip` |
| Calibre (`calibredb list --fields title,authors,formats,identifiers --for-machine`) | `CalibreId`, `Title`, `Authors`, `HasKfx`, `HasEpub`, `EpubPath`, read from the `mobi-asin` identifier |

**Title and author:** taken from Calibre first (so any edits you made there show up), then from `index.json`, and finally the ASIN is used if neither has one.

**Status:** the first rule that matches, checked in this order:

| Status | Condition | Sort order |
|---|---|---|
| `incomplete` | Downloaded, but no `.azw` file | 1 |
| `new` | Downloaded and complete, but not extracted | 2 |
| `extracted` | Extracted, but not in Calibre | 3 |
| `in Calibre` | In Calibre with KFX, but no EPUB | 4 |
| `EPUB done` | In Calibre with an EPUB, and still downloaded | 5 |
| `not downloaded` | In Calibre, but no longer downloaded in Kindle | 6 |

### 5.2 Flow

1. **Refresh** (runs when you open menu 3; press `s` to skip it):
   - If Kindle is running, asks to close it.
   - Runs the extractor for `new` books only. The stall watchdog is unchanged from today's tool.
   - Runs `ebook-meta` on each `.kfx-zip` that isn't in `index.json` yet, about 2 s per book. Each result is saved to `index.json` straight away.
   - When there are no new books, refresh does nothing and returns quickly.
2. **Search:** `Search (title/author, blank = all):`. This is a case-insensitive substring match on the title or any author. Results are sorted by status order, then title.
3. **List:** shows the matching books in columns `#`, `Title`, `Author`, `Status`. Titles are cut to the console width.
4. **Pick:** `Pick books (e.g. 1,3  2-5  all  new; blank = new search):`. Ranges that are out of bounds or malformed show an error and ask again.
5. **Action** for the picked books:
   - `1) Convert` (the default): does whatever each book still needs (extract → import → EPUB → export) and skips steps already done. `incomplete` books are skipped, with a reminder to download them again in Kindle.
   - `2) Re-convert`: needs `CalibreId` and `HasKfx`. Rebuilds the EPUB from the KFX, replaces the EPUB stored in Calibre, and overwrites the exported file.
   - `3) Re-export`: needs `HasEpub`. Exports the EPUB again, overwriting the old copy.
   - `4) Open folder`: opens Explorer with the exported EPUB selected, or the Calibre book folder if there is no exported EPUB.
   - `0) Back`
6. **Result:** one line per book (`ok`, or `FAILED – <log path>`), then the list is redrawn with updated statuses for the same search.

## 6. Code layout

The repo folder is `KindleDeDRM/`. It replaces `kindle-dedrm/`.

| File | Responsibility | Depends on |
|---|---|---|
| `KindleDeDRM.cmd` | PATH launcher | – |
| `KindleDeDRM.ps1` | Parses arguments, loads `lib\*.ps1`, sends commands to their handlers or starts the menu loop | all of `lib` |
| `lib\Config.ps1` | `$Pinned` versions, URLs, paths, `Get-Settings` and `Save-Settings` | – |
| `lib\Ui.ps1` | `Say/Step/Ok/Warn/Fail`, `Confirm-Step`, `Read-MenuChoice`, `Format-Table`-style printing, `ConvertFrom-Selection` (parses `1,3 2-5 all new`) | – |
| `lib\Native.ps1` | `Invoke-Native`, `Invoke-Elevated`, `Save-File`, `Save-GitHubAsset` (SHA-256 check), `Stop-AppIfRunning` | Ui |
| `lib\Prereqs.ps1` | Detects requirements (`Get-Requirements`, `Find-Archiver`, …), `$Components`, `Install-*`, `Set-StoreAutoUpdate` | Native, Config |
| `lib\Library.ps1` | `Get-KindleBooks`, `Get-LibraryBooks`, `Update-TitleIndex`, `Merge-BookIndex` (pure function), `Get-BookIndex`, `Find-Books` | Native, Config |
| `lib\Pipeline.ps1` | `Invoke-Archiver` (watchdog), `Import-Books -Asin`, `Convert-Books -CalibreId [-Replace]`, `Export-Epubs -CalibreId [-Overwrite]`, `Invoke-Clean` | Native, Library |
| `install.cmd`, `install.ps1`, `uninstall.cmd`, `uninstall.ps1` | Install and uninstall | – |
| `README.md` | Usage notes | – |
| `tests\*.Tests.ps1` | Pester tests | lib |

Rules:

- Keep each file under about 300 lines.
- `Merge-BookIndex` and `ConvertFrom-Selection` must be pure functions, with no file or process access, so they can be unit-tested.
- All code must be compatible with PowerShell 5.1 and ASCII-only.

### Data files

All data files live in `%LOCALAPPDATA%\kindle-dedrm\`, the same place as today.

| File | Contents |
|---|---|
| `settings.json` | `{ "OutDir": "...", "Library": "...", "StallSeconds": 300 }`. Defaults are used for any missing key. |
| `index.json` | `{ "<ASIN>": { "Title": "...", "Authors": ["..."] } }` |
| `work\`, `tools\`, `downloads\` | Unchanged |

### Changes to existing behavior

- `Import-Books`, `Convert-Books` and `Export-Epubs` take an optional list of ASINs or Calibre IDs. When they're called without one (as by the command-line `convert`), they keep today's behavior of handling all new books.
- **Export overwrite:** delete the target `Title - Author.epub` before running `calibredb export`, so the file is replaced and not saved under a new name.
- **Re-convert:** after `ebook-convert`, run `calibredb add_format` with `--replace` (the default) so Calibre's EPUB is replaced.

## 7. Error handling

- Each menu action runs inside try/catch. On an error it prints `Error: <message>`, waits for Enter, and goes back to the menu.
- Before menu 3 starts, it checks the requirements and lists any that are missing.
- If one book fails, the rest of the batch still runs. Failures are listed with their log paths, and logs go in `work\logs\` (unchanged).
- If `settings.json` or `index.json` is corrupt, it prints a warning, renames the bad file to `*.bad`, and carries on with defaults or rebuilds the index.
- Running from the command line exits with code 1 on error (unchanged).
- Calibre and Kindle are only closed after you confirm, unless `-Yes` is used.

## 8. Testing

**Pester unit tests:** they use Pester 3.4, which comes with Windows, so nothing needs installing. Tests are run with `Invoke-Pester .\tests`.

- `ConvertFrom-Selection`:
  - single numbers, lists and ranges
  - `all` and `new`
  - extra spaces
  - out-of-range numbers and garbage input, which must produce errors
- `Merge-BookIndex`, using made-up Kindle, archive, index and Calibre records:
  - every status in section 5.1 is assigned correctly
  - Calibre's title takes priority over `index.json`
  - books with no title fall back to the ASIN
- `Find-Books`: case-insensitive matching on title or author, plus status and title sort order.
- `Get-Settings` and `Save-Settings`: a full round trip, a file with missing keys, and a corrupt file.
- `Find-Archiver` build matching: works with a fake tools folder.

**Manual checks on this PC:**

1. `install.cmd`, then in a new terminal `KindleDeDRM` opens the menu. The Start-menu shortcut also works.
2. Menu 1 shows everything as OK.
3. Menu 2 reports that nothing is missing.
4. Menu 3: search for "orwell", pick `1`, Re-convert. The EPUB in `Kindle EPUBs` is replaced (its timestamp changes) and no duplicate file appears.
5. Menu 3: Re-export one book, and the file is overwritten.
6. Menu 3: blank search lists all 27 books with correct statuses.
7. `KindleDeDRM convert -Yes` ends with "nothing new".
8. `uninstall.cmd` removes the PATH entry and the shortcut, and `%LOCALAPPDATA%\kindle-dedrm\` is still there.

## 9. Migration

- `kindle-dedrm/` is removed from the repo once `KindleDeDRM/` works.
- No data migration is needed, because the data folder is the same.
- `index.json` is filled in automatically the first time menu 3 runs: 27 books × about 2 s.
