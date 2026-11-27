# TalorianTP

Аддон для **WoW Prime (3.3.5a)** — быстрый призыв спутника Талориана, расстановка рейд-метки, авто-телепорт к целям и навигация по госсип-меню.

## Скачать и установить (Releases)

Самый простой способ установки для игры:

1. Откройте страницу последнего релиза: https://github.com/Soodoqie/TalorianTP/releases/latest
2. Скачайте готовый архив **`TalorianTP-v*.zip`** (не `Source code`).
3. Распакуйте его в `<ПУТЬ_К_WOW>\Interface\AddOns\` — внутри уже есть папка `TalorianTP/` со всеми нужными файлами.
4. Перезапустите клиент или выполните `/reload` в игре.

Либо клонируйте напрямую через Git:

```powershell
cd "<ПУТЬ_К_WOW>\Interface\AddOns"
git clone https://github.com/Soodoqie/TalorianTP.git TalorianTP
```

## Основные команды

- `/ttp` — открыть окно настроек и управления Талорианом
- `/ttp minimap` — переключить кнопку на миникарте
- `/ttp status` — вывести текущий статус

## Как выпускать новые релизы

1. Обновите `## Version` в `TalorianTP.toc` и добавьте описание изменений в [CHANGELOG.md](./CHANGELOG.md).
2. Закоммитьте и отправьте изменения в `main`.
3. Создайте тег (например, `git tag v4.3 && git push origin v4.3`) или опубликуйте релиз через GitHub UI / `gh release create` — workflow [release.yml](./.github/workflows/release.yml) автоматически соберет чистый архив `TalorianTP-<tag>.zip` и прикрепит его к релизу.

## Опциональные зависимости

Указаны в `TalorianTP.toc` как `OptionalDeps` (`AttuneParser`, `AttuneAtlas`, `WCollections`, `PrimeAttuneCore`, `PrimeAuctionHouse`) — аддон работает полностью автономно, а при наличии `AttuneParser` интегрируется с ним автоматически.
