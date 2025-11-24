<!-- Side-by-side, no borders, vertically centered, responsive -->
<table align="center" width="100%" style="border-collapse:collapse;border:none;">
  <tr>
    <td align="center" valign="middle" style="border:none;padding:0 20px 0 0;width:28%;">
      <img
        src="https://i.imgur.com/B8cPgXy.png"
        alt="QuickPasta logo"
        style="display:block;width:100%;max-width:180px;min-width:120px;height:auto;"
      />
    </td>
    <td align="center" valign="middle" style="border:none;padding:0;width:72%;">
      <img
        src="https://i.imgur.com/IpMLNtP.gif"
        alt="QuickPasta demo"
        style="display:block;width:100%;max-width:800px;height:auto;"
      />
    </td>
  </tr>
</table>

**QuickPasta** adds a **custom right-click context menu** to Windows Explorer that lets you instantly paste a prepared set of files from a local folder or a ZIP URL into the place you clicked.  
It ships with a polished **GUI Manager** to create, reorder, and install your menu profiles—no manual registry edits, no terminals, fully portable.

---

## ✨ Highlights

- **Friendly GUI Manager (WPF)**
  - Add / remove / save profiles (selecting a profile is edit mode—no extra “Edit” button).
  - Reorder with ▲/▼ buttons or **Ctrl+↑ / Ctrl+↓**; order is preserved.
  - **Apply + Install/Update** writes the classic Explorer context-menu submenu and shows a single confirmation dialog.
  - **Uninstall Menu** removes every entry for the current user.

- **Powerful profiles**
  - Source can be a **local folder**, a **ZIP URL** (auto-download & extract), or any **HTTP(S) file** (with optional extraction). Add **multiple sources in one profile** (processed in order).
  - Optional **rename rules** (e.g., `ReShade64.dll -> dxgi.dll` or `*.cfg, settings.cfg`).
  - Profiles are stored in `profiles.json` in the **same order** you see in the Manager.

- **Portable & quiet**
  - No installers, no services, no PATH changes.  
  - Runs PowerShell invisibly via a small VBS launcher.  
  - Small rotating logs for diagnostics.

---

## ⚡ Installation

### Option A — Use the GUI (recommended)

1. Place the folder anywhere (e.g., `D:\Tools\QuickPasta\`).
2. Run **`QuickPastaManager.ps1`**.
3. Add a profile:
   - **Name** – label shown in the submenu.
   - **Source** - a **local folder**, a **ZIP** URL (`https://...`), or any **HTTP(S)** file. Add multiple sources on separate lines.
   - **Extract non-zip URLs** – optional; enable this for self-extracting downloads you want unpacked automatically.
   - **Renames** – optional (one rule per line; see syntax below).
4. Click **Save**.
5. Reorder with ▲/▼ or **Ctrl+↑ / Ctrl+↓** (click the list to focus).
6. Click **Apply + Install/Update** → a single “installed/updated” dialog appears.
7. Right-click in Explorer → **Quick Pasta** submenu → choose a profile.

To remove the menu later: open the Manager and click **Uninstall Menu**.

### Option B — Script-only

- Install **`Install_QuickPasta.vbs`** to (re)install from the current `profiles.json`.

---


❌ Uninstall
-----------

*   In the Manager: **Uninstall Menu**
    
*   Or run: **Uninstall_QuickPasta.vbs**

---

## 👁️ Where You’ll See It

- Right-click on **files**, **folders**, or a folder’s **background**.
- On Windows 11, open the classic context menu via “Show more options” or (Shift+Right-Click).

---

## 🔤 **Rename Rules — Mini DSL**

Write one rule per line in the Manager:

    from -> to
    from, to

Rules run **after** the source has been copied into the target (post-copy).Only the **destination** is modified — your **source is never changed**.

### Matching (left side: from)

*   \* matches within a single path segment (non-recursive).
    
*   \*\* makes the rule **recursive** (any depth).
    
*   Without \*\*, patterns like shaders/\*.fxc match **only the top-level files** inside shaders\\ (not its subfolders).
    

### Destination behavior (right side: to)

*   Ends with / → **move into folder** under the target root, **preserve filename**.
    
*   Contains / → treat as **relative path** under the target root (directories are created as needed).
    
*   Bare filename with a path on the left (e.g., textures/\*.cfg -> settings.cfg) → **move to target root** and rename to that filename.
    
*   Bare filename with no path on the left (e.g., ReShade64.dll -> dxgi.dll) → **rename in place** (same directory).
    

### Excludes / deletes

Use the special action @delete on the right to remove matches:

```
**/notes.txt -> @delete
shaders/**   -> @delete
```

> After deletes/moves, QuickPasta aggressively removes now-empty folders (including hidden/system “crumbs” like desktop.ini), and for full-tree deletes (e.g., shaders/\*\*) it also removes the base folder itself.

### **Order matters**

Put **move/rename rules first**, and your @delete rules **after**, so you don’t delete files you intend to move.

## Quick reference

| Intent                             | Rule                                    | Effect                                                   |
| ---------------------------------- | --------------------------------------- | -------------------------------------------------------- |
| Rename in place                    | `ReShade64.dll -> dxgi.dll`             | Same folder, new name                                    |
| Move top-level matches to a folder | `shaders/*.fxc -> shaders_cache/`       | Create `shaders_cache\` if needed; keep filenames        |
| Recursive move                     | `shaders/**/*.fxc -> shaders_cache/`    | Any depth; keep filenames                                |
| Move & rename to a specific path   | `textures/readme.txt -> docs/guide.txt` | Create `docs\`; new leaf name                            |
| Move to root with new name         | `textures/*.cfg -> settings.cfg`        | Root of target; last match wins                          |
| Delete matches                     | `**/notes.txt -> @delete`               | Removes files; folder cleanup runs                       |
| Delete whole subtree               | `shaders/** -> @delete`                 | Removes all files under `shaders\` and the folder itself |

> Wildcards and subpaths are supported.

> Use `@include <source> -> <destination>` when you only need a single file from a downloaded/extracted payload (for example, `@include ReShade64.dll -> dxgi.dll`). The Manager keeps whatever hint you specify, flags include-only profiles, and only prompts for a hint when the destination includes folders (meaning you plan to rename as you copy).

### Common recipes

**Rename in place**

`ReShade64.dll -> dxgi.dll`

**Move all top-level FXC files from shaders\\ into shaders\_cache\\**

`shaders/*.fxc -> shaders_cache/`

**Recursive move (any depth under shaders\\)**

`shaders/**/*.fxc -> shaders_cache/`

**Move top-level CFGs from textures\\ to target root and rename to settings.cfg**_(If multiple files match, the last one wins and overwrites.)_

`textures/*.cfg -> settings.cfg`

**Delete everything left in shaders\\ after your moves (and remove the folder itself)**

`shaders/** -> @delete`

**Delete every notes.txt anywhere**

`**/notes.txt -> @delete`

---

## 📂 Project Layout
Keep all files in the same folder:

    QuickPasta\
    ├── QuickPastaManager.ps1     # GUI Manager (WPF)
    ├── QuickPasta.ps1            # Core logic (copy/ZIP/renames + logging)
    ├── QuickPasta.vbs            # Hidden runner for PowerShell
    ├── Install_QuickPasta.vbs    # One-click installer (writes registry; one confirmation)
    ├── Uninstall_QuickPasta.vbs  # One-click uninstaller
    ├── profiles.json             # Your profiles (saved in UI order)
    └── QuickPasta.ico            # Icon for Explorer & the Manager


---

🧠 How It Works (under the hood)
--------------------------------

*   **QuickPastaManager.ps1** edits profiles, keeps their **order**, and calls the installer/uninstaller.
    
*   **Install\_QuickPasta.vbs** reads profiles.json in order and registers the submenu.It silently writes numbered keys (e.g., 001\_…, 002\_…) to guarantee display order, while the **labels remain clean**.
    
*   **QuickPasta.vbs** launches **PowerShell hidden** with the selected profile and the clicked path.
    
*   **QuickPasta.ps1** copies local content or downloads & extracts ZIPs, applies renames, and logs.
    
*   **Uninstall\_QuickPasta.vbs** removes every QuickPasta menu entry for the current user.

## 📝 `profiles.json` Examples

> The Manager writes this file for you and preserves list order.  
> You can still hand-edit it if you like.

**Local folders**

    {
      "ReShade": "D:\\Tools\\ReShade\\Copy Pasta",
      "ReShade No Addon": "D:\\Tools\\ReShade\\Copy Pasta - No Addon",
      "ReShade RenoDX": "D:\\Tools\\ReShade\\Copy Pasta - RenoDX"
    }
    

**Remote ZIP with renames**

    {
      "ReShade RenoDX (Live)": {
        "source": "https://nightly.link/clshortfuse/reshade/workflows/renodx/renodx/ReShade%20(64-bit).zip",
        "renames": [
          { "from": "ReShade64.dll", "to": "dxgi.dll" },
          { "from": "reshade.ini",   "to": "ReShade.ini" }
        ]
      }
    }

**Multiple sources in one profile (processed in order)**

    {
      "ReShade + DLSS Bundle": {
        "sources": [
          "D:\\Tools\\ReShade\\Copy Pasta",
          { "source": "https://example.com/dlss-pack.zip" }
        ],
        "renames": [
          { "from": "ReShade64.dll", "to": "dxgi.dll" }
        ]
      }
    }

**Self-extracting download**

    {
      "ReShade SFX (Live)": {
        "source": "https://example.com/ReShadeSetup.exe",
        "extract": true,
        "renames": [
          { "from": "ReShade64.dll", "to": "dxgi.dll" }
        ]
      }
    }

> Set `extract` to `true` (or check **Extract non-zip URLs** in the Manager) when you want QuickPasta to unpack a downloaded EXE before rename rules run. If extraction fails, the original file is copied instead.
> QuickPasta first tries the built-in ZIP extractor and, if that fails, looks for `7z.exe` in Program Files, Program Files (x86), the script folder, or anything on your PATH. If nothing turns up it silently downloads a portable copy into `./7Zip/` and reuses it next time. If that still fails, the original executable is copied intact.


> Tip: JSON does **not** allow trailing commas. If you see errors, check your brackets/commas.


🧾 Logging
----------

*   Log file: quickpasta.log (next to the scripts).
    
*   Rotates around **512 KB**; keeps the last ~400 lines.
    
*   Enable info-level logs in QuickPasta.ps1: `$LogInfoEnabled = $true`
    
⌨️ Shortcuts (Manager)
----------------------

*   **Ctrl+↑ / Ctrl+↓** — move the selected profile up/down.
    
*   Click the list once to give it keyboard focus so shortcuts work immediately.

⚠️ Requirements
---------------

*   Windows **10/11**
    
*   PowerShell **5.1+** (built-in Windows)
    
*   .NET Framework **4.8** (for the WPF Manager)
    

After changing profiles or their order, click **Apply + Install/Update** to refresh the submenu.

🐞 Troubleshooting
------------------

*   **Menu isn’t visible** → Use **Right-Click → Show more options** to check the classic menu, or use **Shift+Right-Click**.
    
*   **Order looks wrong** → Open the Manager, verify list order, then **Apply + Install/Update**.
    
*   **Invalid JSON** → The Manager warns if profiles.json can’t be parsed.
