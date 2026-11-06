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

try {
    $showWinDef = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();'
    $null = Add-Type -MemberDefinition $showWinDef -Name Win32ConsoleHelper -Namespace GuiConsoleApp -PassThru -ErrorAction SilentlyContinue
} catch {}

try {

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Hyper-V Workstation (GPU-PV Gaming Console)" 
        Height="650" Width="980" 
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
                <Button Name="BtnVMConnect" Content="⚙️ Hyper-V Manager"/>
            </StackPanel>

            <!-- Detail Cards -->
            <Grid Grid.Row="2">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <UniformGrid Grid.Row="0" Columns="4" Margin="0,0,0,16">
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

                <!-- Streaming Settings & Log Panel -->
                <Border Grid.Row="1" Background="#1f1f23" CornerRadius="8" Padding="16" BorderBrush="#2e2e33" BorderThickness="1">
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

function Update-SelectedVMDetails {
    $sel = $ListVMs.SelectedItem
    if (-not $sel) {
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
}

# Events
$ListVMs.Add_SelectionChanged({
    Update-SelectedVMDetails
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

$BtnPairMoonlight.Add_Click({
    $sel = $ListVMs.SelectedItem
    if (-not $sel) { return }

    $pin = [Microsoft.VisualBasic.Interaction]::InputBox("Введите 4-значный PIN код для связывания Moonlight с Sunshine (например, 1234):", "Связывание Moonlight", "1234")
    if ([string]::IsNullOrWhiteSpace($pin)) { return }

    Write-ConsoleLog "Связывание Moonlight с хостом $($sel.IP) с PIN: $pin..."
    
    # 1. Post PIN to Sunshine Web API on guest
    try {
        $pairUrl = "https://$($sel.IP):47990/api/pin"
        $body = @{ pin = $pin } | ConvertTo-Json
        $pairHeader = @{
            Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:admin1234"))
        }

        # Ignore self-signed SSL certificate on guest
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        Invoke-RestMethod -Uri $pairUrl -Method Post -Body $body -ContentType "application/json" -Headers $pairHeader -TimeoutSec 5 -ErrorAction SilentlyContinue
        Write-ConsoleLog "[+] PIN отправлен в Sunshine API."
    } catch {
        Write-ConsoleLog "[!] Не удалось автоматически передать PIN через API (возможно служба еще запускается): $($_.Exception.Message)"
    }

    # 2. Run Moonlight pairing command
    Start-Process -FilePath $MoonlightExe -ArgumentList "pair $($sel.IP) --pin $pin"
    Write-ConsoleLog "Команда сопряжения Moonlight отправлена."
})

$BtnVMConnect.Add_Click({
    $sel = $ListVMs.SelectedItem
    if ($sel) {
        Start-Process "vmconnect.exe" -ArgumentList "localhost `"$($sel.Name)`""
    } else {
        Start-Process "virtmgmt.msc"
    }
})

$BtnCloneVM.Add_Click({
    $allVMs = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "Gaming-*" }
    $nextNum = $allVMs.Count + 1
    $defaultNewName = "Gaming-VM$nextNum"
    $defaultNewIP = "192.168.100.$(10 + $nextNum)"

    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Введите имя новой виртуальной машины:", "Клонирование VM", $defaultNewName)
    if ([string]::IsNullOrWhiteSpace($newName)) { return }

    $newIP = [Microsoft.VisualBasic.Interaction]::InputBox("Введите IP адрес для новой VM ($newName):", "Настройка сетевого IP", $defaultNewIP)
    if ([string]::IsNullOrWhiteSpace($newIP)) { return }

    Write-ConsoleLog "Клонирование новой VM '$newName' с IP $newIP..."
    
    $cloneScript = "C:\Users\server1\Desktop\Hyper-V\scripts\05-Clone-VM.ps1"
    $args = "-NewVMName `"$newName`" -NewGuestIP `"$newIP`""
    
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$cloneScript`" $args" -Wait
    
    Write-ConsoleLog "Клонирование завершено!"
    Refresh-VMList
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
Refresh-VMList

$window.ShowDialog() | Out-Null
$timer.Stop()
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Произошла ошибка при запуске Hyper-V Workstation:`n`n$($_.Exception.Message)`n`n$($_.ScriptStackTrace)", "Hyper-V Workstation - Ошибка", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}
