# CanYouDialMeNow

A lightweight Windows desktop sidecar for cataloging special extensions like contacts and sending a selected extension into the active dial field of a VOIP desktop app.

## What it does

- Stores extension entries with name, extension, group, notes, and favorite status.
- Searches and filters entries quickly.
- Imports and exports CSV files.
- Copies an extension to the clipboard.
- Attempts to restore focus to the last external app window and paste the extension with `Ctrl+V`.

## Run it

Recommended on Windows:

Double-click `Launch-VoipExtensionModule.vbs` to launch without a console window.

You can also run:

```powershell
powershell -ExecutionPolicy Bypass -File .\VoipExtensionModule.ps1
```

No third-party packages are required.

Optional Python prototype:

```powershell
python .\voip_extension_module.py
```

## Typical workflow

1. Open your VOIP desktop application.
2. Click inside its dial/search field once.
3. Open this module and click `Dial Selected`, or double-click an extension row.
4. The module copies the extension, switches back to the last external window, and pastes it.

If your VOIP app blocks simulated paste, enable `Copy only`, then click the VOIP dial field and press `Ctrl+V`.

## CSV format

CSV import/export uses these columns:

```csv
name,extension,team,notes,favorite
Reception,100,Front Desk,Main line,true
Support Queue,200,Queues,General support,false
Voicemail,*98,System,Mailbox access,false
```

Data is stored at:

```text
%APPDATA%\CanYouDialMeNow\extensions.json
```

## Notes

This first version behaves like a virtual speed-dial sidecar. It does not need to integrate directly with a PBX or SIP account, so it can work across many VOIP desktop apps as long as they accept text input or paste in their dial field.
