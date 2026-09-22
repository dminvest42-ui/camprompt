# Research: macOS-телесуфлёр с записью видео под камерой MacBook

Дата: 2026-07-25. Статус: завершён, лёг в основу v0.1 (уже собирается в CI).
Термины и имена API — английские, пояснения — русские.

---

## 1. Обзор существующих приложений

### 1.1 Коммерческие notch-телесуфлёры (текст у камеры, БЕЗ записи видео)

| Приложение | Цена | Технологии | Сильные стороны | Слабые стороны | Почему не решает нашу задачу |
|---|---|---|---|---|---|
| **Notchie** (notchie.app) | $29.99 one-time | Нативный Swift | Voice-sync скролл, Ghost Mode (невидим при screen share), «живёт в notch» | Закрытый код | Не записывает видео. Только суфлёр |
| **CueNotch** | $29.99 one-time | Нативный, App Store | AI Rehearsal Coach, AutoCaption, Memorize Mode, библиотека скриптов | Закрытый код, перегружен AI-фичами | Не записывает видео |
| **Moody** | $29 one-time | Нативный | Простота | Закрытый код | Не записывает видео |
| **ShareSpeak** | $12.50 | Кроссплатформенный (Windows тоже) | Дешевле | Не нативный | Не записывает видео |

### 1.2 Телесуфлёры с записью (текст НЕ у камеры)

| Приложение | Модель | Технологии | Сильные стороны | Слабые стороны |
|---|---|---|---|---|
| **Teleprompter Premium / Pro+** (App Store id1533078079) | Подписка/покупка | Mac Catalyst (iPad-порт) | Запись видео + суфлёр в одном окне, полировка, «Плавающий» режим | Текст в центре окна, не под камерой; iPad-UI на Mac; глаза бегают |
| **Teleprompter.com** | Подписка | Web + нативные обёртки | 4K 50fps, mirror, remote control | Облако, подписка, текст не у камеры |
| **BIGVU** | Подписка | Web/Electron | Не останавливается при паузе записи, монтаж | Тяжёлый, облачный, дорогой |

Референс-скриншоты заказчика — приложение этого класса («Телесуфлёр», Catalyst-стиль). Разбор — §6.

### 1.3 Open source (ключевой ресурс)

| Репозиторий | Лицензия | Стек | Что даёт | Ограничение |
|---|---|---|---|---|
| **f/textream** (3.5k★) | MIT | Swift, SwiftUI+AppKit, macOS 15+ | Эталон notch-оверлея: NSPanel-геометрия, 3 режима скролла (word tracking через SFSpeechRecognizer, classic WPM, voice-activated), multi-display, Sidecar, WebSocket-режиссёрский пульт | Нет камеры/записи вообще |
| **aliarain/notchprompt** (21★) | MIT | SwiftUI, macOS 14+, DynamicNotchKit | Компактная модульная структура (App/Core/Views/Services), WordFlowView, PPTX-импорт | Нет камеры; зависимость DynamicNotchKit |
| **AndrewUsher/prontch** | нет лицензии | SwiftUI+AVFoundation (VAD) | Тот же notch-паттерн + voice activity detection | 2 коммита, сырой; нет записи |
| **arunngun/openTeleprompt** | OSS | **Electron** + React/Vite/Zustand | Dynamic Island анимации, rich-text редактор | Electron: тяжёлый рантайм, нет нативного качества оконного слоя |
| **guajardo/peek** | MIT | Чистый Swift + AVFoundation, SPM | Эталон: запись веб-камеры (AVAssetWriter), бандлинг SPM-бинаря в .app, ad-hoc codesign | Video-only (без звука), menu-bar утилита |
| **ahmetb/iris** | OSS | Swift | Круглое always-on-top превью камеры | Только превью |
| **jasonzh0/cinescreen** | MIT | Swift+SwiftUI+Metal, macOS 14+ | Production-пайплайн AVAssetWriter (экспорт без дропа кадров) | Screen recorder, не суфлёр |
| **TheBoredTeam/boring.notch, Lakr233/NotchDrop, DynamicNotch** | OSS | Swift | Техника окон в зоне notch, Dynamic Island UX | Не суфлёры |
| **capsoftware/cap** (PR #2006) | OSS | Tauri/Rust | Паттерн «телесуфлёр внутри рекордера» + исключение окна из записи | Чужая экосистема (Tauri) |

**Вывод §1.** Ниша «текст под камерой + запись в приложении» реально пуста. Ни один OSS-проект не годится как база целиком (нет capture-подсистемы), но Textream даёт проверенный оконный слой, Peek — проверенный бандлинг и capture, NotchPrompt — структуру модулей. Стратегия: своё ядро + точечное заимствование паттернов (все MIT).

---

## 2. Интеграция камеры (AVFoundation)

### 2.1 Строительные блоки

- **`AVCaptureSession`** — центральный объект: входы (камера, микрофон) → выходы (превью, файл). Конфигурация между `beginConfiguration()`/`commitConfiguration()`, работа на выделенной serial queue (UI не блокируется).
- **`AVCaptureDevice.DiscoverySession`** — перечисление камер: `.builtInWideAngleCamera` (встроенная FaceTime-камера в notch), `.continuityCamera` (iPhone как камера, macOS 14+), `.external` (USB-камеры, macOS 14+). Микрофоны: `.microphone`.
- **`AVCaptureVideoPreviewLayer`** — hardware-accelerated превью (CALayer), `videoGravity = .resizeAspectFill`. Зеркалирование: `connection.automaticallyAdjustsVideoMirroring = false; isVideoMirrored = true`.
- **Запись, 2 пути:**
  1. **`AVCaptureMovieFileOutput`** — high-level: `startRecording(to:recordingDelegate:)`, сам муксит видео+звук в .mov (H.264+AAC), обрабатывает дропы. ✅ **Выбран для v0.1** — минимум кода, максимум надёжности.
  2. **`AVAssetWriter` + `AVCaptureVideoDataOutput`/`AVCaptureAudioDataOutput`** — low-level: полный контроль (пауза записи, оверлеи, кастомный битрейт/кодек). Известные грабли (задокументированы в проде у других): порядок буферов строго FIFO на одной serial queue (иначе `writer.status == .failed`); `startWriting()` занимает до 300 мс — вызывать заранее, не в первом колбэке; финализация после дрейна всех колбэков. Путь апгрейда для v2 (пауза записи, «сглаживание кожи»).
- **Hardware acceleration** — H.264/HEVC энкодинг на Apple Silicon аппаратный (VideoToolbox под капотом MovieFileOutput), CPU-нагрузка минимальна.

### 2.2 Разрешения (TCC)

- `NSCameraUsageDescription` + `NSMicrophoneUsageDescription` в Info.plist обязательны — без них процесс убивается при первом обращении.
- `AVCaptureDevice.requestAccess(for: .video/.audio)` — системный диалог один раз; отказ → вести в System Settings → Privacy & Security.
- TCC-диалоги неустранимы (это ОС), показываются один раз на приложение.

### 2.3 App Store / sandbox

- Всё выше — публичные API, App Store-совместимы. Для sandbox: entitlements `com.apple.security.device.camera` + `...device.audio-input`; сохранение в `~/Movies` потребует security-scoped bookmark или папку контейнера. v0.1 распространяется вне App Store без sandbox → пишет в `~/Movies/Teleprompter` напрямую (папка не под TCC-защитой, в отличие от Desktop/Documents/Downloads).

### 2.4 Производительность

Превью-слой + 60fps скролл текста + запись 1080p одновременно — штатная нагрузка для Apple Silicon (аналогичные связки крутят Zoom/OBS + суфлёры). Риск один: SwiftUI-рендер длинного текста (тысячи строк) — решение: одна `Text`-нода со смещением `offset` (композитинг, без relayout) — так сделано в v0.1; при деградации → CATextLayer/TextKit 2 (§4 RISKS).

---

## 3. Плавающие окна и позиционирование под камерой

### 3.1 Рецепт «поверх всего» (проверен в Textream/NotchPrompt/boring.notch)

```swift
let panel = NSPanel(contentRect: rect,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
panel.level = .screenSaver                     // выше .floating, .statusBar, окон QuickTime/OBS/браузеров
panel.collectionBehavior = [.canJoinAllSpaces, // на всех Spaces
                            .fullScreenAuxiliary, // поверх native-fullscreen приложений
                            .stationary]       // не двигается при Mission Control
panel.isOpaque = false; panel.backgroundColor = .clear
panel.orderFrontRegardless()                   // показать без активации приложения
```

- `.nonactivatingPanel` — клики по панели не крадут фокус у приложения, в котором работает пользователь.
- `NSWindow.Level` лестница: `.normal` < `.floating` < `.modalPanel` < `.mainMenu` < `.statusBar` < `.popUpMenu` < `.screenSaver`. QuickTime/OBS/Loom/Screen Studio/браузеры живут на `.normal` — любой уровень от `.floating` уже выше; `.screenSaver` перекрывает и статус-бар оверлеи.
- Драг: `isMovableByWindowBackground = true` (в закреплённом режиме выключен).

### 3.2 Позиционирование под камерой (notch)

- Камера физически в центре notch, notch — внутри полосы меню-бара.
- Геометрия: `menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY` (~37-38 pt на notched-моделях); notch-экран определяется `screen.safeAreaInsets.top > 0` (macOS 12+); точные границы notch: `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`.
- Панель: `x = screenFrame.midX - width/2`, `y = screenFrame.maxY - height`, `height = menuBarHeight + textHeight` — верхняя часть панели (чёрная) сливается с notch, текст начинается сразу под ним. Это даёт минимальное расстояние глаз-объектив ≈ 1-3° вертикального угла.

### 3.3 Ограничения macOS (все найденные)

1. **Внутри notch пикселей нет** — это вырез в матрице. Рисовать «в notch» нельзя ни публичными, ни приватными API; можно только вплотную вокруг/под ним. Все «notch-приложения» рисуют чёрный фон, визуально сливающийся с вырезом.
2. Меню-бар полоса: окно уровня `.screenSaver` рисуется ПОВЕРХ меню-бара — наша панель занимает эту полосу (чёрная зона), меню-бар под ней временно не виден в этой области. Для суфлёра это фича (сплошной чёрный «расширенный notch»).
3. **Mission Control / Exposé** — оверлеи скрываются на время жеста (системное поведение, `.stationary` смягчает).
4. **Полноэкранные игры с captured display** (CGDisplayCapture) перекрыть нельзя — не наш кейс.
5. **Секретные шторки ОС** (ввод пароля, экран блокировки) всегда выше — корректно.
6. `orderFrontRegardless` не делает окно key — хоткеи панели работают через глобальный/локальный монитор, не через responder chain (в v0.1 — локальный, см. RISKS §5).
7. Приватные API не нужны: весь стек — публичный (подтверждено четырьмя работающими OSS-проектами и прохождением CueNotch в App Store).

### 3.4 Бонус: невидимость для записи экрана

`panel.sharingType = .none` — окно исключается из ScreenCaptureKit/CGDisplayStream → Zoom/OBS/QuickTime его не видят. В v0.1 это опция «Прятать от записи экрана» (по умолчанию ВЫКЛ — при записи через нашу камеру это не нужно, а при скринкастах пользователь решает сам).

---

## 4. Реюз библиотек: что берём, что пишем сами

| Область | Кандидат | Решение v0.1 | Причина |
|---|---|---|---|
| Глобальные хоткеи | sindresorhus/**KeyboardShortcuts** (MIT) | ❌ позже (v2) | Глобальный NSEvent-монитор требует Accessibility-разрешение; v0.1 обходится локальными хоткеями без единого лишнего разрешения |
| Настройки | sindresorhus/**Defaults** | ❌ свой SettingsStore на UserDefaults | Zero-dependency цель; 100 строк своего кода |
| Автозапуск | **LaunchAtLogin** | ❌ не нужно суфлёру | — |
| Обновления | **Sparkle 2** (EdDSA, appcast) | ❌ v2 | Требует ключи подписи и хостинг appcast; v0.1 обновляется скачиванием нового .dmg из Releases |
| Notch-анимации | **DynamicNotchKit** | ❌ своя панель | Зависимость ради анимации раскрытия; наш прямоугольник под notch проще и предсказуемее |
| Word tracking | Apple **SFSpeechRecognizer** (on-device) | ❌ v2 | Паттерн готов в Textream (MIT) — перенос при запросе фичи |
| Скролл текста | — | ✅ свой ScrollEngine (60fps Timer) | Тривиален (80 строк), полный контроль |
| Camera/запись | — | ✅ свой CaptureManager | AVFoundation-обвязка тонкая; MovieFileOutput надёжен |
| Окна | — | ✅ свой PrompterPanelController | 100 строк по проверенному рецепту §3.1 |

Итог v0.1: **ноль внешних зависимостей** — меньше движущихся частей при автономной CI-доставке без запуска на живом Mac.

---

## 5. Каталог полезных репозиториев (ускорители)

- github.com/f/textream — оконный слой, скролл-режимы, speech (MIT)
- github.com/aliarain/notchprompt — структура модулей, WordFlowView (MIT)
- github.com/guajardo/peek — SPM→.app бандлинг, capture (MIT)
- github.com/jasonzh0/cinescreen — AVAssetWriter экспорт-пайплайн (MIT)
- github.com/ahmetb/iris — always-on-top превью камеры
- github.com/TheBoredTeam/boring.notch, github.com/Lakr233/NotchDrop — notch-UX
- Apple sample: AVCam (Building a Camera App)
- nonstrict.eu/blog — статьи про audio gaps / ScreenCaptureKit+AVAssetWriter грабли

---

## 6. UI-анализ референса (4 скриншота «Телесуфлёр», 2026-07-25)

### Что взяли как паттерны
- **Сайдбар «Скрипты» + рабочая зона** → в CamPrompt: NavigationSplitView (скрипты + записи) слева, редактор + превью справа.
- **Строка-якорь** (подчёркивание текущей строки) → акцентная линия чтения на настраиваемой высоте.
- **Три кластера настроек** (видео / текст / суфлёр) в компактных поповерах → три поповера в тулбаре.
- **Запись**: таймер-бейдж, крупная Record-кнопка, countdown → повторено, плюс индикатор в notch-панели.

### Слабости референса → улучшения в CamPrompt
1. Текст в центре окна → глаза вниз. **CamPrompt: текст в notch-панели вплотную к камере.**
2. iPad/Catalyst UI, поповеры перекрывают текст. **CamPrompt: нативный macOS, авто-скрытие HUD, контролы вне текста.**
3. «Плавающий» режим — обычное окно без уровня поверх fullscreen и без привязки к камере. **CamPrompt: `.screenSaver` + `fullScreenAuxiliary` + pin к notch.**
4. Нет хоткеев. **CamPrompt: Пробел/R/стрелки/Esc.**
5. Бьюти-фичи (сглаживание кожи, виртуальные фоны) — тяжёлые и вторичные. **CamPrompt: v2, после стабильного ядра (Core Image + Vision person segmentation).**

---

## 7. Final Recommendation (реализовано в v0.1)

1. **Архитектура**: SwiftUI (контент/настройки) + AppKit (оконный слой NSPanel), MVVM-lite: ObservableObject-сервисы (SettingsStore, ScriptStore, ScrollEngine, CaptureManager, RecordingsStore) + координатор AppState.
2. **Технологии**: Swift 5.9+, macOS 14+, SwiftPM (без Xcode-проекта — сборка скриптом + CI).
3. **Библиотеки**: v0.1 — ноль; v2 — KeyboardShortcuts, Sparkle, SFSpeechRecognizer-паттерн из Textream.
4. **С нуля**: оконный слой, scroll engine, capture, редактор, настройки.
5. **Реюз**: рецепты (не код) из Textream/NotchPrompt/Peek; бандлинг-скрипт по образцу Peek.
6. **Порядок разработки**: окно+скролл → камера+превью → запись → полировка (см. DEV_PLAN.md).
7. **Риски**: см. RISKS.md.
8. **Альтернативы отклонены**: Electron (тяжесть, нет нативного notch-качества), Catalyst (источник слабостей референса), форк Textream (нет capture, дороже вырезать лишнее, чем собрать своё ядро).
9. **Почему это лучший путь**: единственная комбинация, дающая (а) физический минимум движения глаз, (б) нативную производительность и качество окон, (в) нулевые зависимости для автономной доставки, (г) прямой путь апгрейда к v2-фичам без переписывания ядра.
