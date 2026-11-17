# AW2521HFL Control
# Unified build: Version B's DDC/CI core (unchanged) under Version A's Quick Settings flyout.
# Requires Windows PowerShell 5.1+ (STA) and DDC/CI enabled in the monitor OSD.

param(
    [switch]$ShowOnStart
)

$script:Root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$script:AppDir = Join-Path $env:APPDATA 'AW2521HFL-Control'
$script:SettingsPath = Join-Path $script:AppDir 'settings.json'
$script:LogPath = Join-Path $script:AppDir 'last-error.log'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    [System.Windows.Forms.MessageBox]::Show(
        'Start this script from Start-AW2521HFL-Control.cmd. It needs PowerShell in single-threaded apartment (-STA) mode.',
        'AW2521HFL Control') | Out-Null
    return
}

# =====================================================================================
#  DDC/CI CORE - COPIED VERBATIM FROM THE WORKING VERSION. DO NOT ADD HANDLE GUARDS.
#  The previous rewrite added an Alive/Invalidate check here and it silently blocked
#  every read and write. Nothing in this block should change.
# =====================================================================================

if (-not ("MonitorDdc" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public sealed class MonitorInfo {
    internal IntPtr Handle;
    public string Description { get; internal set; }
    public uint BrightnessMaximum { get; internal set; }
    public override string ToString() { return Description; }
}

public static class MonitorDdc {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct PHYSICAL_MONITOR {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData);
    private static readonly MonitorEnumProc monitorEnumCallback = EnumerateMonitor;

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc callback, IntPtr data);
    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint numberOfPhysicalMonitors);
    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint numberOfPhysicalMonitors, [Out] PHYSICAL_MONITOR[] physicalMonitorArray);
    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool DestroyPhysicalMonitors(uint numberOfPhysicalMonitors, PHYSICAL_MONITOR[] physicalMonitorArray);
    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr hMonitor, byte vcpCode, IntPtr pvct, out uint currentValue, out uint maximumValue);
    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool SetVCPFeature(IntPtr hMonitor, byte vcpCode, uint newValue);

    private static readonly List<PHYSICAL_MONITOR> handles = new List<PHYSICAL_MONITOR>();

    private static bool EnumerateMonitor(IntPtr hMonitor, IntPtr hdc, IntPtr rect, IntPtr data) {
        uint count;
        if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, out count) || count == 0) return true;
        PHYSICAL_MONITOR[] monitors = new PHYSICAL_MONITOR[count];
        if (GetPhysicalMonitorsFromHMONITOR(hMonitor, count, monitors)) handles.AddRange(monitors);
        return true;
    }

    public static MonitorInfo[] GetMonitors() {
        ReleaseAll();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, monitorEnumCallback, IntPtr.Zero);

        List<MonitorInfo> result = new List<MonitorInfo>();
        foreach (PHYSICAL_MONITOR monitor in handles) {
            uint current, maximum;
            GetVCPFeatureAndVCPFeatureReply(monitor.hPhysicalMonitor, 0x10, IntPtr.Zero, out current, out maximum);
            result.Add(new MonitorInfo { Handle = monitor.hPhysicalMonitor, Description = monitor.szPhysicalMonitorDescription, BrightnessMaximum = maximum == 0 ? 100 : maximum });
        }
        return result.ToArray();
    }

    public static bool TryGet(MonitorInfo monitor, byte code, out uint current, out uint maximum) {
        return GetVCPFeatureAndVCPFeatureReply(monitor.Handle, code, IntPtr.Zero, out current, out maximum);
    }
    public static bool TrySet(MonitorInfo monitor, byte code, uint value) {
        return SetVCPFeature(monitor.Handle, code, value);
    }
    public static void ReleaseAll() {
        if (handles.Count == 0) return;
        PHYSICAL_MONITOR[] values = handles.ToArray();
        DestroyPhysicalMonitors((uint)values.Length, values);
        handles.Clear();
    }
}
'@
}

# ===================================================================================
#  Shell helpers - hotkey, tray, single instance. Nothing here touches DDC/CI.
# ===================================================================================

if (-not ("Native" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class Native {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern uint RegisterWindowMessage(string lpString);
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr handle);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern IntPtr WindowFromPoint(POINT pt);
    [DllImport("user32.dll")]
    public static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")]
    public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    public static extern IntPtr GetModuleHandle(string lpModuleName);
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")]
    private static extern bool SetProcessWorkingSetSize(IntPtr process, IntPtr min, IntPtr max);

    public static readonly IntPtr HWND_BROADCAST = new IntPtr(0xFFFF);
    // GA_ROOT = 2: walk up to the top-level owner window
    public const uint GA_ROOT = 2;

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSLLHOOKSTRUCT {
        public POINT pt;
        public uint mouseData;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    public delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    public static void TrimWorkingSet() {
        try { SetProcessWorkingSetSize(GetCurrentProcess(), new IntPtr(-1), new IntPtr(-1)); } catch { }
    }
}
'@
}

$script:ShowMessage = [Native]::RegisterWindowMessage('AW2521HFL_Control_Show')
$script:instanceMutex = New-Object System.Threading.Mutex($false, 'Local\AW2521HFL-Control-SingleInstance')
if (-not $script:instanceMutex.WaitOne(0)) {
    [void][Native]::PostMessage([Native]::HWND_BROADCAST, $script:ShowMessage, [IntPtr]::Zero, [IntPtr]::Zero)
    exit
}

# ------------------------------------------------------------------- settings

$script:Defaults = [ordered]@{
    HotkeyModifiers   = 3
    HotkeyVirtualKey  = 120
    HotkeyText        = 'Ctrl+Alt+F9'
    HotkeyEnabled     = $true
    LastMode          = 'Standard Mode'
    StandardCode      = '0'
    StandardAuxCode   = '0'
    StandardColorCode = '5'
    ComfortCode       = '12'
    ComfortAuxCode    = '29'
}

function Import-Settings {
    $settings = @{}
    foreach ($key in $script:Defaults.Keys) { $settings[$key] = $script:Defaults[$key] }
    if (Test-Path -LiteralPath $script:SettingsPath) {
        try {
            $saved = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($key in @($settings.Keys)) {
                if ($null -ne $saved.PSObject.Properties[$key]) { $settings[$key] = $saved.$key }
            }
        } catch { }
    }
    return $settings
}

function Export-Settings {
    try {
        if (-not (Test-Path -LiteralPath $script:AppDir)) { New-Item -ItemType Directory -Path $script:AppDir -Force | Out-Null }
        ($script:Settings | ConvertTo-Json) | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
    } catch { }
}

$script:Settings = Import-Settings

# ------------------------------------------------------------------- interface

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AW2521HFL Control" Width="372" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="False" Topmost="True"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13" Foreground="#FFFFFF">
  <Window.Resources>
    <SolidColorBrush x:Key="Surface" Color="#2B2B2B"/>
    <SolidColorBrush x:Key="Edge" Color="#3D3D3D"/>
    <SolidColorBrush x:Key="Raised" Color="#333333"/>
    <SolidColorBrush x:Key="Accent" Color="#EE6C4D"/>
    <SolidColorBrush x:Key="Muted" Color="#9C9C9C"/>
    <SolidColorBrush x:Key="Track" Color="#5B5B5B"/>

    <Style x:Key="Glyph" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe Fluent Icons, Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="HorizontalAlignment" Value="Center"/>
    </Style>

    <Style x:Key="IconButton" TargetType="Button">
      <Setter Property="Width" Value="32"/><Setter Property="Height" Value="28"/>
      <Setter Property="Foreground" Value="#D6D6D6"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Chrome" Background="Transparent" CornerRadius="4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Chrome" Property="Background" Value="#3C3C3C"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Chrome" Property="Background" Value="#474747"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Segment" TargetType="Button">
      <Setter Property="Foreground" Value="#DEDEDE"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Background" Value="Transparent"/><Setter Property="Padding" Value="10,7"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Chrome" Background="{TemplateBinding Background}" CornerRadius="5" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Chrome" Property="Opacity" Value="0.85"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="Slider">
      <Setter Property="Height" Value="20"/>
      <Setter Property="IsMoveToPointEnabled" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Grid Background="Transparent">
              <Border Height="4" CornerRadius="2" Background="{StaticResource Track}" VerticalAlignment="Center"/>
              <Track x:Name="PART_Track" VerticalAlignment="Center">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="Slider.DecreaseLarge">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton"><Border Height="4" CornerRadius="2" Background="{StaticResource Accent}"/></ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Width="14" Height="14">
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb"><Border Width="14" Height="14" CornerRadius="7" Background="{StaticResource Accent}"/></ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="Slider.IncreaseLarge">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.IncreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#1F1F1F"/><Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="BorderBrush" Value="#4A4A4A"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="6,3"/><Setter Property="FontSize" Value="12"/>
      <Setter Property="CaretBrush" Value="#FFFFFF"/>
    </Style>

    <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#DEDEDE"/><Setter Property="FontSize" Value="12"/></Style>

    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="#FFFFFF"/><Setter Property="FontSize" Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="Toggle" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="Chrome" Background="Transparent" CornerRadius="4" Padding="4,3">
                      <Grid>
                        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="16"/></Grid.ColumnDefinitions>
                        <ContentPresenter Grid.Column="0" VerticalAlignment="Center"/>
                        <Path Grid.Column="1" Fill="#9C9C9C" VerticalAlignment="Center" HorizontalAlignment="Center" Data="M 0 0 L 7 0 L 3.5 4.5 Z"/>
                      </Grid>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Chrome" Property="Background" Value="#3C3C3C"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
                <ContentPresenter Content="{TemplateBinding SelectionBoxItem}" TextBlock.Foreground="#FFFFFF"/>
              </ToggleButton>
              <Popup x:Name="PART_Popup" Placement="Bottom" AllowsTransparency="True"
                     IsOpen="{TemplateBinding IsDropDownOpen}" PopupAnimation="Fade">
                <Border Background="#1F1F1F" BorderBrush="#4A4A4A" BorderThickness="1" CornerRadius="6" Margin="0,4,0,0" Padding="2">
                  <ScrollViewer CanContentScroll="True"><StackPanel IsItemsHost="True"/></ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#E8E8E8"/><Setter Property="Padding" Value="8,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="Chrome" Background="Transparent" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Chrome" Property="Background" Value="#3C3C3C"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border Background="{StaticResource Surface}" BorderBrush="{StaticResource Edge}" BorderThickness="1" CornerRadius="8">
    <StackPanel>

      <Grid x:Name="HeaderBar" Margin="14,12,10,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="26"/><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0" Style="{StaticResource Glyph}" Text="&#xE7F4;" FontSize="17" HorizontalAlignment="Left"/>
        <ComboBox x:Name="MonitorSelector" Grid.Column="1" Margin="2,0,0,0"/>
        <Button x:Name="RefreshButton" Grid.Column="2" Style="{StaticResource IconButton}" ToolTip="Re-detect displays">
          <TextBlock Style="{StaticResource Glyph}" Text="&#xE72C;" FontSize="14"/>
        </Button>
      </Grid>

      <!-- WheelZone is transparent but hit-testable, so the wheel works well outside
           the 20px slider: the whole padded strip scrolls brightness. -->
      <Border x:Name="WheelZone" Background="#01000000" Margin="8,4,10,0" Padding="6,10,6,10">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="44"/></Grid.ColumnDefinitions>
          <Slider x:Name="BrightnessSlider" Grid.Column="0" Minimum="0" Maximum="100" Value="50"
                  IsSnapToTickEnabled="True" TickFrequency="1" VerticalAlignment="Center"/>
          <TextBlock x:Name="BrightnessValue" Grid.Column="1" Text="--" FontSize="17"
                     HorizontalAlignment="Right" VerticalAlignment="Center"/>
        </Grid>
      </Border>

      <Border Margin="14,8,14,0" Background="{StaticResource Raised}" BorderBrush="#404040" BorderThickness="1" CornerRadius="7" Padding="3">
        <UniformGrid Columns="2">
          <Button x:Name="StandardButton" Style="{StaticResource Segment}" Content="Standard"/>
          <Button x:Name="ComfortButton" Style="{StaticResource Segment}" Content="ComfortView"/>
        </UniformGrid>
      </Border>

      <Border Height="1" Background="{StaticResource Edge}" Margin="0,12,0,0"/>

      <Grid Margin="14,8,10,10">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <TextBlock x:Name="FooterText" Grid.Column="0" Foreground="{StaticResource Muted}" FontSize="12"
                   VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Text="Switch modes with Ctrl+Alt+F9"/>
        <Button x:Name="SettingsButton" Grid.Column="1" Style="{StaticResource IconButton}" ToolTip="Settings">
          <TextBlock Style="{StaticResource Glyph}" Text="&#xE713;"/>
        </Button>
        <Button x:Name="CloseButton" Grid.Column="2" Style="{StaticResource IconButton}" ToolTip="Hide panel">
          <TextBlock Style="{StaticResource Glyph}" Text="&#xE711;" FontSize="14"/>
        </Button>
      </Grid>

      <Border x:Name="SettingsPanel" Visibility="Collapsed" Background="#262626" BorderBrush="{StaticResource Edge}"
              BorderThickness="0,1,0,0" CornerRadius="0,0,7,7" Padding="14,12,14,12">
        <StackPanel>
          <TextBlock Text="Mode shortcut" Foreground="#DEDEDE" Margin="0,0,0,6"/>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <Border Grid.Column="0" Background="#1F1F1F" BorderBrush="#4A4A4A" BorderThickness="1" CornerRadius="4">
              <Button x:Name="HotkeyButton" Style="{StaticResource Segment}" Background="Transparent"
                      Padding="8,6" HorizontalContentAlignment="Left" FontSize="12" Content="Ctrl+Alt+F9"/>
            </Border>
            <CheckBox x:Name="HotkeyEnabled" Grid.Column="1" Content="Enabled" VerticalAlignment="Center" Margin="10,0,0,0"/>
          </Grid>
          <TextBlock x:Name="HotkeyHint" Text="Click the box, then press the combination you want." Foreground="{StaticResource Muted}" FontSize="11" Margin="0,5,0,0" TextWrapping="Wrap"/>

          <TextBlock Text="Register values" Foreground="#DEDEDE" Margin="0,14,0,6"/>
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="72"/><ColumnDefinition/><ColumnDefinition Width="8"/><ColumnDefinition/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/><RowDefinition Height="4"/><RowDefinition Height="Auto"/>
              <RowDefinition Height="4"/><RowDefinition Height="Auto"/><RowDefinition Height="4"/><RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Grid.Column="1" Text="Standard" Foreground="{StaticResource Muted}" FontSize="11"/>
            <TextBlock Grid.Row="0" Grid.Column="3" Text="ComfortView" Foreground="{StaticResource Muted}" FontSize="11"/>

            <TextBlock Grid.Row="2" Grid.Column="0" Text="0xF0" VerticalAlignment="Center" FontSize="12"/>
            <TextBox x:Name="StandardCode" Grid.Row="2" Grid.Column="1" Text="0"/>
            <TextBox x:Name="ComfortCode" Grid.Row="2" Grid.Column="3" Text="12"/>

            <TextBlock Grid.Row="4" Grid.Column="0" Text="0xE3 / 0xE2" VerticalAlignment="Center" FontSize="12"/>
            <TextBox x:Name="StandardAuxCode" Grid.Row="4" Grid.Column="1" Text="0"/>
            <TextBox x:Name="ComfortAuxCode" Grid.Row="4" Grid.Column="3" Text="29"/>

            <TextBlock Grid.Row="6" Grid.Column="0" Text="0x14" VerticalAlignment="Center" FontSize="12"/>
            <TextBox x:Name="StandardColorCode" Grid.Row="6" Grid.Column="1" Text="5"/>
            <TextBlock Grid.Row="6" Grid.Column="3" Text="Standard only" Foreground="{StaticResource Muted}" FontSize="11" VerticalAlignment="Center"/>
          </Grid>

          <CheckBox x:Name="StartWithWindows" Content="Start with Windows" Margin="0,14,0,0"/>

          <Grid Margin="0,12,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <Button x:Name="DesktopShortcutButton" Grid.Column="0" Style="{StaticResource Segment}" Background="#3A3A3A"
                    Content="Create desktop shortcut" HorizontalAlignment="Left" FontSize="12"/>
            <Button x:Name="ExitButton" Grid.Column="1" Style="{StaticResource Segment}" Background="#3A3A3A"
                    Content="Quit" FontSize="12" Padding="16,7"/>
          </Grid>
        </StackPanel>
      </Border>

      <TextBlock x:Name="StatusText" Foreground="{StaticResource Muted}" FontSize="11" TextWrapping="Wrap"
                 Margin="14,0,14,10" Visibility="Collapsed"/>
    </StackPanel>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$controls = @{}
$namespaceManager = New-Object System.Xml.XmlNamespaceManager($xaml.NameTable)
$namespaceManager.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
$xaml.SelectNodes('//*[@x:Name]', $namespaceManager) | ForEach-Object {
    $name = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $controls[$name] = $window.FindName($name)
}

# ------------------------------------------------------------------- state (from Version B)

$syncing = $false
$currentMonitor = $null
$brightnessMaximum = 100
$brightnessValue = 0
$pendingBrightness = $null
$script:currentMode = $null
$script:capturing = $false

$brightnessTimer = New-Object System.Windows.Threading.DispatcherTimer
$brightnessTimer.Interval = [TimeSpan]::FromMilliseconds(120)
$brightnessTimer.Add_Tick({
    if ($null -eq $script:pendingBrightness -or $null -eq $script:currentMonitor) { $brightnessTimer.Stop(); return }
    $value = $script:pendingBrightness
    $script:pendingBrightness = $null
    $target = [uint32][Math]::Round(($value / 100.0) * $script:brightnessMaximum)
    if ([MonitorDdc]::TrySet($script:currentMonitor, 0x10, $target)) { Set-Status '' }
    else { Set-Status 'Windows could not write the brightness value to this display.' '#EF8D8D' }
    if ($null -eq $script:pendingBrightness) { $brightnessTimer.Stop() }
})

# Low-level mouse hook — installed only while the panel is visible.
# Fires Hide-Panel when any mouse button is pressed outside our window,
# regardless of which application owns the foreground. This is the only
# reliable way to detect "user clicked back into Telegram fullscreen"
# because SetForegroundWindow is silently ignored when a fullscreen app
# holds the foreground lock, so WPF's Deactivated never fires in that case.
$script:mouseHook = [IntPtr]::Zero
$script:mouseHookHandle = [IntPtr]::Zero   # our window handle, cached at hook time

$script:mouseHookProc = [Native+LowLevelMouseProc]{
    param([int]$nCode, [IntPtr]$wParam, [IntPtr]$lParam)
    # WM_LBUTTONDOWN=0x0201, WM_RBUTTONDOWN=0x0204, WM_MBUTTONDOWN=0x0207,
    # WM_XBUTTONDOWN=0x020B, WM_NCLBUTTONDOWN=0x00A1 (title-bar clicks)
    $buttonDown = ($wParam -eq 0x0201 -or $wParam -eq 0x0204 -or
                   $wParam -eq 0x0207 -or $wParam -eq 0x020B -or $wParam -eq 0x00A1)
    if ($nCode -ge 0 -and $buttonDown) {
        $info = [System.Runtime.InteropServices.Marshal]::PtrToStructure(
            $lParam, [type][Native+MSLLHOOKSTRUCT])
        # Walk to the root window under the cursor and compare with ours.
        $clicked = [Native]::WindowFromPoint($info.pt)
        $root    = [Native]::GetAncestor($clicked, [Native]::GA_ROOT)
        if ($root -ne $script:mouseHookHandle -and $clicked -ne $script:mouseHookHandle) {
            # Click landed outside our panel — hide it.
            # Dispatch back onto the UI thread; the hook runs on a thread-pool thread.
            $window.Dispatcher.InvokeAsync([Action]{ Hide-Panel }) | Out-Null
        }
    }
    return [Native]::CallNextHookEx($script:mouseHook, $nCode, $wParam, $lParam)
}

function Install-MouseHook {
    if ($script:mouseHook -ne [IntPtr]::Zero) { return }
    $script:mouseHookHandle = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
    $hMod = [Native]::GetModuleHandle($null)
    $script:mouseHook = [Native]::SetWindowsHookEx(14, $script:mouseHookProc, $hMod, 0)  # WH_MOUSE_LL=14
}

function Remove-MouseHook {
    if ($script:mouseHook -eq [IntPtr]::Zero) { return }
    [void][Native]::UnhookWindowsHookEx($script:mouseHook)
    $script:mouseHook = [IntPtr]::Zero
}

function Set-Status([string]$message, [string]$color = '#9C9C9C') {
    if ([string]::IsNullOrWhiteSpace($message)) { $controls.StatusText.Visibility = 'Collapsed'; return }
    $controls.StatusText.Text = $message
    $controls.StatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($color)
    $controls.StatusText.Visibility = 'Visible'
}

function Get-SelectedMonitor { return $controls.MonitorSelector.SelectedItem }

function Convert-VcpValue([string]$text) {
    $trimmed = $text.Trim()
    if ($trimmed -match '^0x[0-9a-fA-F]+$') { return [Convert]::ToUInt32($trimmed.Substring(2), 16) }
    return [uint32]::Parse($trimmed)
}

function Update-Readings {
    $script:currentMonitor = Get-SelectedMonitor
    if ($null -eq $script:currentMonitor) { return }
    $script:syncing = $true
    try {
        [uint32]$now = 0; [uint32]$maximum = 0
        # The monitor may need a moment after waking before it responds to DDC/CI.
        # Retry silently up to 3 times with short pauses before giving up.
        $ok = $false
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            if ([MonitorDdc]::TryGet($script:currentMonitor, 0x10, [ref]$now, [ref]$maximum)) {
                $ok = $true; break
            }
            if ($attempt -lt 2) {
                # Re-enumerate handles on second attempt — the monitor may have
                # re-registered itself with the OS after waking.
                if ($attempt -eq 1) { [MonitorDdc]::GetMonitors() | Out-Null }
                Start-Sleep -Milliseconds 600
            }
        }
        if ($ok) {
            $maximum = [Math]::Max(1, $maximum)
            $percent = [Math]::Round(($now * 100.0) / $maximum)
            $script:brightnessMaximum = $maximum
            $script:brightnessValue = $percent
            $controls.BrightnessSlider.Value = $percent
            $controls.BrightnessValue.Text = "$percent"
            Set-Status ''
        } else {
            $controls.BrightnessValue.Text = '--'
            Set-Status 'This display did not respond to the DDC/CI brightness query. Enable DDC/CI in its on-screen menu, then refresh.' '#F5C26B'
        }
    } finally { $script:syncing = $false }
}

function Find-Monitors {
    $script:syncing = $true
    try {
        $script:currentMonitor = $null
        $controls.MonitorSelector.ItemsSource = $null
        $items = [MonitorDdc]::GetMonitors()
        $controls.MonitorSelector.ItemsSource = $items
        if ($items.Count -eq 0) {
            $controls.BrightnessValue.Text = '--'
            Set-Status 'Connect the AW2521HFL directly (some docks/KVMs block DDC/CI).' '#F5C26B'
            return
        }
        $preferred = $items | Where-Object { $_.Description -match 'AW2521HFL' } | Select-Object -First 1
        $controls.MonitorSelector.SelectedItem = if ($preferred) { $preferred } else { $items[0] }
        Update-Readings
    } catch {
        Set-Status "Unable to enumerate DDC/CI displays: $($_.Exception.Message)" '#EF8D8D'
    } finally { $script:syncing = $false }
}

$controls.RefreshButton.Add_Click({ Find-Monitors })
$controls.MonitorSelector.Add_SelectionChanged({ if (-not $script:syncing) { Update-Readings } })
$controls.BrightnessSlider.Add_ValueChanged({
    $value = [Math]::Round($controls.BrightnessSlider.Value)
    $controls.BrightnessValue.Text = "$value"
    $script:brightnessValue = $value
    if ($script:syncing -or $null -eq $script:currentMonitor) { return }
    $script:pendingBrightness = $value
    $brightnessTimer.Stop(); $brightnessTimer.Start()
})

# Wheel handler from Version B, hosted on the padded transparent strip so the hit
# area is far bigger than the slider itself. PreviewMouseWheel tunnels from the
# Border downward, so one handler covers the slider and the surrounding padding.
$wheelHandler = {
    param($sender, $eventArgs)
    if ($null -eq $script:currentMonitor) { return }
    $step = if ($eventArgs.Delta -gt 0) { 3 } else { -3 }
    $controls.BrightnessSlider.Value = [Math]::Max(0, [Math]::Min(100, $controls.BrightnessSlider.Value + $step))
    $eventArgs.Handled = $true
}
$controls.WheelZone.Add_PreviewMouseWheel($wheelHandler)
$controls.BrightnessSlider.Add_PreviewMouseWheel($wheelHandler)

function Set-ModeHighlight([string]$name) {
    $script:currentMode = $name
    $on = [Windows.Media.BrushConverter]::new().ConvertFromString('#EE6C4D')
    $off = [Windows.Media.BrushConverter]::new().ConvertFromString('Transparent')
    if ($name -eq 'Standard Mode') {
        $controls.StandardButton.Background = $on
        $controls.ComfortButton.Background = $off
    } elseif ($name -eq 'ComfortView Mode') {
        $controls.ComfortButton.Background = $on
        $controls.StandardButton.Background = $off
    } else {
        $controls.StandardButton.Background = $off
        $controls.ComfortButton.Background = $off
    }
}

function Set-Preset([System.Windows.Controls.TextBox]$codeBox, [System.Windows.Controls.TextBox]$auxCodeBox, [System.Windows.Controls.TextBox]$colorCodeBox, [string]$name) {
    $monitor = Get-SelectedMonitor
    [uint32]$value = 0
    if ($null -eq $monitor) { Set-Status 'Select a monitor first.' '#F5C26B'; return $false }
    try { $value = Convert-VcpValue $codeBox.Text } catch { Set-Status 'Preset values must be whole numbers between 0 and 255.' '#EF8D8D'; return $false }
    if ($value -gt 255) { Set-Status 'Preset values must be whole numbers between 0 and 255.' '#EF8D8D'; return $false }
    [uint32]$auxValue = 0
    try { $auxValue = Convert-VcpValue $auxCodeBox.Text } catch { Set-Status 'E3/E2 values must be whole numbers between 0 and 255.' '#EF8D8D'; return $false }
    if ($auxValue -gt 255) { Set-Status 'E3/E2 values must be whole numbers between 0 and 255.' '#EF8D8D'; return $false }
    $colorSucceeded = $true
    [uint32]$colorValue = 0
    if ($null -ne $colorCodeBox) {
        try { $colorValue = Convert-VcpValue $colorCodeBox.Text } catch { Set-Status 'The 0x14 color preset value must be a whole number between 0 and 255.' '#EF8D8D'; return $false }
        if ($colorValue -gt 255) { Set-Status 'The 0x14 color preset value must be a whole number between 0 and 255.' '#EF8D8D'; return $false }
        $colorSucceeded = [MonitorDdc]::TrySet($monitor, 0x14, $colorValue)
    }
    $f0Succeeded = [MonitorDdc]::TrySet($monitor, 0xF0, $value)
    $e3Succeeded = [MonitorDdc]::TrySet($monitor, 0xE3, $auxValue)
    $e2Succeeded = [MonitorDdc]::TrySet($monitor, 0xE2, $auxValue)
    if ($colorSucceeded -and $f0Succeeded -and $e3Succeeded -and $e2Succeeded) {
        Set-ModeHighlight $name
        Set-Status ''
        $script:Settings.LastMode = $name
        Save-Registers
        return $true
    }
    else {
        Set-Status "$name could not be applied to all requested registers (0x14=$colorSucceeded, F0=$f0Succeeded, E3=$e3Succeeded, E2=$e2Succeeded). Confirm DDC/CI is enabled." '#EF8D8D'
        return $false
    }
}

$controls.StandardButton.Add_Click({ [void](Set-Preset $controls.StandardCode $controls.StandardAuxCode $controls.StandardColorCode 'Standard Mode') })
$controls.ComfortButton.Add_Click({ [void](Set-Preset $controls.ComfortCode $controls.ComfortAuxCode $null 'ComfortView Mode') })

function Show-Toast([string]$label) {
    if ($window.IsVisible) { return }
    try {
        $script:Tray.BalloonTipTitle = 'AW2521HFL'
        $script:Tray.BalloonTipText = "$label mode"
        $script:Tray.ShowBalloonTip(900)
    } catch { }
}

function Invoke-ModeToggle {
    if ($null -eq (Get-SelectedMonitor)) { Find-Monitors }
    if ($script:currentMode -eq 'ComfortView Mode') {
        $applied = Set-Preset $controls.StandardCode $controls.StandardAuxCode $controls.StandardColorCode 'Standard Mode'
        $label = 'Standard'
    } else {
        $applied = Set-Preset $controls.ComfortCode $controls.ComfortAuxCode $null 'ComfortView Mode'
        $label = 'ComfortView'
    }
    if ($applied) { Show-Toast $label }
}

function Save-Registers {
    $script:Settings.StandardCode = $controls.StandardCode.Text
    $script:Settings.StandardAuxCode = $controls.StandardAuxCode.Text
    $script:Settings.StandardColorCode = $controls.StandardColorCode.Text
    $script:Settings.ComfortCode = $controls.ComfortCode.Text
    $script:Settings.ComfortAuxCode = $controls.ComfortAuxCode.Text
    Export-Settings
}

foreach ($box in @('StandardCode','StandardAuxCode','StandardColorCode','ComfortCode','ComfortAuxCode')) {
    $controls[$box].Add_LostFocus({ Save-Registers })
}

# ------------------------------------------------------------------- show / hide

function Show-Panel {
    if (-not $window.IsVisible) {
        $window.Show()
        $window.UpdateLayout()
        $area = [System.Windows.SystemParameters]::WorkArea
        $window.Left = [Math]::Max($area.Left + 8, $area.Right - $window.ActualWidth - 12)
        $window.Top = [Math]::Max($area.Top + 8, $area.Bottom - $window.ActualHeight - 12)
    }
    $window.Activate()
    [void][Native]::SetForegroundWindow((New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle)
    # Physical monitor handles stay alive for the life of the process, exactly as in
    # the working version. Only enumerate again if we somehow have nothing selected.
    if ($null -eq (Get-SelectedMonitor)) { Find-Monitors } else { Update-Readings }
    Install-MouseHook
}

function Hide-Panel {
    if ($script:capturing) { return }
    if ($controls.MonitorSelector.IsDropDownOpen) { return }
    Remove-MouseHook
    $window.Hide()
    $controls.SettingsPanel.Visibility = 'Collapsed'
    Set-Status ''
    [System.GC]::Collect()
    [Native]::TrimWorkingSet()
}

$window.Add_Deactivated({ Hide-Panel })
$window.Add_Closing({ param($sender, $e) $e.Cancel = $true; Hide-Panel })
$window.Add_PreviewKeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Escape -and -not $script:capturing) { $e.Handled = $true; Hide-Panel }
})
$controls.HeaderBar.Add_MouseLeftButtonDown({ try { $window.DragMove() } catch { } })
$controls.CloseButton.Add_Click({ Hide-Panel })
$controls.SettingsButton.Add_Click({
    $controls.SettingsPanel.Visibility = if ($controls.SettingsPanel.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }
    $window.UpdateLayout()
    $area = [System.Windows.SystemParameters]::WorkArea
    $window.Top = [Math]::Max($area.Top + 8, $area.Bottom - $window.ActualHeight - 12)
})

# ------------------------------------------------------------------- shortcuts

function Get-LauncherTarget([bool]$openPanel) {
    $vbs = Join-Path $script:Root 'AW2521HFL-Control.vbs'
    if (Test-Path -LiteralPath $vbs) {
        $arguments = "`"$vbs`""
        if ($openPanel) { $arguments += ' show' }
        return @{ Path = (Join-Path $env:SystemRoot 'System32\wscript.exe'); Arguments = $arguments }
    }
    $ps1 = Join-Path $script:Root 'AW2521HFL-Control.ps1'
    $arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$ps1`""
    if ($openPanel) { $arguments += ' -ShowOnStart' }
    return @{
        Path      = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        Arguments = $arguments
    }
}

function New-AppShortcut([string]$path, [bool]$openPanel) {
    $target = Get-LauncherTarget $openPanel
    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($path)
        $link.TargetPath = $target.Path
        $link.Arguments = $target.Arguments
        $link.WorkingDirectory = $script:Root
        $link.WindowStyle = 7
        $link.IconLocation = "$env:SystemRoot\System32\SHELL32.dll,15"
        $link.Description = 'AW2521HFL display control'
        $link.Save()
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
}

function Get-StartupShortcutPath { Join-Path ([Environment]::GetFolderPath('Startup')) 'AW2521HFL Control.lnk' }

function Set-StartWithWindows([bool]$enabled) {
    $path = Get-StartupShortcutPath
    try {
        if ($enabled) { New-AppShortcut $path $false; Set-Status 'Added to startup. It will sit in the tray, no panel.' '#8FD19E' }
        elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force; Set-Status 'Removed from startup.' }
    } catch { Set-Status "Could not update the startup shortcut: $($_.Exception.Message)" '#EF8D8D' }
}

$controls.StartWithWindows.Add_Click({ Set-StartWithWindows ([bool]$controls.StartWithWindows.IsChecked) })
$controls.DesktopShortcutButton.Add_Click({
    try {
        New-AppShortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'AW2521HFL Control.lnk') $true
        Set-Status 'Shortcut created on the desktop.' '#8FD19E'
    } catch { Set-Status "Could not create the shortcut: $($_.Exception.Message)" '#EF8D8D' }
})

# ------------------------------------------------------------------- hotkey

$script:HotkeyId = 0xA511
$script:HotkeyRegistered = $false

function Format-Hotkey([uint32]$modifiers, [uint32]$vk) {
    if ($vk -eq 0) { return 'None' }
    $parts = @()
    if ($modifiers -band 2) { $parts += 'Ctrl' }
    if ($modifiers -band 1) { $parts += 'Alt' }
    if ($modifiers -band 4) { $parts += 'Shift' }
    if ($modifiers -band 8) { $parts += 'Win' }
    $parts += ([System.Windows.Input.KeyInterop]::KeyFromVirtualKey([int]$vk)).ToString()
    return ($parts -join '+')
}

function Register-Hotkey {
    Unregister-Hotkey
    if (-not $script:Settings.HotkeyEnabled) {
        $controls.HotkeyHint.Text = 'Shortcut is off.'
        $controls.FooterText.Text = 'Mode shortcut off'
        return
    }
    $vk = [uint32]$script:Settings.HotkeyVirtualKey
    if ($vk -eq 0) { return }
    $modifiers = ([uint32]$script:Settings.HotkeyModifiers) -bor 0x4000   # MOD_NOREPEAT
    $handle = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
    if ([Native]::RegisterHotKey($handle, $script:HotkeyId, $modifiers, $vk)) {
        $script:HotkeyRegistered = $true
        $controls.HotkeyHint.Text = 'Shortcut is active, even when the panel is hidden.'
        $controls.FooterText.Text = "Switch modes with $($script:Settings.HotkeyText)"
        if ($script:Tray) { $script:Tray.Text = "AW2521HFL Control - $($script:Settings.HotkeyText)" }
    } else {
        $controls.HotkeyHint.Text = 'Another program already owns that combination. Pick a different one.'
        $controls.FooterText.Text = 'Shortcut unavailable'
    }
}

function Unregister-Hotkey {
    if (-not $script:HotkeyRegistered) { return }
    $handle = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
    [void][Native]::UnregisterHotKey($handle, $script:HotkeyId)
    $script:HotkeyRegistered = $false
}

$controls.HotkeyEnabled.Add_Click({
    $script:Settings.HotkeyEnabled = [bool]$controls.HotkeyEnabled.IsChecked
    Export-Settings
    Register-Hotkey
})

$controls.HotkeyButton.Add_Click({
    $script:capturing = $true
    $controls.HotkeyButton.Content = 'Press a combination...'
    $controls.HotkeyHint.Text = 'Hold Ctrl, Alt, Shift or Win and press a key. Esc cancels.'
    [void]$controls.HotkeyButton.Focus()
})

$controls.HotkeyButton.Add_PreviewKeyDown({
    param($sender, $e)
    if (-not $script:capturing) { return }
    $e.Handled = $true
    $key = $e.Key
    if ($key -eq [System.Windows.Input.Key]::System) { $key = $e.SystemKey }
    $ignored = @('LeftCtrl','RightCtrl','LeftAlt','RightAlt','LeftShift','RightShift','LWin','RWin','None')
    if ($ignored -contains $key.ToString()) { return }

    $script:capturing = $false
    if ($key -eq [System.Windows.Input.Key]::Escape) {
        $controls.HotkeyButton.Content = $script:Settings.HotkeyText
        $controls.HotkeyHint.Text = 'Unchanged.'
        return
    }

    $wpfModifiers = [System.Windows.Input.Keyboard]::Modifiers
    [uint32]$modifiers = 0
    if ($wpfModifiers -band [System.Windows.Input.ModifierKeys]::Alt) { $modifiers = $modifiers -bor 1 }
    if ($wpfModifiers -band [System.Windows.Input.ModifierKeys]::Control) { $modifiers = $modifiers -bor 2 }
    if ($wpfModifiers -band [System.Windows.Input.ModifierKeys]::Shift) { $modifiers = $modifiers -bor 4 }
    if ($wpfModifiers -band [System.Windows.Input.ModifierKeys]::Windows) { $modifiers = $modifiers -bor 8 }

    $isFunctionKey = $key -ge [System.Windows.Input.Key]::F1 -and $key -le [System.Windows.Input.Key]::F24
    if ($modifiers -eq 0 -and -not $isFunctionKey) {
        $controls.HotkeyButton.Content = $script:Settings.HotkeyText
        $controls.HotkeyHint.Text = 'Add at least one of Ctrl, Alt, Shift or Win, or use a function key.'
        return
    }

    $vk = [uint32][System.Windows.Input.KeyInterop]::VirtualKeyFromKey($key)
    $script:Settings.HotkeyModifiers = $modifiers
    $script:Settings.HotkeyVirtualKey = $vk
    $script:Settings.HotkeyText = Format-Hotkey $modifiers $vk
    $controls.HotkeyButton.Content = $script:Settings.HotkeyText
    Export-Settings
    Register-Hotkey
})

# ------------------------------------------------------------------- tray

function New-TrayIcon {
    $bitmap = New-Object System.Drawing.Bitmap 32, 32
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = 'AntiAlias'
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 235, 235, 235)), 2.4
        $graphics.DrawRectangle($pen, 4, 6, 24, 16)
        $fill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 238, 108, 77))
        $graphics.FillRectangle($fill, 7, 9, 18, 10)
        $stand = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 235, 235, 235))
        $graphics.FillRectangle($stand, 12, 23, 8, 3)
        $pen.Dispose(); $fill.Dispose(); $stand.Dispose()
    } finally { $graphics.Dispose() }
    $script:IconHandle = $bitmap.GetHicon()
    $bitmap.Dispose()
    return [System.Drawing.Icon]::FromHandle($script:IconHandle)
}

$script:Tray = New-Object System.Windows.Forms.NotifyIcon
$script:Tray.Icon = New-TrayIcon
$script:Tray.Text = 'AW2521HFL Control'
$script:Tray.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.BackColor = [System.Drawing.Color]::FromArgb(43, 43, 43)
$menu.ForeColor = [System.Drawing.Color]::White
$menu.ShowImageMargin = $false

function Add-MenuItem([string]$text, [scriptblock]$action) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem $text
    $item.BackColor = [System.Drawing.Color]::FromArgb(43, 43, 43)
    $item.ForeColor = [System.Drawing.Color]::White
    $item.Add_Click($action)
    [void]$menu.Items.Add($item)
    return $item
}

[void](Add-MenuItem 'Open panel' { Show-Panel })
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void](Add-MenuItem 'Standard' { if ($null -eq (Get-SelectedMonitor)) { Find-Monitors }; [void](Set-Preset $controls.StandardCode $controls.StandardAuxCode $controls.StandardColorCode 'Standard Mode') })
[void](Add-MenuItem 'ComfortView' { if ($null -eq (Get-SelectedMonitor)) { Find-Monitors }; [void](Set-Preset $controls.ComfortCode $controls.ComfortAuxCode $null 'ComfortView Mode') })
[void](Add-MenuItem 'Toggle mode' { Invoke-ModeToggle })
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void](Add-MenuItem 'Quit' { Stop-App })
$script:Tray.ContextMenuStrip = $menu

$script:Tray.Add_MouseClick({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($window.IsVisible) { Hide-Panel } else { Show-Panel }
    }
})

$controls.ExitButton.Add_Click({ Stop-App })

function Stop-App {
    try { Unregister-Hotkey } catch { }
    try { $brightnessTimer.Stop() } catch { }
    try { Remove-MouseHook } catch { }
    try { $script:Tray.Visible = $false; $script:Tray.Dispose() } catch { }
    try { if ($script:IconHandle) { [void][Native]::DestroyIcon($script:IconHandle) } } catch { }
    try { [MonitorDdc]::ReleaseAll() } catch { }
    try { [System.Windows.Application]::Current.Shutdown() } catch { }
}

# ------------------------------------------------------------------- start

$app = New-Object System.Windows.Application
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown

$helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
$handle = $helper.EnsureHandle()
$source = [System.Windows.Interop.HwndSource]::FromHwnd($handle)
$source.AddHook({
    param($hwnd, $msg, $wParam, $lParam, $handled)
    if ($msg -eq 0x0312 -and [int]$wParam -eq $script:HotkeyId) { Invoke-ModeToggle }
    elseif ($msg -eq $script:ShowMessage) { Show-Panel }
    return [IntPtr]::Zero
})

$controls.StandardCode.Text = "$($script:Settings.StandardCode)"
$controls.StandardAuxCode.Text = "$($script:Settings.StandardAuxCode)"
$controls.StandardColorCode.Text = "$($script:Settings.StandardColorCode)"
$controls.ComfortCode.Text = "$($script:Settings.ComfortCode)"
$controls.ComfortAuxCode.Text = "$($script:Settings.ComfortAuxCode)"
$controls.HotkeyButton.Content = $script:Settings.HotkeyText
$controls.HotkeyEnabled.IsChecked = [bool]$script:Settings.HotkeyEnabled
$controls.StartWithWindows.IsChecked = (Test-Path -LiteralPath (Get-StartupShortcutPath))
Set-ModeHighlight "$($script:Settings.LastMode)"

Register-Hotkey
Find-Monitors

if ($ShowOnStart) { Show-Panel } else { [Native]::TrimWorkingSet() }

try {
    $app.Run()
} catch {
    try {
        if (-not (Test-Path -LiteralPath $script:AppDir)) { New-Item -ItemType Directory -Path $script:AppDir -Force | Out-Null }
        "$(Get-Date -Format s) $($_.Exception.ToString())" | Set-Content -LiteralPath $script:LogPath -Encoding UTF8
    } catch { }
    [System.Windows.Forms.MessageBox]::Show("AW2521HFL Control stopped: $($_.Exception.Message)", 'AW2521HFL Control') | Out-Null
} finally {
    try { $brightnessTimer.Stop() } catch { }
    try { Remove-MouseHook } catch { }
    try { $script:Tray.Visible = $false; $script:Tray.Dispose() } catch { }
    try { if ($script:IconHandle) { [void][Native]::DestroyIcon($script:IconHandle) } } catch { }
    try { [MonitorDdc]::ReleaseAll() } catch { }
    try { $script:instanceMutex.ReleaseMutex(); $script:instanceMutex.Dispose() } catch { }
}
