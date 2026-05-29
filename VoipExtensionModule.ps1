Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32CanYouDialMeNow {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
"@

$ErrorActionPreference = "Stop"
$AppTitle = "CanYouDialMeNow"
$DataDir = Join-Path $env:APPDATA "CanYouDialMeNow"
$DataFile = Join-Path $DataDir "extensions.json"
$OwnProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
$LastExternalWindow = [IntPtr]::Zero
$Entries = New-Object System.Collections.ArrayList

function Normalize-Extension {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return [regex]::Replace($Value.Trim(), "[^\d*#+,;]", "")
}

function New-ExtensionEntry {
    param([string]$Name, [string]$Extension, [string]$Team = "", [string]$Notes = "", [bool]$Favorite = $false)
    [pscustomobject]@{
        Name = $Name.Trim()
        Extension = Normalize-Extension $Extension
        Team = $Team.Trim()
        Notes = $Notes.Trim()
        Favorite = $Favorite
    }
}

function Load-Entries {
    $Entries.Clear()
    if (Test-Path $DataFile) {
        $loaded = Get-Content -LiteralPath $DataFile -Raw | ConvertFrom-Json
        foreach ($item in @($loaded)) {
            [void]$Entries.Add((New-ExtensionEntry -Name ([string]$item.Name) -Extension ([string]$item.Extension) -Team ([string]$item.Team) -Notes ([string]$item.Notes) -Favorite ([bool]$item.Favorite)))
        }
        return
    }
    [void]$Entries.Add((New-ExtensionEntry -Name "Reception" -Extension "100" -Team "Front Desk" -Notes "Sample entry" -Favorite $true))
    [void]$Entries.Add((New-ExtensionEntry -Name "Support Queue" -Extension "200" -Team "Queues" -Notes "Sample entry" -Favorite $true))
    [void]$Entries.Add((New-ExtensionEntry -Name "Voicemail" -Extension "*98" -Team "System" -Notes "Sample entry"))
}

function Save-Entries {
    if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }
    $Entries | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $DataFile -Encoding UTF8
}

function Get-FilteredEntries {
    $query = $SearchBox.Text.Trim().ToLowerInvariant()
    $group = [string]$GroupCombo.SelectedItem
    $Entries | Sort-Object @{Expression = { -not $_.Favorite }}, Team, Name | Where-Object {
        $text = "$($_.Name) $($_.Extension) $($_.Team) $($_.Notes)".ToLowerInvariant()
        (($query.Length -eq 0) -or $text.Contains($query)) -and
        ($group -eq "All" -or ($group -eq "Favorites" -and $_.Favorite) -or $_.Team -eq $group)
    }
}

function Refresh-Groups {
    $current = [string]$GroupCombo.SelectedItem
    $GroupCombo.Items.Clear()
    [void]$GroupCombo.Items.Add("All")
    [void]$GroupCombo.Items.Add("Favorites")
    $Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Team) } | Select-Object -ExpandProperty Team -Unique | Sort-Object | ForEach-Object { [void]$GroupCombo.Items.Add($_) }
    if ($GroupCombo.Items.Contains($current)) { $GroupCombo.SelectedItem = $current } else { $GroupCombo.SelectedItem = "All" }
}

function Refresh-Grid {
    $Grid.Rows.Clear()
    foreach ($entry in @(Get-FilteredEntries)) {
        $rowIndex = $Grid.Rows.Add()
        $row = $Grid.Rows[$rowIndex]
        $row.Cells["Favorite"].Value = $(if ($entry.Favorite) { "*" } else { "" })
        $row.Cells["Name"].Value = $entry.Name
        $row.Cells["Extension"].Value = $entry.Extension
        $row.Cells["Team"].Value = $entry.Team
        $row.Cells["Notes"].Value = $entry.Notes
        $row.Tag = $entry
    }
}

function Get-SelectedEntry {
    if ($Grid.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select an extension first.", "No extension selected", "OK", "Information") | Out-Null
        return $null
    }
    return $Grid.SelectedRows[0].Tag
}

function Show-EntryDialog {
    param([string]$Title, [object]$Entry)
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = $Title
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ClientSize = New-Object System.Drawing.Size(390, 220)

    $labels = @("Name", "Extension", "Group", "Notes")
    $boxes = @{}
    for ($i = 0; $i -lt $labels.Count; $i++) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $labels[$i]
        $label.Location = New-Object System.Drawing.Point(16, (22 + ($i * 36)))
        $label.Size = New-Object System.Drawing.Size(80, 22)
        $dialog.Controls.Add($label)

        $box = New-Object System.Windows.Forms.TextBox
        $box.Location = New-Object System.Drawing.Point(104, (18 + ($i * 36)))
        $box.Size = New-Object System.Drawing.Size(250, 24)
        $boxes[$labels[$i]] = $box
        $dialog.Controls.Add($box)
    }

    $favorite = New-Object System.Windows.Forms.CheckBox
    $favorite.Text = "Favorite"
    $favorite.Location = New-Object System.Drawing.Point(104, 162)
    $favorite.Size = New-Object System.Drawing.Size(120, 24)
    $dialog.Controls.Add($favorite)

    if ($Entry) {
        $boxes["Name"].Text = $Entry.Name
        $boxes["Extension"].Text = $Entry.Extension
        $boxes["Group"].Text = $Entry.Team
        $boxes["Notes"].Text = $Entry.Notes
        $favorite.Checked = [bool]$Entry.Favorite
    }

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Location = New-Object System.Drawing.Point(178, 184)
    $cancel.Size = New-Object System.Drawing.Size(84, 28)
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dialog.CancelButton = $cancel
    $dialog.Controls.Add($cancel)

    $save = New-Object System.Windows.Forms.Button
    $save.Text = "Save"
    $save.Location = New-Object System.Drawing.Point(270, 184)
    $save.Size = New-Object System.Drawing.Size(84, 28)
    $save.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.AcceptButton = $save
    $dialog.Controls.Add($save)

    while ($dialog.ShowDialog($Form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $name = $boxes["Name"].Text.Trim()
        $extension = Normalize-Extension $boxes["Extension"].Text
        if ([string]::IsNullOrWhiteSpace($name)) {
            [System.Windows.Forms.MessageBox]::Show("Enter a name for this extension.", "Missing name", "OK", "Error") | Out-Null
            continue
        }
        if ([string]::IsNullOrWhiteSpace($extension)) {
            [System.Windows.Forms.MessageBox]::Show("Enter a dialable extension.", "Missing extension", "OK", "Error") | Out-Null
            continue
        }
        return New-ExtensionEntry -Name $name -Extension $extension -Team $boxes["Group"].Text -Notes $boxes["Notes"].Text -Favorite $favorite.Checked
    }
    return $null
}

function Send-Extension {
    param([object]$Entry)
    [System.Windows.Forms.Clipboard]::SetText($Entry.Extension)
    if ($CopyOnlyCheck.Checked) {
        $StatusLabel.Text = "Copied $($Entry.Extension) for $($Entry.Name)."
        return
    }
    if ($LastExternalWindow -eq [IntPtr]::Zero -or -not [Win32CanYouDialMeNow]::IsWindow($LastExternalWindow)) {
        $StatusLabel.Text = "Copied $($Entry.Extension). Click the VOIP dial field, then press Ctrl+V."
        return
    }
    [Win32CanYouDialMeNow]::SetForegroundWindow($LastExternalWindow) | Out-Null
    Start-Sleep -Milliseconds 120
    [System.Windows.Forms.SendKeys]::SendWait("^v")
    $StatusLabel.Text = "Sent $($Entry.Extension) for $($Entry.Name)."
}

[System.Windows.Forms.Application]::EnableVisualStyles()
$Form = New-Object System.Windows.Forms.Form
$Form.Text = $AppTitle
$Form.StartPosition = "CenterScreen"
$Form.MinimumSize = New-Object System.Drawing.Size(700, 460)
$Form.Size = New-Object System.Drawing.Size(820, 560)

$SearchLabel = New-Object System.Windows.Forms.Label
$SearchLabel.Text = "Search"
$SearchLabel.Location = New-Object System.Drawing.Point(12, 18)
$SearchLabel.Size = New-Object System.Drawing.Size(48, 22)
$Form.Controls.Add($SearchLabel)

$SearchBox = New-Object System.Windows.Forms.TextBox
$SearchBox.Location = New-Object System.Drawing.Point(64, 14)
$SearchBox.Anchor = "Top,Left,Right"
$SearchBox.Size = New-Object System.Drawing.Size(330, 24)
$Form.Controls.Add($SearchBox)

$GroupLabel = New-Object System.Windows.Forms.Label
$GroupLabel.Text = "Group"
$GroupLabel.Anchor = "Top,Right"
$GroupLabel.Location = New-Object System.Drawing.Point(410, 18)
$GroupLabel.Size = New-Object System.Drawing.Size(48, 22)
$Form.Controls.Add($GroupLabel)

$GroupCombo = New-Object System.Windows.Forms.ComboBox
$GroupCombo.DropDownStyle = "DropDownList"
$GroupCombo.Anchor = "Top,Right"
$GroupCombo.Location = New-Object System.Drawing.Point(462, 14)
$GroupCombo.Size = New-Object System.Drawing.Size(150, 24)
$Form.Controls.Add($GroupCombo)

$AddButton = New-Object System.Windows.Forms.Button
$AddButton.Text = "Add"
$AddButton.Anchor = "Top,Right"
$AddButton.Location = New-Object System.Drawing.Point(622, 12)
$AddButton.Size = New-Object System.Drawing.Size(54, 28)
$Form.Controls.Add($AddButton)

$ImportButton = New-Object System.Windows.Forms.Button
$ImportButton.Text = "Import"
$ImportButton.Anchor = "Top,Right"
$ImportButton.Location = New-Object System.Drawing.Point(682, 12)
$ImportButton.Size = New-Object System.Drawing.Size(58, 28)
$Form.Controls.Add($ImportButton)

$ExportButton = New-Object System.Windows.Forms.Button
$ExportButton.Text = "Export"
$ExportButton.Anchor = "Top,Right"
$ExportButton.Location = New-Object System.Drawing.Point(746, 12)
$ExportButton.Size = New-Object System.Drawing.Size(58, 28)
$Form.Controls.Add($ExportButton)

$CopyOnlyCheck = New-Object System.Windows.Forms.CheckBox
$CopyOnlyCheck.Text = "Copy only"
$CopyOnlyCheck.Location = New-Object System.Drawing.Point(12, 48)
$CopyOnlyCheck.Size = New-Object System.Drawing.Size(110, 24)
$Form.Controls.Add($CopyOnlyCheck)

$Grid = New-Object System.Windows.Forms.DataGridView
$Grid.Location = New-Object System.Drawing.Point(12, 78)
$Grid.Size = New-Object System.Drawing.Size(792, 370)
$Grid.Anchor = "Top,Bottom,Left,Right"
$Grid.AllowUserToAddRows = $false
$Grid.AllowUserToDeleteRows = $false
$Grid.MultiSelect = $false
$Grid.ReadOnly = $true
$Grid.RowHeadersVisible = $false
$Grid.SelectionMode = "FullRowSelect"
$Grid.AutoSizeColumnsMode = "Fill"
$Grid.Columns.Add("Favorite", "*") | Out-Null
$Grid.Columns.Add("Name", "Name") | Out-Null
$Grid.Columns.Add("Extension", "Extension") | Out-Null
$Grid.Columns.Add("Team", "Group") | Out-Null
$Grid.Columns.Add("Notes", "Notes") | Out-Null
$Grid.Columns["Favorite"].FillWeight = 15
$Grid.Columns["Extension"].FillWeight = 40
$Grid.Columns["Team"].FillWeight = 55
$Form.Controls.Add($Grid)

$DialButton = New-Object System.Windows.Forms.Button
$DialButton.Text = "Dial Selected"
$DialButton.Anchor = "Bottom,Right"
$DialButton.Location = New-Object System.Drawing.Point(488, 458)
$DialButton.Size = New-Object System.Drawing.Size(104, 30)
$Form.Controls.Add($DialButton)

$EditButton = New-Object System.Windows.Forms.Button
$EditButton.Text = "Edit"
$EditButton.Anchor = "Bottom,Right"
$EditButton.Location = New-Object System.Drawing.Point(600, 458)
$EditButton.Size = New-Object System.Drawing.Size(96, 30)
$Form.Controls.Add($EditButton)

$DeleteButton = New-Object System.Windows.Forms.Button
$DeleteButton.Text = "Delete"
$DeleteButton.Anchor = "Bottom,Right"
$DeleteButton.Location = New-Object System.Drawing.Point(704, 458)
$DeleteButton.Size = New-Object System.Drawing.Size(100, 30)
$Form.Controls.Add($DeleteButton)

$StatusLabel = New-Object System.Windows.Forms.Label
$StatusLabel.Anchor = "Bottom,Left,Right"
$StatusLabel.Location = New-Object System.Drawing.Point(12, 496)
$StatusLabel.Size = New-Object System.Drawing.Size(792, 22)
$StatusLabel.Text = "Click inside your VOIP dial field once, then use a Dial button here."
$Form.Controls.Add($StatusLabel)

$SearchBox.Add_TextChanged({ Refresh-Grid })
$GroupCombo.Add_SelectedIndexChanged({ Refresh-Grid })

$AddButton.Add_Click({
    $entry = Show-EntryDialog -Title "Add Extension"
    if ($entry) { [void]$Entries.Add($entry); Save-Entries; Refresh-Groups; Refresh-Grid; $StatusLabel.Text = "Added $($entry.Name)." }
})

$EditButton.Add_Click({
    $entry = Get-SelectedEntry
    if (-not $entry) { return }
    $updated = Show-EntryDialog -Title "Edit Extension" -Entry $entry
    if ($updated) { $Entries[$Entries.IndexOf($entry)] = $updated; Save-Entries; Refresh-Groups; Refresh-Grid; $StatusLabel.Text = "Updated $($updated.Name)." }
})

$DeleteButton.Add_Click({
    $entry = Get-SelectedEntry
    if (-not $entry) { return }
    $confirm = [System.Windows.Forms.MessageBox]::Show("Delete $($entry.Name) ($($entry.Extension))?", "Delete extension", "YesNo", "Question")
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) { $Entries.Remove($entry); Save-Entries; Refresh-Groups; Refresh-Grid; $StatusLabel.Text = "Deleted $($entry.Name)." }
})

$DialButton.Add_Click({ $entry = Get-SelectedEntry; if ($entry) { Send-Extension -Entry $entry } })
$Grid.Add_CellDoubleClick({ $entry = Get-SelectedEntry; if ($entry) { Send-Extension -Entry $entry } })

$ImportButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
    if ($dialog.ShowDialog($Form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $count = 0
    foreach ($row in Import-Csv -LiteralPath $dialog.FileName) {
        $name = if ($row.Name) { $row.Name } else { $row.name }
        $extension = if ($row.Extension) { $row.Extension } else { $row.extension }
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace((Normalize-Extension $extension))) { continue }
        $team = if ($row.Team) { $row.Team } elseif ($row.Group) { $row.Group } else { $row.team }
        $notes = if ($row.Notes) { $row.Notes } else { $row.notes }
        $favoriteText = if ($row.Favorite) { $row.Favorite } else { $row.favorite }
        $favorite = "$favoriteText".ToLowerInvariant() -in @("1", "true", "yes", "y")
        [void]$Entries.Add((New-ExtensionEntry -Name $name -Extension $extension -Team $team -Notes $notes -Favorite $favorite))
        $count++
    }
    Save-Entries; Refresh-Groups; Refresh-Grid; $StatusLabel.Text = "Imported $count extension entries."
})

$ExportButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = "CSV files (*.csv)|*.csv"
    $dialog.DefaultExt = "csv"
    if ($dialog.ShowDialog($Form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $Entries | Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Encoding UTF8
    $StatusLabel.Text = "Exported $($Entries.Count) extension entries."
})

$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = 250
$Timer.Add_Tick({
    $hwnd = [Win32CanYouDialMeNow]::GetForegroundWindow()
    if ($hwnd -ne [IntPtr]::Zero) {
        [uint32]$pid = 0
        [Win32CanYouDialMeNow]::GetWindowThreadProcessId($hwnd, [ref]$pid) | Out-Null
        if ($pid -ne $OwnProcessId) { $script:LastExternalWindow = $hwnd }
    }
})

Load-Entries
Refresh-Groups
Refresh-Grid
$Timer.Start()
[void]$Form.ShowDialog()
