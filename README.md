# TalorianTP

Аддон для **WoW Prime (3.3.5a)** — быстрый призыв спутника Талориана, расстановка рейд-метки, авто-телепорт к целям и навигация по госсип-меню.

## Установка в клиент WoW 3.3.5a

Скопируйте репозиторий прямо в папку аддонов под именем `TalorianTP`:

```powershell
cd "<ПУТЬ_К_WOW>\Interface\AddOns"
git clone https://github.com/Soodoqie/TalorianTP.git TalorianTP
```

Или распакуйте ZIP-архив так, чтобы внутри `Interface\AddOns\TalorianTP\` лежали `TalorianTP.toc`, `TalorianTP.lua`, `TalorianLootDB.lua` и `Bindings.xml`.

## Основные команды

- `/ttp` — открыть окно настроек и управления Талорианом
- `/ttp minimap` — переключить кнопку на миникарте
- `/ttp status` — вывести текущий статус

## Опциональные зависимости

Указаны в `TalorianTP.toc` как `OptionalDeps` (`AttuneParser`, `AttuneAtlas`, `WCollections`, `PrimeAttuneCore`, `PrimeAuctionHouse`) — аддон работает полностью автономно, а при наличии `AttuneParser` интегрируется с ним автоматически.
