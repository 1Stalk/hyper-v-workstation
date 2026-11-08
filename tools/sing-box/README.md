# Sing-box Transparent Routing Engine

В этой папке размещается исполняемый файл маршрутизатора **Sing-box** (`sing-box.exe`), который используется подсистемой `Host-Proxy-Manager.ps1` для прозрачной маршрутизации трафика каждой виртуальной машины через внешние SOCKS5-прокси на стороне хоста (с использованием Windows Filtering Platform и TUN-стека gVisor).

## Установка:
Исполняемый файл загружается автоматически скриптом:
```powershell
powershell -ExecutionPolicy Bypass -File scripts\00-Download-Tools.ps1
```
Или вручную:
1. Скачайте `sing-box-*-windows-amd64.zip` со страницы релизов [SagerNet/sing-box](https://github.com/SagerNet/sing-box/releases).
2. Распакуйте `sing-box.exe` в данную папку (`tools\sing-box\`).

*Бинарный файл `sing-box.exe` исключен из Git-репозитория через `.gitignore`.*
