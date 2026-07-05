# Auto Wallpaper Switcher

Небольшая утилита для Windows 10/11, которая автоматически меняет обои в зависимости от количества активных мониторов и добавляет горячие клавиши переключения режима экранов.

## Поведение

- Один активный монитор: `images/merged.png`.
- Два активных монитора: `images/blue.png` слева и `images/pink.png` справа.
- Проверка конфигурации экранов выполняется каждые 5 секунд.

## Горячие клавиши

- `Ctrl+Alt+1` — только экран компьютера.
- `Ctrl+Alt+2` — расширить экраны.
- `Ctrl+Alt+3` — только второй экран.

## Установка

Откройте PowerShell и выполните:

```powershell
powershell -ExecutionPolicy Bypass -File ".\AutoWallpaper.ps1" -Action install
```

Скрипт сразу запускается в фоне и добавляется в автозагрузку Windows.

## Команды

```powershell
# Однократное применение
powershell -ExecutionPolicy Bypass -File ".\AutoWallpaper.ps1" -Action once

# Диагностика в открытом окне
powershell -ExecutionPolicy Bypass -File ".\AutoWallpaper.ps1" -Action diagnose

# Удаление из автозагрузки и удаление горячих клавиш
powershell -ExecutionPolicy Bypass -File ".\AutoWallpaper.ps1" -Action uninstall
```

Пути к изображениям и интервал проверки задаются в `wallpapers.json`.
