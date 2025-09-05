<p align="center">
  <img src="https://i.imgur.com/B8cPgXy.png" alt="QuickPasta logo" width="200"/>
</p>

A lightweight Windows right-click helper for quickly pasting predefined sets of files (e.g., ReShade presets) into any game folder.

---

## Files in this repo
- **Add_QuickPasta_Menu.reg** – installs the QuickPasta submenu into Explorer’s right-click menu  
- **Remove_QuickPasta_Menu.reg** – removes the menu entries  
- **profiles.json** – defines your copy “profiles” (name → source folder)  
- **QuickPasta.ps1** – PowerShell script that does the actual copy based on the selected profile  
- **QuickPasta.ico** – custom icon for the context menu  

---

## How it works
1. Edit `profiles.json` to point each profile to the folder you want to copy from.  
2. Run `Add_QuickPasta_Menu.reg` to add **Quick Pasta → [profiles]** to your right-click menu.  
   - Works on files, folders, and folder background.  
   - On Windows 11, you’ll find it under **Show more options**.  
3. Right-click your game folder or `.exe`, pick a QuickPasta profile, and the files are copied there automatically.  
4. To remove the menu, run `Remove_QuickPasta_Menu.reg`.  

---

## Changing paths for your system
QuickPasta uses two sets of paths that may need to be customized:

1. **`profiles.json`**  
   - Maps profile names (submenu labels) to source folders.  
   - Example:
     ```json
     {
       "ReShade": "D:\\Tools\\ReShade\\Copy Pasta",
       "ReShade No Addon": "D:\\Tools\\ReShade\\Copy Pasta - No Addon"
     }
     ```
   - Change the paths on the right-hand side to match your own folders.  
   - Add or remove entries as you like—each one becomes a submenu option.  

2. **Registry files (`.reg`)**  
   - The `.reg` files contain paths to `QuickPasta.ps1`.  
   - Since you will move the QuickPasta folder to another location, edit the `.reg` files with a text editor and update the paths.  
   - Look for lines like:
     ```
     "Z:\\Game Tools\\.QuickPasta\\QuickPasta.ps1"
     "Z:\\Game Tools\\.QuickPasta\\QuickPasta.ico"
     ```
     Replace them with the actual location on your system.  

---

## Notes
- Requires PowerShell (built into Windows 10/11).  
- Copy behavior: overwrites existing files silently.  
