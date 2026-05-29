import csv
import json
import os
import re
import sys
import time
import ctypes
from ctypes import wintypes
from dataclasses import dataclass, asdict
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk


APP_TITLE = "CanYouDialMeNow"
DATA_DIR = Path(os.getenv("APPDATA", Path.home())) / "CanYouDialMeNow"
DATA_FILE = DATA_DIR / "extensions.json"
PASTE_DELAY_MS = 120


user32 = ctypes.WinDLL("user32", use_last_error=True)

GetForegroundWindow = user32.GetForegroundWindow
GetForegroundWindow.restype = wintypes.HWND

SetForegroundWindow = user32.SetForegroundWindow
SetForegroundWindow.argtypes = [wintypes.HWND]
SetForegroundWindow.restype = wintypes.BOOL

IsWindow = user32.IsWindow
IsWindow.argtypes = [wintypes.HWND]
IsWindow.restype = wintypes.BOOL

GetWindowThreadProcessId = user32.GetWindowThreadProcessId
GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
GetWindowThreadProcessId.restype = wintypes.DWORD

keybd_event = user32.keybd_event
keybd_event.argtypes = [ctypes.c_ubyte, ctypes.c_ubyte, wintypes.DWORD, ctypes.c_void_p]

VK_CONTROL = 0x11
VK_V = 0x56
KEYEVENTF_KEYUP = 0x0002


@dataclass
class ExtensionEntry:
    name: str
    extension: str
    team: str = ""
    notes: str = ""
    favorite: bool = False


def normalize_extension(value):
    return re.sub(r"[^\d*#+,;]", "", value.strip())


def load_entries():
    if not DATA_FILE.exists():
        return [
            ExtensionEntry("Reception", "100", "Front Desk", "Sample entry", True),
            ExtensionEntry("Support Queue", "200", "Queues", "Sample entry", True),
            ExtensionEntry("Voicemail", "*98", "System", "Sample entry", False),
        ]

    with DATA_FILE.open("r", encoding="utf-8") as handle:
        raw_entries = json.load(handle)

    entries = []
    for item in raw_entries:
        entries.append(
            ExtensionEntry(
                name=item.get("name", ""),
                extension=item.get("extension", ""),
                team=item.get("team", ""),
                notes=item.get("notes", ""),
                favorite=bool(item.get("favorite", False)),
            )
        )
    return entries


def save_entries(entries):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with DATA_FILE.open("w", encoding="utf-8") as handle:
        json.dump([asdict(entry) for entry in entries], handle, indent=2)


class ExtensionDialog(tk.Toplevel):
    def __init__(self, parent, title, entry=None):
        super().__init__(parent)
        self.title(title)
        self.resizable(False, False)
        self.result = None
        self.transient(parent)
        self.grab_set()

        self.name_var = tk.StringVar(value=entry.name if entry else "")
        self.extension_var = tk.StringVar(value=entry.extension if entry else "")
        self.team_var = tk.StringVar(value=entry.team if entry else "")
        self.notes_var = tk.StringVar(value=entry.notes if entry else "")
        self.favorite_var = tk.BooleanVar(value=entry.favorite if entry else False)

        body = ttk.Frame(self, padding=16)
        body.grid(row=0, column=0, sticky="nsew")

        self._field(body, "Name", self.name_var, 0)
        self._field(body, "Extension", self.extension_var, 1)
        self._field(body, "Team / Group", self.team_var, 2)
        self._field(body, "Notes", self.notes_var, 3)

        favorite = ttk.Checkbutton(body, text="Favorite", variable=self.favorite_var)
        favorite.grid(row=4, column=1, sticky="w", pady=(8, 0))

        actions = ttk.Frame(body)
        actions.grid(row=5, column=0, columnspan=2, sticky="e", pady=(16, 0))
        ttk.Button(actions, text="Cancel", command=self.destroy).grid(row=0, column=0, padx=(0, 8))
        ttk.Button(actions, text="Save", command=self._save).grid(row=0, column=1)

        self.bind("<Return>", lambda _event: self._save())
        self.bind("<Escape>", lambda _event: self.destroy())
        self.wait_visibility()
        self.focus_force()

    def _field(self, parent, label, variable, row):
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", pady=5, padx=(0, 12))
        entry = ttk.Entry(parent, width=34, textvariable=variable)
        entry.grid(row=row, column=1, sticky="ew", pady=5)
        if row == 0:
            entry.focus_set()

    def _save(self):
        name = self.name_var.get().strip()
        extension = normalize_extension(self.extension_var.get())

        if not name:
            messagebox.showerror("Missing name", "Enter a name for this extension.", parent=self)
            return
        if not extension:
            messagebox.showerror("Missing extension", "Enter a dialable extension.", parent=self)
            return

        self.result = ExtensionEntry(
            name=name,
            extension=extension,
            team=self.team_var.get().strip(),
            notes=self.notes_var.get().strip(),
            favorite=self.favorite_var.get(),
        )
        self.destroy()


class ExtensionModuleApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(APP_TITLE)
        self.geometry("760x520")
        self.minsize(650, 420)

        self.entries = load_entries()
        self.filtered_entries = []
        self.last_external_hwnd = None
        self.own_pid = os.getpid()

        self.search_var = tk.StringVar()
        self.team_var = tk.StringVar(value="All")
        self.status_var = tk.StringVar(value="Click inside your VOIP dial field once, then use a Dial button here.")
        self.copy_only_var = tk.BooleanVar(value=False)

        self._configure_styles()
        self._build_ui()
        self._refresh_team_filter()
        self._refresh_list()
        self._track_foreground_window()

    def _configure_styles(self):
        style = ttk.Style(self)
        if "vista" in style.theme_names():
            style.theme_use("vista")
        style.configure("Favorite.TButton", font=("Segoe UI", 9, "bold"))
        style.configure("Status.TLabel", foreground="#44546a")

    def _build_ui(self):
        self.columnconfigure(0, weight=1)
        self.rowconfigure(2, weight=1)

        toolbar = ttk.Frame(self, padding=(12, 12, 12, 6))
        toolbar.grid(row=0, column=0, sticky="ew")
        toolbar.columnconfigure(1, weight=1)

        ttk.Label(toolbar, text="Search").grid(row=0, column=0, padx=(0, 8))
        search = ttk.Entry(toolbar, textvariable=self.search_var)
        search.grid(row=0, column=1, sticky="ew", padx=(0, 12))
        search.bind("<KeyRelease>", lambda _event: self._refresh_list())

        ttk.Label(toolbar, text="Group").grid(row=0, column=2, padx=(0, 8))
        self.team_combo = ttk.Combobox(toolbar, textvariable=self.team_var, state="readonly", width=18)
        self.team_combo.grid(row=0, column=3, padx=(0, 12))
        self.team_combo.bind("<<ComboboxSelected>>", lambda _event: self._refresh_list())

        ttk.Button(toolbar, text="Add", command=self._add_entry).grid(row=0, column=4, padx=(0, 6))
        ttk.Button(toolbar, text="Import", command=self._import_csv).grid(row=0, column=5, padx=(0, 6))
        ttk.Button(toolbar, text="Export", command=self._export_csv).grid(row=0, column=6)

        options = ttk.Frame(self, padding=(12, 0, 12, 6))
        options.grid(row=1, column=0, sticky="ew")
        ttk.Checkbutton(options, text="Copy only", variable=self.copy_only_var).grid(row=0, column=0, sticky="w")

        table_frame = ttk.Frame(self, padding=(12, 0, 12, 8))
        table_frame.grid(row=2, column=0, sticky="nsew")
        table_frame.columnconfigure(0, weight=1)
        table_frame.rowconfigure(0, weight=1)

        columns = ("favorite", "name", "extension", "team", "notes")
        self.tree = ttk.Treeview(table_frame, columns=columns, show="headings", selectmode="browse")
        self.tree.heading("favorite", text="*")
        self.tree.heading("name", text="Name")
        self.tree.heading("extension", text="Extension")
        self.tree.heading("team", text="Group")
        self.tree.heading("notes", text="Notes")

        self.tree.column("favorite", width=36, minwidth=36, anchor="center", stretch=False)
        self.tree.column("name", width=180, minwidth=120)
        self.tree.column("extension", width=100, minwidth=80)
        self.tree.column("team", width=130, minwidth=90)
        self.tree.column("notes", width=260, minwidth=120)

        self.tree.grid(row=0, column=0, sticky="nsew")
        scrollbar = ttk.Scrollbar(table_frame, orient="vertical", command=self.tree.yview)
        scrollbar.grid(row=0, column=1, sticky="ns")
        self.tree.configure(yscrollcommand=scrollbar.set)
        self.tree.bind("<Double-1>", lambda _event: self._dial_selected())
        self.tree.bind("<Return>", lambda _event: self._dial_selected())

        actions = ttk.Frame(self, padding=(12, 0, 12, 8))
        actions.grid(row=3, column=0, sticky="ew")
        actions.columnconfigure(0, weight=1)

        ttk.Button(actions, text="Dial Selected", style="Favorite.TButton", command=self._dial_selected).grid(row=0, column=1, padx=(0, 8))
        ttk.Button(actions, text="Edit", command=self._edit_selected).grid(row=0, column=2, padx=(0, 8))
        ttk.Button(actions, text="Delete", command=self._delete_selected).grid(row=0, column=3)

        ttk.Label(self, textvariable=self.status_var, style="Status.TLabel", padding=(12, 0, 12, 12)).grid(
            row=4, column=0, sticky="ew"
        )

    def _track_foreground_window(self):
        hwnd = GetForegroundWindow()
        if hwnd and self._is_external_window(hwnd):
            self.last_external_hwnd = hwnd
        self.after(250, self._track_foreground_window)

    def _is_external_window(self, hwnd):
        if not hwnd:
            return False
        pid = wintypes.DWORD()
        GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        return pid.value != self.own_pid

    def _refresh_team_filter(self):
        groups = sorted({entry.team for entry in self.entries if entry.team})
        values = ["All", "Favorites"] + groups
        self.team_combo.configure(values=values)
        if self.team_var.get() not in values:
            self.team_var.set("All")

    def _refresh_list(self):
        query = self.search_var.get().strip().lower()
        group = self.team_var.get()

        self.filtered_entries = []
        for entry in sorted(self.entries, key=lambda item: (not item.favorite, item.team.lower(), item.name.lower())):
            haystack = " ".join([entry.name, entry.extension, entry.team, entry.notes]).lower()
            if query and query not in haystack:
                continue
            if group == "Favorites" and not entry.favorite:
                continue
            if group not in ("All", "Favorites") and entry.team != group:
                continue
            self.filtered_entries.append(entry)

        for item_id in self.tree.get_children():
            self.tree.delete(item_id)

        for index, entry in enumerate(self.filtered_entries):
            self.tree.insert(
                "",
                "end",
                iid=str(index),
                values=("*" if entry.favorite else "", entry.name, entry.extension, entry.team, entry.notes),
            )

    def _selected_entry(self):
        selected = self.tree.selection()
        if not selected:
            messagebox.showinfo("No extension selected", "Select an extension first.", parent=self)
            return None
        return self.filtered_entries[int(selected[0])]

    def _add_entry(self):
        dialog = ExtensionDialog(self, "Add Extension")
        self.wait_window(dialog)
        if dialog.result:
            self.entries.append(dialog.result)
            save_entries(self.entries)
            self._refresh_team_filter()
            self._refresh_list()
            self.status_var.set(f"Added {dialog.result.name}.")

    def _edit_selected(self):
        entry = self._selected_entry()
        if not entry:
            return

        dialog = ExtensionDialog(self, "Edit Extension", entry)
        self.wait_window(dialog)
        if dialog.result:
            index = self.entries.index(entry)
            self.entries[index] = dialog.result
            save_entries(self.entries)
            self._refresh_team_filter()
            self._refresh_list()
            self.status_var.set(f"Updated {dialog.result.name}.")

    def _delete_selected(self):
        entry = self._selected_entry()
        if not entry:
            return

        confirmed = messagebox.askyesno("Delete extension", f"Delete {entry.name} ({entry.extension})?", parent=self)
        if confirmed:
            self.entries.remove(entry)
            save_entries(self.entries)
            self._refresh_team_filter()
            self._refresh_list()
            self.status_var.set(f"Deleted {entry.name}.")

    def _dial_selected(self):
        entry = self._selected_entry()
        if not entry:
            return
        self._place_on_clipboard(entry.extension)

        if self.copy_only_var.get():
            self.status_var.set(f"Copied {entry.extension} for {entry.name}.")
            return

        if not self.last_external_hwnd or not IsWindow(self.last_external_hwnd):
            self.status_var.set(f"Copied {entry.extension}. Click the VOIP dial field, then press Ctrl+V.")
            return

        target = self.last_external_hwnd
        self.after(PASTE_DELAY_MS, lambda: self._paste_into_window(target, entry))

    def _place_on_clipboard(self, text):
        self.clipboard_clear()
        self.clipboard_append(text)
        self.update_idletasks()

    def _paste_into_window(self, hwnd, entry):
        SetForegroundWindow(hwnd)
        time.sleep(0.08)
        keybd_event(VK_CONTROL, 0, 0, None)
        keybd_event(VK_V, 0, 0, None)
        keybd_event(VK_V, 0, KEYEVENTF_KEYUP, None)
        keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, None)
        self.status_var.set(f"Sent {entry.extension} for {entry.name}.")

    def _import_csv(self):
        path = filedialog.askopenfilename(
            title="Import extensions",
            filetypes=[("CSV files", "*.csv"), ("All files", "*.*")],
            parent=self,
        )
        if not path:
            return

        imported = []
        try:
            with open(path, newline="", encoding="utf-8-sig") as handle:
                reader = csv.DictReader(handle)
                for row in reader:
                    name = (row.get("name") or row.get("Name") or "").strip()
                    extension = normalize_extension(row.get("extension") or row.get("Extension") or "")
                    if not name or not extension:
                        continue
                    favorite_value = (row.get("favorite") or row.get("Favorite") or "").strip().lower()
                    imported.append(
                        ExtensionEntry(
                            name=name,
                            extension=extension,
                            team=(row.get("team") or row.get("Team") or row.get("group") or row.get("Group") or "").strip(),
                            notes=(row.get("notes") or row.get("Notes") or "").strip(),
                            favorite=favorite_value in {"1", "true", "yes", "y"},
                        )
                    )
        except (OSError, csv.Error) as exc:
            messagebox.showerror("Import failed", str(exc), parent=self)
            return

        self.entries.extend(imported)
        save_entries(self.entries)
        self._refresh_team_filter()
        self._refresh_list()
        self.status_var.set(f"Imported {len(imported)} extension entries.")

    def _export_csv(self):
        path = filedialog.asksaveasfilename(
            title="Export extensions",
            defaultextension=".csv",
            filetypes=[("CSV files", "*.csv")],
            parent=self,
        )
        if not path:
            return

        try:
            with open(path, "w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=["name", "extension", "team", "notes", "favorite"])
                writer.writeheader()
                for entry in self.entries:
                    writer.writerow(asdict(entry))
        except OSError as exc:
            messagebox.showerror("Export failed", str(exc), parent=self)
            return

        self.status_var.set(f"Exported {len(self.entries)} extension entries.")


def main():
    if sys.platform != "win32":
        raise SystemExit("This prototype targets Windows desktop VOIP applications.")
    app = ExtensionModuleApp()
    app.mainloop()


if __name__ == "__main__":
    main()
