<#
.SYNOPSIS
    Hyper-V Workstation - Unified Management Launcher and Viewer for GPU-PV Gaming VMs.
.DESCRIPTION
    Provides a VMware Workstation-like desktop interface for managing Hyper-V Gaming VMs:
    - Real-time status monitoring (Running/Stopped, vCPU, RAM, GPU VRAM)
    - 1-Click Launch into windowed, low-latency Moonlight streaming (default 720p @ 60Hz)
    - Pairing wizard for Sunshine / Moonlight
    - 1-Click VM cloning for multi-VM scaling
#>

# Auto-elevate if not Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

try {
    $showWinDef = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();'
    $null = Add-Type -MemberDefinition $showWinDef -Name Win32ConsoleHelper -Namespace GuiConsoleApp -PassThru -ErrorAction SilentlyContinue
} catch {}

try {

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Hyper-V Workstation (GPU-PV Gaming Console)" 
        Height="720" Width="1020" 
        WindowStartupLocation="CenterScreen"
        Background="#18181b" Foreground="#f4f4f5" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#27272a"/>
            <Setter Property="Foreground" Value="#fafafa"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#3f3f46"/>
            <Setter Property="Padding" Value="12,7"/>
            <Setter Property="Margin" Value="4"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#3f3f46"/>
                    <Setter Property="BorderBrush" Value="#71717a"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#2563eb"/>
            <Setter Property="BorderBrush" Value="#3b82f6"/>
            <Setter Property="FontSize" Value="13"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#1d4ed8"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="SuccessButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#16a34a"/>
            <Setter Property="BorderBrush" Value="#22c55e"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#15803d"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#dc2626"/>
            <Setter Property="BorderBrush" Value="#ef4444"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#b91c1c"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="ComboBox">
            <Setter Property="Foreground" Value="#09090b"/>
            <Setter Property="Background" Value="#ffffff"/>
            <Setter Property="BorderBrush" Value="#71717a"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>

        <Style TargetType="ComboBoxItem">
            <Setter Property="Foreground" Value="#09090b"/>
            <Setter Property="Background" Value="#ffffff"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="6,4"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="280"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Left Sidebar: VM Inventory -->
        <Border Grid.Column="0" Background="#111113" BorderBrush="#27272a" BorderThickness="0,0,1,0">
            <Grid Margin="12">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <StackPanel Grid.Row="0" Margin="0,0,0,12">
                    <TextBlock Text="Виртуальные машины" FontSize="16" FontWeight="Bold" Foreground="#e4e4e7"/>
                    <TextBlock Text="GPU-PV Gaming Cluster" FontSize="12" Foreground="#71717a"/>
                </StackPanel>

                <!-- VM ListBox -->
                <ListBox Grid.Row="1" Name="ListVMs" Background="Transparent" BorderThickness="0"
                         Foreground="#e4e4e7" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                    <ListBox.ItemTemplate>
                        <DataTemplate>
                            <Border Background="#1f1f23" CornerRadius="8" Padding="10,8" Margin="0,0,0,6" BorderBrush="#2e2e33" BorderThickness="1">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <Ellipse Grid.Column="0" Width="10" Height="10" Margin="0,0,10,0" Fill="{Binding StatusColor}"/>
                                    <StackPanel Grid.Column="1">
                                        <TextBlock Text="{Binding Name}" FontWeight="Bold" FontSize="13" Foreground="#f4f4f5"/>
                                        <TextBlock Text="{Binding StateText}" FontSize="11" Foreground="#a1a1aa"/>
                                    </StackPanel>
                                    <TextBlock Grid.Column="2" Text="{Binding VRAMText}" FontSize="11" Foreground="#38bdf8" VerticalAlignment="Center"/>
                                </Grid>
                            </Border>
                        </DataTemplate>
                    </ListBox.ItemTemplate>
                </ListBox>

                <!-- Sidebar Bottom Toolbar -->
                <StackPanel Grid.Row="2" Margin="0,10,0,0">
                    <Button Name="BtnCloneVM" Content="➕ Клонировать новую VM" Style="{StaticResource PrimaryButton}"/>
                    <Button Name="BtnRefresh" Content="🔄 Обновить список"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Right Content Area -->
        <Grid Grid.Column="1" Margin="24">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Top Header & Status -->
            <Border Grid.Row="0" Background="#1f1f23" CornerRadius="8" Padding="18" BorderBrush="#2e2e33" BorderThickness="1" Margin="0,0,0,16">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0">
                        <TextBlock Name="TxtVMTitle" Text="Выберите виртуальную машину" FontSize="22" FontWeight="Bold" Foreground="#f4f4f5"/>
                        <TextBlock Name="TxtVMSub" Text="Параметры и потоковое управление" FontSize="13" Foreground="#a1a1aa" Margin="0,4,0,0"/>
                    </StackPanel>
                    <Border Grid.Column="1" Name="BadgeStatus" CornerRadius="12" Padding="12,4" Background="#27272a" VerticalAlignment="Center">
                        <TextBlock Name="TxtStatusBadge" Text="НЕТ ВЫБОРА" FontWeight="Bold" FontSize="11" Foreground="#a1a1aa"/>
                    </Border>
                </Grid>
            </Border>

            <!-- Controls Toolbar -->
            <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,16">
                <Button Name="BtnStartVM" Content="▶ Запустить VM" Style="{StaticResource SuccessButton}" Width="130"/>
                <Button Name="BtnStopVM" Content="⏹ Остановить" Style="{StaticResource DangerButton}" Width="120"/>
                <Button Name="BtnOpenStream" Content="🖥️ Открыть окно (Moonlight)" Style="{StaticResource PrimaryButton}" Padding="16,7"/>
                <Button Name="BtnPairMoonlight" Content="🔑 Связать Moonlight"/>
                <Button Name="BtnRandomizeHWID" Content="🎲 Спуфинг HWID"/>
                <Button Name="BtnVMConnect" Content="⚙️ Hyper-V Manager"/>
            </StackPanel>

            <!-- Detail Cards -->
            <Grid Grid.Row="2">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <UniformGrid Grid.Row="0" Columns="4" Margin="0,0,0,12">
                    <!-- CPU Card -->
                    <Border Background="#1f1f23" CornerRadius="8" Padding="12" Margin="4" BorderBrush="#2e2e33" BorderThickness="1">
                        <StackPanel>
                            <TextBlock Text="ПРОЦЕССОР" FontSize="10" FontWeight="Bold" Foreground="#71717a"/>
                            <TextBlock Name="TxtCPU" Text="-" FontSize="18" FontWeight="Bold" Foreground="#f4f4f5" Margin="0,4,0,0"/>
                            <TextBlock Text="vCPU (VT-x/EPT)" FontSize="10" Foreground="#a1a1aa"/>
                        </StackPanel>
                    </Border>

                    <!-- RAM Card -->
                    <Border Background="#1f1f23" CornerRadius="8" Padding="12" Margin="4" BorderBrush="#2e2e33" BorderThickness="1">
                        <StackPanel>
                            <TextBlock Text="ОПЕРАТИВНАЯ ПАМЯТЬ" FontSize="10" FontWeight="Bold" Foreground="#71717a"/>
                            <TextBlock Name="TxtRAM" Text="-" FontSize="18" FontWeight="Bold" Foreground="#f4f4f5" Margin="0,4,0,0"/>
                            <TextBlock Text="Статическая ECC" FontSize="10" Foreground="#a1a1aa"/>
                        </StackPanel>
                    </Border>

                    <!-- GPU VRAM Card -->
                    <Border Background="#1f1f23" CornerRadius="8" Padding="12" Margin="4" BorderBrush="#2e2e33" BorderThickness="1">
                        <StackPanel>
                            <TextBlock Text="GPU-PV ВИДЕОПАМЯТЬ" FontSize="10" FontWeight="Bold" Foreground="#71717a"/>
                            <TextBlock Name="TxtVRAM" Text="-" FontSize="18" FontWeight="Bold" Foreground="#38bdf8" Margin="0,4,0,0"/>
                            <TextBlock Text="NVIDIA GTX 1050 Ti" FontSize="10" Foreground="#a1a1aa"/>
                        </StackPanel>
                    </Border>

                    <!-- Network IP Card -->
                    <Border Background="#1f1f23" CornerRadius="8" Padding="12" Margin="4" BorderBrush="#2e2e33" BorderThickness="1">
                        <StackPanel>
                            <TextBlock Text="IP АДРЕС СЕТИ NAT" FontSize="10" FontWeight="Bold" Foreground="#71717a"/>
                            <TextBlock Name="TxtIP" Text="-" FontSize="16" FontWeight="Bold" Foreground="#4ade80" Margin="0,4,0,0"/>
                            <TextBlock Text="VM-Gaming-Switch" FontSize="10" Foreground="#a1a1aa"/>
                        </StackPanel>
                    </Border>
                </UniformGrid>

                <!-- SOCKS5 External Proxy Card -->
                <Border Grid.Row="1" Background="#1f1f23" CornerRadius="8" Padding="14,10" Margin="0,0,0,12" BorderBrush="#2e2e33" BorderThickness="1">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <!-- Proxy Header & Live Status -->
                        <Grid Grid.Row="0" Margin="0,0,0,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="🌐 SOCKS5 Проксирование" FontWeight="Bold" FontSize="13" Foreground="#f4f4f5" Margin="0,0,8,0"/>
                                <TextBlock Text="(Внешняя изоляция • Чистый гость • DNS Leak-Free)" FontSize="11" Foreground="#71717a" VerticalAlignment="Center"/>
                            </StackPanel>

                            <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                                <Border Name="BadgeProxyStatus" CornerRadius="10" Padding="10,3" Background="#27272a" Margin="0,0,8,0">
                                    <TextBlock Name="TxtProxyStatus" Text="Прямой Интернет" FontSize="11" FontWeight="Bold" Foreground="#a1a1aa"/>
                                </Border>
                                <Border Name="BadgeKillSwitch" CornerRadius="10" Padding="8,3" Background="#27272a">
                                    <TextBlock Name="TxtKillSwitch" Text="🛡️ Kill-Switch: ВЫКЛ" FontSize="11" FontWeight="SemiBold" Foreground="#a1a1aa"/>
                                </Border>
                            </StackPanel>
                        </Grid>

                        <!-- Proxy Controls Row -->
                        <WrapPanel Grid.Row="1" VerticalAlignment="Center">
                            <StackPanel Orientation="Horizontal" Margin="0,0,14,0" VerticalAlignment="Center">
                                <TextBlock Text="Режим:" VerticalAlignment="Center" Foreground="#a1a1aa" Margin="0,0,8,0"/>
                                <ComboBox Name="CmbProxyMode" Width="160" SelectedIndex="0" Background="#ffffff" Foreground="#09090b">
                                    <ComboBoxItem Content="🔘 Прямое (IP Хоста)" Foreground="#09090b"/>
                                    <ComboBoxItem Content="🔒 SOCKS5 Прокси" Foreground="#09090b"/>
                                </ComboBox>
                            </StackPanel>

                            <StackPanel Orientation="Horizontal" Margin="0,0,14,0" VerticalAlignment="Center">
                                <TextBlock Text="Профиль:" VerticalAlignment="Center" Foreground="#a1a1aa" Margin="0,0,8,0"/>
                                <ComboBox Name="CmbProxyProfiles" Width="260" Background="#ffffff" Foreground="#09090b"/>
                            </StackPanel>

                            <Button Name="BtnApplyProxy" Content="⚡ Применить" Style="{StaticResource PrimaryButton}" Margin="0,0,6,0" Padding="12,5"/>
                            <Button Name="BtnTestProxy" Content="🔍 Проверить" Margin="0,0,6,0" Padding="12,5"/>
                            <Button Name="BtnAddProxy" Content="➕ Добавить" Margin="0,0,6,0" Padding="10,5"/>
                            <Button Name="BtnListProxy" Content="📋 Список" Margin="0" Padding="10,5"/>
                        </WrapPanel>
                    </Grid>
                </Border>

                <!-- Streaming Settings & Log Panel -->
                <Border Grid.Row="2" Background="#1f1f23" CornerRadius="8" Padding="16" BorderBrush="#2e2e33" BorderThickness="1">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <TextBlock Grid.Row="0" Text="Параметры потокового окна VMware-like (Moonlight):" FontWeight="Bold" FontSize="13" Foreground="#e4e4e7" Margin="0,0,0,10"/>
                        
                        <WrapPanel Grid.Row="1" Margin="0,0,0,12">
                            <StackPanel Orientation="Horizontal" Margin="0,0,20,0" VerticalAlignment="Center">
                                <TextBlock Text="Разрешение:" VerticalAlignment="Center" Foreground="#a1a1aa" Margin="0,0,8,0"/>
                                <ComboBox Name="CmbResolution" Width="170" SelectedIndex="0" Background="#ffffff" Foreground="#09090b">
                                    <ComboBoxItem Content="1024x768 (Стандартное)" Foreground="#09090b"/>
                                    <ComboBoxItem Content="1280x720 (720p)" Foreground="#09090b"/>
                                    <ComboBoxItem Content="1920x1080 (1080p)" Foreground="#09090b"/>
                                </ComboBox>
                            </StackPanel>

                            <StackPanel Orientation="Horizontal" Margin="0,0,20,0" VerticalAlignment="Center">
                                <TextBlock Text="Частота:" VerticalAlignment="Center" Foreground="#a1a1aa" Margin="0,0,8,0"/>
                                <ComboBox Name="CmbFps" Width="105" SelectedIndex="0" Background="#ffffff" Foreground="#09090b">
                                    <ComboBoxItem Content="60 FPS" Foreground="#09090b"/>
                                    <ComboBoxItem Content="120 FPS" Foreground="#09090b"/>
                                </ComboBox>
                            </StackPanel>

                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <TextBlock Text="Режим:" VerticalAlignment="Center" Foreground="#a1a1aa" Margin="0,0,8,0"/>
                                <ComboBox Name="CmbMode" Width="150" SelectedIndex="0" Background="#ffffff" Foreground="#09090b">
                                    <ComboBoxItem Content="Оконный (VMware)" Foreground="#09090b"/>
                                    <ComboBoxItem Content="Полноэкранный" Foreground="#09090b"/>
                                </ComboBox>
                            </StackPanel>
                        </WrapPanel>

                        <!-- Log Console -->
                        <TextBox Grid.Row="2" Name="TxtLog" Background="#111113" Foreground="#94a3b8" 
                                 FontFamily="Consolas" FontSize="12" IsReadOnly="True" TextWrapping="Wrap"
                                 VerticalScrollBarVisibility="Auto" BorderBrush="#27272a" Padding="8"/>
                    </Grid>
                </Border>
            </Grid>

            <!-- Footer -->
            <TextBlock Grid.Row="3" Text="Hyper-V GPU Partitioning Management Suite • Xeon E5-2696 v3 • GTX 1050 Ti" 
                       FontSize="11" Foreground="#52525b" Margin="0,10,0,0" HorizontalAlignment="Center"/>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Element References
$ListVMs          = $window.FindName("ListVMs")
$BtnCloneVM       = $window.FindName("BtnCloneVM")
$BtnRefresh       = $window.FindName("BtnRefresh")
$BtnStartVM       = $window.FindName("BtnStartVM")
$BtnStopVM        = $window.FindName("BtnStopVM")
$BtnOpenStream    = $window.FindName("BtnOpenStream")
$BtnPairMoonlight = $window.FindName("BtnPairMoonlight")
$BtnRandomizeHWID = $window.FindName("BtnRandomizeHWID")
$BtnVMConnect     = $window.FindName("BtnVMConnect")
$TxtVMTitle       = $window.FindName("TxtVMTitle")
$TxtVMSub         = $window.FindName("TxtVMSub")
$TxtStatusBadge   = $window.FindName("TxtStatusBadge")
$BadgeStatus      = $window.FindName("BadgeStatus")
$TxtCPU           = $window.FindName("TxtCPU")
$TxtRAM           = $window.FindName("TxtRAM")
$TxtVRAM          = $window.FindName("TxtVRAM")
$TxtIP            = $window.FindName("TxtIP")
$TxtLog           = $window.FindName("TxtLog")
$CmbResolution    = $window.FindName("CmbResolution")
$CmbFps           = $window.FindName("CmbFps")
$CmbMode          = $window.FindName("CmbMode")

# SOCKS5 Proxy Controls
$CmbProxyMode     = $window.FindName("CmbProxyMode")
$CmbProxyProfiles = $window.FindName("CmbProxyProfiles")
$BtnApplyProxy    = $window.FindName("BtnApplyProxy")
$BtnTestProxy     = $window.FindName("BtnTestProxy")
$BtnAddProxy      = $window.FindName("BtnAddProxy")
$BtnListProxy     = $window.FindName("BtnListProxy")
$TxtProxyStatus   = $window.FindName("TxtProxyStatus")
$BadgeProxyStatus = $window.FindName("BadgeProxyStatus")
$TxtKillSwitch    = $window.FindName("TxtKillSwitch")
$BadgeKillSwitch  = $window.FindName("BadgeKillSwitch")

$proxyManagerScript = Join-Path $PSScriptRoot "Host-Proxy-Manager.ps1"
if (Test-Path $proxyManagerScript) {
    . $proxyManagerScript
}

$MoonlightExe = "C:\Program Files\Moonlight Game Streaming\Moonlight.exe"

function Write-ConsoleLog([string]$msg) {
    $time = (Get-Date).ToString("HH:mm:ss")
    $TxtLog.AppendText("[$time] $msg`r`n")
    $TxtLog.ScrollToEnd()
}

function Get-VMIPAddress([string]$vmName) {
    # 1. Try query live IP from Hyper-V NetworkAdapters first
    try {
        $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        $ip = ($vm.NetworkAdapters.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notlike '169.254.*' })[0]
        if ($ip) { return $ip }
    } catch {}

    # 2. Check if VM has static IP mapped in table
    $ipMap = @{
        "Gaming-VM1" = "192.168.100.11"
        "Gaming-VM2" = "192.168.100.12"
        "Gaming-VM3" = "192.168.100.13"
        "Gaming-VM4" = "192.168.100.14"
        "Gaming-VM5" = "192.168.100.15"
    }
    if ($ipMap.ContainsKey($vmName)) {
        return $ipMap[$vmName]
    }
    
    return "192.168.100.11"
}

function Refresh-VMList {
    $currentSelectionName = $null
    if ($ListVMs.SelectedItem) {
        $currentSelectionName = $ListVMs.SelectedItem.Name
    }

    $allVMs = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Gaming-*" }
    $items = [System.Collections.ArrayList]::new()

    foreach ($vm in $allVMs) {
        $gpu = Get-VMGpuPartitionAdapter -VMName $vm.Name -ErrorAction SilentlyContinue
        $vramMB = "0 MB"
        if ($gpu -and $gpu.MaxPartitionVRAM) {
            $mb = [math]::Round(($gpu.MaxPartitionVRAM / 1000000000) * 4096)
            $vramMB = "${mb} MB VRAM"
        }

        $color = if ($vm.State -eq 'Running') { "#22c55e" } else { "#71717a" }
        $stateText = if ($vm.State -eq 'Running') { "Работает" } else { "Остановлена" }

        [void]$items.Add([PSCustomObject]@{
            Name        = $vm.Name
            State       = $vm.State
            StateText   = $stateText
            StatusColor = $color
            VRAMText    = $vramMB
            CPUCount    = $vm.ProcessorCount
            RAMGB       = [math]::Round($vm.MemoryAssigned / 1GB, 1)
            RAMStartup  = [math]::Round($vm.MemoryStartup / 1GB, 1)
            IP          = Get-VMIPAddress $vm.Name
        })
    }

    $ListVMs.ItemsSource = $items

    # Restore selection
    if ($currentSelectionName) {
        foreach ($item in $ListVMs.Items) {
            if ($item.Name -eq $currentSelectionName) {
                $ListVMs.SelectedItem = $item
                break
            }
        }
    }

    if (-not $ListVMs.SelectedItem -and $ListVMs.Items.Count -gt 0) {
        $ListVMs.SelectedIndex = 0
    }
}

function Refresh-ProxyProfilesUI {
    $CmbProxyProfiles.Items.Clear()
    if (Get-Command Get-ProxyConfig -ErrorAction SilentlyContinue) {
        $cfg = Get-ProxyConfig
        if ($cfg -and $cfg.profiles) {
            foreach ($p in $cfg.profiles) {
                $item = New-Object System.Windows.Controls.ComboBoxItem
                $item.Tag = $p.id
                $item.Content = "$($p.name) [$($p.server):$($p.port)]"
                $item.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#09090b")
                [void]$CmbProxyProfiles.Items.Add($item)
            }
        }
    }
    if ($CmbProxyProfiles.Items.Count -gt 0 -and $CmbProxyProfiles.SelectedIndex -lt 0) {
        $CmbProxyProfiles.SelectedIndex = 0
    }
}

function Update-SelectedVMDetails {
    param([bool]$ForceControlsUpdate = $false)

    $sel = $ListVMs.SelectedItem
    if (-not $sel) {
        $script:LastSelectedVMForProxy = $null
        $TxtVMTitle.Text = "Выберите виртуальную машину"
        $TxtVMSub.Text = "Нет активного выбора"
        $TxtStatusBadge.Text = "НЕТ ВЫБОРА"
        $BadgeStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#27272a")
        $TxtCPU.Text = "-"
        $TxtRAM.Text = "-"
        $TxtVRAM.Text = "-"
        $TxtIP.Text = "-"
        return
    }

    $TxtVMTitle.Text = $sel.Name
    $TxtVMSub.Text = "Hyper-V Generation 2 • GPU Partitioning"
    $TxtStatusBadge.Text = $sel.StateText.ToUpper()
    
    if ($sel.State -eq 'Running') {
        $BadgeStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#15803d")
        $TxtStatusBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#86efac")
    } else {
        $BadgeStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3f3f46")
        $TxtStatusBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#d4d4d8")
    }

    $TxtCPU.Text = "$($sel.CPUCount) ядер"
    $TxtRAM.Text = "$($sel.RAMStartup) ГБ"
    $TxtVRAM.Text = $sel.VRAMText
    $TxtIP.Text = $sel.IP

    # Update SOCKS5 Proxy Card State for selected VM
    if (Get-Command Get-VMProxyState -ErrorAction SilentlyContinue) {
        $proxyState = Get-VMProxyState -VMName $sel.Name
        if ($proxyState.Enabled) {
            $TxtProxyStatus.Text = "$($proxyState.ProfileName) ($($proxyState.Server))"
            $BadgeProxyStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#14532d")
            $TxtProxyStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ade80")
            $TxtKillSwitch.Text = "🛡️ Kill-Switch: АКТИВЕН"
            $BadgeKillSwitch.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#14532d")
            $TxtKillSwitch.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ade80")
        } else {
            $TxtProxyStatus.Text = "Прямой Интернет (IP Хоста)"
            $BadgeProxyStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#27272a")
            $TxtProxyStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#a1a1aa")
            $TxtKillSwitch.Text = "🛡️ Прямой NAT"
            $BadgeKillSwitch.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#27272a")
            $TxtKillSwitch.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#a1a1aa")
        }

        # CRITICAL: Only update user input controls (ComboBoxes) when selection changed or explicitly forced.
        # This prevents the 3-second background timer from resetting user's selection while they are configuring mode!
        $vmChanged = ($script:LastSelectedVMForProxy -ne $sel.Name)
        if ($ForceControlsUpdate -or $vmChanged) {
            $script:LastSelectedVMForProxy = $sel.Name

            if ($proxyState.Enabled) {
                $CmbProxyMode.SelectedIndex = 1
                for ($i = 0; $i -lt $CmbProxyProfiles.Items.Count; $i++) {
                    if ($CmbProxyProfiles.Items[$i].Tag -eq $proxyState.ProfileId) {
                        $CmbProxyProfiles.SelectedIndex = $i
                        break
                    }
                }
            } else {
                $CmbProxyMode.SelectedIndex = 0
            }
        }
    }
}

# Events
$ListVMs.Add_SelectionChanged({
    Update-SelectedVMDetails -ForceControlsUpdate $true
})

$BtnRefresh.Add_Click({
    Refresh-VMList
    Write-ConsoleLog "Список виртуальных машин обновлен."
})

$BtnStartVM.Add_Click({
    $sel = $ListVMs.SelectedItem
    if (-not $sel) { return }
    Write-ConsoleLog "Запуск виртуальной машины '$($sel.Name)'..."
    try {
        Start-VM -Name $sel.Name -ErrorAction Stop
        Write-ConsoleLog "Виртуальная машина '$($sel.Name)' успешно запущена!"
        Start-Sleep -Seconds 1
        Refresh-VMList
    } catch {
        Write-ConsoleLog "ОШИБКА запуска: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Ошибка запуска", "OK", "Error")
    }
})

$BtnStopVM.Add_Click({
    $sel = $ListVMs.SelectedItem
    if (-not $sel) { return }
    $res = [System.Windows.MessageBox]::Show("Выключить виртуальную машину '$($sel.Name)'?", "Подтверждение", "YesNo", "Question")
    if ($res -ne "Yes") { return }

    Write-ConsoleLog "Остановка виртуальной машины '$($sel.Name)'..."
    try {
        Stop-VM -Name $sel.Name -TurnOff -Force -ErrorAction Stop
        Write-ConsoleLog "Виртуальная машина '$($sel.Name)' остановлена."
        Start-Sleep -Seconds 1
        Refresh-VMList
    } catch {
        Write-ConsoleLog "ОШИБКА остановки: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show($_.Exception.Message, "Ошибка остановки", "OK", "Error")
    }
})

$BtnOpenStream.Add_Click({
    $sel = $ListVMs.SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Выберите виртуальную машину из списка слева.", "Внимание", "OK", "Warning")
        return
    }

    if (-not (Test-Path $MoonlightExe)) {
        [System.Windows.MessageBox]::Show("Клиент Moonlight не найден по пути:`n$MoonlightExe", "Moonlight не найден", "OK", "Error")
        return
    }

    # Ensure VM is running
    $vmState = (Get-VM -Name $sel.Name).State
    if ($vmState -ne 'Running') {
        $startNow = [System.Windows.MessageBox]::Show("Виртуальная машина '$($sel.Name)' не запущена. Запустить сейчас?", "Запуск VM", "YesNo", "Question")
        if ($startNow -eq "Yes") {
            Write-ConsoleLog "Запуск VM перед открытием стрима..."
            Start-VM -Name $sel.Name
            Refresh-VMList
        } else {
            return
        }
    }

    # Stream Arguments
    $modeArg = if ($CmbMode.SelectedIndex -eq 0) { "--display-mode windowed" } else { "--display-mode fullscreen" }
    $resArg = if ($CmbResolution.SelectedIndex -eq 0) { "--width 1024 --height 768" } elseif ($CmbResolution.SelectedIndex -eq 1) { "--720" } else { "--1080" }
    $fpsArg = if ($CmbFps.SelectedIndex -eq 0) { "--fps 60" } else { "--fps 120" }
    $guestIp = $sel.IP

    Write-ConsoleLog "Запуск окна Moonlight: $guestIp (Режим: Windowed VMware-like, $($CmbResolution.Text))..."
    
    $fullArgs = "stream $guestIp Desktop $modeArg $resArg $fpsArg"
    Start-Process -FilePath $MoonlightExe -ArgumentList $fullArgs
    Write-ConsoleLog "Сеанс Moonlight инициирован."
})

# --- Modern Dialog Helpers (Pure WPF, Dark Theme, 100% Crash-Proof) ---

function Show-PairMoonlightDialog {
    param([string]$vmIp, [string]$vmName)
    try {
        [xml]$pairXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Связывание Moonlight с Sunshine" Height="240" Width="400"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#18181b" Foreground="#f4f4f5" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#27272a"/>
            <Setter Property="Foreground" Value="#ffffff"/>
            <Setter Property="BorderBrush" Value="#3f3f46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="Связывание с $vmName ($vmIp)" FontWeight="Bold" FontSize="14" Foreground="#f4f4f5" Margin="0,0,0,6"/>
        <TextBlock Grid.Row="1" Text="Введите 4-значный PIN-код сопряжения:" FontSize="12" Foreground="#a1a1aa" Margin="0,0,0,10"/>
        
        <TextBox Grid.Row="2" Name="TxtPairPin" Text="1234" Margin="0,0,0,16"/>

        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Bottom">
            <Button Name="BtnDoPair" Content="🔑 Связать" Margin="0,0,8,0" Padding="16,6" Background="#2563eb" Foreground="#ffffff" BorderBrush="#3b82f6" FontWeight="Bold" Cursor="Hand"/>
            <Button Name="BtnCancelPair" Content="Отмена" Padding="14,6" Background="#27272a" Foreground="#a1a1aa" BorderBrush="#3f3f46" Cursor="Hand"/>
        </StackPanel>
    </Grid>
</Window>
"@
        $reader = [System.Xml.XmlNodeReader]::new($pairXaml)
        $dlg = [Windows.Markup.XamlReader]::Load($reader)
        $dlg.Owner = $window

        $TxtPairPin    = $dlg.FindName("TxtPairPin")
        $BtnDoPair     = $dlg.FindName("BtnDoPair")
        $BtnCancelPair = $dlg.FindName("BtnCancelPair")

        $script:pairPinResult = $null

        $BtnDoPair.Add_Click({
            $p = $TxtPairPin.Text.Trim()
            if (-not [string]::IsNullOrWhiteSpace($p)) {
                $script:pairPinResult = $p
                $dlg.DialogResult = $true
                $dlg.Close()
            }
        })

        $BtnCancelPair.Add_Click({
            $dlg.DialogResult = $false
            $dlg.Close()
        })

        $script:pairPinResult = $null
        $res = $dlg.ShowDialog()
        if ($res -eq $true -and $script:pairPinResult) {
            return $script:pairPinResult
        }
    } catch {
        Write-ConsoleLog "[!] Ошибка окна сопряжения Moonlight: $($_.Exception.Message)"
    }
    return $null
}

function Show-CloneVMDialog {
    param([string]$defaultName, [string]$defaultIp)
    try {
        [xml]$cloneXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Клонирование виртуальной машины" Height="270" Width="400"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#18181b" Foreground="#f4f4f5" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#27272a"/>
            <Setter Property="Foreground" Value="#ffffff"/>
            <Setter Property="BorderBrush" Value="#3f3f46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#a1a1aa"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Margin" Value="0,0,0,3"/>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0">
            <TextBlock Text="Имя новой виртуальной машины:" FontWeight="SemiBold"/>
            <TextBox Name="TxtCloneName" Text="$defaultName"/>
        </StackPanel>

        <StackPanel Grid.Row="1">
            <TextBlock Text="Статический IP адрес (сеть 192.168.100.x):" FontWeight="SemiBold"/>
            <TextBox Name="TxtCloneIp" Text="$defaultIp"/>
        </StackPanel>

        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Bottom">
            <Button Name="BtnDoClone" Content="➕ Создать клон" Margin="0,0,8,0" Padding="16,6" Background="#2563eb" Foreground="#ffffff" BorderBrush="#3b82f6" FontWeight="Bold" Cursor="Hand"/>
            <Button Name="BtnCancelClone" Content="Отмена" Padding="14,6" Background="#27272a" Foreground="#a1a1aa" BorderBrush="#3f3f46" Cursor="Hand"/>
        </StackPanel>
    </Grid>
</Window>
"@
        $reader = [System.Xml.XmlNodeReader]::new($cloneXaml)
        $dlg = [Windows.Markup.XamlReader]::Load($reader)
        $dlg.Owner = $window

        $TxtCloneName   = $dlg.FindName("TxtCloneName")
        $TxtCloneIp     = $dlg.FindName("TxtCloneIp")
        $BtnDoClone     = $dlg.FindName("BtnDoClone")
        $BtnCancelClone = $dlg.FindName("BtnCancelClone")

        $script:cloneResult = $null

        $BtnDoClone.Add_Click({
            $n = $TxtCloneName.Text.Trim()
            $ip = $TxtCloneIp.Text.Trim()
            if (-not [string]::IsNullOrWhiteSpace($n) -and -not [string]::IsNullOrWhiteSpace($ip)) {
                $script:cloneResult = [PSCustomObject]@{ Name = $n; IP = $ip }
                $dlg.DialogResult = $true
                $dlg.Close()
            }
        })

        $BtnCancelClone.Add_Click({
            $dlg.DialogResult = $false
            $dlg.Close()
        })

        $script:cloneResult = $null
        $res = $dlg.ShowDialog()
        if ($res -eq $true -and $script:cloneResult) {
            return $script:cloneResult
        }
    } catch {
        Write-ConsoleLog "[!] Ошибка окна клонирования VM: $($_.Exception.Message)"
    }
    return $null
}

function Show-AddProxyDialog {
    try {
        [xml]$dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Добавление SOCKS5 Прокси" Height="520" Width="500"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#18181b" Foreground="#f4f4f5" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#27272a"/>
            <Setter Property="Foreground" Value="#ffffff"/>
            <Setter Property="BorderBrush" Value="#3f3f46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#a1a1aa"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Margin" Value="0,0,0,3"/>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Быстрый ввод -->
        <Border Grid.Row="0" Background="#202024" CornerRadius="6" Padding="10" Margin="0,0,0,12" BorderBrush="#3f3f46" BorderThickness="1">
            <StackPanel>
                <TextBlock Text="⚡ Быстрый ввод (domain:port:username:password):" FontWeight="SemiBold" Foreground="#38bdf8" Margin="0,0,0,5"/>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBox Name="TxtDlgQuickInput" Margin="0,0,8,0" Padding="8,5" Text="" ToolTip="Вставьте строку вида domain:port:username:password"/>
                    <Button Grid.Column="1" Name="BtnDlgPaste" Content="📋 Вставить" Padding="12,5" Background="#27272a" Foreground="#e4e4e7" BorderBrush="#52525b" Cursor="Hand" FontWeight="SemiBold"/>
                </Grid>
                <TextBlock Text="При вводе или вставке строки поля ниже заполняются мгновенно" FontSize="11" Foreground="#71717a" Margin="0,2,0,0"/>
            </StackPanel>
        </Border>

        <!-- Название профиля -->
        <StackPanel Grid.Row="1">
            <TextBlock Text="Название профиля:" FontWeight="SemiBold"/>
            <TextBox Name="TxtDlgName" Text="Новый SOCKS5"/>
        </StackPanel>

        <!-- Хост и Порт -->
        <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="100"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,10,0">
                <TextBlock Text="IP адрес / Хост:" FontWeight="SemiBold"/>
                <TextBox Name="TxtDlgServer" Text=""/>
            </StackPanel>
            <StackPanel Grid.Column="1">
                <TextBlock Text="Порт:" FontWeight="SemiBold"/>
                <TextBox Name="TxtDlgPort" Text="1080"/>
            </StackPanel>
        </Grid>

        <!-- Логин и Пароль -->
        <Grid Grid.Row="3">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Margin="0,0,10,0">
                <TextBlock Text="Логин (необязательно):"/>
                <TextBox Name="TxtDlgUser" Text=""/>
            </StackPanel>
            <StackPanel Grid.Column="1">
                <TextBlock Text="Пароль (необязательно):"/>
                <TextBox Name="TxtDlgPass" Text=""/>
            </StackPanel>
        </Grid>

        <!-- Статус проверки -->
        <Border Grid.Row="4" Background="#111113" CornerRadius="6" Padding="10" Margin="0,2,0,12" BorderBrush="#27272a" BorderThickness="1">
            <TextBlock Name="TxtDlgStatus" Text="💡 Введите данные вручную или вставьте строку domain:port:username:password выше" FontSize="11" Foreground="#71717a" TextWrapping="Wrap"/>
        </Border>

        <!-- Кнопки управления -->
        <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Bottom">
            <Button Name="BtnDlgTest" Content="🔍 Проверить" Margin="0,0,8,0" Padding="14,6" Background="#27272a" Foreground="#ffffff" BorderBrush="#3f3f46" Cursor="Hand"/>
            <Button Name="BtnDlgSave" Content="💾 Сохранить" Margin="0,0,8,0" Padding="14,6" Background="#2563eb" Foreground="#ffffff" BorderBrush="#3b82f6" FontWeight="Bold" Cursor="Hand"/>
            <Button Name="BtnDlgCancel" Content="Отмена" Padding="14,6" Background="#27272a" Foreground="#a1a1aa" BorderBrush="#3f3f46" Cursor="Hand"/>
        </StackPanel>
    </Grid>
</Window>
"@
        $reader = [System.Xml.XmlNodeReader]::new($dialogXaml)
        $dlg = [Windows.Markup.XamlReader]::Load($reader)
        $dlg.Owner = $window

        $TxtDlgQuickInput = $dlg.FindName("TxtDlgQuickInput")
        $BtnDlgPaste      = $dlg.FindName("BtnDlgPaste")
        $TxtDlgName       = $dlg.FindName("TxtDlgName")
        $TxtDlgServer     = $dlg.FindName("TxtDlgServer")
        $TxtDlgPort       = $dlg.FindName("TxtDlgPort")
        $TxtDlgUser       = $dlg.FindName("TxtDlgUser")
        $TxtDlgPass       = $dlg.FindName("TxtDlgPass")
        $TxtDlgStatus     = $dlg.FindName("TxtDlgStatus")
        $BtnDlgTest       = $dlg.FindName("BtnDlgTest")
        $BtnDlgSave       = $dlg.FindName("BtnDlgSave")
        $BtnDlgCancel     = $dlg.FindName("BtnDlgCancel")

        $ParseQuickString = {
            param([string]$raw)
            if ([string]::IsNullOrWhiteSpace($raw)) { return }
            $clean = $raw.Trim()

            # Очистка от протокола (socks5://, socks5h://, http://)
            if ($clean -match '^[a-zA-Z0-9]+://(.*)$') {
                $clean = $matches[1]
            }

            # Поддержка формата user:pass@domain:port
            if ($clean -match '^(.*?):(.*?)@(.*?):(\d+)$') {
                $TxtDlgUser.Text = $matches[1].Trim()
                $TxtDlgPass.Text = $matches[2].Trim()
                $TxtDlgServer.Text = $matches[3].Trim()
                $TxtDlgPort.Text = $matches[4].Trim()
                if ($TxtDlgName.Text -eq "Новый SOCKS5" -or [string]::IsNullOrWhiteSpace($TxtDlgName.Text)) {
                    $TxtDlgName.Text = "SOCKS5 " + $matches[3].Trim()
                }
                $TxtDlgStatus.Text = "✅ Распознано: " + $matches[3].Trim() + ":" + $matches[4].Trim() + " (Пользователь: " + $matches[1].Trim() + ")"
                $TxtDlgStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ade80")
                return
            }

            # Основной формат: domain:port:username:password или domain:port
            $parts = $clean -split ':'
            if ($parts.Count -ge 4) {
                $TxtDlgServer.Text = $parts[0].Trim()
                $TxtDlgPort.Text = $parts[1].Trim()
                $TxtDlgUser.Text = $parts[2].Trim()
                $TxtDlgPass.Text = ($parts[3..($parts.Count - 1)] -join ':').Trim()
                if ($TxtDlgName.Text -eq "Новый SOCKS5" -or [string]::IsNullOrWhiteSpace($TxtDlgName.Text)) {
                    $TxtDlgName.Text = "SOCKS5 " + $parts[0].Trim()
                }
                $TxtDlgStatus.Text = "✅ Распознано: " + $parts[0].Trim() + ":" + $parts[1].Trim() + " (Пользователь: " + $parts[2].Trim() + ")"
                $TxtDlgStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ade80")
            } elseif ($parts.Count -eq 2) {
                $TxtDlgServer.Text = $parts[0].Trim()
                $TxtDlgPort.Text = $parts[1].Trim()
                if ($TxtDlgName.Text -eq "Новый SOCKS5" -or [string]::IsNullOrWhiteSpace($TxtDlgName.Text)) {
                    $TxtDlgName.Text = "SOCKS5 " + $parts[0].Trim()
                }
                $TxtDlgStatus.Text = "✅ Распознано: " + $parts[0].Trim() + ":" + $parts[1].Trim() + " (Без авторизации)"
                $TxtDlgStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ade80")
            } elseif ($parts.Count -eq 3) {
                $TxtDlgServer.Text = $parts[0].Trim()
                $TxtDlgPort.Text = $parts[1].Trim()
                $TxtDlgUser.Text = $parts[2].Trim()
                $TxtDlgStatus.Text = "✅ Распознано: " + $parts[0].Trim() + ":" + $parts[1].Trim() + " (Логин: " + $parts[2].Trim() + ")"
                $TxtDlgStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ade80")
            }
        }

        # Автоматическое распознавание при вводе в поле быстрого ввода
        $TxtDlgQuickInput.Add_TextChanged({
            try {
                & $ParseQuickString $TxtDlgQuickInput.Text
            } catch {}
        })

        # Кнопка вставки из буфера обмена
        $BtnDlgPaste.Add_Click({
            try {
                $clip = [System.Windows.Clipboard]::GetText()
                if (-not [string]::IsNullOrWhiteSpace($clip)) {
                    $TxtDlgQuickInput.Text = $clip.Trim()
                    & $ParseQuickString $clip
                }
            } catch {
                $TxtDlgStatus.Text = "⚠️ Буфер обмена недоступен: $($_.Exception.Message)"
                $TxtDlgStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f59e0b")
            }
        })

        $BtnDlgTest.Add_Click({
            $s = $TxtDlgServer.Text.Trim()
            $p = 1080
            [int]::TryParse($TxtDlgPort.Text.Trim(), [ref]$p) | Out-Null
            $u = $TxtDlgUser.Text.Trim()
            $pw = $TxtDlgPass.Text.Trim()

            if ([string]::IsNullOrWhiteSpace($s)) {
                $TxtDlgStatus.Text = "⚠️ Укажите IP адрес или хост сервера!"
                $TxtDlgStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f59e0b")
                return
            }

            $TxtDlgStatus.Text = "⏳ Проверка подключения к " + $s + ":" + $p + "..."
            $TxtDlgStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38bdf8")
            
            try {
                $testRes = Test-ProxyEndpoint -Server $s -Port $p -Username $u -Password $pw -TimeoutSec 5
                if ($testRes.Success) {
                    $TxtDlgStatus.Text = "🟢 Успешно! Exit IP: $($testRes.IP) ($($testRes.Country), $($testRes.City)), Пинг: $($testRes.LatencyMs) мс"
                    $TxtDlgStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ade80")
                } else {
                    $TxtDlgStatus.Text = "🔴 Ошибка подключения: $($testRes.Error)"
                    $TxtDlgStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f87171")
                }
            } catch {
                $TxtDlgStatus.Text = "🔴 Ошибка теста: $($_.Exception.Message)"
                $TxtDlgStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f87171")
            }
        })

        $BtnDlgSave.Add_Click({
            $s = $TxtDlgServer.Text.Trim()
            $p = 1080
            [int]::TryParse($TxtDlgPort.Text.Trim(), [ref]$p) | Out-Null
            $n = $TxtDlgName.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($n)) { $n = "SOCKS5 Proxy" }
            $u = $TxtDlgUser.Text.Trim()
            $pw = $TxtDlgPass.Text.Trim()

            if ([string]::IsNullOrWhiteSpace($s)) {
                $TxtDlgStatus.Text = "⚠️ Укажите IP адрес или хост сервера!"
                $TxtDlgStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f59e0b")
                return
            }

            $script:savedProfileResult = [PSCustomObject]@{
                name = $n
                server = $s
                port = $p
                username = $u
                password = $pw
            }
            $dlg.DialogResult = $true
            $dlg.Close()
        })

        $BtnDlgCancel.Add_Click({
            $dlg.DialogResult = $false
            $dlg.Close()
        })

        $script:savedProfileResult = $null
        $res = $dlg.ShowDialog()
        if ($res -eq $true -and $script:savedProfileResult) {
            return $script:savedProfileResult
        }
    } catch {
        Write-ConsoleLog "[!] Ошибка окна добавления прокси: $($_.Exception.Message)"
    }
    return $null
}

function Show-ProxyListDialog {
    try {
        [xml]$dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Список сохранённых SOCKS5 Прокси" Height="500" Width="720"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#18181b" Foreground="#f4f4f5" FontFamily="Segoe UI">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Grid Grid.Row="0" Margin="0,0,0,12">
            <StackPanel>
                <TextBlock Text="📋 Сохранённые SOCKS5 Прокси" FontSize="16" FontWeight="Bold" Foreground="#ffffff"/>
                <TextBlock Text="Управление сохранёнными профилями. При удалении активного прокси привязанная виртуалка будет безопасно переведена на прямое подключение." FontSize="11" Foreground="#71717a" Margin="0,3,0,0"/>
            </StackPanel>
        </Grid>

        <!-- Scrollable Cards List -->
        <Border Grid.Row="1" Background="#131316" CornerRadius="8" BorderBrush="#2e2e33" BorderThickness="1" Padding="8">
            <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <StackPanel Name="PnlProxyCards"/>
            </ScrollViewer>
        </Border>

        <!-- Footer Controls -->
        <Grid Grid.Row="2" Margin="0,12,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Button Grid.Column="0" Name="BtnListAdd" Content="➕ Добавить новый прокси" Padding="14,6" Background="#2563eb" Foreground="#ffffff" BorderBrush="#3b82f6" FontWeight="SemiBold" Cursor="Hand"/>
            <Button Grid.Column="2" Name="BtnListClose" Content="Закрыть" Padding="16,6" Background="#27272a" Foreground="#a1a1aa" BorderBrush="#3f3f46" Cursor="Hand"/>
        </Grid>
    </Grid>
</Window>
"@
        $reader = [System.Xml.XmlNodeReader]::new($dialogXaml)
        $dlg = [Windows.Markup.XamlReader]::Load($reader)
        $dlg.Owner = $window

        $PnlProxyCards = $dlg.FindName("PnlProxyCards")
        $BtnListAdd    = $dlg.FindName("BtnListAdd")
        $BtnListClose  = $dlg.FindName("BtnListClose")

        $RenderList = {
            $PnlProxyCards.Children.Clear()
            $cfg = Get-ProxyConfig
            if (-not $cfg.profiles -or $cfg.profiles.Count -eq 0) {
                $emptyTb = New-Object System.Windows.Controls.TextBlock
                $emptyTb.Text = "Нет сохранённых профилей. Нажмите '➕ Добавить новый прокси', чтобы добавить сервер."
                $emptyTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#71717a")
                $emptyTb.FontSize = 12
                $emptyTb.Margin = [System.Windows.Thickness]::new(10, 20, 10, 10)
                $emptyTb.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                [void]$PnlProxyCards.Children.Add($emptyTb)
                return
            }

            foreach ($p in $cfg.profiles) {
                # Determine active VM bindings
                $activeVMs = @()
                if ($cfg.assignments) {
                    foreach ($prop in $cfg.assignments.PSObject.Properties) {
                        if ($prop.Value.enabled -and $prop.Value.profileId -eq $p.id) {
                            $activeVMs += $prop.Name
                        }
                    }
                }

                $border = New-Object System.Windows.Controls.Border
                $border.CornerRadius = [System.Windows.CornerRadius]::new(6)
                $border.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
                $border.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
                $border.BorderThickness = [System.Windows.Thickness]::new(1)
                if ($activeVMs.Count -gt 0) {
                    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#18261e")
                    $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#059669")
                } else {
                    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1f1f23")
                    $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2e2e33")
                }

                $grid = New-Object System.Windows.Controls.Grid
                $col0 = New-Object System.Windows.Controls.ColumnDefinition
                $col0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
                $col1 = New-Object System.Windows.Controls.ColumnDefinition
                $col1.Width = [System.Windows.GridLength]::Auto
                $grid.ColumnDefinitions.Add($col0)
                $grid.ColumnDefinitions.Add($col1)

                # Info Column
                $infoPnl = New-Object System.Windows.Controls.StackPanel
                $infoPnl.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

                $titleRow = New-Object System.Windows.Controls.StackPanel
                $titleRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal

                $nameTb = New-Object System.Windows.Controls.TextBlock
                $nameTb.Text = $p.name
                $nameTb.FontWeight = [System.Windows.FontWeights]::Bold
                $nameTb.FontSize = 13
                $nameTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f4f4f5")
                $titleRow.Children.Add($nameTb)

                $badge = New-Object System.Windows.Controls.Border
                $badge.CornerRadius = [System.Windows.CornerRadius]::new(4)
                $badge.Padding = [System.Windows.Thickness]::new(6, 1, 6, 1)
                $badge.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
                $badgeTb = New-Object System.Windows.Controls.TextBlock
                $badgeTb.FontSize = 10
                $badgeTb.FontWeight = [System.Windows.FontWeights]::SemiBold

                if ($activeVMs.Count -gt 0) {
                    $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#064e3b")
                    $badgeTb.Text = "🔒 АКТИВЕН: " + ($activeVMs -join ", ")
                    $badgeTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34d399")
                } else {
                    $badge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#27272a")
                    $badgeTb.Text = "Не привязан"
                    $badgeTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#71717a")
                }
                $badge.Child = $badgeTb
                $titleRow.Children.Add($badge)
                $infoPnl.Children.Add($titleRow)

                # Endpoint details
                $subTb = New-Object System.Windows.Controls.TextBlock
                $authText = if ($p.username) { "Пользователь: $($p.username)" } else { "Без авторизации" }
                $geoText = if ($p.country -and $p.country -ne "Custom") { " • $($p.country) $($p.city)" } else { "" }
                $subTb.Text = "$($p.server):$($p.port) • $authText$geoText"
                $subTb.FontSize = 11
                $subTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#a1a1aa")
                $subTb.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
                $infoPnl.Children.Add($subTb)

                # Test Status TextBlock (dynamically updated on test)
                $statusTb = New-Object System.Windows.Controls.TextBlock
                $statusTb.FontSize = 11
                $statusTb.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
                $statusTb.Visibility = [System.Windows.Visibility]::Collapsed
                $infoPnl.Children.Add($statusTb)

                [System.Windows.Controls.Grid]::SetColumn($infoPnl, 0)
                $grid.Children.Add($infoPnl)

                # Action Buttons Column
                $btnPnl = New-Object System.Windows.Controls.StackPanel
                $btnPnl.Orientation = [System.Windows.Controls.Orientation]::Horizontal
                $btnPnl.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

                # Test Button
                $btnTest = New-Object System.Windows.Controls.Button
                $btnTest.Content = "🔍 Проверить"
                $btnTest.Padding = [System.Windows.Thickness]::new(8, 4, 8, 4)
                $btnTest.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
                $btnTest.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#27272a")
                $btnTest.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#e4e4e7")
                $btnTest.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3f3f46")
                $btnTest.Cursor = [System.Windows.Input.Cursors]::Hand
                $btnTest.Tag = [PSCustomObject]@{ Profile = $p; StatusBlock = $statusTb }

                $btnTest.Add_Click({
                    $tagObj = $this.Tag
                    $targetP = $tagObj.Profile
                    $targetTb = $tagObj.StatusBlock
                    $targetTb.Visibility = [System.Windows.Visibility]::Visible
                    $targetTb.Text = "⏳ Проверка $($targetP.server):$($targetP.port)..."
                    $targetTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38bdf8")
                    
                    try {
                        $res = Test-ProxyEndpoint -Server $targetP.server -Port $targetP.port -Username $targetP.username -Password $targetP.password -TimeoutSec 5
                        if ($res.Success) {
                            $targetTb.Text = "🟢 OK! IP: $($res.IP) ($($res.Country), $($res.City)), Пинг: $($res.LatencyMs) мс"
                            $targetTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ade80")
                        } else {
                            $targetTb.Text = "🔴 Ошибка: $($res.Error)"
                            $targetTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f87171")
                        }
                    } catch {
                        $targetTb.Text = "🔴 Сбой теста: $($_.Exception.Message)"
                        $targetTb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f87171")
                    }
                })
                $btnPnl.Children.Add($btnTest)

                # Delete Button
                $btnDel = New-Object System.Windows.Controls.Button
                $btnDel.Content = "❌ Удалить"
                $btnDel.Padding = [System.Windows.Thickness]::new(10, 4, 10, 4)
                $btnDel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#450a0a")
                $btnDel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#fca5a5")
                $btnDel.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#991b1b")
                $btnDel.Cursor = [System.Windows.Input.Cursors]::Hand
                $btnDel.FontWeight = [System.Windows.FontWeights]::SemiBold
                $btnDel.Tag = [PSCustomObject]@{ Profile = $p; ActiveVMs = $activeVMs }

                $btnDel.Add_Click({
                    try {
                        $tagObj = $this.Tag
                        $delP = $tagObj.Profile
                        $delActiveVMs = $tagObj.ActiveVMs

                        if ($delActiveVMs -and $delActiveVMs.Count -gt 0) {
                            $msg = "Прокси '$($delP.name)' в данный момент АКТИВЕН для виртуальной машины: $($delActiveVMs -join ', ')!`n`nПри удалении прокси будет отключен, а виртуалка будет немедленно переведена на прямое подключение хоста (Kill-Switch будет снят).`n`nВы действительно хотите удалить этот прокси?"
                            $ans = [System.Windows.MessageBox]::Show($msg, "Удаление активного прокси", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
                            if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { return }
                        } else {
                            $msg = "Удалить профиль прокси '$($delP.name)' ($($delP.server):$($delP.port))?"
                            $ans = [System.Windows.MessageBox]::Show($msg, "Удаление прокси", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
                            if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { return }
                        }

                        Write-ConsoleLog "Удаление профиля '$($delP.name)' ($($delP.id))..."
                        $rmRes = Remove-ProxyProfile -ProfileId $delP.id
                        if ($rmRes -and $rmRes.Success) {
                            Write-ConsoleLog "Профиль '$($delP.name)' успешно удален!"
                            if ($rmRes.UnboundVMs.Count -gt 0) {
                                Write-ConsoleLog "Виртуальные машины [$($rmRes.UnboundVMs -join ', ')] переведены на прямое интернет-соединение хоста."
                            }
                        } else {
                            Write-ConsoleLog "Профиль '$($delP.name)' удален из списка."
                        }

                        Refresh-ProxyProfilesUI
                        Update-SelectedVMDetails -ForceControlsUpdate $true
                        & $RenderList
                    } catch {
                        Write-ConsoleLog "[!] Ошибка удаления прокси: $($_.Exception.Message)"
                        [System.Windows.MessageBox]::Show("Ошибка удаления прокси: $($_.Exception.Message)", "Ошибка", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                    }
                })
                $btnPnl.Children.Add($btnDel)

                [System.Windows.Controls.Grid]::SetColumn($btnPnl, 1)
                $grid.Children.Add($btnPnl)

                $border.Child = $grid
                [void]$PnlProxyCards.Children.Add($border)
            }
        }

        # Initial Render
        & $RenderList

        # Add Button in Dialog
        $BtnListAdd.Add_Click({
            try {
                $newProxy = Show-AddProxyDialog
                if ($newProxy) {
                    $cfg = Get-ProxyConfig
                    $newId = "proxy-" + ($cfg.profiles.Count + 1)
                    $newProf = [PSCustomObject]@{
                        id = $newId
                        name = $newProxy.name
                        server = $newProxy.server
                        port = $newProxy.port
                        username = $newProxy.username
                        password = $newProxy.password
                        country = "Custom"
                        city = "Custom"
                        isp = "Custom"
                    }
                    $cfg.profiles += $newProf
                    Save-ProxyConfig $cfg
                    Refresh-ProxyProfilesUI
                    Write-ConsoleLog "Профиль '$($newProxy.name)' ($($newProxy.server):$($newProxy.port)) успешно добавлен!"
                    & $RenderList
                }
            } catch {
                Write-ConsoleLog "[!] Ошибка при добавлении прокси: $($_.Exception.Message)"
            }
        })

        $BtnListClose.Add_Click({
            $dlg.Close()
        })

        $dlg.ShowDialog() | Out-Null
    } catch {
        Write-ConsoleLog "[!] Ошибка окна списка прокси: $($_.Exception.Message)"
    }
}

# --- Action Event Handlers ---

$BtnPairMoonlight.Add_Click({
    try {
        $sel = $ListVMs.SelectedItem
        if (-not $sel) {
            [System.Windows.MessageBox]::Show("Пожалуйста, выберите виртуальную машину для связывания.", "Связывание Moonlight", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }

        $pin = Show-PairMoonlightDialog -vmIp $sel.IP -vmName $sel.Name
        if ([string]::IsNullOrWhiteSpace($pin)) { return }

        Write-ConsoleLog "Связывание Moonlight с хостом $($sel.IP) с PIN: $pin..."
        
        # 1. Start Moonlight pairing process in background
        try {
            Start-Process -FilePath $MoonlightExe -ArgumentList "pair $($sel.IP) --pin $pin"
            Start-Sleep -Seconds 2
        } catch {
            Write-ConsoleLog "[!] Ошибка запуска Moonlight: $($_.Exception.Message)"
        }

        # 2. Submit PIN to Sunshine Web API on guest
        try {
            $pairUrl = "https://$($sel.IP):47990/api/pin"
            $pairHeader = @{
                Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:admin1234"))
            }

            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
            $pending = Invoke-RestMethod -Uri $pairUrl -Method Get -Headers $pairHeader -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($pending -and $pending.pairings -and $pending.pairings.Count -gt 0) {
                $pId = $pending.pairings[0].id
                $devName = $pending.pairings[0].name
                $body = @{
                    pairing_id = $pId
                    pin = $pin
                    name = $devName
                } | ConvertTo-Json
                Invoke-RestMethod -Uri $pairUrl -Method Post -Body $body -ContentType "application/json" -Headers $pairHeader -TimeoutSec 5 -ErrorAction SilentlyContinue | Out-Null
                Write-ConsoleLog "[+] PIN успешно подтвержден в Sunshine API для устройства '$devName'."
            } else {
                # Direct PIN submission fallback
                $body = @{ pin = $pin } | ConvertTo-Json
                Invoke-RestMethod -Uri $pairUrl -Method Post -Body $body -ContentType "application/json" -Headers $pairHeader -TimeoutSec 5 -ErrorAction SilentlyContinue | Out-Null
                Write-ConsoleLog "[+] Запрос PIN отправлен в Sunshine API."
            }
        } catch {
            Write-ConsoleLog "[!] Замечание при передаче PIN через API: $($_.Exception.Message)"
        }

        Write-ConsoleLog "Команда сопряжения Moonlight завершена."
    } catch {
        Write-ConsoleLog "[!] Ошибка в обработчике сопряжения Moonlight: $($_.Exception.Message)"
    }
})

$BtnVMConnect.Add_Click({
    try {
        $sel = $ListVMs.SelectedItem
        if ($sel) {
            Start-Process "vmconnect.exe" -ArgumentList "localhost `"$($sel.Name)`""
        } else {
            Start-Process "virtmgmt.msc"
        }
    } catch {
        Write-ConsoleLog "[!] Ошибка запуска vmconnect: $($_.Exception.Message)"
    }
})

$BtnRandomizeHWID.Add_Click({
    try {
        $sel = $ListVMs.SelectedItem
        if (-not $sel) {
            [System.Windows.MessageBox]::Show("Пожалуйста, выберите виртуальную машину для рандомизации HWID.", "Спуфинг HWID", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }
        $vm = Get-VM -Name $sel.Name -ErrorAction SilentlyContinue
        if ($vm -and $vm.State -ne 'Off') {
            $ans = [System.Windows.MessageBox]::Show("ВМ '$($sel.Name)' в данный момент работает.`n`nДля безопасной модификации SMBIOS, SCSI Disk Identifier и сетевого MAC адреса ВМ должна быть выключена.`n`nВыключить ВМ и выполнить спуфинг HWID?", "Требуется остановка ВМ", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
            if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { return }
            Write-ConsoleLog "Остановка ВМ '$($sel.Name)'..."
            Stop-VM -Name $sel.Name -TurnOff -Force
            Start-Sleep -Seconds 2
        }
        Write-ConsoleLog "Запуск спуфинга и аппаратной рандомизации для '$($sel.Name)'..."
        $randScript = Join-Path $PSScriptRoot "Host-HyperV-Randomize.ps1"
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$randScript`" -VMName `"$($sel.Name)`"" -Wait
        Write-ConsoleLog "Аппаратный профиль '$($sel.Name)' успешно рандомизирован!"
        Refresh-VMList
    } catch {
        Write-ConsoleLog "[!] Ошибка при спуфинге HWID: $($_.Exception.Message)"
    }
})

$BtnCloneVM.Add_Click({
    try {
        $allVMs = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Gaming-*" }
        $existingNums = @()
        foreach ($v in $allVMs) {
            if ($v.Name -match '^Gaming-VM(\d+)$') {
                $existingNums += [int]$Matches[1]
            }
        }
        $nextNum = 1
        while ($nextNum -in $existingNums) { $nextNum++ }
        $defaultNewName = "Gaming-VM$nextNum"
        $defaultNewIP = "192.168.100.$(10 + $nextNum)"

        $cloneData = Show-CloneVMDialog -defaultName $defaultNewName -defaultIp $defaultNewIP
        if (-not $cloneData) { return }

        $newName = $cloneData.Name
        $newIP = $cloneData.IP
        $targetVhd = "C:\Hyper-V\VMs\$newName.vhdx"

        Write-ConsoleLog "Запуск процесса клонирования VM '$newName' (IP: $newIP, Диск: $targetVhd)..."
        
        $cloneScript = Join-Path $PSScriptRoot "05-Clone-VM.ps1"
        $cmd = "& '$cloneScript' -NewVMName '$newName' -NewVHDPath '$targetVhd' -NewGuestIP '$newIP'"
        $fullArgs = "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd; if (`$LASTEXITCODE -ne 0) { Write-Host '`n[!] Ошибка выполнения! Нажмите любую клавишу для закрытия...' -ForegroundColor Red; `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }`""
        
        $proc = Start-Process powershell.exe -ArgumentList $fullArgs -Wait -PassThru
        
        if ($proc.ExitCode -eq 0) {
            Write-ConsoleLog "Клонирование успешно завершено! Создана VM '$newName'."
            Refresh-VMList
            $newItem = $ListVMs.Items | Where-Object { $_.Name -eq $newName } | Select-Object -First 1
            if ($newItem) {
                $ListVMs.SelectedItem = $newItem
            }
        } else {
            Write-ConsoleLog "[!] Ошибка: процесс клонирования VM завершился с кодом $($proc.ExitCode)."
            [System.Windows.MessageBox]::Show("Произошла ошибка при клонировании виртуальной машины '$newName' (код $($proc.ExitCode)).`nПроверьте детали в консольном окне.", "Ошибка клонирования", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    } catch {
        Write-ConsoleLog "[!] Ошибка при вызове клонирования VM: $($_.Exception.Message)"
    }
})

# SOCKS5 Proxy Events
$BtnApplyProxy.Add_Click({
    try {
        $sel = $ListVMs.SelectedItem
        if (-not $sel) {
            [System.Windows.MessageBox]::Show("Пожалуйста, выберите виртуальную машину для настройки прокси.", "SOCKS5 Прокси", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }

        $isProxy = ($CmbProxyMode.SelectedIndex -eq 1)
        $profileId = if ($CmbProxyProfiles.SelectedItem) { $CmbProxyProfiles.SelectedItem.Tag } else { "proxy-1" }

        Write-ConsoleLog "Применение сетевой маршрутизации для $($sel.Name)..."
        Set-VMProxyRouting -VMName $sel.Name -Enabled $isProxy -ProfileId $profileId
        if ($isProxy) {
            Write-ConsoleLog "SOCKS5 Прокси [$profileId] успешно активирован для $($sel.Name)! Прямой NAT отключен (Kill-Switch активен)."
        } else {
            Write-ConsoleLog "Прокси отключен для $($sel.Name). Восстановлен прямой Интернет (IP Хоста)."
        }
        Update-SelectedVMDetails -ForceControlsUpdate $true
    } catch {
        Write-ConsoleLog "[!] Ошибка применения прокси: $($_.Exception.Message)"
    }
})

$BtnTestProxy.Add_Click({
    try {
        $selItem = $CmbProxyProfiles.SelectedItem
        if (-not $selItem) { return }
        $profId = $selItem.Tag
        $cfg = Get-ProxyConfig
        $prof = $cfg.profiles | Where-Object { $_.id -eq $profId } | Select-Object -First 1
        if (-not $prof) { return }

        Write-ConsoleLog "Тестирование прокси '$($prof.name)' ($($prof.server):$($prof.port))..."
        $res = Test-ProxyEndpoint -Server $prof.server -Port $prof.port -Username $prof.username -Password $prof.password
        if ($res.Success) {
            Write-ConsoleLog "Результат теста: УСПЕХ! Внешний IP: $($res.IP) ($($res.Country), $($res.City)), Пинг: $($res.LatencyMs) мс"
        } else {
            Write-ConsoleLog "Результат теста: ОШИБКА ($($res.Error))"
        }
    } catch {
        Write-ConsoleLog "[!] Ошибка тестирования прокси: $($_.Exception.Message)"
    }
})

$BtnAddProxy.Add_Click({
    try {
        $newProxy = Show-AddProxyDialog
        if (-not $newProxy) { return }

        $cfg = Get-ProxyConfig
        $newId = "proxy-" + ($cfg.profiles.Count + 1)
        $newProf = [PSCustomObject]@{
            id = $newId
            name = $newProxy.name
            server = $newProxy.server
            port = $newProxy.port
            username = $newProxy.username
            password = $newProxy.password
            country = "Custom"
            city = "Custom"
            isp = "Custom"
        }
        $cfg.profiles += $newProf
        Save-ProxyConfig $cfg
        Refresh-ProxyProfilesUI

        # Select the newly added profile in combo box
        for ($i = 0; $i -lt $CmbProxyProfiles.Items.Count; $i++) {
            if ($CmbProxyProfiles.Items[$i].Tag -eq $newId) {
                $CmbProxyProfiles.SelectedIndex = $i
                break
            }
        }

        Write-ConsoleLog "Профиль '$($newProxy.name)' ($($newProxy.server):$($newProxy.port)) успешно добавлен!"
    } catch {
        Write-ConsoleLog "[!] Ошибка при добавлении прокси: $($_.Exception.Message)"
    }
})

$BtnListProxy.Add_Click({
    try {
        Show-ProxyListDialog
    } catch {
        Write-ConsoleLog "[!] Ошибка открытия списка прокси: $($_.Exception.Message)"
    }
})

# Auto-refresh timer every 3 seconds
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({
    # Silently refresh status colors and states
    $allVMs = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Gaming-*" }
    foreach ($item in $ListVMs.Items) {
        $vm = $allVMs | Where-Object { $_.Name -eq $item.Name }
        if ($vm) {
            $item.State = $vm.State
            $item.StateText = if ($vm.State -eq 'Running') { "Работает" } else { "Остановлена" }
            $item.StatusColor = if ($vm.State -eq 'Running') { "#22c55e" } else { "#71717a" }
        }
    }
    $ListVMs.Items.Refresh()
    Update-SelectedVMDetails
})
$timer.Start()

# Hide console window once GUI appears
$window.Add_Loaded({
    try {
        $hwnd = [GuiConsoleApp.Win32ConsoleHelper]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            [GuiConsoleApp.Win32ConsoleHelper]::ShowWindow($hwnd, 0) | Out-Null
        }
    } catch {}
})

# Initial Load
Write-ConsoleLog "Запуск консоли Hyper-V Workstation..."
Write-ConsoleLog "Хостовая система: Xeon E5-2696 v3 • GTX 1050 Ti (4GB VRAM)"
Write-ConsoleLog "Выделение на VM: 1024 MB VRAM (250,000,000 единиц GPU-PV)"
Write-ConsoleLog "Разрешение по умолчанию: 1024x768 @ 60 FPS"

Refresh-ProxyProfilesUI
try { 
    Start-ProxyEngine 
    Write-ConsoleLog "Модуль внешней SOCKS5 маршрутизации активен (Kill-Switch • DNS Leak-Free)"
} catch {
    Write-ConsoleLog "[!] Замечание запуска прокси: $($_.Exception.Message)"
}

Refresh-VMList

$window.ShowDialog() | Out-Null
$timer.Stop()
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Произошла ошибка при запуске Hyper-V Workstation:`n`n$($_.Exception.Message)`n`n$($_.ScriptStackTrace)", "Hyper-V Workstation - Ошибка", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}
