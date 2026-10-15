# KindleDeDRM App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to carry out this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the single-file `kindle-dedrm/kindle-dedrm.ps1` command-line tool into an app called **KindleDeDRM**. It is installed once, launched as `KindleDeDRM`, and offers a menu for: checking prerequisites, installing prerequisites, and DeDRM (search for books, then convert, re-convert or re-export them).

**Architecture:**
- The logic that already works moves out of `kindle-dedrm/kindle-dedrm.ps1` into focused `lib\*.ps1` files. Each file only defines functions.
- `KindleDeDRM.ps1` dot-sources them. With no arguments it starts a numbered-menu loop. With arguments it runs a single command.
- A per-user installer copies the app to `%LOCALAPPDATA%\Programs\KindleDeDRM`, adds that folder to the user PATH, and adds a Start-menu shortcut.

**Tech Stack:** Windows PowerShell 5.1 and Pester 3.4.0 (both included with Windows). External tools used: Calibre CLI (`calibredb`, `ebook-convert`, `ebook-meta`, `calibre-customize`), Satsuoni's `MSIXKFXArchiver`, and winget.

**Spec:** `docs/superpowers/specs/2026-10-15-kindlededrm-app-design.md`

**Source being ported:** `kindle-dedrm/kindle-dedrm.ps1`. "Port X" below means: move that function's body over, keep its behavior, and change only what the step says.

## Global Constraints

- PowerShell 5.1 only. Do not use `??`, `?.`, ternaries, `&&`, `||`, or `-Parallel`.
- Every `.ps1` and `.cmd` file must be **ASCII-only**, because PS 5.1 reads files without a BOM as ANSI.
- Keep each file under about 300 lines.
- Pester 3.4 syntax only: `Should Be`, `Should BeExactly`, `Should Throw`, `Should Match`, `Should BeNullOrEmpty`. Do not use the `-Be` dash syntax.
- Data folder: `%LOCALAPPDATA%\kindle-dedrm\` (unchanged). Install folder: `%LOCALAPPDATA%\Programs\KindleDeDRM\`.
- Pinned versions: Calibre `9.16.0`, DeDRM tag `v10.0.32`, Kindle build `25218`, KFX Input `2.34.2`. Kindle Store ID `9P8JQ0JJSTLL`.
- Calibre and Kindle may only be closed after the user confirms, unless `-Yes` is given.
- Never use `Remove-Item -Recurse` on a folder that may contain junctions. Junctions are removed with `DirectoryInfo.Delete()` (as `Reset-JunctionDir` already does).
- From the command line, an error exits with code 1. In the menu, an error prints `Error: <msg>`, waits for Enter, and returns to the menu.

## Decisions this plan adds to the spec

- **Menu code** goes in a new file, `lib\Menu.ps1`, so that `KindleDeDRM.ps1` stays small. `KindleDeDRM.ps1` only parses arguments and dispatches.
- **Export overwrite:** `calibredb export` names files after its own template (for example "Best Minds, The - …"), so the exported file name can't be predicted in advance. Instead, `Export-Epubs` exports **one book at a time** into a fresh temporary folder and then uses `Move-Item -Force` to move that file into `OutDir`. It returns the final path for each book, and that path is saved in `index.json` as `Exported`, which "Open folder" uses.
- **Author format:** `index.json` stores `Authors` as one string joined with ` & `, the same format `calibredb --for-machine` uses. It does not store an array.
- **Books without an ASIN:** Calibre books that have no `mobi-asin` identifier are still listed. Their `Asin` is `$null` and their status is `not downloaded`.
- **PATH editing** is done by pure functions in `lib\Setup.ps1` so it can be tested.

## Review Focus

1. **Running `install.cmd` twice:** PATH must not end up with a duplicate entry, and an entry that differs only in letter case or a trailing `\` counts as the same → tested in Task 9.
2. **Calibre books with no ASIN**, and empty sources (no Kindle downloads, no `metadata.db`): menu 3 shows them or says "no books" and does not crash → tested in Task 4.
3. **Choosing `new` when there are no new books**, or typing a reversed range like `5-2`: the user gets a clear message, not an empty batch run or a silent no-op → tested in Task 2.
4. **Titles with non-ASCII characters** (for example "Saint-Exupéry") must survive `calibredb` JSON and `ebook-meta` output → `[Console]::OutputEncoding` and `PYTHONIOENCODING` must be set before any native call. This is checked manually in Task 10.
5. **Re-convert or re-export when a file with that name already exists in `OutDir`:** the file is overwritten, not saved as a duplicate with a suffix → verified in Task 5, Step 2.

## File Structure

```
KindleDeDRM/
  KindleDeDRM.cmd          launcher on PATH
  KindleDeDRM.ps1          param parsing, loads lib, CLI dispatch or Start-MainMenu
  install.cmd / install.ps1
  uninstall.cmd / uninstall.ps1
  README.md
  lib/
    Config.ps1      pinned versions, paths, Get-Settings/Save-Settings
    Ui.ps1          Say/Step/Ok/Warn/Fail, Confirm-Step, Read-MenuChoice, Write-BookTable, ConvertFrom-Selection
    Native.ps1      Invoke-Native, Invoke-Elevated, Save-File, Save-GitHubAsset, Stop-AppIfRunning
    Prereqs.ps1     detection, $Components, Install-*, Set-StoreAutoUpdate, Show-Requirements
    Library.ps1     Get-KindleBooks, Get-LibraryBooks, Read/Save-TitleIndex, Update-TitleIndex, Merge-BookIndex, Get-BookIndex, Find-Books
    Pipeline.ps1    Reset-JunctionDir, Invoke-Archiver, Import-Books, Convert-Books, Export-Epubs, Invoke-BookAction, Invoke-Clean
    Menu.ps1        Start-MainMenu, Show-PrereqMenu, Show-SettingsMenu, Show-BooksMenu
    Setup.ps1       Add-PathEntry, Remove-PathEntry (pure)
  tests/
    Config.Tests.ps1  Ui.Tests.ps1  Prereqs.Tests.ps1  Library.Tests.ps1  Setup.Tests.ps1
```

Every test file starts like this:

```powershell
$lib = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\lib'
. "$lib\Config.ps1"; . "$lib\Ui.ps1"   # plus the file under test and its deps
```

Run all tests with `powershell -NoProfile -Command "Invoke-Pester .\KindleDeDRM\tests"`.

---

### Task 1: Config and settings

**Files:**
- Create: `KindleDeDRM/lib/Config.ps1`
- Test: `KindleDeDRM/tests/Config.Tests.ps1`

**Interfaces:**
- Produces:
  - Variables: `$AppVersion = '1.0'`, `$Pinned` (the hashtable from the old script, unchanged), `$DeDrmRepo`, `$KindleStoreId`, `$KindlePkgName`, `$KfxInputUrl`, `$VcRedistUrl`, `$StorePolicy`, `$AppDir`, `$DownloadDir`, `$ToolsDir`, `$WorkDir`, `$ArchiveDir`, `$CalibreDir`, `$Calibredb`, `$SettingsPath = "$AppDir\settings.json"`, `$IndexPath = "$AppDir\index.json"`.
  - `Get-Settings [-Path <string>] -> pscustomobject @{ OutDir; Library; StallSeconds }`
  - `Save-Settings -Settings <pscustomobject> [-Path <string>]`
  - `Get-DefaultSettings -> pscustomobject`: OutDir `"$env:USERPROFILE\Documents\Kindle EPUBs"`, Library `"$env:USERPROFILE\Calibre Library"`, StallSeconds `300`.

- [ ] **Step 1: Write failing tests in `Config.Tests.ps1`**
  - `Get-Settings returns defaults when file missing`: `(Get-Settings -Path TestDrive:\none.json).StallSeconds | Should Be 300`.
  - `Save then Get round-trips`: save OutDir `C:\x`, StallSeconds `60`, then read them back.
  - `fills missing keys with defaults`: the file contains `{"OutDir":"C:\\y"}`, so OutDir is `C:\y` and Library is the default.
  - `corrupt file is renamed to .bad and defaults returned`: the file contains `{nope`. Afterwards `Test-Path "$path.bad"` is `$true`, and StallSeconds is 300.
- [ ] **Step 2:** Run `Invoke-Pester .\KindleDeDRM\tests\Config.Tests.ps1`. Expected: FAIL (`Get-Settings` not recognized).
- [ ] **Step 3: Implement `lib\Config.ps1`.** Copy the constants and path variables from the old script lines 27-50. On corrupt JSON, `Get-Settings` calls `Warn` only if it is defined (`Get-Command Warn -ErrorAction SilentlyContinue`), so that Config has no dependencies. `Save-Settings` writes `ConvertTo-Json` and creates the parent folder.
- [ ] **Step 4:** Run the tests again. Expected: 4 passed.
- [ ] **Step 5:** `git add KindleDeDRM/lib/Config.ps1 KindleDeDRM/tests/Config.Tests.ps1; git commit -m "feat(app): config and persisted settings"`

### Task 2: UI helpers and selection parser

**Files:**
- Create: `KindleDeDRM/lib/Ui.ps1`
- Test: `KindleDeDRM/tests/Ui.Tests.ps1`

**Interfaces:**
- Produces:
  - `Say`, `Step`, `Ok`, `Warn`, `Fail`, `Show-Value`: ported unchanged.
  - `Confirm-Step($question) -> bool`: uses `$script:AssumeYes` in place of `$Yes`.
  - `Read-MenuChoice -Prompt <string> -Valid <string[]> -> string`: loops until the input (trimmed, lower-case) is in `-Valid`. After a bad input it prints `  Choose one of: <valid>`.
  - `Write-BookTable -Books <obj[]>`: prints `#`, `Title`, `Author`, `Status`. Title and author are truncated with `~` to fit `[Console]::WindowWidth` (use 100 if that throws).
  - `ConvertFrom-Selection -Text <string> -Count <int> [-NewIndexes <int[]>] -> int[]`: returns 1-based numbers, unique and ascending. Blank text returns `@()`. Invalid input throws.

- [ ] **Step 1: Write failing tests for `ConvertFrom-Selection`**
  - `'1,3'` with Count 5 → `1,3`
  - `'2-5'` → `2,3,4,5`
  - `' 1 , 2-3 '` → `1,2,3`
  - `'3,1,3'` → `1,3`
  - `'ALL'` with Count 4 → `1..4`
  - `'new'` with NewIndexes `2,4` → `2,4`
  - `''` → count 0
  - These must throw:
    - `'0'` throws `*out of range*`
    - `'6'` with Count 5 throws `*out of range*`
    - `'abc'` throws `*not understood*`
    - `'5-2'` throws `*reversed*`
    - `'new'` with empty NewIndexes throws `*no new books*`

  Compare arrays with `($r -join ',') | Should Be '1,3'`.
- [ ] **Step 2:** Run `Invoke-Pester .\KindleDeDRM\tests\Ui.Tests.ps1`. Expected: FAIL.
- [ ] **Step 3:** Implement `lib\Ui.ps1`. Port the output helpers from the old lines 55-66. In the parser, split on `,`, then match each part against `^\d+$` or `^(\d+)-(\d+)$`.
- [ ] **Step 4:** Run the tests again. Expected: 12 passed.
- [ ] **Step 5:** `git commit -m "feat(app): ui helpers and selection parser"` (stage both files).

### Task 3: Native helpers and prerequisites

**Files:**
- Create: `KindleDeDRM/lib/Native.ps1`, `KindleDeDRM/lib/Prereqs.ps1`
- Test: `KindleDeDRM/tests/Prereqs.Tests.ps1`

**Interfaces:**
- Consumes: Config variables and Ui helpers.
- Produces:
  - `Native.ps1`: port `Invoke-Native`, `Invoke-Elevated`, `Stop-AppIfRunning`, `Save-File` and `Save-GitHubAsset` unchanged.
  - `Prereqs.ps1`:
    - Port `Get-WindowsBuild`, `Get-VcRedistVersion`, `Get-KindlePackage`, `Get-KindleBuild`, `Get-KindleContentDir`, `Get-CalibreVersion`, `Get-CalibrePlugins` (keeping `$script:PluginCache`), `Test-StoreUpdatesOff`, `Get-Requirements`, `$Components`, `$RequirementFor`, every `Install-*`, `Set-StoreAutoUpdate`, `Show-Requirements` and `Invoke-Install`.
    - **Changed signature:** `Find-Archiver [-Build <int>] [-Dir <string>] -> FileInfo|$null`. The defaults are `(Get-KindleBuild)` and `$ToolsDir`.
    - **New:** `Get-MissingRequirements -> obj[]`, the requirements where `-not Ok -and Component -ne '-'`.
    - In `Show-Requirements`, change the "Next:" hint text to `choose 2) Install prerequisites (or: KindleDeDRM install <parts>)`.

- [ ] **Step 1: Write failing tests**
  - In `TestDrive:\tools`, create the empty files `MSIXKFXArchiver_x64_1_25218.exe` and `MSIXKFXArchiver1_23620_final.exe`.
  - `Find-Archiver -Build 25218 -Dir TestDrive:\tools` → Name `MSIXKFXArchiver_x64_1_25218.exe`
  - `-Build 23620` → Name `MSIXKFXArchiver1_23620_final.exe`
  - `-Build 2521` → `$null`, so a partial build number must not match
  - `-Build 99999` → `$null`
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Port the code into the two files as listed under Interfaces.
- [ ] **Step 4:** Run the tests again. Expected: 4 passed. Then run this smoke check:
  ```
  powershell -NoProfile -Command ". .\KindleDeDRM\lib\Config.ps1; . .\KindleDeDRM\lib\Ui.ps1; . .\KindleDeDRM\lib\Native.ps1; . .\KindleDeDRM\lib\Prereqs.ps1; Show-Requirements"
  ```
  Expected: every row says OK (this PC already has everything installed).
- [ ] **Step 5:** `git commit -m "feat(app): native helpers and prerequisites module"`

### Task 4: Book index (merge, titles, search)

**Files:**
- Create: `KindleDeDRM/lib/Library.ps1`
- Test: `KindleDeDRM/tests/Library.Tests.ps1`

**Interfaces:**
- Consumes: `Invoke-Native`, `Get-KindleContentDir`, `$ArchiveDir`, `$IndexPath`, `$Calibredb`, `$CalibreDir`.
- Produces:
  - `Get-KindleBooks`: ported unchanged. Outputs `Name`, `Asin`, `FullName`, `Complete`, `SizeMB`.
  - `Get-LibraryBooks -Library <string>`: ported, with `title,authors,formats,identifiers`.
  - `Read-TitleIndex [-Path] -> hashtable` (ASIN → `@{Title; Authors; Exported}`). A missing file gives `@{}`. A corrupt file is renamed to `.bad` and gives `@{}`.
  - `Save-TitleIndex -Index <hashtable> [-Path]`.
  - `Update-TitleIndex -Index <hashtable> -Asins <string[]>`: runs `ebook-meta.exe` on `$ArchiveDir\<asin>_EBOK.kfx-zip` for each ASIN that has no entry yet. It parses `^Title\s*:\s*(.+)$` and `^Author\(s\)\s*:\s*(.+?)(\s*\[.*\])?$`, saves after each book, and prints `  reading titles i/n`.
  - `Merge-BookIndex -Kindle <obj[]> -Extracted <hashtable asin->path> -Titles <hashtable> -Calibre <obj[]> -> obj[]`. This function is **pure**. Each output record has:
    `Key` (the ASIN, or `"calibre:<id>"`), `Asin`, `Title`, `Authors`, `Status`, `StatusOrder`, `Downloaded`, `Complete`, `KindlePath`, `Extracted`, `KfxZipPath`, `CalibreId`, `HasKfx`, `HasEpub`, `KfxPath`, `EpubPath`, `Exported`.
    - Status rules and order (incomplete=1 … not downloaded=6) are exactly as in spec section 5.1.
    - Title: Calibre's title, then `Titles[asin].Title`, then the ASIN.
  - `Get-BookIndex -Library <string> -> obj[]`: gathers the four sources and calls `Merge-BookIndex`.
  - `Find-Books -Books <obj[]> [-Query <string>] -> obj[]`: a case-insensitive substring match on Title or Authors, sorted by StatusOrder and then Title.

- [ ] **Step 1: Write failing tests for `Merge-BookIndex` and `Find-Books`.** Build fixtures with `[pscustomobject]`. The Calibre fixture has the shape `@{id=1; title='T'; authors='A'; formats=@('x.kfx','x.epub'); identifiers=@{'mobi-asin'='B1'}}`. Tests:
  - Six status tests, one per row of the spec table:
    - B1 downloaded without `.azw` → `incomplete`
    - B2 complete, not extracted → `new`
    - B3 extracted, no Calibre → `extracted`
    - B4 in Calibre with KFX only → `in Calibre`
    - B5 KFX and EPUB and downloaded → `EPUB done`
    - B6 in Calibre but not in Kindle → `not downloaded`
  - `Calibre title wins over index title`
  - `falls back to ASIN when no title`
  - `Calibre book without mobi-asin gets Key calibre:<id> and status not downloaded`
  - `empty inputs return empty array` (`@(Merge-BookIndex ...).Count | Should Be 0`)
  - `Find-Books 'ORWELL' matches author case-insensitively`
  - `Find-Books blank returns all sorted new before EPUB done`
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `lib\Library.ps1`. Build the Merge result in an ordered hashtable keyed by `Key`, filling it from Kindle, then Extracted, then Calibre. Work out each record's status last.
- [ ] **Step 4:** Run the tests again. Expected: 12 passed. Then a live smoke check: dot-source Config, Ui, Native, Prereqs and Library, run `$i = Read-TitleIndex; Update-TitleIndex -Index $i -Asins (Get-KindleBooks).Asin`, then `(Get-BookIndex -Library "$env:USERPROFILE\Calibre Library").Count`. Expected: `27`, and `index.json` holds 27 entries.
- [ ] **Step 5:** `git commit -m "feat(app): merged book index with search"`

### Task 5: Pipeline with per-book selection

**Files:**
- Create: `KindleDeDRM/lib/Pipeline.ps1`
- Test: `KindleDeDRM/tests/Pipeline.Tests.ps1`

**Interfaces:**
- Consumes: Native, Prereqs (`Find-Archiver`), Library (records from `Get-BookIndex`, plus `Read/Save/Update-TitleIndex`).
- Produces:
  - `Reset-JunctionDir`: ported.
  - `Invoke-Archiver -Archiver <FileInfo> -Books <obj[]> -StallSeconds <int> -> string[]`: returns the Names of books it skipped. Ported. It extracts only the `-Books` given (Kindle records with `Name` and `FullName`), not every pending book.
  - `Import-Books -Library <string> -Asins <string[]> -> int[]`: imports `$ArchiveDir\<asin>_EBOK.kfx-zip` for the given ASINs and returns the new Calibre ids. The KFX-ZIP warning is kept.
  - `Convert-Books -Library <string> -CalibreIds <int[]> [-Replace] -> int[]`: converts the given ids. Without `-Replace`, ids that already have an EPUB are skipped. `add_format` replaces the stored EPUB.
  - `Export-Epubs -Library <string> -OutDir <string> -CalibreIds <int[]> -> hashtable id->path`. For **each id, one at a time**:
    1. Empty `"$WorkDir\export-tmp"`.
    2. Run `calibredb export <id> --formats epub --dont-save-cover --dont-write-opf --single-dir --to-dir <tmp>`. Keep Calibre's default naming so file names match the 27 files already exported.
    3. `Move-Item -Force` the single `*.epub` in that folder into OutDir.
    4. Record `id -> final path`.
  - `Invoke-BookAction -Books <obj[]> -Action <'Convert'|'Reconvert'|'Reexport'> -Settings <obj> -> obj[]`. It returns one `[pscustomobject]@{Title; Ok; Message}` per book.
    - **Convert:** extract the `new` ones, then `Update-TitleIndex`, then import the `extracted` ones, then convert, then export, then save `Exported` to the index.
    - **Reconvert:** requires `HasKfx` (otherwise `Ok=$false`, `Message='not in Calibre as KFX'`). Runs `Convert-Books -Replace`, then export.
    - **Reexport:** requires `HasEpub`. Runs export.
    - `incomplete` books return `Message='incomplete download - re-download in Kindle'`.
  - `Invoke-Clean`: ported.

This task has no pure logic to unit-test: it orchestrates external tools. It is verified against the real library instead.

- [ ] **Step 1:** Implement `lib\Pipeline.ps1` as described under Interfaces. The old `Invoke-Convert` flow becomes `Invoke-BookAction -Action Convert`.
- [ ] **Step 2: Verify the overwrite behavior (Review Focus 5).** Dot-source the libs and run `Invoke-BookAction -Books (Find-Books (Get-BookIndex -Library $lib) 'best minds') -Action Reconvert -Settings (Get-Settings)` **twice**. Use "best minds" because its exported name, `Best Minds, The - ...`, comes from Calibre's template.
  Expected: `ok` both times. `Kindle EPUBs` still holds exactly one `Best Minds*.epub` with a newer LastWriteTime, and there are still 27 EPUBs in total.
- [ ] **Step 3:** Run all tests. Expected: they pass.
- [ ] **Step 4:** `git commit -m "feat(app): pipeline with per-book convert, reconvert, reexport"`

### Task 6: Entry point and CLI commands

**Files:**
- Create: `KindleDeDRM/KindleDeDRM.ps1`, `KindleDeDRM/KindleDeDRM.cmd`

**Interfaces:**
- Consumes: every `lib` file; `Start-MainMenu` comes from Task 7.
- Produces:
  - Parameters: `[ValidateSet('','check','install','convert','clean','help')] $Command`, `$Component` (taking the remaining arguments), `$OutDir`, `$Library`, `$StallSeconds`, `-Yes`, `-Force`.
  - `$script:AssumeYes = [bool]$Yes`.
  - Settings come from `Get-Settings`. Any `-OutDir`, `-Library` or `-StallSeconds` given on the command line overrides them **for that run only** and is not saved.
  - Before dispatching, set `[Console]::OutputEncoding = UTF8` (inside try/catch) and `$env:PYTHONIOENCODING='utf-8'`.
  - Dispatch:
    - no command → `Start-MainMenu -Settings $s`
    - `check` → `Show-Requirements`
    - `install` → `Invoke-Install $Component`
    - `convert` → if `Get-MissingRequirements` is not empty, throw; otherwise run `Invoke-BookAction` with the books whose Status is `new`, `extracted` or `in Calibre`, using Action `Convert`, and print a summary
    - `clean` → `Invoke-Clean`
    - `help` → usage text, with the old command list plus a line saying "run with no arguments for the menu"
  - The whole dispatch is wrapped in try/catch, which prints `Error:` and then `exit 1`.
  - `KindleDeDRM.cmd` contains: `@echo off` followed by `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0KindleDeDRM.ps1" %*`

- [ ] **Step 1:** Create both files. Until Task 7 exists, `Start-MainMenu` is a stub in `KindleDeDRM.ps1` that says "menu coming in Task 7".
- [ ] **Step 2: Verify**
  - `.\KindleDeDRM\KindleDeDRM.cmd check`: the table appears and every row is OK.
  - `.\KindleDeDRM\KindleDeDRM.cmd convert -Yes`: prints "nothing new" (no books have Status new, extracted or in Calibre). Exit code 0.
  - `.\KindleDeDRM\KindleDeDRM.cmd bogus`: exit code is non-zero.
- [ ] **Step 3:** Run all tests. Expected: everything still passes.
- [ ] **Step 4:** `git commit -m "feat(app): KindleDeDRM entry point and CLI commands"`

### Task 7: Main, prerequisites and settings menus

**Files:**
- Create: `KindleDeDRM/lib/Menu.ps1`
- Modify: `KindleDeDRM/KindleDeDRM.ps1` (remove the stub and dot-source Menu.ps1)

**Interfaces:**
- Consumes: Ui (`Read-MenuChoice`), Prereqs (`Get-MissingRequirements`, `Show-Requirements`, `$Components`, `Install-*`, `Set-StoreAutoUpdate`), Config (`Save-Settings`), Pipeline (`Invoke-Clean`).
- Produces:
  - `Start-MainMenu -Settings <obj>`:
    - Loops: clear the screen, print the header `KindleDeDRM <ver>` with the status line `Kindle <ver>  .  <n> books  .  all prerequisites OK|<n> missing - choose 2`, print the menu exactly as in spec section 4, then `Read-MenuChoice -Valid '0','1','2','3','4','5'`.
    - Each action runs inside `try { … } catch { Fail "Error: …" }`, followed by `Read-Host '  Press Enter to return to the menu'`.
    - Use ASCII `.` and `-` in place of the spec's `·` and `–`.
  - `Show-PrereqMenu`:
    - If items are missing, list them numbered with their component names, plus `a) install all missing` and `0) back`. Installing goes through the same per-item Why/From/Y-n flow as `Invoke-Install`.
    - If nothing is missing, print `everything is installed` and offer `f) force reinstall a part`, `s) Store auto-updates off/on` and `0) back`.
  - `Show-SettingsMenu -Settings <obj> -> obj`:
    - Options: `1) EPUB folder`, `2) Calibre library`, `3) Stall timeout (seconds)`, `4) Store auto-updates on/off`, `0) back`.
    - A blank input keeps the current value. Folders that don't exist are created after a Y/n confirmation. The timeout must be an integer of 30 or more.
    - Saves with `Save-Settings` and returns the updated settings.
  - Menu item 3 calls `Show-BooksMenu` (Task 8). If `Get-MissingRequirements` is not empty, it lists the missing items and returns to the menu.

- [ ] **Step 1:** Implement `lib\Menu.ps1` with `Show-BooksMenu` as a stub.
- [ ] **Step 2: Verify manually** by running `.\KindleDeDRM\KindleDeDRM.cmd`:
  - The header shows `27 books . all prerequisites OK`.
  - 1 shows the table.
  - 2 says everything is installed.
  - 4: set the stall timeout to 120 and go back. `settings.json` now has 120. Set it back to 300.
  - Typing `9` shows the "Choose one of" hint.
  - 0 exits.
- [ ] **Step 3:** Run all tests. Expected: they pass.
- [ ] **Step 4:** `git commit -m "feat(app): main, prerequisites and settings menus"`

### Task 8: DeDRM books screen

**Files:**
- Modify: `KindleDeDRM/lib/Menu.ps1` (replace the `Show-BooksMenu` stub)

**Interfaces:**
- Consumes: Library (`Get-KindleBooks`, `Read-TitleIndex`, `Update-TitleIndex`, `Get-BookIndex`, `Find-Books`), Pipeline (`Invoke-Archiver`, `Invoke-BookAction`), Ui (`Write-BookTable`, `ConvertFrom-Selection`, `Read-MenuChoice`), Native (`Stop-AppIfRunning`).
- Produces `Show-BooksMenu -Settings <obj>`, which runs this flow (spec section 5.2):
  1. **Refresh**, unless the user types `s` at `Refresh Kindle books now? [Y/s]`:
     - Find the `new` books.
     - If there are any, run `Stop-AppIfRunning Kindle`, then `Invoke-Archiver` on those books.
     - Then `Update-TitleIndex` for every extracted ASIN that has no title yet.
  2. **Loop:**
     - Prompt `Search (title/author, blank = all, 0 = back):`. Run `Find-Books`. If nothing matches, print `no books match` and ask again.
     - `Write-BookTable`.
     - Prompt `Pick books (e.g. 1,3  2-5  all  new; blank = new search):`, then `ConvertFrom-Selection` with NewIndexes set to the rows whose Status is `new`, `extracted` or `in Calibre`. If it throws, print the message and ask again. Blank input goes back to the search.
     - Prompt `Action: 1) Convert  2) Re-convert  3) Re-export  4) Open folder  0) Back` (Enter means 1).
     - Actions 1-3: run `Invoke-BookAction`, then print one line per result: green `ok`, or red `FAILED - <Message>`.
     - Action 4: for each picked book, if `Exported` exists, run `explorer.exe /select,"<path>"`; otherwise open the Calibre folder of its `KfxPath` or `EpubPath`.
     - Rebuild the index with `Get-BookIndex` and show the same search again.

- [ ] **Step 1:** Implement `Show-BooksMenu`.
- [ ] **Step 2: Verify manually** (spec section 8, items 4-6):
  - At refresh, choose `s`.
  - Search `orwell`: two rows, both `EPUB done`.
  - Pick `1`, action `2`: `ok`, the `1984` EPUB timestamp updates, and there is no duplicate file.
  - Pick `2`, action `3`: `ok`.
  - Pick `1`, action `4`: Explorer opens with the file selected.
  - Blank search lists 27 rows.
  - Pick `new`: prints `no new books`.
  - Type `5-2`: prints the reversed-range error.
- [ ] **Step 3:** Run all tests. Expected: they pass.
- [ ] **Step 4:** `git commit -m "feat(app): DeDRM books search, pick and actions"`

### Task 9: Installer and uninstaller

**Files:**
- Create: `KindleDeDRM/lib/Setup.ps1`, `KindleDeDRM/install.cmd`, `KindleDeDRM/install.ps1`, `KindleDeDRM/uninstall.cmd`, `KindleDeDRM/uninstall.ps1`
- Test: `KindleDeDRM/tests/Setup.Tests.ps1`

**Interfaces:**
- Produces:
  - `Add-PathEntry -PathValue <string> -Dir <string> -> string`: appends `;Dir` unless an entry equal to it (ignoring case and a trailing `\`) is already there. Empty entries are dropped.
  - `Remove-PathEntry -PathValue <string> -Dir <string> -> string`: removes every entry that matches by the same rule.
  - `install.ps1`:
    - Copies `KindleDeDRM.cmd`, `KindleDeDRM.ps1`, `README.md` and `lib\` to `$InstallDir = "$env:LOCALAPPDATA\Programs\KindleDeDRM"` (overwriting).
    - Sets the user PATH via `[Environment]::SetEnvironmentVariable('Path', (Add-PathEntry ...), 'User')`.
    - Creates the shortcut `"$env:APPDATA\Microsoft\Windows\Start Menu\Programs\KindleDeDRM.lnk"` through `WScript.Shell`. Its target is `powershell.exe`, its arguments are `-NoProfile -ExecutionPolicy Bypass -NoExit -File "<InstallDir>\KindleDeDRM.ps1"`, and its working directory is `%USERPROFILE%`.
    - Prints `Installed. Open a new terminal and run: KindleDeDRM`.
  - `uninstall.ps1` reverses those three steps and prints that `%LOCALAPPDATA%\kindle-dedrm` was kept.
  - Each `.cmd` file contains: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0<name>.ps1"`.

- [ ] **Step 1: Write failing tests**
  - Add to `'C:\a;C:\b'` → `'C:\a;C:\b;C:\k'`
  - Add when `'c:\K\'` is already present → unchanged
  - Add to `''` → `'C:\k'`
  - Add to `'C:\a;;C:\b'` drops the empty entry
  - Remove from `'C:\a;c:\k\;C:\b'` → `'C:\a;C:\b'`
  - Remove when the entry is absent → unchanged
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `Setup.ps1` and the four install/uninstall scripts.
- [ ] **Step 4: Run the tests (6 pass), then verify**
  - Run `KindleDeDRM\install.cmd` twice. `[Environment]::GetEnvironmentVariable('Path','User')` contains the install directory exactly once.
  - In a **new** terminal, `KindleDeDRM check` works.
  - The Start-menu shortcut opens the menu.
- [ ] **Step 5:** `git commit -m "feat(app): per-user installer and uninstaller"`

### Task 10: README, retire old CLI, final verification

**Files:**
- Create: `KindleDeDRM/README.md`. Adapt `kindle-dedrm/README.md`: install/uninstall steps first, then the menu walkthrough, then CLI usage, requirements table, files table and troubleshooting.
- Delete: `kindle-dedrm/` (via `git rm -r kindle-dedrm`)

- [ ] **Step 1:** Write the README and remove the old folder.
- [ ] **Step 2:** Run the full test suite (`Invoke-Pester .\KindleDeDRM\tests`). Expected: 0 failed.
- [ ] **Step 3:** Run the full spec section 8 manual checklist against the **installed** copy (re-run `install.cmd` first), plus these extra checks:
  - **Review Focus 4:** in menu 3, search `saint`. The Little Prince's author shows as `Antoine de Saint-Exupery`, with no mangled characters.
  - Run `uninstall.cmd`. The shortcut and PATH entry are gone, and `%LOCALAPPDATA%\kindle-dedrm\work\archived_kfx` still holds 27 files.
  - Run `install.cmd` again to leave the app installed.
- [ ] **Step 4:** `git commit -m "docs(app): README; remove superseded kindle-dedrm CLI"`
