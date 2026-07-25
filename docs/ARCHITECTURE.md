# Архитектура CamPrompt

Состояние: v0.1 реализована. Файлы — `Sources/CamPrompt/`.

## Слои

```
┌────────────────────────────────────────────────────────────┐
│ SwiftUI                                                    │
│  MainWindowView (сайдбар+редактор+превью+запись)           │
│  PrompterView (текст в notch-панели)  SettingsPopovers ×3  │
├────────────────────────────────────────────────────────────┤
│ Координатор: AppState (@MainActor, singleton)              │
│  record-flow: countdown → capture.start + engine.play      │
│  клавиатура: локальный NSEvent-монитор → handleKeyDown     │
├──────────────┬──────────────┬──────────────────────────────┤
│ WindowKit    │ PrompterCore │ CaptureKit                   │
│ Prompter-    │ ScrollEngine │ CaptureManager               │
│ Panel-       │ (60fps Timer,│ (AVCaptureSession на serial  │
│ Controller   │  offset/loop)│  queue, MovieFileOutput)     │
├──────────────┴──────────────┴──────────────────────────────┤
│ Persistence: SettingsStore (UserDefaults)                  │
│  ScriptStore (JSON, ~/Library/App Support/CamPrompt)       │
│  RecordingsStore (файлы ~/Movies/Teleprompter)             │
└────────────────────────────────────────────────────────────┘
```

## Ключевые решения

1. **SwiftUI + AppKit гибрид.** SwiftUI рисует контент, AppKit владеет окнами. Причина: SwiftUI не умеет borderless nonactivating панели с window level и `orderFrontRegardless` — это территория `NSPanel`. Контент внутрь через `NSHostingView`.
2. **Zero dependencies.** Автономная CI-доставка без запуска на Mac: каждая зависимость — риск несовместимости. Всё нужное укладывается в ~1400 строк своего кода.
3. **Однонаправленный поток состояния.** Все сервисы — `ObservableObject`, инжектятся через `environmentObject`. Панель получает ссылки напрямую (без environment — у неё своя NSHostingView-иерархия).
4. **Конкурентность.** UI-классы `@MainActor`. `CaptureManager` — не изолирован (работа на `sessionQueue`), `@Published` мутируются только через main. Swift 5 language mode (tools 5.9) — без строгой Sendable-проверки.
5. **Запись через `AVCaptureMovieFileOutput`** (не AVAssetWriter): муксинг видео+звук из коробки, меньше кода — надёжнее для v0.1. Апгрейд-путь на AVAssetWriter (пауза записи, фильтры) не ломает интерфейс CaptureManager.
6. **ScrollEngine — Timer 60 Гц**, `offset += pointsPerSecond * dt` с реальным dt (CACurrentMediaTime). Текст — ОДНА `Text`-нода с `.offset(y:)` → композитинг без relayout. Конец текста: стоп или луп (настройка).
7. **Панель**: `NSPanel(.borderless, .nonactivatingPanel)`, `level=.screenSaver`, `collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]`, `sharingType` по настройке. Геометрия: центр по `midX` notch-экрана (`safeAreaInsets.top > 0`), `height = menuBarHeight + textHeight`, `y = screenFrame.maxY - height`. Скруглённый низ (PanelShape) — визуально «расширенный notch».
8. **Пересоздание панели** при смене геометрии/режима (reloadPanelIfVisible) вместо живой перестройки — проще и надёжнее для v0.1.

## Файлы

| Файл | Роль | ~строк |
|---|---|---|
| CamPromptApp.swift | @main, сцены, меню-команды, AppDelegate (key monitor) | 70 |
| AppState.swift | координатор, record-flow, хоткеи | 180 |
| SettingsStore.swift | 20+ настроек в UserDefaults, hex-цвета | 150 |
| ScriptStore.swift | модель Script + JSON-библиотека | 90 |
| ScrollEngine.swift | 60fps прокрутка, луп | 80 |
| CaptureManager.swift | discovery/permissions/session/запись | 200 |
| RecordingsStore.swift | список записей, Finder-интеграция | 60 |
| PrompterPanelController.swift | NSPanel под notch | 90 |
| PrompterView.swift | текст+якорь+HUD, PanelShape | 160 |
| CameraPreviewView.swift | NSViewRepresentable превью-слоя | 50 |
| MainWindowView.swift | главное окно | 280 |
| SettingsPopovers.swift | три поповера настроек | 160 |

## Сборка и дистрибуция

- SwiftPM executable → `scripts/build_app.sh`: `swift build -c release` → ручной бандл `.app` (Info.plist, icns через sips/iconutil) → ad-hoc `codesign` → `hdiutil` .dmg.
- CI: `.github/workflows/build.yml`, `macos-15` раннер. Пуш в main → артефакт; тег `v*` → GitHub Release с .dmg.
- Нотарификация: v2 — понадобятся Developer ID cert + App Store Connect API key как GitHub secrets; жёстко в пайплайн не зашита.

## Путь к v2

- Voice-follow скролл: порт SpeechRecognizer/SpeechTextAlignment из Textream (MIT), on-device.
- Пауза записи/сегменты: замена MovieFileOutput на AVAssetWriter-пайплайн (рецепт CineScreen).
- Сглаживание кожи / виртуальный фон: AVCaptureVideoDataOutput → Core Image (+Vision person segmentation) → превью через CAMetalLayer, запись через AVAssetWriter.
- Глобальные хоткеи: KeyboardShortcuts (Carbon RegisterEventHotKey — без Accessibility-разрешения).
- Sparkle-обновления, нотарификация, App Store-вариант (sandbox + security-scoped bookmarks для ~/Movies).
