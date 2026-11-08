Исследование конкретно под связку **Hyper-V + GPU-PV (GPU Partitioning) на Windows 11 25H2** выявило важные архитектурные особенности, возможности и ограничения. 

Никакой готовой публичной "кнопочной" утилиты вроде AntiOS именно под Hyper-V GPU-PV не существует (AntiOS и большинство его форков создавались исключительно под старый VirtualBox/VMware). **Однако всё необходимое для полного спуфинга и рандомизации такого сетапа реализуется средствами WMI v2 и PowerShell.**

---

### 1. Архитектурный анализ: Что видит софт в Hyper-V с GPU-PV

В виртуалке Windows 11 25H2 с включенным GPU-PV аппаратный профиль формируется из нескольких слоёв:

| Компонент | Что видит Windows 11 по умолчанию | Можно ли изменить/спуфить? | Каким методом? |
| :--- | :--- | :---: | :--- |
| **BIOS Serial** | Сгенерированный серийник Hyper-V | **ДА** | WMI `Msvm_VirtualSystemSettingData` (`BIOSSerialNumber`) |
| **Motherboard Serial** | Пусто или дефолтный ID платы | **ДА** | WMI `Msvm_VirtualSystemSettingData` (`BaseBoardSerialNumber`) |
| **Chassis Serial / Tag** | Пусто или дефолт | **ДА** | WMI `Msvm_VirtualSystemSettingData` (`ChassisSerialNumber`) |
| **System UUID** | Уникальный GUID ВМ | **ДА** | WMI `Msvm_VirtualSystemSettingData` (`BIOSGUID`) |
| **Накопитель (VHDX)** | `Microsoft Virtual Disk` + SCSI Disk ID | **ДА (ID)** | Команда `Set-VHD -ResetDiskIdentifier` |
| **Том диска (VolumeID)** | Серийный номер NTFS тома `C:` | **ДА** | `Volumeid64.exe` внутри гостевой ОС |
| **Сетевая карта (MAC)** | `00:15:5D:xx:xx:xx` (OUI Microsoft) | **ДА** | `Set-VMNetworkAdapter -StaticMacAddress` |
| **Видеокарта (GPU-PV)** | Модель физической карты хоста (напр. RTX 4070) | **ЧАСТИЧНО** | Пересоздание Partition Adapter сбрасывает Instance ID |
| **Производитель/Вендор** | `"Microsoft Corporation"` / `"Virtual Machine"` | **НЕТ** | Зашито в коде `vmwp.exe` Hyper-V |
| **CPUID Hypervisor** | Лист `0x40000000` (`Microsoft Hv`) | **НЕТ** | Зашито в гипервизоре (но **это норма** для Win 11!) |

---

### 2. Важные нюансы именно для вашего сетапа

#### А. Почему флаг `Microsoft Hv` в Windows 11 25H2 больше не выдает виртуалку с головой?
В Windows 10 наличие гипервизора в `CPUID` однозначно указывало на ВМ. Но в **Windows 11 24H2/25H2** по умолчанию на всех реальных физических компьютерах включены:
- **VBS (Virtualization-Based Security)**;
- **HVCI (Memory Integrity)**;
- **Подсистема WSL2 / Windows Sandbox**.

При включении VBS сама физическая хостовая Windows запускается поверх микро-гипервизора Microsoft! Поэтому антифрод-системы и защитный софт уже **не считают флаг Hyper-V признаком эмулятора**. Главным фактором идентификации является **уникальность связки аппаратных серийников (SMBIOS + UUID + Disk Signature + MAC + MachineGuid)**.

#### Б. Специфика видеокарты при GPU-PV
При GPU-PV гостевая система получает аппаратный доступ к физическому видеочипу хоста через DirectX Graphics Kernel (`dxgkrnl.sys`) и шину `VMBus`.
- Название видеокарты, VendorID (`0x10DE` для Nvidia) и DeviceID всегда будут соответствовать вашей физической видеокарте хоста.
- Уникальный идентификатор устройства (Device Instance Path) в диспетчере устройств привязан к `Partition GUID`. Если удалить и заново добавить `VMGpuPartitionAdapter`, Hyper-V выделит новый экземпляр раздела, что обновит узел устройства в реестре.
- **Внимание к монитору:** В GPU-PV выводом изображения управляет либо базовый драйвер Hyper-V, либо виртуальный дисплей (например, *Amyuni VDD* или *IddSampleDriver*). Антифрод в браузерах часто проверяет EDID монитора. Если вы используете виртуалку для антидетект-задач, настройте виртуальный монитор с реальным разрешением и EDID (например, профиль 1080p/144Hz).

---

### 3. Готовое решение для Hyper-V GPU-PV

В директории [`D:\Projects\AntiOS_analog\scripts`](file:///d:/Projects/AntiOS_analog/scripts) подготовлен комплект из двух специализированных скриптов:

#### Скрипт 1: [Host-HyperV-Randomize.ps1](file:///d:/Projects/AntiOS_analog/scripts/Host-HyperV-Randomize.ps1) (Запускается на ХОСТЕ)
Выполняется перед запуском виртуальной машины от имени Администратора:
1. Подключается к пространству `root\virtualization\v2` через WMI.
2. Генерирует новые валидные случайные значения для `BIOSSerialNumber`, `BaseBoardSerialNumber`, `ChassisSerialNumber`, `ChassisAssetTag` и `BIOSGUID`.
3. Вызывает метод `ModifySystemSettings` сервиса управления Hyper-V и прошивает их в виртуальный UEFI.
4. Находит VHDX-диск виртуалки и сбрасывает его аппаратную сигнатуру командой `Set-VHD -ResetDiskIdentifier`.
5. Меняет MAC-адрес на случайный с OUI реальных вендоров (Intel, Dell, Realtek вместо палевного пула Microsoft `00:15:5D`).
6. Переинициализирует GPU-PV адаптер (сбрасывает экземпляр раздела).

**Пример запуска на хосте:**
```powershell
# Запуск в PowerShell от Администратора
cd D:\Projects\AntiOS_analog\scripts
.\Host-HyperV-Randomize.ps1 -VMName "Имя_Вашей_ВМ"
```

#### Скрипт 2: [Guest-HyperV-CleanID.ps1](file:///d:/Projects/AntiOS_analog/scripts/Guest-HyperV-CleanID.ps1) (Запускается ВНУТРИ ГОСТЯ)
Выполняется внутри Windows 11 25H2 (аналог внутренней логики AntiOS, адаптированный под требования Win 11):
1. Генерирует новый криптографический `MachineGuid` в `HKLM:\SOFTWARE\Microsoft\Cryptography`.
2. Меняет `HardwareProfileGuid`, `BuildGuid`, `InstallDate` и `ProductId`.
3. Сбрасывает телеметрический идентификатор `SQMClient\MachineId`.
4. Сменяет Volume Serial Number тома `C:` утилитой [Volumeid64.exe](file:///d:/Projects/AntiOS_analog/scripts/Volumeid64.exe) (бинарник скопирован прямо в папку `scripts`).
5. Рандомизирует имя компьютера (`DESKTOP-XXXXXXX`).

#### Скрипт 3: [Verify-HWID.ps1](file:///d:/Projects/AntiOS_analog/scripts/Verify-HWID.ps1) (Проверка)
Запустите его внутри виртуалки до и после рандомизации, чтобы наглядно увидеть, как изменились все аппаратные и системные идентификаторы:
- SMBIOS серийники BIOS и материнки;
- Системный UUID;
- Серийник и DeviceID накопителя;
- Серийный номер тома C:;
- MAC-адрес и MachineGuid.

---