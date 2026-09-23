# Архитектура CamPrompt

Состояние: **v0.3.0** (2026-09-23). Исходники — [`Sources/CamPrompt/`](../Sources/CamPrompt/).

Навигация: [AGENT_ONBOARDING](AGENT_ONBOARDING.md) · [DECISIONS](DECISIONS.md) · [TROUBLESHOOTING](TROUBLESHOOTING.md) · [RISKS](RISKS.md) · [DEV_PLAN](DEV_PLAN.md) · [RESEARCH](RESEARCH.md) · [CHANGELOG](../CHANGELOG.md)

---

## 1. Что это и зачем

Телесуфлёр для macOS, в котором текст едет **под вырезом камеры MacBook**, а запись видео и звука идёт внутри того же приложения. Смысл: глаза остаются в объективе, и не нужен второй инструмент для записи. Почему не собрали из готового — [D-001](DECISIONS.md#d-001-пишем-своё-приложение-а-не-собираем-связку-из-готовых), обзор рынка — [RESEARCH](RESEARCH.md) §1.

Инструмент личный: один пользователь, приложение русскоязычное, без телеметрии и сети.

Требования: macOS 14+, SwiftPM, без внешних зависимостей ([D-003](DECISIONS.md#d-003-zero-dependencies)).

---

## 2. Слои

```
┌──────────────────────────────────────────────────────────────┐
│ SwiftUI (содержимое)                                         │
│  MainWindowView   — сайдбар, редактор, превью, кнопки записи │
│  PrompterView     — текст в панели, плашка управления, грипы │
│  SettingsPopovers — 3 поповера + NumberSliderRow             │
│  CameraPreviewView— NSViewRepresentable над AVCapture-слоем  │
├──────────────────────────────────────────────────────────────┤
│ Координатор: AppState (@MainActor, singleton .shared)        │
│  сценарий записи: отсчёт → capture.start + engine.play       │
│  клавиатура: локальный NSEvent-монитор → handleKeyDown       │
│  владеет всеми сторами и контроллером панели                 │
├───────────────┬──────────────┬───────────────────────────────┤
│ Оконный слой  │ Прокрутка    │ Захват                        │
│ PrompterPanel │ ScrollEngine │ CaptureManager                │
│ Controller    │ Timer 60 Гц  │ AVCaptureSession на своей     │
│ ScrollForward │ offset/луп   │ очереди + MovieFileOutput     │
│ ingPanel      │              │ + диагностика                 │
│ PanelHosting  │              │                               │
│ View          │              │                               │
├───────────────┴──────────────┴───────────────────────────────┤
│ Хранение                                                     │
│  SettingsStore  — UserDefaults (25 ключей)                   │
│  ScriptStore    — JSON ~/Library/Application Support/CamPrompt│
│  RecordingsStore— файлы в папке записей                      │
└──────────────────────────────────────────────────────────────┘
```

Поток состояния однонаправленный: сторы — `ObservableObject`, в главное окно приходят через `environmentObject`. **Исключение:** у панели своя иерархия `NSHostingView`, environment туда не долетает — `PrompterView` получает `state`, `settings`, `engine` явным конструктором ([D-002](DECISIONS.md#d-002-swiftui--appkit-гибрид)).

---

## 3. Точки входа

| Что | Где | Комментарий |
|---|---|---|
| `@main` | [CamPromptApp.swift](../Sources/CamPrompt/CamPromptApp.swift) | `WindowGroup` + меню-команды (⌘T, ⌘E, ⌘R, ⌘N, ⌘Space) |
| Запуск приложения | `AppDelegate.applicationDidFinishLaunching` | активация + локальный монитор клавиш |
| Старт камеры | `MainWindowView.onAppear` → `capture.refreshDevices()` + `capture.startCamera()` | TCC-диалоги появляются здесь |
| Показ суфлёра | `AppState.togglePanel()` → `PrompterPanelController.show()` | ⌘T или кнопка в главном окне |
| Запись | `AppState.toggleRecording()` | из главного окна, из панели, из меню (⌘E) |
| Завершение | `AppDelegate.applicationWillTerminate` | снимает монитор клавиш, `capture.shutdown()` |

Окно закрывается — приложение живёт (`applicationShouldTerminateAfterLastWindowClosed = false`), чтобы панель не умирала вместе с окном.

---

## 4. Сценарий записи по шагам

```
toggleRecording()
  ├─ .idle ──────────► startRecordingFlow()
  │                     ├─ engine.text ← текст выбранного скрипта
  │                     ├─ показать панель, если settings.showPanelOnRecord
  │                     ├─ сессия уже живая? → startCountdown()
  │                     └─ иначе capture.startCamera(), ждать до 5 с
  │                          (50 × 100 мс), потом startCountdown()
  │                          — не дождались → lastError, выход
  ├─ .countingDown ──► cancelCountdown()        (повторное нажатие отменяет)
  └─ .recording ─────► stopRecordingFlow()

startCountdown(n = settings.countdownSeconds)
  ├─ n == 0 → beginRecording()
  └─ Timer 1 Гц: n → n-1 → … → beginRecording()

beginRecording()
  ├─ capture.startRecording() -> Bool
  │     └─ нет активного видео-соединения → false, остаёмся в .idle   ← D-012
  ├─ recordingState = .recording, recordingSeconds = 0
  ├─ engine.restart(); engine.play()
  └─ Timer 1 Гц: recordingSeconds += 1

stopRecordingFlow()
  ├─ capture.stopRecording() → делегат fileOutput(didFinishRecordingTo:)
  │     └─ onRecordingFinished → recordings.refresh(), lastRecordingURL
  ├─ engine.pause()
  └─ recordingState = .idle
```

Состояние записи — `AppState.RecordingState`: `.idle` / `.countingDown(Int)` / `.recording`. Оно же управляет видом кнопок в главном окне и на панели.

---

## 5. Захват: `CaptureManager`

Файл: [CaptureManager.swift](../Sources/CamPrompt/CaptureManager.swift).

**Конкурентность.** Сессия конфигурируется и стартует на приватной очереди `ru.olya.camprompt.session`; все `@Published` меняются через `DispatchQueue.main.async`. Класс не изолирован в актор (`@unchecked Sendable`), методы обнаружения устройств и старта — `@MainActor`.

**Порядок конфигурации — критичный, см. [D-011](DECISIONS.md#d-011-sessionpreset-выставляется-после-добавления-входов):**

```
beginConfiguration()
  sessionPreset = .high              ← универсальный, НЕ 1080p
  снять старые входы
  addInput(video)   → не вышло: lastError + сессия не запускается
  addInput(audio)   → не вышло: только заметка в лог, видео не роняем
  addOutput(movieOutput)
  если canSetSessionPreset(.hd1920x1080) УЖЕ С ВХОДАМИ → поднять до 1080p
commitConfiguration()
  startRunning()
  проверить movieOutput.connection(with: .video)?.isActive
    └─ не активно → lastError «сигнал не идёт»
```

**Почему не наоборот.** У сессии без входов `canSetSessionPreset` отвечает «да» на любой пресет. Камера 720p (Air M1, 13″ Pro) затем отклоняется `canAddInput` — и без явной проверки это происходит молча.

**Обнаружение устройств.** `AVCaptureDevice.DiscoverySession` по типам `.builtInWideAngleCamera`, `.continuityCamera`, `.external` (видео) и `.microphone` (звук). Выбор: явный `uniqueID` из настроек → иначе встроенная камера → иначе первая доступная.

**Диагностика** ([D-018](DECISIONS.md#d-018-диагностика--в-буфер-обмена)): `diagnosticsReport()` собирает версии, статусы TCC, список камер с максимальным и активным разрешением, занятость, состояние сессии и соединений, заметки последней конфигурации. `copyDiagnosticsToClipboard()` кладёт это в буфер. Параллельно — `os.Logger(subsystem: "ru.olya.camprompt", category: "capture")`.

**Формат записи** ([D-020](DECISIONS.md#d-020-качество-записи-hevc-с-потолком-битрейта-и-ступенчатый-откат)). `.mov` с AAC-звуком, 1080p или максимум камеры. Имя: `CamPrompt_ГГГГ-ММ-ДД_ЧЧ-ММ-СС.mov`. Кодек и битрейт задаёт настройка `recordingQuality`, применяется перед **каждой** записью:

```
startRecording()                              [main]
  quality = settings.recordingQuality
  sessionQueue:
    applyOutputSettings(quality)
      bitrate = база_1080p × clamp(пиксели/1080p, 0.6…1.0)
      попытки через CPTryObjC (NSException → следующая):
        1. HEVC + AVVideoAverageBitRateKey
        2. H.264 + AVVideoAverageBitRateKey
        3. HEVC без ограничения
        4. H.264 без ограничения          ← единственная у «Максимума»
      → recordingFormatInfo (что сработало)
    movieOutput.startRecording(...)
fileOutput(didFinishRecordingTo:)
  recordedFileSize / recordedDuration → lastRecordingStats «МБ · мм:сс · Мбит/с»
```

| Режим | Видео | 30 мин | В бота 2 ГБ |
|---|---|---|---|
| `economy` | HEVC 2,3 Мбит/с | ≈ 0,6 ГБ | ~108 мин |
| `standard` (по умолчанию) | HEVC 3,5 Мбит/с | ≈ 0,8 ГБ | ~73 мин |
| `max` | H.264 без ограничения | ≈ 3 ГБ | ~20 мин |

⚠️ На macOS нет ни `supportedOutputSettingsKeys(for:)`, ни `availableVideoCodecTypes` — обе только для iOS. Спросить Mac заранее нельзя, поэтому только пробовать под `CPTryObjC`.

---

## 6. Панель суфлёра

Файлы: [PrompterPanelController.swift](../Sources/CamPrompt/PrompterPanelController.swift), [PrompterView.swift](../Sources/CamPrompt/PrompterView.swift).

**Окно.** `ScrollForwardingPanel: NSPanel`, стиль `[.borderless, .nonactivatingPanel]`, `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, `isOpaque = false`, фон прозрачный, `sharingType = .none` при «прятать от записи экрана». `canBecomeKey` переопределён в `true` — иначе поле ввода скорости не получает клавиатуру ([D-014](DECISIONS.md#d-014-панель-может-становиться-key-оставаясь-неактивирующей)).

**Геометрия.**

```
screen        = первый экран с safeAreaInsets.top > 0, иначе главный
menuBarHeight = screenFrame.maxY - visibleFrame.maxY     // полоса меню = зона выреза

режим «под камерой» (pinned):
  height = menuBarHeight + panelTextHeight
  y      = screenFrame.maxY - height        // верх на кромке экрана
  x      = screenFrame.midX - width / 2     // всегда по центру выреза

свободный режим:
  height = panelTextHeight
  y      = screenFrame.maxY - height - menuBarHeight - 8
  окно двигается мышью (isMovableByWindowBackground), позиция не сохраняется
```

Ограничения: ширина 300…ширина экрана, высота текста 80…800 (`PrompterPanelController.minWidth` / `minTextHeight` / `maxTextHeight`).

**Пересоздание против живого ресайза** ([D-010](DECISIONS.md#d-010-живой-ресайз-панели-вместо-пересоздания)): смена `panelPinnedToNotch` или `hideFromScreenCapture` → `AppState.reloadPanelIfVisible()` (стиль окна меняется). Ширина/высота → `AppState.applyPanelGeometry()` → `setFrame`.

**Ресайз за края** ([D-016](DECISIONS.md#d-016-перетаскивание-краёв-перехватывается-в-nspanelsendevent-не-swiftui-жестом)): `sendEvent` перехватывает `leftMouseDown` в зоне 8 точек у левого/правого/нижнего края и сам ведёт перетаскивание, считая смещение в экранных координатах. В pinned-режиме ширина меняется на `dx * 2` (панель остаётся по центру). Настройки пишутся только на `leftMouseUp`. Курсоры ↔ / ↕ ставит `PanelHostingView` через tracking areas с `.activeAlways`.

**Прокрутка колесом.** `scrollWheel` не передаётся дальше, а уходит в `engine.jump(by: -dy)` — текст отматывается пальцами. Точные дельты трекпада идут как есть, «щелчки» мыши умножаются на 10.

**Содержимое (`PrompterView`).**
- `PanelShape` — скруглённый низ в pinned-режиме (верх упирается в кромку экрана), скругление со всех сторон в свободном.
- Верхняя полоса в зоне меню: индикатор записи с таймером слева, кнопка записи справа — чтобы глаза не уходили вниз.
- Текст: одна `Text` со сдвигом `anchorY - engine.offset`, обязателен `.fixedSize(horizontal: false, vertical: true)` ([D-009](DECISIONS.md#d-009-текст--одна-text-нода-со-сдвигом-не-scrollview)). Реальная высота уходит наверх через `ContentHeightKey` (`PreferenceKey`) — по ней движок знает конец текста.
- Линия чтения на `anchorFraction` высоты. Зеркалирование — `scaleEffect(x:y:)` для beam-splitter-ригов.
- Тап по тексту — пауза/пуск.
- Плашка управления (по наведению или пока идёт ввод скорости): пуск/пауза, «с начала», −, поле скорости, +, закрыть. Фон **сплошной тёмный**, не системный материал ([D-015](DECISIONS.md#d-015-фон-плашки-управления--сплошной-тёмный-не-ultrathinmaterial)). Кнопки ± шагают по `PrompterView.hudSpeedStep` = 1 ([D-017](DECISIONS.md#d-017-кнопки--на-плашке-шагают-по-1)).
- Грипы по краям — декорация, перетаскивание идёт мимо SwiftUI.

---

## 7. Прокрутка: `ScrollEngine`

Файл: [ScrollEngine.swift](../Sources/CamPrompt/ScrollEngine.swift).

`Timer` 60 Гц в `RunLoop.common` (иначе встаёт при взаимодействии с интерфейсом). На каждом тике:

    dt = min(now - lastTick, 0.1)          // защита от скачка после сна
    offset += pointsPerSecond * dt          // pointsPerSecond = speed * 3
    offset > contentHeight → луп (offset = -viewportHeight * 0.5) или стоп

Почему не `CVDisplayLink` — [D-008](DECISIONS.md#d-008-прокрутка--timer-60-гц-а-не-cvdisplaylink). `contentHeight` и `viewportHeight` приходят из вью, движок их не вычисляет.

---

## 8. Настройки: ключи `UserDefaults`

Файл: [SettingsStore.swift](../Sources/CamPrompt/SettingsStore.swift). Каждое свойство пишется в `didSet` — отдельного «сохранить» нет.

| Ключ | Тип | По умолчанию | Диапазон в интерфейсе |
|---|---|---|---|
| `fontSize` | Double | 34 | 16…72 |
| `fontName` | String | `System` | список из 11 шрифтов |
| `isBold` | Bool | true | — |
| `textColorHex` | String | `#FFFFFF` | — |
| `bgColorHex` | String | `#000000` | — |
| `bgOpacity` | Double | 0.85 | 0.1…1.0 (показ в %) |
| `lineSpacing` | Double | 8 | 0…30 |
| `horizontalMargin` | Double | 24 | 0…80 |
| `alignment` | Int | 1 (центр) | 0 лево / 1 центр / 2 право |
| `speed` | Double | 20 | 1…100 (точки/с = ×3) |
| `mirrorHorizontal` / `mirrorVertical` | Bool | false | — |
| `loopMode` | Bool | false | — |
| `countdownSeconds` | Int | 3 | 0…10 |
| `showPanelOnRecord` | Bool | true | — |
| `panelWidth` | Double | 700 | 300…1600, обрезается шириной экрана |
| `panelTextHeight` | Double | 190 | 80…800 |
| `panelPinnedToNotch` | Bool | true | пересоздаёт панель |
| `hideFromScreenCapture` | Bool | false | пересоздаёт панель |
| `anchorFraction` | Double | 0.22 | 0.05…0.6 (показ в %) |
| `mirrorPreview` | Bool | true | — |
| `selectedCameraID` / `selectedMicID` | String | `""` (авто) | `uniqueID` устройства |
| `overlayTextOnPreview` | Bool | false | — |
| `recordingsFolder` | String | `downloads` | downloads / documents / movies |
| `recordingQuality` | String | `standard` | economy / standard / max ([D-020](DECISIONS.md#d-020-качество-записи-hevc-с-потолком-битрейта-и-ступенчатый-откат)) |

`recordingsFolder` читается ещё и напрямую из `UserDefaults` в статическом `CaptureManager.recordingsDirectory` — ему нужен путь без экземпляра стора.

**Добавление новой настройки:** свойство с `didSet` → значение по умолчанию в `init` → строка в таблицу выше → элемент в нужный поповер → если влияет на геометрию или стиль панели, повесить `onChange` на `applyPanelGeometry()` или `reloadPanelIfVisible()`.

---

## 9. Хранение скриптов и записей

- **Скрипты** ([ScriptStore.swift](../Sources/CamPrompt/ScriptStore.swift)): массив `Script {id, title, text, updatedAt}` в JSON по пути `~/Library/Application Support/CamPrompt/scripts.json`, атомарная запись на каждое изменение. При первом запуске создаётся приветственный скрипт.
- **Записи** ([RecordingsStore.swift](../Sources/CamPrompt/RecordingsStore.swift)): не база, а чтение каталога — `.mov` с датой и размером, сортировка по дате. Открытие и «Показать в Finder» через `NSWorkspace`.

---

## 10. Клавиатура

Локальный монитор `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` в `AppDelegate`, обработчик — `AppState.handleKeyDown`.

Гарды по порядку:
1. Идёт ввод текста (`firstResponder` — `NSTextView` или `NSTextField`) → не вмешиваемся. Источник — **`event.window?.firstResponder`**, потому что `NSApp.keyWindow` равен `nil`, пока приложение неактивно, а панель при этом key ([D-014](DECISIONS.md#d-014-панель-может-становиться-key-оставаясь-неактивирующей)).
2. Панель не видна и записи нет → не вмешиваемся.
3. Зажат ⌘/⌥/⌃ → отдаём системе (меню-команды).

Клавиши: `Пробел` пауза/пуск · `R` с начала · `↑/↓` скорость ±5 · `←/→` перемотка ±150 точек · `Esc` скрыть панель.

Ограничение: работает только когда CamPrompt активен ([RISKS](RISKS.md) §5).

---

## 11. Карта файлов

| Файл | Роль | ~строк |
|---|---|---|
| [CamPromptApp.swift](../Sources/CamPrompt/CamPromptApp.swift) | `@main`, сцены, меню, `AppDelegate` | 60 |
| [AppState.swift](../Sources/CamPrompt/AppState.swift) | координатор, сценарий записи, клавиатура | 215 |
| [CaptureManager.swift](../Sources/CamPrompt/CaptureManager.swift) | устройства, разрешения, сессия, качество записи с откатом, запись, диагностика | 430 |
| [PrompterPanelController.swift](../Sources/CamPrompt/PrompterPanelController.swift) | `NSPanel`, геометрия, ресайз за края, курсоры | 260 |
| [PrompterView.swift](../Sources/CamPrompt/PrompterView.swift) | текст, линия чтения, плашка, грипы, `PanelShape` | 290 |
| [MainWindowView.swift](../Sources/CamPrompt/MainWindowView.swift) | сайдбар, редактор, превью, кнопки, баннер ошибки | 330 |
| [SettingsPopovers.swift](../Sources/CamPrompt/SettingsPopovers.swift) | `NumberSliderRow` + три поповера | 260 |
| [SettingsStore.swift](../Sources/CamPrompt/SettingsStore.swift) | 26 настроек, `RecordingQuality`, hex-цвета | 210 |
| [ScrollEngine.swift](../Sources/CamPrompt/ScrollEngine.swift) | таймер 60 Гц, смещение, луп | 70 |
| [ScriptStore.swift](../Sources/CamPrompt/ScriptStore.swift) | библиотека скриптов в JSON | 75 |
| [RecordingsStore.swift](../Sources/CamPrompt/RecordingsStore.swift) | список записей, Finder | 55 |
| [CameraPreviewView.swift](../Sources/CamPrompt/CameraPreviewView.swift) | `AVCaptureVideoPreviewLayer` в SwiftUI | 50 |

Objective-C: [ObjCExceptionCatcher](../Sources/ObjCExceptionCatcher/) — отдельная цель SwiftPM, одна функция `CPTryObjC`, превращает `NSException` в `NSError` (Swift такие исключения не ловит).

Вне кода: [Package.swift](../Package.swift) (SwiftPM, macOS 14, две цели, без внешних зависимостей), [Resources/Info.plist](../Resources/Info.plist) (bundle id `ru.olya.camprompt`, тексты TCC), [Resources/icon_1024.png](../Resources/icon_1024.png), [scripts/build_app.sh](../scripts/build_app.sh), [.github/workflows/build.yml](../.github/workflows/build.yml), `refs/` (клоны MIT-референсов, в `.gitignore`).

---

## 12. Сборка и выпуск

Собрать приложение можно **только на macOS-раннере GitHub Actions** — среда разработки Linux ([D-006](DECISIONS.md#d-006-сборка-только-на-macos-раннере-github-actions)).

```
git push origin main
  └─ .github/workflows/build.yml на macos-15
       └─ scripts/build_app.sh <версия>
            swift build -c release
            собрать CamPrompt.app вручную (Info.plist с версией,
              .icns через sips + iconutil)
            codesign --force --deep --sign -        ← ad-hoc, D-007
            hdiutil create … CamPrompt-<версия>.dmg
       └─ артефакт CamPrompt-dmg

git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z
  └─ тот же workflow + softprops/action-gh-release → GitHub Release с .dmg
```

Версия на пуше в main — `0.0.0-dev.<номер прогона>`; на теге — из тега. Время прогона ~45 секунд.

**Чек-лист выпуска:**
1. Правки → пуш в `main` → `gh run watch <id> --exit-status`.
2. Обновить [CHANGELOG](../CHANGELOG.md) и, если решение новое, [DECISIONS](DECISIONS.md).
3. Тег `vX.Y.Z` → пуш тега → дождаться Release.
4. Отдать пользователю ссылку + напомнить про `xattr` и запуск из `/Applications`.
5. Назвать, **что проверить руками** — CI поведение не проверяет.

---

## 13. Ограничения и компромиссы

| Что | Почему | Где подробно |
|---|---|---|
| Внутри выреза нет пикселей | Физика матрицы — текст «в» вырезе невозможен | [RISKS](RISKS.md) §1 |
| Нужна команда `xattr` после каждого обновления | Нет нотарификации | [D-007](DECISIONS.md#d-007-ad-hoc-подпись--xattr-пока-нет-apple-developer) |
| Хоткеи только при активном приложении | Локальный монитор событий | [RISKS](RISKS.md) §5 |
| Нет паузы записи и фильтров | `MovieFileOutput` вместо `AVAssetWriter` | [D-004](DECISIONS.md#d-004-запись-через-avcapturemoviefileoutput-не-avassetwriter) |
| Панель перекрывает меню в своей зоне | Следствие уровня `.screenSaver` | [RISKS](RISKS.md) §1 |
| Позиция панели в свободном режиме не сохраняется | Не сделано; сохраняются только размеры | [DEV_PLAN](DEV_PLAN.md) M5 |
| Поведение проверяется только руками | Нет живого Mac в цикле | [RISKS](RISKS.md) §2 |
| Переключение камеры во время записи не блокируется | Известная дыра v0.1 | [RISKS](RISKS.md) §2 |

---

## 14. Путь к v2

Порядок — по ценности для съёмок: прокрутка за голосом (`SFSpeechRecognizer`, порт из Textream), нотарификация и Sparkle, пауза записи и склейка сегментов (`AVAssetWriter`), сглаживание кожи и виртуальный фон (Core Image + Vision), глобальные хоткеи, пульт с iPhone. Оценки — [DEV_PLAN](DEV_PLAN.md).
