# Auto Wallpaper Switcher

Небольшая утилита для Windows 10/11, которая автоматически меняет обои в зависимости от количества активных мониторов и добавляет горячие клавиши переключения режима экранов.

## Поведение

- Один активный монитор: `images/merged.png`.
- Два активных монитора: `images/blue.png` слева и `images/pink.png` справа.
- Проверка конфигурации экранов выполняется каждые 5 секунд.
- Обои применяются только при изменении состояния мониторов.

## Горячие клавиши

- `Ctrl+Alt+1` — только экран компьютера.
- `Ctrl+Alt+2` — расширить экраны.
- `Ctrl+Alt+3` — только второй экран.

## Установка

Откройте PowerShell в папке со скриптом и выполните:

```powershell
powershell -ExecutionPolicy Bypass -File ".\AutoWallpaper.ps1" -Action install
```

Команда `install` создает задачу Windows Task Scheduler `Auto Wallpaper`. Она запускается при входе в Windows с задержкой 20 секунд, чтобы Explorer и рабочий стол успели загрузиться. Скрипт сразу запускается в фоне после установки.

## Команды

```powershell
# Однократное применение
powershell -ExecutionPolicy Bypass -File ".\AutoWallpaper.ps1" -Action once

# Постоянный запуск в текущем окне
powershell -ExecutionPolicy Bypass -File ".\AutoWallpaper.ps1" -Action run

# Диагностика в открытом окне
powershell -ExecutionPolicy Bypass -File ".\AutoWallpaper.ps1" -Action diagnose

# Удаление автозапуска и горячих клавиш
powershell -ExecutionPolicy Bypass -File ".\AutoWallpaper.ps1" -Action uninstall
```

Пути к изображениям и интервал проверки задаются в `wallpapers.json`.

## Изображения

```text
images/merged.png — когда подключен 1 монитор
images/blue.png   — левый монитор
images/pink.png   — правый монитор
```
