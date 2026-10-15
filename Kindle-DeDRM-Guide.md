# Kindle → Calibre DRM Removal Guide (Windows)

Personal-backup guide for books you have purchased. Compiled 2026-10-15 from:

- Reddit: <https://www.reddit.com/r/Calibre/comments/1iujtfj/final_post_for_those_who_want_to_use_kindle_for/>
- MobileRead: <https://www.mobileread.com/forums/showthread.php?t=361503>

> **Read this first: Kindle for PC 2.x was retired on 30 June 2026.**
> Amazon replaced it with the new "Kindle for Windows" app in the Microsoft Store. After the cutoff, the old app may no longer sign in or download books.
> - **Plan A** uses the Kindle for PC 2.4.0 you already have installed, following the Reddit post. Try it first. If sign-in or downloads fail, go straight to **Plan B**.
> - **Plan B** uses the new Kindle for Windows app with Satsuoni's tools. This is the method MobileRead currently points to.
>
> Legal note: in some countries, removing DRM is not allowed even from books you own. Check your local law.

---

## Version cheat sheet

| Component | Plan A (old Kindle for PC) | Plan B (new Kindle for Windows) | Where to get it |
|---|---|---|---|
| Kindle app | **Kindle for PC 2.4.0 (70904)** ✅ already installed here | **Kindle for Windows 1.0.25218** | Plan A: Amazon no longer hosts old installers (the old S3 links return 403). Keep your installer. Plan B: Microsoft Store, search "Amazon Kindle". |
| Calibre | **9.16.0** (64-bit) | **9.16.0** (64-bit) | <https://calibre-ebook.com/download_windows> · direct: <https://github.com/kovidgoyal/calibre/releases/download/v9.16.0/calibre-64bit-9.16.0.msi> |
| DeDRM plugin | **noDRM v10.0.9** (the version the Reddit post used). Fallback: Satsuoni v10.0.32 | **Satsuoni v10.0.32** | noDRM: <https://github.com/noDRM/DeDRM_tools/releases> · Satsuoni: <https://github.com/Satsuoni/DeDRM_tools/releases/tag/v10.0.32> |
| KFX Input plugin | **2.34.2** (needs Calibre 6.0 or newer) | **2.34.2** | Calibre → Preferences → Plugins → *Get new plugins*, or `KFX Input.zip` from <https://www.mobileread.com/forums/showthread.php?t=291290> |
| Key/book extractor | not needed | **`MSIXKFXArchiver_x64_1_25218.exe`** (included in the Satsuoni v10.0.32 release) | Satsuoni v10.0.32 release assets |
| VC++ runtime | not needed | **Microsoft Visual C++ Redistributable x64** | <https://aka.ms/vs/17/release/vc_redist.x64.exe> |

Versions change often. If your Kindle for Windows build is newer than 1.0.25218, check the newest Satsuoni release for a matching archiver, since each archiver build works with only one Kindle build.

---

# Plan A: Kindle for PC 2.4.0

## Step 1. Install Kindle for PC 2.4.0 ✅ (done)

- Installed at `%LOCALAPPDATA%\Amazon\Kindle\application\Kindle.exe`. Verified on this PC as version **2.4.0.70904**.
- Keep the installer `.exe` in a safe place, because Amazon no longer offers it for download.

## Step 2. Block auto-update ✅ (done)

Amazon quietly downloads 2.4.1 in the background and installs it the next time you open the app. The newer version breaks DeDRM.

What was done on this PC:
1. Closed Kindle.
2. Created an **empty read-only file** named `updates` (a file, not a folder) at
   `%LOCALAPPDATA%\Amazon\Kindle\updates`
   Kindle downloads updates into a folder with this name, and it can't create the folder while the file is there.

To do it yourself (PowerShell):
```powershell
$u = "$env:LOCALAPPDATA\Amazon\Kindle\updates"
if (Test-Path $u -PathType Container) { Remove-Item $u -Recurse -Force }   # delete any already-downloaded update
New-Item -ItemType File -Path $u | Out-Null
Set-ItemProperty -Path $u -Name IsReadOnly -Value $true
```

After you sign in, also set a second safeguard:
- **Tools → Options → General** → untick **"Automatically install updates when they become available"**.

**Never delete the `updates` file.**

## Step 3. Sign in and download all books

1. Open Kindle for PC and sign in with your Amazon account.
   - If sign-in fails or says the app is no longer supported, the June 2026 cutoff applies to you. Go to **Plan B**.
2. In **Library → All**, right-click each book and choose **Download**.
   - Download **a few at a time**. Downloading many at once can leave images missing, and those books then import as broken `KFX-ZIP` files.
3. Open each book once, so you know it downloaded completely.
4. Books are saved to `Documents\My Kindle Content\` (check **Tools → Options → Content** for the exact folder). Each book is a folder ending in `_EBOK`.
5. Close Kindle, open it again, and check **Help → About**. It must still say **2.4.0 (70904)**.

## Step 4. Install Calibre 9.16.0

1. Download `calibre-64bit-9.16.0.msi` (link in the cheat sheet).
2. Run the installer with the default options.
3. Open Calibre once and finish the welcome wizard. Pick any library folder; the e-reader choice doesn't matter.

## Step 5. Install the DeDRM plugin, then KFX Input

Do this **after** Kindle 2.4.0 is installed and signed in, so DeDRM picks up the right key.

**DeDRM (noDRM v10.0.9):**
1. Download `DeDRM_tools_10.0.9.zip` from the noDRM releases page.
2. **Unzip it.** Inside is `DeDRM_plugin.zip`. That inner zip is the plugin, so don't unzip it further, and don't load the outer zip into Calibre.
3. Calibre → **Preferences → Plugins → Load plugin from file** → select `DeDRM_plugin.zip` → confirm with **Yes**.
4. Restart Calibre.

**KFX Input 2.34.2:**
1. Calibre → **Preferences → Plugins → Get new plugins** → search **KFX Input** → **Install**.
   Or: **Load plugin from file** → `KFX Input.zip`.
2. Restart Calibre.

**Check the key:**
1. **Preferences → Plugins** → find **DeDRM** (under *File type*) → **Customize plugin**.
2. Open **Kindle for Mac/PC ebooks**. There should be **exactly one key**.
   - If there is more than one, remove the old ones. Leftover keys from earlier installs cause the KFX-ZIP problem described in the Reddit post.
   - If there are none, click **+** to import the key from the installed Kindle.

## Step 6. Remove the DRM (import into Calibre)

1. In Calibre, click **Add books → Add books from directories, including sub-directories** (or drag the book in).
2. Select `Documents\My Kindle Content\`, or a single `_EBOK` folder, or the main `.azw` file inside it.
   - Keep each book's folder structure as it is. Don't move files out of their `_EBOK` folders.
   - Don't use Calibre's "Automatic adding" folder for Kindle books.
3. DeDRM removes the DRM automatically during import.
4. **Check the result.** The format shown in the right-hand panel should be **KFX** or **AZW3**.
   - **KFX-ZIP** or **AZW** means it failed. See Troubleshooting below.
5. To get EPUB: select the books → **Convert books** → output format **EPUB** → **OK**.
6. Test it: **Save to disk**, or open the EPUB in another reader. It should open without any Amazon account.

If noDRM 10.0.9 fails on newer books: remove the plugin and install the DeDRM plugin from **Satsuoni v10.0.32** instead. The KFX Input author recommends Satsuoni's fork because older noDRM releases can't handle Amazon's current KFX DRM.

---

# Plan B: New Kindle for Windows (Microsoft Store), for after the June 2026 cutoff

Needs Windows 11.

## Step B1. Install Kindle for Windows

1. Microsoft Store → search **Amazon Kindle** → install.
2. Open it → **⋯ / Settings → About** → write down the version. This guide matches **1.0.25218**.
3. Microsoft Store apps can't be held at an old version reliably. If yours updates past the supported build, wait for a new Satsuoni release that matches it.
4. Sign in.

## Step B2. Download all books

1. Download your books inside the app, a few at a time.
2. Open each book and page to the end once. This makes sure the book's keys are loaded.
3. Books are saved under
   `%LOCALAPPDATA%\Packages\AMZNKindle.AmazonKindleReadingApp_<id>\LocalState\Classic\Content`

## Step B3. Install Calibre 9.16.0

Same as Plan A Step 4.

## Step B4. Get the Satsuoni tools and the VC++ runtime

1. Install the **VC++ Redistributable x64**: <https://aka.ms/vs/17/release/vc_redist.x64.exe>
   (Without it, the archiver fails with `VCRUNTIME140_1.dll was not found`.)
2. Download the **v10.0.32** release assets from <https://github.com/Satsuoni/DeDRM_tools/releases/tag/v10.0.32>:
   - the DeDRM tools zip (contains the Calibre plugin)
   - `MSIXKFXArchiver_x64_1_25218.exe`. Use this exact build for 1.0.25218. The older `..._23620_final` build does not work with it.
3. Put them in their own folder, e.g. `C:\KindleTools\`.

## Step B5. Install the plugins in Calibre

1. **Load plugin from file** → the Satsuoni `DeDRM_plugin.zip`. Unzip the outer archive first, as in Plan A Step 5.
2. Install **KFX Input 2.34.2**, the same way as Plan A Step 5.
3. Restart Calibre.

## Step B6. Run the archiver

1. **Close the Kindle app.**
2. Open PowerShell in `C:\KindleTools\` and run:
   ```powershell
   .\MSIXKFXArchiver_x64_1_25218.exe
   ```
   With no arguments it uses the defaults. It finds Kindle through the registry, reads your downloaded books, and writes:
   - `archived_kfx\`: one `.kfx-zip` per book
   - `oldbooks.k4i` and `books.keyfile`: the keys
   - a temporary `C:\Data` folder (about 400 MB) that you can delete afterwards.
3. Books that are already in `archived_kfx` are skipped. To redo one, delete its output first.
4. If you see "Book opened, but no book keys detected": check the VC++ runtime, use the archiver that matches your Kindle version exactly, and open the book in Kindle again.

Full argument list (all optional; use `default` to skip one):
```
MSIXKFXArchiver_x64_1_25218.exe [kindle content folder] [output folder] [output k4i] [Kindle DLL folder] [extra k4i/keyfile ...]
```

## Step B7. Import into Calibre

1. If the plugin asks for the keys: in **DeDRM → Customize plugin → Kindle for Mac/PC ebooks**, import `oldbooks.k4i`.
2. **Add books** → select the `.kfx-zip` files in `archived_kfx\`.
3. Each book should show as **KFX**. Convert to **EPUB** as in Plan A Step 6.

---

# Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Book shows as **KFX-ZIP** or **AZW**, not KFX | DRM wasn't removed, or the download was incomplete. Delete the book from Calibre, delete and re-download it in Kindle (one at a time), then import again. Check that DeDRM has exactly one correct key. |
| Several keys in DeDRM's Kindle list | Leftovers from older Kindle installs. Remove them all and re-import the key from the current install. |
| Worked yesterday, fails today (Plan A) | Kindle updated itself to 2.4.1. Check **Help → About**. If so, reinstall 2.4.0, delete the `updates` folder, recreate the read-only `updates` file, and download the books again. |
| Kindle 2.4.0 won't sign in or download | The June 30, 2026 cutoff. Use Plan B. |
| `dsx120.dll MD5 not in supported map` (Plan B) | Your Kindle for Windows version has no matching archiver. Check for a newer Satsuoni release. |
| `VCRUNTIME140_1.dll was not found` | Install the VC++ Redistributable x64. |
| Still stuck | Some users report that moving the Kindle content folder to another location helps. Restart Calibre in debug mode (**Preferences → Restart in debug mode**), import again, and read the log. MobileRead doesn't allow detailed DRM help, so ask at <https://github.com/Satsuoni/DeDRM_tools/discussions>. |

---

## Support links

- MobileRead overview (kept up to date): <https://www.mobileread.com/forums/showthread.php?t=361503>
- Kindle for PC retirement thread: <https://www.mobileread.com/forums/showthread.php?t=373108>
- KFX Input plugin: <https://www.mobileread.com/forums/showthread.php?t=291290>
- Satsuoni DeDRM releases and discussions: <https://github.com/Satsuoni/DeDRM_tools/releases> · <https://github.com/Satsuoni/DeDRM_tools/discussions>
- noDRM DeDRM releases and issues: <https://github.com/noDRM/DeDRM_tools/releases> · <https://github.com/noDRM/DeDRM_tools/issues>
