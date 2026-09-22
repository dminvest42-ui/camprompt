# Онбординг: CamPrompt за 15 минут

Точка входа для нового разработчика или ИИ-агента. Прочитав это и ссылки по порядку, можно работать без обращения к истории переписки.

---

## 1. Что это

**CamPrompt** — нативное macOS-приложение: телесуфлёр, у которого текст едет **под вырезом камеры MacBook**, плюс запись видео и звука внутри того же приложения. Глаза остаются в объективе, второй инструмент для записи не нужен.

Инструмент личный: один пользователь, интерфейс русский, сети и телеметрии в приложении нет.

- Репозиторий: `dminvest42-ui/camprompt` (публичный — ради бесплатных macOS-раннеров).
- Рабочая копия на сервере: `~/projects/teleprompter/`.
- Стек: Swift 5.9+, SwiftUI + AppKit, AVFoundation, SwiftPM, **ноль внешних зависимостей**.
- Требование: macOS 14 (Sonoma)+.

---

## 2. Главное, что ломает новичка

**Собрать приложение локально нельзя.** Среда разработки — Linux (`kd-dev`), swift-тулчейна для macOS там нет. Единственная сборка — macOS-раннер GitHub Actions, ~45 секунд на прогон. Компиляция при этом — **единственная** автоматическая проверка: геометрию панели, TCC, цвета, фокус ввода и реальные камеры проверяет только человек на живом Mac.

Отсюда стиль работы: консервативные правки, паттерны с проверенных MIT-проектов, каждая правка сопровождается явным списком «что проверить руками». Подробности — [DECISIONS D-006](DECISIONS.md#d-006-сборка-только-на-macos-раннере-github-actions), [RISKS §2](RISKS.md).

---

## 3. Порядок чтения

| # | Файл | Зачем | Время |
|---|---|---|---|
| 1 | [CLAUDE.md](../CLAUDE.md) | Правила работы в репозитории: сборка, git, что нельзя | 3 мин |
| 2 | этот файл | Карта и контекст | 3 мин |
| 3 | [ARCHITECTURE](ARCHITECTURE.md) | Слои, точки входа, сценарий записи, геометрия панели, ключи настроек, карта файлов | 10 мин |
| 4 | [DECISIONS](DECISIONS.md) | Почему сделано именно так; инциденты и правила из них | 10 мин |
| 5 | [CHANGELOG](../CHANGELOG.md) | Что менялось по версиям | 3 мин |
| 6 | [TROUBLESHOOTING](TROUBLESHOOTING.md) | Симптом → причина → что делать; как отлаживать без Mac | по нужде |
| 7 | [RISKS](RISKS.md) | Ограничения macOS, чек-лист приёмки (16 пунктов) | 5 мин |
| 8 | [DEV_PLAN](DEV_PLAN.md) | Вехи M0–M6, что сделано, что дальше | 3 мин |
| 9 | [RESEARCH](RESEARCH.md) | Обзор рынка и техническая разведка июля 2026 | по нужде |

Разбираешь конкретную проблему — начинай с [TROUBLESHOOTING](TROUBLESHOOTING.md), он отправит в нужное решение.

---

## 4. Пять граблей, на которых уже спотыкались

1. **`sessionPreset` — после добавления входов.** У пустой `AVCaptureSession` любой пресет «поддерживается»; камера 720p потом молча отклоняется. Так на одном из маков была чёрная камера и запись без картинки. [D-011](DECISIONS.md#d-011-sessionpreset-выставляется-после-добавления-входов)
2. **`Slider(step:)` на macOS рисует засечку на каждый шаг.** 1300 засечек на диапазон ширины — поповер открывается секунды. Шаг — в `Binding`. [D-013](DECISIONS.md#d-013-шаг-ползунка--в-binding-а-не-в-sliderstep)
3. **`Text` фиксированной высоты обрезает себя многоточием** и не едет. Всегда `.fixedSize(horizontal: false, vertical: true)`. [D-009](DECISIONS.md#d-009-текст--одна-text-нода-со-сдвигом-не-scrollview)
4. **Системные материалы и `Color.primary` внутри панели запрещены.** `.ultraThinMaterial` в светлой теме белеет, белые иконки пропадают. Цвета панели задаёт пользователь. [D-015](DECISIONS.md#d-015-фон-плашки-управления--сплошной-тёмный-не-ultrathinmaterial)
5. **Borderless-панель не становится key** — поле ввода в ней мертво, пока не переопределён `canBecomeKey`. И гард клавиатуры должен смотреть `event.window?.firstResponder`, а не `NSApp.keyWindow`. [D-014](DECISIONS.md#d-014-панель-может-становиться-key-оставаясь-неактивирующей)

---

## 5. Первый цикл правки

```bash
cd ~/projects/teleprompter
# 1. правка в Sources/CamPrompt/…
# 2. коммит (почта обязательна, иначе GitHub отклонит пуш)
git add -A
git -c user.email=dminvest42-ui@users.noreply.github.com -c user.name=Olya \
    commit -m "что и почему"
git push origin main
# 3. дождаться сборки
gh run list -R dminvest42-ui/camprompt --limit 1
gh run watch <id> -R dminvest42-ui/camprompt --exit-status
# 4. предупреждения компилятора из зелёной сборки
gh run view <id> -R dminvest42-ui/camprompt --log | grep -E 'warning:|error:' | grep -v Node.js
```

Выпуск версии:

```bash
# обновить CHANGELOG.md (+ DECISIONS.md, если решение новое)
git tag -a v0.2.3 -m "CamPrompt v0.2.3" && git push origin v0.2.3
gh release view v0.2.3 -R dminvest42-ui/camprompt --json tagName,assets
```

Что сказать пользователю: ссылка на релиз, «перетащить в Программы с заменой», команда `xattr` (нужна после **каждого** обновления), «запускать из Программ», список «что проверить».

---

## 6. Где что лежит

```
~/projects/teleprompter/
├── CLAUDE.md              ← правила работы в репозитории (читать первым)
├── README.md              ← для пользователя: возможности, установка, диагностика
├── CHANGELOG.md           ← история версий
├── Package.swift          ← SwiftPM, macOS 14, без зависимостей
├── Sources/CamPrompt/     ← весь код, 12 файлов (карта — ARCHITECTURE §11)
├── Resources/             ← Info.plist (bundle id, тексты TCC), иконка
├── scripts/build_app.sh   ← .app + .icns + ad-hoc подпись + .dmg
├── scripts/check_docs_links.py ← проверка ссылок и якорей в докумен­тации
├── .github/workflows/     ← build.yml (macos-15)
├── docs/                  ← AGENT_ONBOARDING, ARCHITECTURE, DECISIONS,
│                            TROUBLESHOOTING, RISKS, DEV_PLAN, RESEARCH
└── refs/                  ← клоны MIT-референсов (в .gitignore, не коммитятся)
```
