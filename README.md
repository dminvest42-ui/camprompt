# CamPrompt — телесуфлёр под камерой MacBook

Нативное macOS-приложение: профессиональный телесуфлёр, оптимизированный под запись видео прямо на MacBook. Текст плавно прокручивается **прямо под камерой (в зоне notch)** — глаза остаются направленными в объектив. Запись видео и звука — внутри самого приложения.

![icon](Resources/icon_1024.png)

## Чем отличается от существующих

Notch-телесуфлёры (Notchie, CueNotch, Textream, NotchPrompt) не записывают видео. Приложения с записью (Teleprompter Premium, BIGVU) не умеют держать текст у камеры. CamPrompt делает и то и другое.

## Возможности v0.1

- Плавающая панель суфлёра, закреплённая под notch — поверх всех приложений (включая fullscreen).
- Плавный автоскролл со строкой-якорем, скорость 1–100, пауза/пуск/с начала, луп.
- Библиотека скриптов со встроенным редактором.
- Настройка текста: шрифт, размер, жирность, цвета, прозрачность фона, межстрочный интервал, отступы, выравнивание, зеркальный текст (для beam-splitter ригов).
- Камера: живое превью, выбор камеры (встроенная / Continuity / внешняя) и микрофона, зеркальное превью.
- Запись видео+звука (H.264/AAC, .mov, 1080p) в `~/Movies/Teleprompter/`, обратный отсчёт, таймер записи, список записей.
- Горячие клавиши: `Пробел` пауза/пуск · `R` с начала · `↑/↓` скорость · `←/→` перемотка · `Esc` скрыть панель.
- Опция «прятать суфлёр от записи экрана» (Zoom/OBS/QuickTime не увидят текст).

## Установка

1. Скачайте `.dmg` из [Releases](../../releases/latest) и откройте.
2. Перетащите **CamPrompt** в **Applications**.
3. Приложение пока не нотарифицировано, поэтому один раз выполните в Терминале:
   ```
   xattr -dr com.apple.quarantine /Applications/CamPrompt.app
   ```
4. Запустите, разрешите доступ к камере и микрофону.

Требуется macOS 14 (Sonoma) или новее. Оптимизировано под MacBook с notch (2021+), но работает на любом Mac.

## Сборка из исходников

```bash
swift build            # проверка компиляции
bash scripts/build_app.sh 0.1.0   # соберёт dist/CamPrompt.app + .dmg (нужен macOS)
```

CI (GitHub Actions, macos-15) собирает `.dmg` на каждый пуш в `main`; тег `v*` публикует Release.

## Архитектура

SwiftUI (UI) + AppKit (оконный слой) без внешних зависимостей:

- `PrompterPanelController` — borderless `NSPanel` (`.nonactivatingPanel`, level `.screenSaver`, `canJoinAllSpaces + fullScreenAuxiliary`), позиционирование по геометрии notch-экрана.
- `ScrollEngine` — 60 fps таймер прокрутки.
- `CaptureManager` — `AVCaptureSession` + `AVCaptureMovieFileOutput` (превью + запись).
- `ScriptStore` / `SettingsStore` / `RecordingsStore` — persistence (JSON + UserDefaults).

Подробности: [docs/RESEARCH.md](docs/RESEARCH.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/DEV_PLAN.md](docs/DEV_PLAN.md), [docs/RISKS.md](docs/RISKS.md).

## Лицензия

MIT. Паттерны оконного слоя изучены по MIT-проектам [Textream](https://github.com/f/textream), [NotchPrompt](https://github.com/aliarain/notchprompt), [Peek](https://github.com/guajardo/peek).
