# Папка для ISO-образа Windows (Windows 11 ISO)

Поместите в эту папку установочный ISO-образ Windows 11.

## Рекомендации:
- **Версия**: Windows 11 Pro / Enterprise / Business Editions (версии 23H2, 24H2 или 25H2 x64).
- Редакция **Pro** (обычно `Index: 3` в файле `install.wim` оригинальных образов) содержит все необходимые компоненты для Hyper-V, RDP и групповых политик.

## Как это работает:
Скрипт автономной сборки `scripts\03-Build-GamingVM.ps1` **автоматически обнаруживает** первый `.iso` файл в этой директории. Если здесь лежит ISO, вам не нужно указывать путь вручную.

Пример:
```text
iso/
└── ru-ru_windows_11_business_editions_version_25h2_updated_jan_2026_x64_dvd.iso
```
