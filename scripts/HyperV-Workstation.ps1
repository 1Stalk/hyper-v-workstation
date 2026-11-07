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
                    <ListBox.ContextMenu>
                        <ContextMenu Background="#1f1f23" Foreground="#f4f4f5" BorderBrush="#3f3f46">
                            <MenuItem Name="CtxStartVM" Header="▶ Запустить VM"/>
                            <MenuItem Name="CtxStopVM" Header="⏹ Остановить VM"/>
                            <Separator Background="#3f3f46"/>
                            <MenuItem Name="CtxEditVM" Header="⚙️ Настройки оборудования..."/>
                            <MenuItem Name="CtxRenameVM" Header="✏️ Переименовать..."/>
                            <MenuItem Name="CtxRandomizeHWID" Header="🎲 Спуфинг HWID..."/>
                            <Separator Background="#3f3f46"/>
                            <MenuItem Name="CtxOpenStream" Header="🖥️ Открыть окно (Moonlight)"/>
                        </ContextMenu>
                    </ListBox.ContextMenu>
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
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                            <TextBlock Name="TxtVMTitle" Text="Выберите виртуальную машину" FontSize="22" FontWeight="Bold" Foreground="#f4f4f5"/>
                            <Button Name="BtnRenameVM" Content="✏️ Переименовать" Margin="14,0,0,0" Padding="8,3" FontSize="11" Background="#27272a" Foreground="#e4e4e7" BorderBrush="#3f3f46" Cursor="Hand" VerticalAlignment="Center"/>
                        </StackPanel>
                        <TextBlock Name="TxtVMSub" Text="Параметры и потоковое управление" FontSize="13" Foreground="#a1a1aa" Margin="0,4,0,0"/>
                    </StackPanel>
                    <Border Grid.Column="1" Name="BadgeStatus" CornerRadius="12" Padding="12,4" Background="#27272a" VerticalAlignment="Center">
                        <TextBlock Name="TxtStatusBadge" Text="НЕТ ВЫБОРА" FontWeight="Bold" FontSize="11" Foreground="#a1a1aa"/>
                    </Border>
                </Grid>
            </Border>

            <!-- Controls Toolbar -->
            <WrapPanel Grid.Row="1" Margin="0,0,0,16">
                <Button Name="BtnStartVM" Content="▶ Запустить VM" Style="{StaticResource SuccessButton}" Width="130"/>
                <Button Name="BtnStopVM" Content="⏹ Остановить" Style="{StaticResource DangerButton}" Width="120"/>
                <Button Name="BtnOpenStream" Content="🖥️ Открыть окно (Moonlight)" Style="{StaticResource PrimaryButton}" Padding="16,7"/>
                <Button Name="BtnPairMoonlight" Content="🔑 Связать Moonlight"/>
                <Button Name="BtnEditVM" Content="⚙️ Настройки ВМ" Style="{StaticResource PrimaryButton}"/>
                <Button Name="BtnRandomizeHWID" Content="🎲 Спуфинг HWID"/>
                <Button Name="BtnVMConnect" Content="⚙️ Hyper-V Manager"/>
            </WrapPanel>

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
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid Grid.Row="0">
                                <TextBlock Text="ПРОЦЕССОР" FontSize="10" FontWeight="Bold" Foreground="#71717a" VerticalAlignment="Center"/>
                                <Button Name="BtnEditCPU" Content="✏️ Изменить" HorizontalAlignment="Right" Padding="6,2" Margin="0" FontSize="10" Background="#27272a" Foreground="#38bdf8" BorderBrush="#3f3f46" BorderThickness="1" Cursor="Hand" ToolTip="Изменить количество ядер CPU"/>
                            </Grid>
                            <TextBlock Grid.Row="1" Name="TxtCPU" Text="-" FontSize="18" FontWeight="Bold" Foreground="#f4f4f5" Margin="0,4,0,0"/>
                            <TextBlock Grid.Row="2" Text="vCPU (VT-x/EPT)" FontSize="10" Foreground="#a1a1aa"/>
                        </Grid>
                    </Border>

                    <!-- RAM Card -->
                    <Border Background="#1f1f23" CornerRadius="8" Padding="12" Margin="4" BorderBrush="#2e2e33" BorderThickness="1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid Grid.Row="0">
                                <TextBlock Text="ОПЕРАТИВНАЯ ПАМЯТЬ" FontSize="10" FontWeight="Bold" Foreground="#71717a" VerticalAlignment="Center"/>
                                <Button Name="BtnEditRAM" Content="✏️ Изменить" HorizontalAlignment="Right" Padding="6,2" Margin="0" FontSize="10" Background="#27272a" Foreground="#38bdf8" BorderBrush="#3f3f46" BorderThickness="1" Cursor="Hand" ToolTip="Изменить объем оперативной памяти"/>
                            </Grid>
                            <TextBlock Grid.Row="1" Name="TxtRAM" Text="-" FontSize="18" FontWeight="Bold" Foreground="#f4f4f5" Margin="0,4,0,0"/>
                            <TextBlock Grid.Row="2" Text="Статическая ECC" FontSize="10" Foreground="#a1a1aa"/>
                        </Grid>
                    </Border>

                    <!-- GPU VRAM Card -->
                    <Border Background="#1f1f23" CornerRadius="8" Padding="12" Margin="4" BorderBrush="#2e2e33" BorderThickness="1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid Grid.Row="0">
                                <TextBlock Text="GPU-PV ВИДЕОПАМЯТЬ" FontSize="10" FontWeight="Bold" Foreground="#71717a" VerticalAlignment="Center"/>
                                <Button Name="BtnEditVRAM" Content="✏️ Изменить" HorizontalAlignment="Right" Padding="6,2" Margin="0" FontSize="10" Background="#27272a" Foreground="#38bdf8" BorderBrush="#3f3f46" BorderThickness="1" Cursor="Hand" ToolTip="Изменить видеопамять GPU-PV"/>
                            </Grid>
                            <TextBlock Grid.Row="1" Name="TxtVRAM" Text="-" FontSize="18" FontWeight="Bold" Foreground="#38bdf8" Margin="0,4,0,0"/>
                            <TextBlock Grid.Row="2" Text="NVIDIA GTX 1050 Ti" FontSize="10" Foreground="#a1a1aa"/>
                        </Grid>
                    </Border>

                    <!-- Network IP Card -->
                    <Border Background="#1f1f23" CornerRadius="8" Padding="12" Margin="4" BorderBrush="#2e2e33" BorderThickness="1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid Grid.Row="0">
                                <TextBlock Text="IP АДРЕС СЕТИ NAT" FontSize="10" FontWeight="Bold" Foreground="#71717a" VerticalAlignment="Center"/>
                                <Button Name="BtnEditIP" Content="✏️ Изменить" HorizontalAlignment="Right" Padding="6,2" Margin="0" FontSize="10" Background="#27272a" Foreground="#4ade80" BorderBrush="#3f3f46" BorderThickness="1" Cursor="Hand" ToolTip="Изменить статический IP адрес NAT"/>
                            </Grid>
                            <TextBlock Grid.Row="1" Name="TxtIP" Text="-" FontSize="16" FontWeight="Bold" Foreground="#4ade80" Margin="0,4,0,0"/>
                            <TextBlock Grid.Row="2" Text="VM-Gaming-Switch" FontSize="10" Foreground="#a1a1aa"/>
                        </Grid>
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
$BtnEditVM        = $window.FindName("BtnEditVM")
$BtnRenameVM      = $window.FindName("BtnRenameVM")
$BtnEditCPU       = $window.FindName("BtnEditCPU")
$BtnEditRAM       = $window.FindName("BtnEditRAM")
$BtnEditVRAM      = $window.FindName("BtnEditVRAM")
$BtnEditIP        = $window.FindName("BtnEditIP")

# Context Menu Items
$CtxStartVM       = $window.FindName("CtxStartVM")
$CtxStopVM        = $window.FindName("CtxStopVM")
$CtxEditVM        = $window.FindName("CtxEditVM")
$CtxRenameVM      = $window.FindName("CtxRenameVM")
$CtxRandomizeHWID = $window.FindName("CtxRandomizeHWID")
$CtxOpenStream    = $window.FindName("CtxOpenStream")

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
    # 1. Try query live IP from Hyper-V NetworkAdapters first if VM is running
    try {
        $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
        if ($vm -and $vm.State -eq 'Running') {
            $liveIps = @($vm.NetworkAdapters.IPAddresses | Where-Object { 
                $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notlike '169.254.*' -and $_ -ne '0.0.0.0'
            })
            # Prioritize 192.168.100.* NAT IPs
            $natIp = @($liveIps | Where-Object { $_ -like '192.168.100.*' })
            if ($natIp -and $natIp.Count -gt 0) {
                $candidate = [string]$natIp[0]
                if ($candidate -match '^\d+\.\d+\.\d+\.\d+$' -and $candidate.Length -gt 6) {
                    return $candidate
                }
            }
            if ($liveIps -and $liveIps.Count -gt 0) {
                $candidate = [string]$liveIps[0]
                if ($candidate -match '^\d+\.\d+\.\d+\.\d+$' -and $candidate.Length -gt 6) {
                    return $candidate
                }
            }
        }
    } catch {}

    # 2. Check if VM has static IP mapped in proxy config assignments
    if (Get-Command Get-ProxyConfig -ErrorAction SilentlyContinue) {
        try {
            $cfg = Get-ProxyConfig
            if ($cfg -and $cfg.assignments) {
                $assign = $cfg.assignments.$vmName
                if ($assign -and $assign.ip) {
                    $val = [string]$assign.ip
                    if ($val -match '^\d+\.\d+\.\d+\.\d+$' -and $val.Length -gt 6) {
                        return $val
                    }
                }
            }
        } catch {}
    }

    # 3. Check if VM has static IP mapped in table
    $ipMap = @{
        "Gaming-VM1" = "192.168.100.11"
        "Gaming-VM2" = "192.168.100.12"
        "Gaming-VM3" = "192.168.100.13"
        "Gaming-VM4" = "192.168.100.14"
        "Gaming-VM5" = "192.168.100.15"
        "Gaming-VM6" = "192.168.100.16"
        "AM1"        = "192.168.100.11"
        "AM2"        = "192.168.100.12"
        "AM3"        = "192.168.100.13"
        "AM4"        = "192.168.100.14"
        "AM5"        = "192.168.100.15"
        "AM6"        = "192.168.100.16"
    }
    if ($ipMap.ContainsKey($vmName)) {
        return [string]$ipMap[$vmName]
    }
    if ($Script:VMIPMap -and $Script:VMIPMap.ContainsKey($vmName)) {
        $val = [string]$Script:VMIPMap[$vmName]
        if ($val -match '^\d+\.\d+\.\d+\.\d+$' -and $val.Length -gt 6) {
            return $val
        }
    }
    
    # 4. Fallback from VM name number Gaming-VM<N> or AM<N>
    if ($vmName -match '(?:Gaming-VM|AM)(\d+)$') {
        return "192.168.100.$(10 + [int]$Matches[1])"
    }

    return "192.168.100.11"
}

function Refresh-VMList {
    $currentSelectionName = $null
    if ($ListVMs.SelectedItem) {
        $currentSelectionName = $ListVMs.SelectedItem.Name
    }

    $cfg = if (Get-Command Get-ProxyConfig -ErrorAction SilentlyContinue) { Get-ProxyConfig } else { $null }
    $assignedNames = @()
    if ($cfg -and $cfg.assignments) {
        $assignedNames = @($cfg.assignments.PSObject.Properties.Name)
    }

    $allVMs = Get-VM -ErrorAction SilentlyContinue | Where-Object { 
        $_.Name -like "Gaming-*" -or 
        $_.Name -in $assignedNames -or
        (Get-VMNetworkAdapter -VMName $_.Name -ErrorAction SilentlyContinue | Where-Object { $_.SwitchName -eq "VM-Gaming-Switch" })
    }
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
    $ipDisplay = if ($sel.IP -and $sel.IP -ne "1" -and $sel.IP -ne "-" -and $sel.IP.Length -gt 6) { $sel.IP } else { Get-VMIPAddress $sel.Name }
    $sel.IP = $ipDisplay
    $TxtIP.Text = $ipDisplay

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
    $guestIp = if ($sel.IP -and $sel.IP -ne "1" -and $sel.IP -ne "-" -and $sel.IP.Length -gt 6) { $sel.IP } else { Get-VMIPAddress $sel.Name }
    $sel.IP = $guestIp

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

function Show-RenameVMDialog {
    param([string]$targetVMName)
    try {
        if (-not $targetVMName) { return $null }

        [xml]$renameXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Переименование виртуальной машины" Height="260" Width="430"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#18181b" Foreground="#f4f4f5" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#27272a"/>
            <Setter Property="Foreground" Value="#ffffff"/>
            <Setter Property="BorderBrush" Value="#3f3f46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="14"/>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="✏️ Переименование виртуальной машины" FontWeight="Bold" FontSize="15" Foreground="#f4f4f5" Margin="0,0,0,6"/>
        <TextBlock Grid.Row="1" Text="Текущее имя: $targetVMName" FontSize="12" Foreground="#a1a1aa" Margin="0,0,0,10"/>
        
        <StackPanel Grid.Row="2" Margin="0,0,0,6">
            <TextBlock Text="Новое имя виртуальной машины:" FontSize="12" FontWeight="SemiBold" Foreground="#e4e4e7" Margin="0,0,0,4"/>
            <TextBox Name="TxtNewVMName" Text="$targetVMName"/>
        </StackPanel>

        <TextBlock Grid.Row="3" Name="TxtRenameStatus" Text="Имя будет обновлено в Hyper-V, proxy-profiles.json и гостевой системе." FontSize="11" Foreground="#71717a" TextWrapping="Wrap" Margin="0,2,0,10"/>

        <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Bottom">
            <Button Name="BtnDoRename" Content="✏️ Переименовать" IsDefault="True" Margin="0,0,8,0" Padding="16,6" Background="#2563eb" Foreground="#ffffff" BorderBrush="#3b82f6" FontWeight="Bold" Cursor="Hand"/>
            <Button Name="BtnCancelRename" Content="Отмена" IsCancel="True" Padding="14,6" Background="#27272a" Foreground="#a1a1aa" BorderBrush="#3f3f46" Cursor="Hand"/>
        </StackPanel>
    </Grid>
</Window>
"@
        $reader = [System.Xml.XmlNodeReader]::new($renameXaml)
        $dlg = [Windows.Markup.XamlReader]::Load($reader)
        $dlg.Owner = $window

        $TxtNewVMName    = $dlg.FindName("TxtNewVMName")
        $TxtRenameStatus = $dlg.FindName("TxtRenameStatus")
        $BtnDoRename     = $dlg.FindName("BtnDoRename")
        $BtnCancelRename = $dlg.FindName("BtnCancelRename")

        $dlg.Add_Loaded({
            $TxtNewVMName.Focus() | Out-Null
            $TxtNewVMName.SelectAll()
        })

        $script:renameResult = $null

        $BtnDoRename.Add_Click({
            $newName = $TxtNewVMName.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($newName)) {
                $TxtRenameStatus.Text = "⚠️ Имя ВМ не может быть пустым."
                $TxtRenameStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f59e0b")
                return
            }
            if ($newName -match '[\\/:*?"<>|]') {
                $TxtRenameStatus.Text = "⚠️ Недопустимые символы в имени (\ / : * ? `"` < > |)."
                $TxtRenameStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ef4444")
                return
            }
            if ($newName -ne $targetVMName) {
                $ex = Get-VM -Name $newName -ErrorAction SilentlyContinue
                if ($ex) {
                    $TxtRenameStatus.Text = "⚠️ ВМ с именем '$newName' уже существует."
                    $TxtRenameStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ef4444")
                    return
                }
            }

            $script:renameResult = $newName
            $dlg.DialogResult = $true
            $dlg.Close()
        })

        $BtnCancelRename.Add_Click({
            $dlg.DialogResult = $false
            $dlg.Close()
        })

        $res = $dlg.ShowDialog()
        if ($res -eq $true -and $script:renameResult) {
            return $script:renameResult
        }
    } catch {
        Write-ConsoleLog "[!] Ошибка окна переименования: $($_.Exception.Message)"
    }
    return $null
}

function Show-VMSettingsDialog {
    param(
        [Parameter(Mandatory=$true)][string]$targetVMName,
        [string]$focusParam = $null
    )
    try {
        $vm = Get-VM -Name $targetVMName -ErrorAction SilentlyContinue
        if (-not $vm) {
            [System.Windows.MessageBox]::Show("Виртуальная машина '$targetVMName' не найдена.", "Ошибка", "OK", "Error")
            return
        }

        $curCPU = $vm.ProcessorCount
        $curRAMGB = [math]::Round($vm.MemoryStartup / 1GB, 1)

        $gpu = Get-VMGpuPartitionAdapter -VMName $targetVMName -ErrorAction SilentlyContinue
        $curVRAMMB = 0
        if ($gpu -and $gpu.MaxPartitionVRAM) {
            $curVRAMMB = [math]::Round(($gpu.MaxPartitionVRAM / 1000000000) * 4096)
        }

        $curIP = Get-VMIPAddress $targetVMName
        $isVMRunning = ($vm.State -eq 'Running')

        $stateWarningVisibility = if ($isVMRunning) { "Visible" } else { "Collapsed" }

        [xml]$settingsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Настройки виртуальной машины - $targetVMName" Height="650" Width="520"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#18181b" Foreground="#f4f4f5" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#27272a"/>
            <Setter Property="Foreground" Value="#ffffff"/>
            <Setter Property="BorderBrush" Value="#3f3f46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#a1a1aa"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Margin" Value="0,0,0,3"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Foreground" Value="#09090b"/>
            <Setter Property="Background" Value="#ffffff"/>
            <Setter Property="BorderBrush" Value="#71717a"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="6,4"/>
        </Style>
        <Style TargetType="ComboBoxItem">
            <Setter Property="Foreground" Value="#09090b"/>
            <Setter Property="Background" Value="#ffffff"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="6,4"/>
        </Style>
    </Window.Resources>
    <Grid Margin="22">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Grid Grid.Row="0" Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
                <TextBlock Text="⚙️ Настройки виртуальной машины" FontSize="16" FontWeight="Bold" Foreground="#ffffff"/>
                <TextBlock Text="Конфигурация аппаратных ресурсов и сети NAT" FontSize="11" Foreground="#71717a" Margin="0,2,0,0"/>
            </StackPanel>
            <Border Grid.Column="1" Name="BadgeDlgStatus" CornerRadius="8" Padding="10,4" Background="#27272a" VerticalAlignment="Center">
                <TextBlock Name="TxtDlgState" Text="ОСТАНОВЛЕНА" FontSize="10" FontWeight="Bold" Foreground="#a1a1aa"/>
            </Border>
        </Grid>

        <!-- Warning panel for running VM -->
        <Border Grid.Row="1" Name="PnlRunningWarning" Visibility="$stateWarningVisibility" Background="#2a1f10" BorderBrush="#f59e0b" BorderThickness="1" CornerRadius="6" Padding="10,8" Margin="0,0,0,10">
            <TextBlock Text="⚠️ Внимание: ВМ работает. Для изменения ядер CPU, памяти RAM и видеопамяти GPU-PV виртуальная машина должна быть выключена. При сохранении будет предложено автоматически остановить ВМ." FontSize="11" Foreground="#fbbf24" TextWrapping="Wrap"/>
        </Border>

        <!-- Field 1: VM Name -->
        <StackPanel Grid.Row="2" Margin="0,0,0,10">
            <TextBlock Text="Имя виртуальной машины:" FontWeight="SemiBold" Foreground="#e4e4e7"/>
            <TextBox Name="TxtDlgVMName" Text="$targetVMName"/>
            <TextBlock Text="Имя в Hyper-V, сетевых маршрутах и файле C:\Setup\vmname.txt" FontSize="11" Foreground="#71717a"/>
        </StackPanel>

        <!-- Field 2: CPU Cores -->
        <StackPanel Grid.Row="3" Margin="0,0,0,10">
            <TextBlock Text="Процессор (Ядра vCPU):" FontWeight="SemiBold" Foreground="#e4e4e7"/>
            <ComboBox Name="CmbDlgCPU">
                <ComboBoxItem Content="1 ядро" Tag="1"/>
                <ComboBoxItem Content="2 ядра" Tag="2"/>
                <ComboBoxItem Content="4 ядра (Рекомендуется)" Tag="4"/>
                <ComboBoxItem Content="6 ядер" Tag="6"/>
                <ComboBoxItem Content="8 ядер" Tag="8"/>
                <ComboBoxItem Content="12 ядер" Tag="12"/>
                <ComboBoxItem Content="16 ядер" Tag="16"/>
                <ComboBoxItem Content="24 ядра" Tag="24"/>
                <ComboBoxItem Content="32 ядра" Tag="32"/>
                <ComboBoxItem Content="36 ядер (Максимум хоста)" Tag="36"/>
            </ComboBox>
            <TextBlock Text="Виртуальные процессоры Xeon E5-2696 v3 с поддержкой VT-x/EPT" FontSize="11" Foreground="#71717a"/>
        </StackPanel>

        <!-- Field 3: RAM Memory -->
        <StackPanel Grid.Row="4" Margin="0,0,0,10">
            <TextBlock Text="Оперативная память (RAM, ГБ):" FontWeight="SemiBold" Foreground="#e4e4e7"/>
            <ComboBox Name="CmbDlgRAM">
                <ComboBoxItem Content="2 ГБ" Tag="2"/>
                <ComboBoxItem Content="4 ГБ" Tag="4"/>
                <ComboBoxItem Content="6 ГБ" Tag="6"/>
                <ComboBoxItem Content="8 ГБ (Стандарт)" Tag="8"/>
                <ComboBoxItem Content="12 ГБ" Tag="12"/>
                <ComboBoxItem Content="16 ГБ (Рекомендуется)" Tag="16"/>
                <ComboBoxItem Content="24 ГБ" Tag="24"/>
                <ComboBoxItem Content="32 ГБ" Tag="32"/>
                <ComboBoxItem Content="48 ГБ" Tag="48"/>
                <ComboBoxItem Content="64 ГБ (Максимум хоста)" Tag="64"/>
            </ComboBox>
            <TextBlock Text="Статическая ECC память с гарантированным выделением" FontSize="11" Foreground="#71717a"/>
        </StackPanel>

        <!-- Field 4: GPU-PV Video Memory -->
        <StackPanel Grid.Row="5" Margin="0,0,0,10">
            <TextBlock Text="GPU-PV Видеопамять (NVIDIA GTX 1050 Ti):" FontWeight="SemiBold" Foreground="#e4e4e7"/>
            <ComboBox Name="CmbDlgVRAM">
                <ComboBoxItem Content="0 MB (Без GPU адаптера)" Tag="0"/>
                <ComboBoxItem Content="512 MB VRAM (125M единиц • 1/8 GPU)" Tag="512"/>
                <ComboBoxItem Content="1024 MB VRAM (250M единиц • По умолчанию)" Tag="1024"/>
                <ComboBoxItem Content="1536 MB VRAM (375M единиц • 3/8 GPU)" Tag="1536"/>
                <ComboBoxItem Content="2048 MB VRAM (500M единиц • 1/2 GPU)" Tag="2048"/>
                <ComboBoxItem Content="3072 MB VRAM (750M единиц • 3/4 GPU)" Tag="3072"/>
                <ComboBoxItem Content="4096 MB VRAM (1000M единиц • Полный GPU)" Tag="4096"/>
            </ComboBox>
            <TextBlock Text="Аппаратное деление видеопамяти через Hyper-V GPU Partitioning" FontSize="11" Foreground="#71717a"/>
        </StackPanel>

        <!-- Field 5: NAT Static IP -->
        <StackPanel Grid.Row="6" Margin="0,0,0,10">
            <TextBlock Text="Статический IP адрес NAT (Сеть 192.168.100.x):" FontWeight="SemiBold" Foreground="#e4e4e7"/>
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBox Name="TxtDlgIP" Text="$curIP" Margin="0,0,8,0"/>
                <Button Grid.Column="1" Name="BtnDlgSuggestIP" Content="🎲 Свободный IP" Padding="12,5" Background="#27272a" Foreground="#e4e4e7" BorderBrush="#3f3f46" Cursor="Hand" FontWeight="SemiBold"/>
            </Grid>
            <TextBlock Text="Шлюз 192.168.100.1 • Синхронизируется с C:\Setup\ip.txt и правилами Sing-box" FontSize="11" Foreground="#71717a"/>
        </StackPanel>

        <!-- Status & Action Buttons -->
        <Grid Grid.Row="7" VerticalAlignment="Bottom">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <TextBlock Grid.Row="0" Name="TxtSettingsStatus" Text="" FontSize="11" Foreground="#71717a" TextWrapping="Wrap" Margin="0,0,0,8"/>

            <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right">
                <Button Name="BtnSettingsSave" Content="💾 Сохранить изменения" IsDefault="True" Margin="0,0,8,0" Padding="16,7" Background="#2563eb" Foreground="#ffffff" BorderBrush="#3b82f6" FontWeight="Bold" Cursor="Hand"/>
                <Button Name="BtnSettingsCancel" Content="Отмена" IsCancel="True" Padding="14,7" Background="#27272a" Foreground="#a1a1aa" BorderBrush="#3f3f46" Cursor="Hand"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@
        $reader = [System.Xml.XmlNodeReader]::new($settingsXaml)
        $dlg = [Windows.Markup.XamlReader]::Load($reader)
        $dlg.Owner = $window

        $TxtDlgVMName      = $dlg.FindName("TxtDlgVMName")
        $CmbDlgCPU         = $dlg.FindName("CmbDlgCPU")
        $CmbDlgRAM         = $dlg.FindName("CmbDlgRAM")
        $CmbDlgVRAM        = $dlg.FindName("CmbDlgVRAM")
        $TxtDlgIP          = $dlg.FindName("TxtDlgIP")
        $BtnDlgSuggestIP   = $dlg.FindName("BtnDlgSuggestIP")
        $TxtSettingsStatus = $dlg.FindName("TxtSettingsStatus")
        $BtnSettingsSave   = $dlg.FindName("BtnSettingsSave")
        $BtnSettingsCancel = $dlg.FindName("BtnSettingsCancel")
        $BadgeDlgStatus    = $dlg.FindName("BadgeDlgStatus")
        $TxtDlgState       = $dlg.FindName("TxtDlgState")

        if ($isVMRunning) {
            $BadgeDlgStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#15803d")
            $TxtDlgState.Text = "РАБОТАЕТ"
            $TxtDlgState.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#86efac")
        } else {
            $BadgeDlgStatus.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3f3f46")
            $TxtDlgState.Text = "ОСТАНОВЛЕНА"
            $TxtDlgState.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#d4d4d8")
        }

        # Initialize CPU selection
        $cpuMatched = $false
        for ($i = 0; $i -lt $CmbDlgCPU.Items.Count; $i++) {
            if ([int]$CmbDlgCPU.Items[$i].Tag -eq $curCPU) {
                $CmbDlgCPU.SelectedIndex = $i
                $cpuMatched = $true
                break
            }
        }
        if (-not $cpuMatched) {
            $cItem = New-Object System.Windows.Controls.ComboBoxItem
            $cItem.Content = "$curCPU ядер (Текущее)"
            $cItem.Tag = $curCPU
            $idx = $CmbDlgCPU.Items.Add($cItem)
            $CmbDlgCPU.SelectedIndex = $idx
        }

        # Initialize RAM selection
        $ramMatched = $false
        $targetRAMVal = [int][math]::Round($curRAMGB)
        for ($i = 0; $i -lt $CmbDlgRAM.Items.Count; $i++) {
            if ([int]$CmbDlgRAM.Items[$i].Tag -eq $targetRAMVal) {
                $CmbDlgRAM.SelectedIndex = $i
                $ramMatched = $true
                break
            }
        }
        if (-not $ramMatched) {
            $rItem = New-Object System.Windows.Controls.ComboBoxItem
            $rItem.Content = "$curRAMGB ГБ (Текущее)"
            $rItem.Tag = $targetRAMVal
            $idx = $CmbDlgRAM.Items.Add($rItem)
            $CmbDlgRAM.SelectedIndex = $idx
        }

        # Initialize VRAM selection
        $vramMatched = $false
        for ($i = 0; $i -lt $CmbDlgVRAM.Items.Count; $i++) {
            if ([int]$CmbDlgVRAM.Items[$i].Tag -eq $curVRAMMB) {
                $CmbDlgVRAM.SelectedIndex = $i
                $vramMatched = $true
                break
            }
        }
        if (-not $vramMatched) {
            $vItem = New-Object System.Windows.Controls.ComboBoxItem
            $vItem.Content = "$curVRAMMB MB VRAM (Текущее)"
            $vItem.Tag = $curVRAMMB
            $idx = $CmbDlgVRAM.Items.Add($vItem)
            $CmbDlgVRAM.SelectedIndex = $idx
        }

        # Set focus when dialog finishes loading
        $dlg.Add_Loaded({
            if ($focusParam -eq "CPU") { $CmbDlgCPU.Focus() | Out-Null }
            elseif ($focusParam -eq "RAM") { $CmbDlgRAM.Focus() | Out-Null }
            elseif ($focusParam -eq "VRAM") { $CmbDlgVRAM.Focus() | Out-Null }
            elseif ($focusParam -eq "IP") { $TxtDlgIP.Focus() | Out-Null; $TxtDlgIP.SelectAll() }
            elseif ($focusParam -eq "Name") { $TxtDlgVMName.Focus() | Out-Null; $TxtDlgVMName.SelectAll() }
            else { $TxtDlgVMName.Focus() | Out-Null; $TxtDlgVMName.SelectAll() }
        })

        # Suggest free IP button handler
        $BtnDlgSuggestIP.Add_Click({
            try {
                $usedIps = @(1)
                $cfg = Get-ProxyConfig
                if ($cfg -and $cfg.assignments) {
                    foreach ($prop in $cfg.assignments.PSObject.Properties) {
                        if ($prop.Value -and $prop.Value.ip -match '^192\.168\.100\.(\d+)$') {
                            $usedIps += [int]$Matches[1]
                        }
                    }
                }
                $allVMs = Get-VM -ErrorAction SilentlyContinue
                foreach ($v in $allVMs) {
                    $ip = Get-VMIPAddress $v.Name
                    if ($ip -match '^192\.168\.100\.(\d+)$') { $usedIps += [int]$Matches[1] }
                }
                $cand = 11
                while ($cand -in $usedIps) { $cand++ }
                if ($cand -le 254) {
                    $TxtDlgIP.Text = "192.168.100.$cand"
                    $TxtSettingsStatus.Text = "💡 Выбран свободный IP: 192.168.100.$cand"
                    $TxtSettingsStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38bdf8")
                }
            } catch {
                $TxtSettingsStatus.Text = "⚠️ Ошибка поиска IP: $($_.Exception.Message)"
                $TxtSettingsStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f59e0b")
            }
        })

        # Save Settings Handler
        $BtnSettingsSave.Add_Click({
            $newName = if ($TxtDlgVMName.Text) { $TxtDlgVMName.Text.Trim() } else { "" }
            $newCPU = if ($CmbDlgCPU.SelectedItem) { [int]$CmbDlgCPU.SelectedItem.Tag } else { $curCPU }
            $newRAMGB = if ($CmbDlgRAM.SelectedItem) { [int]$CmbDlgRAM.SelectedItem.Tag } else { [int][math]::Round($curRAMGB) }
            $newVRAMMB = if ($CmbDlgVRAM.SelectedItem) { [int]$CmbDlgVRAM.SelectedItem.Tag } else { $curVRAMMB }
            $newIP = if ($TxtDlgIP.Text) { $TxtDlgIP.Text.Trim() } else { "" }

            # 1. Validation
            if ([string]::IsNullOrWhiteSpace($newName)) {
                $TxtSettingsStatus.Text = "⚠️ Имя ВМ не может быть пустым."
                $TxtSettingsStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ef4444")
                return
            }
            if ($newName -match '[\\/:*?"<>|]') {
                $TxtSettingsStatus.Text = "⚠️ Недопустимые символы в имени ВМ."
                $TxtSettingsStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ef4444")
                return
            }
            if ($newName -ne $targetVMName) {
                $ex = Get-VM -Name $newName -ErrorAction SilentlyContinue
                if ($ex) {
                    $TxtSettingsStatus.Text = "⚠️ ВМ с именем '$newName' уже существует."
                    $TxtSettingsStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ef4444")
                    return
                }
            }

            if ($newIP -notmatch '^192\.168\.100\.(\d+)$') {
                $TxtSettingsStatus.Text = "⚠️ IP адрес должен быть в сети 192.168.100.x"
                $TxtSettingsStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ef4444")
                return
            }
            $octet = [int]$Matches[1]
            if ($octet -lt 2 -or $octet -gt 254) {
                $TxtSettingsStatus.Text = "⚠️ Октет IP адреса ($octet) должен быть в диапазоне 2 - 254."
                $TxtSettingsStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ef4444")
                return
            }

            if ($newIP -ne $curIP) {
                $cfg = Get-ProxyConfig
                $otherMap = @{}
                if ($cfg -and $cfg.assignments) {
                    foreach ($prop in $cfg.assignments.PSObject.Properties) {
                        if ($prop.Name -ne $targetVMName -and $prop.Value -and $prop.Value.ip) {
                            $otherMap[$prop.Value.ip] = $prop.Name
                        }
                    }
                }
                $allVMs = Get-VM -ErrorAction SilentlyContinue
                foreach ($v in $allVMs) {
                    if ($v.Name -ne $targetVMName) {
                        $otherIp = Get-VMIPAddress $v.Name
                        if ($otherIp -and -not $otherMap.ContainsKey($otherIp)) {
                            $otherMap[$otherIp] = $v.Name
                        }
                    }
                }
                if ($otherMap.ContainsKey($newIP)) {
                    $TxtSettingsStatus.Text = "⚠️ IP адрес '$newIP' уже назначен ВМ '$($otherMap[$newIP])'."
                    $TxtSettingsStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ef4444")
                    return
                }
            }

            # 2. Check changes
            $hwChanged = ($newCPU -ne $curCPU -or $newRAMGB -ne [int][math]::Round($curRAMGB) -or $newVRAMMB -ne $curVRAMMB)
            $ipChanged = ($newIP -ne $curIP)
            $nameChanged = ($newName -ne $targetVMName)

            if (-not $hwChanged -and -not $ipChanged -and -not $nameChanged) {
                $dlg.DialogResult = $true
                $dlg.Close()
                return
            }

            # 3. Check VM Running status for Hardware changes
            $liveVM = Get-VM -Name $targetVMName
            if ($hwChanged -and $liveVM.State -ne 'Off') {
                $ans = [System.Windows.MessageBox]::Show("Виртуальная машина '$targetVMName' работает.`n`nДля изменения ядер CPU ($newCPU), памяти RAM ($newRAMGB ГБ) и видеопамяти GPU-PV ($newVRAMMB MB) виртуальная машина должна быть выключена.`n`nВыключить ВМ сейчас и применить новые параметры?", "Требуется остановка ВМ", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
                if ($ans -ne [System.Windows.MessageBoxResult]::Yes) {
                    $TxtSettingsStatus.Text = "⚠️ Применение отменено: ВМ должна быть выключена."
                    $TxtSettingsStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#f59e0b")
                    return
                }

                $TxtSettingsStatus.Text = "⏳ Остановка виртуальной машины '$targetVMName'..."
                $TxtSettingsStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38bdf8")
                Write-ConsoleLog "Остановка ВМ '$targetVMName' перед изменением оборудования..."
                Stop-VM -Name $targetVMName -TurnOff -Force -ErrorAction Stop
                $timeout = 20
                while ((Get-VM -Name $targetVMName).State -ne 'Off' -and $timeout -gt 0) {
                    Start-Sleep -Seconds 1
                    $timeout--
                }
                if ((Get-VM -Name $targetVMName).State -ne 'Off') {
                    throw "Не удалось остановить виртуальную машину '$targetVMName' перед изменением оборудования."
                }
            }

            $TxtSettingsStatus.Text = "⏳ Применение настроек..."
            $TxtSettingsStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38bdf8")

            try {
                # 4. Apply Hardware (only changed components)
                if ($hwChanged) {
                    $applyCPU = if ($newCPU -ne $curCPU) { $newCPU } else { 0 }
                    $applyRAM = if ($newRAMGB -ne [int][math]::Round($curRAMGB)) { ($newRAMGB * 1GB) } else { 0 }
                    $applyVRAM = if ($newVRAMMB -ne $curVRAMMB) { $newVRAMMB } else { -1 }
                    Set-VMHardwareConfig -VMName $targetVMName -CPUCount $applyCPU -RAMBytes $applyRAM -VRAMMB $applyVRAM -ForceStop:$false
                    Write-ConsoleLog "Параметры оборудования для '$targetVMName' обновлены: $newCPU vCPU, $newRAMGB ГБ RAM, $newVRAMMB MB VRAM."
                }

                # 5. Apply IP
                if ($ipChanged) {
                    Set-VMStaticIP -VMName $targetVMName -IPAddress $newIP
                    Write-ConsoleLog "IP адрес для '$targetVMName' изменен на $newIP."
                }

                # 6. Apply Rename
                $effectiveName = $targetVMName
                if ($nameChanged) {
                    Rename-GamingVM -OldVMName $targetVMName -NewVMName $newName
                    $effectiveName = $newName
                    Write-ConsoleLog "Виртуальная машина '$targetVMName' переименована в '$newName'."
                }

                $script:modifiedVMTarget = $effectiveName
                $dlg.DialogResult = $true
                $dlg.Close()
            } catch {
                $TxtSettingsStatus.Text = "🔴 Ошибка сохранения: $($_.Exception.Message)"
                $TxtSettingsStatus.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ef4444")
                Write-ConsoleLog "[!] Ошибка сохранения параметров: $($_.Exception.Message)"
            }
        })

        $BtnSettingsCancel.Add_Click({
            $dlg.DialogResult = $false
            $dlg.Close()
        })

        $script:modifiedVMTarget = $null
        $res = $dlg.ShowDialog()
        Refresh-VMList
        $selName = if ($script:modifiedVMTarget) { $script:modifiedVMTarget } else { $targetVMName }
        $newItem = $ListVMs.Items | Where-Object { $_.Name -eq $selName } | Select-Object -First 1
        if ($newItem) {
            $ListVMs.SelectedItem = $newItem
        }
        Refresh-ProxyProfilesUI
        Update-SelectedVMDetails -ForceControlsUpdate $true
    } catch {
        Write-ConsoleLog "[!] Ошибка окна настроек ВМ: $($_.Exception.Message)"
    }
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

        $targetIp = if ($sel.IP -and $sel.IP -ne "1" -and $sel.IP -ne "-" -and $sel.IP.Length -gt 6) { $sel.IP } else { Get-VMIPAddress $sel.Name }
        $sel.IP = $targetIp

        $pin = Show-PairMoonlightDialog -vmIp $targetIp -vmName $sel.Name
        if ([string]::IsNullOrWhiteSpace($pin)) { return }

        Write-ConsoleLog "Связывание Moonlight с хостом $targetIp с PIN: $pin..."
        
        # 1. Start Moonlight pairing process in background
        try {
            Start-Process -FilePath $MoonlightExe -ArgumentList "pair $targetIp --pin $pin"
            Start-Sleep -Seconds 2
        } catch {
            Write-ConsoleLog "[!] Ошибка запуска Moonlight: $($_.Exception.Message)"
        }

        # 2. Submit PIN to Sunshine Web API on guest
        try {
            $pairUrl = "https://${targetIp}:47990/api/pin"
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
        Write-Host "    -> Generated unique ComputerName and Hostname: $VMName" -ForegroundColor Gray
    } catch {
        Write-ConsoleLog "[!] Ошибка при спуфинге HWID: $($_.Exception.Message)"
    }
})

$BtnEditVM.Add_Click({
    try {
        $sel = $ListVMs.SelectedItem
        if (-not $sel) {
            [System.Windows.MessageBox]::Show("Пожалуйста, выберите виртуальную машину для изменения настроек.", "Настройки ВМ", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }
        Show-VMSettingsDialog -targetVMName $sel.Name
    } catch {
        Write-ConsoleLog "[!] Ошибка вызова настроек ВМ: $($_.Exception.Message)"
    }
})

$BtnRenameVM.Add_Click({
    try {
        $sel = $ListVMs.SelectedItem
        if (-not $sel) {
            [System.Windows.MessageBox]::Show("Пожалуйста, выберите виртуальную машину для переименования.", "Переименование ВМ", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }
        $newName = Show-RenameVMDialog -targetVMName $sel.Name
        if ($newName -and $newName -ne $sel.Name) {
            Write-ConsoleLog "Переименование виртуальной машины '$($sel.Name)' в '$newName'..."
            Rename-GamingVM -OldVMName $sel.Name -NewVMName $newName
            Write-ConsoleLog "Виртуальная машина '$($sel.Name)' успешно переименована в '$newName'!"
            Refresh-VMList
            $newItem = $ListVMs.Items | Where-Object { $_.Name -eq $newName } | Select-Object -First 1
            if ($newItem) {
                $ListVMs.SelectedItem = $newItem
            }
            Refresh-ProxyProfilesUI
            Update-SelectedVMDetails -ForceControlsUpdate $true
        }
    } catch {
        Write-ConsoleLog "[!] Ошибка переименования ВМ: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Ошибка переименования ВМ:`n$($_.Exception.Message)", "Ошибка", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
})

# Right-click item selection handler for ContextMenu
$ListVMs.Add_PreviewMouseRightButtonDown({
    param($sender, $e)
    try {
        $pt = $e.GetPosition($ListVMs)
        $hit = [System.Windows.Media.VisualTreeHelper]::HitTest($ListVMs, $pt)
        if ($hit -and $hit.VisualHit) {
            $elem = $hit.VisualHit
            while ($elem -and $elem -ne $ListVMs) {
                if ($elem -is [System.Windows.Controls.ListBoxItem]) {
                    if ($elem.DataContext) {
                        $ListVMs.SelectedItem = $elem.DataContext
                    }
                    break
                }
                $elem = [System.Windows.Media.VisualTreeHelper]::GetParent($elem)
            }
        }
    } catch {}
})

$BtnEditCPU.Add_Click({
    $sel = $ListVMs.SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Пожалуйста, выберите виртуальную машину для изменения параметров.", "Настройки ВМ", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }
    Show-VMSettingsDialog -targetVMName $sel.Name -focusParam "CPU"
})

$BtnEditRAM.Add_Click({
    $sel = $ListVMs.SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Пожалуйста, выберите виртуальную машину для изменения параметров.", "Настройки ВМ", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }
    Show-VMSettingsDialog -targetVMName $sel.Name -focusParam "RAM"
})

$BtnEditVRAM.Add_Click({
    $sel = $ListVMs.SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Пожалуйста, выберите виртуальную машину для изменения параметров.", "Настройки ВМ", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }
    Show-VMSettingsDialog -targetVMName $sel.Name -focusParam "VRAM"
})

$BtnEditIP.Add_Click({
    $sel = $ListVMs.SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Пожалуйста, выберите виртуальную машину для изменения параметров.", "Настройки ВМ", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }
    Show-VMSettingsDialog -targetVMName $sel.Name -focusParam "IP"
})

# Context Menu Events
if ($CtxStartVM) {
    $CtxStartVM.Add_Click({
        $sel = $ListVMs.SelectedItem
        if ($sel) { $BtnStartVM.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
    })
}
if ($CtxStopVM) {
    $CtxStopVM.Add_Click({
        $sel = $ListVMs.SelectedItem
        if ($sel) { $BtnStopVM.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
    })
}
if ($CtxEditVM) {
    $CtxEditVM.Add_Click({
        $sel = $ListVMs.SelectedItem
        if ($sel) { Show-VMSettingsDialog -targetVMName $sel.Name }
    })
}
if ($CtxRenameVM) {
    $CtxRenameVM.Add_Click({
        $sel = $ListVMs.SelectedItem
        if ($sel) { $BtnRenameVM.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
    })
}
if ($CtxRandomizeHWID) {
    $CtxRandomizeHWID.Add_Click({
        $sel = $ListVMs.SelectedItem
        if ($sel) { $BtnRandomizeHWID.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
    })
}
if ($CtxOpenStream) {
    $CtxOpenStream.Add_Click({
        $sel = $ListVMs.SelectedItem
        if ($sel) { $BtnOpenStream.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
    })
}

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
            try {
                $cfg = Get-ProxyConfig
                if (-not $cfg.assignments) { $cfg | Add-Member -MemberType NoteProperty -Name "assignments" -Value ([PSCustomObject]@{}) -Force }
                if (-not $cfg.assignments.$newName) {
                    $newAssign = [PSCustomObject]@{ enabled = $false; profileId = $null; ip = $newIP }
                    $cfg.assignments | Add-Member -MemberType NoteProperty -Name $newName -Value $newAssign -Force
                    Save-ProxyConfig $cfg
                }
                if ($Script:VMIPMap) { $Script:VMIPMap[$newName] = $newIP }
            } catch {}
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
    $cfg = if (Get-Command Get-ProxyConfig -ErrorAction SilentlyContinue) { Get-ProxyConfig } else { $null }
    $assignedNames = @()
    if ($cfg -and $cfg.assignments) {
        $assignedNames = @($cfg.assignments.PSObject.Properties.Name)
    }
    $allVMs = Get-VM -ErrorAction SilentlyContinue | Where-Object { 
        $_.Name -like "Gaming-*" -or 
        $_.Name -in $assignedNames -or
        (Get-VMNetworkAdapter -VMName $_.Name -ErrorAction SilentlyContinue | Where-Object { $_.SwitchName -eq "VM-Gaming-Switch" })
    }
    foreach ($item in $ListVMs.Items) {
        $vm = $allVMs | Where-Object { $_.Name -eq $item.Name }
        if ($vm) {
            $item.State = $vm.State
            $item.StateText = if ($vm.State -eq 'Running') { "Работает" } else { "Остановлена" }
            $item.StatusColor = if ($vm.State -eq 'Running') { "#22c55e" } else { "#71717a" }
            if ($vm.State -eq 'Running') {
                $freshIp = Get-VMIPAddress $vm.Name
                if ($freshIp -and $freshIp -ne "1" -and $freshIp -ne "-" -and $freshIp.Length -gt 6) {
                    $item.IP = $freshIp
                }
            }
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
