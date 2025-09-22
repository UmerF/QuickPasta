# QuickPastaManager.ps1 - GUI for managing QuickPasta profiles
#                   (c) 2025 by Umer Farooq
# Usage: run this script with PowerShell 5.1+ (Windows 10+)
# Note: requires .NET Framework 4.5+ (default on Windows 8+)
# Note: requires Windows PowerShell, not PowerShell Core (6+)
# Note: requires Windows Presentation Framework (WPF) - included with Windows
# Note: requires 'profiles.json' in the same folder (created automatically if missing)
# Note: requires 'Install_QuickPasta.vbs' and 'Uninstall_QuickPasta.vbs' in the same folder
# Note: requires 'QuickPasta.ico' in the same folder (optional, for window icon)
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
$ErrorActionPreference = 'Stop'

# ---------- Paths ----------
$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProfilesPath = Join-Path $ScriptDir 'profiles.json'
$InstallVbs   = Join-Path $ScriptDir 'Install_QuickPasta.vbs'
$UninstallVbs = Join-Path $ScriptDir 'Uninstall_QuickPasta.vbs'
$IcoPath      = Join-Path $ScriptDir 'QuickPasta.ico'

# ---------- Strongly-typed row (C#5-safe) ----------
Add-Type -TypeDefinition @"
using System.ComponentModel;

public class ProfileRow : INotifyPropertyChanged
{
  private string _name;
  private string _source;

  public string Name
  {
    get { return _name; }
    set
    {
      if (_name != value)
      {
        _name = value;
        var h = PropertyChanged;
        if (h != null) h(this, new PropertyChangedEventArgs("Name"));
      }
    }
  }

  public string Source
  {
    get { return _source; }
    set
    {
      if (_source != value)
      {
        _source = value;
        var h = PropertyChanged;
        if (h != null) h(this, new PropertyChangedEventArgs("Source"));
      }
    }
  }

  public event PropertyChangedEventHandler PropertyChanged;
}
"@ -Language CSharp


# ---------- Helpers ----------
function Load-Profiles {
  if (!(Test-Path -LiteralPath $ProfilesPath)) { return [ordered]@{} }
  $json = Get-Content -LiteralPath $ProfilesPath -Raw
  if ([string]::IsNullOrWhiteSpace($json)) { return [ordered]@{} }
  try {
    $o = $json | ConvertFrom-Json
    $map = [ordered]@{}
    foreach ($p in $o.PSObject.Properties) { $map[$p.Name] = $p.Value }
    return $map
  } catch {
    [System.Windows.MessageBox]::Show("profiles.json is invalid JSON.`n$($_.Exception.Message)","QuickPasta",'OK','Error')|Out-Null
    return [ordered]@{}
  }
}

# Save in current UI order (Rows)
function Save-Profiles {
  $o = [ordered]@{}
  foreach ($row in $Rows) {
    $name = $row.Name
    $val  = $Profiles[$name]
    $o[$name] = $val
  }
  $o | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ProfilesPath -Encoding UTF8
}

function Parse-Renames([string]$text) {
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }
  $rules = New-Object System.Collections.Generic.List[object]
  foreach ($line in ($text -split "`r?`n")) {
    $s = $line.Trim(); if (-not $s) { continue }
    if ($s -match '^\s*(.+?)\s*->\s*(.+?)\s*$') { $from=$matches[1].Trim(); $to=$matches[2].Trim() }
    elseif ($s -match '^\s*([^,]+?)\s*,\s*(.+?)\s*$') { $from=$matches[1].Trim(); $to=$matches[2].Trim() }
    else { continue }
    $rules.Add([pscustomobject]@{ from=$from; to=$to }) | Out-Null
  }
  if ($rules.Count -eq 0) { return $null }
  return $rules.ToArray()
}
function Build-RenamesText($rules) { if (-not $rules) { '' } else { ($rules | ForEach-Object { "$($_.from) -> $($_.to)" }) -join [Environment]::NewLine } }

function Pick-Folder([string]$startPath) {
  Add-Type -AssemblyName System.Windows.Forms

  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Title = "Select a folder"
  $dlg.Filter = "Folders|*.*"          # cosmetic; we're not picking a real file
  $dlg.CheckFileExists = $false
  $dlg.CheckPathExists = $true
  $dlg.ValidateNames = $false
  $dlg.FileName = "Select this folder" # fake file name to allow folder selection

  if ($startPath -and (Test-Path $startPath)) {
    $dlg.InitialDirectory = (Resolve-Path $startPath).Path
  }

  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    # Strip the fake file name, return the chosen directory
    $dir = [System.IO.Path]::GetDirectoryName($dlg.FileName)
    if ([string]::IsNullOrEmpty($dir)) { $dir = [System.IO.Path]::GetPathRoot($dlg.FileName) }
    return $dir
  }
  return $null
}

# ---- VBS runner: **no wait**, so Manager never hangs
function Run-Vbs([string]$file) {
  if (!(Test-Path -LiteralPath $file)) { [System.Windows.MessageBox]::Show("Not found: $file","QuickPasta",'OK','Error')|Out-Null; return }
  $psi = [System.Diagnostics.ProcessStartInfo]::new("wscript.exe", '"' + $file + '"')
  $psi.UseShellExecute = $true
  $psi.WindowStyle = 'Hidden'
  [System.Diagnostics.Process]::Start($psi) | Out-Null
}

# ---------- XAML ----------
$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='QuickPasta Manager' Height='560' Width='1000'
        Background='#F8FAFC' WindowStartupLocation='CenterScreen'
        SnapsToDevicePixels='True' UseLayoutRounding='True'>

  <Window.Resources>
    <SolidColorBrush x:Key='CardBg'     Color='#FFFFFFFF'/>
    <SolidColorBrush x:Key='CardBorder' Color='#E5E7EB'/>
    <SolidColorBrush x:Key='Ink'        Color='#111827'/>
    <SolidColorBrush x:Key='InkSubtle'  Color='#374151'/>
    <SolidColorBrush x:Key='Muted'      Color='#6B7280'/>
    <SolidColorBrush x:Key='Muted2'     Color='#9CA3AF'/>
    <SolidColorBrush x:Key='Accent'     Color='#2563EB'/>

    <SolidColorBrush x:Key='QP_RowHover'   Color='#F3F4F6'/>
    <SolidColorBrush x:Key='QP_RowSelect'  Color='#E8F0FE'/>
    <SolidColorBrush x:Key='QP_RowBorder'  Color='#BBD2FD'/>

    <Style x:Key='Heading' TargetType='TextBlock'>
      <Setter Property='FontSize' Value='18'/>
      <Setter Property='FontWeight' Value='SemiBold'/>
      <Setter Property='Foreground' Value='{StaticResource Ink}'/>
      <Setter Property='Margin' Value='0,0,0,12'/>
    </Style>
    <Style x:Key='Label' TargetType='TextBlock'>
      <Setter Property='Foreground' Value='{StaticResource InkSubtle}'/>
      <Setter Property='Margin' Value='0,8,12,4'/>
    </Style>
    <Style x:Key='TextInput' TargetType='TextBox'>
      <Setter Property='Padding' Value='10,8'/>
      <Setter Property='Margin' Value='0,0,0,12'/>
      <Setter Property='BorderBrush' Value='#D1D5DB'/>
      <Setter Property='BorderThickness' Value='1'/>
      <Setter Property='Background' Value='White'/>
      <Setter Property='SnapsToDevicePixels' Value='True'/>
    </Style>
    <Style x:Key='BaseButton' TargetType='Button'>
      <Setter Property='Padding' Value='14,10'/>
      <Setter Property='Margin' Value='8,0,0,0'/>
      <Setter Property='Foreground' Value='{StaticResource Ink}'/>
      <Setter Property='Background' Value='#F3F4F6'/>
      <Setter Property='BorderBrush' Value='#D1D5DB'/>
      <Setter Property='BorderThickness' Value='1'/>
      <Setter Property='Cursor' Value='Hand'/>
      <Setter Property='Template'>
        <Setter.Value>
          <ControlTemplate TargetType='Button'>
            <Border CornerRadius='8' Background='{TemplateBinding Background}'
                    BorderBrush='{TemplateBinding BorderBrush}'
                    BorderThickness='{TemplateBinding BorderThickness}' Padding='4'>
              <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center' Margin='6,2,6,2'/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key='PrimaryButton' TargetType='Button' BasedOn='{StaticResource BaseButton}'>
      <Setter Property='Background' Value='{StaticResource Accent}'/>
      <Setter Property='Foreground' Value='White'/>
      <Setter Property='BorderBrush' Value='{StaticResource Accent}'/>
    </Style>
    <Style x:Key='DangerButton' TargetType='Button' BasedOn='{StaticResource BaseButton}'>
      <Setter Property='Background' Value='#DC2626'/>
      <Setter Property='Foreground' Value='White'/>
      <Setter Property='BorderBrush' Value='#DC2626'/>
    </Style>

    <Style x:Key='CenterHeader' TargetType='{x:Type GridViewColumnHeader}'>
      <Setter Property='HorizontalContentAlignment' Value='Center'/>
    </Style>

    <Style TargetType='{x:Type ListView}'>
      <Setter Property='BorderThickness' Value='0'/>
      <Setter Property='SnapsToDevicePixels' Value='True'/>
      <Setter Property='ScrollViewer.HorizontalScrollBarVisibility' Value='Disabled'/>
      <Setter Property='VirtualizingStackPanel.IsVirtualizing' Value='True'/>
      <Setter Property='ScrollViewer.CanContentScroll' Value='True'/>
    </Style>
    <Style x:Key='QPListItemStyle' TargetType='{x:Type ListViewItem}'>
      <Setter Property='Padding' Value='8,6'/>
      <Setter Property='Margin' Value='0,2,0,2'/>
      <Setter Property='BorderThickness' Value='1'/>
      <Setter Property='BorderBrush' Value='Transparent'/>
      <Setter Property='Background' Value='Transparent'/>
      <Setter Property='HorizontalContentAlignment' Value='Stretch'/>
      <Setter Property='VerticalContentAlignment' Value='Center'/>
      <Setter Property='FocusVisualStyle' Value='{x:Null}'/>
      <Setter Property='Template'>
        <Setter.Value>
          <ControlTemplate TargetType='{x:Type ListViewItem}'>
            <Border x:Name='Row' CornerRadius='8'
                    Background='{TemplateBinding Background}'
                    BorderBrush='{TemplateBinding BorderBrush}'
                    BorderThickness='{TemplateBinding BorderThickness}'>
              <GridViewRowPresenter
                 Columns='{Binding RelativeSource={RelativeSource AncestorType=ListView}, Path=View.Columns}'
                 Margin='6,2,6,2'/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property='IsMouseOver' Value='True'>
                <Setter TargetName='Row' Property='Background' Value='{StaticResource QP_RowHover}'/>
              </Trigger>
              <Trigger Property='IsSelected' Value='True'>
                <Setter TargetName='Row' Property='Background' Value='#E8F0FE'/>
                <Setter TargetName='Row' Property='BorderBrush'  Value='#BBD2FD'/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid Margin='16'>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width='*'/>
      <ColumnDefinition Width='16'/>
      <ColumnDefinition Width='1.2*'/>
    </Grid.ColumnDefinitions>

    <!-- Left Card -->
    <Border Grid.Column='0' Background='{StaticResource CardBg}' CornerRadius='14'
            BorderBrush='{StaticResource CardBorder}' BorderThickness='1' Padding='16'>
      <Border.Effect><DropShadowEffect Color='#000' Opacity='0.08' BlurRadius='14' ShadowDepth='0'/></Border.Effect>
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height='Auto'/>
          <RowDefinition Height='*'/>
          <RowDefinition Height='Auto'/>
        </Grid.RowDefinitions>
        <TextBlock Text='Profiles' Style='{StaticResource Heading}'/>
        <ListView Name='lvProfiles' Grid.Row='1' Margin='0,8,0,12' ItemContainerStyle='{StaticResource QPListItemStyle}'>
          <ListView.View>
            <GridView x:Name='gvProfiles' AllowsColumnReorder='False'>
              <GridViewColumn Header='Name' HeaderContainerStyle='{StaticResource CenterHeader}' DisplayMemberBinding='{Binding Name}'/>
              <GridViewColumn Header='Source / Type' HeaderContainerStyle='{StaticResource CenterHeader}' DisplayMemberBinding='{Binding Source}'/>
            </GridView>
          </ListView.View>
        </ListView>
        <StackPanel Grid.Row='2' Orientation='Horizontal' HorizontalAlignment='Left' Margin='-8,0,0,0'>
          <Button Name='btnAdd'     Style='{StaticResource BaseButton}'    Content='Add'/>
          <Button Name='btnRemove'  Style='{StaticResource BaseButton}'    Content='Remove'/>
          <Button Name='btnUp'      Style='{StaticResource BaseButton}'    Content='Move ↑'/>
          <Button Name='btnDown'    Style='{StaticResource BaseButton}'    Content='Move ↓'/>
          <Button Name='btnSave'    Style='{StaticResource PrimaryButton}' Content='Save'/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- Right Card -->
    <Border Grid.Column='2' Background='{StaticResource CardBg}' CornerRadius='14'
            BorderBrush='{StaticResource CardBorder}' BorderThickness='1' Padding='16'>
      <Border.Effect><DropShadowEffect Color='#000' Opacity='0.08' BlurRadius='14' ShadowDepth='0'/></Border.Effect>
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height='Auto'/>
          <RowDefinition Height='Auto'/>
          <RowDefinition Height='Auto'/>
          <RowDefinition Height='Auto'/>
          <RowDefinition Height='Auto'/>
          <RowDefinition Height='*'/>
          <RowDefinition Height='Auto'/>
          <RowDefinition Height='Auto'/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width='Auto'/>
          <ColumnDefinition Width='*'/>
          <ColumnDefinition Width='Auto'/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Row='0' Grid.ColumnSpan='3' Text='Profile Details' Style='{StaticResource Heading}'/>
        <TextBlock Grid.Row='1' Grid.Column='0' Text='Name' Style='{StaticResource Label}'/>
        <TextBox   Grid.Row='1' Grid.Column='1' Name='txtName' Style='{StaticResource TextInput}'/>
        <TextBlock Grid.Row='2' Grid.Column='0' Text='Source' Style='{StaticResource Label}'/>
        <TextBox   Grid.Row='2' Grid.Column='1' Name='txtSource' Style='{StaticResource TextInput}'/>
        <Button    Grid.Row='2' Grid.Column='2' Name='btnBrowse' Content='Browse' Style='{StaticResource BaseButton}' Margin='8,0,0,12'/>
        <TextBlock Grid.Row='3' Grid.ColumnSpan='3' Text='Tip: source can be a local folder or a URL (zip files supported) (https://...)' Foreground='{StaticResource Muted}' Margin='4,0,0,8' TextWrapping='Wrap'/>
        <TextBlock Grid.Row='4' Grid.ColumnSpan='3' Text='Renames (optional)' Style='{StaticResource Label}'/>
        <Grid Grid.Row='5' Grid.ColumnSpan='3'>
          <TextBox Name='txtRen' AcceptsReturn='True' VerticalScrollBarVisibility='Auto' Style='{StaticResource TextInput}' MinHeight='220' VerticalAlignment='Stretch' TextWrapping='Wrap' Margin='0,0,0,6'/>
          <TextBlock Name='hintRen' Text='Format: one per line —  ReShade64.dll -> dxgi.dll    or    *.cfg, settings.cfg' Foreground='{StaticResource Muted2}' Margin='8,0,0,12' VerticalAlignment='Bottom' IsHitTestVisible='False'/>
        </Grid>
        <StackPanel Grid.Row='7' Grid.ColumnSpan='3' Orientation='Horizontal' HorizontalAlignment='Right'>
          <Button Name='btnApplyInstall' Style='{StaticResource PrimaryButton}'  Content='Apply + Install/Update'/>
          <Button Name='btnUninstall'    Style='{StaticResource DangerButton}'   Content='Uninstall Menu'/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

# ---------- Build window ----------
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$window.FontFamily = 'Segoe UI Variable, Segoe UI'; $window.FontSize = 12

# Icon
if (Test-Path -LiteralPath $IcoPath) {
  try {
    $uri=[Uri]$IcoPath
    $decoder = New-Object Windows.Media.Imaging.IconBitmapDecoder($uri,[Windows.Media.Imaging.BitmapCreateOptions]::None,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $window.Icon = $decoder.Frames[0]
  } catch {}
}

# ---------- Controls ----------
$lv         = $window.FindName('lvProfiles')
$txtName    = $window.FindName('txtName')
$txtSource  = $window.FindName('txtSource')
$txtRen     = $window.FindName('txtRen')
$hintRen    = $window.FindName('hintRen')
$btnBrowse  = $window.FindName('btnBrowse')
$btnAdd     = $window.FindName('btnAdd')
$btnRemove  = $window.FindName('btnRemove')
$btnUp      = $window.FindName('btnUp')
$btnDown    = $window.FindName('btnDown')
$btnSave    = $window.FindName('btnSave')
$btnApply   = $window.FindName('btnApplyInstall')
$btnUninst  = $window.FindName('btnUninstall')

# ---------- Data ----------
$Rows     = New-Object System.Collections.ObjectModel.ObservableCollection[ProfileRow]
$Profiles = Load-Profiles
function Refresh-Rows {
  $Rows.Clear()
  foreach ($k in $Profiles.Keys) {
    $v = $Profiles[$k]
    if ($v -is [string]) { $src = $v }
    else {
      $src = [string]($v | Select-Object -ExpandProperty source -ErrorAction SilentlyContinue)
      if (-not $src) { $src = [string]($v | Select-Object -ExpandProperty path -ErrorAction SilentlyContinue) }
      if (-not $src) { $src = '' }
    }
    $row = New-Object ProfileRow
    $row.Name   = $k
    $row.Source = $src
    $Rows.Add($row) | Out-Null
  }
}
$lv.ItemsSource = $Rows

# equal columns at load / resize
$initSized = $false; $padding = 40
function Get-Columns { $gv=[System.Windows.Controls.GridView]$lv.View; if (-not $gv -or $gv.Columns.Count -lt 2) { return $null }; ,$gv,$gv.Columns[0],$gv.Columns[1] }
$lv.Add_Loaded({ $cols=Get-Columns; if ($cols){ $gv,$c1,$c2=$cols; $avail=[Math]::Max(100.0,$lv.ActualWidth-$padding); $c1.Width=[Math]::Round($avail/2.0); $c2.Width=$avail-$c1.Width; $initSized=$true } })
$lv.Add_SizeChanged({ if ($initSized){ $cols=Get-Columns; if ($cols){ $gv,$c1,$c2=$cols; $c2.Width=[Math]::Max(100.0,$lv.ActualWidth-$c1.Width-$padding) } } })

# selection sync
function Load-Selected {
  if (-not $lv.SelectedItem) { $txtName.Clear(); $txtSource.Clear(); $txtRen.Clear(); return }
  $row  = [ProfileRow]$lv.SelectedItem
  $val  = $Profiles[$row.Name]
  $txtName.Text = $row.Name
  if ($val -is [string]) { $txtSource.Text = $val; $txtRen.Text = '' }
  else {
    $src = [string]($val | Select-Object -ExpandProperty source -ErrorAction SilentlyContinue)
    if (-not $src) { $src = [string]($val | Select-Object -ExpandProperty path -ErrorAction SilentlyContinue) }
    $txtSource.Text = $src
    $txtRen.Text    = Build-RenamesText ($val.renames)
  }
}
$lv.Add_SelectionChanged({ Load-Selected })

# hint
$updateHint = { $hintRen.Visibility = $(if ([string]::IsNullOrWhiteSpace($txtRen.Text)) { 'Visible' } else { 'Collapsed' }) }
$txtRen.Add_TextChanged($updateHint); $txtRen.Add_GotFocus($updateHint); $txtRen.Add_LostFocus($updateHint)

# move ↑ / ↓
function Move-Selected([int]$delta) {
  $i = $lv.SelectedIndex; if ($i -lt 0) { return }
  $j = [Math]::Max(0, [Math]::Min($Rows.Count-1, $i + $delta))
  if ($j -eq $i) { return }
  $item = $Rows[$i]; $Rows.RemoveAt($i); $Rows.Insert($j,$item); $lv.SelectedIndex=$j; $lv.ScrollIntoView($item)
}
$btnUp.Add_Click({   Move-Selected -delta -1 })
$btnDown.Add_Click({ Move-Selected -delta  1 })

# Ctrl+Up / Ctrl+Down on the list move the selected row
$lv.Add_PreviewKeyDown({
    param($s,$e)
    if ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) {
        if ($e.Key -eq [System.Windows.Input.Key]::Up)   { Move-Selected -delta -1; $e.Handled = $true }
        if ($e.Key -eq [System.Windows.Input.Key]::Down) { Move-Selected -delta  1; $e.Handled = $true }
    }
})

# Make sure click focuses the list so the shortcuts work immediately
$lv.Add_PreviewMouseDown({ $lv.Focus() })


# add/remove/save
$btnAdd.Add_Click({ $txtName.Text=''; $txtSource.Text=''; $txtRen.Text=''; $lv.SelectedIndex=-1; $txtName.Focus() })
$btnRemove.Add_Click({ if (-not $lv.SelectedItem){return}; $name=([ProfileRow]$lv.SelectedItem).Name; $Profiles.Remove($name)|Out-Null; $Rows.Remove($lv.SelectedItem)|Out-Null })

function Save-Current-ToMap {
  $name = $txtName.Text.Trim()
  $src  = $txtSource.Text.Trim()
  if (-not $name) { [System.Windows.MessageBox]::Show("Name is required.","QuickPasta")|Out-Null; return $false }
  if (-not $src)  { [System.Windows.MessageBox]::Show("Source is required (folder or URL).","QuickPasta")|Out-Null; return $false }
  $rules = Parse-Renames $txtRen.Text
  if ($rules) { $Profiles[$name] = [pscustomobject]@{ source=$src; renames=$rules } } else { $Profiles[$name] = $src }
  $existing = $Rows | Where-Object Name -eq $name | Select-Object -First 1
  if ($existing) { $existing.Source = $src; $lv.SelectedItem=$existing }
  else { $row = New-Object ProfileRow; $row.Name=$name; $row.Source=$src; $Rows.Add($row)|Out-Null; $lv.SelectedItem=$row }
  return $true
}
$btnSave.Add_Click({ if (Save-Current-ToMap) { Save-Profiles; [System.Windows.MessageBox]::Show("Saved profiles.json","QuickPasta")|Out-Null } })

# browse
$btnBrowse.Add_Click({ $p = Pick-Folder $txtSource.Text; if ($p) { $txtSource.Text = $p } })

# apply / uninstall — just call the VBS (non-blocking)
$btnApply.Add_Click({ if (Save-Current-ToMap) { Save-Profiles; Run-Vbs $InstallVbs } })
$btnUninst.Add_Click({ Run-Vbs $UninstallVbs })

# ---------- Run ----------
Refresh-Rows
$updateHint.Invoke()
$null = $window.ShowDialog()
