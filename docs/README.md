# Документы проекта

Указатель. Источник правды — код и история git; документ, разошедшийся с кодом, правится тем же коммитом.

## С чего начать

1. [WHERE_WE_ARE.md](WHERE_WE_ARE.md) — что сделано, что дальше, окружение.
2. [CONCEPT.md](CONCEPT.md) — что строим и чего не строим.
3. [ARCHITECTURE.md](ARCHITECTURE.md) — как устроено.

## Что строим

| Документ | О чём |
|---|---|
| [CONCEPT.md](CONCEPT.md) | замысел, читатель, состав функций, «Чего не делаем» |
| [ARCHITECTURE.md](ARCHITECTURE.md) | модули и их зависимости, модель книги, раскладка страниц, озвучка, хранение, замеры |
| [specs/001-first-version.md](specs/001-first-version.md) | спека первой версии: решения, требования по этапам, критерии приёмки, журнал решений (Changelog) |
| [GEMINI_TTS.md](GEMINI_TTS.md) | форма запроса к Gemini TTS, голоса, тарифы, замеры задержки |
| [GOOGLE_PLAY_PLAN.md](GOOGLE_PLAY_PLAN.md) | планы на потом: публикация в Google Play и платный сервис; не решение |

## Как выглядит

| Документ | О чём |
|---|---|
| [prototype/README.md](prototype/README.md) | прототип экранов на Flutter — он задаёт вид; запуск, жесты, палитра, снимки |
| [mockup/](mockup/) | статический макет: справка по составу экранов и текстам, не эталон вида |
| [logo.svg](logo.svg) | знак приложения; те же контуры — в значке Android |

## Как проверяем

| Документ | О чём |
|---|---|
| [DEVICE_CHECKLIST.md](DEVICE_CHECKLIST.md) | ручная проверка на телефоне: фон, экран блокировки, гарнитура, звонок |
| [CODEX_INDEPENDENT_REVIEW.md](CODEX_INDEPENDENT_REVIEW.md) | как запускать независимое ревью |

## Ревью и проверки (`reviews/`)

Записи того, что было найдено и что с этим сделано. Источником правды не служат.

| Запись | Что проверялось |
|---|---|
| [CODEX_REVIEW_ARCH_2026-11-14.md](reviews/CODEX_REVIEW_ARCH_2026-11-14.md) | архитектура |
| [CODEX_REVIEW_SPEC_2026-11-14.md](reviews/CODEX_REVIEW_SPEC_2026-11-14.md) | спека первой версии |
| [CODEX_REVIEW_MOCKUP_2026-11-14.md](reviews/CODEX_REVIEW_MOCKUP_2026-11-14.md) | статический макет |
| [CODEX_REVIEW_PROTOTYPE_2026-11-14.md](reviews/CODEX_REVIEW_PROTOTYPE_2026-11-14.md) | прототип экранов |
| [CODEX_REVIEW_LOGIC_2026-11-14.md](reviews/CODEX_REVIEW_LOGIC_2026-11-14.md) | логика экранов прототипа |
| [JOURNEY_AUDIT_2026-11-14.md](reviews/JOURNEY_AUDIT_2026-11-14.md) | пути пользователя |
| [GESTURE_AUDIT_2026-11-14.md](reviews/GESTURE_AUDIT_2026-11-14.md) | жесты |
| [FABLE_REVIEW_001_STAGE1_2026-11-15.md](reviews/FABLE_REVIEW_001_STAGE1_2026-11-15.md) | код этапа 1 «Читалка» |
| [FABLE_REVIEW_001_STAGE2_2026-11-15.md](reviews/FABLE_REVIEW_001_STAGE2_2026-11-15.md) | код этапа 2 «Озвучка» |
| [FABLE_REVIEW_001_NAV_TXT_2026-11-15.md](reviews/FABLE_REVIEW_001_NAV_TXT_2026-11-15.md) | переходы по абзацам, возврат страницы, TXT |
| [EXPERIMENT_CODEX_IMPL.md](reviews/EXPERIMENT_CODEX_IMPL.md) | журнал эксперимента: код пишут агенты Codex, принимает оркестратор |

## Правила именования

- Спека — `specs/NNN-<slug>.md`; в ней решения, требования, приёмка, «Не делаем», Changelog.
- Запись ревью — `reviews/<КТО>_REVIEW_<что>_<дата>.md`.
- Решение владельца записывается в спеку или концепцию в тот же день, с датой.
