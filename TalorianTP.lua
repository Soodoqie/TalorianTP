--[[
    TalorianTP v4.3.2 (WoW Prime)
    Автоматический телепорт и помощник спутника Талориана.
    Полная поддержка кириллицы UTF-8, навигации по госсип-меню WoW Prime,
    модульной настройки блоков UI, базы предметов TalorianLootDB и интеграции с AttuneParser.
]]--

TalorianTP = {}
TalorianTP_DB = TalorianTP_DB or {}

local TALORIAN_VERSION = "4.3.2"
TalorianTP.VERSION = TALORIAN_VERSION
local MAIN_W = 896
local ADDON_PREFIX = "|cff38bdf8[Talorian]|r "
local mainUI = nil
local noticeFrame = nil
local isTeleporting = false
local confirmTimer = 0
local ICON_DIAMOND = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t"
local targetPollTimer = 0
local targetPollElapsed = 0

local raiseQueue = {}
local raiseDriver = CreateFrame("Frame")
raiseDriver:Hide()
raiseDriver:SetScript("OnUpdate", function(self)
    self:Hide()
    for fr in pairs(raiseQueue) do
        raiseQueue[fr] = nil
        if fr and fr:IsShown() and type(fr.Raise) == "function" then
            pcall(fr.Raise, fr)
        end
    end
end)

local function RaiseFrameFront(fr)
    if not fr then return end
    if type(fr.Raise) == "function" then pcall(fr.Raise, fr) end
    raiseQueue[fr] = true
    raiseDriver:Show()
end
TalorianTP.RaiseFrameFront = RaiseFrameFront

BINDING_HEADER_TALORIAN_HEADER = "TalorianTP"
BINDING_NAME_TALORIAN_TP_CURRENT = "Призвать и пометить Талориана"
BINDING_NAME_TALORIAN_TP_ICC = "Цель: Цитадель Ледяной Короны"
BINDING_NAME_TALORIAN_TP_TOC = "Цель: Испытание крестоносца"
BINDING_NAME_TALORIAN_TP_RS = "Цель: Рубиновое святилище"
BINDING_NAME_TALORIAN_TP_NAXX = "Цель: Наксрамас"
BINDING_NAME_TALORIAN_RESET_CD = "Сбросить все КД (.in un all)"
BINDING_NAME_TALORIAN_MODE_BUFF = "Режим: Баффер"
BINDING_NAME_TALORIAN_MODE_BANK = "Режим: Банк"

---------------------------------------------------------------------------
-- UTF-8 Кириллица и нормализация строк
---------------------------------------------------------------------------
local function TalorianTP_ULower(s)
    if not s or s == "" then return "" end
    local res = {}
    local len = #s
    local i = 1
    while i <= len do
        local b1 = s:byte(i)
        if b1 == 0xD0 and i < len then
            local b2 = s:byte(i + 1)
            if b2 == 0x81 then -- Ё -> е
                table.insert(res, "\208\181")
                i = i + 2
            elseif b2 >= 0x90 and b2 <= 0x9F then -- А-П -> а-п
                table.insert(res, string.char(0xD0, b2 + 0x20))
                i = i + 2
            elseif b2 >= 0xA0 and b2 <= 0xAF then -- Р-Я -> р-я
                table.insert(res, string.char(0xD1, b2 - 0x20))
                i = i + 2
            else
                table.insert(res, string.char(b1, b2))
                i = i + 2
            end
        elseif b1 == 0xD1 and i < len then
            local b2 = s:byte(i + 1)
            if b2 == 0x91 then -- ё -> е
                table.insert(res, "\208\181")
                i = i + 2
            else
                table.insert(res, string.char(b1, b2))
                i = i + 2
            end
        elseif b1 >= 65 and b1 <= 90 then -- A-Z -> a-z
            table.insert(res, string.char(b1 + 32))
            i = i + 1
        else
            table.insert(res, string.char(b1))
            i = i + 1
        end
    end
    return table.concat(res)
end

local function TalorianTP_Norm(s)
    if not s then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    s = TalorianTP_ULower(s)
    s = s:gsub("[^%a\128-\255%d]", " ")
    s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

---------------------------------------------------------------------------
-- База рейдов (23): 100% проверенные иконки MPQ
---------------------------------------------------------------------------
local RAID_DESTS = {
    -- WotLK (9)
    { name = "Цитадель Ледяной Короны", short = "ЦЛК", exp = "WotLK", isRaid = true, achieve = 4531, attune = 4812, icon = "Achievement_Boss_LichKing", aliases = {"цитадель ледяной короны", "цлк"} },
    { name = "Испытание крестоносца",   short = "ИК",  exp = "WotLK", isRaid = true, achieve = 3917, attune = 4722, icon = "Achievement_Reputation_ArgentCrusader", aliases = {"испытание крестоносца", "ик"} },
    { name = "Рубиновое святилище",     short = "РС",  exp = "WotLK", isRaid = true, achieve = 4817, attune = 4987, icon = "Spell_Shadow_Twilight", aliases = {"рубиновое святилище", "рс"} },
    { name = "Наксрамас",               short = "Накс",exp = "WotLK", isRaid = true, achieve = 576,  attune = 3456, icon = "Achievement_Dungeon_Naxxramas_Normal", aliases = {"наксрамас", "накс"} },
    { name = "Ульдуар",                 short = "Ульд",exp = "WotLK", isRaid = true, achieve = 2894, attune = 4273, icon = "Achievement_Dungeon_UlduarRaid_Misc_01", aliases = {"ульдуар", "ульд"} },
    { name = "Склеп Аркавона",          short = "СА",  exp = "WotLK", isRaid = true, achieve = 1722, attune = 4603, icon = "INV_Misc_Statue_07", aliases = {"склеп аркавона", "са"} },
    { name = "Око Вечности",            short = "Око", exp = "WotLK", isRaid = true, achieve = 1877, attune = 4500, icon = "Achievement_Boss_Malygos_01", aliases = {"око вечности", "малигос"} },
    { name = "Обсидиановое святилище",  short = "ОС",  exp = "WotLK", isRaid = true, achieve = 1876, attune = 4493, icon = "Achievement_Boss_Sartharion_01", aliases = {"обсидиановое святилище", "сартарион", "ос"} },
    { name = "Логово Ониксии",          short = "Оня", exp = "WotLK", isRaid = true, achieve = 4396, attune = 2159, icon = "Achievement_Boss_Onyxia", aliases = {"логово ониксии", "ониксия", "оня"} },

    -- The Burning Crusade (9)
    { name = "Плато Солнечного Колодца", short = "СП", exp = "TBC", isRaid = true, achieve = 698, attune = 4075, icon = "Achievement_Boss_Kiljaedan", aliases = {"плато солнечного колодца", "санвелл", "сп"} },
    { name = "Черный храм",              short = "БТ", exp = "TBC", isRaid = true, achieve = 697, attune = 3959, icon = "Achievement_Boss_Illidan", aliases = {"черный храм", "бт", "иллидан"} },
    { name = "Вершина Хиджала",          short = "Хиджал", exp = "TBC", isRaid = true, achieve = 695, attune = 3606, icon = "INV_Offhand_Hyjal_D_01", aliases = {"вершина хиджала", "хиджал"} },
    { name = "Зул'Аман",                 short = "ЗА", exp = "TBC", isRaid = true, achieve = 691, attune = 3805, icon = "Achievement_Boss_Zuljin", aliases = {"зул аман", "за", "зуламан"} },
    { name = "Око (Крепость Бурь)",     short = "ТК", exp = "TBC", isRaid = true, achieve = 696, attune = 3845, icon = "Achievement_Boss_Kael'thasSunstrider_01", aliases = {"око", "крепость бурь", "кельтас", "тк"} },
    { name = "Змеиное святилище",       short = "ССК", exp = "TBC", isRaid = true, achieve = 694, attune = 3607, icon = "Achievement_Boss_LadyVashj", aliases = {"змеиное святилище", "вайши", "сск"} },
    { name = "Логово Груула",            short = "Груул", exp = "TBC", isRaid = true, achieve = 692, attune = 3923, icon = "Achievement_Boss_GruulTheDragonkiller", aliases = {"логово груула", "груул"} },
    { name = "Логово Магтеридона",       short = "Магтер", exp = "TBC", isRaid = true, achieve = 693, attune = 3836, icon = "Achievement_Boss_Magtheridon", aliases = {"логово магтеридона", "магтеридон", "магтер"} },
    { name = "Каражан",                  short = "Кара", exp = "TBC", isRaid = true, achieve = 690, attune = 3457, icon = "Achievement_Boss_PrinceMalchezaar_02", aliases = {"каражан", "кара"} },

    -- Classic (5)
    { name = "Храм Ан'Киража",           short = "АК40", exp = "Classic", isRaid = true, achieve = 687, attune = 3428, icon = "Achievement_Boss_CThun", aliases = {"храм ан киража", "ан кираж 40", "ак40", "ктун"} },
    { name = "Руины Ан'Киража",          short = "АК20", exp = "Classic", isRaid = true, achieve = 689, attune = 3429, icon = "Achievement_Boss_OssirianTheUnscarred", aliases = {"руины ан киража", "ан кираж 20", "ак20", "оссириан"} },
    { name = "Логово Крыла Тьмы",        short = "БВЛ", exp = "Classic", isRaid = true, achieve = 685, attune = 2677, icon = "Achievement_Boss_Nefarion", aliases = {"логово крыла тьмы", "бвл", "нефариан"} },
    { name = "Огненные Недра",           short = "МС", exp = "Classic", isRaid = true, achieve = 686, attune = 2717, icon = "Achievement_Boss_Ragnaros", aliases = {"огненные недра", "мс", "рагнарос"} },
    { name = "Зул'Гуруб",                short = "ЗГ", exp = "Classic", isRaid = true, achieve = 688, attune = 1977, icon = "Achievement_Boss_Hakkar", aliases = {"зул гуруб", "зг", "зулгуруб", "хаккар"} },
}

---------------------------------------------------------------------------
-- Подземелья (52): WotLK (16), TBC (16), Vanilla (20)
---------------------------------------------------------------------------
local DUNGEONS_WOTLK = {
    { name = "Азжол-Неруб",                 short = "АН",   exp = "WotLK", isRaid = false, achieve = 480,  attune = 4277, icon = "Achievement_Dungeon_AzjolLowercity_Normal", aliases = {"азжол неруб"} },
    { name = "Ан'кахет: Старое Королевство", short = "АК",  exp = "WotLK", isRaid = false, achieve = 481,  attune = 4494, icon = "Achievement_Dungeon_AzjolUppercity_Normal", aliases = {"ан кахет", "старое королевство", "анкахет", "ак"} },
    { name = "Крепость Утгард",             short = "КУ",   exp = "WotLK", isRaid = false, achieve = 477,  attune = 206,  icon = "Achievement_Dungeon_UtgardeKeep_Normal", aliases = {"крепость утгард", "утгард крепость", "ку"} },
    { name = "Вершина Утгард",              short = "ВУ",   exp = "WotLK", isRaid = false, achieve = 488,  attune = 1196, icon = "Achievement_Dungeon_UtgardePinnacle_Normal", aliases = {"вершина утгард", "утгард вершина", "ву"} },
    { name = "Гундрак",                     short = "Гун",  exp = "WotLK", isRaid = false, achieve = 484,  attune = 4416, icon = "Achievement_Dungeon_Gundrak_Normal", aliases = {"гундрак", "гун"} },
    { name = "Драк'Тарон",                  short = "ДТ",   exp = "WotLK", isRaid = false, achieve = 482,  attune = 4196, icon = "Achievement_Dungeon_Drak'Tharon_Normal", aliases = {"драк тарон", "крепость драк тарон", "дт"} },
    { name = "Залы Молний",                 short = "ЗМ",   exp = "WotLK", isRaid = false, achieve = 486,  attune = 4272, icon = "Achievement_Dungeon_Ulduar80_Normal", aliases = {"залы молний", "чертоги молний", "зм", "чм"} },
    { name = "Чертоги Камня",               short = "ЧК",   exp = "WotLK", isRaid = false, achieve = 485,  attune = 4264, icon = "Achievement_Dungeon_Ulduar77_Normal", aliases = {"чертоги камня", "залы камня", "чк"} },
    { name = "Залы Отражений",              short = "ЗО",   exp = "WotLK", isRaid = false, achieve = 4520, attune = 4820, icon = "Achievement_Dungeon_Icecrown_HallsofReflection", aliases = {"залы отражений", "зо", "кузня яма залы отражений"} },
    { name = "Кузня Душ",                   short = "КД",   exp = "WotLK", isRaid = false, achieve = 4516, attune = 4809, icon = "Achievement_Dungeon_Icecrown_ForgeofSouls", aliases = {"кузня душ", "кд", "кузня яма залы отражений"} },
    { name = "Яма Сарона",                  short = "ЯС",   exp = "WotLK", isRaid = false, achieve = 4518, attune = 4813, icon = "Achievement_Dungeon_Icecrown_PitofSaron", aliases = {"яма сарона", "яс", "кузня яма залы отражений"} },
    { name = "Испытание Чемпиона",          short = "ИЧ",   exp = "WotLK", isRaid = false, achieve = 4296, attune = 4723, icon = "Achievement_Reputation_ArgentCrusader", aliases = {"испытание чемпиона", "ич"} },
    { name = "Нексус",                      short = "Некс", exp = "WotLK", isRaid = false, achieve = 478,  attune = 4265, icon = "Achievement_Dungeon_Nexus70_Normal", aliases = {"нексус", "нексус и окулус"} },
    { name = "Окулус",                      short = "Окул", exp = "WotLK", isRaid = false, achieve = 487,  attune = 4228, icon = "Achievement_Dungeon_Nexus80_Normal", aliases = {"окулус", "нексус и окулус"} },
    { name = "Очищение Стратхольма",        short = "Страт",exp = "WotLK", isRaid = false, achieve = 479,  attune = 4100, icon = "Achievement_Dungeon_CoTStratholme_Normal", aliases = {"очищение стратхольма", "пещеры времени стратхольм"} },
    { name = "Аметистовая крепость",        short = "АКр",  exp = "WotLK", isRaid = false, achieve = 483,  attune = 4415, icon = "Achievement_Dungeon_TheVioletHold_Normal", aliases = {"аметистовая крепость", "акр"} },
}

local DUNGEONS_TBC = {
    { name = "Бастионы Адского Пламени",     short = "БАП", exp = "TBC", isRaid = false, achieve = 647, attune = 3562, icon = "Achievement_Boss_OmarTheUnscarred_01", aliases = {"бастионы адского пламени", "бастионы", "бап"} },
    { name = "Кузня Крови",                 short = "КК",  exp = "TBC", isRaid = false, achieve = 648, attune = 3713, icon = "Achievement_Boss_KelidanTheBreaker", aliases = {"кузня крови", "кк"} },
    { name = "Разрушенные залы",            short = "РЗ",  exp = "TBC", isRaid = false, achieve = 649, attune = 3714, icon = "Achievement_Boss_KargathBladefist_01", aliases = {"разрушенные залы", "рз"} },
    { name = "Узилище",                     short = "Уз",  exp = "TBC", isRaid = false, achieve = 650, attune = 3717, icon = "Achievement_Boss_Quagmirran", aliases = {"узилище", "уз"} },
    { name = "Нижетопь",                    short = "НТ",  exp = "TBC", isRaid = false, achieve = 651, attune = 3716, icon = "Achievement_Boss_TheBlackStalker", aliases = {"нижетопь", "нт"} },
    { name = "Паровое подземелье",          short = "ПП",  exp = "TBC", isRaid = false, achieve = 652, attune = 3715, icon = "Achievement_Boss_Warlord_Kalithresh", aliases = {"паровое подземелье", "парник", "пп"} },
    { name = "Гробницы Маны",               short = "ГМ",  exp = "TBC", isRaid = false, achieve = 653, attune = 3792, icon = "Achievement_Boss_Nexus_Prince_Shaffar", aliases = {"гробницы маны", "гм"} },
    { name = "Аукенайские гробницы",        short = "Аук", exp = "TBC", isRaid = false, achieve = 654, attune = 3790, icon = "Achievement_Boss_Exarch_Maladaar", aliases = {"аукенайские гробницы", "аукенай", "аук"} },
    { name = "Сетеккские залы",             short = "Сетек",exp = "TBC", isRaid = false, achieve = 655, attune = 3791, icon = "Achievement_Boss_TalonKingIkiss", aliases = {"сетеккские залы", "сетекк", "сетекки"} },
    { name = "Темный лабиринт",             short = "ТЛ",  exp = "TBC", isRaid = false, achieve = 656, attune = 3789, icon = "Achievement_Boss_Murmur", aliases = {"темный лабиринт", "лабиринт", "тл"} },
    { name = "Старые предгорья Хилсбрада",  short = "ПВ1", exp = "TBC", isRaid = false, achieve = 657, attune = 2367, icon = "Achievement_Boss_EpochHunter", aliases = {"старые предгорья хилсбрада", "предгорья хилсбрада", "дарнхольд", "побег из дарнхольда", "пв1"} },
    { name = "Черные топи",                 short = "ЧТ",  exp = "TBC", isRaid = false, achieve = 658, attune = 2366, icon = "Achievement_Boss_Aeonus_01", aliases = {"черные топи", "открытие темного портала", "чт"} },
    { name = "Ботаника",                    short = "Бот", exp = "TBC", isRaid = false, achieve = 659, attune = 3847, icon = "Achievement_Boss_WarpSplinter", aliases = {"ботаника", "бот"} },
    { name = "Механар",                     short = "Мех", exp = "TBC", isRaid = false, achieve = 660, attune = 3849, icon = "Achievement_Boss_PathaleonTheCalculator", aliases = {"механар", "мех"} },
    { name = "Аркатрац",                    short = "Арк", exp = "TBC", isRaid = false, achieve = 661, attune = 3848, icon = "Achievement_Boss_Harbinger_Skyriss", aliases = {"аркатрац", "арк"} },
    { name = "Терраса Магистров",           short = "ТМ",  exp = "TBC", isRaid = false, achieve = 662, attune = 4131, icon = "Achievement_Boss_Kael'thasSunstrider_01", aliases = {"терраса магистров", "тм"} },
}

local DUNGEONS_VANILLA = {
    { name = "Огненная пропасть",           short = "ОП",   exp = "Classic", isRaid = false, achieve = 627, attune = 2437, icon = "Achievement_Zone_Durotar", aliases = {"огненная пропасть", "оп"} },
    { name = "Мертвые копи",                short = "МК",   exp = "Classic", isRaid = false, achieve = 628, attune = 1581, icon = "Achievement_Boss_EdwinVancleef", aliases = {"мертвые копи", "дедмайнс", "мк"} },
    { name = "Пещеры Стенаний",             short = "ПС",   exp = "Classic", isRaid = false, achieve = 629, attune = 718,  icon = "Achievement_Boss_Mutanus_the_Devourer", aliases = {"пещеры стенаний", "пс"} },
    { name = "Крепость Темного Клыка",      short = "КТК",  exp = "Classic", isRaid = false, achieve = 630, attune = 209,  icon = "Achievement_Boss_ArchmageArugal", aliases = {"крепость темного клыка", "ктк", "аругал"} },
    { name = "Непроглядная Пучина",         short = "НП",   exp = "Classic", isRaid = false, achieve = 631, attune = 719,  icon = "Achievement_Boss_Bazil_Akumai", aliases = {"непроглядная пучина", "нп"} },
    { name = "Тюрьма",                      short = "Тюрьма",exp = "Classic", isRaid = false, achieve = 632, attune = 717,  icon = "Achievement_Boss_Bazil_Thredd", aliases = {"тюрьма", "тюрьма штормграда"} },
    { name = "Гномреган",                   short = "Гном", exp = "Classic", isRaid = false, achieve = 633, attune = 721,  icon = "INV_Misc_Head_Gnome_01", aliases = {"гномреган", "гномореган", "гном"} },
    { name = "Лабиринты Иглошкурых",        short = "ЛабИгл",exp = "Classic", isRaid = false, achieve = 635, attune = 491,  icon = "Achievement_Boss_CharlgaRazorflank", aliases = {"лабиринты иглошкурых", "лабиринты", "ли"} },
    { name = "Курганы Иглошкурых",          short = "Курганы",exp = "Classic", isRaid = false, achieve = 634, attune = 722,  icon = "Achievement_Boss_Amnennar_the_Coldbringer", aliases = {"курганы иглошкурых", "курганы", "ки"} },
    { name = "Монастырь Алого ордена",      short = "Скарлет",exp = "Classic", isRaid = false, achieve = 636, attune = 796,  icon = "Spell_Holy_SealOfFury", aliases = {"монастырь алого ордена", "монастырь", "смао"} },
    { name = "Ульдаман",                    short = "Ульд1",exp = "Classic", isRaid = false, achieve = 637, attune = 1337, icon = "Achievement_Boss_Archaedas", aliases = {"ульдаман", "ульда"} },
    { name = "Зул'Фаррак",                  short = "ЗФ",   exp = "Classic", isRaid = false, achieve = 638, attune = 1176, icon = "Achievement_Boss_ChiefUkorzSandscalp", aliases = {"зул фаррак", "зф", "зулфаррак"} },
    { name = "Мародон",                     short = "Мар",  exp = "Classic", isRaid = false, achieve = 639, attune = 2100, icon = "Achievement_Boss_PrincessTheradras", aliases = {"мародон", "мар"} },
    { name = "Затонувший храм",             short = "ЗХ",   exp = "Classic", isRaid = false, achieve = 640, attune = 1417, icon = "Achievement_Boss_ShadeOfEranikus", aliases = {"затонувший храм", "храм аталай", "зх"} },
    { name = "Глубины Черной горы",         short = "БРД",  exp = "Classic", isRaid = false, achieve = 641, attune = 1584, icon = "Achievement_Boss_EmperorDagranThaurissan", aliases = {"глубины черной горы", "брд"} },
    { name = "Нижняя часть пика Черной горы", short = "ЛБРС", exp = "Classic", isRaid = false, achieve = 642, attune = 1583, icon = "Achievement_Boss_Overlord_Wyrmthalak", aliases = {"нижняя часть пика черной горы", "нижняя часть черной горы", "лбрс"} },
    { name = "Верхняя часть пика Черной горы", short = "УБРС", exp = "Classic", isRaid = false, achieve = 1307, attune = 1583, icon = "Achievement_Boss_GeneralDrakkisath", aliases = {"верхняя часть пика черной горы", "вершина черной горы", "убрс"} },
    { name = "Некроситет",                  short = "Некро",exp = "Classic", isRaid = false, achieve = 643, attune = 2057, icon = "INV_Misc_Book_11", aliases = {"некроситет", "некро"} },
    { name = "Стратхольм",                  short = "Страт1",exp = "Classic", isRaid = false, achieve = 644, attune = 2017, icon = "Achievement_Zone_EasternPlaguelands", aliases = {"стратхольм", "страт"} },
    { name = "Забытый Город",               short = "ДМ",   exp = "Classic", isRaid = false, achieve = 645, attune = 2557, icon = "Achievement_Zone_Feralas", aliases = {"забытый город", "дирмаул", "дм"} },
}

---------------------------------------------------------------------------
-- Столицы и VIP (с фильтрацией по фракции и расе игрока)
---------------------------------------------------------------------------
local CAPITAL_DESTS = {
    -- Нейтральные столицы (доступны всем)
    { name = "Даларан",        short = "Дал",   exp = "WotLK",   faction = "Neutral",  icon = "Spell_Arcane_PortalDalaran",     aliases = {"даларан"} },
    { name = "Шаттрат",        short = "Шатт",  exp = "TBC",     faction = "Neutral",  icon = "Spell_Arcane_PortalShattrath",   aliases = {"шаттрат"} },
    -- Столицы Альянса (Люди, Дворфы, Гномы, Ночные эльфы, Дренеи)
    { name = "Штормград",      short = "Шторм", exp = "Classic", faction = "Alliance", icon = "Spell_Arcane_PortalStormWind",  aliases = {"штормград"} },
    { name = "Стальгорн",      short = "ИФ",    exp = "Classic", faction = "Alliance", icon = "Spell_Arcane_PortalIronForge",  aliases = {"стальгорн"} },
    { name = "Дарнас",         short = "Дарн",  exp = "Classic", faction = "Alliance", icon = "Spell_Arcane_PortalDarnassus",  aliases = {"дарнас"} },
    { name = "Экзодар",        short = "Экз",   exp = "TBC",     faction = "Alliance", icon = "Spell_Arcane_PortalExodar",     aliases = {"экзодар"} },
    -- Столицы Орды (Орки, Таурены, Тролли, Нежить, Эльфы крови)
    { name = "Оргриммар",      short = "Орг",   exp = "Classic", faction = "Horde",    icon = "Spell_Arcane_PortalOrgrimmar",  aliases = {"оргриммар"} },
    { name = "Подгород",       short = "Андер", exp = "Classic", faction = "Horde",    icon = "Spell_Arcane_PortalUnderCity",  aliases = {"подгород"} },
    { name = "Громовой Утес",  short = "ТБ",    exp = "Classic", faction = "Horde",    icon = "Spell_Arcane_PortalThunderBluff", aliases = {"громовой утес", "громовой утёс"} },
    { name = "Луносвет",       short = "Лун",   exp = "TBC",     faction = "Horde",    icon = "Spell_Arcane_PortalSilvermoon", aliases = {"луносвет"} },
    -- VIP Зона
    { name = "VIP ZONA",       short = "VIP",   exp = "VIP",     faction = "Neutral",  icon = "Spell_Arcane_TeleportMoonglade", aliases = {"vip zona", "vip", "вип", "prime", "wow prime"}, subText = "WoW Prime" },
}

local HORDE_RACES = {
    ["orc"] = true, ["tauren"] = true, ["troll"] = true, ["scourge"] = true, ["undead"] = true, ["bloodelf"] = true,
    ["орк"] = true, ["таурен"] = true, ["тролль"] = true, ["нежить"] = true, ["эльф крови"] = true, ["эльфийка крови"] = true,
}
local ALLIANCE_RACES = {
    ["human"] = true, ["dwarf"] = true, ["gnome"] = true, ["nightelf"] = true, ["draenei"] = true,
    ["человек"] = true, ["дворф"] = true, ["гном"] = true, ["ночной эльф"] = true, ["ночная эльфийка"] = true, ["дреней"] = true, ["дренейка"] = true,
}

local function GetPlayerFactionGroup()
    if type(UnitRace) == "function" then
        local locRace, engRace = UnitRace("player")
        if engRace and engRace ~= "" then
            local er = engRace:lower():gsub("%s+", "")
            if HORDE_RACES[er] then return "Horde" end
            if ALLIANCE_RACES[er] then return "Alliance" end
        end
        if locRace and locRace ~= "" then
            local lr = TalorianTP_Norm(locRace)
            if HORDE_RACES[lr] or lr:find("орк") or lr:find("таурен") or lr:find("тролл") or lr:find("нежит") or lr:find("кров") then
                return "Horde"
            end
            if ALLIANCE_RACES[lr] or lr:find("человек") or lr:find("дворф") or lr:find("гном") or lr:find("ночн") or lr:find("дрене") then
                return "Alliance"
            end
        end
    end
    if type(UnitFactionGroup) == "function" then
        local engFac, locFac = UnitFactionGroup("player")
        if engFac == "Horde" or engFac == "Alliance" then
            return engFac
        end
        if locFac and locFac ~= "" then
            local lf = TalorianTP_Norm(locFac)
            if lf:find("орд") then return "Horde" end
            if lf:find("альянс") then return "Alliance" end
        end
    end
    return "Both"
end

local function GetCurrentCapitalList()
    local pFac = GetPlayerFactionGroup()
    if pFac == "Both" then return CAPITAL_DESTS end
    local list = {}
    for _, c in ipairs(CAPITAL_DESTS) do
        if c.faction == "Neutral" or c.faction == pFac then
            table.insert(list, c)
        end
    end
    return list
end

local function GetCurrentRaidList()
    local era = TalorianTP_DB and TalorianTP_DB.raidEra or "All"
    if era == "All" then
        return RAID_DESTS
    end
    local filtered = {}
    for _, r in ipairs(RAID_DESTS) do
        if r.exp == era then
            table.insert(filtered, r)
        end
    end
    return filtered
end

local function FindDestByName(destName)
    if not destName or destName == "" then return nil end
    for _, r in ipairs(RAID_DESTS) do if r.name == destName then return r end end
    for _, d in ipairs(DUNGEONS_WOTLK) do if d.name == destName then return d end end
    for _, d in ipairs(DUNGEONS_TBC) do if d.name == destName then return d end end
    for _, d in ipairs(DUNGEONS_VANILLA) do if d.name == destName then return d end end
    for _, c in ipairs(CAPITAL_DESTS) do if c.name == destName then return c end end
    return nil
end

local function GetCurrentDungeonList()
    local era = TalorianTP_DB and TalorianTP_DB.dungeonEra or "WotLK"
    if era == "TBC" then
        return DUNGEONS_TBC
    elseif era == "Classic" then
        return DUNGEONS_VANILLA
    else
        return DUNGEONS_WOTLK
    end
end


---------------------------------------------------------------------------
-- Кэш и иконки
---------------------------------------------------------------------------
local ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"

local function ResolveIcon(iconName)
    if not iconName or iconName == "" then return ICON_FALLBACK end
    if iconName:find("\\") then return iconName end
    return "Interface\\Icons\\" .. iconName
end

---------------------------------------------------------------------------
-- AttuneAtlas интеграция и расчет по сложностям
---------------------------------------------------------------------------
local zoneSummaryCache = {}
local GetZoneForgeStats = nil
local hoveredCardBtn = nil

local function RefreshZoneSummaryCache(payloadMsg)
    if type(payloadMsg) == "string" and payloadMsg ~= "" then
        local clear, payload = strsplit("\t", payloadMsg, 2)
        if clear == "1" then
            zoneSummaryCache = {}
        end
        if payload and payload ~= "" then
            for rec in payload:gmatch("([^;]+)") do
                local id, rem, tot, name = strsplit(":", rec, 4)
                local zid = tonumber(id)
                local ztot = tonumber(tot)
                local zrem = tonumber(rem)
                if zid and ztot and zrem then
                    zoneSummaryCache[zid] = {
                        id = zid,
                        name = name or "",
                        total = ztot,
                        remain = zrem,
                        consumed = math.max(0, ztot - zrem),
                    }
                end
            end
        end
        return
    end

    zoneSummaryCache = {}
    if not rawget(_G, "AttuneAtlasDB") or not AttuneAtlasDB.zones then return end
    for _, z in ipairs(AttuneAtlasDB.zones) do
        if z.id and z.total and z.remain then
            zoneSummaryCache[z.id] = {
                id = z.id,
                name = z.name or "",
                total = z.total,
                remain = z.remain,
                consumed = math.max(0, z.total - z.remain),
            }
        end
    end
end

-- Возвращает { total, consumed, pct, modes = { [1] = {c, t}, ... } }
local function GetAttuneInfo(zoneId, zoneName, isRaid, exp)
    if not zoneId then return nil end
    local base = zoneSummaryCache[zoneId]
    if not base and rawget(_G, "AttuneAtlasDB") and AttuneAtlasDB.zones then
        local targetNorm = TalorianTP_Norm(zoneName)
        for _, z in ipairs(AttuneAtlasDB.zones) do
            if z.id == zoneId then
                base = { id = z.id, name = z.name or "", total = z.total, remain = z.remain, consumed = math.max(0, z.total - z.remain) }
                zoneSummaryCache[zoneId] = base
                break
            end
            if targetNorm ~= "" and z.name then
                local znNorm = TalorianTP_Norm(z.name)
                if znNorm == targetNorm or (znNorm:find(targetNorm, 1, true) and #targetNorm >= 5) then
                    base = { id = z.id, name = z.name or "", total = z.total, remain = z.remain, consumed = math.max(0, z.total - z.remain) }
                    zoneSummaryCache[zoneId] = base
                    break
                end
            end
        end
    end

    if not base or not base.total or base.total == 0 then return nil end

    local tot = base.total
    local cons = base.consumed
    local pct = math.floor((cons / tot) * 100 + 0.5)

    local modes = {}

    if isRaid then
        if exp == "Classic" then
            -- Классика рейды: только 1 режим (10 и 25 показывают общее, гер недоступен)
            modes[1] = { cons = cons, tot = tot }
            modes[2] = { cons = cons, tot = tot }
            modes[3] = nil
            modes[4] = nil
        elseif exp == "TBC" then
            -- Каражан и ЗА - 10 игроков; остальные - 25 игроков; гер сложности нет
            local isTen = (zoneId == 3457 or zoneId == 3805)
            if isTen then
                modes[1] = { cons = cons, tot = tot }
                modes[2] = nil
            else
                modes[1] = nil
                modes[2] = { cons = cons, tot = tot }
            end
            modes[3] = nil
            modes[4] = nil
        elseif exp == "WotLK" then
            -- 4-режимные рейды: ЦЛК (4812), ИК (4722), РС (4987)
            if zoneId == 4812 or zoneId == 4722 or zoneId == 4987 then
                local t10n = math.max(1, math.floor(tot * 0.24 + 0.5))
                local t25n = math.max(1, math.floor(tot * 0.32 + 0.5))
                local t10h = math.max(1, math.floor(tot * 0.18 + 0.5))
                local t25h = math.max(1, tot - (t10n + t25n + t10h))

                local c10n = math.min(t10n, math.floor(cons * 0.25 + 0.5))
                local c25n = math.min(t25n, math.floor(cons * 0.33 + 0.5))
                local c10h = math.min(t10h, math.floor(cons * 0.18 + 0.5))
                local c25h = math.min(t25h, math.max(0, cons - (c10n + c25n + c10h)))

                modes[1] = { cons = c10n, tot = t10n }
                modes[2] = { cons = c25n, tot = t25n }
                modes[3] = { cons = c10h, tot = t10h }
                modes[4] = { cons = c25h, tot = t25h }
            else
                -- 2-режимные рейды WotLK: Накс, Ульд, СА, Око, ОС, Оня
                local t10 = math.max(1, math.floor(tot * 0.46 + 0.5))
                local t25 = math.max(1, tot - t10)
                local c10 = math.min(t10, math.floor(cons * 0.48 + 0.5))
                local c25 = math.min(t25, math.max(0, cons - c10))

                modes[1] = { cons = c10, tot = t10 }
                modes[2] = { cons = c25, tot = t25 }
                modes[3] = nil
                modes[4] = nil
            end
        end
    else
        -- Подземелья
        if exp == "Classic" then
            -- Ванильные подземелья не имеют героической сложности!
            modes[1] = { cons = cons, tot = tot }
            modes[2] = nil
        else
            -- TBC и WotLK подземелья: Обычный (1) и Героический (2)
            local tNorm = math.max(1, math.floor(tot * 0.45 + 0.5))
            local tHero = math.max(1, tot - tNorm)
            local cNorm = math.min(tNorm, math.floor(cons * 0.45 + 0.5))
            local cHero = math.min(tHero, math.max(0, cons - cNorm))

            modes[1] = { cons = cNorm, tot = tNorm }
            modes[2] = { cons = cHero, tot = tHero }
        end
    end

    return {
        total = tot,
        consumed = cons,
        pct = pct,
        modes = modes,
    }
end

---------------------------------------------------------------------------
-- Отслеживание КД (Raid Locks)
---------------------------------------------------------------------------
local lockedInstances = {}

local function RefreshRaidLocks()
    lockedInstances = {}
    local num = GetNumSavedInstances()
    for i = 1, num do
        local name, id, reset, difficulty, locked, extended, isRaid, maxPlayers, difficultyName = GetSavedInstanceInfo(i)
        if locked and name then
            local nNorm = TalorianTP_Norm(name)
            lockedInstances[nNorm] = true
        end
    end
end

local function IsInstanceLocked(destName)
    if not destName then return false end
    local dNorm = TalorianTP_Norm(destName)
    if lockedInstances[dNorm] then return true end
    for lockName, _ in pairs(lockedInstances) do
        local mismatch = (dNorm == "стратхольм" and lockName:find("очищен", 1, true))
            or (lockName == "стратхольм" and dNorm:find("очищен", 1, true))
        if not mismatch and (lockName:find(dNorm, 1, true) or dNorm:find(lockName, 1, true)) then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Проверка присутствия, авто-призыв и метка Талориана
---------------------------------------------------------------------------
local lastSummonTime = 0
local CreateNoticeFrame
local ParseServerZoneItems
local ProcessBgForgeScanQueue
local GetZoneForgeStats
local noticeShownCount = 0
local MAX_NOTICES_PER_SELECTION = 2
local targetConfirmedNotified = false

local function ShowTalorianNotice(msg)
    if not msg or msg == "" then return end
    if not noticeFrame and CreateNoticeFrame then
        noticeFrame = CreateNoticeFrame()
    end
    if noticeFrame and noticeFrame.ShowNotice then
        noticeFrame:ShowNotice(msg)
    end
end

local function BuildActionNoticeText()
    local k = TalorianTP_DB and TalorianTP_DB.interactKey or "ъ"
    local targetName = TalorianTP_DB and TalorianTP_DB.targetRaid or "Цитадель Ледяной Короны"
    local mode = TalorianTP_DB and TalorianTP_DB.mode or "teleport"
    if mode == "teleport" and targetName ~= "" then
        return "Выбрано: |cffffd200" .. targetName .. "|r! Нажмите ПКМ на Талориана " .. ICON_DIAMOND .. " или клавишу бинда [|cffffffff" .. k .. "|r]"
    else
        local names = { buffer = "Баффер", bank = "Банк", shop = "Магазин", auction = "Аукцион" }
        local mName = names[mode] or "Талориан"
        return "Режим: |cffffd200" .. mName .. "|r! Нажмите ПКМ на Талориана " .. ICON_DIAMOND .. " или клавишу бинда [|cffffffff" .. k .. "|r]"
    end
end

local unitScanTip = nil

local function GetUnitScanTip()
    if unitScanTip then return unitScanTip end
    unitScanTip = CreateFrame("GameTooltip", "TalorianUnitScanTooltip", UIParent, "GameTooltipTemplate")
    return unitScanTip
end

local function IsTalorianSummoned()
    local num = (type(GetNumCompanions) == "function" and GetNumCompanions("CRITTER")) or 0
    local foundInList = false
    local customName = nil
    for i = 1, num do
        local _, name, spellId, _, isCurrent = GetCompanionInfo("CRITTER", i)
        if spellId == 91200 or (name and (name:find("Талориан", 1, true) or (TalorianTP_Norm and TalorianTP_Norm(name):find("талориан")))) then
            foundInList = true
            if name and name ~= "" then customName = name end
            -- В 3.3.5a isCurrent возвращает 1 или true если спутник активен
            if isCurrent == 1 or isCurrent == true then
                return true, true, i, customName
            end
        end
    end
    return false, foundInList, nil, customName
end

local function Utf8LenAndGenitiveStem(s)
    if type(s) ~= "string" or s == "" then return 0, nil end
    local count, prevEnd, i, n = 0, 0, 1, #s
    while i <= n do
        local b = s:byte(i)
        local cl = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
        if i + cl - 1 > n then break end
        count = count + 1
        if i + cl - 1 < n then prevEnd = i + cl - 1 end
        i = i + cl
    end
    return count, (count >= 4 and prevEnd > 0) and s:sub(1, prevEnd) or nil
end

-- Проверка, что юнит "Талориан" принадлежит именно игроку, который его призвал
local function IsUnitPlayersTalorian(unit)
    if not (TalorianTP_DB and TalorianTP_DB.enabled) then return false end
    if type(UnitExists) ~= "function" or not UnitExists(unit) then return false end
    local name = UnitName(unit)
    if not name or name == "" then return false end
    local _, _, _, talCustomName = IsTalorianSummoned()
    local isTalName = name:find("Талориан", 1, true)
        or (TalorianTP_Norm and TalorianTP_Norm(name):find("талориан"))
        or (talCustomName and (name == talCustomName or (TalorianTP_Norm and TalorianTP_Norm(name) == TalorianTP_Norm(talCustomName))))
    if not isTalName then
        return false
    end

    -- 1. Проверка владельца спутника по строке тултипа юнита ("Спутник <ИмяИгрока>" / "<ИмяИгрока>")
    local playerName = type(UnitName) == "function" and UnitName("player") or nil
    if playerName and playerName ~= "" then
        local tip = GetUnitScanTip()
        if tip and tip.SetUnit then
            tip:SetOwner(UIParent, "ANCHOR_NONE")
            tip:ClearLines()
            local ok = pcall(tip.SetUnit, tip, unit)
            if ok then
                local nLines = (tip.NumLines and tip:NumLines()) or 0
                local pNorm = TalorianTP_Norm and TalorianTP_Norm(playerName) or playerName:lower()
                local pChars, pStem = Utf8LenAndGenitiveStem(pNorm)
                local hasOtherOwnerTag = false
                local matchesPlayer = false
                for i = 2, math.min(nLines, 5) do
                    local fs = _G["TalorianUnitScanTooltipTextLeft" .. i]
                    local lText = fs and fs:GetText() or (tip.lines and tip.lines[i]) or ""
                    if lText and lText ~= "" then
                        local lNorm = TalorianTP_Norm and TalorianTP_Norm(lText) or lText:lower()
                        local lLow = lText:lower()
                        local lPad = " " .. lNorm .. " "
                        local exactMatch = (pNorm ~= "" and lPad:find(" " .. pNorm .. " ", 1, true) ~= nil)
                            or lText:find("^" .. playerName:gsub("([^%w])", "%%%1") .. "$")
                        local stemMatch = false
                        if not exactMatch and pStem and pChars >= 4 then
                            local escStem = pStem:gsub("([^%w])", "%%%1")
                            local tok = lPad:match(" (" .. escStem .. "%S*) ")
                            if tok then
                                local tail = tok:sub(#pStem + 1)
                                if tok == pNorm or tail == "а" or tail == "я" or tail == "и" or tail == "ы" or tail == "у" or tail == "ю" or tail == "е" or tail == "s" then
                                    stemMatch = true
                                end
                            end
                        end
                        if exactMatch or stemMatch then
                            matchesPlayer = true
                            break
                        end
                        if lNorm:find("спутник%s+%S") or lNorm:find("прислужник%s+%S") or lNorm:find("питомец%s+%S") or lNorm:find("страж%s+%S")
                            or lLow:find("'s%s+companion") or lLow:find("'s%s+minion") or lLow:find("'s%s+pet")
                            or lNorm:find("%ss%s+companion") or lNorm:find("%ss%s+minion") or lNorm:find("%ss%s+pet") then
                            hasOtherOwnerTag = true
                        end
                    end
                end
                tip:Hide()
                if matchesPlayer then return true end
                if hasOtherOwnerTag and not matchesPlayer then return false end
            else
                tip:Hide()
            end
        end
    end

    -- 2. Резервная проверка: если в тултипе нет строки владельца, проверяем активен ли спутник (с окном 3с после призыва)
    local isSummoned, foundInList = IsTalorianSummoned()
    local now = (type(GetTime) == "function" and GetTime()) or 0
    if foundInList and not isSummoned and not (lastSummonTime > 0 and now > 0 and (now - lastSummonTime) < 3.0) then
        return false
    end

    return true
end

local function IsTalorianTargetValid()
    return IsUnitPlayersTalorian("target")
end

local function CanSetRaidMarks()
    if type(GetNumRaidMembers) == "function" and GetNumRaidMembers() > 0 then
        local isLead = type(IsRaidLeader) == "function" and IsRaidLeader()
        local isOff = type(IsRaidOfficer) == "function" and IsRaidOfficer()
        return isLead or isOff
    end
    return true
end

local function CheckAndMarkTalorian(allowNotice)
    if not (TalorianTP_DB and TalorianTP_DB.enabled) then return false end

    local markedAny = false
    if TalorianTP_DB.autoMarkDiamond ~= false and CanSetRaidMarks() then
        local unitsToCheck = { "target", "mouseover", "focus", "npc", "pet", "targettarget", "focustarget" }
        for _, u in ipairs(unitsToCheck) do
            if IsUnitPlayersTalorian(u) then
                if type(GetRaidTargetIndex) == "function" and type(SetRaidTarget) == "function" then
                    if GetRaidTargetIndex(u) ~= 3 then
                        SetRaidTarget(u, 3)
                    end
                    markedAny = true
                end
            end
        end
    end

    if IsTalorianTargetValid() then
        if allowNotice and not targetConfirmedNotified then
            targetConfirmedNotified = true
            ShowTalorianNotice(BuildActionNoticeText())
        end
        return true
    end
    return markedAny
end

local function SummonTalorianIfNeeded()
    if not (TalorianTP_DB and TalorianTP_DB.enabled) then return false end
    if InCombatLockdown() then return false end

    -- Проверка на транспорте, такси, стелсе, касте/потоке, арене/БГ и в виде духа
    if type(IsMounted) == "function" and IsMounted() then return false end
    if type(IsStealthed) == "function" and IsStealthed() then return false end
    if type(UnitInVehicle) == "function" and UnitInVehicle("player") then return false end
    if type(UnitUsingVehicle) == "function" and UnitUsingVehicle("player") then return false end
    if type(UnitOnTaxi) == "function" and UnitOnTaxi("player") then return false end
    if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player") then return false end
    if type(UnitCastingInfo) == "function" and UnitCastingInfo("player") then return false end
    if type(UnitChannelInfo) == "function" and UnitChannelInfo("player") then return false end
    if type(IsInInstance) == "function" then
        local inInst, instType = IsInInstance()
        if inInst and (instType == "arena" or instType == "pvp") then return false end
    end

    local isSummoned = IsTalorianSummoned()
    if isSummoned then
        CheckAndMarkTalorian(false)
        return true
    end

    if not select(2, IsTalorianSummoned()) then
        targetPollTimer = 0
        return false
    end
    local now = (type(GetTime) == "function" and GetTime()) or 0
    if now > 0 and (now - lastSummonTime) < 1.2 then return false end

    local num = (type(GetNumCompanions) == "function" and GetNumCompanions("CRITTER")) or 0
    for i = 1, num do
        local _, name, spellId, _, isCurrent = GetCompanionInfo("CRITTER", i)
        if spellId == 91200 or (name and (name:find("Талориан", 1, true) or (TalorianTP_Norm and TalorianTP_Norm(name):find("талориан")))) then
            local isActive = (isCurrent == 1 or isCurrent == true)
            if not isActive then
                lastSummonTime = now
                pcall(CallCompanion, "CRITTER", i)
                -- Запускаем активный поллинг разметки после призыва
                targetPollTimer = 4.0
                targetPollElapsed = 0
            end
            return true
        end
    end
    return false
end

local function BuildTalorianTargetLines()
    local _, _, _, customName = IsTalorianSummoned()
    local tgtLines = "/targetexact Талориан"
    if customName and customName ~= "" and customName ~= "Талориан" then
        tgtLines = "/targetexact " .. customName .. "\n" .. tgtLines
    end
    return tgtLines
end

local function BuildTalorianSecureMacro(summonOnlyIfNeeded)
    local isSum = IsTalorianSummoned()
    local castName = (type(GetSpellInfo) == "function" and GetSpellInfo(91200)) or "Призыв Талориана"
    local tgtLines = BuildTalorianTargetLines()
    if summonOnlyIfNeeded and isSum then
        return tgtLines .. "\n/run if CheckAndMarkTalorian then CheckAndMarkTalorian() end"
    end
    return "/cleartarget\n" .. tgtLines .. "\n/cast [noexists] " .. castName .. "\n" .. tgtLines .. "\n/run if CheckAndMarkTalorian then CheckAndMarkTalorian() end"
end

local function EnsureSecureExecButton()
    if InCombatLockdown() then return _G["TalorianSecureExecBtn"] end
    local btn = _G["TalorianSecureExecBtn"]
    if not btn then
        btn = CreateFrame("Button", "TalorianSecureExecBtn", UIParent, "SecureActionButtonTemplate")
    end
    btn:SetAttribute("type", "macro")
    local en = TalorianTP_DB and TalorianTP_DB.enabled
    btn:SetAttribute("macrotext", en and BuildTalorianSecureMacro(true) or "")
    return btn
end

local function RefreshTalorianOverrideBinding()
    if InCombatLockdown and InCombatLockdown() then return end
    if type(GetBindingKey) ~= "function" or type(SetOverrideBindingClick) ~= "function" or type(ClearOverrideBindings) ~= "function" then
        return
    end
    local btn = EnsureSecureExecButton()
    if not btn then return end
    ClearOverrideBindings(btn)
    if TalorianTP_DB and TalorianTP_DB.enabled then
        local k1, k2 = GetBindingKey("TALORIAN_TP_CURRENT")
        if k1 then SetOverrideBindingClick(btn, true, k1, "TalorianSecureExecBtn", "LeftButton") end
        if k2 then SetOverrideBindingClick(btn, true, k2, "TalorianSecureExecBtn", "LeftButton") end
    end
end

local function UpdateSecureBtnMacro(btn)
    if not btn or InCombatLockdown() then return end
    if not (TalorianTP_DB and TalorianTP_DB.enabled) then
        btn:SetAttribute("macrotext", "")
        return
    end
    local isSum = IsTalorianSummoned()
    if isSum then
        btn:SetAttribute("macrotext", BuildTalorianSecureMacro(true))
    else
        lastSummonTime = (type(GetTime) == "function" and GetTime()) or 0
        targetPollTimer = 4.0
        targetPollElapsed = 0
        btn:SetAttribute("macrotext", BuildTalorianSecureMacro(false))
    end
end

local function UpdateAllSecureButtonsMacro()
    if InCombatLockdown() then return end
    EnsureSecureExecButton()
    RefreshTalorianOverrideBinding()
    if not mainUI then return end
    local en = TalorianTP_DB and TalorianTP_DB.enabled
    local mText = en and BuildTalorianSecureMacro(true) or ""
    if mainUI.modeBtns then
        for _, b in ipairs(mainUI.modeBtns) do b:SetAttribute("macrotext", mText) end
    end
    if mainUI.quickRaidBtns then
        for _, b in ipairs(mainUI.quickRaidBtns) do b:SetAttribute("macrotext", mText) end
    end
    if mainUI.destButtons then
        for _, b in ipairs(mainUI.destButtons) do b:SetAttribute("macrotext", mText) end
    end
end

_G.TalorianTP_SummonIfNeeded = SummonTalorianIfNeeded
_G.SummonTalorianIfNeeded = SummonTalorianIfNeeded
_G.CheckAndMarkTalorian = CheckAndMarkTalorian
_G.TalorianTP_CheckAndMark = CheckAndMarkTalorian
_G.TalorianTP_EnsureSecureExecButton = EnsureSecureExecButton
_G.TalorianTP_UpdateSecureMacro = UpdateSecureBtnMacro

---------------------------------------------------------------------------
-- Управление макросами персонажа (/macro)
---------------------------------------------------------------------------
local MAX_ACCOUNT_MACROS = _G.MAX_ACCOUNT_MACROS or 36
local MAX_CHARACTER_MACROS = _G.MAX_CHARACTER_MACROS or 18

local function Utf8SubBytes(str, maxBytes)
    if not str or #str <= maxBytes then return str or "" end
    local res = {}
    local i = 1
    local len = #str
    local used = 0
    while i <= len do
        local b = str:byte(i)
        local charLen = 1
        if b >= 240 then charLen = 4
        elseif b >= 224 then charLen = 3
        elseif b >= 192 then charLen = 2 end
        if i + charLen - 1 > len then break end
        if used + charLen > maxBytes then break end
        table.insert(res, str:sub(i, i + charLen - 1))
        used = used + charLen
        i = i + charLen
    end
    return table.concat(res)
end

local function Utf8CropChars(str, maxChars)
    str = tostring(str or "")
    if str == "" then return "" end
    maxChars = tonumber(maxChars) or 24
    local total, cutByte = 0, #str
    local limit = (maxChars > 3) and (maxChars - 2) or maxChars
    local i, len = 1, #str
    while i <= len do
        local b = str:byte(i)
        local charLen = 1
        if b >= 240 then charLen = 4
        elseif b >= 224 then charLen = 3
        elseif b >= 192 then charLen = 2 end
        if i + charLen - 1 > len then break end
        total = total + 1
        if total == limit then cutByte = i + charLen - 1 end
        i = i + charLen
    end
    if total <= maxChars then return str end
    if limit <= 0 then return ".." end
    return str:sub(1, cutByte) .. ".."
end

local function ResolveMacroIconIndex(icon)
    if type(icon) == "number" and icon >= 1 then
        return math.floor(icon)
    end
    local total = (type(GetNumMacroIcons) == "function") and (GetNumMacroIcons() or 0) or 0
    if type(icon) == "string" and icon ~= "" and total > 0 and type(GetMacroIconInfo) == "function" then
        local target = icon:lower():gsub(".*\\", ""):gsub(".*\\/", ""):gsub("%.blp$", "")
        for i = 1, total do
            local tex = GetMacroIconInfo(i)
            if type(tex) == "string" then
                local clean = tex:lower():gsub(".*\\", ""):gsub(".*\\/", ""):gsub("%.blp$", "")
                if clean == target then
                    return i
                end
            end
        end
    end
    return 1
end

local function GetDestMacroTag(destName)
    local d = destName and FindDestByName and FindDestByName(destName) or nil
    if d and d.short and d.short ~= "" then
        local tag = "T_" .. tostring(d.short):gsub("%s+", "")
        return Utf8SubBytes(tag, 16)
    end
    local s = TalorianTP_Norm(destName):gsub("%s+", "")
    s = Utf8SubBytes(s, 12)
    return "T_" .. s
end

local function GetCharMacroIndex(macroName)
    local numAccount, numChar = GetNumMacros()
    local base = _G.MAX_ACCOUNT_MACROS or MAX_ACCOUNT_MACROS or 36
    for i = (base + 1), (base + (numChar or 0)) do
        local name = GetMacroInfo(i)
        if name == macroName then return i end
    end
    for i = 1, (numAccount or 0) do
        local name = GetMacroInfo(i)
        if name == macroName then return i end
    end
    return nil
end

local function CreateOrUpdateCharMacro(name, icon, body)
    if InCombatLockdown and InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "|cffff4444Невозможно изменять макросы в бою!|r")
        return nil
    end
    if type(CreateMacro) ~= "function" then
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "|cffff4444API макросов недоступно.|r")
        return nil
    end

    name = Utf8SubBytes(tostring(name or "Talorian"), 16)
    body = Utf8SubBytes(tostring(body or ""), 255)
    local iconIdx = ResolveMacroIconIndex(icon)

    local idx = GetCharMacroIndex(name)
    if idx then
        local ok, res = pcall(EditMacro, idx, name, iconIdx, body)
        if not ok then
            ok, res = pcall(EditMacro, idx, name, 1, body)
        end
        if ok then
            if MacroFrame and MacroFrame:IsVisible() and type(MacroFrame_Update) == "function" then
                pcall(MacroFrame_Update)
            end
            return res or idx
        end
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "|cffff4444Ошибка обновления макроса: " .. tostring(res) .. "|r")
        return nil
    else
        local numAccount, numChar = GetNumMacros()
        local maxAcc = _G.MAX_ACCOUNT_MACROS or MAX_ACCOUNT_MACROS or 36
        local maxChar = _G.MAX_CHARACTER_MACROS or MAX_CHARACTER_MACROS or 18
        local perChar = 1
        if (numChar or 0) >= maxChar then
            if (numAccount or 0) < maxAcc then
                perChar = nil
                DEFAULT_CHAT_FRAME:AddMessage(string.format("%s|cffffd200Личные слоты (%d/%d) заполнены - сохраняю %s в Общие макросы.|r", ADDON_PREFIX, numChar or 0, maxChar, name))
            else
                DEFAULT_CHAT_FRAME:AddMessage(string.format("%s|cffff4444Все слоты макросов заняты (Персонаж: %d/%d, Общие: %d/%d)!|r", ADDON_PREFIX, numChar or 0, maxChar, numAccount or 0, maxAcc))
                return nil
            end
        end
        local ok, newIdx = pcall(CreateMacro, name, iconIdx, body, perChar)
        if not ok or not newIdx then
            ok, newIdx = pcall(CreateMacro, name, 1, body, perChar)
        end
        if ok and newIdx then
            if MacroFrame and MacroFrame:IsVisible() and type(MacroFrame_Update) == "function" then
                pcall(MacroFrame_Update)
            end
            return newIdx
        end
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "|cffff4444Не удалось создать макрос (" .. tostring(newIdx) .. "). Проверьте /macro.|r")
        return nil
    end
end

local function DeleteCharMacro(name)
    if InCombatLockdown and InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "|cffff4444Невозможно удалять макросы в бою!|r")
        return false
    end
    local idx = GetCharMacroIndex(name)
    if idx then
        DeleteMacro(idx)
        if MacroFrame and MacroFrame:IsVisible() and type(MacroFrame_Update) == "function" then
            pcall(MacroFrame_Update)
        end
        return true
    end
    return false
end

local function BuildCharMacroBody(luaCall)
    local castName = (type(GetSpellInfo) == "function" and GetSpellInfo(91200)) or "Призыв Талориана"
    local tgtLines = BuildTalorianTargetLines()
    local body = "#showtooltip\n/cleartarget\n" .. tgtLines .. "\n/cast [noexists] " .. castName .. "\n" .. tgtLines .. "\n/run " .. luaCall
    if #body > 255 then
        local _, _, _, customName = IsTalorianSummoned()
        if customName and customName ~= "" and customName ~= "Талориан" then
            local shortTgt = "/tar " .. customName
            body = "#showtooltip\n/cleartarget\n" .. shortTgt .. "\n/cast [noexists] " .. castName .. "\n" .. shortTgt .. "\n/run " .. luaCall
        end
        if #body > 255 then
            body = "#showtooltip\n/cleartarget\n/targetexact Талориан\n/cast [noexists] " .. castName .. "\n/targetexact Талориан\n/run " .. luaCall
        end
    end
    return body
end

function TalorianTP_ToggleMacroForDest(destName)
    destName = destName or (TalorianTP_DB and TalorianTP_DB.targetRaid) or "Цитадель Ледяной Короны"
    local tag = GetDestMacroTag(destName)
    local idx = GetCharMacroIndex(tag)
    if idx then
        if DeleteCharMacro(tag) then
            DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Макрос |cffffffff" .. tag .. "|r удален из вкладки персонажа.")
        end
    else
        local body = BuildCharMacroBody("TalorianTP_SetAndGo(\"" .. destName .. "\")")
        local dest = FindDestByName(destName)
        local iconRef = (dest and dest.icon) or "INV_Misc_QuestionMark"
        local created = CreateOrUpdateCharMacro(tag, iconRef, body)
        if created then
            DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Макрос |cffffd200" .. tag .. "|r (" .. destName .. ") создан в /macro.")
        end
    end
    if mainUI and mainUI.RefreshButtons then mainUI:RefreshButtons() end
    if mainUI and mainUI.UpdateHeaderTarget then mainUI:UpdateHeaderTarget() end
end

function TalorianTP_CreateMacro_TopRaids()
    local topRaids = {
        { name = "Цитадель Ледяной Короны", tag = "T_ЦЛК",  icon = "Achievement_Boss_LichKing" },
        { name = "Испытание крестоносца",   tag = "T_ИК",   icon = "Achievement_Reputation_ArgentCrusader" },
        { name = "Рубиновое святилище",     tag = "T_РС",   icon = "Spell_Shadow_Twilight" },
        { name = "Наксрамас",               tag = "T_Накс", icon = "Achievement_Dungeon_Naxxramas_Normal" },
    }
    local count = 0
    for _, r in ipairs(topRaids) do
        local body = BuildCharMacroBody("TalorianTP_SetAndGo(\"" .. r.name .. "\")")
        if CreateOrUpdateCharMacro(r.tag, r.icon, body) then
            count = count + 1
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Создано " .. count .. "/4 топ-рейд макросов персонажа (ЦЛК, ИК, РС, Накс).")
    if mainUI and mainUI.RefreshButtons then mainUI.RefreshButtons() end
end

function TalorianTP_Delete_TopRaids()
    local tags = { "T_ЦЛК", "T_ИК", "T_РС", "T_Накс" }
    local count = 0
    for _, tag in ipairs(tags) do
        if DeleteCharMacro(tag) then count = count + 1 end
    end
    DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Удалено " .. count .. " топ-рейд макросов персонажа.")
    if mainUI and mainUI.RefreshButtons then mainUI.RefreshButtons() end
end

function TalorianTP_CreateMacro_Buffer()
    local body = BuildCharMacroBody("TalorianTP_SetModeAndGo(\"buffer\")")
    if CreateOrUpdateCharMacro("T_Баффер", "Spell_Holy_GreaterBlessingofKings", body) then
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Макрос Баффера (|cffffd200T_Баффер|r) создан в макросах персонажа.")
    end
    if mainUI and mainUI.RefreshButtons then mainUI.RefreshButtons() end
end

function TalorianTP_DeleteAllTalorianMacros()
    if InCombatLockdown and InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "|cffff4444Невозможно удалять макросы в бою!|r")
        return 0
    end
    local numAccount, numChar = GetNumMacros()
    local maxAcc = _G.MAX_ACCOUNT_MACROS or MAX_ACCOUNT_MACROS or 36
    local count = 0
    for i = (maxAcc + (numChar or 0)), (maxAcc + 1), -1 do
        local name = GetMacroInfo(i)
        if name and name:find("^T_") then
            DeleteMacro(i)
            count = count + 1
        end
    end
    for i = (numAccount or 0), 1, -1 do
        local name = GetMacroInfo(i)
        if name and name:find("^T_") then
            DeleteMacro(i)
            count = count + 1
        end
    end
    if MacroFrame and MacroFrame:IsVisible() and type(MacroFrame_Update) == "function" then
        pcall(MacroFrame_Update)
    end
    DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Удалено " .. count .. " макросов TalorianTP.")
    if mainUI and mainUI.RefreshButtons then mainUI:RefreshButtons() end
    return count
end

---------------------------------------------------------------------------
-- Навигация и переключение режимов
---------------------------------------------------------------------------
function TalorianTP_SetTarget(destName)
    -- Проверка на null / пустую строку
    if not destName or destName == "" then return end

    TalorianTP_DB.targetRaid = destName
    TalorianTP_DB.mode = "teleport"
    if mainUI and mainUI.UpdateModeHighlight then
        mainUI:UpdateModeHighlight()
    elseif mainUI and mainUI.UpdateHeaderTarget then
        mainUI:UpdateHeaderTarget()
    end
    if mainUI and mainUI.RefreshButtons then
        mainUI:RefreshButtons()
    end

    -- Если аддон отключен, не призываем, не берем в таргет и не ставим метку
    if not (TalorianTP_DB and TalorianTP_DB.enabled) then
        targetPollTimer = 0
        UpdateAllSecureButtonsMacro()
        if _G["TalorianSecureExecBtn"] and not InCombatLockdown() then
            _G["TalorianSecureExecBtn"]:SetAttribute("macrotext", "")
        end
        return
    end

    SummonTalorianIfNeeded()

    noticeShownCount = 0
    targetConfirmedNotified = false
    local noticeMsg = BuildActionNoticeText()
    ShowTalorianNotice(noticeMsg)
    DEFAULT_CHAT_FRAME:AddMessage(noticeMsg)

    -- Если Талориан уже выбран, сразу метим без лишнего дубля оповещения
    if CheckAndMarkTalorian(false) then
        targetConfirmedNotified = true
        targetPollTimer = 0
        return
    end

    -- Запуск активного опроса появления цели (каждые 0.1 сек до 3.5 сек, максимум 2 оповещения)
    targetPollTimer = 3.5
    targetPollElapsed = 0
end

function TalorianTP_SetMode(modeId)
    if not modeId or modeId == "" then return end
    TalorianTP_DB.mode = modeId
    if mainUI and mainUI.UpdateModeHighlight then
        mainUI:UpdateModeHighlight()
    end

    if not (TalorianTP_DB and TalorianTP_DB.enabled) then
        targetPollTimer = 0
        return
    end

    SummonTalorianIfNeeded()

    noticeShownCount = 0
    targetConfirmedNotified = false
    local noticeMsg = BuildActionNoticeText()
    ShowTalorianNotice(noticeMsg)
    DEFAULT_CHAT_FRAME:AddMessage(noticeMsg)

    if CheckAndMarkTalorian(false) then
        targetConfirmedNotified = true
        targetPollTimer = 0
        return
    end
    targetPollTimer = 3.5
    targetPollElapsed = 0
end

function TalorianTP_SetAndGo(destName)
    TalorianTP_SetTarget(destName)
    CheckAndMarkTalorian()
end

function TalorianTP_SetModeAndGo(modeId)
    TalorianTP_SetMode(modeId)
    CheckAndMarkTalorian()
end

function TalorianTP_SetRaidDiff(diffId)
    TalorianTP_DB.raidDiff = diffId
    if mainUI and mainUI.UpdateDiffHighlight then mainUI:UpdateDiffHighlight() end
    if mainUI and mainUI.RefreshButtons then mainUI:RefreshButtons() end
end

function TalorianTP_SetDungeonDiff(diffId)
    TalorianTP_DB.dungeonDiff = diffId
    if mainUI and mainUI.UpdateDiffHighlight then mainUI:UpdateDiffHighlight() end
    if mainUI and mainUI.RefreshButtons then mainUI:RefreshButtons() end
end

function TalorianTP_ResetAllCD()
    SendChatMessage(".in un all", "SAY")
    DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Запрос сброса всех КД отправлен (.in un all).")
end

---------------------------------------------------------------------------
-- Авто-подтверждение всплывающих окон
---------------------------------------------------------------------------
local function AutoAcceptPopup()
    if StaticPopup1 and StaticPopup1:IsVisible() then
        local w = StaticPopup1.which
        local txt = _G["StaticPopup1Text"] and _G["StaticPopup1Text"]:GetText() or ""
        local nTxt = TalorianTP_Norm(txt)
        local isSafeTeleportPopup = (w == "GOSSIP_CONFIRM")
            or nTxt:find("телепорт") or nTxt:find("перемест")
            or nTxt:find("портал") or nTxt:find("талориан")
        if isSafeTeleportPopup and StaticPopup1Button1 and StaticPopup1Button1:IsVisible() then
            StaticPopup1Button1:Click()
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Сопоставление целей и Gossip навигация
---------------------------------------------------------------------------
local function IsMatch(optText, targetName, aliases)
    local oNorm = TalorianTP_Norm(optText)
    local tNorm = TalorianTP_Norm(targetName)
    if oNorm == "" or tNorm == "" then return false end
    if oNorm == tNorm then return true end

    if aliases then
        for _, al in ipairs(aliases) do
            local aNorm = TalorianTP_Norm(al)
            if aNorm ~= "" then
                if not (aNorm == "око" and oNorm:find("вечност")) then
                    if oNorm == aNorm then return true end
                    if oNorm:find("^" .. aNorm .. "%s") or oNorm:find("%s" .. aNorm .. "$") or oNorm:find("%s" .. aNorm .. "%s") then
                        return true
                    end
                end
            end
        end
    end

    if (targetName == "VIP ZONA" or tNorm:find("vip")) and (oNorm:find("vip") or oNorm:find("вип") or oNorm:find("prime")) then
        return true
    end

    local allTokensFound = true
    local tokenCount = 0
    for tok in tNorm:gmatch("%S+") do
        if #tok >= 3 then
            tokenCount = tokenCount + 1
            if not oNorm:find(tok, 1, true) then
                allTokensFound = false
                break
            end
        end
    end
    if allTokensFound and tokenCount > 0 then
        if tokenCount == 1 and tNorm == "око" and oNorm:find("вечност") then return false end
        if tNorm == "стратхольм" and oNorm:find("очищен") then return false end
        if tNorm:find("храм") and not oNorm:find("храм") then return false end
        if tNorm:find("руин") and not oNorm:find("руин") then return false end
        if tNorm:find("вершин") and not oNorm:find("вершин") then return false end
        if tNorm:find("крепост") and not oNorm:find("крепост") then return false end
        return true
    end

    return false
end

local function ProcessGossip()
    if not (TalorianTP_DB and TalorianTP_DB.enabled) then return end
    local count = select("#", GetGossipOptions())
    if count == 0 then return end

    TalorianTP_DB.gossipLog = TalorianTP_DB.gossipLog or {}
    local currentLog = { time = date("%H:%M:%S"), options = {} }
    for i = 1, count, 2 do
        local text = select(i, GetGossipOptions())
        table.insert(currentLog.options, text or "")
    end
    table.insert(TalorianTP_DB.gossipLog, currentLog)
    if #TalorianTP_DB.gossipLog > 20 then
        table.remove(TalorianTP_DB.gossipLog, 1)
    end

    local mode = TalorianTP_DB.mode or "teleport"

    if mode == "buffer" then
        for i = 1, count, 2 do
            local text = select(i, GetGossipOptions())
            local n = TalorianTP_Norm(text)
            if n:find("баф") then SelectGossipOption((i + 1) / 2); return end
        end
        return
    elseif mode == "bank" then
        for i = 1, count, 2 do
            local text = select(i, GetGossipOptions())
            local n = TalorianTP_Norm(text)
            if n:find("банк") then SelectGossipOption((i + 1) / 2); return end
        end
        return
    elseif mode == "shop" then
        for i = 1, count, 2 do
            local text = select(i, GetGossipOptions())
            local n = TalorianTP_Norm(text)
            if n:find("магаз") or n:find("торг") or n:find("ремонт") then SelectGossipOption((i + 1) / 2); return end
        end
        return
    elseif mode == "auction" then
        for i = 1, count, 2 do
            local text = select(i, GetGossipOptions())
            local n = TalorianTP_Norm(text)
            if n:find("аукцион") then SelectGossipOption((i + 1) / 2); return end
        end
        return
    end

    -- TELEPORT
    local targetDest = TalorianTP_DB.targetRaid or "Цитадель Ледяной Короны"
    local activeTab = TalorianTP_DB.activeTab or 1
    local dungeonEra = TalorianTP_DB.dungeonEra or "WotLK"

    local destInfo = nil
    for _, r in ipairs(RAID_DESTS) do if r.name == targetDest then destInfo = r; break end end
    if not destInfo then
        for _, d in ipairs(DUNGEONS_WOTLK) do if d.name == targetDest then destInfo = d; break end end
    end
    if not destInfo then
        for _, d in ipairs(DUNGEONS_TBC) do if d.name == targetDest then destInfo = d; break end end
    end
    if not destInfo then
        for _, d in ipairs(DUNGEONS_VANILLA) do if d.name == targetDest then destInfo = d; break end end
    end
    if not destInfo then
        for _, c in ipairs(CAPITAL_DESTS) do if c.name == targetDest then destInfo = c; break end end
    end

    local exp = destInfo and destInfo.exp or (activeTab == 1 and "WotLK" or dungeonEra)
    local isRaid = destInfo and destInfo.isRaid
    if isRaid == nil then isRaid = (activeTab == 1) end
    local isCapital = (destInfo ~= nil and not destInfo.isRaid and not destInfo.achieve) or (destInfo == nil and activeTab == 3)

    -- ШАГ 1: Прямое совпадение в текущем меню
    for i = 1, count, 2 do
        local text = select(i, GetGossipOptions())
        if text and IsMatch(text, targetDest, destInfo and destInfo.aliases) then
            SelectGossipOption((i + 1) / 2)
            isTeleporting = true
            confirmTimer = 0
            AutoAcceptPopup()
            return
        end
    end

    -- ШАГ 2: Категории по эрам и типам
    if isCapital then
        for i = 1, count, 2 do
            local text = select(i, GetGossipOptions())
            local n = TalorianTP_Norm(text)
            if n:find("назад") or n:find("back") then SelectGossipOption((i + 1) / 2); return end
        end
    elseif not isRaid then
        for i = 1, count, 2 do
            local text = select(i, GetGossipOptions())
            local n = TalorianTP_Norm(text)
            if exp == "WotLK" then
                if n:find("лич") or ((n:find("подземел") or n:find("инст")) and (n:find("лк") or n:find("нордскол") or n:find("wotlk"))) then
                    SelectGossipOption((i + 1) / 2); return
                end
            elseif exp == "TBC" then
                if n:find("burning") or n:find("crusade") or ((n:find("подземел") or n:find("инст")) and (n:find("tbc") or n:find("бк") or n:find("запредел"))) then
                    SelectGossipOption((i + 1) / 2); return
                end
            elseif exp == "Classic" then
                if n:find("классическ") or ((n:find("подземел") or n:find("инст")) and (n:find("classic") or n:find("ванил") or n:find("азерот"))) then
                    SelectGossipOption((i + 1) / 2); return
                end
            end
        end
    else
        for i = 1, count, 2 do
            local text = select(i, GetGossipOptions())
            local n = TalorianTP_Norm(text)
            if n:find("рейдов") or n:find("рейд") then
                SelectGossipOption((i + 1) / 2); return
            end
        end
    end

    -- ШАГ 3: Пагинация (Далее...)
    for i = 1, count, 2 do
        local text = select(i, GetGossipOptions())
        local n = TalorianTP_Norm(text)
        if n:find("далее") or n:find("след") or n:find(">>") or n:find("вперед") or n:find("next") then
            SelectGossipOption((i + 1) / 2); return
        end
    end

    -- ШАГ 4: Корневое "Телепорт Меню"
    for i = 1, count, 2 do
        local text = select(i, GetGossipOptions())
        local n = TalorianTP_Norm(text)
        if n:find("телепорт") or n:find("тп") then
            SelectGossipOption((i + 1) / 2); return
        end
    end

    -- ШАГ 5: Возврат назад при ошибке
    for i = 1, count, 2 do
        local text = select(i, GetGossipOptions())
        local n = TalorianTP_Norm(text)
        if n:find("назад") or n:find("back") then
            SelectGossipOption((i + 1) / 2); return
        end
    end
end

---------------------------------------------------------------------------
-- Тултип для карточек
---------------------------------------------------------------------------
local function FormatStatValue(val)
    val = math.floor(tonumber(val) or 0)
    if val >= 1000 then
        local hi = math.floor(val / 1000)
        local lo = val % 1000
        return string.format("%d %03d", hi, lo)
    end
    return tostring(val)
end

local ownedState = { cache = {}, dirty = true, lastTs = 0 }

local function InvalidateOwnedZoneCache()
    ownedState.dirty = true
end

local function GetZoneOwnedReadyItems(zoneId)
    if not zoneId then return nil end
    local ap = rawget(_G, "AttuneParser")
    if not ap or type(ap.GetOwnedUpgradeCandidates) ~= "function" then return nil end
    local now = GetTime and GetTime() or 0
    if ownedState.dirty and (now - ownedState.lastTs) >= 1.2 then
        ownedState.dirty = false
        ownedState.lastTs = now
        ownedState.cache = {}
        local topMap = (ap.Data and ap.Data.TopMap) or {}
        local cands = ap:GetOwnedUpgradeCandidates()
        for _, it in ipairs(cands) do
            local isMk = (ap.IsMorKelItem and ap:IsMorKelItem(it.itemId)) or (ap.MORKEL_ITEMS and ap.MORKEL_ITEMS[it.itemId])
            if not isMk then
                local seenZ = {}
                if it.primaryZone and it.primaryZone > 0 then
                    seenZ[topMap[it.primaryZone] or it.primaryZone] = true
                end
                if ap.GetItemSources then
                    local sm = ap:GetItemSources(it.itemId)
                    for _, sc in ipairs((sm and sm.list) or {}) do
                        if sc.zoneId and sc.zoneId > 0 then
                            seenZ[topMap[sc.zoneId] or sc.zoneId] = true
                        end
                    end
                end
                for zid in pairs(seenZ) do
                    ownedState.cache[zid] = ownedState.cache[zid] or {}
                    table.insert(ownedState.cache[zid], it)
                end
            end
        end
    end
    local topId = (ap.Data and ap.Data.TopMap and ap.Data.TopMap[zoneId]) or zoneId
    return ownedState.cache[topId]
end

local function ShowDestTooltip(btn)
    local data = btn and btn.destData
    if not data then return end

    hoveredCardBtn = btn
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(data.name, 1, 1, 1)

    local ap = rawget(_G, "AttuneParser")
    local curDiff = data.isRaid and (TalorianTP_DB and TalorianTP_DB.raidDiff or 1) or (TalorianTP_DB and TalorianTP_DB.dungeonDiff or 1)
    local za = nil

    if ap and ap.GetZoneAnalysis and data.attune then
        if ap.RequestZoneSync then ap:RequestZoneSync(data.attune) end
        za = ap:GetZoneAnalysis(data.attune, {
            diffId = curDiff,
            isRaid = data.isRaid,
            exp = data.exp,
            scope = "hero",
        })
    end

    local kindLabel = data.subText or data.exp or ""
    if data.isRaid then
        if za and za.isSingleDiff then
            kindLabel = (data.exp or "") .. " - Рейд (единая сложность)"
        elseif za and (za.maxDiffs or 1) == 2 then
            kindLabel = (data.exp or "") .. " - Рейд (10 и 25 обыч.)"
        elseif data.attune then
            kindLabel = (data.exp or "") .. " - Рейд (10/25 об. и гер.)"
        end
    elseif data.attune then
        if za and za.isSingleDiff then
            kindLabel = (data.exp or "") .. " - Подземелье (единая сложность)"
        else
            kindLabel = (data.exp or "") .. " - Подземелье (Обычный / Героический)"
        end
    end
    GameTooltip:AddLine(kindLabel, 0.4, 0.75, 1)

    if za then
        local diffLabels = data.isRaid
            and { "10 обычная", "25 обычная", "10 героическая", "25 героическая" }
            or  { "Обычный", "Героический" }

        if not za.isSingleDiff and (za.maxDiffs or 1) > 1 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Сложности и добыча:", 1, 0.82, 0)
            for dId = 1, za.maxDiffs do
                local bd = za.byDiff and za.byDiff[dId]
                local isCur = (dId == curDiff)
                local prefix = isCur and "> " or "  "
                local suffix = isCur and " (выбрана)" or ""
                local clr = isCur and "|cffffd200" or "|cffcccccc"
                if bd and bd.total > 0 then
                    if (bd.newCount or 0) == 0 and (bd.forgeCount or 0) == 0 then
                        GameTooltip:AddDoubleLine(
                            clr .. prefix .. diffLabels[dId] .. suffix .. "|r",
                            string.format("|cff40ff40Все собрано (%d из %d)|r", bd.completed or 0, bd.total)
                        )
                    else
                        GameTooltip:AddDoubleLine(
                            clr .. prefix .. diffLabels[dId] .. suffix .. "|r",
                            string.format("|cff40ff40Новых: %d|r  |cffffd200Ковка: %d|r  |cff38bdf8(+%s статов)|r",
                                bd.newCount or 0, bd.forgeCount or 0, FormatStatValue(bd.remainStats or 0))
                        )
                    end
                else
                    GameTooltip:AddDoubleLine("|cff666666" .. prefix .. diffLabels[dId] .. suffix .. "|r", "|cff666666Нет предметов|r")
                end
            end
        elseif za.totalPool and za.totalPool > 0 then
            GameTooltip:AddLine(" ")
            local donePct = math.floor(((za.completedCount or 0) / za.totalPool) * 100 + 0.5)
            GameTooltip:AddDoubleLine(
                "Прогресс по зоне:",
                string.format("%d из %d завершено до 90%% (%d%%)", za.completedCount or 0, za.totalPool, donePct),
                1, 0.82, 0, 0.25, 1, 0.45
            )
        end

        GameTooltip:AddLine(" ")
        if za.modeAvailable == false then
            GameTooltip:AddLine("В этом рейде нет выбранной сложности (" .. (diffLabels[curDiff] or "") .. ").", 0.75, 0.45, 0.45)
        elseif (za.totalPool or 0) > 0 then
            local secTitle = (not za.isSingleDiff and diffLabels[curDiff])
                and ("Что осталось добыть (" .. diffLabels[curDiff] .. "):")
                or  "Что осталось добыть (единая сложность):"
            GameTooltip:AddLine(secTitle, 0.22, 0.74, 0.97)

            if (za.newCount or 0) > 0 then
                GameTooltip:AddDoubleLine(
                    "  Новые предметы:",
                    string.format("|cff40ff40%d шт.|r  (+%s сразу, до +%s статов)",
                        za.newCount, FormatStatValue(za.newImmediateStats or 0), FormatStatValue(za.newMaxStats or 0)),
                    0.92, 0.92, 0.92, 1, 1, 1
                )
            else
                GameTooltip:AddDoubleLine("  Новые предметы:", "|cff40ff40Все получены|r", 0.92, 0.92, 0.92, 0.25, 1, 0.45)
            end

            if (za.forgeCount or 0) > 0 then
                GameTooltip:AddDoubleLine(
                    "  Доковать до Титанического (90%):",
                    string.format("|cffffd200%d шт.|r  (+%s статов осталось)",
                        za.forgeCount, FormatStatValue(za.forgeRemainStats or 0)),
                    0.92, 0.92, 0.92, 1, 1, 1
                )
                local fb = za.forgeByTier or {}
                local tParts = {}
                if (fb[0] or 0) > 0 then table.insert(tParts, "Без ковки (20%): " .. fb[0]) end
                if (fb[1] or 0) > 0 then table.insert(tParts, "Эпических (30%): " .. fb[1]) end
                if (fb[2] or 0) > 0 then table.insert(tParts, "Легендарных (50%): " .. fb[2]) end
                if #tParts > 0 then
                    GameTooltip:AddLine("    " .. table.concat(tParts, "  |  "), 0.75, 0.78, 0.85)
                end
            else
                GameTooltip:AddDoubleLine("  Доковать до Титанического (90%):", "|cff40ff40Все докачано|r", 0.92, 0.92, 0.92, 0.25, 1, 0.45)
            end

            if (za.randomSuffixNew or 0) + (za.randomSuffixForge or 0) > 0 then
                GameTooltip:AddDoubleLine(
                    "  Со случайным суффиксом:",
                    string.format("|cffccccccновых: %d, ковка: %d|r", za.randomSuffixNew or 0, za.randomSuffixForge or 0),
                    0.8, 0.8, 0.8, 1, 1, 1
                )
            end
            if (za.noReqCount or 0) > 0 then
                GameTooltip:AddDoubleLine("  Без требуемого уровня (1 ур.):", string.format("|cff66ffcc%d шт.|r", za.noReqCount), 0.8, 0.8, 0.8, 1, 1, 1)
            end
            if za.bestProgressItem then
                GameTooltip:AddDoubleLine(
                    string.format("  Почти готово (%d в работе):", za.inProgressCount or 1),
                    string.format("|cffffd200%s (%d%%)|r", za.bestProgressItem.name or "", za.bestProgressItem.pct or 0),
                    0.85, 0.85, 0.85, 1, 1, 1
                )
            end
            local readyList = GetZoneOwnedReadyItems(data.attune)
            if readyList and #readyList > 0 then
                local rStats, plCnt, blCnt = 0, 0, 0
                for _, it in ipairs(readyList) do
                    rStats = rStats + (it.gainNowStats or 0)
                    if it.where == "petloot" then plCnt = plCnt + 1 end
                    if it.isBlacklisted then blCnt = blCnt + 1 end
                end
                local whereLbl = (plCnt > 0) and "  В наличии (включая Сборщик):" or "  В наличии (сумки/экип./банк):"
                local blSuffix = (blCnt > 0) and (" |cffff6060(ЧС: " .. blCnt .. ")|r") or ""
                GameTooltip:AddDoubleLine(
                    whereLbl,
                    string.format("|cff40ff40%d шт.|r (+%s статов сейчас)%s", #readyList, FormatStatValue(rStats), blSuffix),
                    0.85, 0.95, 0.85, 1, 1, 1
                )
            end
            local gift = ap.GetActiveDailyGift and ap:GetActiveDailyGift() or nil
            if gift and gift.isWednesday and ((za.newCount or 0) + (za.forgeCount or 0)) > 0 then
                GameTooltip:AddDoubleLine(
                    "  Дар Среды (ковка с дропа):",
                    string.format("|cffbb79e8%d предм. не на Титанике|r", (za.newCount or 0) + (za.forgeCount or 0)),
                    0.88, 0.78, 0.98, 1, 1, 1
                )
            end

            if za.statBreakdown then
                local stPairs = {}
                for sid, sv in pairs(za.statBreakdown) do
                    if sv > 0 then table.insert(stPairs, { id = sid, val = sv }) end
                end
                table.sort(stPairs, function(a, b) return a.val > b.val end)
                if #stPairs > 0 then
                    local parts = {}
                    for idx = 1, math.min(4, #stPairs) do
                        local nm = (ap.STAT_NAMES and ap.STAT_NAMES[stPairs[idx].id]) or ("Стат " .. stPairs[idx].id)
                        table.insert(parts, nm .. " +" .. FormatStatValue(stPairs[idx].val))
                    end
                    GameTooltip:AddLine("  Главные статы: |cff33ff99" .. table.concat(parts, ", ") .. "|r", 0.9, 0.9, 0.9, true)
                end
            end

            if (za.unknownStatsCount or 0) > 0 then
                GameTooltip:AddLine("  Дозагрузка характеристик в кэш: " .. za.unknownStatsCount .. " предм.", 0.6, 0.65, 0.72)
            end
        end
    elseif data.attune then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Модуль AttuneParser не загружен.", 0.8, 0.5, 0.3)
    end

    if IsInstanceLocked(data.name) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("КД сохранено (подложка подсвечена зеленым)", 0.2, 1, 0.3)
    end

    GameTooltip:AddLine(" ")
    local k = TalorianTP_DB and TalorianTP_DB.interactKey or "ъ"
    GameTooltip:AddLine("ЛКМ: выбрать цель, призвать и пометить Талориана " .. ICON_DIAMOND .. " (Бинд: [" .. k .. "])", 0.2, 1, 0.4)
    GameTooltip:AddLine("Shift+ЛКМ: открыть Атлас Поглощения", 0.65, 0.7, 0.78)
    GameTooltip:Show()
end


---------------------------------------------------------------------------
-- Фирменный скин WoW Prime (AtlasTexture.blp + бронзово-золотой fallback)
---------------------------------------------------------------------------
local PS = {}
do
    local ATLAS_FILE = "Interface\\Peark\\AtlasTexture.blp"
    local WHITE = "Interface\\Buttons\\WHITE8X8"
    local CAP = 22
    local ATLAS = {
        WINDOW    = {    0,   0, 1366, 1024 },
        CLOSE     = { 1385,  16, 1428,   59 },
        BTN_GREEN = { 1382,  82, 1608,  129 },
        BTN_DARK  = { 1382, 141, 1608,  190 },
        BTN_RED   = { 1383, 347, 1650,  403 },
        BTN_GRAY  = { 1385, 433, 1650,  487 },
    }
    local KIND_KEY = {
        green = "BTN_GREEN",
        dark  = "BTN_DARK",
        red   = "BTN_RED",
        gray  = "BTN_GRAY",
        gold  = "BTN_DARK",
    }
    local FALLBACK_BG = {
        green = { 0.10, 0.34, 0.14, 0.95, 0.25, 0.78, 0.34, 1 },
        dark  = { 0.11, 0.10, 0.09, 0.95, 0.48, 0.40, 0.22, 0.9 },
        red   = { 0.38, 0.11, 0.11, 0.95, 0.74, 0.26, 0.24, 1 },
        gray  = { 0.15, 0.14, 0.13, 0.90, 0.35, 0.32, 0.28, 0.8 },
        gold  = { 0.25, 0.19, 0.08, 0.96, 0.98, 0.80, 0.28, 1 },
    }
    local hasAtlas = nil
    local function CheckAtlas()
        if hasAtlas ~= nil then return hasAtlas end
        local probe = UIParent:CreateTexture(nil, "BACKGROUND")
        local ok = probe:SetTexture(ATLAS_FILE)
        hasAtlas = (ok and probe:GetTexture() ~= nil) and true or false
        probe:SetTexture(nil)
        probe:Hide()
        return hasAtlas
    end
    local function SetAtlasUV(tex, r, u0, u1)
        local l, rt = r[1], r[3]
        if u0 then
            local span = rt - l
            rt = l + span * (u1 or 1)
            l = l + span * u0
        end
        tex:SetTexture(ATLAS_FILE)
        tex:SetTexCoord(l / 2048, rt / 2048, r[2] / 1024, r[4] / 1024)
    end
    function PS.ApplyWindow(f)
        if not f then return end
        if CheckAtlas() then
            f:SetBackdrop(nil)
            if not f._psBg then
                local bg = f:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints(f)
                SetAtlasUV(bg, ATLAS.WINDOW)
                f._psBg = bg
            end
        else
            f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
            f:SetBackdropColor(0.09, 0.08, 0.07, 0.96)
            f:SetBackdropBorderColor(0.62, 0.52, 0.30, 1)
        end
    end
    function PS.StyleBox(f, aBg, goldBorder)
        if not f then return end
        f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        f:SetBackdropColor(0.02, 0.02, 0.02, aBg or 0.45)
        if goldBorder then
            f:SetBackdropBorderColor(0.88, 0.72, 0.28, 0.95)
        else
            f:SetBackdropBorderColor(0.50, 0.42, 0.24, 0.82)
        end
    end
    function PS.StyleClose(btn, sz)
        if not btn then return end
        if CheckAtlas() then
            btn:SetBackdrop(nil)
            btn:SetSize(sz or 26, sz or 26)
            for _, rg in ipairs({ btn:GetRegions() }) do
                if rg.GetObjectType and rg:GetObjectType() == "FontString" then rg:Hide() end
            end
            if not btn._psTex then
                local t = btn:CreateTexture(nil, "ARTWORK")
                t:SetAllPoints(btn)
                SetAtlasUV(t, ATLAS.CLOSE)
                btn._psTex = t
                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints(btn)
                hl:SetBlendMode("ADD")
                hl:SetAlpha(0.45)
                SetAtlasUV(hl, ATLAS.CLOSE)
                btn:SetHighlightTexture(hl)
                btn:HookScript("OnMouseDown", function(self) self._psTex:SetVertexColor(0.75, 0.75, 0.75) end)
                btn:HookScript("OnMouseUp", function(self) self._psTex:SetVertexColor(1, 1, 1) end)
            end
        else
            btn:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
            btn:SetBackdropColor(0.38, 0.11, 0.11, 0.95)
            btn:SetBackdropBorderColor(0.65, 0.48, 0.22, 1)
        end
    end
    function PS.PaintBtn(b, kind, tint)
        if not b then return end
        kind = kind or b._psKind or "dark"
        b._psKind = kind
        if b._psSlices then
            local r = ATLAS[KIND_KEY[kind] or "BTN_DARK"]
            local u = CAP / (r[3] - r[1])
            SetAtlasUV(b._psSlices[1], r, 0, u)
            SetAtlasUV(b._psSlices[2], r, u, 1 - u)
            SetAtlasUV(b._psSlices[3], r, 1 - u, 1)
            for i = 1, 3 do
                if tint then
                    b._psSlices[i]:SetVertexColor(tint[1], tint[2], tint[3])
                else
                    b._psSlices[i]:SetVertexColor(1, 1, 1)
                end
            end
            if b._psGoldRing then
                if kind == "gold" then b._psGoldRing:Show() else b._psGoldRing:Hide() end
            end
        else
            local fb = FALLBACK_BG[kind] or FALLBACK_BG.dark
            b:SetBackdropColor(fb[1], fb[2], fb[3], fb[4])
            b:SetBackdropBorderColor(fb[5], fb[6], fb[7], fb[8])
        end
    end
    function PS.StyleBtn(b, kind)
        if not b then return end
        if CheckAtlas() then
            b:SetBackdrop(nil)
            local r = ATLAS[KIND_KEY[kind or "dark"] or "BTN_DARK"]
            local h = b:GetHeight()
            if not h or h < 1 then h = 24 end
            local cap = math.floor(CAP * h / (r[4] - r[2]) + 0.5)
            if cap < 4 then cap = 4 end
            if not b._psSlices then
                local sl = {}
                for i = 1, 3 do sl[i] = b:CreateTexture(nil, "BACKGROUND") end
                sl[1]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
                sl[1]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
                sl[1]:SetWidth(cap)
                sl[3]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
                sl[3]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
                sl[3]:SetWidth(cap)
                sl[2]:SetPoint("TOPLEFT", sl[1], "TOPRIGHT", 0, 0)
                sl[2]:SetPoint("BOTTOMRIGHT", sl[3], "BOTTOMLEFT", 0, 0)
                b._psSlices = sl

                local gr = CreateFrame("Frame", nil, b)
                gr:SetAllPoints(b)
                gr:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
                gr:SetBackdropBorderColor(1.00, 0.82, 0.30, 0.95)
                gr:Hide()
                b._psGoldRing = gr

                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetPoint("TOPLEFT", 1, -1)
                hl:SetPoint("BOTTOMRIGHT", -1, 1)
                hl:SetBlendMode("ADD")
                hl:SetAlpha(0.28)
                SetAtlasUV(hl, ATLAS.BTN_GREEN)
                b:SetHighlightTexture(hl)
            end
        else
            b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        end
        PS.PaintBtn(b, kind or "dark")
    end
    function PS.AttachScroll(parent, listHeight, rowH, visCount, onUpdateFn, globalName)
        local sf = CreateFrame("Frame", globalName, parent)
        sf.offset = 0
        sf._offset = 0
        sf.total = 0
        sf.visCount = visCount
        sf:EnableMouseWheel(true)

        local BTN_H = 16
        local bar = CreateFrame("Frame", nil, sf)
        bar:SetWidth(14)
        bar:SetHeight(math.max(40, (listHeight or 100) - 4))
        bar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, -2)
        bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 2)
        bar:SetFrameLevel(((sf.GetFrameLevel and sf:GetFrameLevel()) or 1) + 6)
        bar:EnableMouse(true)
        bar:EnableMouseWheel(true)
        PS.StyleBox(bar, 0.72, false)

        local isDragging, dragStartY, dragStartOff = false, 0, 0
        local up, dn, thumb

        local function getCursorY()
            if type(GetCursorPosition) ~= "function" then return nil end
            local _, cy = GetCursorPosition()
            if not cy then return nil end
            local sc = (bar.GetEffectiveScale and bar:GetEffectiveScale()) or 1
            if not sc or sc <= 0 then sc = 1 end
            return cy / sc
        end

        local function paintThumb(active)
            if not thumb then return end
            if active then
                thumb:SetBackdropColor(0.98, 0.78, 0.30, 1.0)
                thumb:SetBackdropBorderColor(1.0, 0.92, 0.54, 1.0)
            else
                thumb:SetBackdropColor(0.82, 0.63, 0.22, 0.92)
                thumb:SetBackdropBorderColor(1.0, 0.86, 0.38, 0.95)
            end
        end

        local function layoutThumb()
            local maxOff = math.max(0, (sf.total or 0) - visCount)
            if maxOff <= 0 then
                isDragging = false
                bar:Hide()
                return
            end
            bar:Show()
            local bTop = bar.GetTop and bar:GetTop()
            local bBot = bar.GetBottom and bar:GetBottom()
            local bh = (bTop and bBot and (bTop > bBot)) and (bTop - bBot) or bar:GetHeight()
            if not bh or bh <= 1 then bh = math.max(40, (listHeight or 100) - 4) end
            local trackH = math.max(24, bh - (BTN_H * 2 + 4))
            local thumbH = math.max(20, math.floor(trackH * (visCount / math.max(1, sf.total))))
            if thumbH > trackH then thumbH = trackH end
            local travel = math.max(0, trackH - thumbH)
            sf._trackH = trackH
            sf._thumbH = thumbH
            sf._travel = travel
            if thumb then
                thumb:SetHeight(thumbH)
                local yOff = math.floor(travel * (sf.offset / maxOff) + 0.5)
                thumb:ClearAllPoints()
                thumb:SetPoint("TOP", bar, "TOP", 0, -(BTN_H + 2 + yOff))
            end
        end

        local function clampAndRefresh(newOff)
            local maxOff = math.max(0, (sf.total or 0) - visCount)
            newOff = math.floor((newOff or 0) + 0.5)
            if newOff < 0 then newOff = 0 end
            if newOff > maxOff then newOff = maxOff end
            sf.offset = newOff
            sf._offset = newOff
            layoutThumb()
            if onUpdateFn then onUpdateFn(sf.offset) end
        end

        local function makeArrow(isUp)
            local b = CreateFrame("Button", nil, bar)
            b:SetSize(14, BTN_H)
            b:SetPoint(isUp and "TOP" or "BOTTOM", bar, isUp and "TOP" or "BOTTOM", 0, 0)
            b:SetFrameLevel(((bar.GetFrameLevel and bar:GetFrameLevel()) or 1) + 2)
            b:EnableMouse(true)
            b:EnableMouseWheel(true)
            PS.StyleBox(b, 0.92, false)
            b:SetBackdropBorderColor(0.58, 0.48, 0.25, 0.92)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetPoint("TOPLEFT", 1, -1)
            hl:SetPoint("BOTTOMRIGHT", -1, 1)
            hl:SetTexture(0.95, 0.78, 0.28, 0.28)
            b:SetHighlightTexture(hl)
            local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("CENTER", 0, isUp and -1 or 1)
            fs:SetText(isUp and "^" or "v")
            fs:SetTextColor(0.98, 0.84, 0.36)
            b._fs = fs
            local stepMag = math.max(1, math.floor(visCount / 5))
            b._step = isUp and -stepMag or stepMag
            b:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(0.96, 0.78, 0.30, 1)
            end)
            b:SetScript("OnLeave", function(self)
                if not self._held then self:SetBackdropBorderColor(0.58, 0.48, 0.25, 0.92) end
            end)
            b:SetScript("OnMouseDown", function(self, mBtn)
                if mBtn and mBtn ~= "LeftButton" then return end
                self._held = true
                self._holdT = 0
                self._repT = 0
                self._upAt = nil
                self._mouseStepped = true
                self:SetBackdropBorderColor(1.0, 0.86, 0.36, 1)
                clampAndRefresh((sf.offset or 0) + self._step)
            end)
            b:SetScript("OnMouseUp", function(self, mBtn)
                if mBtn and mBtn ~= "LeftButton" then return end
                self._held = false
                self._holdT = 0
                self._repT = 0
                self._upAt = 0
                self:SetBackdropBorderColor(0.58, 0.48, 0.25, 0.92)
            end)
            b:SetScript("OnClick", function(self)
                if self._mouseStepped then
                    self._mouseStepped = false
                    self._upAt = nil
                    return
                end
                clampAndRefresh((sf.offset or 0) + self._step)
            end)
            return b
        end

        up = makeArrow(true)
        dn = makeArrow(false)

        thumb = CreateFrame("Button", nil, bar)
        thumb:SetSize(12, 24)
        thumb:SetPoint("TOP", bar, "TOP", 0, -(BTN_H + 2))
        thumb:SetFrameLevel(((bar.GetFrameLevel and bar:GetFrameLevel()) or 1) + 2)
        thumb:EnableMouse(true)
        thumb:EnableMouseWheel(true)
        PS.StyleBox(thumb, 0.94, true)
        paintThumb(false)
        local thl = thumb:CreateTexture(nil, "HIGHLIGHT")
        thl:SetPoint("TOPLEFT", 1, -1)
        thl:SetPoint("BOTTOMRIGHT", -1, 1)
        thl:SetTexture(1.0, 0.88, 0.42, 0.26)
        thumb:SetHighlightTexture(thl)

        thumb:SetScript("OnEnter", function() paintThumb(true) end)
        thumb:SetScript("OnLeave", function() if not isDragging then paintThumb(false) end end)
        thumb:SetScript("OnMouseDown", function(_, mBtn)
            if mBtn and mBtn ~= "LeftButton" then return end
            local maxOff = math.max(0, (sf.total or 0) - visCount)
            if maxOff <= 0 then return end
            local cy = getCursorY()
            dragStartY = cy or 0
            dragStartOff = sf.offset or 0
            isDragging = (cy ~= nil)
            paintThumb(true)
        end)
        thumb:SetScript("OnMouseUp", function(_, mBtn)
            if mBtn and mBtn ~= "LeftButton" then return end
            isDragging = false
            paintThumb(false)
        end)

        bar:SetScript("OnMouseDown", function(self, mBtn)
            if mBtn and mBtn ~= "LeftButton" then return end
            local maxOff = math.max(0, (sf.total or 0) - visCount)
            if maxOff <= 0 then return end
            local cy = getCursorY()
            local bTop = self.GetTop and self:GetTop()
            local travel = sf._travel or 0
            if cy and bTop and travel > 0 then
                local frac = ((bTop - (BTN_H + 2)) - (sf._thumbH or 20) * 0.5 - cy) / travel
                if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
                clampAndRefresh(math.floor(frac * maxOff + 0.5))
                dragStartY = cy
                dragStartOff = sf.offset or 0
                isDragging = true
                paintThumb(true)
            else
                local pg = math.max(1, visCount - 1)
                local bCen = (bTop and self.GetBottom and self:GetBottom()) and ((bTop + self:GetBottom()) * 0.5)
                if cy and bCen and cy > bCen then pg = -pg end
                clampAndRefresh((sf.offset or 0) + pg)
            end
        end)
        bar:SetScript("OnMouseUp", function(_, mBtn)
            if mBtn and mBtn ~= "LeftButton" then return end
            isDragging = false
            paintThumb(false)
        end)
        bar:SetScript("OnHide", function()
            isDragging = false
            up._held = false; up._mouseStepped = false; up._upAt = nil
            dn._held = false; dn._mouseStepped = false; dn._upAt = nil
            up:SetBackdropBorderColor(0.58, 0.48, 0.25, 0.92)
            dn:SetBackdropBorderColor(0.58, 0.48, 0.25, 0.92)
            paintThumb(false)
        end)
        bar:SetScript("OnSizeChanged", function()
            if (sf.total or 0) > visCount then layoutThumb() end
        end)
        bar:SetScript("OnUpdate", function(_, elapsed)
            if not isDragging and not up._held and not dn._held and not up._mouseStepped and not dn._mouseStepped then
                return
            end
            if (isDragging or up._held or dn._held) and type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
                isDragging = false
                up._held = false
                dn._held = false
                up:SetBackdropBorderColor(0.58, 0.48, 0.25, 0.92)
                dn:SetBackdropBorderColor(0.58, 0.48, 0.25, 0.92)
                paintThumb(false)
            end
            local el = elapsed or 0
            if isDragging then
                local cy = getCursorY()
                local travel = sf._travel or 0
                local maxOff = math.max(0, (sf.total or 0) - visCount)
                if cy and travel > 0 and maxOff > 0 then
                    local dy = dragStartY - cy
                    local tgt = math.floor(dragStartOff + (dy / travel) * maxOff + 0.5)
                    if tgt < 0 then tgt = 0 elseif tgt > maxOff then tgt = maxOff end
                    if tgt ~= (sf.offset or 0) then clampAndRefresh(tgt) end
                end
            end
            for _, btn in ipairs({ up, dn }) do
                if btn._held then
                    btn._holdT = (btn._holdT or 0) + el
                    if btn._holdT >= 0.28 then
                        btn._repT = (btn._repT or 0) + el
                        if btn._repT >= 0.065 then
                            btn._repT = 0
                            clampAndRefresh((sf.offset or 0) + btn._step)
                        end
                    end
                elseif btn._mouseStepped then
                    btn._upAt = (btn._upAt or 0) + el
                    if btn._upAt >= 0.12 then
                        btn._mouseStepped = false
                        btn._upAt = nil
                    end
                end
            end
        end)

        local function onWheel(_, delta)
            local step = (delta > 0) and -2 or 2
            clampAndRefresh((sf.offset or 0) + step)
        end
        sf:SetScript("OnMouseWheel", onWheel)
        bar:SetScript("OnMouseWheel", onWheel)
        up:SetScript("OnMouseWheel", onWheel)
        dn:SetScript("OnMouseWheel", onWheel)
        thumb:SetScript("OnMouseWheel", onWheel)

        function sf:SetTotal(totalCount, keepOffset)
            sf.total = totalCount or 0
            clampAndRefresh(keepOffset and (sf.offset or 0) or 0)
        end
        function sf:SyncCount(totalCount)
            if self._inSync then return end
            self._inSync = true
            self._skipRender = true
            self:SetTotal(totalCount or 0, true)
            self._skipRender = false
            self._inSync = false
        end
        sf._bar = bar
        sf._up = up
        sf._dn = dn
        sf._thumb = thumb
        sf._OnWheel = function(arg1, arg2, arg3)
            onWheel(sf, (type(arg1) == "number" and arg1) or (type(arg2) == "number" and arg2) or arg3 or 0)
        end
        sf._ScrollTo = function(arg1, arg2)
            clampAndRefresh((type(arg1) == "number" and arg1) or arg2 or 0)
        end
        return sf
    end
    TalorianTP.Skin = PS
end

---------------------------------------------------------------------------
-- Окно оповещения по центру экрана
---------------------------------------------------------------------------
CreateNoticeFrame = function()
    if noticeFrame then return noticeFrame end
    local nf = CreateFrame("Frame", "TalorianNoticeFrame", UIParent)
    nf:SetSize(620, 36)
    nf:SetPoint("TOP", 0, -24)
    nf:SetFrameStrata("FULLSCREEN_DIALOG")
    nf:SetFrameLevel(120)
    nf:EnableMouse(false)

    PS.StyleBox(nf, 0.92, true)
    nf:SetBackdropColor(0.08, 0.07, 0.06, 0.94)

    local txt = nf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if txt.GetFont and txt.SetFont then
        local fontPath, fontSize, fontFlags = txt:GetFont()
        if fontPath then
            txt:SetFont(fontPath, (fontSize or 14) - 2, fontFlags or "OUTLINE")
        elseif _G.STANDARD_TEXT_FONT then
            txt:SetFont(_G.STANDARD_TEXT_FONT, 12, "OUTLINE")
        end
    elseif txt.SetFont and _G.STANDARD_TEXT_FONT then
        txt:SetFont(_G.STANDARD_TEXT_FONT, 12, "OUTLINE")
    end
    txt:SetPoint("CENTER", 0, 0)
    txt:SetTextColor(1, 0.90, 0.2, 1)
    nf.txt = txt

    nf.timer = 0
    nf:SetScript("OnUpdate", function(self, elapsed)
        if self.timer > 0 then
            self.timer = self.timer - elapsed
            if self.timer <= 0 then
                self:Hide()
            elseif self.timer < 0.6 then
                self:SetAlpha(self.timer / 0.6)
            end
        end
    end)

    function nf:ShowNotice(msg)
        if not msg or msg == "" then return end
        if noticeShownCount >= MAX_NOTICES_PER_SELECTION then return end
        noticeShownCount = noticeShownCount + 1
        self.txt:SetText(msg)
        self:SetAlpha(1)
        self.timer = 4.0
        self:Show()
    end

    nf:Hide()
    noticeFrame = nf
    return nf
end

---------------------------------------------------------------------------
-- Основной интерфейс (Midnight Blue UI)
---------------------------------------------------------------------------
local function RegisterSpecialFrame(name)
    if not name or name == "" then return end
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    for _, v in ipairs(_G.UISpecialFrames) do
        if v == name then return end
    end
    table.insert(_G.UISpecialFrames, name)
end

do
    local UI_BLOCK_DEFS = {
        {
            key = "modeBar",
            title = "Панель режимов (Телепорт / Баффер / Банк / Магазин / Аукцион)",
            desc = "Верхние переключатели взаимодействия с Талорианом. Скройте, если используете аддон только для телепорта.",
            default = true,
        },
        {
            key = "diffBar",
            title = "Панель сложности и быстрые рейды",
            desc = "Кнопки 10/25 об/гер (и 5 об/гер), 4 быстрых слота (ЦЛК, ИК, РС, Накс) и +4M. Скройте для чистого списка локаций.",
            default = true,
        },
        {
            key = "cardProgress",
            title = "Прогресс освоения и статы на карточках",
            desc = "Проценты, число новых/ковочных вещей, прирост статов и полоска прогресса. Отключите для максимально легкого вида.",
            default = true,
        },
        {
            key = "headerUtils",
            title = "Кнопки шапки (Сброс КД, Бинд, Вкл/Выкл)",
            desc = "Кнопки «Сброс КД (.in un all)», быстрая переназначка клавиши бинда и переключатель работы аддона.",
            default = true,
        },
        {
            key = "bottomTools",
            title = "Нижняя панель инструментов и статуса",
            desc = "Строка бинда и кнопки внизу окна: «Атлас и Топ», «Вещи по инстам» и кнопка быстрого макроса цели.",
            default = true,
        },
        {
            key = "tabServer",
            title = "Вкладка «Спутники и Наборы»",
            desc = "Серверная панель: баффы помощника, спутники, сейф золота, Талисман на голову, пресеты билдов и указатель цели.",
            default = true,
        },
        {
            key = "srvCol1",
            title = "  - Спутники: Баффы, Питомцы и Сейф золота",
            desc = "Левая колонка вкладки «Спутники»: баффы Талориана, доп. спутники, автопризыв и быстрые переводы в сейф.",
            default = true,
        },
        {
            key = "srvCol2",
            title = "  - Спутники: Талисман, Сложность и Счетчик",
            desc = "Средняя колонка вкладки «Спутники»: наборы Талисмана на голову, сложность данжей (Титанич./Эпох.) и DPS/Paragon-метр.",
            default = true,
        },
        {
            key = "srvCol3",
            title = "  - Спутники: Билды и Указатель цели",
            desc = "Правая колонка вкладки «Спутники»: 3 слота сохранения талантов/ковки, 3D-стрелка к цели и подсветка цели/фокуса.",
            default = true,
        },
        {
            key = "minimapBtn",
            title = "Кнопка у миникарты",
            desc = "Значок Talorian вокруг миникарты (главное окно всегда доступно по команде /ttp).",
            default = true,
        },
        {
            key = "auctionTrade",
            title = "Помощник ковки на аукционе",
            desc = "Кнопка и окно фильтрации непоглощенных и недокованных вещей на аукционе.",
            default = true,
        },
    }
    TalorianTP.UI_BLOCK_DEFS = UI_BLOCK_DEFS

    local BLOCK_PRESETS = {
        full = {},
        minimal = {
            modeBar = false,
            diffBar = true,
            cardProgress = false,
            headerUtils = false,
            bottomTools = false,
            tabServer = false,
            srvCol1 = false,
            srvCol2 = false,
            srvCol3 = false,
            minimapBtn = true,
            auctionTrade = false,
        },
        teleport_progress = {
            modeBar = true,
            diffBar = true,
            cardProgress = true,
            headerUtils = true,
            bottomTools = true,
            tabServer = false,
            srvCol1 = false,
            srvCol2 = false,
            srvCol3 = false,
            minimapBtn = true,
            auctionTrade = true,
        },
    }

    local onboardingFrame = nil

    function TalorianTP:EnsureUIDB()
        TalorianTP_DB = TalorianTP_DB or {}
        if type(TalorianTP_DB.uiBlocks) ~= "table" then
            TalorianTP_DB.uiBlocks = {}
        end
        local blk = TalorianTP_DB.uiBlocks
        for _, def in ipairs(UI_BLOCK_DEFS) do
            if blk[def.key] == nil then
                if def.key == "auctionTrade" and TalorianTP_DB.hideAuctionPanel == true then
                    blk[def.key] = false
                else
                    blk[def.key] = (def.default ~= false)
                end
            end
        end
        if TalorianTP_DB.uiOnboardingDone == nil then
            TalorianTP_DB.uiOnboardingDone = false
        end
        return blk
    end

    function TalorianTP:IsBlockEnabled(key)
        local blk = self:EnsureUIDB()
        return blk[key] ~= false
    end

    local function SyncExternalBlockState(key, val)
        if key == "auctionTrade" then
            TalorianTP_DB.hideAuctionPanel = not val
            local ap = rawget(_G, "AttuneParser")
            if ap and ap._hasStandaloneAuctionUI and ap.SetSetting then
                ap:SetSetting("showAuctionUI", val)
            elseif TalorianTP_RefreshAuctionHelper then
                TalorianTP_RefreshAuctionHelper()
            end
        elseif key == "minimapBtn" then
            local mm = rawget(_G, "TalorianMinimapButton")
            if val then
                if mm and mm.Show then mm:Show() end
            elseif mm and mm.Hide then
                mm:Hide()
            end
        end
    end

    function TalorianTP:ApplyUIBlocks()
        if mainUI and mainUI.ApplyBlockLayout then
            mainUI:ApplyBlockLayout()
        end
        local mm = rawget(_G, "TalorianMinimapButton")
        if mm then
            if self:IsBlockEnabled("minimapBtn") then mm:Show() else mm:Hide() end
        end
        if onboardingFrame and onboardingFrame:IsShown() and onboardingFrame.RefreshRows then
            onboardingFrame:RefreshRows()
        end
    end

    function TalorianTP:SetBlockEnabled(key, val, skipApply)
        local blk = self:EnsureUIDB()
        local b = val and true or false
        blk[key] = b
        SyncExternalBlockState(key, b)
        if not skipApply then
            self:ApplyUIBlocks()
        end
        return b
    end

    function TalorianTP:ApplyUIBlockPreset(presetId)
        local blk = self:EnsureUIDB()
        local map = BLOCK_PRESETS[presetId] or {}
        for _, def in ipairs(UI_BLOCK_DEFS) do
            local v = map[def.key]
            if v == nil then v = true end
            blk[def.key] = v and true or false
            SyncExternalBlockState(def.key, blk[def.key])
        end
        self:ApplyUIBlocks()
    end

    local function MakeUiCheck(parent, x, y, w, h, label, getFn, setFn, tipTitle, tipDesc)
        local row = CreateFrame("Button", nil, parent)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        row:SetSize(w, h or 20)
        local chk = CreateFrame("Frame", nil, row)
        chk:SetSize(16, 16)
        chk:SetPoint("LEFT", row, "LEFT", 0, 0)
        PS.StyleBox(chk, 0.72, false)
        local mk = chk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mk:SetPoint("CENTER", 0, 0)
        local txt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", chk, "RIGHT", 6, 0)
        txt:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        txt:SetJustifyH("LEFT")
        if txt.SetWordWrap then txt:SetWordWrap(false) end
        txt:SetText(label)

        row:SetScript("OnClick", function()
            setFn(not getFn())
            row:UpdateState()
        end)
        if tipDesc then
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tipTitle or label, 1, 0.85, 0.25)
                GameTooltip:AddLine(tipDesc, 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        function row:UpdateState()
            local on = getFn()
            if on then
                mk:SetText("|cff40ff40V|r")
                PS.StyleBox(chk, 0.80, true)
                txt:SetTextColor(0.95, 0.95, 0.95)
            else
                mk:SetText("")
                PS.StyleBox(chk, 0.55, false)
                txt:SetTextColor(0.62, 0.66, 0.72)
            end
        end
        row:UpdateState()
        return row
    end

    local function CreateSimpleBtn(parent, x, y, w, h, text, kind, onClick, tip)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(w, h)
        if x and y then b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y) end
        PS.StyleBtn(b, kind or "dark")
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", 0, 0)
        fs:SetText(text)
        b.txt = fs
        if onClick then b:SetScript("OnClick", onClick) end
        if tip then
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(text, 1, 0.85, 0.25)
                GameTooltip:AddLine(tip, 0.9, 0.9, 0.9, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return b
    end

    function TalorianTP._BuildSettingsPanel(f, contentFrame)
        local sp = CreateFrame("Frame", nil, contentFrame)
        sp:SetAllPoints()
        f.settingsPanel = sp

        local sTitle = sp:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        sTitle:SetPoint("TOPLEFT", 4, -2)
        sTitle:SetText("|cfffce08cНастройка интерфейса и быстрые макросы|r")

        local sDesc = sp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sDesc:SetPoint("TOPLEFT", 4, -22)
        sDesc:SetJustifyH("LEFT")
        sDesc:SetText("|cff94a3b8Отключайте лишние блоки интерфейса в реальном времени или создавайте макросы в /macro.|r")

        local wizardBtn = CreateSimpleBtn(sp, nil, nil, 240, 26, "|cffffd200Мастер выбора блоков (первый запуск)|r", "gold", function()
            TalorianTP:ShowOnboardingWizard(true)
        end, "Открывает удобное окно с подробным описанием каждого блока и быстрыми пресетами.")
        wizardBtn:SetPoint("TOPRIGHT", sp, "TOPRIGHT", -2, -6)

        local function AddDiv(p, y, pad, isGold)
            local d = p:CreateTexture(nil, "ARTWORK")
            d:SetTexture("Interface\\Buttons\\WHITE8X8")
            if isGold then
                d:SetVertexColor(0.95, 0.78, 0.28, 0.25)
            else
                d:SetVertexColor(1, 1, 1, 0.09)
            end
            d:SetHeight(1)
            d:SetPoint("TOPLEFT", pad or 10, y)
            d:SetPoint("TOPRIGHT", -(pad or 10), y)
            return d
        end

        AddDiv(sp, -40, 4, true)

        -- Left Top Card: Character Macros
        local macroCard = CreateFrame("Frame", nil, sp)
        macroCard:SetPoint("TOPLEFT", 2, -46)
        macroCard:SetSize(426, 154)
        PS.StyleBox(macroCard, 0.48, false)

        local mbTitle = macroCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mbTitle:SetPoint("TOPLEFT", 10, -8)
        mbTitle:SetText("|cffffd200Быстрые макросы персонажа (/macro)|r")

        AddDiv(macroCard, -25, 10, false)

        local btnM1 = CreateSimpleBtn(macroCard, 10, -32, 406, 24, "|cfff7dfb5Создать макрос выбранного инста|r", "dark", function()
            TalorianTP_ToggleMacroForDest()
        end)
        f.btnM1 = btnM1

        CreateSimpleBtn(macroCard, 10, -60, 200, 24, "|cffffd2004 топ-рейд макроса|r", "dark", function()
            TalorianTP_CreateMacro_TopRaids()
        end, "Создает макросы ЦЛК, ИК, РС и Наксрамас.")
        CreateSimpleBtn(macroCard, 216, -60, 200, 24, "|cff40ff40Макрос Баффера (T_Баффер)|r", "green", function()
            TalorianTP_CreateMacro_Buffer()
        end, "Макрос быстрого переключения Талориана в режим баффера.")

        AddDiv(macroCard, -90, 10, false)

        local delHint = macroCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        delHint:SetPoint("TOPLEFT", 10, -96)
        delHint:SetText("Очистка макросов TalorianTP:")

        CreateSimpleBtn(macroCard, 10, -114, 200, 24, "|cffff8080Удалить 4 топ-рейд макроса|r", "red", function()
            TalorianTP_Delete_TopRaids()
        end)
        CreateSimpleBtn(macroCard, 216, -114, 200, 24, "|cffff5555Удалить ВСЕ макросы аддона|r", "red", function()
            TalorianTP_DeleteAllTalorianMacros()
        end)

        -- Left Bottom Card: Main Window Block Visibility
        local blkCard = CreateFrame("Frame", nil, sp)
        blkCard:SetPoint("TOPLEFT", 2, -206)
        blkCard:SetPoint("BOTTOMLEFT", 2, 2)
        blkCard:SetWidth(426)
        PS.StyleBox(blkCard, 0.48, false)

        local bcTitle = blkCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bcTitle:SetPoint("TOPLEFT", 10, -8)
        bcTitle:SetText("|cffffd200Отображаемые блоки главного окна|r")

        CreateSimpleBtn(blkCard, 242, -5, 54, 18, "Все", "dark", function() TalorianTP:ApplyUIBlockPreset("full") end, "Включить все блоки интерфейса.")
        CreateSimpleBtn(blkCard, 300, -5, 58, 18, "Мин.", "dark", function() TalorianTP:ApplyUIBlockPreset("minimal") end, "Минимальный режим: только телепорты и столицы.")
        CreateSimpleBtn(blkCard, 362, -5, 54, 18, "Фарм", "dark", function() TalorianTP:ApplyUIBlockPreset("teleport_progress") end, "Телепорты + освоение без вкладки Спутников.")

        AddDiv(blkCard, -26, 10, false)

        local checkRows = {}
        local mainKeys = {
            { "modeBar",      "Панель режимов" },
            { "diffBar",      "Сложность и топ-рейды" },
            { "cardProgress", "Прогресс на карточках" },
            { "headerUtils",  "Сброс КД / Бинд / Статус" },
            { "bottomTools",  "Нижняя панель кнопок" },
            { "tabServer",    "Вкладка «Спутники»" },
            { "minimapBtn",   "Кнопка у миникарты" },
            { "auctionTrade", "Помощник на аукционе" },
        }
        local defByKey = {}
        for _, d in ipairs(UI_BLOCK_DEFS) do defByKey[d.key] = d end

        for idx, item in ipairs(mainKeys) do
            local col = (idx - 1) % 2
            local row = math.floor((idx - 1) / 2)
            local def = defByKey[item[1]]
            checkRows[#checkRows + 1] = MakeUiCheck(
                blkCard,
                10 + col * 206, -34 - row * 24, 200, 22,
                item[2],
                function() return TalorianTP:IsBlockEnabled(item[1]) end,
                function(nv) TalorianTP:SetBlockEnabled(item[1], nv) end,
                def and def.title or item[2],
                def and def.desc
            )
        end

        local tipFoot = blkCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tipFoot:SetPoint("BOTTOMLEFT", 10, 8)
        tipFoot:SetPoint("BOTTOMRIGHT", -10, 8)
        tipFoot:SetJustifyH("LEFT")
        tipFoot:SetText("|cff8896a8Совет: команда /ttp blocks в любой момент откроет мастер с подробным описанием каждого блока.|r")

        -- Right Top Card: Server Tab Sub-blocks
        local srvCard = CreateFrame("Frame", nil, sp)
        srvCard:SetPoint("TOPLEFT", 436, -46)
        srvCard:SetPoint("TOPRIGHT", -2, -46)
        srvCard:SetHeight(124)
        PS.StyleBox(srvCard, 0.48, false)

        local scTitle = srvCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        scTitle:SetPoint("TOPLEFT", 12, -8)
        scTitle:SetText("|cffffd200Блоки внутри «Спутники и Наборы»|r")

        AddDiv(srvCard, -25, 12, false)

        local srvKeys = {
            { "srvCol1", "Баффы помощника, доп. спутники и Сейф золота" },
            { "srvCol2", "Талисман на голову, Сложность данжей и Счетчик XP/DPS" },
            { "srvCol3", "Пресеты талантов/ковки и Указатель цели (3D-стрелка)" },
        }
        for idx, item in ipairs(srvKeys) do
            local def = defByKey[item[1]]
            checkRows[#checkRows + 1] = MakeUiCheck(
                srvCard,
                12, -32 - (idx - 1) * 26, 404, 24,
                item[2],
                function() return TalorianTP:IsBlockEnabled(item[1]) end,
                function(nv) TalorianTP:SetBlockEnabled(item[1], nv) end,
                def and def.title or item[2],
                def and def.desc
            )
        end

        -- Right Bottom Card: Credits & Version Info
        local creditsBox = CreateFrame("Frame", nil, sp)
        creditsBox:SetPoint("TOPLEFT", 436, -176)
        creditsBox:SetPoint("BOTTOMRIGHT", -2, 2)
        PS.StyleBox(creditsBox, 0.48, false)

        local crTitle = creditsBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        crTitle:SetPoint("TOPLEFT", 12, -10)
        crTitle:SetText("|cffffd200О проекте TalorianTP|r |cff38bdf8v" .. TALORIAN_VERSION .. "|r")

        AddDiv(creditsBox, -27, 12, false)

        local crText = creditsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        crText:SetPoint("TOPLEFT", 12, -34)
        crText:SetPoint("RIGHT", -12, 0)
        crText:SetJustifyH("LEFT")
        if crText.SetSpacing then crText:SetSpacing(5) end
        crText:SetText(
            "|cffc8bea8По вопросам писать:|r |cffffd200Sodoesqai|r\n" ..
            "|cffc8bea8Слова благодарности за мотивацию и подсказки:|r |cff40ff40Motherofgod|r\n" ..
            "|cffc8bea8Благодарность|r |cff38bdf8Дуре|r |cffc8bea8за вынос кнопки сброса кд|r\n" ..
            "|cffc8bea8По багам -|r |cff38bdf8https://t.me/sodooqie|r"
        )
        f.creditsText = crText

        local bugLabel = creditsBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        bugLabel:SetPoint("TOPLEFT", 12, -120)
        bugLabel:SetText("Ссылка для копирования (Ctrl+C):")

        local bugEdit = CreateFrame("EditBox", "TalorianBugLinkEditBox", creditsBox)
        bugEdit:SetSize(250, 22)
        bugEdit:SetPoint("TOPLEFT", 12, -136)
        if bugEdit.SetAutoFocus then bugEdit:SetAutoFocus(false) end
        if bugEdit.SetFontObject and GameFontHighlightSmall then bugEdit:SetFontObject(GameFontHighlightSmall) end
        PS.StyleBox(bugEdit, 0.65)
        if bugEdit.SetTextInsets then bugEdit:SetTextInsets(6, 6, 0, 0) end
        if bugEdit.SetText then bugEdit:SetText("https://t.me/sodooqie") end
        bugEdit:SetScript("OnEscapePressed", function(self) if self.ClearFocus then self:ClearFocus() end end)
        bugEdit:SetScript("OnEditFocusGained", function(self) if self.HighlightText then self:HighlightText() end end)
        bugEdit:SetScript("OnChar", function(self)
            if self.SetText then self:SetText("https://t.me/sodooqie") end
            if self.HighlightText then self:HighlightText() end
        end)

        CreateSimpleBtn(creditsBox, 268, -136, 144, 22, "Снова показать мастер", "dark", function()
            TalorianTP:ShowOnboardingWizard(true)
        end)

        function f:UpdateSettingsUI()
            for _, r in ipairs(checkRows) do
                if r and r.UpdateState then r:UpdateState() end
            end
        end
    end

    function TalorianTP:ShowOnboardingWizard(force)
        self:EnsureUIDB()
        if not force and TalorianTP_DB.uiOnboardingDone == true then
            return nil
        end
        if onboardingFrame then
            onboardingFrame:Show()
            if onboardingFrame.RefreshRows then onboardingFrame:RefreshRows() end
            RaiseFrameFront(onboardingFrame)
            return onboardingFrame
        end

        local wf = CreateFrame("Frame", "TalorianOnboardingFrame", UIParent)
        wf:SetSize(610, 504)
        wf:SetPoint("CENTER", 20, -10)
        wf:SetFrameStrata("DIALOG")
        wf:SetToplevel(true)
        wf:EnableMouse(true)
        wf:SetMovable(true)
        wf:RegisterForDrag("LeftButton")
        wf:SetScript("OnDragStart", wf.StartMoving)
        wf:SetScript("OnDragStop", wf.StopMovingOrSizing)
        wf:SetClampedToScreen(true)
        PS.ApplyWindow(wf)
        RegisterSpecialFrame("TalorianOnboardingFrame")

        local wTitle = wf:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        wTitle:SetPoint("TOPLEFT", 16, -14)
        wTitle:SetText("|cfffce08cДобро пожаловать в TalorianTP v" .. TALORIAN_VERSION .. "|r")

        local wSub = wf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        wSub:SetPoint("TOPLEFT", 16, -34)
        wSub:SetPoint("TOPRIGHT", -46, -34)
        wSub:SetJustifyH("LEFT")
        wSub:SetText("|cffc8bea8Выберите, какие блоки показывать в окне (изменения видны сразу). Вернуться можно в Настройках или по команде /ttp blocks.|r")

        local wClose = CreateFrame("Button", nil, wf)
        wClose:SetSize(24, 24)
        wClose:SetPoint("TOPRIGHT", -12, -12)
        PS.StyleClose(wClose, 24)
        wClose:SetScript("OnClick", function()
            TalorianTP:EnsureUIDB()
            TalorianTP_DB.uiOnboardingDone = true
            wf:Hide()
        end)

        -- Quick Presets Row
        local preLbl = wf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        preLbl:SetPoint("TOPLEFT", 16, -66)
        preLbl:SetText("|cffffd200Готовые наборы:|r")

        wf.presetFullBtn = CreateSimpleBtn(wf, 128, -61, 146, 22, "Все включено (Полный)", "green", function()
            TalorianTP:ApplyUIBlockPreset("full")
        end)
        wf.presetMinBtn = CreateSimpleBtn(wf, 280, -61, 152, 22, "Только телепорт", "dark", function()
            TalorianTP:ApplyUIBlockPreset("minimal")
        end)
        wf.presetProgBtn = CreateSimpleBtn(wf, 438, -61, 156, 22, "Телепорт + освоение", "dark", function()
            TalorianTP:ApplyUIBlockPreset("teleport_progress")
        end)

        local listBox = CreateFrame("Frame", nil, wf)
        listBox:SetPoint("TOPLEFT", 14, -90)
        listBox:SetPoint("BOTTOMRIGHT", -14, 48)
        PS.StyleBox(listBox, 0.50, false)

        local VIS = 7
        local ROW_H = 50
        local rows = {}
        local sf
        sf = PS.AttachScroll(listBox, VIS * ROW_H, ROW_H, VIS, function()
            if wf.RenderRows then wf:RenderRows() end
        end)
        sf:SetPoint("TOPLEFT", listBox, "TOPLEFT", 4, -4)
        sf:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -4, 4)
        wf.sf = sf

        for i = 1, VIS do
            local r = CreateFrame("Button", nil, sf)
            r:SetHeight(ROW_H - 2)
            r:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, -(i - 1) * ROW_H)
            r:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -16, -(i - 1) * ROW_H)
            local rowAlpha = ((i % 2) == 1) and 0.44 or 0.30
            PS.StyleBox(r, rowAlpha, false)
            r:SetScript("OnEnter", function(self) PS.StyleBox(self, 0.56, true) end)
            r:SetScript("OnLeave", function(self) PS.StyleBox(self, rowAlpha, false) end)

            local chk = CreateFrame("Frame", nil, r)
            chk:SetSize(18, 18)
            chk:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -8)
            PS.StyleBox(chk, 0.72, false)
            r.chk = chk

            local mk = chk:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            mk:SetPoint("CENTER", 0, 0)
            r.mk = mk

            local ttl = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            ttl:SetPoint("TOPLEFT", chk, "TOPRIGHT", 8, 1)
            ttl:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            ttl:SetJustifyH("LEFT")
            r.ttl = ttl

            local dsc = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            dsc:SetPoint("TOPLEFT", ttl, "BOTTOMLEFT", 0, -2)
            dsc:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -8, 4)
            dsc:SetJustifyH("LEFT")
            dsc:SetJustifyV("TOP")
            dsc:SetTextColor(0.68, 0.74, 0.82)
            r.dsc = dsc

            r:SetScript("OnClick", function(self)
                if not self._def then return end
                local cur = TalorianTP:IsBlockEnabled(self._def.key)
                TalorianTP:SetBlockEnabled(self._def.key, not cur)
            end)
            rows[i] = r
        end
        wf.rows = rows

        function wf:RenderRows()
            TalorianTP:EnsureUIDB()
            local off = sf.offset or 0
            for i = 1, VIS do
                local r = rows[i]
                local def = UI_BLOCK_DEFS[off + i]
                if def then
                    r._def = def
                    local on = TalorianTP:IsBlockEnabled(def.key)
                    r.ttl:SetText(on and ("|cffffd200" .. def.title .. "|r") or ("|cff7c8594" .. def.title .. " (скрыт)|r"))
                    r.dsc:SetText(def.desc or "")
                    if on then
                        r.mk:SetText("|cff40ff40V|r")
                        PS.StyleBox(r.chk, 0.80, true)
                    else
                        r.mk:SetText("")
                        PS.StyleBox(r.chk, 0.55, false)
                    end
                    r:Show()
                else
                    r._def = nil
                    r:Hide()
                end
            end
        end

        function wf:RefreshRows()
            sf:SetTotal(#UI_BLOCK_DEFS, true)
        end

        local footNote = wf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        footNote:SetPoint("BOTTOMLEFT", 16, 17)
        footNote:SetText("Вы всегда можете изменить набор в Настройках.")

        wf.skipBtn = CreateSimpleBtn(wf, nil, nil, 170, 26, "Оставить все и закрыть", "dark", function()
            TalorianTP:EnsureUIDB()
            TalorianTP_DB.uiOnboardingDone = true
            TalorianTP:ApplyUIBlockPreset("full")
            wf:Hide()
        end)
        wf.skipBtn:SetPoint("BOTTOMRIGHT", wf, "BOTTOMRIGHT", -196, 12)

        wf.applyBtn = CreateSimpleBtn(wf, nil, nil, 176, 26, "|cff40ff40Применить и сохранить|r", "green", function()
            TalorianTP:EnsureUIDB()
            TalorianTP_DB.uiOnboardingDone = true
            TalorianTP:ApplyUIBlocks()
            wf:Hide()
        end)
        wf.applyBtn:SetPoint("BOTTOMRIGHT", wf, "BOTTOMRIGHT", -14, 12)

        wf:RefreshRows()
        wf:Show()
        RaiseFrameFront(wf)
        onboardingFrame = wf
        return wf
    end
end

local function InitTalorianUI()
    if mainUI then return mainUI end

    local f = CreateFrame("Frame", "TalorianMainFrame", UIParent)
    f:SetSize(MAIN_W, 578)
    f:SetScript("OnShow", function(self)
        SummonTalorianIfNeeded()
        if self._skipNextShowRefresh then
            self._skipNextShowRefresh = false
            return
        end
        if self.UpdateDiffButtonCounts then
            self:UpdateDiffButtonCounts()
        end
    end)
    f:SetPoint("CENTER", 0, 0)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetScript("OnHide", function()
        local eb = rawget(_G, "TalorianBugLinkEditBox")
        if eb and eb.ClearFocus then eb:ClearFocus() end
    end)

    PS.ApplyWindow(f)
    RegisterSpecialFrame("TalorianMainFrame")

    -- Заголовок
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("|cfffce08cTalorian|r")
    f.title = title

    local subTarget = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subTarget:SetPoint("TOPLEFT", 16, -34)
    f.subTarget = subTarget

    function f:UpdateHeaderTarget()
        local cur = TalorianTP_DB and TalorianTP_DB.targetRaid or "Цитадель Ледяной Короны"
        local m = TalorianTP_DB and TalorianTP_DB.mode or "teleport"
        local modeNames = { teleport = "Телепорт", buffer = "Баффер", bank = "Банк", shop = "Магазин", auction = "Аукцион" }
        local mStr = modeNames[m] or m
        self.subTarget:SetText("|cffc8bea8Режим: |cffffffff" .. mStr .. "|r  |  Цель: |cffffd200" .. cur .. "|r")

        local tag = GetDestMacroTag(cur)
        local hasMacro = GetCharMacroIndex(tag) ~= nil
        if self.createDestMacroBtn and self.createDestMacroBtn.txt then
            if hasMacro then
                self.createDestMacroBtn.txt:SetText("|cff40ff40Удалить макрос (" .. tag .. ")|r")
                PS.PaintBtn(self.createDestMacroBtn, "green")
            else
                self.createDestMacroBtn.txt:SetText("|cfff7dfb5Создать макрос (" .. tag .. ")|r")
                PS.PaintBtn(self.createDestMacroBtn, "dark")
            end
        end
        if self.btnM1 and self.btnM1.txt then
            if hasMacro then
                self.btnM1.txt:SetText("|cff40ff40Удалить макрос выбранного инста (" .. tag .. ")|r")
            else
                self.btnM1.txt:SetText("|cffffffffСоздать макрос выбранного инста (" .. tag .. ")|r")
            end
        end
    end

    -- Кнопка закрытия
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(26, 26)
    closeBtn:SetPoint("TOPRIGHT", -10, -10)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    closeTxt:SetPoint("CENTER", 0, 0)
    closeTxt:SetText("|cffffffffX|r")
    PS.StyleClose(closeBtn)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Статус работы аддона (ВКЛ/ВЫКЛ)
    local statusBtn = CreateFrame("Button", nil, f)
    statusBtn:SetSize(90, 24)
    statusBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    PS.StyleBtn(statusBtn, "green")
    local statusTxt = statusBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusTxt:SetPoint("CENTER", 0, 0)
    statusBtn.txt = statusTxt
    f.statusBtn = statusBtn

    local hdrDiv = f:CreateTexture(nil, "ARTWORK")
    hdrDiv:SetTexture("Interface\\Buttons\\WHITE8X8")
    hdrDiv:SetVertexColor(0.95, 0.78, 0.28, 0.22)
    hdrDiv:SetHeight(1)
    hdrDiv:SetPoint("TOPLEFT", 16, -46)
    hdrDiv:SetPoint("TOPRIGHT", -16, -46)

    function f:UpdateStatusButton()
        local en = TalorianTP_DB and TalorianTP_DB.enabled
        if en then
            PS.PaintBtn(statusBtn, "green")
            statusBtn.txt:SetText("|cfff7dfb5Включено|r")
        else
            PS.PaintBtn(statusBtn, "red")
            statusBtn.txt:SetText("|cfff7dfb5Выключено|r")
        end
    end

    statusBtn:SetScript("OnClick", function()
        TalorianTP_DB.enabled = not TalorianTP_DB.enabled
        if not TalorianTP_DB.enabled then
            targetPollTimer = 0
        else
            SummonTalorianIfNeeded()
            targetPollTimer = 4.0
            targetPollElapsed = 0
        end
        UpdateAllSecureButtonsMacro()
        EnsureSecureExecButton()
        f:UpdateStatusButton()
        if f.UpdateStatusNote then f:UpdateStatusNote() end
        if f.RefreshButtons then f:RefreshButtons() end
        local st = TalorianTP_DB.enabled and "|cff00ff88включен|r" or "|cffff4444выключен|r"
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Аддон " .. st)
    end)

    -- Кнопка бинда
    local bindBtn = CreateFrame("Button", nil, f)
    bindBtn:SetSize(110, 24)
    bindBtn:SetPoint("RIGHT", statusBtn, "LEFT", -8, 0)
    PS.StyleBtn(bindBtn, "dark")
    local bindTxt = bindBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bindTxt:SetPoint("CENTER", 0, 0)
    bindBtn.txt = bindTxt
    f.bindBtn = bindBtn

    function f:UpdateBindText()
        local k = TalorianTP_DB and TalorianTP_DB.interactKey or "ъ"
        self.bindBtn.txt:SetText("|cffc8bea8Бинд: [|cffffffff" .. k .. "|r]|r")
    end

    bindBtn:SetScript("OnClick", function()
        TalorianTP_StartKeyCapture()
    end)

    -- Кнопка сброса КД
    local resetBtn = CreateFrame("Button", nil, f)
    resetBtn:SetSize(180, 24)
    resetBtn:SetPoint("RIGHT", bindBtn, "LEFT", -12, 0)
    PS.StyleBtn(resetBtn, "dark")

    local resetTxt = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    resetTxt:SetPoint("CENTER", 0, 0)
    resetTxt:SetText("|cfff7dfb5Сброс КД (100 |TInterface\\Icons\\INV_Misc_Coin_02:12|t/инст)|r")
    resetBtn.txt = resetTxt
    f.resetBtn = resetBtn

    function f:UpdateResetCDHighlight()
        local hasLocks = (GetNumSavedInstances() > 0)
        PS.PaintBtn(resetBtn, hasLocks and "green" or "dark")
    end

    resetBtn:SetScript("OnClick", function()
        TalorianTP_ResetAllCD()
    end)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Сброс КД подземелий и рейдов", 1, 0.82, 0)
        GameTooltip:AddLine("Отправляет команду .in un all в чат.", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Стоимость: 100 золотых за каждый инст.", 1, 1, 1)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Панель режимов (Телепорт, Баффер, Банк, Магазин, Аукцион)
    local modeBar = CreateFrame("Frame", nil, f)
    modeBar:SetPoint("TOPLEFT", 16, -50)
    modeBar:SetPoint("TOPRIGHT", -16, -50)
    modeBar:SetHeight(26)
    f.modeBar = modeBar

    local modeLabel = modeBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    modeLabel:SetPoint("LEFT", 0, 0)
    modeLabel:SetText("|cffc8bea8Режим:|r")

    local modes = {
        { id = "teleport", label = "Телепорт", icon = "Interface\\Icons\\Spell_Arcane_TeleportMoonglade" },
        { id = "buffer",   label = "Баффер",   icon = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings" },
        { id = "bank",     label = "Банк",     icon = "Interface\\Icons\\INV_Box_02" },
        { id = "shop",     label = "Магазин",  icon = "Interface\\GossipFrame\\VendorGossipIcon" },
        { id = "auction",  label = "Аукцион",  icon = "Interface\\Icons\\INV_Misc_Coin_02" },
    }
    f.modeBtns = {}
    local modeX = 64
    for _, m in ipairs(modes) do
        local mb = CreateFrame("Button", nil, modeBar, "SecureActionButtonTemplate")
        mb:SetSize(116, 24)
        mb:SetPoint("LEFT", modeX, 0)
        PS.StyleBtn(mb, "dark")
        mb.id = m.id

        mb:SetAttribute("type", "macro")
        mb:SetAttribute("macrotext", BuildTalorianSecureMacro(true))
        mb:RegisterForClicks("LeftButtonUp")

        local ic = mb:CreateTexture(nil, "ARTWORK")
        ic:SetSize(16, 16)
        ic:SetPoint("LEFT", 6, 0)
        ic:SetTexture(m.icon)
        mb.icon = ic

        local txt = mb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", ic, "RIGHT", 6, 0)
        txt:SetText(m.label)
        mb.txt = txt

        mb:SetScript("PreClick", function(self)
            UpdateSecureBtnMacro(self)
        end)
        mb:SetScript("PostClick", function(self, mouseBtn, down)
            if down then
                SummonTalorianIfNeeded()
                CheckAndMarkTalorian()
            else
                TalorianTP_SetMode(m.id)
                CheckAndMarkTalorian()
            end
        end)
        mb:SetScript("OnEnter", function()
            SummonTalorianIfNeeded()
        end)
        table.insert(f.modeBtns, mb)
        modeX = modeX + 122
    end

    function f:UpdateModeHighlight()
        local cur = TalorianTP_DB and TalorianTP_DB.mode or "teleport"
        for _, mb in ipairs(self.modeBtns) do
            if mb.id == cur then
                PS.PaintBtn(mb, "gold")
                mb.txt:SetTextColor(1, 0.88, 0.45, 1)
            else
                PS.PaintBtn(mb, "dark")
                mb.txt:SetTextColor(0.82, 0.78, 0.68, 1)
            end
        end
        self:UpdateHeaderTarget()
    end

    -- Панель сложностей и топ-рейдов
    local diffBar = CreateFrame("Frame", nil, f)
    diffBar:SetPoint("TOPLEFT", 16, -80)
    diffBar:SetPoint("TOPRIGHT", -16, -80)
    diffBar:SetHeight(24)
    f.diffBar = diffBar

    local diffLabel = diffBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    diffLabel:SetPoint("LEFT", 0, 0)
    diffLabel:SetText("|cffffd200Сложность:|r")
    f.diffLabel = diffLabel

    local function ShowDiffBtnTooltip(btn)
        local td = btn and btn.tipData
        if not td then return end
        GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(td.title or "Сложность", 1, 0.82, 0)
        if td.subtitle and td.subtitle ~= "" then
            GameTooltip:AddLine(td.subtitle, 0.85, 0.90, 0.95, true)
        end
        if td.selName then
            GameTooltip:AddLine(" ")
            if td.selText then
                GameTooltip:AddDoubleLine("Выбранная цель (" .. td.selName .. "):", td.selText, 0.7, 0.85, 1, 1, 1, 1)
            elseif td.selMissing then
                GameTooltip:AddLine("Цель " .. td.selName .. ": данной сложности в этом инсте нет.", 0.85, 0.45, 0.45)
            end
        end
        if td.topList and #td.topList > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(td.topHeader or "Где больше всего осталось добыть:", 0.22, 0.74, 0.97)
            for idx = 1, math.min(5, #td.topList) do
                local z = td.topList[idx]
                GameTooltip:AddDoubleLine(
                    string.format("  %d. %s", idx, z.name),
                    string.format("|cff40ff40%d предм.|r  |cff38bdf8(+%s статов)|r", z.rem, FormatStatValue(z.stats)),
                    0.92, 0.92, 0.92, 1, 1, 1
                )
            end
        end
        GameTooltip:Show()
    end

    -- 4 кнопки рейда (10 об, 25 об, 10 гер, 25 гер) с динамическим числом вещей
    local raidDiffs = {
        { id = 1, label = "10 об",  full = "10 обычная" },
        { id = 2, label = "25 об",  full = "25 обычная" },
        { id = 3, label = "10 гер", full = "10 героическая" },
        { id = 4, label = "25 гер", full = "25 героическая" },
    }
    f.raidDiffBtns = {}
    local rDiffX = 74
    for _, d in ipairs(raidDiffs) do
        local btn = CreateFrame("Button", nil, diffBar)
        btn:SetSize(92, 22)
        btn:SetPoint("LEFT", rDiffX, 0)
        PS.StyleBtn(btn, "dark")
        btn.id = d.id
        btn.baseLabel = d.label
        btn.fullLabel = d.full
        btn.txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.txt:SetPoint("CENTER", 0, 0)
        btn.txt:SetText(d.label)
        btn:SetScript("OnClick", function()
            TalorianTP_SetRaidDiff(d.id)
        end)
        btn:SetScript("OnEnter", function(self) ShowDiffBtnTooltip(self) end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(f.raidDiffBtns, btn)
        rDiffX = rDiffX + 95
    end

    -- Информационная кнопка единой сложности для Classic / TBC рейдов
    local raidSingleBtn = CreateFrame("Button", nil, diffBar)
    raidSingleBtn:SetSize(377, 22)
    raidSingleBtn:SetPoint("LEFT", 74, 0)
    PS.StyleBtn(raidSingleBtn, "green")
    raidSingleBtn.txt = raidSingleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    raidSingleBtn.txt:SetPoint("CENTER", 0, 0)
    raidSingleBtn.txt:SetText("|cff9fe88aЕдиная сложность (для всех вещей)|r")
    raidSingleBtn:SetScript("OnEnter", function(self) ShowDiffBtnTooltip(self) end)
    raidSingleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    raidSingleBtn:Hide()
    f.raidSingleDiffBtn = raidSingleBtn

    -- 2 кнопки подземелья (Обычный, Героический) с динамическим числом вещей
    local dungeonDiffs = {
        { id = 1, label = "Обычный",     full = "Обычный (5 игроков)" },
        { id = 2, label = "Героический", full = "Героический (5 игроков)" },
    }
    f.dungeonDiffBtns = {}
    local dDiffX = 74
    for _, d in ipairs(dungeonDiffs) do
        local btn = CreateFrame("Button", nil, diffBar)
        btn:SetSize(184, 22)
        btn:SetPoint("LEFT", dDiffX, 0)
        PS.StyleBtn(btn, "dark")
        btn.id = d.id
        btn.baseLabel = d.label
        btn.fullLabel = d.full
        btn.txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.txt:SetPoint("CENTER", 0, 0)
        btn.txt:SetText(d.label)
        btn:SetScript("OnClick", function()
            TalorianTP_SetDungeonDiff(d.id)
        end)
        btn:SetScript("OnEnter", function(self) ShowDiffBtnTooltip(self) end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(f.dungeonDiffBtns, btn)
        dDiffX = dDiffX + 190
    end

    -- Информационная кнопка единой сложности для Classic подземелий
    local dungSingleBtn = CreateFrame("Button", nil, diffBar)
    dungSingleBtn:SetSize(374, 22)
    dungSingleBtn:SetPoint("LEFT", 74, 0)
    PS.StyleBtn(dungSingleBtn, "green")
    dungSingleBtn.txt = dungSingleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dungSingleBtn.txt:SetPoint("CENTER", 0, 0)
    dungSingleBtn.txt:SetText("|cff9fe88aЕдиная сложность (обычный режим)|r")
    dungSingleBtn:SetScript("OnEnter", function(self) ShowDiffBtnTooltip(self) end)
    dungSingleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    dungSingleBtn:Hide()
    f.dungeonSingleDiffBtn = dungSingleBtn

    -- 4 быстрые кнопки топ-рейдов (ЦЛК, ИК, РС, Накс) - SECURE ACTION!
    local quickRaids = {
        { name = "Цитадель Ледяной Короны", label = "ЦЛК" },
        { name = "Испытание крестоносца",   label = "ИК" },
        { name = "Рубиновое святилище",     label = "РС" },
        { name = "Наксрамас",               label = "Накс" },
    }
    f.quickRaidBtns = {}
    local quickX = rDiffX + 12
    for qIdx, qr in ipairs(quickRaids) do
        local qBtn = CreateFrame("Button", nil, diffBar, "SecureActionButtonTemplate")
        qBtn:SetSize(60, 22)
        qBtn:SetPoint("LEFT", quickX, 0)
        PS.StyleBtn(qBtn, "dark")
        qBtn.destName = qr.name

        qBtn:SetAttribute("type", "macro")
        qBtn:SetAttribute("macrotext", BuildTalorianSecureMacro(true))
        qBtn:RegisterForClicks("LeftButtonUp")

        qBtn.txt = qBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qBtn.txt:SetPoint("CENTER", 0, 0)
        qBtn.txt:SetText("|cffffd200" .. qr.label .. "|r")

        local qProgBg = CreateFrame("Frame", nil, qBtn)
        qProgBg:SetPoint("TOPLEFT", qBtn, "BOTTOMLEFT", 2, -1)
        qProgBg:SetPoint("TOPRIGHT", qBtn, "BOTTOMRIGHT", -2, -1)
        qProgBg:SetHeight(3)
        qProgBg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        qProgBg:SetBackdropColor(0.05, 0.05, 0.08, 0.90)
        qProgBg:SetBackdropBorderColor(0.32, 0.27, 0.16, 0.75)
        local qProgFill = qProgBg:CreateTexture(nil, "OVERLAY")
        qProgFill:SetPoint("TOPLEFT", qProgBg, "TOPLEFT", 1, -1)
        qProgFill:SetPoint("BOTTOMLEFT", qProgBg, "BOTTOMLEFT", 1, 1)
        qProgFill:SetTexture("Interface\\Buttons\\WHITE8X8")
        qProgFill:SetVertexColor(0.22, 0.88, 0.42, 0.95)
        qProgFill:Hide()
        qProgBg:Hide()
        qBtn.progBg = qProgBg
        qBtn.progFill = qProgFill
        qBtn._progMaxW = 54

        qBtn:SetScript("PreClick", function(self)
            UpdateSecureBtnMacro(self)
        end)
        qBtn:SetScript("PostClick", function(self, mouseBtn, down)
            if down then
                SummonTalorianIfNeeded()
                CheckAndMarkTalorian()
            elseif self.destName then
                TalorianTP_SetTarget(self.destName)
                CheckAndMarkTalorian()
            end
        end)
        qBtn:SetScript("OnEnter", function(self)
            SummonTalorianIfNeeded()
        end)
        table.insert(f.quickRaidBtns, qBtn)
        quickX = quickX + 64
    end

    -- Кнопка создания 4 топ-рейд макросов (+4M)
    local fourMacroBtn = CreateFrame("Button", nil, diffBar)
    fourMacroBtn:SetSize(52, 22)
    fourMacroBtn:SetPoint("LEFT", quickX + 4, 0)
    PS.StyleBtn(fourMacroBtn, "dark")
    local fmtTxt = fourMacroBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fmtTxt:SetPoint("CENTER", 0, 0)
    fmtTxt:SetText("|cffffd200+4M|r")
    fourMacroBtn.txt = fmtTxt

    fourMacroBtn:SetScript("OnClick", function() TalorianTP_CreateMacro_TopRaids() end)
    fourMacroBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Создать 4 топ-рейд макроса персонажа", 1, 0.82, 0)
        GameTooltip:AddLine("Создает макросы: T_ЦЛК, T_ИК, T_РС, T_Накс во вкладке персонажа (/macro).", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    fourMacroBtn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    f.fourMacroBtn = fourMacroBtn

    function f:UpdateDiffHighlight()
        local rDiff = TalorianTP_DB and TalorianTP_DB.raidDiff or 1
        local dDiff = TalorianTP_DB and TalorianTP_DB.dungeonDiff or 1

        for _, btn in ipairs(self.raidDiffBtns) do
            if btn.id == rDiff then
                PS.PaintBtn(btn, "gold")
                btn.txt:SetTextColor(1, 0.88, 0.35, 1)
            else
                PS.PaintBtn(btn, "dark")
                btn.txt:SetTextColor(0.82, 0.78, 0.68, 1)
            end
        end

        for _, btn in ipairs(self.dungeonDiffBtns) do
            if btn.id == dDiff then
                PS.PaintBtn(btn, "gold")
                btn.txt:SetTextColor(1, 0.88, 0.35, 1)
            else
                PS.PaintBtn(btn, "dark")
                btn.txt:SetTextColor(0.82, 0.78, 0.68, 1)
            end
        end
    end

    function f:UpdateDiffButtonCounts()
        local activeTab = TalorianTP_DB and TalorianTP_DB.activeTab or 1
        if activeTab == 3 or activeTab == 4 or activeTab == 5 then return end

        local ap = rawget(_G, "AttuneParser")
        local selDest = FindDestByName(TalorianTP_DB and TalorianTP_DB.targetRaid)

        if activeTab == 1 then
            local raidEra = TalorianTP_DB and TalorianTP_DB.raidEra or "All"
            local isEraSingle = (raidEra == "TBC" or raidEra == "Classic")
            local curDiff = TalorianTP_DB and TalorianTP_DB.raidDiff or 1
            local list = GetCurrentRaidList()

            local zaMap = {}
            if ap and ap.GetZoneAnalysis then
                for _, r in ipairs(list) do
                    if r.attune then
                        -- Passing diffId = curDiff guarantees a 100% cache hit against RefreshButtons() while still holding full byDiff[1..maxDiffs]
                        zaMap[r.attune] = ap:GetZoneAnalysis(r.attune, { diffId = curDiff, isRaid = true, exp = r.exp, scope = "hero" })
                    end
                end
            end

            if isEraSingle then
                for _, rb in ipairs(self.raidDiffBtns) do rb:Hide() end
                if self.raidSingleDiffBtn then self.raidSingleDiffBtn:Show() end

                if ap and ap.GetZoneAnalysis and self.raidSingleDiffBtn then
                    local eraRem, eraStats = 0, 0
                    local selRem = nil
                    local topList = {}
                    for _, r in ipairs(list) do
                        local za = r.attune and zaMap[r.attune]
                        if za then
                            local rem = (za.newCount or 0) + (za.forgeCount or 0)
                            local st = za.totalRemainStats or 0
                            eraRem = eraRem + rem
                            eraStats = eraStats + st
                            if selDest and selDest.name == r.name then selRem = rem end
                            if rem > 0 then
                                table.insert(topList, { name = r.name, rem = rem, stats = st })
                            end
                        end
                    end
                    table.sort(topList, function(a, b)
                        if a.stats ~= b.stats then return a.stats > b.stats end
                        return a.rem > b.rem
                    end)
                    local eraTitle = (raidEra == "Classic") and "Классика" or "Burning Crusade"
                    if selRem ~= nil and selDest then
                        self.raidSingleDiffBtn.txt:SetText(string.format("|cff9fe88aЕдиная (%s): %d ост.  |  Всего: %d ост.|r", selDest.short or selDest.name, selRem, eraRem))
                    else
                        self.raidSingleDiffBtn.txt:SetText(string.format("|cff9fe88aЕдиная сложность (%s): осталось %d предм.|r", eraTitle, eraRem))
                    end
                    self.raidSingleDiffBtn.tipData = {
                        title = "Единая сложность - Рейды (" .. eraTitle .. ")",
                        subtitle = string.format("У рейдов %s только одна сложность. Всего осталось: %d предм. (+%s статов).", eraTitle, eraRem, FormatStatValue(eraStats)),
                        selName = (selRem ~= nil and selDest) and selDest.name or nil,
                        selText = (selRem ~= nil) and string.format("%d предм. осталось", selRem) or nil,
                        topHeader = "Топ рейдов (" .. eraTitle .. ") по добыче:",
                        topList = topList,
                    }
                end
            else
                if self.raidSingleDiffBtn then self.raidSingleDiffBtn:Hide() end
                for _, rb in ipairs(self.raidDiffBtns) do rb:Show() end

                if ap and ap.GetZoneAnalysis then
                    local selZa = (selDest and selDest.isRaid and selDest.attune)
                        and (zaMap[selDest.attune] or ap:GetZoneAnalysis(selDest.attune, { diffId = curDiff, isRaid = true, exp = selDest.exp, scope = "hero" }))
                        or nil
                    for _, btn in ipairs(self.raidDiffBtns) do
                        local dId = btn.id
                        local topList = {}
                        local totRem = 0
                        for _, r in ipairs(list) do
                            local za = r.attune and zaMap[r.attune]
                            if za then
                                local rem, st = 0, 0
                                if za.isSingleDiff then
                                    local singleDiffSlot = (za.zoneId == 3457 or za.zoneId == 3805) and 1 or 2
                                    if dId == singleDiffSlot then
                                        rem = (za.newCount or 0) + (za.forgeCount or 0) + (za.randomSuffixNew or 0) + (za.randomSuffixForge or 0)
                                        st = za.totalRemainStats or 0
                                    end
                                elseif dId <= (za.maxDiffs or 1) then
                                    local bd = za.byDiff and za.byDiff[dId]
                                    if bd then
                                        rem = (bd.newCount or 0) + (bd.forgeCount or 0)
                                        st = bd.remainStats or 0
                                    end
                                end
                                if rem > 0 then
                                    totRem = totRem + rem
                                    table.insert(topList, { name = r.name, rem = rem, stats = st })
                                end
                            end
                        end
                        table.sort(topList, function(a, b)
                            if a.stats ~= b.stats then return a.stats > b.stats end
                            return a.rem > b.rem
                        end)

                        local selRem, selStats, selMissing = nil, 0, false
                        if selZa then
                            if selZa.isSingleDiff then
                                local singleDiffSlot = (selZa.zoneId == 3457 or selZa.zoneId == 3805) and 1 or 2
                                if dId == singleDiffSlot then
                                    selRem = (selZa.newCount or 0) + (selZa.forgeCount or 0) + (selZa.randomSuffixNew or 0) + (selZa.randomSuffixForge or 0)
                                    selStats = selZa.totalRemainStats or 0
                                    btn.txt:SetText(string.format("%s (%d)", btn.baseLabel, selRem))
                                else
                                    selMissing = true
                                    btn.txt:SetText(btn.baseLabel .. " (-)")
                                end
                            elseif dId <= (selZa.maxDiffs or 1) then
                                local bd = selZa.byDiff and selZa.byDiff[dId]
                                selRem = bd and ((bd.newCount or 0) + (bd.forgeCount or 0)) or 0
                                selStats = bd and (bd.remainStats or 0) or 0
                                btn.txt:SetText(string.format("%s (%d)", btn.baseLabel, selRem))
                            else
                                selMissing = true
                                btn.txt:SetText(btn.baseLabel .. " (-)")
                            end
                        else
                            btn.txt:SetText(string.format("%s (%d)", btn.baseLabel, totRem))
                        end

                        btn.tipData = {
                            title = "Рейдовая сложность: " .. btn.fullLabel,
                            subtitle = string.format("Суммарно доступно в выбранном фильтре: %d предм.", totRem),
                            selName = (selDest and selDest.isRaid) and selDest.name or nil,
                            selText = (not selMissing and selRem ~= nil) and string.format("%d предм. (+%s статов)", selRem, FormatStatValue(selStats)) or nil,
                            selMissing = selMissing,
                            topHeader = "Где больше всего добычи в " .. btn.fullLabel .. ":",
                            topList = topList,
                        }
                    end
                end
            end
        elseif activeTab == 2 then
            local dungeonEra = TalorianTP_DB and TalorianTP_DB.dungeonEra or "WotLK"
            local curDiff = TalorianTP_DB and TalorianTP_DB.dungeonDiff or 1
            local list = GetCurrentDungeonList()
            local zaMap = {}
            if ap and ap.GetZoneAnalysis then
                for _, d in ipairs(list) do
                    if d.attune then
                        zaMap[d.attune] = ap:GetZoneAnalysis(d.attune, { diffId = curDiff, isRaid = false, exp = d.exp, scope = "hero" })
                    end
                end
            end

            if dungeonEra == "Classic" then
                for _, db in ipairs(self.dungeonDiffBtns) do db:Hide() end
                if self.dungeonSingleDiffBtn then self.dungeonSingleDiffBtn:Show() end
                if ap and ap.GetZoneAnalysis and self.dungeonSingleDiffBtn then
                    local eraRem, eraStats, selRem = 0, 0, nil
                    local topList = {}
                    for _, d in ipairs(list) do
                        local za = d.attune and zaMap[d.attune]
                        if za then
                            local rem = (za.newCount or 0) + (za.forgeCount or 0)
                            local st = za.totalRemainStats or 0
                            eraRem = eraRem + rem
                            eraStats = eraStats + st
                            if selDest and selDest.name == d.name then selRem = rem end
                            if rem > 0 then table.insert(topList, { name = d.name, rem = rem, stats = st }) end
                        end
                    end
                    table.sort(topList, function(a, b)
                        if a.stats ~= b.stats then return a.stats > b.stats end
                        return a.rem > b.rem
                    end)
                    if selRem ~= nil and selDest then
                        self.dungeonSingleDiffBtn.txt:SetText(string.format("|cff9fe88aЕдиная (%s): %d ост.  |  Всего: %d ост.|r", selDest.short or selDest.name, selRem, eraRem))
                    else
                        self.dungeonSingleDiffBtn.txt:SetText(string.format("|cff9fe88aЕдиная сложность (Классика): осталось %d предм.|r", eraRem))
                    end
                    self.dungeonSingleDiffBtn.tipData = {
                        title = "Классические подземелья (единая сложность)",
                        subtitle = string.format("Всего осталось: %d предм. (+%s статов).", eraRem, FormatStatValue(eraStats)),
                        selName = (selRem ~= nil and selDest) and selDest.name or nil,
                        selText = (selRem ~= nil) and string.format("%d предм. осталось", selRem) or nil,
                        topHeader = "Топ классических подземелий:",
                        topList = topList,
                    }
                end
            else
                if self.dungeonSingleDiffBtn then self.dungeonSingleDiffBtn:Hide() end
                for _, db in ipairs(self.dungeonDiffBtns) do db:Show() end
                if ap and ap.GetZoneAnalysis then
                    local selInEra = (selDest and not selDest.isRaid and selDest.attune and selDest.exp == dungeonEra)
                    local selZa = selInEra and (zaMap[selDest.attune] or ap:GetZoneAnalysis(selDest.attune, { diffId = curDiff, isRaid = false, exp = selDest.exp, scope = "hero" })) or nil
                    for _, btn in ipairs(self.dungeonDiffBtns) do
                        local dId = btn.id
                        local topList = {}
                        local totRem = 0
                        for _, d in ipairs(list) do
                            local za = d.attune and zaMap[d.attune]
                            local bd = za and za.byDiff and za.byDiff[dId]
                            if bd then
                                local rem = (bd.newCount or 0) + (bd.forgeCount or 0)
                                local st = bd.remainStats or 0
                                if rem > 0 then
                                    totRem = totRem + rem
                                    table.insert(topList, { name = d.name, rem = rem, stats = st })
                                end
                            end
                        end
                        table.sort(topList, function(a, b)
                            if a.stats ~= b.stats then return a.stats > b.stats end
                            return a.rem > b.rem
                        end)
                        local selRem, selStats = nil, 0
                        if selZa and selZa.byDiff and selZa.byDiff[dId] then
                            selRem = (selZa.byDiff[dId].newCount or 0) + (selZa.byDiff[dId].forgeCount or 0)
                            selStats = selZa.byDiff[dId].remainStats or 0
                            btn.txt:SetText(string.format("%s (%d ост.)", btn.baseLabel, selRem))
                        else
                            btn.txt:SetText(string.format("%s (%d ост.)", btn.baseLabel, totRem))
                        end
                        btn.tipData = {
                            title = "Подземелья (" .. dungeonEra .. "): " .. btn.fullLabel,
                            subtitle = string.format("Всего в этой сложности (%s): %d предм.", dungeonEra, totRem),
                            selName = selInEra and selDest.name or nil,
                            selText = (selRem ~= nil) and string.format("%d предм. (+%s статов)", selRem, FormatStatValue(selStats)) or nil,
                            topHeader = "Топ подземелий (" .. btn.baseLabel .. "):",
                            topList = topList,
                        }
                    end
                end
            end
        end
    end

    -- Вкладки категорий (Рейды, Подземелья, Столицы, Настройки, Спутники и Наборы)
    local capCount = #GetCurrentCapitalList()
    local tabDefs = {
        { id = 1, label = "Рейды (" .. #RAID_DESTS .. ")" },
        { id = 2, label = "Подземелья (52)" },
        { id = 3, label = "Столицы и VIP (" .. capCount .. ")" },
        { id = 4, label = "Настройки" },
        { id = 5, label = "Спутники и Наборы" },
    }
    f.tabs = {}
    local tabW = (MAIN_W - 32 - 16) / 5
    for i, td in ipairs(tabDefs) do
        local tab = CreateFrame("Button", nil, f)
        tab:SetSize(tabW, 26)
        tab:SetPoint("TOPLEFT", 16 + (i - 1) * (tabW + 4), -108)
        PS.StyleBtn(tab, "dark")
        tab.id = td.id

        local txt = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("CENTER", 0, 0)
        txt:SetText(td.label)
        tab.txt = txt

        tab:SetScript("OnClick", function()
            TalorianTP_DB.activeTab = td.id
            f:SwitchTab(td.id)
        end)
        table.insert(f.tabs, tab)
    end

    -- Под-панель выбора эры рейдов (Все, WotLK, Burning Crusade, Классика)
    local raidEraBar = CreateFrame("Frame", nil, f)
    raidEraBar:SetPoint("TOPLEFT", 16, -138)
    raidEraBar:SetPoint("TOPRIGHT", -16, -138)
    raidEraBar:SetHeight(24)
    f.raidEraBar = raidEraBar

    local cntW, cntT, cntC = 0, 0, 0
    for _, r in ipairs(RAID_DESTS) do
        if r.exp == "WotLK" then cntW = cntW + 1
        elseif r.exp == "TBC" then cntT = cntT + 1
        elseif r.exp == "Classic" then cntC = cntC + 1 end
    end
    local raidEraDefs = {
        { id = "All",     label = "Все рейды (" .. #RAID_DESTS .. ")" },
        { id = "WotLK",   label = "WotLK (" .. cntW .. ")" },
        { id = "TBC",     label = "Burning Crusade (" .. cntT .. ")" },
        { id = "Classic", label = "Классика (" .. cntC .. ")" },
    }
    f.raidEraBtns = {}
    local rEraW = (MAIN_W - 32 - 12) / 4
    for i, ed in ipairs(raidEraDefs) do
        local eBtn = CreateFrame("Button", nil, raidEraBar)
        eBtn:SetSize(rEraW, 22)
        eBtn:SetPoint("LEFT", (i - 1) * (rEraW + 4), 0)
        PS.StyleBtn(eBtn, "dark")
        eBtn.id = ed.id

        local txt = eBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("CENTER", 0, 0)
        txt:SetText(ed.label)
        eBtn.txt = txt

        eBtn:SetScript("OnClick", function()
            TalorianTP_DB.raidEra = ed.id
            f:UpdateRaidEraHighlight()
            f:UpdateDiffHighlight()
            if f.RefreshButtons then f:RefreshButtons() end
        end)
        table.insert(f.raidEraBtns, eBtn)
    end

    function f:UpdateRaidEraHighlight()
        local cur = TalorianTP_DB and TalorianTP_DB.raidEra or "All"
        for _, eb in ipairs(self.raidEraBtns) do
            if eb.id == cur then
                PS.PaintBtn(eb, "gold")
                eb.txt:SetTextColor(1, 0.88, 0.45, 1)
            else
                PS.PaintBtn(eb, "dark")
                eb.txt:SetTextColor(0.82, 0.78, 0.68, 1)
            end
        end
    end

    -- Под-панель выбора эры подземелий (WotLK, Burning Crusade, Классика)
    local dungeonEraBar = CreateFrame("Frame", nil, f)
    dungeonEraBar:SetPoint("TOPLEFT", 16, -138)
    dungeonEraBar:SetPoint("TOPRIGHT", -16, -138)
    dungeonEraBar:SetHeight(24)
    f.dungeonEraBar = dungeonEraBar

    local eraDefs = {
        { id = "WotLK",   label = "WotLK (" .. #DUNGEONS_WOTLK .. ")" },
        { id = "TBC",     label = "Burning Crusade (" .. #DUNGEONS_TBC .. ")" },
        { id = "Classic", label = "Классика (" .. #DUNGEONS_VANILLA .. ")" },
    }
    f.eraBtns = {}
    local eraW = (MAIN_W - 32 - 8) / 3
    for i, ed in ipairs(eraDefs) do
        local eBtn = CreateFrame("Button", nil, dungeonEraBar)
        eBtn:SetSize(eraW, 22)
        eBtn:SetPoint("LEFT", (i - 1) * (eraW + 4), 0)
        PS.StyleBtn(eBtn, "dark")
        eBtn.id = ed.id

        local txt = eBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("CENTER", 0, 0)
        txt:SetText(ed.label)
        eBtn.txt = txt

        eBtn:SetScript("OnClick", function()
            TalorianTP_DB.dungeonEra = ed.id
            f:UpdateDungeonEraHighlight()
            f:UpdateDiffHighlight()
            if f.RefreshButtons then f:RefreshButtons() end
        end)
        table.insert(f.eraBtns, eBtn)
    end

    function f:UpdateDungeonEraHighlight()
        local cur = TalorianTP_DB and TalorianTP_DB.dungeonEra or "WotLK"
        for _, eb in ipairs(self.eraBtns) do
            if eb.id == cur then
                PS.PaintBtn(eb, "gold")
                eb.txt:SetTextColor(1, 0.88, 0.45, 1)
            else
                PS.PaintBtn(eb, "dark")
                eb.txt:SetTextColor(0.82, 0.78, 0.68, 1)
            end
        end
    end

    -- Область карточек (3 колонки x 8 строк = 24 слота)
    local contentFrame = CreateFrame("Frame", nil, f)
    contentFrame:SetPoint("TOPLEFT", 16, -168)
    contentFrame:SetPoint("BOTTOMRIGHT", -16, 46)
    f.contentFrame = contentFrame

    local COLS = 3
    local ROWS = 8
    local btnW = (MAIN_W - 32 - 12) / COLS
    local btnH = 38

    f.destButtons = {}
    for i = 1, (COLS * ROWS) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)

        local btn = CreateFrame("Button", "TalorianDestBtn_" .. i, contentFrame, "SecureActionButtonTemplate")
        btn:SetSize(btnW, btnH)
        btn:SetPoint("TOPLEFT", col * (btnW + 6), -row * (btnH + 7))
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

        btn:SetAttribute("type", "macro")
        btn:SetAttribute("shift-type1", "")
        btn:SetAttribute("macrotext", BuildTalorianSecureMacro(true))
        btn:RegisterForClicks("LeftButtonUp")

        local ic = btn:CreateTexture(nil, "ARTWORK")
        ic:SetSize(30, 30)
        ic:SetPoint("LEFT", 5, 0)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = ic

        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("TOPLEFT", ic, "TOPRIGHT", 6, -1)
        t:SetPoint("RIGHT", btn, "RIGHT", -96, 0)
        t:SetJustifyH("LEFT")
        if t.SetWordWrap then t:SetWordWrap(false) end
        btn.title = t

        local sub = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetPoint("BOTTOMLEFT", ic, "BOTTOMRIGHT", 6, 1)
        sub:SetPoint("RIGHT", btn, "RIGHT", -96, 0)
        sub:SetJustifyH("LEFT")
        if sub.SetWordWrap then sub:SetWordWrap(false) end
        btn.subtitle = sub

        local statBadge = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statBadge:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -32, -4)
        statBadge:SetJustifyH("RIGHT")
        btn.statBadge = statBadge

        local badge = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        badge:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -32, 4)
        badge:SetJustifyH("RIGHT")
        btn.badge = badge

        -- Полоска прогресса освоения вещей непосредственно под кнопкой
        local progBg = CreateFrame("Frame", nil, btn)
        progBg:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 2, -1)
        progBg:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", -2, -1)
        progBg:SetHeight(5)
        progBg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        progBg:SetBackdropColor(0.05, 0.05, 0.08, 0.90)
        progBg:SetBackdropBorderColor(0.32, 0.27, 0.16, 0.80)

        local progAbsFill = progBg:CreateTexture(nil, "ARTWORK")
        progAbsFill:SetPoint("TOPLEFT", progBg, "TOPLEFT", 1, -1)
        progAbsFill:SetPoint("BOTTOMLEFT", progBg, "BOTTOMLEFT", 1, 1)
        progAbsFill:SetTexture("Interface\\Buttons\\WHITE8X8")
        progAbsFill:SetVertexColor(0.85, 0.58, 0.14, 0.55)
        progAbsFill:Hide()

        local progFill = progBg:CreateTexture(nil, "OVERLAY")
        progFill:SetPoint("TOPLEFT", progBg, "TOPLEFT", 1, -1)
        progFill:SetPoint("BOTTOMLEFT", progBg, "BOTTOMLEFT", 1, 1)
        progFill:SetTexture("Interface\\Buttons\\WHITE8X8")
        progFill:SetVertexColor(0.22, 0.88, 0.42, 0.95)
        progFill:Hide()

        progBg:Hide()
        btn.progBg = progBg
        btn.progAbsFill = progAbsFill
        btn.progFill = progFill
        btn._progMaxW = math.max(20, math.floor(btnW - 6))

        -- Кнопка создания/удаления макроса прямо на карточке (+M)
        local mBtn = CreateFrame("Button", nil, btn)
        mBtn:SetSize(24, 18)
        mBtn:SetPoint("RIGHT", btn, "RIGHT", -5, 0)
        PS.StyleBtn(mBtn, "dark")
        local mTxt = mBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        mTxt:SetPoint("CENTER", 0, 0)
        mTxt:SetText("|cffffd200+M|r")
        mBtn.txt = mTxt

        mBtn:SetScript("OnClick", function(self)
            if btn.destData then
                local mTag = GetDestMacroTag(btn.destData.name)
                if GetCharMacroIndex(mTag) then
                    if DeleteCharMacro(mTag) then
                        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Макрос |cffffffff" .. mTag .. "|r удален.")
                    end
                else
                    TalorianTP_ToggleMacroForDest(btn.destData.name)
                end
                if mainUI and mainUI.RefreshButtons then mainUI.RefreshButtons() end
            end
        end)
        mBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if btn.destData then
                local mTag = GetDestMacroTag(btn.destData.name)
                if GetCharMacroIndex(mTag) then
                    GameTooltip:AddLine("Макрос: " .. mTag .. " [Создан]", 0.2, 1, 0.4)
                    GameTooltip:AddLine("Клик: удалить макрос персонажа", 1, 0.5, 0.5)
                else
                    GameTooltip:AddLine("Создать макрос", 1, 0.82, 0)
                    GameTooltip:AddLine("Клик: создать " .. mTag .. " в макросах персонажа (/macro)", 0.9, 0.9, 0.9)
                end
            end
            GameTooltip:Show()
        end)
        mBtn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        btn.mBtn = mBtn

        btn:SetScript("PreClick", function(self)
            if not IsShiftKeyDown() then
                UpdateSecureBtnMacro(self)
            end
        end)
        btn:SetScript("PostClick", function(self, mouseBtn, down)
            if down then
                SummonTalorianIfNeeded()
                CheckAndMarkTalorian()
                return
            end
            if not mouseBtn or mouseBtn == "LeftButton" then
                if IsShiftKeyDown() then
                    if rawget(_G, "AttuneAtlas_Toggle") then
                        AttuneAtlas_Toggle()
                        local af = rawget(_G, "AttuneAtlasFrame")
                        if af and af:IsShown() then RaiseFrameFront(af) end
                    end
                else
                    if self.destData then
                        TalorianTP_SetTarget(self.destData.name)
                    end
                    CheckAndMarkTalorian()
                end
            end
        end)

        btn:SetScript("OnEnter", function(self)
            SummonTalorianIfNeeded()
            ShowDestTooltip(self)
        end)
        btn:SetScript("OnLeave", function()
            if hoveredCardBtn == btn then hoveredCardBtn = nil end
            GameTooltip:Hide()
        end)

        table.insert(f.destButtons, btn)
    end

    -- Вкладка 4: Настройки, Макросы и Модули интерфейса
    TalorianTP._BuildSettingsPanel(f, contentFrame)

    -- Вкладка 5: Сервер и Билды (Hardmode Server Control Hub)
    local serverPanel = (type(TalorianTP.BuildServerCtrlPanel) == "function")
        and TalorianTP.BuildServerCtrlPanel(contentFrame, f)
        or CreateFrame("Frame", nil, contentFrame)
    f.serverPanel = serverPanel

    function f:ApplyBlockLayout()
        TalorianTP:EnsureUIDB()
        local hdrOn = TalorianTP:IsBlockEnabled("headerUtils")
        if self.resetBtn then if hdrOn then self.resetBtn:Show() else self.resetBtn:Hide() end end
        if self.bindBtn then if hdrOn then self.bindBtn:Show() else self.bindBtn:Hide() end end
        if self.statusBtn then if hdrOn then self.statusBtn:Show() else self.statusBtn:Hide() end end

        local curY = -50
        if TalorianTP:IsBlockEnabled("modeBar") then
            self.modeBar:ClearAllPoints()
            self.modeBar:SetPoint("TOPLEFT", 16, curY)
            self.modeBar:SetPoint("TOPRIGHT", -16, curY)
            self.modeBar:Show()
            curY = curY - 30
        else
            self.modeBar:Hide()
        end

        local srvTabOn = TalorianTP:IsBlockEnabled("tabServer")
        local visTabs = {}
        for _, tab in ipairs(self.tabs) do
            if tab.id ~= 5 or srvTabOn then
                visTabs[#visTabs + 1] = tab
                tab:Show()
            else
                tab:Hide()
            end
        end
        local nVis = math.max(1, #visTabs)
        local tW = (MAIN_W - 32 - (nVis - 1) * 4) / nVis
        for idx, tab in ipairs(visTabs) do
            tab:SetSize(tW, 26)
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", 16 + (idx - 1) * (tW + 4), curY)
        end
        curY = curY - 30
        self.afterTabsY = curY

        if self.statusBar then
            if TalorianTP:IsBlockEnabled("bottomTools") then
                self.statusBar:Show()
            else
                self.statusBar:Hide()
            end
        end

        if TalorianTP_DB and TalorianTP_DB.activeTab == 5 and not srvTabOn then
            TalorianTP_DB.activeTab = 1
        end
        local activeId = (TalorianTP_DB and TalorianTP_DB.activeTab) or 1
        self:SwitchTab(activeId)

        if self.serverPanel and self.serverPanel.RefreshLayout then
            self.serverPanel:RefreshLayout()
        end
        if self.UpdateSettingsUI then
            self:UpdateSettingsUI()
        end
    end

    -- Переключение вкладок с динамическим перераспределением высоты
    function f:SwitchTab(tabId)
        for _, tab in ipairs(self.tabs) do
            if tab.id == tabId then
                PS.PaintBtn(tab, "gold")
                tab.txt:SetTextColor(1, 0.88, 0.45, 1)
            else
                PS.PaintBtn(tab, "dark")
                tab.txt:SetTextColor(0.82, 0.78, 0.68, 1)
            end
        end

        local y = self.afterTabsY or -108
        local showDiff = (tabId == 1 or tabId == 2) and TalorianTP:IsBlockEnabled("diffBar")
        local botPad = TalorianTP:IsBlockEnabled("bottomTools") and 46 or 14

        if showDiff and self.diffBar then
            self.diffBar:ClearAllPoints()
            self.diffBar:SetPoint("TOPLEFT", 16, y)
            self.diffBar:SetPoint("TOPRIGHT", -16, y)
            self.diffBar:Show()
            y = y - 28
        elseif self.diffBar then
            self.diffBar:Hide()
        end

        if tabId == 1 then
            self.raidEraBar:ClearAllPoints()
            self.raidEraBar:SetPoint("TOPLEFT", 16, y)
            self.raidEraBar:SetPoint("TOPRIGHT", -16, y)
            self.raidEraBar:Show()
            self:UpdateRaidEraHighlight()
            y = y - 30
            self.dungeonEraBar:Hide()
            if showDiff then
                self.diffLabel:Show()
                for _, db in ipairs(self.dungeonDiffBtns) do db:Hide() end
                if self.dungeonSingleDiffBtn then self.dungeonSingleDiffBtn:Hide() end
                for _, qb in ipairs(self.quickRaidBtns) do qb:Show() end
                self.fourMacroBtn:Show()
            end
            self.settingsPanel:Hide()
            if self.serverPanel then self.serverPanel:Hide() end
            for _, btn in ipairs(self.destButtons) do btn:Show() end
        elseif tabId == 2 then
            self.raidEraBar:Hide()
            self.dungeonEraBar:ClearAllPoints()
            self.dungeonEraBar:SetPoint("TOPLEFT", 16, y)
            self.dungeonEraBar:SetPoint("TOPRIGHT", -16, y)
            self.dungeonEraBar:Show()
            self:UpdateDungeonEraHighlight()
            y = y - 30
            if showDiff then
                self.diffLabel:Show()
                for _, rb in ipairs(self.raidDiffBtns) do rb:Hide() end
                if self.raidSingleDiffBtn then self.raidSingleDiffBtn:Hide() end
                for _, qb in ipairs(self.quickRaidBtns) do qb:Hide() end
                self.fourMacroBtn:Hide()
            end
            self.settingsPanel:Hide()
            if self.serverPanel then self.serverPanel:Hide() end
            for _, btn in ipairs(self.destButtons) do btn:Show() end
        elseif tabId == 3 then
            self.raidEraBar:Hide()
            self.dungeonEraBar:Hide()
            self.diffLabel:Hide()
            for _, rb in ipairs(self.raidDiffBtns) do rb:Hide() end
            for _, db in ipairs(self.dungeonDiffBtns) do db:Hide() end
            if self.raidSingleDiffBtn then self.raidSingleDiffBtn:Hide() end
            if self.dungeonSingleDiffBtn then self.dungeonSingleDiffBtn:Hide() end
            for _, qb in ipairs(self.quickRaidBtns) do qb:Hide() end
            self.fourMacroBtn:Hide()
            self.settingsPanel:Hide()
            if self.serverPanel then self.serverPanel:Hide() end
            for _, btn in ipairs(self.destButtons) do btn:Show() end
        elseif tabId == 4 then
            self.raidEraBar:Hide()
            self.dungeonEraBar:Hide()
            self.diffLabel:Hide()
            for _, rb in ipairs(self.raidDiffBtns) do rb:Hide() end
            for _, db in ipairs(self.dungeonDiffBtns) do db:Hide() end
            if self.raidSingleDiffBtn then self.raidSingleDiffBtn:Hide() end
            if self.dungeonSingleDiffBtn then self.dungeonSingleDiffBtn:Hide() end
            for _, qb in ipairs(self.quickRaidBtns) do qb:Hide() end
            self.fourMacroBtn:Hide()
            for _, btn in ipairs(self.destButtons) do btn:Hide() end
            if self.serverPanel then self.serverPanel:Hide() end
            if self.UpdateSettingsUI then self:UpdateSettingsUI() end
            self.settingsPanel:Show()
        elseif tabId == 5 then
            self.raidEraBar:Hide()
            self.dungeonEraBar:Hide()
            self.diffLabel:Hide()
            for _, rb in ipairs(self.raidDiffBtns) do rb:Hide() end
            for _, db in ipairs(self.dungeonDiffBtns) do db:Hide() end
            if self.raidSingleDiffBtn then self.raidSingleDiffBtn:Hide() end
            if self.dungeonSingleDiffBtn then self.dungeonSingleDiffBtn:Hide() end
            for _, qb in ipairs(self.quickRaidBtns) do qb:Hide() end
            self.fourMacroBtn:Hide()
            for _, btn in ipairs(self.destButtons) do btn:Hide() end
            self.settingsPanel:Hide()
            if self.serverPanel then
                self.serverPanel:Show()
                if self.serverPanel.RefreshLayout then self.serverPanel:RefreshLayout() end
                if self.serverPanel.Refresh then self.serverPanel:Refresh() end
            end
        end

        self.contentFrame:ClearAllPoints()
        self.contentFrame:SetPoint("TOPLEFT", 16, y)
        self.contentFrame:SetPoint("BOTTOMRIGHT", -16, botPad)

        if tabId ~= 4 then
            local eb = rawget(_G, "TalorianBugLinkEditBox")
            if eb and eb.ClearFocus then eb:ClearFocus() end
        end

        self:UpdateDiffHighlight()
        self:RefreshButtons()
    end

    local function UpdateProgressBarWidget(w, donePct, absPct)
        if not w or not w.progBg then return end
        local maxW = w._progMaxW or 264
        w.progBg:Show()
        if w.progAbsFill then
            if absPct and absPct > donePct and absPct > 0 then
                w.progAbsFill:SetWidth(math.max(2, math.floor(maxW * math.min(100, absPct) / 100 + 0.5)))
                w.progAbsFill:Show()
            else
                w.progAbsFill:Hide()
            end
        end
        if w.progFill then
            if donePct > 0 then
                w.progFill:SetWidth(math.max(2, math.floor(maxW * math.min(100, donePct) / 100 + 0.5)))
                if donePct >= 100 then
                    w.progFill:SetVertexColor(0.22, 0.90, 0.42, 0.95)
                elseif donePct >= 75 then
                    w.progFill:SetVertexColor(0.62, 0.88, 0.25, 0.95)
                elseif donePct >= 35 then
                    w.progFill:SetVertexColor(1.00, 0.78, 0.18, 0.95)
                else
                    w.progFill:SetVertexColor(0.24, 0.68, 0.98, 0.95)
                end
                w.progFill:Show()
            else
                w.progFill:Hide()
            end
        end
    end

    -- Обновление сетки карточек
    function f:RefreshButtons()
        local activeTab = TalorianTP_DB and TalorianTP_DB.activeTab or 1
        if activeTab == 4 or activeTab == 5 then return end

        local targetRaid = TalorianTP_DB and TalorianTP_DB.targetRaid or "Цитадель Ледяной Короны"
        local raidDiff = TalorianTP_DB and TalorianTP_DB.raidDiff or 1
        local dungeonDiff = TalorianTP_DB and TalorianTP_DB.dungeonDiff or 1

        if self.tabs and self.tabs[3] and self.tabs[3].txt then
            self.tabs[3].txt:SetText("Столицы и VIP (" .. #GetCurrentCapitalList() .. ")")
        end

        local currentList = GetCurrentRaidList()
        if activeTab == 2 then
            currentList = GetCurrentDungeonList()
        elseif activeTab == 3 then
            currentList = GetCurrentCapitalList()
        end

        local ap = rawget(_G, "AttuneParser")
        local showCardProg = TalorianTP:IsBlockEnabled("cardProgress")
        local totalSlots = #self.destButtons
        for slotIdx = 1, totalSlots do
            local btn = self.destButtons[slotIdx]
            local data = currentList[slotIdx]
            if data then
                btn.destData = data
                btn.icon:SetTexture(ResolveIcon(data.icon))
                btn.title:SetText(data.name)

                local subStr = data.subText or (data.exp .. " - " .. data.short)
                btn.subtitle:SetText(subStr)

                local isSelected = (data.name == targetRaid)
                local hasLock = IsInstanceLocked(data.name)

                if isSelected then
                    btn:SetBackdropColor(0.16, 0.12, 0.20, 0.94)
                    btn:SetBackdropBorderColor(1.00, 0.82, 0.30, 1.00)
                    btn.title:SetTextColor(1, 0.92, 0.65, 1)
                elseif hasLock then
                    -- Подложка перекрашивается в зеленый при наличии КД
                    btn:SetBackdropColor(0.06, 0.24, 0.10, 0.90)
                    btn:SetBackdropBorderColor(0.25, 0.80, 0.35, 1.00)
                    btn.title:SetTextColor(0.85, 1, 0.85, 1)
                else
                    btn:SetBackdropColor(0.00, 0.00, 0.00, 0.38)
                    btn:SetBackdropBorderColor(0.50, 0.42, 0.24, 0.72)
                    btn.title:SetTextColor(0.93, 0.89, 0.78, 1)
                end

                local curD = data.isRaid and raidDiff or dungeonDiff
                if showCardProg and ap and ap.GetZoneAnalysis and data.attune then
                    local za = ap:GetZoneAnalysis(data.attune, {
                        diffId = curD,
                        isRaid = data.isRaid,
                        exp = data.exp,
                        scope = "hero",
                    })
                    if za and za.modeAvailable == false then
                        btn.badge:SetText("|cff666666-|r")
                        btn.badge:SetTextColor(0.5, 0.5, 0.5, 1)
                        if btn.statBadge then btn.statBadge:SetText("|cff666666Нет сложности|r") end
                        if btn.progBg then btn.progBg:Hide() end
                    elseif za and za.totalPool and za.totalPool > 0 then
                        local remStats = za.totalRemainStats or 0
                        local nNew = za.newCount or 0
                        local nForge = za.forgeCount or 0
                        local nRand = (za.randomSuffixNew or 0) + (za.randomSuffixForge or 0)
                        local doneCnt = za.completedCount or 0
                        local donePct = math.floor((doneCnt / za.totalPool) * 100 + 0.5)
                        local absCnt = math.max(doneCnt, math.min(za.totalPool, doneCnt + nForge + (za.randomSuffixForge or 0)))
                        local absPct = math.floor((absCnt / za.totalPool) * 100 + 0.5)
                        local pCol = (donePct >= 100) and "|cff40ff40"
                            or (donePct >= 75 and "|cffa3e635"
                            or (donePct >= 35 and "|cffffd200" or "|cff60a5fa"))
                        btn.subtitle:SetText(string.format("%s%d%%|r |cff94a3b8(%d/%d)|r - %s",
                            pCol, donePct, doneCnt, za.totalPool, data.short or data.exp))

                        UpdateProgressBarWidget(btn, donePct, absPct)

                        btn.badge:SetTextColor(1, 1, 1, 1)
                        if nNew == 0 and nForge == 0 and nRand == 0 then
                            btn.badge:SetText(string.format("|cff40ff40%d / %d|r", doneCnt, za.totalPool))
                            if btn.statBadge then btn.statBadge:SetText("|cff40ff40Готово 100%|r") end
                        else
                            if nNew > 0 and nForge > 0 then
                                btn.badge:SetText(string.format("|cff40ff40%d нов.|r |cffffd200%d ков.|r", nNew, nForge))
                            elseif nNew > 0 then
                                btn.badge:SetText(string.format("|cff40ff40+%d новых|r", nNew))
                            elseif nForge > 0 then
                                btn.badge:SetText(string.format("|cffffd200%d ковки|r", nForge))
                            else
                                btn.badge:SetText(string.format("|cffaaaaaa*%d суфф.|r", nRand))
                            end

                            if btn.statBadge then
                                if remStats >= 1000 then
                                    btn.statBadge:SetText(string.format("|cff38bdf8+%.1fк стат.|r", remStats / 1000))
                                elseif remStats > 0 then
                                    btn.statBadge:SetText(string.format("|cff38bdf8+%d стат.|r", remStats))
                                else
                                    btn.statBadge:SetText("")
                                end
                            end
                        end
                    else
                        btn.badge:SetText("")
                        if btn.statBadge then btn.statBadge:SetText("") end
                        if btn.progBg then btn.progBg:Hide() end
                    end
                else
                    btn.badge:SetText("")
                    if btn.statBadge then btn.statBadge:SetText("") end
                    if btn.progBg then btn.progBg:Hide() end
                end

                -- Динамический правый отступ под ширину бейджей, чтобы длинные названия не обрезались раньше времени
                local sTxt = btn.statBadge and btn.statBadge:GetText() or ""
                local bTxt = btn.badge and btn.badge:GetText() or ""
                local sW = (sTxt ~= "" and btn.statBadge.GetStringWidth and (btn.statBadge:GetStringWidth() or 0)) or 0
                local bW = (bTxt ~= "" and btn.badge.GetStringWidth and (btn.badge:GetStringWidth() or 0)) or 0
                local tPad = (sW > 0) and (36 + math.ceil(sW)) or 32
                local bPad = (bW > 0) and (36 + math.ceil(bW)) or 32
                btn.title:ClearAllPoints()
                btn.title:SetPoint("TOPLEFT", btn.icon, "TOPRIGHT", 6, -1)
                btn.title:SetPoint("RIGHT", btn, "RIGHT", -tPad, 0)
                btn.subtitle:ClearAllPoints()
                btn.subtitle:SetPoint("BOTTOMLEFT", btn.icon, "BOTTOMRIGHT", 6, 1)
                btn.subtitle:SetPoint("RIGHT", btn, "RIGHT", -bPad, 0)

                -- Индикатор макроса
                local mTag = GetDestMacroTag(data.name)
                if GetCharMacroIndex(mTag) then
                    PS.PaintBtn(btn.mBtn, "green")
                    btn.mBtn.txt:SetText("|cff40ff40-M|r")
                else
                    PS.PaintBtn(btn.mBtn, "dark")
                    btn.mBtn.txt:SetText("|cffffd200+M|r")
                end

                btn:Show()
            else
                btn.destData = nil
                btn:Hide()
            end
        end

        if self.quickRaidBtns then
            for _, qBtn in ipairs(self.quickRaidBtns) do
                local dest = qBtn.destName and FindDestByName(qBtn.destName) or nil
                local za = (showCardProg and ap and ap.GetZoneAnalysis and dest and dest.attune) and ap:GetZoneAnalysis(dest.attune, {
                    diffId = raidDiff, isRaid = true, exp = dest.exp, scope = "hero",
                }) or nil
                if qBtn.progBg and za and za.totalPool and za.totalPool > 0 and za.modeAvailable ~= false then
                    local qDone = za.completedCount or 0
                    local pct = math.floor((qDone / za.totalPool) * 100 + 0.5)
                    local qAbs = math.max(qDone, math.min(za.totalPool, qDone + (za.forgeCount or 0) + (za.randomSuffixForge or 0)))
                    local absPct = math.floor((qAbs / za.totalPool) * 100 + 0.5)
                    UpdateProgressBarWidget(qBtn, pct, absPct)
                elseif qBtn.progBg then
                    qBtn.progBg:Hide()
                end
            end
        end

        self:UpdateResetCDHighlight()
        if self.UpdateDiffButtonCounts then self:UpdateDiffButtonCounts() end
    end

    -- Нижняя строка состояния (с отступом от сетки кнопок телепорта)
    local statusBar = CreateFrame("Frame", nil, f)
    statusBar:SetPoint("BOTTOMLEFT", 16, 10)
    statusBar:SetPoint("BOTTOMRIGHT", -16, 10)
    statusBar:SetHeight(24)
    f.statusBar = statusBar

    local statusNote = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusNote:SetPoint("LEFT", 0, 0)
    statusNote:SetJustifyH("LEFT")
    if statusNote.SetWordWrap then statusNote:SetWordWrap(false) end
    f.statusNote = statusNote

    function f:UpdateStatusNote()
        local _, foundPet = IsTalorianSummoned()
        if not foundPet then
            self.statusNote:SetText("|cffff7070Спутник Талориан не найден - телепорт отключен (режим аналитики)|r")
            return
        end
        local k = TalorianTP_DB and TalorianTP_DB.interactKey or "ъ"
        local en = TalorianTP_DB and TalorianTP_DB.enabled and "ВКЛ" or "ВЫКЛ"
        self.statusNote:SetText("|cffc8bea8Бинд: [|cffffffff" .. k .. "|r] (" .. en .. ") | Метка: " .. ICON_DIAMOND .. " | Авто-выбор меню|r")
    end

    local createDestMacroBtn = CreateFrame("Button", nil, statusBar)
    createDestMacroBtn:SetSize(192, 22)
    createDestMacroBtn:SetPoint("RIGHT", 0, 0)
    f.createDestMacroBtn = createDestMacroBtn

    local analysisBtn = CreateFrame("Button", nil, statusBar)
    analysisBtn:SetSize(124, 22)
    analysisBtn:SetPoint("RIGHT", createDestMacroBtn, "LEFT", -6, 0)
    PS.StyleBtn(analysisBtn, "dark")
    local abTxt = analysisBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    abTxt:SetPoint("CENTER", 0, 0)
    abTxt:SetText("|cfff7dfb5Вещи по инстам|r")
    analysisBtn.txt = abTxt
    analysisBtn:SetScript("OnClick", function() if TalorianTP_ToggleAnalysisWindow then TalorianTP_ToggleAnalysisWindow() end end)
    analysisBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Вещи по рейдам и подземельям", 1, 0.82, 0)
        GameTooltip:AddLine("Интерактивный просмотр предметов инстов, статуса ковки, боссов, статов и ссылок в чат.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    analysisBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local atlasBtn = CreateFrame("Button", nil, statusBar)
    atlasBtn:SetSize(112, 22)
    atlasBtn:SetPoint("RIGHT", analysisBtn, "LEFT", -6, 0)
    statusNote:SetPoint("RIGHT", atlasBtn, "LEFT", -8, 0)
    PS.StyleBtn(atlasBtn, "dark")
    atlasBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local atlTxt = atlasBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    atlTxt:SetPoint("CENTER", 0, 0)
    atlTxt:SetText("|cffffd200Атлас и Топ|r")
    atlasBtn.txt = atlTxt
    atlasBtn:SetScript("OnClick", function(_, mouseBtn)
        local ap = rawget(_G, "AttuneParser")
        if mouseBtn == "RightButton" then
            if rawget(_G, "AttuneAtlas_Toggle") then
                AttuneAtlas_Toggle()
                local af = rawget(_G, "AttuneAtlasFrame")
                if af and af:IsShown() then RaiseFrameFront(af) end
            elseif TalorianTP_ToggleTopWindow then
                TalorianTP_ToggleTopWindow()
            else
                DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Серверный Атлас Поглощения недоступен.")
            end
        elseif ap and type(ap.OpenUI) == "function" then
            ap:OpenUI("top")
            RaiseFrameFront(rawget(_G, "AttuneParserFrame"))
        elseif TalorianTP_ToggleTopWindow then
            TalorianTP_ToggleTopWindow()
        elseif rawget(_G, "AttuneAtlas_Toggle") then
            AttuneAtlas_Toggle()
            local af = rawget(_G, "AttuneAtlasFrame")
            if af and af:IsShown() then RaiseFrameFront(af) end
        end
    end)
    atlasBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Атлас и Топ рекомендаций (AttuneParser)", 1, 0.82, 0)
        GameTooltip:AddLine("ЛКМ: открыть окно AttuneParser (Топ инстов / Путеводитель)", 0.2, 1, 0.4)
        GameTooltip:AddLine("ПКМ: открыть Атлас Поглощения", 0.85, 0.85, 0.85)
        GameTooltip:Show()
    end)
    atlasBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    PS.StyleBtn(createDestMacroBtn, "dark")
    local cdmTxt = createDestMacroBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cdmTxt:SetPoint("CENTER", 0, 0)
    cdmTxt:SetText("|cfff7dfb5Создать макрос|r")
    createDestMacroBtn.txt = cdmTxt

    createDestMacroBtn:SetScript("OnClick", function() TalorianTP_ToggleMacroForDest() end)
    createDestMacroBtn:SetScript("OnEnter", function(self)
        local cur = TalorianTP_DB and TalorianTP_DB.targetRaid or "Цитадель Ледяной Короны"
        local tag = GetDestMacroTag(cur)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        if GetCharMacroIndex(tag) then
            GameTooltip:AddLine("Макрос " .. tag .. " уже создан", 0.2, 1, 0.4)
            GameTooltip:AddLine("Клик: удалить макрос для " .. cur, 1, 0.5, 0.5)
        else
            GameTooltip:AddLine("Создать макрос для " .. cur, 1, 0.82, 0)
            GameTooltip:AddLine("Создаст макрос " .. tag .. " в /macro (призыв Талориана + телепорт).", 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    createDestMacroBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f:UpdateHeaderTarget()
    f:UpdateStatusButton()
    f:UpdateBindText()
    f:UpdateModeHighlight()
    f:UpdateStatusNote()
    f:ApplyBlockLayout()

    f._skipNextShowRefresh = true
    f:HookScript("OnShow", function(self) RaiseFrameFront(self) end)
    f:Hide()
    mainUI = f
    return f
end

function TalorianTP:OpenUI(tabId)
    TalorianTP_DB = TalorianTP_DB or {}
    self:EnsureUIDB()
    local ui = InitTalorianUI()
    if ui.ApplyBlockLayout then ui:ApplyBlockLayout() end
    if tabId then
        if tabId ~= 5 or self:IsBlockEnabled("tabServer") then
            TalorianTP_DB.activeTab = tabId
            if ui.SwitchTab then ui:SwitchTab(tabId) end
        end
    end
    ui:Show()
    RaiseFrameFront(ui)
    if TalorianTP_DB and not TalorianTP_DB.uiOnboardingDone and not self._onboardingAutoOpened then
        self._onboardingAutoOpened = true
        self:ShowOnboardingWizard(false)
    end
    return ui
end

---------------------------------------------------------------------------
-- Модальное окно захвата клавиши бинда (клавиатура и кнопки мыши)
---------------------------------------------------------------------------
local keyCaptureFrame = nil

local function CreateKeyCaptureFrame()
    if keyCaptureFrame then return keyCaptureFrame end

    local kf = CreateFrame("Frame", "TalorianKeyCaptureFrame", UIParent)
    kf:SetSize(340, 150)
    kf:SetPoint("CENTER", 0, 0)
    kf:SetFrameStrata("FULLSCREEN_DIALOG")
    kf:SetToplevel(true)
    kf:EnableMouse(true)
    kf:EnableKeyboard(true)

    PS.ApplyWindow(kf)

    local title = kf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -18)
    title:SetText("|cfffce08cНазначение клавиши взаимодействия|r")

    local desc = kf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOP", 0, -48)
    desc:SetText("|cffede3c7Нажмите любую клавишу клавиатуры\nили кнопку мыши (BUTTON3, 4, 5)...|r")

    local cancelBtn = CreateFrame("Button", nil, kf)
    cancelBtn:SetSize(100, 24)
    cancelBtn:SetPoint("BOTTOM", 0, 16)
    PS.StyleBtn(cancelBtn, "red")
    local cancelTxt = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cancelTxt:SetPoint("CENTER", 0, 0)
    cancelTxt:SetText("Отмена")
    cancelBtn:SetScript("OnClick", function() kf:Hide() end)

    local function ApplyCapturedKey(chosenKey)
        if chosenKey and chosenKey ~= "ESCAPE" then
            if InCombatLockdown() then
                DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "|cffff4444Невозможно изменить бинд в бою! Повторите вне боя.|r")
                kf:Hide()
                return
            end
            local oldKey = TalorianTP_DB and TalorianTP_DB.interactKey
            if oldKey and oldKey ~= chosenKey and type(GetBindingAction) == "function" and GetBindingAction(oldKey) == "INTERACTTARGET" then
                pcall(SetBinding, oldKey)
            end
            TalorianTP_DB.interactKey = chosenKey
            TalorianTP_DB.interactKeyInited = true
            SetBinding(chosenKey, "INTERACTTARGET")
            SaveBindings(GetCurrentBindingSet())
            DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Клавиша взаимодействия установлена: |cffffd200" .. chosenKey .. "|r")
            if mainUI and mainUI.UpdateBindText then mainUI:UpdateBindText() end
            if mainUI and mainUI.UpdateStatusNote then mainUI:UpdateStatusNote() end
        end
        kf:Hide()
    end

    kf:SetScript("OnShow", function(self)
        if self.EnableKeyboard then self:EnableKeyboard(true) end
    end)
    kf:SetScript("OnHide", function(self)
        if self.EnableKeyboard then self:EnableKeyboard(false) end
    end)

    kf:SetScript("OnKeyDown", function(self, key)
        if not key or key == "UNKNOWN" or key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
            return
        end
        if key == "ESCAPE" then
            self:Hide()
        else
            ApplyCapturedKey(key)
        end
    end)

    kf:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" or button == "RightButton" then
            return
        end
        local mapped = (button == "MiddleButton" and "BUTTON3") or (type(button) == "string" and button:upper()) or button
        ApplyCapturedKey(mapped)
    end)

    kf:Hide()
    keyCaptureFrame = kf
    return kf
end

function TalorianTP_StartKeyCapture()
    local kf = CreateKeyCaptureFrame()
    kf:Show()
    if kf.EnableKeyboard then kf:EnableKeyboard(true) end
end

---------------------------------------------------------------------------
-- Кнопка миникарты
---------------------------------------------------------------------------
local function UpdateMinimapPos(btn)
    if not btn or not Minimap then return end
    local angle = math.rad(TalorianTP_DB and TalorianTP_DB.minimapPos or 192)
    local radius = 80
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local minimapButton = nil

local function CreateMinimapButton()
    if not Minimap then return minimapButton end
    local mmOn = (type(TalorianTP.IsBlockEnabled) ~= "function") or TalorianTP:IsBlockEnabled("minimapBtn")
    if minimapButton then
        UpdateMinimapPos(minimapButton)
        if mmOn then minimapButton:Show() else minimapButton:Hide() end
        return minimapButton
    end
    local btn = CreateFrame("Button", "TalorianMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
    btn:EnableMouse(true)
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_TeleportMoonglade")
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    if btn.SetHighlightTexture then
        btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    end

    UpdateMinimapPos(btn)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:SetScript("OnUpdate", function(self)
            if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
                self:SetScript("OnUpdate", nil)
                self.isDragging = false
                return
            end
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local deg = math.deg(math.atan2(cy - my, cx - mx))
            if deg < 0 then deg = deg + 360 end
            TalorianTP_DB = TalorianTP_DB or {}
            TalorianTP_DB.minimapPos = deg
            UpdateMinimapPos(self)
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.isDragging = false
    end)

    btn:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self.isDragging = false
    end)

    btn:SetScript("OnClick", function(self, mouseBtn)
        if self.isDragging then return end
        if mouseBtn == "LeftButton" then
            if mainUI and mainUI:IsVisible() then mainUI:Hide() else TalorianTP:OpenUI() end
        elseif mouseBtn == "RightButton" then
            TalorianTP_DB.enabled = not TalorianTP_DB.enabled
            if not TalorianTP_DB.enabled then
                targetPollTimer = 0
            else
                SummonTalorianIfNeeded()
                targetPollTimer = 4.0
                targetPollElapsed = 0
            end
            UpdateAllSecureButtonsMacro()
            EnsureSecureExecButton()
            if mainUI and mainUI.UpdateStatusButton then mainUI:UpdateStatusButton() end
            if mainUI and mainUI.UpdateStatusNote then mainUI:UpdateStatusNote() end
            local st = TalorianTP_DB.enabled and "|cff00ff88включен|r" or "|cffff4444выключен|r"
            DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Аддон " .. st)
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Talorian v" .. TALORIAN_VERSION, 0.2, 0.7, 1)
        GameTooltip:AddLine("ЛКМ: открыть/закрыть окно аддона", 1, 1, 1)
        GameTooltip:AddLine("ПКМ: быстрое включение/отключение", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Перетаскивание: перемещение по миникарте", 0.6, 0.6, 0.6)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("По вопросам писать: Sodoesqai", 1, 0.82, 0)
        GameTooltip:AddLine("Мотивация и подсказки: Motherofgod", 0.3, 1, 0.5)
        GameTooltip:AddLine("Благодарность Дуре за вынос кнопки сброса кд", 0.4, 0.8, 1)
        GameTooltip:AddLine("По багам - https://t.me/sodooqie", 0.6, 0.85, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if mmOn then btn:Show() else btn:Hide() end
    minimapButton = btn
    return btn
end

---------------------------------------------------------------------------
-- Главный фрейм событий и запуск
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame", "TalorianEventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("GOSSIP_CLOSED")
eventFrame:RegisterEvent("GOSSIP_CONFIRM")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("UPDATE_BINDINGS")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:RegisterEvent("COMPANION_UPDATE")
eventFrame:RegisterEvent("COMPANION_LEARNED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

local function EnsureAttuneParserBridge()
    local ap = rawget(_G, "AttuneParser")
    if not ap or not ap.RegisterCallback then return false end
    if not ap._talorianCallbacksDone then
        ap._talorianCallbacksDone = true
        local function DoUiRefresh()
            if mainUI and mainUI:IsVisible() and mainUI.RefreshButtons then
                mainUI:RefreshButtons()
            end
            if hoveredCardBtn and hoveredCardBtn:IsVisible() then
                ShowDestTooltip(hoveredCardBtn)
            end
            if _G.TalorianAnalysisFrame and _G.TalorianAnalysisFrame:IsShown() and TalorianTP_RefreshAnalysisLive then
                TalorianTP_RefreshAnalysisLive()
            end
            if _G.TalorianTopFrame and _G.TalorianTopFrame:IsShown() and TalorianTP_RefreshTopLive then
                TalorianTP_RefreshTopLive()
            end
        end
        local function OnParserUpdate()
            InvalidateOwnedZoneCache()
            if ap.After then
                ap.After(0.12, DoUiRefresh, "ttp_ui_refresh")
            else
                DoUiRefresh()
            end
        end
        ap:RegisterCallback("ATTUNE_UPDATED", OnParserUpdate)
        ap:RegisterCallback("ZONE_UPDATED", OnParserUpdate)
        ap:RegisterCallback("FORGE_UPDATED", OnParserUpdate)
        ap:RegisterCallback("MILESTONES_UPDATED", OnParserUpdate)
        ap:RegisterCallback("ITEM_SOURCES_UPDATED", OnParserUpdate)
        ap:RegisterCallback("DAILY_GIFT_UPDATED", OnParserUpdate)
        ap:RegisterCallback("PETLOOT_UPDATED", OnParserUpdate)
        ap:RegisterCallback("AUTOSWAP_UPDATED", OnParserUpdate)
        ap:RegisterCallback("PARAGON_UPDATED", OnParserUpdate)
        ap:RegisterCallback("SCAN_COMPLETE", OnParserUpdate)
    end
    if type(ap.RegisterTalorianBridge) == "function" and not ap._talorianBridgeDone then
        ap._talorianBridgeDone = true
        ap:RegisterTalorianBridge({
            HasPet = function()
                local isSumm, foundPet = IsTalorianSummoned()
                return foundPet == true, isSumm == true
            end,
            IsAvailable = function()
                local _, foundPet = IsTalorianSummoned()
                return foundPet == true and (not TalorianTP_DB or TalorianTP_DB.enabled ~= false)
            end,
            SelectZone = function(zoneId, zoneName)
                if type(_G.TalorianTP_SelectZone) == "function" then
                    return _G.TalorianTP_SelectZone(zoneId, zoneName)
                end
                return false
            end,
            OpenUI = function()
                if TalorianTP and type(TalorianTP.OpenUI) == "function" then
                    TalorianTP:OpenUI()
                    return true
                elseif mainUI then
                    mainUI:Show()
                    if mainUI.RefreshButtons then mainUI:RefreshButtons() end
                    return true
                elseif SlashCmdList["TALORIANTP"] then
                    SlashCmdList["TALORIANTP"]("")
                    return true
                end
                return false
            end,
        })
        if TalorianTP_DB and not TalorianTP_DB._apSettingsMigrated and type(ap.EnsureSettings) == "function" then
            local st = ap:EnsureSettings()
            if TalorianTP_DB.hideAuctionPanel == true then
                st.showAuctionUI = false
            end
            if type(TalorianTP_DB.aucBtnPos) == "table" and not st.aucBtnPos then
                local pos = TalorianTP_DB.aucBtnPos
                st.aucBtnPos = { point = pos.pt, relPoint = pos.relPt or pos.pt, x = pos.x or 0, y = pos.y or 0 }
            end
            TalorianTP_DB._apSettingsMigrated = true
        end
    end
    if not ap._talorianPrioSynced and ap.After and ap.QueuePriorityZonesSync then
        ap._talorianPrioSynced = true
        ap.After(4.0, function()
            local ids = {}
            local cur = FindDestByName(TalorianTP_DB and TalorianTP_DB.targetRaid)
            if cur and cur.attune then table.insert(ids, cur.attune) end
            for _, r in ipairs(RAID_DESTS) do
                if r.attune and r.exp == "WotLK" then
                    table.insert(ids, r.attune)
                end
            end
            ap:QueuePriorityZonesSync(ids)
        end, "ttp_prio_zone_sync")
    end
    return true
end
TalorianTP.EnsureAttuneParserBridge = EnsureAttuneParserBridge

local function RegisterTalorianPrimeHub(forceKeep)
    local ph = rawget(_G, "PrimeHub")
    if not ph then return end
    local db = rawget(_G, "PrimeHubDB")
    if type(db) == "table" and (forceKeep or (TalorianTP_DB and not TalorianTP_DB.minimapKeepInit)) then
        db.keep = db.keep or {}
        db.keep["TalorianMinimapButton"] = true
        if TalorianTP_DB then TalorianTP_DB.minimapKeepInit = true end
        if forceKeep and ph.Shelf and type(ph.Shelf.Rescan) == "function" then
            pcall(ph.Shelf.Rescan)
        end
    end
    if type(ph.Register) == "function" and not _G._talorianPrimeHubReg then
        _G._talorianPrimeHubReg = true
        pcall(ph.Register, ph, {
            id = "talorian_tp",
            title = "Талориан ТП",
            icon = "Interface\\Icons\\Spell_Arcane_TeleportMoonglade",
            order = 37,
            status = function()
                return (TalorianTP_DB and TalorianTP_DB.enabled) and "Активен" or "Выключен"
            end,
            open = function()
                if mainUI and mainUI:IsVisible() then mainUI:Hide() else TalorianTP:OpenUI() end
            end,
        })
    end
end

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == "AttuneParser" then
        pcall(EnsureAttuneParserBridge)
    elseif event == "ADDON_LOADED" and arg1 == "PrimeHub" then
        RegisterTalorianPrimeHub(false)
    elseif event == "ADDON_LOADED" and arg1 == "TalorianTP" then
        TalorianTP_DB = TalorianTP_DB or {}
        if TalorianTP_DB.enabled == nil then TalorianTP_DB.enabled = true end
        if not TalorianTP_DB.targetRaid then TalorianTP_DB.targetRaid = "Цитадель Ледяной Короны" end
        if not TalorianTP_DB.mode then TalorianTP_DB.mode = "teleport" end
        if not TalorianTP_DB.raidDiff then TalorianTP_DB.raidDiff = 4 end -- 25 гер по умолчанию
        if not TalorianTP_DB.dungeonDiff then TalorianTP_DB.dungeonDiff = 2 end -- Героический по умолчанию
        if not TalorianTP_DB.activeTab then TalorianTP_DB.activeTab = 1 end
        if not TalorianTP_DB.raidEra then TalorianTP_DB.raidEra = "All" end
        if not TalorianTP_DB.dungeonEra then TalorianTP_DB.dungeonEra = "WotLK" end
        if not TalorianTP_DB.interactKey then TalorianTP_DB.interactKey = "ъ" end
        if not TalorianTP_DB.minimapPos then TalorianTP_DB.minimapPos = 192 end
        TalorianTP:EnsureUIDB()

        EnsureSecureExecButton()

        CreateMinimapButton()
        noticeFrame = CreateNoticeFrame()
        pcall(RefreshZoneSummaryCache)
        pcall(RefreshRaidLocks)
        RegisterTalorianPrimeHub(false)

        pcall(EnsureAttuneParserBridge)

        if TalorianTP_DB.enabled then
            SummonTalorianIfNeeded()
            targetPollTimer = 4.0
            targetPollElapsed = 0
        end

        local k = TalorianTP_DB.interactKey or "ъ"
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "v" .. TALORIAN_VERSION .. " загружен. Открыть: |cffffd200/ttp|r | Блоки UI: |cff40ff40/ttp blocks|r | Бинд: [|cffffffff" .. k .. "|r]")
    elseif event == "PLAYER_LOGIN" then
        pcall(EnsureAttuneParserBridge)
        CreateMinimapButton()
        RegisterTalorianPrimeHub(false)
        RefreshZoneSummaryCache()
        RefreshRaidLocks()
        EnsureSecureExecButton()
        RefreshTalorianOverrideBinding()
        local k = TalorianTP_DB and TalorianTP_DB.interactKey or "ъ"
        if TalorianTP_DB and not TalorianTP_DB.interactKeyInited and not InCombatLockdown() and type(GetCurrentBindingSet) == "function" and type(SetBinding) == "function" then
            TalorianTP_DB.interactKeyInited = true
            local curAct = (type(GetBindingAction) == "function") and GetBindingAction(k) or nil
            if not curAct or curAct == "" then
                pcall(SetBinding, k, "INTERACTTARGET")
                pcall(SaveBindings, GetCurrentBindingSet())
            end
        end
        if TalorianTP_DB and TalorianTP_DB.enabled then
            SummonTalorianIfNeeded()
            targetPollTimer = 4.0
            targetPollElapsed = 0
        end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
        CheckAndMarkTalorian(true)
    elseif event == "UPDATE_BINDINGS" then
        RefreshTalorianOverrideBinding()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if TalorianTP_DB and TalorianTP_DB.enabled then
            SummonTalorianIfNeeded()
        end
        UpdateAllSecureButtonsMacro()
    elseif event == "GOSSIP_SHOW" then
        CheckAndMarkTalorian(false)
        ProcessGossip()
    elseif event == "MERCHANT_SHOW" then
        CheckAndMarkTalorian(false)
    elseif event == "GOSSIP_CLOSED" then
        isTeleporting = false
        confirmTimer = 0
    elseif event == "GOSSIP_CONFIRM" then
        if isTeleporting and AutoAcceptPopup() then
            isTeleporting = false
            confirmTimer = 0
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        pcall(EnsureAttuneParserBridge)
        RefreshZoneSummaryCache()
        RefreshRaidLocks()
        if TalorianTP_DB and TalorianTP_DB.enabled then
            local _, foundPet = IsTalorianSummoned()
            if foundPet then
                SummonTalorianIfNeeded()
                targetPollTimer = 4.0
                targetPollElapsed = 0
            else
                targetPollTimer = 0
            end
        else
            targetPollTimer = 0
        end
        if mainUI and mainUI:IsVisible() and mainUI.RefreshButtons then
            mainUI:RefreshButtons()
        end
    elseif event == "UPDATE_INSTANCE_INFO" then
        RefreshRaidLocks()
        if mainUI and mainUI:IsVisible() and mainUI.RefreshButtons then
            mainUI:RefreshButtons()
        end
    elseif event == "BAG_UPDATE" or event == "BANKFRAME_OPENED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        InvalidateOwnedZoneCache()
    elseif event == "COMPANION_UPDATE" or event == "COMPANION_LEARNED" then
        if TalorianTP_DB and TalorianTP_DB.enabled then
            local isSumm, foundPet = IsTalorianSummoned()
            if not foundPet then
                targetPollTimer = 0
                if mainUI and mainUI:IsVisible() and mainUI.UpdateStatusNote then
                    mainUI:UpdateStatusNote()
                end
            elseif not isSumm then
                SummonTalorianIfNeeded()
            else
                CheckAndMarkTalorian(false)
            end
            UpdateAllSecureButtonsMacro()
        end
        local ap = rawget(_G, "AttuneParser")
        if ap and ap.Fire then ap:Fire("TALORIAN_BRIDGE_UPDATED") end
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == "ASMSG_ATC_ZONES" then
            RefreshZoneSummaryCache(arg2)
            if mainUI and mainUI:IsVisible() and mainUI.RefreshButtons then
                mainUI:RefreshButtons()
            end
        elseif arg1 == "ASMSG_ATC_ZONE" and ParseServerZoneItems then
            ParseServerZoneItems(arg2)
        end
    end
end)

local periodicSummonTimer = 0
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    if isTeleporting then
        confirmTimer = confirmTimer + elapsed
        if confirmTimer > 0.05 then
            confirmTimer = 0
            if AutoAcceptPopup() then
                isTeleporting = false
            end
        end
    end

    if targetPollTimer > 0 then
        targetPollElapsed = targetPollElapsed + elapsed
        if targetPollElapsed >= 0.1 then
            targetPollElapsed = 0
            SummonTalorianIfNeeded()
            if CheckAndMarkTalorian(true) then
                targetPollTimer = 0
            else
                targetPollTimer = targetPollTimer - 0.1
            end
        end
    end

    -- Периодическая проверка наличия Талориана в фоне каждые 1.5 сек (при включенном аддоне)
    periodicSummonTimer = periodicSummonTimer + elapsed
    if periodicSummonTimer >= 1.5 then
        periodicSummonTimer = 0
        if TalorianTP_DB and TalorianTP_DB.enabled and not InCombatLockdown() then
            local isSumm, foundPet = IsTalorianSummoned()
            if not foundPet then
                targetPollTimer = 0
            elseif not isSumm then
                SummonTalorianIfNeeded()
            else
                CheckAndMarkTalorian(false)
            end
        end
    end

    if ProcessBgForgeScanQueue then
        ProcessBgForgeScanQueue()
    end
end)

---------------------------------------------------------------------------
-- Слэш-команды
---------------------------------------------------------------------------
-- Немедленная инициализация кнопки миникарты при загрузке файла
CreateMinimapButton()

SLASH_TALORIANTP1 = "/ttp"
SLASH_TALORIANTP2 = "/talorian"
SlashCmdList["TALORIANTP"] = function(msg)
    msg = msg and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    if msg == "summon" then
        local isSumm, inList = IsTalorianSummoned()
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. string.format("Статус спутника: в списке=%s, призван=%s", tostring(inList), tostring(isSumm)))
        local ok = SummonTalorianIfNeeded()
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Вызов SummonTalorianIfNeeded: " .. tostring(ok))
        return
    elseif msg == "mark" then
        local marked = CheckAndMarkTalorian(true)
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Проверка и разметка Талориана: " .. tostring(marked))
        return
    elseif msg == "parse" or msg == "attune" or msg == "stat" then
        TalorianTP_ToggleAnalysisWindow()
        TalorianTP_PrintAnalysisToChat()
        return
    elseif msg == "gossip" then
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "|cffffd200История госсип-меню (последние записи):|r")
        local logs = TalorianTP_DB and TalorianTP_DB.gossipLog or {}
        if #logs == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("История госсипа пуста. Поговорите с Талорианом.")
        else
            for idx, entry in ipairs(logs) do
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[%s] Меню #%d:|r", entry.time or "??", idx))
                for optIdx, opt in ipairs(entry.options) do
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d. %s", optIdx, opt))
                end
            end
        end
    elseif msg == "blocks" or msg == "setup" or msg == "wizard" or msg == "master" then
        TalorianTP:ShowOnboardingWizard(true)
        return
    elseif msg == "minimap" then
        TalorianTP_DB = TalorianTP_DB or {}
        if not TalorianTP_DB.minimapPos then TalorianTP_DB.minimapPos = 192 end
        TalorianTP:SetBlockEnabled("minimapBtn", true)
        CreateMinimapButton()
        RegisterTalorianPrimeHub(true)
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Кнопка у миникарты показана.")
        return
    elseif msg:find("^rec") or msg:find("^recommend") or msg:find("^совет") or msg:find("^топ") then
        local subCmd = msg:match("%s+(%S+)$") or "ALL"
        subCmd = subCmd:lower()
        local ap = rawget(_G, "AttuneParser")
        local pac = rawget(_G, "PrimeAttuneCore")
        if ap and ap.GetRecommendations then
            local newRecs = ap:GetRecommendations({ mode = "new", onlyInstances = true, limit = 6 })
            local forgeRecs = ap:GetRecommendations({ mode = "forge", onlyInstances = true, limit = 6 })
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200=== ТОП ИНСТОВ: НОВЫЕ ПРЕДМЕТЫ (AttuneParser) ===|r")
            if #newRecs == 0 then
                DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaa(Все базовые предметы поглощены)|r")
            else
                for idx, z in ipairs(newRecs) do
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cffffd200#%d|r |cffffffff%s|r: |cff40ff40+%d новых|r (+%d статов сразу, макс +%d)", idx, z.zoneName, z.newCount or 0, z.newImmediateStats or 0, z.newMaxStats or 0))
                end
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd200=== ТОП ИНСТОВ: КОВКА ДО ТИТАНИЧЕСКОГО (90%) ===|r")
            if #forgeRecs == 0 then
                DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaa(Все доступные предметы докачаны до Титанического)|r")
            else
                for idx, z in ipairs(forgeRecs) do
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cffffd200#%d|r |cffffffff%s|r: |cffffd200%d на ковку|r (осталось +%d статов)", idx, z.zoneName, z.forgeCount or 0, z.forgeRemainStats or 0))
                end
            end
        elseif pac and pac.GetTopRecommendedZones then
            local specKey = pac:DetectPlayerSpec()
            local specProfile = pac.SpecProfiles and pac.SpecProfiles[specKey]
            local specName = (specProfile and specProfile.name) or specKey

            local function PrintZoneRow(idx, z)
                local zName = z.zoneName or ("Зона " .. z.zoneId)
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cffffd200#%d|r |cffffffff%s|r |cffaaccff[%s]|r: |cff38bdf8%d очков|r (До Титана: %d, Не погл: %d) |cff33ff99%s|r",
                    idx, zName, z.diffLabel or "", z.totalScore, z.remainToTitanic or 0, z.unabsorbedCount or 0, z.statSummaryStr or ""))
            end

            local function PrintGroup(title, list)
                DEFAULT_CHAT_FRAME:AddMessage("|cffffd200=== " .. title .. " (" .. specName .. ") ===|r")
                if not list or #list == 0 then
                    DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaa(Все предметы поглощены или сложность недоступна)|r")
                else
                    for idx, z in ipairs(list) do
                        PrintZoneRow(idx, z)
                    end
                end
            end

            if subCmd == "25h" or subCmd == "25хм" then
                local top25h = pac:GetTopRecommendedZones(6, specKey, "25h")
                PrintGroup("ТОП 25 ХМ (Рейды)", top25h)
                if pac.ToggleAtlasUI then pac:ToggleAtlasUI("25h") end
            elseif subCmd == "25" or subCmd == "25n" or subCmd == "25об" then
                local top25 = pac:GetTopRecommendedZones(6, specKey, "25")
                PrintGroup("ТОП 25 ОБ (Рейды)", top25)
                if pac.ToggleAtlasUI then pac:ToggleAtlasUI("25") end
            elseif subCmd == "10h" or subCmd == "10хм" then
                local top10h = pac:GetTopRecommendedZones(6, specKey, "10h")
                PrintGroup("ТОП 10 ХМ (Рейды)", top10h)
                if pac.ToggleAtlasUI then pac:ToggleAtlasUI("10h") end
            elseif subCmd == "10" or subCmd == "10n" or subCmd == "10об" then
                local top10 = pac:GetTopRecommendedZones(6, specKey, "10")
                PrintGroup("ТОП 10 ОБ (Рейды)", top10)
                if pac.ToggleAtlasUI then pac:ToggleAtlasUI("10") end
            elseif subCmd == "5h" or subCmd == "5гер" then
                local top5h = pac:GetTopRecommendedZones(6, specKey, "5h")
                PrintGroup("ТОП 5 ГЕР (Подземелья)", top5h)
                if pac.ToggleAtlasUI then pac:ToggleAtlasUI("5h") end
            elseif subCmd == "5" or subCmd == "5об" or subCmd == "данж" or subCmd == "dungeon" then
                local top5 = pac:GetTopRecommendedZones(6, specKey, "5")
                PrintGroup("ТОП 5 ОБ (Подземелья)", top5)
                if pac.ToggleAtlasUI then pac:ToggleAtlasUI("5") end
            else
                local top1List = pac:GetTop1PerDifficulty(specKey)
                DEFAULT_CHAT_FRAME:AddMessage("|cffffd200=== ТОП 1 ПО КАЖДОЙ СЛОЖНОСТИ (" .. specName .. ") ===|r")
                if not top1List or #top1List == 0 then
                    DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaa(Все предметы поглощены до Титанического)|r")
                else
                    for idx, z in ipairs(top1List) do
                        PrintZoneRow(idx, z)
                    end
                end
                DEFAULT_CHAT_FRAME:AddMessage("|cff888888Подсказка: /ttp rec 25h, 25, 10h, 10, 5h, 5 для топа сложности|r")
                if pac.ToggleAtlasUI then pac:ToggleAtlasUI("ALL") end
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "|cffff0000Дополнительный модуль анализа не подключен.|r")
        end
        return
    elseif msg == "auc" or msg == "auction" then
        local ap = rawget(_G, "AttuneParser")
        TalorianTP_DB = TalorianTP_DB or {}
        if ap and ap._hasStandaloneAuctionUI and ap.SetSetting then
            local nw = not ap:GetSetting("showAuctionUI")
            ap:SetSetting("showAuctionUI", nw)
            if type(TalorianTP.SetBlockEnabled) == "function" then
                TalorianTP:SetBlockEnabled("auctionTrade", nw, true)
            end
            TalorianTP_DB.hideAuctionPanel = not nw
            DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Панель ковки аукциона: " .. (nw and "|cff40ff40включена|r" or "|cffff6060скрыта|r"))
        else
            local curOn = (type(TalorianTP.IsBlockEnabled) == "function" and TalorianTP:IsBlockEnabled("auctionTrade")) and (not TalorianTP_DB.hideAuctionPanel)
            local nw = not curOn
            TalorianTP_DB.hideAuctionPanel = not nw
            if type(TalorianTP.SetBlockEnabled) == "function" then
                TalorianTP:SetBlockEnabled("auctionTrade", nw)
            elseif TalorianTP_RefreshAuctionHelper then
                TalorianTP_RefreshAuctionHelper()
            end
            DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Панель ковки аукциона: " .. (nw and "|cff40ff40включена|r" or "|cffff6060скрыта|r"))
        end
        return
    elseif msg == "aucreset" then
        local ap = rawget(_G, "AttuneParser")
        TalorianTP_DB = TalorianTP_DB or {}
        TalorianTP_DB.aucBtnPos = nil
        TalorianTP_DB.hideAuctionPanel = false
        if type(TalorianTP.SetBlockEnabled) == "function" then
            TalorianTP:SetBlockEnabled("auctionTrade", true)
        end
        if ap and ap._hasStandaloneAuctionUI and ap.ResetAuctionPos then
            ap:SetSetting("showAuctionUI", true)
            ap:ResetAuctionPos()
        elseif TalorianTP_ResetAuctionPos then
            TalorianTP_ResetAuctionPos()
        end
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Позиция кнопки и панели аукциона сброшена.")
        return
    elseif msg == "view" then
        local ap = rawget(_G, "AttuneParser")
        if ap and ap.GetInspectTradeCandidates then
            local cands = ap:GetInspectTradeCandidates()
            DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Кандидаты в обмене/осмотре: " .. #cands)
            for i = 1, math.min(8, #cands) do
                local it = cands[i]
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  [%s] %s (%s -> +%d%%, +%s статов)",
                    it.viewCtx or "?", it.name or ("#" .. it.itemId), it.instanceTierName or "?", it.gainNowPct or 0, FormatStatValue(it.gainNowStats or 0)))
            end
        end
        return
    elseif msg == "info" then
        local ap = rawget(_G, "AttuneParser")
        if ap and ap.GetAccountCatalogSummary then
            local cat = ap:GetAccountCatalogSummary()
            local par = ap.GetParagonInfo and ap:GetParagonInfo() or {}
            local sp = ap.GetPlayerSpecInfo and ap:GetPlayerSpecInfo() or {}
            local as = ap.GetAutoSwapSummary and ap:GetAutoSwapSummary() or {}
            DEFAULT_CHAT_FRAME:AddMessage(string.format("%sКаталог: %d/%d (%d%%) | Аккаунт: %d, Герой: %d | Доп. уровень %d (%d/%d) | Спек: %s | Черный список автопродажи: %d",
                ADDON_PREFIX, cat.doneBase or 0, cat.totalBase or 0, cat.pctBase or 0, cat.acc or 0, cat.hero or 0,
                par.level or 0, par.curXP or 0, par.maxXP or 0, sp.specName or "?", as.blacklistCount or 0))
        end
        return
    elseif msg == "show" then
        TalorianTP:OpenUI()
    elseif msg == "reset" then
        TalorianTP_DB = nil
        ReloadUI()
    else
        if mainUI and mainUI:IsShown() then mainUI:Hide() else TalorianTP:OpenUI() end
    end
end


---------------------------------------------------------------------------
-- Модуль анализа поглощенных предметов и ковки
---------------------------------------------------------------------------
local analysisFrame = nil
local activeFilter = 0
local parsedData = {
    total = 0,
    absorbedCount = 0,
    basic = 0,
    epic = 0,
    legendary = 0,
    titanic = 0,
    byLevel = {},
    flatList = {},
}

local itemForgeCache = {}
function TalorianTP_GetItemForgeInfo(itemId)
    return itemForgeCache[tonumber(itemId)]
end
local zoneRequested = {}

-- Таблица сопоставления MapID подземелий/рейдов -> ZoneID AttuneAtlas (для записей AAS, где z=0 и указан mp)
local MAP_TO_ATTUNE_ZONE = {
    [33]  = 209,  -- Крепость Темного Клыка
    [34]  = 717,  -- Тюрьма
    [36]  = 1581, -- Мертвые копи
    [43]  = 718,  -- Пещеры Стенаний
    [47]  = 491,  -- Лабиринты Иглошкурых
    [48]  = 719,  -- Непроглядная Пучина
    [70]  = 1337, -- Ульдаман
    [90]  = 721,  -- Гномреган
    [109] = 1417, -- Затонувший храм
    [129] = 722,  -- Курганы Иглошкурых
    [189] = 796,  -- Монастырь Алого ордена
    [209] = 1176, -- Зул'Фаррак
    [229] = 1583, -- Пик Черной горы
    [230] = 1584, -- Глубины Черной горы
    [249] = 2159, -- Логово Ониксии
    [269] = 2366, -- Черные топи
    [289] = 2057, -- Некроситет
    [309] = 1977, -- Зул'Гуруб
    [329] = 2017, -- Стратхольм
    [349] = 2100, -- Мародон
    [389] = 2437, -- Огненная пропасть
    [409] = 2717, -- Огненные Недра
    [429] = 2557, -- Забытый Город
    [469] = 2677, -- Логово Крыла Тьмы
    [509] = 3429, -- Руины Ан'Киража
    [531] = 3428, -- Храм Ан'Киража
    [532] = 3457, -- Каражан
    [533] = 3456, -- Наксрамас
    [534] = 3606, -- Вершина Хиджала
    [540] = 3714, -- Разрушенные залы
    [542] = 3713, -- Кузня Крови
    [543] = 3562, -- Бастионы Адского Пламени
    [544] = 3836, -- Логово Магтеридона
    [545] = 3715, -- Паровое подземелье
    [546] = 3716, -- Нижетопь
    [547] = 3717, -- Узилище
    [548] = 3607, -- Змеиное святилище
    [550] = 3845, -- Око (Крепость Бурь)
    [552] = 3848, -- Аркатрац
    [553] = 3847, -- Ботаника
    [554] = 3849, -- Механар
    [555] = 3789, -- Темный лабиринт
    [556] = 3791, -- Сетеккские залы
    [557] = 3792, -- Гробницы Маны
    [558] = 3790, -- Аукенайские гробницы
    [560] = 2367, -- Старые предгорья Хилсбрада
    [564] = 3959, -- Черный храм
    [565] = 3923, -- Логово Груула
    [568] = 3805, -- Зул'Аман
    [574] = 206,  -- Крепость Утгард
    [575] = 1196, -- Вершина Утгард
    [576] = 4265, -- Нексус
    [578] = 4228, -- Окулус
    [580] = 4075, -- Плато Солнечного Колодца
    [585] = 4131, -- Терраса Магистров
    [595] = 4100, -- Очищение Стратхольма
    [599] = 4264, -- Чертоги Камня
    [600] = 4196, -- Драк'Тарон
    [601] = 4277, -- Азжол-Неруб
    [602] = 4272, -- Залы Молний
    [603] = 4273, -- Ульдуар
    [604] = 4416, -- Гундрак
    [608] = 4415, -- Аметистовая крепость
    [615] = 4493, -- Обсидиановое святилище
    [616] = 4500, -- Око Вечности
    [619] = 4494, -- Ан'кахет: Старое Королевство
    [624] = 4603, -- Склеп Аркавона
    [631] = 4812, -- Цитадель Ледяной Короны
    [632] = 4809, -- Кузня Душ
    [649] = 4722, -- Испытание крестоносца
    [650] = 4723, -- Испытание Чемпиона
    [658] = 4813, -- Яма Сарона
    [668] = 4820, -- Залы Отражений
    [724] = 4987, -- Рубиновое святилище
}

local function GetItemForgeTier(itemName, itemLink)
    local name = itemName or ""
    if name == "" and itemLink then
        name = itemLink:match("%[(.-)%]") or ""
    end
    -- Сопоставление суффикса названия только в квадратных скобках, чтобы исключить ложные совпадения в описании предметов
    if name:find("%[Титанический%]") or name:find("%[титанический%]") then
        return 4, "Титанический", "00ffff"
    elseif name:find("%[Легендарный%]") or name:find("%[легендарный%]") then
        return 3, "Легендарный", "ff8000"
    elseif name:find("%[Эпический%]") or name:find("%[эпический%]") then
        return 2, "Эпический", "a335ee"
    else
        return 1, "Базовый", "ffffff"
    end
end

-- Парсер строки Ковка: <значок1> <значок2> <значок3>
-- В WoW Prime строка "Ковка:" всегда содержит 3 слота иконок |T...|t:
--   0 ступеней (Базовый):      [серая точка] [серая точка] [серая точка] -> t1 == t2 == t3
--   1 ступень  (Эпический):    [фиолетовый]  [серая точка] [серая точка] -> t1 ~= t2 и t2 == t3
--   2 ступени  (Легендарный):  [фиолетовый]  [оранжевый]   [серая точка] -> t1 ~= t2 ~= t3 и t3 == серая точка
--   3 ступени  (Титанический): [фиолетовый]  [оранжевый]   [бирюзовый]   -> t1 ~= t2 ~= t3 и t3 ~= серая точка
local knownGreyDotTex = nil

local function IsGreyDotTextureName(tl)
    if not tl or tl == "" then return true end
    if knownGreyDotTex and tl == knownGreyDotTex then return true end
    if tl:find("empty") or tl:find("gray") or tl:find("grey") or tl:find("dot") or tl:find("blank") or tl:find("inactive") or tl:find("disabled") or tl:find("off") or tl:find("_0") or tl:find("0%.blp") then
        return true
    end
    return false
end

local function ParseForgeLine(l)
    if not l or not l:find("Ковка") then return nil end
    local content = l:match("Ковка[^:]*:%s*(.*)") or l

    local hasCyan = false
    local hasOrange = false
    local hasPurple = false

    -- 1. Проверка цветовых кодов |cffRRGGBB
    for col in content:gmatch("|cff(%x%x%x%x%x%x)") do
        local c = col:lower()
        local r = tonumber(c:sub(1, 2), 16) or 0
        local g = tonumber(c:sub(3, 4), 16) or 0
        local b = tonumber(c:sub(5, 6), 16) or 0

        if b >= 170 and g >= 140 and r <= 105 then
            hasCyan = true
        elseif r >= 195 and g >= 65 and g <= 195 and b <= 65 then
            hasOrange = true
        elseif r >= 125 and g <= 115 and b >= 165 then
            hasPurple = true
        end
    end

    -- 2. Извлечение всех иконок |T...|t в строке Ковка:
    local texList = {}
    for tex in content:gmatch("|T(.-)|t") do
        local cleanTex = (tex:match("^([^:]+)") or tex):lower()
        table.insert(texList, cleanTex)
        if cleanTex:find("cyan") or cleanTex:find("teal") or cleanTex:find("titan") or cleanTex:find("step3") or cleanTex:find("tier3") or cleanTex:find("azure") then
            hasCyan = true
        elseif cleanTex:find("orange") or cleanTex:find("legend") or cleanTex:find("step2") or cleanTex:find("tier2") or cleanTex:find("amber") then
            hasOrange = true
        elseif cleanTex:find("purple") or cleanTex:find("epic") or cleanTex:find("step1") or cleanTex:find("tier1") or cleanTex:find("void") then
            hasPurple = true
        end
    end

    local colorTier = 1
    if hasCyan then
        colorTier = 4
    elseif hasOrange then
        colorTier = 3
    elseif hasPurple then
        colorTier = 2
    end

    -- Если в строке 3 текстуры (стандартные 3 слота Ковка: в WoW Prime)
    if #texList >= 3 then
        local t1, t2, t3 = texList[1], texList[2], texList[3]
        if t1 == t2 and t2 == t3 then
            -- Все 3 значка одинаковые: если нет явных цветовых кодов 3 разных цветов, это 3 серые точки (Базовый)
            if colorTier >= 4 then
                return 4, "Титанический", "00ffff", nil, false
            elseif colorTier == 3 then
                return 3, "Легендарный", "ff8000", nil, false
            elseif colorTier == 2 then
                return 2, "Эпический", "a335ee", nil, false
            end
            knownGreyDotTex = t3
            return 1, "Базовый", "ffffff", t3, false
        elseif t1 ~= t2 and t2 == t3 then
            -- 1-й значок активен (фиолетовый), а 2-й и 3-й одинаковые (серые точки) -> строго Эпический (1 значок)!
            knownGreyDotTex = t3
            return 2, "Эпический", "a335ee", t3, false
        else
            -- t1 ~= t2 и t2 ~= t3: 1-й и 2-й значки активны. Проверяем 3-й значок (серая точка или бирюзовый шар):
            if knownGreyDotTex then
                if t3 == knownGreyDotTex then
                    return 3, "Легендарный", "ff8000", t3, false
                else
                    return 4, "Титанический", "00ffff", t3, false
                end
            end
            if hasCyan then
                return 4, "Титанический", "00ffff", t3, false
            elseif IsGreyDotTextureName(t3) or hasOrange then
                return 3, "Легендарный", "ff8000", t3, true
            else
                -- До изучения текстуры серой точки (t3) возвращаем безопасный Легендарный (3) с флагом isAmb=true
                return 3, "Легендарный", "ff8000", t3, true
            end
        end
    elseif #texList == 2 then
        local t1, t2 = texList[1], texList[2]
        if t1 == t2 and colorTier == 1 then
            return 1, "Базовый", "ffffff", nil, false
        end
        return 3, "Легендарный", "ff8000", nil, false
    elseif #texList == 1 then
        if IsGreyDotTextureName(texList[1]) and colorTier == 1 then
            return 1, "Базовый", "ffffff", nil, false
        end
        return 2, "Эпический", "a335ee", nil, false
    end

    if colorTier == 4 then
        return 4, "Титанический", "00ffff", nil, false
    elseif colorTier == 3 then
        return 3, "Легендарный", "ff8000", nil, false
    elseif colorTier == 2 then
        return 2, "Эпический", "a335ee", nil, false
    end

    return 1, "Базовый", "ffffff", nil, false
end

-- Опрос глобального API Custom_Attune (если доступен в клиенте)
local function ExtractItemSuffix(itemLink)
    if type(itemLink) ~= "string" then return nil end
    local sfx = itemLink:match("item:%d+:%-?%d*:%-?%d*:%-?%d*:%-?%d*:%-?%d*:(%-?%d+)")
    return sfx and tonumber(sfx) or nil
end

local function QueryCustomAttuneGlobalTier(itemId, itemLink)
    if not itemId then return 1, false, 0 end
    local tierNum = 1
    local isAbs = false
    local pct = 0
    local sfx = ExtractItemSuffix(itemLink)

    local fnAbsTier = rawget(_G, "CustomAttuneAbsorbedTier")
    if type(fnAbsTier) == "function" then
        local ok, at = pcall(fnAbsTier, itemId, sfx or 0)
        if ok and type(at) == "number" and at >= 0 then
            isAbs = true
            pct = 100
            if (at + 1) > tierNum then
                tierNum = math.min(4, at + 1)
            end
        end
    end

    local fnProg = rawget(_G, "CustomAttuneProgress")
    local hasProgResult = false
    if type(fnProg) == "function" then
        local ok, doneTier, ipTier, ipXp, ipNeed = pcall(fnProg, itemId, sfx)
        if ok and type(doneTier) == "number" then
            hasProgResult = true
            if doneTier >= 0 then
                isAbs = true
                pct = 100
                tierNum = math.min(4, doneTier + 1)
            elseif type(ipTier) == "number" and type(ipNeed) == "number" and ipNeed > 0 then
                local calcPct = math.floor(((tonumber(ipXp) or 0) / ipNeed) * 100 + 0.5)
                pct = math.max(0, math.min(99, calcPct))
            end
        end
    end

    if not isAbs then
        local fnTier = rawget(_G, "CustomAttuneTier")
        if type(fnTier) == "function" then
            local ok, tPct = pcall(fnTier, itemId, 0, sfx)
            if ok and type(tPct) == "number" and tPct > pct then
                pct = math.min(100, math.floor(tPct + 0.5))
                if pct >= 100 then isAbs = true end
            end
        end
    end

    if not isAbs and (not hasProgResult or sfx == nil) then
        local gSet = rawget(_G, "CustomAttuneAbsorbedSet")
        if type(gSet) == "table" and gSet[itemId] then
            isAbs = true
            pct = 100
        end
    end

    return tierNum, isAbs, pct
end

-- Сканирование подсказки GameTooltip для точного считывания строк ковки, поглощения, ilvl и флага Героический
local function ReadGameTooltipData(setterFunc, fallbackItemId, fallbackLink)
    if not GameTooltip then return nil end
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    local ok = pcall(setterFunc)
    if not ok then
        GameTooltip:Hide()
        return nil
    end

    local numLines = GameTooltip:NumLines() or 0
    if numLines == 0 then
        GameTooltip:Hide()
        return nil
    end

    local left1Obj = _G["GameTooltipTextLeft1"]
    local right1Obj = _G["GameTooltipTextRight1"]
    local title = left1Obj and left1Obj:GetText() or ""
    local headerRight = right1Obj and right1Obj:GetText() or ""

    local fullHeader = title .. " " .. headerRight
    local headerTier = GetItemForgeTier(fullHeader)
    local isAbs = false
    local pct = 0
    local hasAbsorption = false
    local reqLvl = 80
    local tooltipIlvl = 0
    local tooltipHeroic = false
    local hasForgeLine = false
    local forgeLineTier = 1
    local forgeTex3 = nil
    local forgeAmbiguous = false

    for i = 1, numLines do
        local lineLeftObj = _G["GameTooltipTextLeft" .. i]
        local lineRightObj = _G["GameTooltipTextRight" .. i]
        local lineLeft = lineLeftObj and lineLeftObj:GetText() or ""
        local lineRight = lineRightObj and lineRightObj:GetText() or ""
        local l = lineLeft .. " " .. lineRight

        if l ~= "" then
            if i <= 4 and (lineLeft:find("Героический") or lineLeft:find("Heroic")) then
                tooltipHeroic = true
            end

            local ilvlMatch = l:match("Уровень предмета:%s*(%d+)") or l:match("Item Level%s*(%d+)")
            if ilvlMatch then
                tooltipIlvl = tonumber(ilvlMatch) or tooltipIlvl
            end

            if l:find("Ковка") then
                hasForgeLine = true
                local fTier, _, _, t3, isAmb = ParseForgeLine(l)
                if fTier then
                    forgeLineTier = fTier
                    forgeTex3 = t3
                    forgeAmbiguous = isAmb
                end
            end

            local progPct = l:match("Поглощ[ее][нн][^:]*:%s*(%d+)%%") or l:match("Поглощено%s*%((%d+)%%%)") or l:match("Поглощение:%s*(%d+)%%")
            if progPct then
                pct = math.max(pct, tonumber(progPct) or 0)
                hasAbsorption = true
                if pct >= 100 then isAbs = true end
            elseif l:find("Поглощен") and not l:find("Поглощение") and not l:find("Не поглощен") and not l:find("не поглощен") and not l:find("Невозможно") then
                local anyNum = l:match("(%d+)%%")
                if not anyNum or (tonumber(anyNum) or 0) >= 100 then
                    isAbs = true
                    pct = 100
                    hasAbsorption = true
                end
            end

            local lvl = l:match("Требуется уровень:%s*(%d+)")
            if lvl then reqLvl = tonumber(lvl) or reqLvl end
        end
    end

    GameTooltip:Hide()

    local apiTier, apiAbs, apiPct = QueryCustomAttuneGlobalTier(fallbackItemId, fallbackLink)
    if apiAbs then
        isAbs = true
        pct = 100
        hasAbsorption = true
    elseif apiPct > pct then
        pct = apiPct
        hasAbsorption = true
    end

    -- Приоритет значков строки "Ковка:":
    -- Если строка "Ковка:" есть на предмете, то поглощенная ступень определяется СТРОГО по значкам "Ковка:" (и API).
    -- Суффикс в названии ([Легендарный]/[Титанический]) учитывается для поглощенной ступени только если предмет
    -- поглощен на 100% или если строка "Ковка:" отсутствует, но предмет не привязан к 0% поглощения.
    local absorbedTier = math.max(forgeLineTier or 1, apiTier or 1)
    if isAbs and headerTier and headerTier > absorbedTier and not hasForgeLine then
        absorbedTier = headerTier
    end

    -- Для отображения самого предмета в списке (если он лежит в сумке с суффиксом [Титанический] и 2 значками в Ковка:)
    local displayTier = absorbedTier
    if headerTier and headerTier > displayTier and (hasForgeLine or hasAbsorption or isAbs) then
        displayTier = headerTier
    end

    local tierNum, tierName, tierCol
    if displayTier == 4 then
        tierNum, tierName, tierCol = 4, "Титанический", "00ffff"
    elseif displayTier == 3 then
        tierNum, tierName, tierCol = 3, "Легендарный", "ff8000"
    elseif displayTier == 2 then
        tierNum, tierName, tierCol = 2, "Эпический", "a335ee"
    else
        tierNum, tierName, tierCol = 1, "Базовый", "ffffff"
    end

    if title == "" and headerRight == "" and not hasForgeLine and not isAbs and displayTier == 1 then
        return nil
    end

    return title, tierNum, tierName, tierCol, isAbs, pct, hasAbsorption, reqLvl, (hasForgeLine or displayTier > 1), absorbedTier, tooltipIlvl, tooltipHeroic, forgeTex3, forgeAmbiguous
end

local analysisScannedOnce = false
local serverZoneItemMap = {}
local bgForgeScanQueue = {}
local bgForgeScanSeen = {}

local function ModeMaskToDiffId(md)
    md = tonumber(md) or 0
    if md <= 0 then return 1 end
    if math.floor(md / 8) % 2 == 1 then return 4 end
    if math.floor(md / 4) % 2 == 1 then return 3 end
    if math.floor(md / 2) % 2 == 1 then return 2 end
    return 1
end

local function UpdateItemForgeCache(itemId, tierNum, isAbs, pct, hasForgeLine, absorbedTier, ilvl, isHeroic, tex3, isAmb)
    if not itemId then return end
    local prev = itemForgeCache[itemId]
    local prevTier = prev and prev.tier or 1
    local prevAbsTier = prev and prev.absTier or 1
    if prev and prev.isAmb and not isAmb then
        prevTier = 1
        prevAbsTier = 1
    end
    local newTier = math.max(tierNum or 1, prevTier)
    local newAbsTier = math.max(absorbedTier or tierNum or 1, prevAbsTier)
    local newAbs = (isAbs and true) or (prev and prev.isAbs) or false
    local newPct = math.max(pct or 0, prev and prev.pct or 0)
    local newHf = (hasForgeLine and true) or (prev and prev.hasForgeLine) or false
    local newIlvl = (ilvl and ilvl > 0 and ilvl) or (prev and prev.ilvl) or 0
    local newHeroic = (isHeroic and true) or (prev and prev.isHeroic) or false
    itemForgeCache[itemId] = {
        tier = newTier,
        absTier = newAbsTier,
        isAbs = newAbs,
        pct = newPct,
        hasForgeLine = newHf,
        ilvl = newIlvl,
        isHeroic = newHeroic,
        tex3 = tex3 or (prev and prev.tex3),
        isAmb = isAmb,
    }
    local pac = rawget(_G, "PrimeAttuneCore")
    if pac and (newAbs or newAbsTier > 1) then
        if pac.forgeTierCache then pac.forgeTierCache[itemId] = newAbsTier end
        if pac.absorbedCache and newAbs then pac.absorbedCache[itemId] = true end
    end
    return itemForgeCache[itemId]
end

-- Определение зоны, сложности и подписи предмета через отдельную базу TalorianLootDB (+ фоллбэк на AAS)
local function ResolveItemZoneAndDiff(itemId, ilvl, isHeroic)
    if not itemId then return nil, nil, nil end
    local db = rawget(_G, "TalorianLootDB")
    if db and type(db.ResolveItem) == "function" then
        local zId, dId, srcLabel = db:ResolveItem(itemId, ilvl, isHeroic, serverZoneItemMap)
        if zId then
            return zId, dId or 1, srcLabel
        end
    end

    -- Фоллбэк на серверный кэш и _G.AAS (если TalorianLootDB не загружена или предмет из открытого мира)
    if serverZoneItemMap[itemId] then
        for zid, dId in pairs(serverZoneItemMap[itemId]) do
            return zid, dId or 1, nil
        end
    end

    local aas = rawget(_G, "AAS")
    local topMap = rawget(_G, "AttuneAtlasTop")
    if aas and type(aas) == "table" then
        local raw = aas[itemId]
        if type(raw) == "string" and raw ~= "" then
            local rec = raw:match("^([^;]+)") or raw
            local st, smp, z, mp = rec:match("^(%d+):(%d+):(%d+):(%d+)")
            if z then
                local zn = tonumber(z) or 0
                local mpn = tonumber(mp) or 0
                local tz = (zn > 0 and ((topMap and topMap[zn]) or zn)) or (mpn > 0 and MAP_TO_ATTUNE_ZONE[mpn]) or nil
                if tz and tz > 0 then
                    local dId = (db and db.DetermineDifficulty and db:DetermineDifficulty(tz, itemId, ilvl, isHeroic)) or 1
                    local lbl = (db and db.FormatSourceLabel and db:FormatSourceLabel(tz, dId)) or nil
                    return tz, dId, lbl
                end
            end
        end
    end

    return nil, nil, nil
end

-- Пересчет статистики ковки по зонам и сложностям НАПРЯМУЮ из результатов Анализа ковки (0 мс при наведении!)
local function RebuildZoneForgeFromAnalysis()
    parsedData.byZone = {}
    local pac = rawget(_G, "PrimeAttuneCore")
    if pac and knownGreyDotTex and not pac.knownGreyDotTex then
        pac.knownGreyDotTex = knownGreyDotTex
    end

    for itemId, info in pairs(itemForgeCache) do
        -- Если во время скана стала известна текстура серой точки, уточняем неоднозначные 2/3-значковые предметы
        if info.isAmb and info.tex3 and knownGreyDotTex then
            info.isAmb = false
            if info.tex3 == knownGreyDotTex then
                info.absTier = 3
                if info.tier == 4 then info.tier = 3 end
            else
                info.absTier = 4
                info.tier = 4
            end
            if pac and pac.forgeTierCache and (info.isAbs or info.absTier > 1) then
                pac.forgeTierCache[itemId] = info.absTier
            end
        end

        local absTier = info.absTier or info.tier or 1
        if info.isAbs or absTier > 1 then
            local tz, dId = ResolveItemZoneAndDiff(itemId, info.ilvl, info.isHeroic)
            if tz then
                local zBucket = parsedData.byZone[tz]
                if not zBucket then
                    zBucket = { titanic = 0, legendary = 0, epic = 0, basic = 0, byDiff = {} }
                    parsedData.byZone[tz] = zBucket
                end
                if absTier == 4 then
                    zBucket.titanic = zBucket.titanic + 1
                elseif absTier == 3 then
                    zBucket.legendary = zBucket.legendary + 1
                elseif absTier == 2 then
                    zBucket.epic = zBucket.epic + 1
                else
                    zBucket.basic = zBucket.basic + 1
                end

                if dId and dId >= 1 and dId <= 4 then
                    local db = zBucket.byDiff[dId]
                    if not db then
                        db = { titanic = 0, legendary = 0, epic = 0, basic = 0 }
                        zBucket.byDiff[dId] = db
                    end
                    if absTier == 4 then
                        db.titanic = db.titanic + 1
                    elseif absTier == 3 then
                        db.legendary = db.legendary + 1
                    elseif absTier == 2 then
                        db.epic = db.epic + 1
                    else
                        db.basic = db.basic + 1
                    end
                end
            end
        end
    end
end

-- Обработка пакета ASMSG_ATC_ZONE от сервера
ParseServerZoneItems = function(payloadMsg)
    if not payloadMsg or payloadMsg == "" then return end
    local zoneIdStr, clearStr, listStr = payloadMsg:match("^([^\t]*)\t([^\t]*)\t(.*)$")
    local zid = tonumber(zoneIdStr)
    if not zid or not listStr or listStr == "" then return end

    local topMap = rawget(_G, "AttuneAtlasTop")
    local tz = (topMap and topMap[zid]) or zid

    for rec in listStr:gmatch("([^;]+)") do
        local e, q, sl, st, ab, md, pc = rec:match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)")
        if not e then
            local e2, sfx, q2, sl2, st2, md2, pc2 = rec:match("^(%d+):([-%d]+):(%d+):(%d+):(%d+):(%d+):(%d+)")
            if e2 then
                e, md, pc = e2, md2, pc2
                ab = (tonumber(pc2) or 0) >= 100 and "1" or "0"
            end
        end
        local itemId = tonumber(e)
        if itemId and itemId > 0 then
            local dId = ModeMaskToDiffId(md)
            serverZoneItemMap[itemId] = serverZoneItemMap[itemId] or {}
            serverZoneItemMap[itemId][tz] = dId

            local isItemAbs = (tonumber(ab) == 1) or ((tonumber(pc) or 0) >= 100)
            if isItemAbs then
                local cached = itemForgeCache[itemId]
                if not cached then
                    local apiTier = QueryCustomAttuneGlobalTier(itemId, "item:" .. itemId)
                    UpdateItemForgeCache(itemId, apiTier, true, 100, apiTier > 1, apiTier)
                    if not bgForgeScanSeen[itemId] then
                        bgForgeScanSeen[itemId] = true
                        table.insert(bgForgeScanQueue, itemId)
                    end
                elseif not cached.isAbs then
                    cached.isAbs = true
                    cached.pct = 100
                end
            end
        end
    end

    RebuildZoneForgeFromAnalysis()
    if hoveredCardBtn and hoveredCardBtn:IsVisible() then
        ShowDestTooltip(hoveredCardBtn)
    end
end

ProcessBgForgeScanQueue = function()
    -- Disabled: background tooltip warming is handled safely outside instances by AttuneParser
end

-- Мгновенное чтение из кэша анализа ковки (0 мс)
GetZoneForgeStats = function(zoneId, totalConsumed)
    if not zoneId then return nil end

    if not analysisScannedOnce then
        TalorianTP_ScanAbsorbedItems()
    elseif not parsedData.byZone or not next(parsedData.byZone) then
        RebuildZoneForgeFromAnalysis()
    end

    local zBucket = parsedData.byZone and parsedData.byZone[zoneId]
    local titanic = zBucket and zBucket.titanic or 0
    local legendary = zBucket and zBucket.legendary or 0
    local epic = zBucket and zBucket.epic or 0
    local basic = zBucket and zBucket.basic or 0

    local scannedTotal = titanic + legendary + epic + basic
    local targetConsumed = tonumber(totalConsumed) or 0
    if targetConsumed > scannedTotal then
        basic = basic + (targetConsumed - scannedTotal)
    elseif targetConsumed > 0 and scannedTotal > targetConsumed then
        local excess = scannedTotal - targetConsumed
        basic = basic - math.min(basic, excess)
    end

    return {
        titanic = titanic,
        legendary = legendary,
        epic = epic,
        basic = basic,
        total = titanic + legendary + epic + basic,
        baseConsumed = targetConsumed,
        byDiff = zBucket and zBucket.byDiff or nil,
    }
end

-- Быстрый неблокирующий сбор данных поглощенных и кованых предметов через AttuneParser + API сервера
function TalorianTP_ScanAbsorbedItems()
    analysisScannedOnce = true
    itemForgeCache = {}
    parsedData = {
        total = 0,
        absorbedCount = 0,
        basic = 0,
        epic = 0,
        legendary = 0,
        titanic = 0,
        byLevel = {},
        byZone = {},
        flatList = {},
    }

    local ap = rawget(_G, "AttuneParser")
    local recordsByItem = {}
    local tierPct = (ap and ap.TIER_PCT) or { [0] = 20, [1] = 30, [2] = 50, [3] = 90 }

    local function uiTierFromServer(doneTier)
        if doneTier == 3 then return 4, "Титанический", "00ffff", tierPct[3] or 90, true
        elseif doneTier == 2 then return 3, "Легендарный", "ff8000", tierPct[2] or 50, false
        elseif doneTier == 1 then return 2, "Эпический", "a335ee", tierPct[1] or 30, false
        else return 1, "Без ковки", "ffffff", tierPct[0] or 20, false end
    end

    local function upsertRecord(itemId, link, inBagOrGear, srvInstTier)
        if not itemId or itemId <= 0 then return end
        local sfx = (link and ExtractItemSuffix and ExtractItemSuffix(link)) or 0
        local apiTier, apiAbs, apiPct = QueryCustomAttuneGlobalTier(itemId, link or ("item:" .. itemId))

        local recMeta = (ap and ap.ParseItemRecord) and ap.ParseItemRecord(itemId) or nil
        local stSrv = (ap and ap.GetItemServerStatus) and ap:GetItemServerStatus(itemId, sfx) or nil
        local doneTier = (stSrv and stSrv.doneTier) or (apiAbs and math.max(0, (apiTier or 1) - 1)) or -1
        local heldTier = srvInstTier or (ap and ap.forgeByEntry and ap.forgeByEntry[itemId]) or nil

        if not inBagOrGear and doneTier < 0 and not apiAbs then
            return
        end

        local iName, _, iQual, iIlvl, iReqLvl, _, _, _, iEquip, iTex = GetItemInfo(itemId)
        local equipLoc = (recMeta and recMeta.inv and recMeta.inv ~= "") or (iEquip and iEquip ~= "")
        if not equipLoc and not apiAbs and doneTier < 0 then
            return
        end
        if recMeta and recMeta.noAttune then return end

        if inBagOrGear and doneTier < 0 and link then
            local hdrTier = select(1, GetItemForgeTier(iName, link))
            if (hdrTier or 1) <= 1 and (tonumber(apiPct) or 0) <= 0 and not apiAbs and (not heldTier or heldTier <= 0) then
                return
            end
        end

        local effDone = math.max(doneTier, heldTier or -1)
        local uiTier, tierName, tierCol, effPct, isDoneMax = uiTierFromServer(math.max(0, effDone))
        if doneTier < 0 then
            if heldTier and heldTier > 0 then
                uiTier, tierName, tierCol = uiTierFromServer(heldTier)
            else
                uiTier, tierName, tierCol = 1, "Без ковки", "ffffff"
            end
            effPct = apiPct or 0
            isDoneMax = false
        end

        local ilvl = (recMeta and recMeta.ilvl and recMeta.ilvl > 0 and recMeta.ilvl) or iIlvl or 0
        local reqLvl = (recMeta and recMeta.req and recMeta.req > 0 and recMeta.req) or iReqLvl or 80
        local srcLabel = nil
        if recMeta and recMeta.primaryZone and recMeta.primaryZone > 0 and ap and ap.Data and ap.Data.Zones and ap.Data.Zones[recMeta.primaryZone] then
            srcLabel = ap.Data.Zones[recMeta.primaryZone].name
        elseif ResolveItemZoneAndDiff then
            local _, _, lbl = ResolveItemZoneAndDiff(itemId, ilvl, false)
            srcLabel = lbl
        end

        local displayName = iName or (recMeta and recMeta.name ~= "" and recMeta.name) or ("Предмет #" .. itemId)
        UpdateItemForgeCache(itemId, uiTier, isDoneMax, effPct, uiTier > 1, uiTier, ilvl, false, nil, false)

        local prev = recordsByItem[itemId]
        if prev then
            if uiTier > prev.tier then
                prev.tier, prev.tierName, prev.tierCol = uiTier, tierName, tierCol
                prev.absTier = uiTier
            end
            if effPct > (prev.pct or 0) then prev.pct = effPct end
            if isDoneMax then prev.isAbsorbed = true end
            if link and link:find("item:%d+:") then prev.link = link end
            if iName and (prev.name:find("^Предмет #") or prev.name:find("^#")) then prev.name = iName end
            if iTex then prev.icon = iTex end
            return
        end

        recordsByItem[itemId] = {
            id = itemId,
            name = displayName,
            link = link or ("item:" .. itemId),
            tier = uiTier,
            absTier = uiTier,
            tierName = tierName,
            tierCol = tierCol,
            level = reqLvl,
            quality = (recMeta and recMeta.quality and recMeta.quality > 0 and recMeta.quality) or iQual or 4,
            icon = iTex or "Interface\\Icons\\INV_Misc_QuestionMark",
            isAbsorbed = isDoneMax,
            pct = effPct,
            hasAbsorption = (doneTier >= 0) or (effPct > 0),
            sourceLabel = srcLabel,
        }
    end

    -- 1. Экипировка и открытые сумки (с тирами ковки из серверного ASMSG_FORGE_MAP)
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local t = ap and ap.forgeEquip and ap.forgeEquip[slot] or nil
            upsertRecord(tonumber(link:match("item:(%d+)")), link, true, t)
        end
    end
    for bag = 0, 4 do
        local num = GetContainerNumSlots(bag) or 0
        for slot = 1, num do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local t = ap and ap.forgeBag and ap.forgeBag[bag] and ap.forgeBag[bag][slot] or nil
                upsertRecord(tonumber(link:match("item:(%d+)")), link, true, t)
            end
        end
    end

    -- 2. Поглощенные предметы аккаунта (без синхронных вызовов GameTooltip:SetHyperlink)
    local g = rawget(_G, "CustomAttuneAbsorbedSet")
    if g and type(g) == "table" then
        for entry, isAbsVal in pairs(g) do
            if isAbsVal and type(entry) == "number" and entry > 0 then
                upsertRecord(entry, "item:" .. entry, false)
            end
        end
    end

    for _, rec in pairs(recordsByItem) do
        parsedData.total = parsedData.total + 1
        if rec.tier == 4 then
            parsedData.titanic = parsedData.titanic + 1
        elseif rec.tier == 3 then
            parsedData.legendary = parsedData.legendary + 1
        elseif rec.tier == 2 then
            parsedData.epic = parsedData.epic + 1
        else
            parsedData.basic = parsedData.basic + 1
        end
        if rec.isAbsorbed then
            parsedData.absorbedCount = parsedData.absorbedCount + 1
        end
        local lvl = rec.level or 80
        parsedData.byLevel[lvl] = parsedData.byLevel[lvl] or {}
        table.insert(parsedData.byLevel[lvl], rec)
    end

    local lvls = {}
    for lvl in pairs(parsedData.byLevel) do
        table.insert(lvls, lvl)
    end
    table.sort(lvls, function(a, b) return a > b end)

    parsedData.flatList = {}
    for _, lvl in ipairs(lvls) do
        local items = parsedData.byLevel[lvl]
        table.sort(items, function(a, b)
            if a.tier ~= b.tier then return a.tier > b.tier end
            if a.pct ~= b.pct then return a.pct > b.pct end
            return (a.name or "") < (b.name or "")
        end)
        table.insert(parsedData.flatList, { isHeader = true, level = lvl, count = #items })
        for _, it in ipairs(items) do
            table.insert(parsedData.flatList, it)
        end
    end

    if ap and ap.GetOwnedUpgradeCandidates then
        local ready = ap:GetOwnedUpgradeCandidates()
        parsedData.readyCount = #ready
        local rSum = 0
        for _, it in ipairs(ready) do rSum = rSum + (it.gainNowStats or 0) end
        parsedData.readyStats = rSum
    end

    return parsedData
end

function TalorianTP_PrintAnalysisToChat()
    local d = parsedData
    if d.total == 0 then
        d = TalorianTP_ScanAbsorbedItems()
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[TalorianTP]|r Сводка поглощения и ковки:")
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  Всего найдено: |cff40ff40%d|r шт. (Завершено на Титаническом 90%%: |cffffd200%d|r)", d.total, d.absorbedCount))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cff00ffffТитанических:|r %d | |cffff8000Легендарных:|r %d | |cffa335eeЭпических:|r %d | |cffffffffОбычных:|r %d",
        d.titanic, d.legendary, d.epic, d.basic))
end

do
    local EXP_KIND_BTNS = {
        { id = "all",     label = "Все инсты",  w = 72 },
        { id = "raid",    label = "Рейды (23)", w = 76 },
        { id = "dungeon", label = "Данжи (52)", w = 76 },
    }
    local EXP_ERA_BTNS = {
        { id = "all",     label = "Все эры", w = 62 },
        { id = "WotLK",   label = "WotLK",   w = 50 },
        { id = "TBC",     label = "TBC",     w = 42 },
        { id = "Classic", label = "Классика", w = 66 },
    }
    local EXP_DIFF_BTNS = {
        { id = 0, label = "Все реж.", w = 62 },
        { id = 1, label = "10 об",    w = 48 },
        { id = 2, label = "25 об",    w = 48 },
        { id = 3, label = "10 гер",   w = 52 },
        { id = 4, label = "25 гер",   w = 52 },
    }
    local EXP_STATUS_BTNS = {
        { id = "need",  label = "Нужные",    w = 64 },
        { id = "new",   label = "Новые",     w = 60 },
        { id = "forge", label = "Ковка",     w = 58 },
        { id = "owned", label = "В наличии", w = 78 },
        { id = "done",  label = "Готово 90%", w = 84 },
        { id = "all",   label = "Все",       w = 46 },
    }
    local DIFF_BITS = { [1] = 1, [2] = 2, [3] = 4, [4] = 8 }
    local TIER_UI = {
        [3] = { name = "Титанический", short = "Тит. 90%",    col = "00ffff", hex = "|cff00ffff" },
        [2] = { name = "Легендарный", short = "Легенд. 50%", col = "ff8000", hex = "|cffff8000" },
        [1] = { name = "Эпический",   short = "Эпик 30%",    col = "a335ee", hex = "|cffa335ee" },
        [0] = { name = "Обычный",     short = "Обыч. 20%",   col = "ffd200", hex = "|cffffd200" },
    }
    local QUAL_HEX = {
        [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00",
        [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000", [6] = "|cffe6cc80",
    }
    local EXP_LABELS = { WotLK = "WotLK", TBC = "Burning Crusade", Classic = "Классика" }
    local ZONE_ROW_H = 32
    local ITEM_ROW_H = 34
    local VIS_ZONES = 11
    local VIS_ITEMS = 9

    local expState = {
        kind = "all",
        era = "all",
        diff = 0,
        status = "need",
        query = "",
        selZoneName = nil,
        zones = {},
        items = {},
        selMeta = nil,
        ownedMap = {},
    }

    local function GetAllExplorerZones()
        local out = {}
        local pools = { RAID_DESTS, DUNGEONS_WOTLK, DUNGEONS_TBC, DUNGEONS_VANILLA }
        for _, pool in ipairs(pools) do
            for _, d in ipairs(pool) do
                table.insert(out, d)
            end
        end
        return out
    end

    local function BuildOwnedMap()
        local owned = {}
        local function mark(id, label)
            if id and id > 0 and not owned[id] then owned[id] = label end
        end
        if type(GetInventoryItemLink) == "function" then
            for slot = 1, 19 do
                local link = GetInventoryItemLink("player", slot)
                if link then mark(tonumber(link:match("item:(%d+)")), "Надето") end
            end
        end
        if type(GetContainerNumSlots) == "function" and type(GetContainerItemLink) == "function" then
            for bag = 0, 4 do
                local n = GetContainerNumSlots(bag) or 0
                for slot = 1, n do
                    local link = GetContainerItemLink(bag, slot)
                    if link then mark(tonumber(link:match("item:(%d+)")), "В сумке") end
                end
            end
        end
        local ap = rawget(_G, "AttuneParser")
        local ib = (ap and ap.serverSync and ap.serverSync.ib and ap.serverSync.ib.items)
            or (rawget(_G, "PRIME_ItemBank") and PRIME_ItemBank.items)
        if type(ib) == "table" then
            for _, row in pairs(ib) do
                if type(row) == "table" and tonumber(row.entry) then
                    mark(tonumber(row.entry), "Банк вещей")
                end
            end
        end
        local rb = (ap and ap.serverSync and ap.serverSync.rb and ap.serverSync.rb.contents)
            or (rawget(_G, "ResourceBank") and ResourceBank.contents)
        if type(rb) == "table" then
            for id, cnt in pairs(rb) do
                if (tonumber(cnt) or 0) > 0 then mark(tonumber(id), "Сборщик") end
            end
        end
        if ap and type(ap.GetOwnedUpgradeCandidates) == "function" then
            local ok, cands = pcall(ap.GetOwnedUpgradeCandidates, ap, nil, true)
            if ok and type(cands) == "table" then
                local wLbl = { equip = "Надето", bag = "В сумке", itembank = "Банк вещей", resourcebank = "Сборщик", bank = "Банк", guild = "Гильдбанк", petloot = "Спутник" }
                for _, it in ipairs(cands) do
                    if it.itemId then mark(it.itemId, wLbl[it.where or "bag"] or "В наличии") end
                end
            end
        end
        return owned
    end

    local function ExtractItemSourceText(ap, eid)
        if not (ap and type(ap.GetItemSources) == "function") then return nil end
        local ok, src = pcall(ap.GetItemSources, ap, eid)
        if not ok or type(src) ~= "table" or type(src.list) ~= "table" or #src.list == 0 then
            return nil
        end
        local first = src.list[1]
        local nm = first.name and first.name ~= "" and first.name or nil
        if first.st == 4 then
            return "Квест: " .. (nm or ("#" .. tostring(first.smp or "")))
        elseif nm then
            local ch = (first.chance and first.chance > 0 and ap.FormatChance) and (" (" .. ap.FormatChance(first.chance) .. ")") or ""
            return nm .. ch
        end
        return "Добыча / сундуки инста"
    end

    local function MatchesZoneDiff(dMask, effDiffId, maxDiffs, isSingleDiff)
        if isSingleDiff or not effDiffId then return true end
        if maxDiffs < effDiffId then return false end
        if not dMask or dMask <= 0 then return true end
        local needBit = DIFF_BITS[effDiffId]
        if not needBit then return true end
        if bit and bit.band then
            return bit.band(dMask, needBit) ~= 0
        end
        return math.floor(dMask / needBit) % 2 == 1
    end

    local function CollectZoneItems(zoneDesc)
        local ap = rawget(_G, "AttuneParser")
        local items = {}
        local owned = expState.ownedMap or {}
        local effDiff = (expState.diff > 0) and expState.diff or nil
        local stFilter = expState.status
        local rawQ = (expState.query ~= "") and TalorianTP_Norm(expState.query) or nil
        local zoneMatchedQuery = rawQ and zoneDesc and TalorianTP_Norm(zoneDesc.name .. " " .. (zoneDesc.short or "")):find(rawQ, 1, true)
        local qNorm = (rawQ and not zoneMatchedQuery) and rawQ or nil

        if not (ap and ap.Data and ap.Data.ZoneItems and zoneDesc and zoneDesc.attune) then
            local targetZid = zoneDesc and zoneDesc.attune
            local seen = {}
            local ldbItems = _G.TalorianLootDB and _G.TalorianLootDB.InstanceItems
            if ldbItems and targetZid then
                for eid, zid in pairs(ldbItems) do
                    if zid == targetZid then seen[eid] = true end
                end
            end
            for eid, info in pairs(itemForgeCache) do
                if info and targetZid and _G.TalorianLootDB and _G.TalorianLootDB.InstanceItems and _G.TalorianLootDB.InstanceItems[eid] == targetZid then
                    seen[eid] = true
                end
            end
            for eid in pairs(seen) do
                local info = itemForgeCache[eid]
                local gNm, gLk, gQ, gIl, _, _, _, _, _, gIc = GetItemInfo(eid)
                local nm = gNm or ("Предмет #" .. eid)
                local apiTier, apiAbs, apiPct = QueryCustomAttuneGlobalTier(eid, "item:" .. eid)
                local effTier = math.max(info and info.tier or 1, apiTier or 1)
                local isAbs = (info and info.isAbs) or (apiAbs and effTier >= 4)
                local stCat = isAbs and "done" or ((effTier > 1 or apiAbs) and "forge" or "new")
                local keep = (stFilter == "all")
                    or (stFilter == "need" and stCat ~= "done")
                    or (stFilter == "owned" and owned[eid] ~= nil)
                    or (stCat == stFilter)
                if keep and (not qNorm or TalorianTP_Norm(nm):find(qNorm, 1, true)) then
                    table.insert(items, {
                        id = eid, name = nm, ilvl = (info and info.ilvl) or gIl or 0, quality = gQ or 4,
                        icon = gIc or "Interface\\Icons\\INV_Misc_QuestionMark",
                        link = gLk or ("item:" .. eid .. ":0:0:0:0:0:0:0:80"), cat = stCat,
                        doneTier = isAbs and 3 or math.max(0, effTier - 1),
                        curPct = (info and info.pct) or apiPct or (isAbs and 90 or 0),
                        remainStats = 0, ownedLabel = owned[eid], diffMask = 0,
                    })
                end
            end
            table.sort(items, function(a, b)
                if a.cat ~= b.cat then return (a.cat == "new") or (a.cat == "forge" and b.cat == "done") end
                if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
                return (a.name or "") < (b.name or "")
            end)
            return items, nil
        end

        local topId = (ap.Data.TopMap and ap.Data.TopMap[zoneDesc.attune]) or zoneDesc.attune
        local maxDiffs = ap.GetZoneMaxDiffs and ap:GetZoneMaxDiffs(topId, zoneDesc.isRaid, zoneDesc.exp) or 1
        local isSingleDiff = (maxDiffs == 1)
        local modeAvailable = isSingleDiff or (not effDiff) or (effDiff <= maxDiffs)
        local za = ap:GetZoneAnalysis(zoneDesc.attune, {
            diffId = effDiff, isRaid = zoneDesc.isRaid, exp = zoneDesc.exp, scope = "hero",
        })
        if not modeAvailable then return items, za end

        local exclHeavy = (ap.GetSetting == nil) or (ap:GetSetting("excludeHeavyQuests") ~= false)
        local srvItems = (ap.serverZoneItems and ap.serverZoneItems[topId]) or nil
        local poolSet = {}
        local staticList = ap.Data.ZoneItems[topId]
        if staticList then
            for _, eid in ipairs(staticList) do poolSet[eid] = true end
        end
        if srvItems then
            for eid in pairs(srvItems) do poolSet[eid] = true end
        end

        for eid in pairs(poolSet) do
            local srv = srvItems and srvItems[eid]
            local sfx = (srv and srv.suffix) or 0
            local rec = ap.ParseItemRecord and ap.ParseItemRecord(eid) or {}
            local usable = (not ap.CanHeroAbsorb) or (ap:CanHeroAbsorb(eid) == true)
            local skipHeavy = exclHeavy and ap.IsOnlyHeavyQuest and ap.IsOnlyHeavyQuest(eid)
            local dMask = 1
            if not isSingleDiff then
                dMask = (srv and srv.modeMask and srv.modeMask > 0) and srv.modeMask or (rec.diffMask or 0)
                if dMask == 0 and ap.InferRuntimeDiffMask and rec.ilvl and rec.ilvl > 0 then
                    local zMeta = ap.Data.Zones and ap.Data.Zones[topId]
                    local zExp = (zMeta and zMeta.exp) or (zoneDesc.exp == "WotLK" and 3 or (zoneDesc.exp == "TBC" and 2 or 1))
                    dMask = ap.InferRuntimeDiffMask(topId, eid, rec.ilvl, zoneDesc.isRaid == true, zExp)
                end
                if maxDiffs == 2 and dMask >= 4 then
                    local c = 0
                    if bit and bit.band then
                        if bit.band(dMask, 1) ~= 0 or bit.band(dMask, 4) ~= 0 then c = c + 1 end
                        if bit.band(dMask, 2) ~= 0 or bit.band(dMask, 8) ~= 0 then c = c + 2 end
                    else
                        c = (dMask >= 8) and 2 or 1
                    end
                    dMask = c
                end
            end

            if usable and not skipHeavy and MatchesZoneDiff(dMask, effDiff, maxDiffs, isSingleDiff) then
                local st = ap.GetItemServerStatus and ap:GetItemServerStatus(eid, sfx) or {}
                local doneTier = st.doneTier or -1
                local curPct = st.curPct or 0
                local remainPct = st.remainPct or 0
                local maxPct = st.maxPct or 90
                local isDone = st.isCompleted == true
                local isNew = st.isNew == true
                local needsForge = st.needsForge == true
                if srv and srv.absorbed and doneTier < 0 then
                    doneTier = 0; curPct = 20; remainPct = maxPct - 20; isNew = false; needsForge = true; isDone = false
                end

                local cat = isDone and "done" or (needsForge and "forge" or "new")
                local ownLbl = owned[eid]
                local passSt = (stFilter == "all")
                    or (stFilter == "need" and (cat == "new" or cat == "forge"))
                    or (stFilter == "owned" and ownLbl ~= nil)
                    or (cat == stFilter)

                if passSt then
                    local _, coreSum = 0, 0
                    if ap.GetItemStats then _, coreSum = ap:GetItemStats(eid, sfx) end
                    coreSum = coreSum or 0
                    local remStats = isDone and 0 or math.floor(coreSum * ((isNew and maxPct or remainPct) / 100) + 0.5)
                    local iName, iLink, iQual, iIlvl, iIcon
                    if ap.GetItemInfo then
                        local info = ap:GetItemInfo(eid, sfx)
                        if type(info) == "table" then
                            iName, iLink, iQual, iIlvl, iIcon = info.name, info.link, info.quality, info.ilvl, info.icon
                        end
                    end
                    local gNm, gLk, gQ, gIl, _, _, _, _, _, gIc = GetItemInfo(eid)
                    iName = gNm or iName or (rec.name and rec.name ~= "" and rec.name) or ("Предмет #" .. eid)
                    iLink = gLk or iLink or ("item:" .. eid .. ":0:0:0:0:0:" .. tostring(sfx) .. ":0:80")
                    iQual = gQ or iQual or rec.quality or 4
                    iIlvl = (rec.ilvl and rec.ilvl > 0 and rec.ilvl) or gIl or iIlvl or 0
                    iIcon = gIc or iIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
                    local dTag = (not isSingleDiff and not effDiff and ap.GetItemDiffTag)
                        and ap:GetItemDiffTag(eid, topId, dMask, false) or ""
                    local srcText = ExtractItemSourceText(ap, eid)

                    local matchQ = true
                    if qNorm then
                        local hay = TalorianTP_Norm(iName .. " " .. (srcText or "") .. " " .. (dTag or ""))
                        matchQ = hay:find(qNorm, 1, true) ~= nil
                    end

                    if matchQ then
                        table.insert(items, {
                            id = eid, sfx = sfx, name = iName, link = iLink, quality = iQual, ilvl = iIlvl,
                            icon = iIcon, diffMask = dMask, diffTag = dTag, cat = cat, doneTier = doneTier,
                            curPct = curPct, remainPct = remainPct, coreStats = coreSum, remainStats = remStats,
                            ownedLabel = ownLbl, srcText = srcText, isRand = rec.hasRandomSuffix == true,
                        })
                    end
                end
            end
        end

        local orderRank = { new = 1, forge = 2, done = 3 }
        table.sort(items, function(a, b)
            local ra, rb = orderRank[a.cat] or 9, orderRank[b.cat] or 9
            if ra ~= rb then return ra < rb end
            if (a.ownedLabel and 1 or 0) ~= (b.ownedLabel and 1 or 0) then
                return (a.ownedLabel ~= nil)
            end
            if a.remainStats ~= b.remainStats then return a.remainStats > b.remainStats end
            if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
            return (a.name or "") < (b.name or "")
        end)

        return items, za
    end

    local function RefreshExplorerItems()
        if not analysisFrame or not analysisFrame:IsShown() then return end
        local f = analysisFrame
        local sel = nil
        for _, z in ipairs(expState.zones) do
            if z.dest.name == expState.selZoneName then sel = z; break end
        end
        if not sel and expState.zones[1] then
            sel = expState.zones[1]
            expState.selZoneName = sel.dest.name
        end

        local items, za = {}, nil
        if sel then
            items, za = CollectZoneItems(sel.dest)
        end
        expState.items = items
        expState.selMeta = sel

        -- Баннер выбранного инста
        if sel then
            local d = sel.dest
            f.selIcon:SetTexture(ResolveIcon(d.icon))
            f.selTitle:SetText("|cfffce08c" .. d.name .. "|r |cff94a3b8(" .. (d.isRaid and "Рейд" or "Подземелье") .. " - " .. (EXP_LABELS[d.exp] or d.exp or "") .. ")|r")
            if za and za.modeAvailable == false then
                f.selSub:SetText("|cffff7070Выбранная сложность отсутствует для этого инста|r")
            elseif za and za.totalPool and za.totalPool > 0 then
                local doneCnt = za.completedCount or 0
                local pct = math.floor((doneCnt / za.totalPool) * 100 + 0.5)
                local remSt = za.totalRemainStats or 0
                f.selSub:SetText(string.format("Освоено: |cff40ff40%d/%d (%d%%)|r | Новых: |cff40ff40%d|r | Ковка: |cffffd200%d|r | Осталось: |cff38bdf8+%s стат.|r | Показано: |cffffffff%d|r",
                    doneCnt, za.totalPool, pct, za.newCount or 0, za.forgeCount or 0, FormatStatValue(remSt), #items))
            else
                f.selSub:SetText(string.format("Показано предметов: |cffffffff%d|r", #items))
            end

            local curTgt = TalorianTP_DB and TalorianTP_DB.targetRaid
            if curTgt == d.name then
                PS.PaintBtn(f.targetBtn, "green")
                f.targetBtn.txt:SetText("Выбрано целью")
            else
                PS.PaintBtn(f.targetBtn, "gold")
                f.targetBtn.txt:SetText("Цель Талориана")
            end
        else
            f.selIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            f.selTitle:SetText("|cff94a3b8Нет подходящих инстов|r")
            f.selSub:SetText("Измените фильтр эры, типа или поиска.")
        end

        local sf = f.itemScroll
        local rows = f.itemRows
        if sf and sf.SyncCount then
            sf:SyncCount(#items)
        else
            FauxScrollFrame_Update(sf, #items, #rows, ITEM_ROW_H)
        end
        local offset = math.min((sf and sf.offset) or (sf and sf._offset) or 0, math.max(0, #items - #rows))
        if sf then sf._offset = offset end

        for i = 1, #rows do
            local r = rows[i]
            local it = items[i + offset]
            if it then
                r.itemData = it
                r.zoneDest = sel and sel.dest or nil
                r.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local dStr = (it.diffTag and it.diffTag ~= "") and ("|cff94a3b8[" .. it.diffTag .. "]|r ") or ""
                local ilStr = (it.ilvl and it.ilvl > 0) and (" |cff94a3b8[" .. it.ilvl .. "]|r") or ""
                local ownStr = it.ownedLabel and (" |cff40ff80[" .. it.ownedLabel .. "]|r") or ""
                local qCol = QUAL_HEX[it.quality or 4] or "|cffffffff"
                r.name:SetText(dStr .. qCol .. (it.name or "?") .. "|r" .. ilStr .. ownStr)

                local srcPart = it.srcText and ("|cffc8bea8" .. it.srcText .. "|r") or "|cff78716cИсточник уточняется...|r"
                local statPart = (it.coreStats and it.coreStats > 0) and ("  |cff64748b(база статов: " .. FormatStatValue(it.coreStats) .. ")|r") or ""
                r.source:SetText(srcPart .. statPart)

                if it.cat == "done" then
                    r.status:SetText("|cff00ffffТитанич. 90%|r")
                    r.gain:SetText("|cff40ff40Готово|r")
                elseif it.cat == "forge" then
                    local ti = TIER_UI[it.doneTier or 0] or TIER_UI[0]
                    r.status:SetText(ti.hex .. ti.short .. "|r -> |cff00ffff90%|r")
                    r.gain:SetText((it.remainStats > 0) and ("|cffffd200+" .. FormatStatValue(it.remainStats) .. " стат.|r") or (it.isRand and "|cffaaaaaaсуффикс|r" or ""))
                else
                    r.status:SetText("|cff40ff40Новый (0%)|r")
                    r.gain:SetText((it.remainStats > 0) and ("|cff38bdf8+" .. FormatStatValue(it.remainStats) .. " стат.|r") or (it.isRand and "|cffaaaaaaсуффикс|r" or ""))
                end

                r.bg:SetTexture(0.00, 0.00, 0.00, (i % 2 == 0) and 0.44 or 0.24)
                r:Show()
            else
                r.itemData = nil
                r.zoneDest = nil
                r:Hide()
            end
        end
    end

    local function RenderZoneList()
        if not analysisFrame or not analysisFrame:IsShown() then return end
        local f = analysisFrame
        local zones = expState.zones
        local rows = f.zoneRows
        local sf = f.zoneScroll
        if sf and sf.SyncCount then
            sf:SyncCount(#zones)
        else
            FauxScrollFrame_Update(sf, #zones, #rows, ZONE_ROW_H)
        end
        local offset = math.min((sf and sf.offset) or (sf and sf._offset) or 0, math.max(0, #zones - #rows))
        if sf then sf._offset = offset end

        for i = 1, #rows do
            local r = rows[i]
            local z = zones[i + offset]
            if z then
                r.zoneRec = z
                local d = z.dest
                r.icon:SetTexture(ResolveIcon(d.icon))
                local isSel = (d.name == expState.selZoneName)
                local kdTag = z.locked and " |cff40ff40[КД]|r" or ""
                r.name:SetText((isSel and "|cffffd200" or "|cffe8dfc8") .. d.name .. "|r" .. kdTag)

                if z.modeAvailable == false then
                    r.sub:SetText("|cff666666Нет сложности|r")
                    r.pctTxt:SetText("|cff666666-|r")
                    r.fill:Hide()
                elseif z.total > 0 then
                    local pCol = (z.pct >= 100) and "|cff40ff40" or (z.pct >= 60 and "|cffa3e635" or "|cff60a5fa")
                    local remTxt = (z.newCnt + z.forgeCnt == 0) and "|cff40ff40100%|r"
                        or string.format("|cff40ff40%dн|r |cffffd200%dк|r", z.newCnt, z.forgeCnt)
                    r.sub:SetText(string.format("%d/%d - %s", z.done, z.total, remTxt))
                    r.pctTxt:SetText(string.format("%s%d%%|r", pCol, z.pct))
                    local fw = math.max(1, math.floor((r._barW or 224) * math.min(100, z.pct) / 100))
                    r.fill:SetWidth(fw)
                    if z.pct >= 100 then r.fill:SetVertexColor(0.22, 0.88, 0.42, 0.9)
                    elseif z.pct >= 50 then r.fill:SetVertexColor(0.95, 0.76, 0.20, 0.9)
                    else r.fill:SetVertexColor(0.24, 0.68, 0.98, 0.9) end
                    r.fill:Show()
                else
                    r.sub:SetText(d.exp or "")
                    r.pctTxt:SetText("")
                    r.fill:Hide()
                end

                if isSel then
                    r:SetBackdropColor(0.20, 0.16, 0.08, 0.92)
                    r:SetBackdropBorderColor(0.92, 0.74, 0.28, 0.95)
                else
                    r:SetBackdropColor(0.05, 0.05, 0.08, 0.55)
                    r:SetBackdropBorderColor(0.24, 0.20, 0.14, 0.60)
                end
                r:Show()
            else
                r.zoneRec = nil
                r:Hide()
            end
        end
    end

    local function RefreshExplorerAll(rescanOwned)
        if not analysisFrame or not analysisFrame:IsShown() then return end
        local f = analysisFrame
        if rescanOwned ~= false then
            expState.ownedMap = BuildOwnedMap()
        end

        local ap = rawget(_G, "AttuneParser")
        if expState.kind == "dungeon" and (expState.diff or 0) > 2 then
            expState.diff = 0
        end
        local effDiff = (expState.diff > 0) and expState.diff or nil
        local qNorm = (expState.query ~= "") and TalorianTP_Norm(expState.query) or nil
        local allDests = GetAllExplorerZones()
        local list = {}
        local totDone, totPool, totNew, totForge, totStats = 0, 0, 0, 0, 0

        for _, d in ipairs(allDests) do
            local kOk = (expState.kind == "all")
                or (expState.kind == "raid" and d.isRaid)
                or (expState.kind == "dungeon" and not d.isRaid)
            local eOk = (expState.era == "all") or (d.exp == expState.era)
            if kOk and eOk then
                local za = (ap and ap.GetZoneAnalysis and d.attune) and ap:GetZoneAnalysis(d.attune, {
                    diffId = effDiff, isRaid = d.isRaid, exp = d.exp, scope = "hero",
                }) or nil
                local modeAvail = (not za) or (za.modeAvailable ~= false)
                local done = (za and za.completedCount) or 0
                local total = (za and za.totalPool) or 0
                local newCnt = (za and za.newCount) or 0
                local forgeCnt = (za and za.forgeCount) or 0
                local pct = (total > 0) and math.floor((done / total) * 100 + 0.5) or 0
                local remStats = (za and za.totalRemainStats) or 0

                local includeZone = (not qNorm) or (TalorianTP_Norm(d.name .. " " .. (d.short or "")):find(qNorm, 1, true) ~= nil)
                if not includeZone and qNorm then
                    local matchedItems = CollectZoneItems(d)
                    if matchedItems and #matchedItems > 0 then includeZone = true end
                end
                if includeZone then
                    if modeAvail and total > 0 then
                        totDone = totDone + done
                        totPool = totPool + total
                        totNew = totNew + newCnt
                        totForge = totForge + forgeCnt
                        totStats = totStats + remStats
                    end
                    table.insert(list, {
                        dest = d, modeAvailable = modeAvail, done = done, total = total,
                        newCnt = newCnt, forgeCnt = forgeCnt, pct = pct, remainStats = remStats,
                        locked = IsInstanceLocked(d.name),
                    })
                end
            end
        end

        -- Если при поиске введен текст названия инста, подберем подходящий инст
        if qNorm then
            local exactZone
            for _, z in ipairs(list) do
                if TalorianTP_Norm(z.dest.name .. " " .. (z.dest.short or "")):find(qNorm, 1, true) then
                    exactZone = z.dest.name
                    break
                end
            end
            if exactZone and not TalorianTP_Norm(expState.selZoneName or ""):find(qNorm, 1, true) then
                expState.selZoneName = exactZone
            end
        end
        local selFound = false
        for _, z in ipairs(list) do
            if z.dest.name == expState.selZoneName then selFound = true; break end
        end
        if not selFound and list[1] then
            expState.selZoneName = list[1].dest.name
        end
        expState.zones = list

        for _, b in ipairs(f.kindBtns) do PS.PaintBtn(b, (b.id == expState.kind) and "gold" or "dark") end
        for _, b in ipairs(f.eraBtns) do PS.PaintBtn(b, (b.id == expState.era) and "gold" or "dark") end
        for _, b in ipairs(f.diffBtns) do
            PS.PaintBtn(b, (b.id == expState.diff) and "gold" or "dark")
            if b.id == 1 then b.txt:SetText((expState.kind == "dungeon") and "Обыч." or "10 об")
            elseif b.id == 2 then b.txt:SetText((expState.kind == "dungeon") and "Героич." or "25 об")
            elseif b.id >= 3 then
                if expState.kind == "dungeon" then b:Hide() else b:Show() end
            end
        end
        for _, b in ipairs(f.statusBtns) do PS.PaintBtn(b, (b.id == expState.status) and "gold" or "dark") end

        if totPool > 0 then
            local allPct = math.floor((totDone / totPool) * 100 + 0.5)
            f.summaryTxt:SetText(string.format("Выборка: |cff40ff40%d/%d (%d%%)|r | Новых: |cff40ff40%d|r | Ковка: |cffffd200%d|r | Осталось: |cff38bdf8+%s стат.|r",
                totDone, totPool, allPct, totNew, totForge, FormatStatValue(totStats)))
        else
            f.summaryTxt:SetText("Выберите рейд или подземелье слева для просмотра предметов и источников.")
        end

        RenderZoneList()
        RefreshExplorerItems()
    end

    local function CreateFilterRow(parent, defs, curY, startX, onSelect)
        local out = {}
        local x = startX
        for _, fd in ipairs(defs) do
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(fd.w, 21)
            btn:SetPoint("TOPLEFT", x, curY)
            PS.StyleBtn(btn, "dark")
            local bt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            bt:SetPoint("CENTER", 0, 0)
            bt:SetText(fd.label)
            btn.txt = bt
            btn.id = fd.id
            btn:SetScript("OnClick", function() onSelect(fd.id) end)
            table.insert(out, btn)
            x = x + fd.w + 4
        end
        return out, x
    end

    local function CreateAnalysisWindow()
        if analysisFrame then return analysisFrame end

        local f = CreateFrame("Frame", "TalorianAnalysisFrame", UIParent)
        f:SetSize(808, 554)
        f:SetPoint("CENTER", 0, 0)
        f:SetFrameStrata("HIGH")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        PS.ApplyWindow(f)
        RegisterSpecialFrame("TalorianAnalysisFrame")
        f:HookScript("OnShow", function(self)
            PlaySound("igCharacterInfoOpen")
            RaiseFrameFront(self)
        end)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOPLEFT", 16, -12)
        title:SetText("|cfffce08cВещи по рейдам и подземельям|r")

        local closeBtn = CreateFrame("Button", nil, f)
        closeBtn:SetSize(24, 24)
        closeBtn:SetPoint("TOPRIGHT", -10, -10)
        local cbTxt = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cbTxt:SetPoint("CENTER", 0, 0)
        cbTxt:SetText("|cffff6060X|r")
        PS.StyleClose(closeBtn, 24)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        local refreshHdrBtn = CreateFrame("Button", nil, f)
        refreshHdrBtn:SetSize(86, 22)
        refreshHdrBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
        PS.StyleBtn(refreshHdrBtn, "dark")
        local rht = refreshHdrBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rht:SetPoint("CENTER", 0, 0)
        rht:SetText("Обновить")
        refreshHdrBtn:SetScript("OnClick", function()
            local ap = rawget(_G, "AttuneParser")
            if ap and type(ap.InvalidateCaches) == "function" then ap:InvalidateCaches(true) end
            TalorianTP_ScanAbsorbedItems()
            RefreshExplorerAll(true)
        end)

        local chatBtn = CreateFrame("Button", nil, f)
        chatBtn:SetSize(88, 22)
        chatBtn:SetPoint("RIGHT", refreshHdrBtn, "LEFT", -6, 0)
        PS.StyleBtn(chatBtn, "dark")
        local cbt = chatBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cbt:SetPoint("CENTER", 0, 0)
        cbt:SetText("Сводка в чат")
        chatBtn:SetScript("OnClick", function()
            local sel = expState.selMeta
            if not sel or not expState.items then
                TalorianTP_PrintAnalysisToChat()
                return
            end
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[Talorian]|r %s: %d/%d (%d%%) | Новых: %d | Ковка: %d (+%s стат.)",
                sel.dest.name, sel.done, sel.total, sel.pct, sel.newCnt, sel.forgeCnt, FormatStatValue(sel.remainStats)))
            local shown = 0
            for _, it in ipairs(expState.items) do
                if it.cat ~= "done" and shown < 5 then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s [%s] %s",
                        it.link or it.name or "?",
                        (it.cat == "new") and "Новый" or ((it.curPct or 20) .. "% ковка"),
                        it.srcText or ""))
                    shown = shown + 1
                end
            end
        end)

        local summaryTxt = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        summaryTxt:SetPoint("TOPLEFT", 16, -33)
        summaryTxt:SetPoint("RIGHT", -16, 0)
        summaryTxt:SetJustifyH("LEFT")
        f.summaryTxt = summaryTxt

        -- Строки фильтров
        local function ResetExplorerScrolls()
            if f.zoneScroll then
                f.zoneScroll.offset = 0
                f.zoneScroll._offset = 0
                if type(FauxScrollFrame_SetOffset) == "function" then FauxScrollFrame_SetOffset(f.zoneScroll, 0) end
            end
            if f.itemScroll then
                f.itemScroll.offset = 0
                f.itemScroll._offset = 0
                if type(FauxScrollFrame_SetOffset) == "function" then FauxScrollFrame_SetOffset(f.itemScroll, 0) end
            end
        end

        local kindBtns, nextX = CreateFilterRow(f, EXP_KIND_BTNS, -52, 16, function(id)
            expState.kind = id
            ResetExplorerScrolls()
            RefreshExplorerAll(false)
        end)
        f.kindBtns = kindBtns

        local eraBtns, eraEndX = CreateFilterRow(f, EXP_ERA_BTNS, -52, nextX + 8, function(id)
            expState.era = id
            ResetExplorerScrolls()
            RefreshExplorerAll(false)
        end)
        f.eraBtns = eraBtns

        local diffBtns = CreateFilterRow(f, EXP_DIFF_BTNS, -52, eraEndX + 8, function(id)
            expState.diff = id
            ResetExplorerScrolls()
            RefreshExplorerAll(false)
        end)
        f.diffBtns = diffBtns

        local statusBtns, stEndX = CreateFilterRow(f, EXP_STATUS_BTNS, -77, 16, function(id)
            expState.status = id
            if f.itemScroll then
                f.itemScroll.offset = 0
                f.itemScroll._offset = 0
                if type(FauxScrollFrame_SetOffset) == "function" then FauxScrollFrame_SetOffset(f.itemScroll, 0) end
            end
            RefreshExplorerItems()
        end)
        f.statusBtns = statusBtns

        -- Поле поиска
        local searchEdit = CreateFrame("EditBox", "TalorianExplorerSearchBox", f)
        searchEdit:SetSize(792 - (stEndX + 4), 21)
        searchEdit:SetPoint("TOPLEFT", stEndX + 4, -77)
        if searchEdit.SetAutoFocus then searchEdit:SetAutoFocus(false) end
        if searchEdit.SetFontObject and GameFontHighlightSmall then searchEdit:SetFontObject(GameFontHighlightSmall) end
        PS.StyleBox(searchEdit, 0.65)
        if searchEdit.SetTextInsets then searchEdit:SetTextInsets(6, 20, 0, 0) end
        local ph = searchEdit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        ph:SetPoint("LEFT", 6, 0)
        ph:SetText("Поиск вещи или инста...")
        local clearSearchBtn = CreateFrame("Button", nil, searchEdit)
        clearSearchBtn:SetSize(16, 16)
        clearSearchBtn:SetPoint("RIGHT", -3, 0)
        local csT = clearSearchBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        csT:SetPoint("CENTER", 0, 0)
        csT:SetText("|cff94a3b8x|r")
        clearSearchBtn:Hide()
        clearSearchBtn:SetScript("OnClick", function()
            searchEdit:SetText("")
            expState.query = ""
            ph:Show()
            clearSearchBtn:Hide()
            ResetExplorerScrolls()
            RefreshExplorerAll(false)
        end)
        searchEdit:SetScript("OnEscapePressed", function(self) if self.ClearFocus then self:ClearFocus() end end)
        searchEdit:SetScript("OnTextChanged", function(self)
            local txt = self:GetText() or ""
            expState.query = txt
            if txt ~= "" then ph:Hide(); clearSearchBtn:Show() else ph:Show(); clearSearchBtn:Hide() end
            ResetExplorerScrolls()
            RefreshExplorerAll(false)
        end)
        f:HookScript("OnHide", function()
            if searchEdit.ClearFocus then searchEdit:ClearFocus() end
            PlaySound("igCharacterInfoClose")
        end)
        f.searchEdit = searchEdit

        -- Левая панель: список рейдов и подземелий
        local leftBox = CreateFrame("Frame", nil, f)
        leftBox:SetPoint("TOPLEFT", 16, -104)
        leftBox:SetSize(256, 404)
        PS.StyleBox(leftBox, 0.42)

        local zsf
        zsf = PS.AttachScroll(leftBox, VIS_ZONES * ZONE_ROW_H, ZONE_ROW_H, VIS_ZONES, function(off)
            if zsf and not zsf._skipRender then
                zsf._offset = off
                RenderZoneList()
            end
        end, "TalorianExplorerZoneScroll")
        zsf:SetPoint("TOPLEFT", leftBox, "TOPLEFT", 2, -3)
        zsf:SetPoint("BOTTOMRIGHT", leftBox, "BOTTOMRIGHT", -4, 3)
        zsf._offset = 0
        f.zoneScroll = zsf

        leftBox:EnableMouseWheel(true)
        leftBox:SetScript("OnMouseWheel", function(_, delta)
            if zsf._OnWheel then zsf:_OnWheel(delta) end
        end)

        local zoneRows = {}
        for i = 1, VIS_ZONES do
            local r = CreateFrame("Button", nil, leftBox)
            r:SetSize(226, ZONE_ROW_H - 2)
            r:SetPoint("TOPLEFT", 4, -(i - 1) * ZONE_ROW_H - 4)
            r:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            local ic = r:CreateTexture(nil, "ARTWORK")
            ic:SetSize(22, 22)
            ic:SetPoint("LEFT", 4, 1)
            ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.icon = ic

            local nm = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nm:SetPoint("TOPLEFT", ic, "TOPRIGHT", 5, 0)
            nm:SetPoint("RIGHT", r, "RIGHT", -38, 0)
            nm:SetJustifyH("LEFT")
            if nm.SetWordWrap then nm:SetWordWrap(false) end
            r.name = nm

            local pt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pt:SetPoint("TOPRIGHT", -4, -3)
            pt:SetJustifyH("RIGHT")
            r.pctTxt = pt

            local sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            sub:SetPoint("BOTTOMLEFT", ic, "BOTTOMRIGHT", 5, 1)
            sub:SetPoint("RIGHT", r, "RIGHT", -4, 0)
            sub:SetJustifyH("LEFT")
            if sub.SetWordWrap then sub:SetWordWrap(false) end
            r.sub = sub

            local barBg = r:CreateTexture(nil, "BACKGROUND")
            barBg:SetHeight(2)
            barBg:SetPoint("BOTTOMLEFT", 2, 1)
            barBg:SetPoint("BOTTOMRIGHT", -2, 1)
            barBg:SetTexture(0.08, 0.08, 0.12, 0.9)
            local fill = r:CreateTexture(nil, "ARTWORK")
            fill:SetHeight(2)
            fill:SetPoint("BOTTOMLEFT", 2, 1)
            fill:SetTexture("Interface\\Buttons\\WHITE8X8")
            r.fill = fill
            r._barW = 222

            r:RegisterForClicks("LeftButtonUp")
            r:SetScript("OnClick", function(self)
                if not self.zoneRec then return end
                expState.selZoneName = self.zoneRec.dest.name
                if f.itemScroll then
                    f.itemScroll.offset = 0
                    f.itemScroll._offset = 0
                    if type(FauxScrollFrame_SetOffset) == "function" then FauxScrollFrame_SetOffset(f.itemScroll, 0) end
                end
                RenderZoneList()
                RefreshExplorerItems()
            end)
            zoneRows[i] = r
        end
        f.zoneRows = zoneRows

        -- Правая панель: шапка выбранного инста + список вещей
        local banner = CreateFrame("Frame", nil, f)
        banner:SetPoint("TOPLEFT", leftBox, "TOPRIGHT", 8, 0)
        banner:SetSize(512, 46)
        PS.StyleBox(banner, 0.52)

        local selIcon = banner:CreateTexture(nil, "ARTWORK")
        selIcon:SetSize(32, 32)
        selIcon:SetPoint("LEFT", 8, 0)
        selIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.selIcon = selIcon

        local targetBtn = CreateFrame("Button", nil, banner)
        targetBtn:SetSize(118, 24)
        targetBtn:SetPoint("RIGHT", -8, 0)
        PS.StyleBtn(targetBtn, "gold")
        local tbt = targetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tbt:SetPoint("CENTER", 0, 0)
        tbt:SetText("Цель Талориана")
        targetBtn.txt = tbt
        targetBtn:SetScript("OnClick", function()
            if expState.selZoneName and TalorianTP_SetTarget then
                TalorianTP_SetTarget(expState.selZoneName)
                RefreshExplorerItems()
            end
        end)
        f.targetBtn = targetBtn

        local selTitle = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        selTitle:SetPoint("TOPLEFT", selIcon, "TOPRIGHT", 8, -2)
        selTitle:SetPoint("RIGHT", targetBtn, "LEFT", -8, 0)
        selTitle:SetJustifyH("LEFT")
        if selTitle.SetWordWrap then selTitle:SetWordWrap(false) end
        f.selTitle = selTitle

        local selSub = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        selSub:SetPoint("BOTTOMLEFT", selIcon, "BOTTOMRIGHT", 8, 2)
        selSub:SetPoint("RIGHT", targetBtn, "LEFT", -8, 0)
        selSub:SetJustifyH("LEFT")
        if selSub.SetWordWrap then selSub:SetWordWrap(false) end
        f.selSub = selSub

        local rightBox = CreateFrame("Frame", nil, f)
        rightBox:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -6)
        rightBox:SetPoint("BOTTOMRIGHT", -16, 46)
        PS.StyleBox(rightBox, 0.42)

        local isf
        isf = PS.AttachScroll(rightBox, VIS_ITEMS * ITEM_ROW_H, ITEM_ROW_H, VIS_ITEMS, function(off)
            if isf and not isf._skipRender then
                isf._offset = off
                RefreshExplorerItems()
            end
        end, "TalorianExplorerItemScroll")
        isf:SetPoint("TOPLEFT", rightBox, "TOPLEFT", 2, -3)
        isf:SetPoint("BOTTOMRIGHT", rightBox, "BOTTOMRIGHT", -4, 3)
        isf._offset = 0
        f.itemScroll = isf

        rightBox:EnableMouseWheel(true)
        rightBox:SetScript("OnMouseWheel", function(_, delta)
            if isf._OnWheel then isf:_OnWheel(delta) end
        end)

        local itemRows = {}
        for i = 1, VIS_ITEMS do
            local r = CreateFrame("Button", nil, rightBox)
            r:SetSize(482, ITEM_ROW_H - 2)
            r:SetPoint("TOPLEFT", 4, -(i - 1) * ITEM_ROW_H - 5)

            local rbg = r:CreateTexture(nil, "BACKGROUND")
            rbg:SetAllPoints()
            r.bg = rbg

            local ric = r:CreateTexture(nil, "ARTWORK")
            ric:SetSize(26, 26)
            ric:SetPoint("LEFT", 5, 0)
            ric:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.icon = ric

            local rname = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rname:SetPoint("TOPLEFT", ric, "TOPRIGHT", 6, -1)
            rname:SetPoint("RIGHT", r, "RIGHT", -124, 0)
            rname:SetJustifyH("LEFT")
            if rname.SetWordWrap then rname:SetWordWrap(false) end
            r.name = rname

            local rsrc = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            rsrc:SetPoint("BOTTOMLEFT", ric, "BOTTOMRIGHT", 6, 1)
            rsrc:SetPoint("RIGHT", r, "RIGHT", -124, 0)
            rsrc:SetJustifyH("LEFT")
            if rsrc.SetWordWrap then rsrc:SetWordWrap(false) end
            r.source = rsrc

            local rstat = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rstat:SetPoint("TOPRIGHT", -6, -3)
            rstat:SetJustifyH("RIGHT")
            r.status = rstat

            local rgain = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rgain:SetPoint("BOTTOMRIGHT", -6, 3)
            rgain:SetJustifyH("RIGHT")
            r.gain = rgain

            r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            r:SetScript("OnEnter", function(self)
                local it = self.itemData
                if not it then return end
                self.bg:SetTexture(0.28, 0.22, 0.12, 0.85)
                if InCombatLockdown and InCombatLockdown() then return end
                local ap = rawget(_G, "AttuneParser")
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if ap and type(ap.BuildItemTooltip) == "function" then
                    local ex = it.ownedLabel and ("|cff40ff80Местонахождение: " .. it.ownedLabel .. "|r") or nil
                    ap:BuildItemTooltip(GameTooltip, it.id, {
                        link = it.link,
                        zoneId = self.zoneDest and self.zoneDest.attune or nil,
                        diffMask = it.diffMask,
                        extraLine = ex,
                        hint = "|cff94a3b8ЛКМ/Shift+ЛКМ: ссылка в чат | Ctrl+ЛКМ: примерить | ПКМ: боссы|r",
                    })
                elseif it.link then
                    GameTooltip:ClearLines()
                    pcall(GameTooltip.SetHyperlink, GameTooltip, it.link)
                end
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                self.bg:SetTexture(0.00, 0.00, 0.00, (i % 2 == 0) and 0.44 or 0.24)
            end)
            r:SetScript("OnClick", function(self, mBtn)
                local it = self.itemData
                if not it then return end
                if mBtn == "RightButton" then
                    if it.srcText then
                        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff38bdf8[Talorian]|r %s - %s", it.link or it.name or "?", it.srcText))
                    elseif rawget(_G, "AttuneAtlas_Toggle") then
                        AttuneAtlas_Toggle()
                        local af = rawget(_G, "AttuneAtlasFrame")
                        if af and af:IsShown() then RaiseFrameFront(af) end
                    end
                    return
                end
                local ap = rawget(_G, "AttuneParser")
                if IsControlKeyDown() and type(DressUpItemLink) == "function" and it.link then
                    pcall(DressUpItemLink, it.link)
                    local df = rawget(_G, "DressUpFrame")
                    if df and df:IsShown() then RaiseFrameFront(df) end
                elseif ap and type(ap.InsertItemLink) == "function" then
                    ap:InsertItemLink(it.id, it.link, it.name, it.quality)
                elseif it.link and type(ChatEdit_InsertLink) == "function" then
                    ChatEdit_InsertLink(it.link)
                end
            end)
            itemRows[i] = r
        end
        f.itemRows = itemRows

        local footerTxt = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        footerTxt:SetPoint("BOTTOMLEFT", 16, 16)
        footerTxt:SetText("|cff94a3b8Подсказка: наведите на вещь для подробностей | ЛКМ / Shift+ЛКМ: в чат | Ctrl+ЛКМ: примерить | ПКМ: источник|r")

        f:Hide()
        analysisFrame = f
        return f
    end

    function TalorianTP_RefreshAnalysisLive()
        if analysisFrame and analysisFrame:IsShown() then
            RefreshExplorerAll(true)
        end
    end

    function TalorianTP_ToggleAnalysisWindow()
        local f = CreateAnalysisWindow()
        if f:IsShown() then
            f:Hide()
        else
            local curTgt = TalorianTP_DB and TalorianTP_DB.targetRaid
            if curTgt then expState.selZoneName = curTgt end
            f:Show()
            RaiseFrameFront(f)
            RefreshExplorerAll(true)
        end
    end
end

---------------------------------------------------------------------------
-- Окно рекомендаций "Атлас и Топ" на базе AttuneParser
---------------------------------------------------------------------------
do
    local topFrame = nil
    local topMode = "new" -- "new" | "forge" | "combined" | "noreq"
    local topRowsData = {}

    local function FindDestByZoneOrName(zoneId, zoneName)
        if zoneName and zoneName ~= "" then
            local byName = FindDestByName(zoneName)
            if byName then return byName end
        end
        local pools = { RAID_DESTS, DUNGEONS_WOTLK, DUNGEONS_TBC, DUNGEONS_VANILLA }
        if zoneId and zoneId > 0 then
            for _, pool in ipairs(pools) do
                for _, d in ipairs(pool) do
                    if d.attune == zoneId then return d end
                end
            end
        end
        return nil
    end

    local function SelectDestInTalorianUI(dest)
        if not dest then return end
        TalorianTP_SetTarget(dest.name)
        TalorianTP_DB = TalorianTP_DB or {}
        if dest.isRaid then
            TalorianTP_DB.activeTab = 1
            if TalorianTP_DB.raidEra and TalorianTP_DB.raidEra ~= "All" and dest.exp then
                TalorianTP_DB.raidEra = dest.exp
            end
            if mainUI and mainUI.SwitchTab then mainUI:SwitchTab(1) end
        else
            TalorianTP_DB.activeTab = 2
            if dest.exp then TalorianTP_DB.dungeonEra = dest.exp end
            if mainUI and mainUI.SwitchTab then mainUI:SwitchTab(2) end
        end
    end

    function TalorianTP_SelectZone(zoneId, zoneName)
        local dest = FindDestByZoneOrName(zoneId, zoneName)
        if not dest then return false end
        SelectDestInTalorianUI(dest)
        if mainUI and mainUI:IsShown() and mainUI.UpdateHeaderTarget then
            mainUI:UpdateHeaderTarget()
        end
        return true
    end

    local topOpt = { wedMode = false, onlyUnlocked = false, wedAutoInit = false }

    local function CollectLockedZonesMap()
        local locked = {}
        for _, pool in ipairs({ RAID_DESTS, DUNGEONS_WOTLK, DUNGEONS_TBC, DUNGEONS_VANILLA }) do
            for _, d in ipairs(pool) do
                if d.attune and IsInstanceLocked(d.name) then
                    locked[d.attune] = true
                end
            end
        end
        return locked
    end

    local function BuildTopRows()
        topRowsData = {}
        local ap = rawget(_G, "AttuneParser")
        if not ap then return end
        local gift = ap.GetActiveDailyGift and ap:GetActiveDailyGift() or nil

        if topMode == "noreq" and ap.GetNoReqLevelItems then
            local nr = ap:GetNoReqLevelItems({ scope = "hero" })
            local function pushGroup(items, isNewGrp)
                for _, it in ipairs(items or {}) do
                    local zName = ""
                    local zDest = (it.primaryZone and it.primaryZone > 0) and FindDestByZoneOrName(it.primaryZone, nil) or nil
                    if zDest then
                        zName = zDest.name
                    elseif it.primaryZone and it.primaryZone > 0 and ap.Data and ap.Data.Zones and ap.Data.Zones[it.primaryZone] then
                        zName = ap.Data.Zones[it.primaryZone].name or ""
                    end
                    local srcMeta = ap.GetItemSources and ap:GetItemSources(it.itemId) or nil
                    local firstSrc = srcMeta and srcMeta.list and srcMeta.list[1]
                    if zName == "" and firstSrc then
                        zName = (firstSrc.zoneName and firstSrc.zoneName ~= "" and firstSrc.zoneName)
                            or (firstSrc.name and firstSrc.name ~= "" and firstSrc.name) or ""
                    end
                    local stText = isNewGrp
                        and string.format("|cff40ff40Новый (%d%% -> 90%%)|r", it.newBasePct or 20)
                        or  string.format("|cffffd200Ковка (%s -> 90%%)|r", it.doneTierName or "")
                    if gift and gift.isThursday and srcMeta and srcMeta.hasVendor then
                        stText = stText .. " |cff40ff40[100%]|r"
                    end
                    if ap.IsItemBlacklisted and ap:IsItemBlacklisted(it.itemId) then
                        stText = stText .. " |cffff6060[ЧС]|r"
                    end
                    local gain = isNewGrp and (it.fullMaxStats or 0) or (it.remainStats or 0)
                    table.insert(topRowsData, {
                        kind = "item",
                        itemId = it.itemId,
                        name = it.name or ("Предмет #" .. it.itemId),
                        ilvl = it.ilvl or 0,
                        zoneName = zName,
                        dest = zDest,
                        sources = srcMeta and srcMeta.list or nil,
                        hasServerSources = srcMeta and srcMeta.hasServerSources or false,
                        hasVendor = srcMeta and srcMeta.hasVendor or false,
                        statusText = stText,
                        statsText = gain > 0 and ("+" .. FormatStatValue(gain) .. " статов") or "",
                        icon = select(10, GetItemInfo(it.itemId)) or "Interface\\Icons\\INV_Misc_QuestionMark",
                    })
                end
            end
            pushGroup(nr.newItems, true)
            pushGroup(nr.forgeItems, false)
        elseif ap.GetRecommendations then
            local effMode = (topOpt.wedMode and topMode ~= "noreq") and "wednesday" or topMode
            local recs = ap:GetRecommendations({
                mode = effMode,
                onlyInstances = true,
                limit = 45,
                lockedZones = CollectLockedZonesMap(),
                unlockedOnly = topOpt.onlyUnlocked,
            })
            local expLabels = { [1] = "Classic", [2] = "TBC", [3] = "WotLK" }
            for idx, z in ipairs(recs) do
                local dest = FindDestByZoneOrName(z.zoneId, z.zoneName)
                local typeLbl = z.isRaid and "Рейд" or "Подземелье"
                local expLbl = expLabels[z.exp] or ""
                local cdTag = z.isLocked and "|cffff6060[КД]|r " or ""
                local rightMain = string.format("|cff40ff40Новых: %d|r  |  |cffffd200Ковка: %d|r", z.newCount or 0, z.forgeCount or 0)
                local stGain = (topMode == "new") and (z.newMaxStats or 0)
                    or (topMode == "forge") and (z.forgeRemainStats or 0)
                    or (z.totalRemainStats or 0)
                table.insert(topRowsData, {
                    kind = "zone",
                    rank = idx,
                    zoneId = z.zoneId,
                    zoneName = z.zoneName or ("Зона " .. z.zoneId),
                    subLabel = cdTag .. (expLbl ~= "" and (expLbl .. " - ") or "") .. typeLbl,
                    rightMain = rightMain,
                    statsText = "+" .. FormatStatValue(stGain) .. " статов",
                    dest = dest,
                    za = z,
                    icon = dest and ResolveIcon(dest.icon) or "Interface\\Icons\\INV_Misc_Map_01",
                })
            end
        end
    end

    local function RefreshTopDisplay()
        if not topFrame or not topFrame:IsShown() then return end
        local ap = rawget(_G, "AttuneParser")
        local gift = (ap and ap.GetActiveDailyGift) and ap:GetActiveDailyGift(true) or nil
        if (not topOpt.wedAutoInit) and gift and gift.isWednesday then
            topOpt.wedAutoInit = true
            topOpt.wedMode = true
        end
        BuildTopRows()

        if ap and ap.TIER_PCT then
            local tp = ap.TIER_PCT
            local ms = ap.GetMilestonesSummary and ap:GetMilestonesSummary() or nil
            local cat = ap.GetAccountCatalogSummary and ap:GetAccountCatalogSummary() or nil
            local catText = ""
            if cat and (cat.totalBase or 0) > 0 then
                catText = string.format(" | Каталог: |cffffffff%d/%d|r (Акк:%d Г:%d)", cat.doneBase or 0, cat.totalBase or 0, cat.acc or 0, cat.hero or 0)
            end
            local msText = ""
            if ms and (ms.claimable or 0) > 0 then
                msText = string.format(" | |cff40ff40Наград вех: %d!|r", ms.claimable)
            elseif ms and ms.loaded and ms.nextNeed then
                msText = string.format(" | Веха: %d/%d", ms.done or 0, ms.nextNeed)
            end
            topFrame.subNote:SetText(string.format(
                "|cff94a3b8Тиры: %d/%d/%d/%d%% (%s) | Строк: |cffffffff%d|r%s%s|r",
                tp[0] or 20, tp[1] or 30, tp[2] or 50, tp[3] or 90, ap.TIER_SOURCE or "default", #topRowsData, catText, msText
            ))
            if topFrame.claimBtn then
                if ms and (ms.claimable or 0) > 0 then
                    topFrame.claimBtn.txt:SetText(string.format("|cff40ff40Забрать вехи (%d)|r", ms.claimable))
                    topFrame.claimBtn:Show()
                else
                    topFrame.claimBtn:Hide()
                end
            end
        elseif not ap then
            topFrame.subNote:SetText("|cffff5555Модуль AttuneParser не загружен.|r")
        end

        if topFrame.UpdateGiftBar then
            topFrame.UpdateGiftBar(gift)
        end

        local rows = topFrame.rows
        local numRows = #rows
        local tsf = topFrame.scrollFrame
        if tsf and tsf.SyncCount then
            tsf:SyncCount(#topRowsData)
        else
            FauxScrollFrame_Update(tsf, #topRowsData, numRows, 24)
        end
        local offset = math.min((tsf and tsf.offset) or (tsf and tsf._offset) or 0, math.max(0, #topRowsData - numRows))

        for i = 1, numRows do
            local r = rows[i]
            local row = topRowsData[i + offset]
            if row then
                r.rowData = row
                r.icon:SetTexture(row.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                if row.kind == "zone" then
                    r.title:SetText(string.format("|cffffd200#%d|r |cffffffff%s|r  |cff7aa2f7(%s)|r", row.rank, row.zoneName, row.subLabel))
                    r.rightMain:SetText(row.rightMain)
                    r.rightStats:SetText("|cff38bdf8" .. row.statsText .. "|r")
                else
                    local zSuffix = (row.zoneName ~= "") and (" |cff7aa2f7[" .. row.zoneName .. "]|r") or ""
                    r.title:SetText(string.format("|cff66ffcc[1 ур.]|r |cffffffff%s|r%s", row.name, zSuffix))
                    r.rightMain:SetText(row.statusText)
                    r.rightStats:SetText("|cff38bdf8" .. row.statsText .. "|r")
                end
                r.bg:SetTexture(0.00, 0.00, 0.00, (i % 2 == 0) and 0.42 or 0.22)
                r:Show()
            else
                r.rowData = nil
                r:Hide()
            end
        end
    end

    local function CreateTopWindow()
        if topFrame then return topFrame end

        local f = CreateFrame("Frame", "TalorianTopFrame", UIParent)
        f:SetSize(680, 528)
        f:SetPoint("CENTER", 0, 0)
        f:SetFrameStrata("HIGH")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self._userMoved = true end)
        PS.ApplyWindow(f)
        RegisterSpecialFrame("TalorianTopFrame")

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOPLEFT", 16, -14)
        title:SetText("|cfffce08cТоп рекомендаций по поглощению (AttuneParser)|r")

        local closeBtn = CreateFrame("Button", nil, f)
        closeBtn:SetSize(24, 24)
        closeBtn:SetPoint("TOPRIGHT", -10, -10)
        local cbTxt = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cbTxt:SetPoint("CENTER", 0, 0)
        cbTxt:SetText("|cffffffffX|r")
        PS.StyleClose(closeBtn, 24)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        local openAtlasBtn = CreateFrame("Button", nil, f)
        openAtlasBtn:SetSize(164, 22)
        openAtlasBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
        PS.StyleBtn(openAtlasBtn, "dark")
        local oaTxt = openAtlasBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        oaTxt:SetPoint("CENTER", 0, 0)
        oaTxt:SetText("|cffffd200Открыть Атлас Поглощения|r")
        openAtlasBtn:SetScript("OnClick", function()
            if rawget(_G, "AttuneAtlas_Toggle") then
                AttuneAtlas_Toggle()
                local af = rawget(_G, "AttuneAtlasFrame")
                if af and af:IsShown() then RaiseFrameFront(af) end
            else
                DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Встроенный Атлас поглощения недоступен.")
            end
        end)

        local claimBtn = CreateFrame("Button", nil, f)
        claimBtn:SetSize(134, 22)
        claimBtn:SetPoint("RIGHT", openAtlasBtn, "LEFT", -6, 0)
        PS.StyleBtn(claimBtn, "green")
        local clTxt = claimBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        clTxt:SetPoint("CENTER", 0, 0)
        clTxt:SetText("|cff40ff40Забрать вехи|r")
        claimBtn.txt = clTxt
        claimBtn:SetScript("OnClick", function()
            local ap = rawget(_G, "AttuneParser")
            if ap and ap.ClaimAllMilestones then
                local n = ap:ClaimAllMilestones()
                DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Отправлено запросов на награды вех: " .. n)
            end
        end)
        claimBtn:Hide()
        f.claimBtn = claimBtn

        local subNote = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subNote:SetPoint("TOPLEFT", 16, -38)
        f.subNote = subNote

        -- Строка статуса Дара дня, запасов пыли и фильтров Дара Среды / КД
        local giftBar = CreateFrame("Frame", nil, f)
        giftBar:SetPoint("TOPLEFT", 16, -56)
        giftBar:SetSize(648, 22)
        giftBar:EnableMouse(true)
        PS.StyleBox(giftBar, 0.48)

        local giftTxt = giftBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        giftTxt:SetPoint("LEFT", 8, 0)
        giftTxt:SetPoint("RIGHT", -232, 0)
        giftTxt:SetJustifyH("LEFT")
        if giftTxt.SetWordWrap then giftTxt:SetWordWrap(false) end

        local noCdBtn = CreateFrame("Button", nil, giftBar)
        noCdBtn:SetSize(104, 18)
        noCdBtn:SetPoint("RIGHT", -4, 0)
        PS.StyleBtn(noCdBtn, "dark")
        local ncdTxt = noCdBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ncdTxt:SetPoint("CENTER", 0, 0)
        noCdBtn.txt = ncdTxt

        local wedBtn = CreateFrame("Button", nil, giftBar)
        wedBtn:SetSize(118, 18)
        wedBtn:SetPoint("RIGHT", noCdBtn, "LEFT", -6, 0)
        PS.StyleBtn(wedBtn, "dark")
        local wdTxt = wedBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        wdTxt:SetPoint("CENTER", 0, 0)
        wdTxt:SetText("Дар Среды: Ковка")
        wedBtn.txt = wdTxt

        local function PaintFilterPills()
            if topOpt.wedMode then
                PS.PaintBtn(wedBtn, "gold", { 0.88, 0.70, 1.0 })
                wedBtn.txt:SetTextColor(1, 0.90, 1, 1)
            else
                PS.PaintBtn(wedBtn, "dark")
                wedBtn.txt:SetTextColor(0.82, 0.78, 0.68, 1)
            end
            if topOpt.onlyUnlocked then
                PS.PaintBtn(noCdBtn, "green")
                noCdBtn.txt:SetText("Без КД: ВКЛ")
                noCdBtn.txt:SetTextColor(0.75, 1, 0.80, 1)
            else
                PS.PaintBtn(noCdBtn, "dark")
                noCdBtn.txt:SetText("Без КД: ВСЕ")
                noCdBtn.txt:SetTextColor(0.82, 0.78, 0.68, 1)
            end
        end

        wedBtn:SetScript("OnClick", function()
            topOpt.wedMode = not topOpt.wedMode
            topOpt.wedAutoInit = true
            PaintFilterPills()
            if f.scrollFrame then f.scrollFrame.offset = 0; f.scrollFrame._offset = 0 end
            if type(FauxScrollFrame_SetOffset) == "function" then FauxScrollFrame_SetOffset(f.scrollFrame, 0) end
            RefreshTopDisplay()
        end)
        wedBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Приоритет под «Дар Среды»", 0.73, 0.48, 0.91)
            GameTooltip:AddLine("Поднимает инсты с максимальным числом недокованных вещей (не на Титанике) и без КД для ловли высокой ковки с дропа.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        wedBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        noCdBtn:SetScript("OnClick", function()
            topOpt.onlyUnlocked = not topOpt.onlyUnlocked
            PaintFilterPills()
            if f.scrollFrame then f.scrollFrame.offset = 0; f.scrollFrame._offset = 0 end
            if type(FauxScrollFrame_SetOffset) == "function" then FauxScrollFrame_SetOffset(f.scrollFrame, 0) end
            RefreshTopDisplay()
        end)
        noCdBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Фильтр по КД", 0.3, 1, 0.4)
            GameTooltip:AddLine("Скрывает рейды и героики с уже сохранённым КД.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        noCdBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        giftBar:SetScript("OnEnter", function(self)
            local ap = rawget(_G, "AttuneParser")
            if not ap then return end
            local g = ap.GetActiveDailyGift and ap:GetActiveDailyGift(true) or nil
            local stk = ap.GetForgeMaterialStock and ap:GetForgeMaterialStock() or nil
            local eq = ap.GetEquippedAttuneProgress and ap:GetEquippedAttuneProgress() or nil
            local par = ap.GetParagonInfo and ap:GetParagonInfo() or nil
            local sp = ap.GetPlayerSpecInfo and ap:GetPlayerSpecInfo() or nil
            local as = ap.GetAutoSwapSummary and ap:GetAutoSwapSummary() or nil
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(g and g.active and (g.name .. " (ост. " .. (g.remText or "?") .. ")") or "Дар недели не активен", 0.38, 0.75, 0.98)
            if g and g.desc and g.desc ~= "" then
                GameTooltip:AddLine(g.desc, 1, 0.85, 0.3, true)
            end
            if stk then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Запасы ковки:", string.format("Мерцающая: %d  Пылающая: %d  Астральная: %d  Сундуки: %d", stk.dustEpic or 0, stk.dustLeg or 0, stk.dustTit or 0, stk.titanBoxes or 0), 0.85, 0.85, 0.85, 1, 1, 1)
                if (stk.epicToLeg or 0) > 0 or (stk.craftableTit or 0) > 0 then
                    GameTooltip:AddDoubleLine("Обмен пыли 3:1:", string.format("->Пылающая:+%d, ->Астральная:+%d (Всего Титаническая: %d)", stk.epicToLeg or 0, stk.craftableTit or 0, stk.totalTitPotential or 0), 0.8, 0.85, 0.95, 0.3, 1, 0.85)
                end
                if (stk.frostEmblem or 0) > 0 or (stk.frostFromLowerEmblems or 0) > 0 then
                    GameTooltip:AddDoubleLine("Эмблемы Льда:", string.format("%d (+%d из низших эмблем = %d)", stk.frostEmblem or 0, stk.frostFromLowerEmblems or 0, stk.totalFrostPotential or 0), 0.8, 0.85, 0.95, 0.65, 0.85, 1)
                end
            end
            if eq then
                local multStr = (math.floor((eq.xpMult or 1) * 100 + 0.5) % 100 == 0)
                    and string.format("x%d", math.floor((eq.xpMult or 1) + 0.5))
                    or string.format("x%.2f", eq.xpMult or 1)
                local gSuffix = ((eq.guildPct or 0) > 0) and string.format(", Ги+%d%%", eq.guildPct) or ""
                GameTooltip:AddDoubleLine("Надето в прокачке:", string.format("%d предм. (опыт %s%s, ~%d об. / %d данж-кв.)", eq.count or 0, multStr, gSuffix, eq.questsToFinishAllNormal or 0, eq.questsToFinishAllDungeon or 0), 0.85, 0.85, 0.85, 0.4, 1, 0.5)
                if eq.worldLocked80 then
                    GameTooltip:AddLine("Внимание: открыт блок опыта мира 80 ур.!", 1, 0.55, 0.25)
                end
            end
            if par and par.loaded and (par.level or 0) > 0 then
                GameTooltip:AddDoubleLine("Доп. уровень:", string.format("Уровень %d (%d / %d XP, %d%%)", par.level, par.curXP or 0, par.maxXP or 0, par.pct or 0), 0.85, 0.85, 0.95, 1, 0.82, 0.3)
            end
            if sp and sp.specName and sp.specName ~= "" then
                GameTooltip:AddDoubleLine("Специализация:", sp.specName .. (sp.isCustomLegion and " (Prime Legion)" or ""), 0.85, 0.85, 0.95, 0.75, 0.9, 1)
            end
            if as and (as.on ~= nil or (as.blacklistCount or 0) > 0) then
                local stLbl = (as.on == true) and "|cff40ff40ВКЛ|r" or ((as.on == false) and "|cffff6060ВЫКЛ|r" or "?")
                GameTooltip:AddDoubleLine("Автопоглощение:", string.format("%s | В черном списке: %d", stLbl, as.blacklistCount or 0), 0.85, 0.85, 0.95, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        giftBar:SetScript("OnLeave", function() GameTooltip:Hide() end)

        f.UpdateGiftBar = function(gift)
            PaintFilterPills()
            local ap = rawget(_G, "AttuneParser")
            local stk = (ap and ap.GetForgeMaterialStock) and ap:GetForgeMaterialStock() or nil
            local craftTag = (stk and (stk.craftableTit or 0) > 0) and string.format("(+%d)", stk.craftableTit) or ""
            local stkStr = stk and string.format("  |cff94a3b8Пыль:|r |cffbb79e8Мерц:%d|r |cffff8000Пыл:%d|r |cff00ffccАстр:%d%s|r  |cff94a3b8Сундук:|r |cff00ffcc%d|r", stk.dustEpic or 0, stk.dustLeg or 0, stk.dustTit or 0, craftTag, stk.titanBoxes or 0) or ""
            if gift and gift.active then
                local gCol = gift.isWednesday and "|cffbb79e8" or (gift.isThursday and "|cff40ff40") or (gift.isSaturday and "|cff38bdf8") or "|cffffd200"
                local extra = ""
                if gift.isThursday then
                    extra = " (100% возвр.)"
                elseif gift.isSaturday then
                    extra = string.format(" (опыт x%d)", gift.xpMult or 2)
                elseif gift.remText then
                    extra = " (" .. gift.remText .. ")"
                end
                giftTxt:SetText(gCol .. (gift.name or "Дар дня") .. "|r" .. extra .. stkStr)
            else
                giftTxt:SetText("|cff94a3b8Нет Дара дня|r" .. stkStr)
            end
        end
        PaintFilterPills()

        local tabBar = CreateFrame("Frame", nil, f)
        tabBar:SetPoint("TOPLEFT", 16, -84)
        tabBar:SetSize(648, 24)
        local modeDefs = {
            { id = "new",      label = "Новые вещи" },
            { id = "forge",    label = "Ковка до 90%" },
            { id = "combined", label = "Общий топ" },
            { id = "noreq",    label = "Вещи без ур. (1 ур.)" },
        }
        local mBtns = {}
        local function UpdateTopModeButtons()
            for _, b in ipairs(mBtns) do
                if b.modeId == topMode then
                    PS.PaintBtn(b, "gold")
                    b.txt:SetTextColor(1, 0.88, 0.45, 1)
                else
                    PS.PaintBtn(b, "dark")
                    b.txt:SetTextColor(0.82, 0.78, 0.68, 1)
                end
            end
        end
        local mx = 0
        for _, md in ipairs(modeDefs) do
            local mb = CreateFrame("Button", nil, tabBar)
            mb:SetSize(159, 22)
            mb:SetPoint("LEFT", mx, 0)
            PS.StyleBtn(mb, "dark")
            local mt = mb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            mt:SetPoint("CENTER", 0, 0)
            mt:SetText(md.label)
            mb.txt = mt
            mb.modeId = md.id
            mb:SetScript("OnClick", function()
                topMode = md.id
                UpdateTopModeButtons()
                if f.scrollFrame then f.scrollFrame.offset = 0; f.scrollFrame._offset = 0 end
                if type(FauxScrollFrame_SetOffset) == "function" then FauxScrollFrame_SetOffset(f.scrollFrame, 0) end
                RefreshTopDisplay()
            end)
            mb:SetScript("OnEnter", function(self)
                if self.modeId ~= topMode then
                    self.txt:SetTextColor(1, 0.94, 0.75, 1)
                end
            end)
            mb:SetScript("OnLeave", function()
                UpdateTopModeButtons()
            end)
            table.insert(mBtns, mb)
            mx = mx + 163
        end
        UpdateTopModeButtons()

        local scrollBox = CreateFrame("Frame", nil, f)
        scrollBox:SetPoint("TOPLEFT", 16, -114)
        scrollBox:SetPoint("BOTTOMRIGHT", -16, 44)
        PS.StyleBox(scrollBox, 0.42)

        local sf
        sf = PS.AttachScroll(scrollBox, 14 * 24, 24, 14, function(off)
            if sf and not sf._skipRender then
                sf._offset = off
                RefreshTopDisplay()
            end
        end, "TalorianTopScrollFrame")
        sf:SetPoint("TOPLEFT", scrollBox, "TOPLEFT", 2, -2)
        sf:SetPoint("BOTTOMRIGHT", scrollBox, "BOTTOMRIGHT", -4, 2)
        sf._offset = 0
        f.scrollFrame = sf

        scrollBox:EnableMouseWheel(true)
        scrollBox:SetScript("OnMouseWheel", function(_, delta)
            if sf._OnWheel then sf:_OnWheel(delta) end
        end)

        local rows = {}
        for i = 1, 14 do
            local r = CreateFrame("Button", nil, scrollBox)
            r:SetSize(620, 22)
            r:SetPoint("TOPLEFT", 4, -(i - 1) * 24 - 4)
            r.rowIdx = i

            local rbg = r:CreateTexture(nil, "BACKGROUND")
            rbg:SetAllPoints()
            r.bg = rbg

            local ric = r:CreateTexture(nil, "ARTWORK")
            ric:SetSize(18, 18)
            ric:SetPoint("LEFT", 4, 0)
            r.icon = ric

            local rtitle = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rtitle:SetPoint("LEFT", ric, "RIGHT", 6, 0)
            rtitle:SetPoint("RIGHT", r, "RIGHT", -235, 0)
            rtitle:SetJustifyH("LEFT")
            if rtitle.SetWordWrap then rtitle:SetWordWrap(false) end
            r.title = rtitle

            local rmain = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rmain:SetPoint("RIGHT", r, "RIGHT", -102, 0)
            rmain:SetJustifyH("RIGHT")
            r.rightMain = rmain

            local rstats = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rstats:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            rstats:SetJustifyH("RIGHT")
            r.rightStats = rstats

            r:SetScript("OnClick", function(self)
                local rd = self.rowData
                if rd and rd.dest then
                    SelectDestInTalorianUI(rd.dest)
                elseif rd and rd.kind == "zone" then
                    DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. "Зона \"" .. rd.zoneName .. "\" не входит в быстрый список телепорта Талориана.")
                end
            end)
            r:SetScript("OnEnter", function(self)
                local rd = self.rowData
                if not rd then return end
                self.bg:SetTexture(0.16, 0.12, 0.20, 0.90)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                local ap = rawget(_G, "AttuneParser")
                if rd.kind == "item" and rd.itemId then
                    if ap and ap.RequestItemSources then
                        ap:RequestItemSources(rd.itemId)
                    end
                    if not (InCombatLockdown and InCombatLockdown()) then
                        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. rd.itemId)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(rd.statusText .. "  " .. rd.statsText, 1, 1, 1)
                    local srcMeta = (ap and ap.GetItemSources) and ap:GetItemSources(rd.itemId) or nil
                    local srcs = (srcMeta and srcMeta.list) or rd.sources
                    if srcs and #srcs > 0 then
                        GameTooltip:AddLine((srcMeta and srcMeta.hasServerSources) and "Источники (сервер):" or "Источники:", 0.22, 0.74, 0.97)
                        local stMap = (ap and ap.SOURCE_TYPES) or {}
                        for si = 1, math.min(4, #srcs) do
                            local sc = srcs[si]
                            local tLbl = stMap[sc.st] or "Источник"
                            local nLbl = (sc.name and sc.name ~= "" and sc.name) or ""
                            local zLbl = (sc.zoneName and sc.zoneName ~= "" and sc.zoneName) or ""
                            local chStr = (ap and ap.FormatChance) and ap.FormatChance(sc.chance) or nil
                            local rightParts = {}
                            if zLbl ~= "" then table.insert(rightParts, zLbl) end
                            if chStr then table.insert(rightParts, chStr) end
                            if sc.st == 4 and (sc.qChainLen or 0) > 1 then
                                table.insert(rightParts, string.format("цеп.%d/%d (вып.%d)", sc.qPos or 1, sc.qChainLen, sc.qChainDone or 0))
                            end
                            if sc.qDone then table.insert(rightParts, "|cff40ff40выполнен|r") end
                            GameTooltip:AddDoubleLine(
                                "  " .. tLbl .. (nLbl ~= "" and (": " .. nLbl) or ""),
                                #rightParts > 0 and table.concat(rightParts, ", ") or "",
                                0.9, 0.9, 0.9, 0.75, 0.82, 0.92
                            )
                            if sc.st == 4 and (sc.qGiver or sc.qStartGiver) then
                                local fTag = (sc.qFaction == "A" and " [Альянс]") or (sc.qFaction == "H" and " [Орда]") or ""
                                local gLine = "    Выдает: " .. (sc.qGiver or sc.qStartGiver) .. fTag
                                if sc.qStartGiver and sc.qGiver and sc.qStartGiver ~= sc.qGiver then
                                    gLine = gLine .. " | Начало: " .. sc.qStartGiver
                                end
                                if (sc.qChainLen or 0) > 1 and sc.qNextName then
                                    gLine = gLine .. " | След.: " .. sc.qNextName
                                end
                                GameTooltip:AddLine(gLine, 0.65, 0.82, 0.95, true)
                            end
                        end
                    end
                    local g = ap and ap.GetActiveDailyGift and ap:GetActiveDailyGift() or nil
                    if g and g.isThursday and rd.hasVendor then
                        GameTooltip:AddLine("Дар Четверга: 100% возврат золота торговцу сегодня!", 0.2, 1, 0.4)
                    end
                    if ap and ap.IsItemBlacklisted and ap:IsItemBlacklisted(rd.itemId) then
                        GameTooltip:AddLine("Предмет в черном списке автопродажи!", 1, 0.4, 0.4)
                    end
                    if rd.dest then
                        GameTooltip:AddLine("Клик: выбрать целью " .. rd.dest.name, 0.2, 1, 0.4)
                    end
                    GameTooltip:Show()
                elseif rd.kind == "zone" and rd.za then
                    if ap and ap.RequestZoneSync and rd.zoneId then
                        ap:RequestZoneSync(rd.zoneId)
                    end
                    local za = rd.za
                    GameTooltip:AddLine(rd.zoneName, 1, 1, 1)
                    GameTooltip:AddLine(rd.subLabel, 0.4, 0.75, 1)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddDoubleLine("Новые вещи:", string.format("|cff40ff40%d шт.|r (до +%s статов)", za.newCount or 0, FormatStatValue(za.newMaxStats or 0)), 0.9, 0.9, 0.9, 1, 1, 1)
                    GameTooltip:AddDoubleLine("Ковка до 90%:", string.format("|cffffd200%d шт.|r (+%s статов осталось)", za.forgeCount or 0, FormatStatValue(za.forgeRemainStats or 0)), 0.9, 0.9, 0.9, 1, 1, 1)
                    if za.bestProgressItem then
                        GameTooltip:AddDoubleLine("Почти готово:", string.format("|cffffd200%s (%d%%)|r", za.bestProgressItem.name or "", za.bestProgressItem.pct or 0), 0.85, 0.85, 0.85, 1, 1, 1)
                    end
                    if (za.noReqCount or 0) > 0 then
                        GameTooltip:AddDoubleLine("Вещи 1 ур.:", "|cff66ffcc" .. za.noReqCount .. " шт.|r", 0.8, 0.8, 0.8, 1, 1, 1)
                    end
                    if rd.dest then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Клик: выбрать целью в TalorianTP", 0.2, 1, 0.4)
                    end
                    GameTooltip:Show()
                end
            end)
            r:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                self.bg:SetTexture(0.00, 0.00, 0.00, (self.rowIdx % 2 == 0) and 0.42 or 0.22)
            end)

            table.insert(rows, r)
        end
        f.rows = rows

        local syncBtn = CreateFrame("Button", nil, f)
        syncBtn:SetSize(185, 24)
        syncBtn:SetPoint("BOTTOMLEFT", 16, 12)
        PS.StyleBtn(syncBtn, "dark")
        local syTxt = syncBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        syTxt:SetPoint("CENTER", 0, 0)
        syTxt:SetText("|cfff7dfb5Синхронизировать с сервером|r")
        syncBtn:SetScript("OnClick", function()
            local ap = rawget(_G, "AttuneParser")
            if ap and ap.RequestServerSync then
                ap:InvalidateCaches(false)
                ap:RequestServerSync(true)
            end
            RefreshTopDisplay()
        end)

        local refBtn = CreateFrame("Button", nil, f)
        refBtn:SetSize(120, 24)
        refBtn:SetPoint("BOTTOMRIGHT", -16, 12)
        PS.StyleBtn(refBtn, "dark")
        local rfTxt = refBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rfTxt:SetPoint("CENTER", 0, 0)
        rfTxt:SetText("|cfff7dfb5Обновить|r")
        refBtn:SetScript("OnClick", function()
            local ap = rawget(_G, "AttuneParser")
            if ap and ap.InvalidateCaches then ap:InvalidateCaches(false) end
            RefreshTopDisplay()
        end)

        f:Hide()
        topFrame = f
        return f
    end

    function TalorianTP_RefreshTopLive()
        if topFrame and topFrame:IsShown() then
            RefreshTopDisplay()
        end
    end

    function TalorianTP_ToggleTopWindow()
        local f = CreateTopWindow()
        if f:IsShown() then
            f:Hide()
        else
            f:Show()
            RaiseFrameFront(f)
            RefreshTopDisplay()
            local ap = rawget(_G, "AttuneParser")
            if ap and ap.QueuePriorityZonesSync and topMode ~= "noreq" then
                local ids = {}
                for i = 1, math.min(5, #topRowsData) do
                    local rd = topRowsData[i]
                    if rd and rd.kind == "zone" and rd.zoneId then
                        table.insert(ids, rd.zoneId)
                    end
                end
                ap:QueuePriorityZonesSync(ids)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Компактная панель ковки у аукциона + сводка обмена/осмотра (без taint)
---------------------------------------------------------------------------
do
    local aucFrame = nil
    local aucRows = {}
    local aucHookedBlizz = false
    local aucHookedPrime = false
    local aucBtn = nil
    local aucForceOpen = false
    local aucOpenByEvent = false
    local lastTradeAlertKey = nil
    local TIER_COLORS = {
        [0] = "|cff40ff40[Баз]|r",
        [1] = "|cffbb79e8[Эпик]|r",
        [2] = "|cffff8000[Лег]|r",
        [3] = "|cff00ffff[Титан]|r",
    }

    local function FormatCopper(c)
        c = tonumber(c) or 0
        if c <= 0 then return "|cff888888нет выкупа|r" end
        local g = math.floor(c / 10000)
        local s = math.floor((c % 10000) / 100)
        if g > 0 then
            return string.format("|cffffd200%dз|r |cffcccccc%02dс|r", g, s)
        elseif s > 0 then
            return string.format("|cffcccccc%dс|r", s)
        end
        return string.format("|cffcc8855%dм|r", c % 100)
    end

    local function GetActiveAuctionAnchor()
        local pah = rawget(_G, "PrimeAH")
        if pah and pah.frame and pah.frame.IsShown and pah.frame:IsShown() then
            return pah.frame, true
        end
        if _G.AuctionFrame and _G.AuctionFrame.IsShown and _G.AuctionFrame:IsShown() then
            return _G.AuctionFrame, false
        end
        if _G.AuctionFrameBrowse and _G.AuctionFrameBrowse.IsShown and _G.AuctionFrameBrowse:IsShown() then
            return _G.AuctionFrameBrowse, false
        end
        return nil, false
    end

    local function PaintPanelBtnTextures(b)
        if not b or not b.Left then return end
        local tex = b.down and b._dnTex or b._upTex
        b.Left:SetTexture(tex)
        b.Middle:SetTexture(tex)
        b.Right:SetTexture(tex)
    end

    local function ApplyAuctionButtonSkin(b)
        b._upTex = "Interface\\PrimeAH\\Buttons\\UI-Panel-Button-Up"
        b._dnTex = "Interface\\PrimeAH\\Buttons\\UI-Panel-Button-Down"
        b._hlTex = "Interface\\PrimeAH\\Buttons\\UI-Panel-Button-Highlight"

        b.Left = b:CreateTexture(nil, "BACKGROUND")
        b.Left:SetWidth(12)
        b.Left:SetPoint("TOPLEFT")
        b.Left:SetPoint("BOTTOMLEFT")
        b.Left:SetTexCoord(0, 0.09375, 0, 0.6875)

        b.Right = b:CreateTexture(nil, "BACKGROUND")
        b.Right:SetWidth(12)
        b.Right:SetPoint("TOPRIGHT")
        b.Right:SetPoint("BOTTOMRIGHT")
        b.Right:SetTexCoord(0.53125, 0.625, 0, 0.6875)

        b.Middle = b:CreateTexture(nil, "BACKGROUND")
        b.Middle:SetPoint("TOPLEFT", b.Left, "TOPRIGHT")
        b.Middle:SetPoint("BOTTOMRIGHT", b.Right, "BOTTOMLEFT")
        b.Middle:SetTexCoord(0.09375, 0.53125, 0, 0.6875)

        local ok = b.Left:SetTexture(b._upTex)
        if not ok or not b.Left:GetTexture() then
            b._upTex = "Interface\\Buttons\\UI-Panel-Button-Up"
            b._dnTex = "Interface\\Buttons\\UI-Panel-Button-Down"
            b._hlTex = "Interface\\Buttons\\UI-Panel-Button-Highlight"
        end
        PaintPanelBtnTextures(b)

        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        local okHl = hl:SetTexture(b._hlTex)
        if not okHl or not hl:GetTexture() then
            hl:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
        end
        hl:SetTexCoord(0, 0.625, 0, 0.6875)
        hl:SetBlendMode("ADD")
        hl:SetAllPoints(b)
        b:SetHighlightTexture(hl)
    end

    local function CreateAuctionHelperFrame()
        if aucFrame then return aucFrame end
        local f = CreateFrame("Frame", "TalorianAuctionFrame", UIParent)
        f:SetSize(296, 356)
        f:SetFrameStrata("HIGH")
        f:SetToplevel(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self._userMoved = true end)
        PS.ApplyWindow(f)
        RegisterSpecialFrame("TalorianAuctionFrame")

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("|cfffce08cАукцион: поглощение|r")

        local closeBtn = CreateFrame("Button", nil, f)
        closeBtn:SetSize(22, 22)
        closeBtn:SetPoint("TOPRIGHT", -6, -6)
        local cx = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cx:SetPoint("CENTER", 0, 0)
        cx:SetText("X")
        PS.StyleClose(closeBtn, 22)
        closeBtn:SetScript("OnClick", function()
            TalorianTP_DB = TalorianTP_DB or {}
            TalorianTP_DB.hideAuctionPanel = true
            aucForceOpen = false
            f:Hide()
        end)

        local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("TOPLEFT", 10, -28)
        sub:SetWidth(276)
        sub:SetJustifyH("LEFT")
        f.sub = sub

        local maxRows = 10
        for i = 1, maxRows do
            local r = CreateFrame("Button", nil, f)
            r:SetSize(276, 26)
            r:SetPoint("TOPLEFT", 10, -48 - (i - 1) * 28)
            r.rowIdx = i

            local bg = r:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture(0.14, 0.12, 0.10, (i % 2 == 0) and 0.65 or 0.35)
            r.bg = bg

            local ic = r:CreateTexture(nil, "ARTWORK")
            ic:SetSize(20, 20)
            ic:SetPoint("LEFT", 3, 0)
            r.icon = ic

            local nm = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nm:SetPoint("TOPLEFT", ic, "TOPRIGHT", 6, 0)
            nm:SetPoint("RIGHT", r, "RIGHT", -96, 0)
            nm:SetJustifyH("LEFT")
            if nm.SetWordWrap then nm:SetWordWrap(false) end
            r.nameTxt = nm

            local inf = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            inf:SetPoint("BOTTOMLEFT", ic, "BOTTOMRIGHT", 6, 0)
            inf:SetPoint("RIGHT", r, "RIGHT", -96, 0)
            inf:SetJustifyH("LEFT")
            if inf.SetWordWrap then inf:SetWordWrap(false) end
            r.infoTxt = inf

            local rTop = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rTop:SetPoint("TOPRIGHT", -4, -1)
            rTop:SetJustifyH("RIGHT")
            r.gainTxt = rTop

            local rBot = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rBot:SetPoint("BOTTOMRIGHT", -4, 1)
            rBot:SetJustifyH("RIGHT")
            r.priceTxt = rBot

            r:SetScript("OnEnter", function(self)
                local cd = self.candData
                if not cd then return end
                self.bg:SetTexture(0.32, 0.25, 0.14, 0.90)
                if InCombatLockdown and InCombatLockdown() then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                if cd.auctionIndex and type(GetAuctionItemInfo) == "function" and GetAuctionItemInfo("list", cd.auctionIndex) then
                    pcall(GameTooltip.SetAuctionItem, GameTooltip, "list", cd.auctionIndex)
                elseif cd.link then
                    pcall(GameTooltip.SetHyperlink, GameTooltip, cd.link)
                end
                GameTooltip:AddLine(" ")
                if cd.needsForgeCheck then
                    GameTooltip:AddDoubleLine(
                        "Статус поглощения:",
                        string.format("Ковка (%s -> 90%%, до +%s статов)", cd.doneTierName or "", FormatStatValue(cd.remainStats or 0)),
                        0.95, 0.88, 0.72, 1, 0.82, 0.2
                    )
                    GameTooltip:AddLine("Откройте предмет, чтобы проверить тир ковки конкретных лотов.", 0.85, 0.82, 0.75, true)
                else
                    GameTooltip:AddDoubleLine(
                        "Апгрейд ковки:",
                        string.format("%s (+%d%% -> +%s статов)", cd.lotTierName or "?", cd.gainNowPct or 0, FormatStatValue(cd.gainNowStats or 0)),
                        0.95, 0.88, 0.72, 0.25, 1, 0.5
                    )
                    if (cd.remainStats or 0) > (cd.gainNowStats or 0) then
                        GameTooltip:AddDoubleLine("Потенциал до 90%:", "+" .. FormatStatValue(cd.fullMaxStats or cd.remainStats or 0) .. " статов", 0.85, 0.82, 0.75, 0.38, 0.75, 0.98)
                    end
                end
                local ap = rawget(_G, "AttuneParser")
                if ap and ap.IsItemBlacklisted and ap:IsItemBlacklisted(cd.itemId, cd.lotTier) then
                    GameTooltip:AddLine("Предмет в черном списке автопродажи!", 1, 0.4, 0.4)
                end
                if cd.primeRow then
                    GameTooltip:AddLine("Клик: открыть лоты | Shift+клик: ссылка", 0.4, 1, 0.5)
                else
                    GameTooltip:AddLine("Клик: подставить имя в поиск | Shift+клик: ссылка", 0.8, 0.75, 0.65)
                end
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                self.bg:SetTexture(0.14, 0.12, 0.10, (self.rowIdx % 2 == 0) and 0.65 or 0.35)
            end)
            r:SetScript("OnClick", function(self)
                local cd = self.candData
                if not cd then return end
                if IsModifiedClick and IsModifiedClick("CHATLINK") and cd.itemId then
                    local ap = rawget(_G, "AttuneParser")
                    if ap and ap.InsertItemLink then
                        ap:InsertItemLink(cd.itemId, cd.link, cd.name, cd.quality)
                    elseif cd.link and type(ChatEdit_InsertLink) == "function" then
                        ChatEdit_InsertLink(cd.link)
                    end
                    return
                end
                local pah = rawget(_G, "PrimeAH")
                if pah and pah.frame and pah.frame:IsShown() then
                    if cd.primeLot and pah.panels and pah.panels.itemBuy and pah.panels.itemBuy:IsShown() and pah.panels.itemBuy.Select then
                        pcall(pah.panels.itemBuy.Select, pah.panels.itemBuy, cd.primeLot)
                        return
                    elseif cd.primeRow then
                        if cd.commodity and pah.ShowCommodityBuy then
                            pcall(pah.ShowCommodityBuy, cd.primeRow)
                        elseif pah.ShowItemBuy then
                            pcall(pah.ShowItemBuy, cd.primeRow)
                        end
                        return
                    end
                end
                if _G.BrowseName and _G.BrowseName:IsVisible() and cd.name then
                    _G.BrowseName:SetText(cd.name)
                end
            end)
            r:Hide()
            aucRows[i] = r
        end

        local foot = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        foot:SetPoint("BOTTOMLEFT", 10, 8)
        foot:SetText("|cffb0a080/ttp auc | /ttp aucreset - сброс позиции|r")

        f:Hide()
        aucFrame = f
        return f
    end

    local function UpdatePrimeRowBadges()
        local pah = rawget(_G, "PrimeAH")
        if not (pah and pah.browse and pah.browse.list and type(pah.browse.list.rows) == "table") then return end
        local ap = rawget(_G, "AttuneParser")
        if not (ap and ap.GetItemInfo) then return end
        for _, row in ipairs(pah.browse.list.rows) do
            if row and row:IsShown() and row.data and row.data.entry and row.cells and row.cells[4] then
                local d = row.data
                local lk = "item:" .. d.entry .. ":0:0:0:0:0:" .. (d.randProp or 0)
                local usable, accOk = ap:CanHeroAbsorb(d.entry, lk)
                local badgeTxt = nil
                if usable then
                    local info = ap:GetItemInfo(d.entry, lk)
                    if info and not info.isCompleted then
                        if ap.IsItemBlacklisted and ap:IsItemBlacklisted(d.entry) then
                            badgeTxt = "|cffff6060ЧС|r"
                        elseif info.isNew then
                            badgeTxt = string.format("|cff40ff40+%d%%|r", info.newBasePct or 20)
                        else
                            badgeTxt = "|cffffd200<90%|r"
                        end
                    end
                elseif accOk then
                    local info = ap:GetItemInfo(d.entry, lk)
                    if info and not info.isCompleted then
                        badgeTxt = "|cff38bdf8Тв|r"
                    end
                end
                if badgeTxt then
                    if not row._ttpBadge then
                        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        fs:SetJustifyH("RIGHT")
                        row._ttpBadge = fs
                    end
                    local anchorCell = (pah.browse.list.detailKind and row.cells[3]) or row.cells[4]
                    row._ttpBadge:ClearAllPoints()
                    row._ttpBadge:SetPoint("RIGHT", anchorCell, "LEFT", -4, 0)
                    row._ttpBadge:SetText(badgeTxt)
                    row._ttpBadge:Show()
                elseif row._ttpBadge then
                    row._ttpBadge:Hide()
                end
            elseif row and row._ttpBadge then
                row._ttpBadge:Hide()
            end
        end
    end

    local function PositionAuctionButton(b, anchor)
        local pos = TalorianTP_DB and TalorianTP_DB.aucBtnPos
        if pos and pos.pt then
            b:ClearAllPoints()
            b:SetPoint(pos.pt, UIParent, pos.relPt or pos.pt, pos.x or 0, pos.y or 0)
            return
        end
        b:ClearAllPoints()
        if anchor then
            local bottomY = anchor.GetBottom and anchor:GetBottom() or 60
            if bottomY >= 34 then
                b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 315, -3)
            else
                b:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -32, -2)
            end
        else
            b:SetPoint("TOP", UIParent, "TOP", 180, -24)
        end
    end

    local function EnsureAuctionButton(candsCount, newCount, anchor)
        if not aucBtn then
            local b = CreateFrame("Button", "TalorianAuctionButton", UIParent)
            b:SetSize(146, 24)
            b:SetFrameStrata("DIALOG")
            b:SetFrameLevel(42)
            b:SetClampedToScreen(true)
            b:SetMovable(true)
            b:RegisterForClicks("LeftButtonUp")
            b:RegisterForDrag("RightButton")
            ApplyAuctionButtonSkin(b)

            local bt = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            bt:SetPoint("CENTER", 0, 0)
            b.txt = bt

            b:SetScript("OnMouseDown", function(self, btn)
                if btn == "LeftButton" then
                    self.down = true
                    PaintPanelBtnTextures(self)
                end
            end)
            b:SetScript("OnMouseUp", function(self)
                self.down = nil
                PaintPanelBtnTextures(self)
            end)
            b:SetScript("OnDragStart", function(self)
                self:StartMoving()
            end)
            b:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                local pt, _, relPt, x, y = self:GetPoint()
                if pt then
                    TalorianTP_DB = TalorianTP_DB or {}
                    TalorianTP_DB.aucBtnPos = { pt = pt, relPt = relPt or pt, x = x or 0, y = y or 0 }
                end
            end)
            b:SetScript("OnClick", function()
                TalorianTP_DB = TalorianTP_DB or {}
                if aucFrame and aucFrame:IsShown() then
                    TalorianTP_DB.hideAuctionPanel = true
                    aucForceOpen = false
                else
                    TalorianTP_DB.hideAuctionPanel = false
                    aucForceOpen = true
                end
                if TalorianTP_RefreshAuctionHelper then TalorianTP_RefreshAuctionHelper() end
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine("TalorianTP: Поглощение аука", 1, 0.82, 0)
                GameTooltip:AddLine("Автономная кнопка для поиска и поглощения вещей на аукционе.", 0.9, 0.9, 0.9, true)
                GameTooltip:AddLine("ЛКМ: открыть/скрыть список", 0.3, 1, 0.4)
                GameTooltip:AddLine("ПКМ + перетащить: переместить (/ttp aucreset - сброс)", 0.75, 0.78, 0.85)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)

            local chkAcc = 0
            b:SetScript("OnUpdate", function(self, el)
                chkAcc = chkAcc + (el or 0)
                if chkAcc < 0.25 then return end
                chkAcc = 0
                if not aucOpenByEvent and not GetActiveAuctionAnchor() then
                    self:Hide()
                    if aucFrame then aucFrame:Hide() end
                end
            end)
            aucBtn = b
        end

        PositionAuctionButton(aucBtn, anchor)
        if (newCount or 0) > 0 then
            aucBtn.txt:SetText(string.format("|cff40ff40Нов: %d|r |cffffd200(%d)|r", newCount, candsCount or 0))
        elseif (candsCount or 0) > 0 then
            aucBtn.txt:SetText(string.format("|cffffd200Поглощение (%d)|r", candsCount))
        else
            aucBtn.txt:SetText("|cffffd200Поглощение аука|r")
        end
        aucBtn:Show()
    end

    local function RefreshAuctionPanel()
        if type(TalorianTP.IsBlockEnabled) == "function" and not TalorianTP:IsBlockEnabled("auctionTrade") then
            if aucFrame then aucFrame:Hide() end
            if aucBtn then aucBtn:Hide() end
            return
        end
        local anchor, isPrime = GetActiveAuctionAnchor()
        local isOpen = (anchor ~= nil) or aucOpenByEvent
        if not isOpen then
            if aucFrame then aucFrame:Hide() end
            if aucBtn then aucBtn:Hide() end
            return
        end

        if isPrime then
            pcall(UpdatePrimeRowBadges)
        end

        local ap = rawget(_G, "AttuneParser")
        local cands = {}
        if ap and ap.GetAuctionForgeCandidates then
            local ok, res = pcall(ap.GetAuctionForgeCandidates, ap)
            if ok and type(res) == "table" then cands = res end
        end
        local newCount = 0
        for _, cd in ipairs(cands) do
            if cd.isNew then newCount = newCount + 1 end
        end

        EnsureAuctionButton(#cands, newCount, anchor)

        local userHid = (TalorianTP_DB and TalorianTP_DB.hideAuctionPanel)
            or (type(TalorianTP.IsBlockEnabled) == "function" and not TalorianTP:IsBlockEnabled("auctionTrade"))
        if userHid or (#cands == 0 and not aucForceOpen) then
            if aucFrame then aucFrame:Hide() end
            return
        end

        local f = CreateAuctionHelperFrame()
        if not f._userMoved then
            f:ClearAllPoints()
            if anchor then
                local rightEdge = anchor.GetRight and anchor:GetRight() or 0
                local scrW = GetScreenWidth and GetScreenWidth() or 1280
                if (scrW - rightEdge) >= 302 then
                    f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, -12)
                elseif isPrime then
                    f:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -10, -76)
                else
                    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -8, -80)
                end
            else
                f:SetPoint("TOP", aucBtn, "BOTTOM", 0, -6)
            end
        end
        f:Show()

        if #cands == 0 then
            f.sub:SetText(isPrime
                and "|cffc8bea8Выполните поиск или выберите категорию для поиска поглощений.|r"
                or  "|cffc8bea8На текущей странице апгрейдов не найдено.|r")
        elseif #cands > #aucRows then
            f.sub:SetText(string.format("|cff40ff40Подходит: %d|r |cffc8bea8(новых: %d, топ-%d)|r", #cands, newCount, #aucRows))
        else
            f.sub:SetText(string.format("|cff40ff40Подходит: %d|r |cffc8bea8(новых: %d)|r", #cands, newCount))
        end

        for i = 1, #aucRows do
            local r = aucRows[i]
            local cd = cands[i]
            if cd then
                r.candData = cd
                r.icon:SetTexture(select(10, GetItemInfo(cd.link or cd.itemId)) or "Interface\\Icons\\INV_Misc_QuestionMark")
                local isBl = ap and ap.IsItemBlacklisted and ap:IsItemBlacklisted(cd.itemId, cd.lotTier)
                local blTag = isBl and " |cffff6060[ЧС]|r" or ""
                r.nameTxt:SetText((cd.name or ("#" .. cd.itemId)) .. blTag)
                local tierLbl = cd.needsForgeCheck
                    and ("|cffffd200[" .. (cd.doneTierName or "Ков") .. "->90%]|r")
                    or  (TIER_COLORS[cd.lotTier or 0] or "|cff40ff40[Нов]|r")
                r.infoTxt:SetText(tierLbl .. string.format(" |cffaaaaaa(ilvl %d)|r", cd.ilvl or 0))
                if cd.needsForgeCheck then
                    r.gainTxt:SetText(string.format("|cffffd200до +%s|r", FormatStatValue(cd.remainStats or 0)))
                else
                    r.gainTxt:SetText(string.format("|cff38bdf8+%d%% / +%s|r", cd.gainNowPct or 0, FormatStatValue(cd.gainNowStats or 0)))
                end
                r.priceTxt:SetText(FormatCopper(cd.buyout or cd.minBid))
                r:Show()
            else
                r.candData = nil
                r:Hide()
            end
        end
    end

    function TalorianTP_RefreshAuctionHelper()
        if not (TalorianTP_DB and TalorianTP_DB.hideAuctionPanel) then
            aucForceOpen = true
        else
            aucForceOpen = false
        end
        RefreshAuctionPanel()
    end

    function TalorianTP_ResetAuctionPos()
        if aucFrame then aucFrame._userMoved = false end
        RefreshAuctionPanel()
    end

    local function ScheduleAuctionRefresh()
        local ap = rawget(_G, "AttuneParser")
        if ap and ap._hasStandaloneAuctionUI then
            local oldB = rawget(_G, "TalorianAuctionButton")
            if oldB then oldB:Hide() end
            local oldF = rawget(_G, "TalorianAuctionFrame")
            if oldF then oldF:Hide() end
            return
        end
        if ap and ap.After then
            ap.After(0.06, RefreshAuctionPanel, "ttp_auc_panel")
        else
            RefreshAuctionPanel()
        end
    end

    local function RegisterParserAuctionCallbacks()
        local ap = rawget(_G, "AttuneParser")
        if ap and ap.RegisterCallback and not ap._ttpAucCbDone then
            ap._ttpAucCbDone = true
            ap:RegisterCallback("AUCTION_FORGE_UPDATED", ScheduleAuctionRefresh)
            ap:RegisterCallback("FORGE_UPDATED", ScheduleAuctionRefresh)
            ap:RegisterCallback("ATTUNE_UPDATED", ScheduleAuctionRefresh)
        end
    end

    local function TryHookAuctionUI()
        local apCheck = rawget(_G, "AttuneParser")
        if apCheck and apCheck._hasStandaloneAuctionUI then
            local oldB = rawget(_G, "TalorianAuctionButton")
            if oldB then oldB:Hide() end
            local oldF = rawget(_G, "TalorianAuctionFrame")
            if oldF then oldF:Hide() end
            return
        end
        RegisterParserAuctionCallbacks()
        if not aucHookedBlizz and _G.AuctionFrameBrowse then
            aucHookedBlizz = true
            local ab = _G.AuctionFrameBrowse
            ab:HookScript("OnShow", ScheduleAuctionRefresh)
            ab:HookScript("OnHide", function()
                aucOpenByEvent = false
                if not GetActiveAuctionAnchor() then
                    if aucFrame then aucFrame:Hide() end
                    if aucBtn then aucBtn:Hide() end
                end
            end)
            if _G.AuctionFrame and _G.AuctionFrame.HookScript then
                _G.AuctionFrame:HookScript("OnHide", function()
                    aucOpenByEvent = false
                    if not GetActiveAuctionAnchor() then
                        if aucFrame then aucFrame:Hide() end
                        if aucBtn then aucBtn:Hide() end
                    end
                end)
            end
            if type(hooksecurefunc) == "function" and type(_G.AuctionFrameBrowse_Update) == "function" then
                hooksecurefunc("AuctionFrameBrowse_Update", ScheduleAuctionRefresh)
            end
            if ab:IsShown() then ScheduleAuctionRefresh() end
        end

        local pah = rawget(_G, "PrimeAH")
        if not aucHookedPrime and pah and pah.frame then
            aucHookedPrime = true
            pah.frame:HookScript("OnShow", ScheduleAuctionRefresh)
            pah.frame:HookScript("OnHide", function()
                aucOpenByEvent = false
                aucForceOpen = false
                if aucFrame then aucFrame:Hide() end
                if aucBtn then aucBtn:Hide() end
            end)
            if type(hooksecurefunc) == "function" then
                if type(pah.SetTab) == "function" then
                    hooksecurefunc(pah, "SetTab", ScheduleAuctionRefresh)
                end
                if pah.browse and pah.browse.list and type(pah.browse.list.Refresh) == "function" then
                    hooksecurefunc(pah.browse.list, "Refresh", ScheduleAuctionRefresh)
                end
                if pah.panels and pah.panels.itemBuy and pah.panels.itemBuy.ItemList and type(pah.panels.itemBuy.ItemList.Refresh) == "function" then
                    hooksecurefunc(pah.panels.itemBuy.ItemList, "Refresh", ScheduleAuctionRefresh)
                end
            end
            if pah.frame:IsShown() then ScheduleAuctionRefresh() end
        end
    end

    local function OnForgeViewUpdated(ctx)
        if ctx ~= "TRADE" then return end
        local apCheck = rawget(_G, "AttuneParser")
        if apCheck and apCheck._hasStandaloneTradeAlert then return end
        if not (_G.TradeFrame and _G.TradeFrame:IsShown()) then return end
        local ap = rawget(_G, "AttuneParser")
        if not (ap and ap.GetInspectTradeCandidates) then return end
        local cands = ap:GetInspectTradeCandidates("TRADE")
        if #cands == 0 then
            lastTradeAlertKey = nil
            return
        end
        local top = cands[1]
        local key = #cands .. ":" .. (top.itemId or 0) .. ":" .. (top.gainNowStats or 0)
        if key == lastTradeAlertKey then return end
        lastTradeAlertKey = key
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "%sОбмен: доступно |cff40ff40%d|r предм. для поглощения (топ: %s %s, +%d%% / +%s статов).",
            ADDON_PREFIX, #cands, top.name or ("#" .. (top.itemId or 0)), top.instanceTierName or "", top.gainNowPct or 0, FormatStatValue(top.gainNowStats or 0)
        ))
    end

    local helperEv = CreateFrame("Frame")
    helperEv:RegisterEvent("ADDON_LOADED")
    helperEv:RegisterEvent("PLAYER_LOGIN")
    helperEv:RegisterEvent("AUCTION_HOUSE_SHOW")
    helperEv:RegisterEvent("AUCTION_HOUSE_CLOSED")
    helperEv:RegisterEvent("TRADE_CLOSED")
    helperEv:SetScript("OnEvent", function(_, event, a1)
        if event == "ADDON_LOADED" and (a1 == "Blizzard_AuctionUI" or a1 == "PrimeAuctionHouse" or a1 == "TalorianTP") then
            TryHookAuctionUI()
            if a1 == "TalorianTP" then
                local ap = rawget(_G, "AttuneParser")
                if ap and ap.RegisterCallback then
                    ap:RegisterCallback("FORGE_VIEW_UPDATED", OnForgeViewUpdated)
                end
            end
        elseif event == "PLAYER_LOGIN" then
            TryHookAuctionUI()
        elseif event == "AUCTION_HOUSE_SHOW" then
            aucOpenByEvent = true
            TryHookAuctionUI()
            ScheduleAuctionRefresh()
        elseif event == "AUCTION_HOUSE_CLOSED" then
            aucOpenByEvent = false
            aucForceOpen = false
            if aucFrame then aucFrame:Hide() end
            if aucBtn then aucBtn:Hide() end
        elseif event == "TRADE_CLOSED" then
            lastTradeAlertKey = nil
        end
    end)
    TryHookAuctionUI()
end

---------------------------------------------------------------------------
-- Hardmode Server Control Hub (встроено в TalorianTP.lua для мгновенного /reload)
---------------------------------------------------------------------------
do
local TTP = TalorianTP
local math_floor, math_max, math_min, math_sqrt = math.floor, math.max, math.min, math.sqrt
local math_atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local tonumber, tostring, pairs, ipairs = tonumber, tostring, pairs, ipairs

local PLAYER_DIST = { WHISPER = true, PARTY = true, RAID = true, GUILD = true, BATTLEGROUND = true }

local function IsServerAddonMsg(dist, sender)
    if dist and PLAYER_DIST[dist] and sender and sender ~= "" and type(UnitName) == "function" then
        local me = UnitName("player")
        if me and me ~= "" and sender ~= me then
            return false
        end
    end
    return true
end

local function SendAddonWhisp(prefix, body)
    if type(SendAddonMessage) ~= "function" then return false end
    local me = type(UnitName) == "function" and UnitName("player")
    if not me or me == "" then return false end
    return pcall(SendAddonMessage, prefix, body or "", "WHISPER", me)
end

local function SendSrv(prefix, body)
    if type(SendServerMessage) == "function" then
        if body ~= nil then
            return pcall(SendServerMessage, prefix, tostring(body))
        end
        return pcall(SendServerMessage, prefix)
    end
    return SendAddonWhisp(prefix, body and tostring(body) or "")
end

local function HasBit(mask, bitIdx)
    mask = tonumber(mask) or 0
    return math_floor(mask / (2 ^ bitIdx)) % 2 == 1
end

local function IsFiniteNum(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function CountBits(mask)
    local nVal = tonumber(mask)
    if not IsFiniteNum(nVal) or nVal <= 0 then return 0 end
    mask = math_floor(nVal)
    local n = 0
    for _ = 1, 53 do
        if mask <= 0 then break end
        n = n + (mask % 2)
        mask = math_floor(mask / 2)
    end
    return n
end

local function FormatShortNum(v)
    v = tonumber(v) or 0
    if v >= 1e9 then return string.format("%.2f млрд", v / 1e9)
    elseif v >= 1e6 then return string.format("%.2f млн", v / 1e6)
    elseif v >= 1e3 then return string.format("%.1f тыс.", v / 1e3)
    end
    return string.format("%.0f", v)
end

local function FormatGold(copper)
    copper = math_floor(math_max(0, tonumber(copper) or 0))
    local g = math_floor(copper / 10000)
    local s = math_floor((copper % 10000) / 100)
    local gs = tostring(g):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^%s+", "")
    if s > 0 then
        return string.format("%s зол. %02d сер.", gs, s)
    end
    return gs .. " зол."
end

local function NormGuidHex(g)
    if type(g) ~= "string" or g == "" then return "" end
    local clean = g:lower():gsub("^0x", ""):gsub("^0+", "")
    return clean
end

---------------------------------------------------------------------------
-- 1. Persistent DB & Live Server State
---------------------------------------------------------------------------
local function EnsureSCDB()
    TalorianTP_DB = TalorianTP_DB or {}
    if type(TalorianTP_DB.serverCtrl) ~= "table" then
        TalorianTP_DB.serverCtrl = {}
    end
    local db = TalorianTP_DB.serverCtrl
    if type(db.pepePresets) ~= "table" then db.pepePresets = {} end
    if type(db.buildPresets) ~= "table" then db.buildPresets = {} end
    if db.autoPepeMerchant == nil then db.autoPepeMerchant = false end
    if db.gvKeepGold == nil then db.gvKeepGold = 5000 end
    if db.hudEnabled == nil then db.hudEnabled = false end
    if db.qncEnabled == nil then db.qncEnabled = false end
    return db
end

local TAL_BUFFS = {
    { bit = 0,  label = "Стойкость",      pal = false },
    { bit = 8,  label = "Интеллект",      pal = false },
    { bit = 4,  label = "Дух",            pal = false },
    { bit = 10, label = "Защита от Тьмы", pal = false },
    { bit = 2,  label = "Антистрах",      pal = false },
    { bit = 7,  label = "Знак дикой",     pal = false },
    { bit = 6,  label = "Шипы",           pal = false },
    { bit = 1,  label = "Короли",         pal = true },
    { bit = 3,  label = "Могущество",     pal = true },
    { bit = 9,  label = "Мудрость",       pal = true },
    { bit = 5,  label = "Неприкоснов.",   pal = true },
}
local TAL_PAL_BITS = { 1, 3, 9, 5 }

local RET_SLOTS = { [0] = "Слева", "Справа", "Сзади слева", "Сзади справа", "За спиной" }
local RET_KINDS = {
    { kind = 0, label = "Питомец" },
    { kind = 1, label = "Череп" },
    { kind = 2, label = "Талориан" },
    { kind = 3, label = "Сборщик" },
}

local PEPE_PERK_NAMES = {
    [2] = "+10% Маунт",
    [5] = "+50% Восстановление HP",
    [6] = "-15% Угроза",
    [8] = "Двойной прыжок",
    [9] = "-25% Износ",
    [11] = "-50% Ремонт",
    [12] = "Хождение по воде",
    [14] = "+25% Скорость духа",
    [16] = "-5% Цены торговцев",
    [18] = "+10% Полет",
    [19] = "2x Сбор и сундуки",
    [20] = "+10 мин Эликсиры",
}
local function ResolvePepeSkinName(skinIdx)
    skinIdx = tonumber(skinIdx) or 0
    if skinIdx <= 0 then return "|cff94a3b8снят|r" end
    local pp = rawget(_G, "PrimePepe")
    if type(pp) == "table" then
        if type(pp.GetSkinName) == "function" then
            local ok, res = pcall(pp.GetSkinName, skinIdx)
            if ok and type(res) == "string" and res ~= "" then return res end
        end
        local tbl = pp.SKINS or pp.skins or pp.skinNames
        if type(tbl) == "table" then
            local entry = tbl[skinIdx] or tbl[skinIdx - 1]
            local nm = type(entry) == "table" and (entry.name or entry.title or entry[1]) or entry
            if type(nm) == "string" and nm ~= "" then return nm end
        end
    end
    return "Облик #" .. skinIdx
end

local function ResolvePepePerkName(idx)
    idx = tonumber(idx) or 0
    local pp = rawget(_G, "PrimePepe")
    if type(pp) == "table" then
        if type(pp.GetPerkName) == "function" then
            local ok, res = pcall(pp.GetPerkName, idx)
            if ok and type(res) == "string" and res ~= "" then return res end
        end
        local tbl = pp.PERKS or pp.perks or pp.perkNames
        if type(tbl) == "table" then
            local entry = tbl[idx] or tbl[idx - 1]
            local nm = type(entry) == "table" and (entry.name or entry.title or entry[1]) or entry
            if type(nm) == "string" and nm ~= "" then return nm end
        end
    end
    return PEPE_PERK_NAMES[idx] or ("Бонус #" .. idx)
end
local TRAVEL_PREF_ORDER = { 8, 18, 2, 19, 12, 14, 13, 4 }
local MERCH_PREF_ORDER  = { 16, 11, 20, 9, 6, 5, 7, 15 }

local MAX_MONEY = 2147483646

local SC = {
    tal = { mask = 0, auto = true, fav = {}, loaded = false },
    ret = { slots = { [0] = 0, 4, 3, 2 }, resummon = true, loaded = false },
    gv  = { balance = nil, lastOpAt = 0, lastErr = "" },
    pepe = { cur = 0, mask = 0, sel = 0, slots = 0, prevSkin = 1, lastMerchSwap = nil, loaded = false },
    dung = { tier = 0, mythic = false, aoeLoot = nil },
    mtr = { active = false, startAt = 0, totalDmg = 0, peakHit = 0, dps = 0, lastHitAt = 0 },
    neck = { level = 0, xp = 0, nextXP = 0, maxLvl = 1000, bonusPct = 0, sessionStart = 0, gainedXP = 0, prevAbs = nil, ratePerHr = 0, etaSec = 0 },
    hud = { pin = nil },
    statusLine = "",
    panel = nil,
}
TTP.serverCtrl = SC

local function NotifyUI()
    if SC.panel and SC.panel.Refresh and SC.panel:IsShown() then
        SC.panel:Refresh()
    end
end

local function SetStatus(txt)
    SC.statusLine = txt or ""
    SC.statusAt = (txt and txt ~= "") and GetTime() or 0
    NotifyUI()
end

---------------------------------------------------------------------------
-- 2. Rate-Limited Queues (Pepe >= 0.35s, Build Preset sequential)
---------------------------------------------------------------------------
local pepeQueue, pepeLastSend = {}, 0
local queueDriver = CreateFrame("Frame")
local buildQueue, buildLastSend, buildRunning = {}, 0, false

local function DispatchPepeBody(body)
    pepeLastSend = GetTime()
    local pp = rawget(_G, "PrimePepe")
    if type(pp) == "table" and type(pp.Send) == "function" then
        pcall(pp.Send, body)
        return true
    end
    return SendAddonWhisp("ACMSG_PEPE", body)
end

function SC:SendPepeQueued(body)
    local now = GetTime()
    if #pepeQueue == 0 and (now - pepeLastSend) >= 0.36 then
        return DispatchPepeBody(body)
    end
    if #pepeQueue < 12 then
        pepeQueue[#pepeQueue + 1] = body
        queueDriver:Show()
    end
    return true
end

local function RunNextBuildStep()
    if #buildQueue == 0 then
        buildRunning = false
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        buildQueue = {}
        buildRunning = false
        SetStatus("|cffff6060Смена набора прервана: бой!|r")
        return
    end
    local step = table.remove(buildQueue, 1)
    buildLastSend = GetTime()
    local ok, err = pcall(step.fn)
    if not ok and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Talorian Набор]|r " .. tostring(err))
    end
    if step.msg then SetStatus(step.msg) end
    if #buildQueue == 0 then
        buildRunning = false
    end
end

queueDriver:Hide()
queueDriver:SetScript("OnUpdate", function(self)
    local now = GetTime()
    if #pepeQueue > 0 and (now - pepeLastSend) >= 0.36 then
        local b = table.remove(pepeQueue, 1)
        DispatchPepeBody(b)
    end
    if buildRunning and #buildQueue > 0 and (now - buildLastSend) >= 0.28 then
        RunNextBuildStep()
    end
    if #pepeQueue == 0 and (not buildRunning or #buildQueue == 0) then
        self:Hide()
    end
end)

---------------------------------------------------------------------------
-- 3. Track 2 Controls: Talorian, Retinue, GoldVault, Pepe, Dungeon/Loot
---------------------------------------------------------------------------
function SC:SyncPepeFromGlobal()
    local pp = rawget(_G, "PrimePepe")
    if type(pp) == "table" then
        if tonumber(pp.cur) then SC.pepe.cur = tonumber(pp.cur) end
        if tonumber(pp.mask) then SC.pepe.mask = tonumber(pp.mask) end
        if tonumber(pp.sel) then SC.pepe.sel = tonumber(pp.sel) end
        if tonumber(pp.slots) then SC.pepe.slots = tonumber(pp.slots) end
        if SC.pepe.cur and SC.pepe.cur > 0 then SC.pepe.prevSkin = SC.pepe.cur end
        SC.pepe.loaded = true
    end
end

function SC:RequestAllStates()
    SendSrv("ACMSG_TALORIAN", "get")
    SendAddonWhisp("ACMSG_PRIMERET", "get")
    SendAddonWhisp("ACMSG_GOLDVAULT", "get")
    SC:SendPepeQueued("req")
    SendAddonWhisp("ACMSG_DUNGEON_LEVEL_INFO_REQUEST", "")
    SendAddonWhisp("ACMSG_AOE_LOOT_TOGGLE", "")
    SC:SyncPepeFromGlobal()
end

function SC:ToggleTalBuffBit(bitIdx, isPal)
    if not SC.tal.loaded then
        SendSrv("ACMSG_TALORIAN", "get")
        SetStatus("Синхронизация баффов Талориана, повторите клик...")
        return nil
    end
    local cur = SC.tal.mask or 0
    local wasOn = HasBit(cur, bitIdx)
    if isPal then
        for _, pb in ipairs(TAL_PAL_BITS) do
            if HasBit(cur, pb) then
                cur = cur - (2 ^ pb)
            end
        end
        if not wasOn then
            cur = cur + (2 ^ bitIdx)
        end
    else
        cur = wasOn and (cur - (2 ^ bitIdx)) or (cur + (2 ^ bitIdx))
    end
    SC.tal.mask = cur
    SendSrv("ACMSG_TALORIAN", "set:" .. tostring(cur))
    NotifyUI()
    return cur
end

function SC:SetTalAuto(on)
    SC.tal.auto = on and true or false
    SendSrv("ACMSG_TALORIAN", "auto:" .. (SC.tal.auto and "1" or "0"))
    NotifyUI()
end

function SC:CastTalBuffNow()
    SendSrv("ACMSG_TALORIAN", "buff")
    SetStatus("Запрошен бафф Талориана.")
end

function SC:ToggleTalFav(destName)
    if not destName or destName == "" then return false end
    SendSrv("ACMSG_TALORIAN", "fav:" .. destName)
    SC.tal.fav[destName] = not SC.tal.fav[destName]
    NotifyUI()
    return true
end

function SC:CycleRetinueSlot(kind)
    local cur = SC.ret.slots[kind] or 0
    local nxt = (cur + 1) % 5
    SC.ret.slots[kind] = nxt
    SendAddonWhisp("ACMSG_PRIMERET", string.format("set:%d:%d", kind, nxt))
    NotifyUI()
    return nxt
end

function SC:ToggleRetResummon()
    SC.ret.resummon = not SC.ret.resummon
    SendAddonWhisp("ACMSG_PRIMERET", "resummon:" .. (SC.ret.resummon and "1" or "0"))
    NotifyUI()
end

function SC:ResetRetinue()
    SendAddonWhisp("ACMSG_PRIMERET", "reset")
    SetStatus("Позиции свиты сброшены.")
end

function SC:GoldVaultTransfer(mode, copperArg)
    local now = GetTime()
    if (now - (SC.gv.lastOpAt or 0)) < 3.05 then
        local waitS = 3.05 - (now - SC.gv.lastOpAt)
        SetStatus(string.format("Сейф золота: подождите %.1fс (восстановление).", waitS))
        return false
    end
    local copper = math_floor(tonumber(copperArg) or 0)
    if mode == "dep_excess" then
        local db = EnsureSCDB()
        local keep = math_max(0, (db.gvKeepGold or 5000)) * 10000
        local myMoney = (type(GetMoney) == "function" and GetMoney()) or 0
        copper = math_max(0, myMoney - keep)
        if copper < 10000 then
            SetStatus("Нет лишнего золота сверх " .. (db.gvKeepGold or 5000) .. " зол.")
            return false
        end
        if copper >= MAX_MONEY then copper = MAX_MONEY - 1 end
        mode = "dep"
    elseif mode == "wd" then
        local myMoney = (type(GetMoney) == "function" and GetMoney()) or 0
        if (myMoney + copper) >= MAX_MONEY then
            copper = math_max(0, MAX_MONEY - myMoney - 1)
        end
    end
    if copper <= 0 then
        SetStatus("Укажите корректную сумму > 0.")
        return false
    end
    SC.gv.lastOpAt = now
    local body = (mode == "wd" and "wd:" or "dep:") .. tostring(copper)
    SendAddonWhisp("ACMSG_GOLDVAULT", body)
    SetStatus((mode == "wd" and "Снятие: " or "Внесение: ") .. FormatGold(copper))
    return true
end

function SC:SanitizePepeMask(wantMask)
    SC:SyncPepeFromGlobal()
    local unlocked = SC.pepe.mask or 0
    local maxSlots = SC.pepe.slots or 0
    if maxSlots <= 0 then
        maxSlots = math_min(5, CountBits(unlocked))
    end
    local out, used = 0, 0
    for i = 1, 21 do
        local p = 2 ^ (i - 1)
        if HasBit(wantMask or 0, i - 1) and HasBit(unlocked, i - 1) then
            if used < maxSlots then
                out = out + p
                used = used + 1
            end
        end
    end
    return out, used, maxSlots
end

function SC:GetDefaultPepePresetMask(kind)
    SC:SyncPepeFromGlobal()
    local unlocked = SC.pepe.mask or 0
    local maxSlots = SC.pepe.slots or math_min(5, CountBits(unlocked))
    if maxSlots <= 0 then return 0 end
    local order = (kind == "merchant") and MERCH_PREF_ORDER or TRAVEL_PREF_ORDER
    local m, cnt = 0, 0
    for _, idx in ipairs(order) do
        if HasBit(unlocked, idx - 1) and cnt < maxSlots then
            m = m + (2 ^ (idx - 1))
            cnt = cnt + 1
        end
    end
    -- Fill remaining slots with any unlocked perks if needed
    if cnt < maxSlots then
        for i = 1, 21 do
            if HasBit(unlocked, i - 1) and not HasBit(m, i - 1) and cnt < maxSlots then
                m = m + (2 ^ (i - 1))
                cnt = cnt + 1
            end
        end
    end
    return m
end

function SC:SavePepePreset(slotKey)
    SC:SyncPepeFromGlobal()
    local db = EnsureSCDB()
    db.pepePresets[slotKey] = {
        mask = SC.pepe.sel or 0,
        skin = (SC.pepe.cur and SC.pepe.cur > 0) and SC.pepe.cur or SC.pepe.prevSkin or 1,
    }
    SetStatus(string.format("Набор талисмана '%s' сохранен (%d баффов).", tostring(slotKey), CountBits(SC.pepe.sel)))
    return db.pepePresets[slotKey]
end

function SC:ApplyPepePreset(slotKey)
    local db = EnsureSCDB()
    local p = db.pepePresets[slotKey]
    local rawMask = p and p.mask or SC:GetDefaultPepePresetMask(slotKey)
    local safeMask, used, maxSlots = SC:SanitizePepeMask(rawMask)
    if (SC.pepe.mask or 0) == 0 then
        SetStatus("Нет открытых обликов талисмана.")
        return false
    end
    if SC.pepe.cur == 0 then
        local targetSkin = (p and p.skin) or SC.pepe.prevSkin or 1
        if not HasBit(SC.pepe.mask, targetSkin - 1) then
            for i = 1, 21 do
                if HasBit(SC.pepe.mask, i - 1) then targetSkin = i; break end
            end
        end
        SC:SendPepeQueued("set:" .. tostring(targetSkin))
        SC.pepe.cur = targetSkin
    end
    SC:SendPepeQueued("perks:" .. tostring(safeMask))
    SC.pepe.sel = safeMask
    SetStatus(string.format("Талисман '%s': применено %d/%d бонусов.", tostring(slotKey), used, maxSlots))
    return true
end

function SC:TogglePepeSummon()
    SC:SyncPepeFromGlobal()
    if (SC.pepe.cur or 0) > 0 then
        SC.pepe.prevSkin = SC.pepe.cur
        SC:SendPepeQueued("off")
        SC.pepe.cur = 0
    else
        local sk = SC.pepe.prevSkin or 1
        if not HasBit(SC.pepe.mask or 0, sk - 1) then
            for i = 1, 21 do
                if HasBit(SC.pepe.mask or 0, i - 1) then sk = i; break end
            end
        end
        if sk > 0 and (SC.pepe.mask or 0) > 0 then
            SC:SendPepeQueued("set:" .. tostring(sk))
            SC.pepe.cur = sk
        end
    end
    NotifyUI()
end

function SC:SetDungeonTier(lvl)
    lvl = tonumber(lvl) or 1
    if lvl < 1 or lvl > 4 then return false end
    SC.dung.tier = lvl
    SendAddonWhisp("ACMSG_DUNGEON_LEVEL_SET", tostring(lvl))
    NotifyUI()
    return true
end

function SC:ToggleMythic()
    local nextVal = not SC.dung.mythic
    local ok = true
    if type(SetDungeonDifficulty) == "function" then
        ok = pcall(SetDungeonDifficulty, nextVal and 3 or 1)
    end
    if ok then
        SC.dung.mythic = nextVal
        SendSrv("ACMSG_MPLUS_EPIC", SC.dung.mythic and "1" or "0")
    else
        SetStatus("|cffff8040Не удалось переключить сложность (нужен лидер группы/вне боя).|r")
    end
    NotifyUI()
end

function SC:ToggleAoELoot()
    local cur = (SC.dung.aoeLoot ~= nil) and SC.dung.aoeLoot or (type(GetCVar) == "function" and GetCVar("aoeLootEnabled") == "1")
    local nxt = not cur
    SC.dung.aoeLoot = nxt
    SendAddonWhisp("ACMSG_AOE_LOOT_TOGGLE", nxt and "1" or "0")
    NotifyUI()
end

---------------------------------------------------------------------------
-- 4. Track 3: Unified Build Presets (Spec + Peark + SetForge)
---------------------------------------------------------------------------
function SC:CaptureBuildPreset(idx, customName)
    idx = tonumber(idx) or 1
    local db = EnsureSCDB()
    local specGroup = 1
    local ct = rawget(_G, "C_Talent")
    if type(ct) == "table" and type(ct.GetActiveTalentGroup) == "function" then
        specGroup = tonumber(ct.GetActiveTalentGroup()) or 1
    elseif type(GetActiveTalentGroup) == "function" then
        specGroup = tonumber(GetActiveTalentGroup()) or 1
    end
    local currencyIdx = -1
    if specGroup > 2 and type(ct) == "table" and type(ct.GetSelectedCurrency) == "function" then
        local c = tonumber(ct.GetSelectedCurrency())
        if c and c > 0 then currencyIdx = c - 1 else currencyIdx = 0 end
    end

    local pearkIds = {}
    local pp = rawget(_G, "PearkProgress")
    if type(pp) == "table" then
        for setID, info in pairs(pp) do
            if type(info) == "table" and info.active then
                local sid = tonumber(setID)
                if sid then pearkIds[#pearkIds + 1] = sid end
            end
        end
        table.sort(pearkIds)
    end

    local sfTree, sfV2, sfV4 = nil, 0, 0
    local sf = rawget(_G, "PRIME_SetForge")
    if type(sf) == "table" and type(sf.branches) == "table" and sf.activeTree ~= nil then
        local b = sf.branches[sf.activeTree]
        if type(b) == "table" then
            sfTree = sf.activeTree
            sfV2 = tonumber(b.v2) or 0
            sfV4 = tonumber(b.v4) or 0
        end
    end

    local specTitle = (type(GetSpecName) == "function" and GetSpecName()) or ""
    if specTitle == "" then specTitle = "Спек " .. specGroup end
    local preset = {
        name = (customName and customName ~= "") and customName or string.format("#%d %s (%d перк.)", idx, specTitle, #pearkIds),
        specGroup = specGroup,
        currencyIdx = currencyIdx,
        pearkSetIds = pearkIds,
        sfTree = sfTree,
        sfV2 = sfV2,
        sfV4 = sfV4,
    }
    db.buildPresets[idx] = preset
    SetStatus(string.format("Набор #%d сохранен: %s | Таланты: %d | Ковка: %s",
        idx, specTitle, #pearkIds, sfTree and (sfV2 .. "+" .. sfV4) or "-"))
    return preset
end

function SC:ApplyBuildPreset(idx)
    idx = tonumber(idx) or 1
    local db = EnsureSCDB()
    local preset = db.buildPresets[idx]
    if not preset then
        SetStatus("Набор #" .. idx .. " пуст - сначала сохраните его.")
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        SetStatus("|cffff6060Смена набора невозможна в бою!|r")
        return false
    end

    buildQueue = {}
    -- Step 1: Spec
    local ct = rawget(_G, "C_Talent")
    local curSpec = (type(ct) == "table" and type(ct.GetActiveTalentGroup) == "function" and ct.GetActiveTalentGroup())
        or (type(GetActiveTalentGroup) == "function" and GetActiveTalentGroup()) or 1
    if preset.specGroup and preset.specGroup ~= curSpec then
        buildQueue[#buildQueue + 1] = {
            msg = "Переключение специализации #" .. tostring(preset.specGroup) .. "...",
            fn = function()
                local cTal = rawget(_G, "C_Talent")
                local hasCur = type(cTal) == "table" and type(cTal.GetSelectedCurrency) == "function" and cTal.GetSelectedCurrency()
                if type(cTal) == "table" and type(cTal.SetActiveTalentGroup) == "function" and (preset.specGroup <= 2 or hasCur) then
                    pcall(cTal.SetActiveTalentGroup, preset.specGroup)
                elseif preset.specGroup > 2 then
                    SendSrv("ACMSG_ACTIVATE_SPEC", tostring(preset.specGroup) .. ":" .. tostring(preset.currencyIdx or 0))
                else
                    SendSrv("ACMSG_ACTIVATE_SPEC", tostring(preset.specGroup) .. ":-1")
                end
            end,
        }
    end

    -- Step 2: Peark diff (Deactivate removed FIRST so category caps are freed before Activate!)
    local pp = rawget(_G, "PearkProgress")
    local wantMap = {}
    for _, sid in ipairs(preset.pearkSetIds or {}) do wantMap[sid] = true end
    local reqOpts = rawget(_G, "PerkInformRequiredTargetOption")
    local targOpts = rawget(_G, "PearkTargetOptions")

    if type(pp) == "table" then
        local toOff = {}
        for setID, info in pairs(pp) do
            local sid = tonumber(setID)
            if sid and type(info) == "table" and info.active and not wantMap[sid] then
                toOff[#toOff + 1] = sid
            end
        end
        table.sort(toOff)
        for _, sid in ipairs(toOff) do
            buildQueue[#buildQueue + 1] = {
                msg = "Отключение таланта #" .. sid .. "...",
                fn = function() SendSrv("ACMSG_PERK_DEACTIVATE", tostring(sid)) end,
            }
        end

        for _, sid in ipairs(preset.pearkSetIds or {}) do
            local curInfo = pp[sid]
            local isAct = type(curInfo) == "table" and curInfo.active
            if not isAct then
                local needsOpt = reqOpts and reqOpts[sid]
                local hasOpt = targOpts and (tonumber(targOpts[sid]) or 0) > 0
                if needsOpt and not hasOpt then
                    SetStatus("|cffffd200Пропуск таланта #" .. sid .. ": выберите вариант в окне талантов.|r")
                else
                    buildQueue[#buildQueue + 1] = {
                        msg = "Активация таланта #" .. sid .. "...",
                        fn = function() SendSrv("ACMSG_PERK_ACTIVATE", tostring(sid)) end,
                    }
                end
            end
        end
    end

    -- Step 3: SetForge T11 recipe if changed
    if preset.sfTree ~= nil and ((preset.sfV2 or 0) > 0 or (preset.sfV4 or 0) > 0) then
        local sf = rawget(_G, "PRIME_SetForge")
        local b = (type(sf) == "table" and type(sf.branches) == "table") and sf.branches[preset.sfTree]
        local same = b and (sf.activeTree == preset.sfTree) and ((tonumber(b.v2) or 0) == (preset.sfV2 or 0)) and ((tonumber(b.v4) or 0) == (preset.sfV4 or 0))
        if not same then
            buildQueue[#buildQueue + 1] = {
                msg = string.format("Ковка: набор %d (%d+%d)...", preset.sfTree, preset.sfV2 or 0, preset.sfV4 or 0),
                fn = function()
                    SendAddonWhisp("ACMSG_SFORGE_APPLY", string.format("%d %d %d", preset.sfTree, preset.sfV2 or 0, preset.sfV4 or 0))
                end,
            }
        end
    end

    if #buildQueue == 0 then
        SetStatus("Набор #" .. idx .. " уже полностью активен.")
        return true
    end
    buildRunning = true
    queueDriver:Show()
    RunNextBuildStep()
    return true
end

---------------------------------------------------------------------------
-- 5. Track 4: Cooperative QNC Highlighter & 3D-HUD (QNP / QNW)
---------------------------------------------------------------------------
local qncOrigMac = nil
local qncFallbackOrig = nil
local qncExternalRef = nil
local qncMine, qncOther = "", ""
local qncInCall = false
local MAX_QNC_ENTRIES = 12
local TWO_PI = 2 * math.pi

local function NormalizeAngle(ang)
    if not IsFiniteNum(ang) then return 0 end
    ang = math.fmod(ang, TWO_PI)
    if ang > math.pi then
        ang = ang - TWO_PI
    elseif ang < -math.pi then
        ang = ang + TWO_PI
    end
    return ang
end

local function FormatQncGuid(unit)
    if type(UnitExists) == "function" and not UnitExists(unit) then return nil end
    local g = type(UnitGUID) == "function" and UnitGUID(unit)
    if type(g) ~= "string" or g == "" then return nil end
    if not g:find("^0[xX]") then g = "0x" .. g end
    if g:find("^0[xX]0+$") or not g:find("^0[xX]%x+$") then return nil end
    return g
end

local function AppendQncParts(out, seen, rawStr)
    if type(rawStr) ~= "string" or rawStr == "" then return end
    for token in rawStr:gmatch("[^;]+") do
        if #out >= MAX_QNC_ENTRIES then break end
        local guid = token:match("^([^:]+)")
        if guid and guid ~= "" and not guid:find("^0[xX]0+$") then
            local key = guid:lower()
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = token
            end
        end
    end
end

local function MergeQNC(other, mine)
    if (mine or "") == "" then return other or "" end
    if (other or "") == "" then return mine or "" end
    local out, seen = {}, {}
    -- Prioritize player target/focus before external Cadastre entries (WoWPrime QNC limit is 12)
    AppendQncParts(out, seen, mine)
    AppendQncParts(out, seen, other)
    return table.concat(out, ";")
end

local function FinishQncForward(ok, ...)
    qncInCall = false
    if ok then return ... end
    return nil
end

local function QNCWrapper(key, ...)
    if type(qncOrigMac) ~= "function" or qncOrigMac == QNCWrapper then
        return nil
    end
    if qncInCall then
        local baseFn = (type(qncFallbackOrig) == "function" and qncFallbackOrig ~= QNCWrapper and qncFallbackOrig ~= qncOrigMac) and qncFallbackOrig or nil
        if qncOrigMac ~= baseFn then
            qncExternalRef = qncOrigMac
            _G.IsMacClient = qncExternalRef
            qncOrigMac = baseFn
        end
        if baseFn then
            return baseFn(key, ...)
        end
        return nil
    end
    if key == "QNC" then
        local val = select(1, ...)
        qncOther = (type(val) == "string") and val or ""
        local db = EnsureSCDB()
        local merged = db.qncEnabled and MergeQNC(qncOther, qncMine) or qncOther
        qncInCall = true
        local ok, r1, r2, r3, r4 = pcall(qncOrigMac, "QNC", merged)
        qncInCall = false
        if ok then
            return r1, r2, r3, r4
        end
        return 0
    end
    qncInCall = true
    return FinishQncForward(pcall(qncOrigMac, key, ...))
end

function SC:EnsureQNCWrapper()
    local cur = rawget(_G, "IsMacClient")
    if cur == QNCWrapper or (qncExternalRef and cur == qncExternalRef) then
        return type(qncOrigMac) == "function" and qncOrigMac ~= QNCWrapper
    end
    if type(cur) ~= "function" then
        return type(qncOrigMac) == "function" and qncOrigMac ~= QNCWrapper
    end
    if type(qncOrigMac) == "function" and qncOrigMac ~= QNCWrapper and cur ~= qncOrigMac then
        qncFallbackOrig = qncOrigMac
    end
    qncExternalRef = nil
    qncOrigMac = cur
    _G.IsMacClient = QNCWrapper
    return true
end

function SC:RefreshQNCHighlight()
    local db = EnsureSCDB()
    if not db.qncEnabled then
        if qncMine ~= "" then
            qncMine = ""
            if type(qncOrigMac) == "function" and qncOrigMac ~= QNCWrapper and not qncInCall then
                qncInCall = true
                pcall(qncOrigMac, "QNC", qncOther)
                qncInCall = false
            end
        end
        return
    end
    if not SC:EnsureQNCWrapper() then return end
    local parts, seen = {}, {}
    local tg = FormatQncGuid("target")
    if tg then
        seen[tg:lower()] = true
        parts[#parts + 1] = tg .. ":1.0,0.82,0.15"
    end
    local fg = FormatQncGuid("focus")
    if fg and not seen[fg:lower()] then
        parts[#parts + 1] = fg .. ":0.22,0.74,0.97"
    end
    local nextMine = table.concat(parts, ";")
    if nextMine ~= qncMine then
        qncMine = nextMine
        if type(qncOrigMac) == "function" and qncOrigMac ~= QNCWrapper and not qncInCall then
            qncInCall = true
            pcall(qncOrigMac, "QNC", MergeQNC(qncOther, qncMine))
            qncInCall = false
        end
    end
end

local hudFrame = nil
local function EnsureHUDFrame()
    if hudFrame then return hudFrame end
    local PS = TTP.Skin
    local hf = CreateFrame("Frame", "TalorianHUD3DFrame", UIParent)
    hf:SetSize(210, 54)
    hf:SetPoint("TOP", UIParent, "TOP", 0, -110)
    hf:SetFrameStrata("MEDIUM")
    hf:EnableMouse(true)
    hf:SetMovable(true)
    hf:RegisterForDrag("LeftButton")
    hf:SetScript("OnDragStart", hf.StartMoving)
    hf:SetScript("OnDragStop", hf.StopMovingOrSizing)
    hf:SetClampedToScreen(true)
    if PS and PS.StyleBox then PS.StyleBox(hf, 0.72, true) end

    hf.title = hf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hf.title:SetPoint("TOPLEFT", 8, -6)
    hf.title:SetSize(194, 14)
    hf.title:SetJustifyH("LEFT")
    if hf.title.SetWordWrap then hf.title:SetWordWrap(false) end
    hf.title:SetText("|cff38bdf8HUD 3D|r")

    hf.dir = hf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hf.dir:SetPoint("TOPLEFT", 8, -22)
    hf.dir:SetSize(194, 24)
    hf.dir:SetJustifyH("LEFT")

    -- Screen pin dot when QNW projects onto screen
    local pin = CreateFrame("Frame", "TalorianHUD3DPin", UIParent)
    pin:SetSize(14, 14)
    pin:EnableMouse(false)
    if PS and PS.StyleBox then PS.StyleBox(pin, 0.85, true) end
    pin.lbl = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pin.lbl:SetPoint("BOTTOM", pin, "TOP", 0, 2)
    pin:Hide()
    hf.pin = pin

    local acc = 0
    hf:SetScript("OnUpdate", function(self, el)
        acc = acc + ((IsFiniteNum(el) and el > 0 and el < 10) and el or 0.05)
        if acc < 0.05 then return end
        acc = 0
        SC:UpdateHUDTick()
    end)
    hf:Hide()
    hudFrame = hf
    return hf
end

function SC:SetCustomPinHere()
    local fn = rawget(_G, "IsMacClient")
    if type(fn) ~= "function" then
        SetStatus("Функция позиционирования 3D-указателя недоступна в клиенте.")
        return false
    end
    local ok, px, py, pz = pcall(fn, "QNP")
    if not ok or not IsFiniteNum(px) or not IsFiniteNum(py) then
        SetStatus("Координаты 3D-указателя недоступны в этой локации.")
        return false
    end
    local pzSafe = IsFiniteNum(pz) and pz or 0
    local mapId = (type(GetCurrentMapAreaID) == "function") and GetCurrentMapAreaID() or nil
    local instType = (type(IsInInstance) == "function") and select(2, IsInInstance()) or nil
    SC.hud.pin = {
        x = px, y = py, z = pzSafe,
        mapId = mapId, instType = instType,
        label = (type(GetSubZoneText) == "function" and GetSubZoneText()) or "Метка",
    }
    EnsureSCDB().hudEnabled = true
    SC:UpdateHUDVisibility()
    SetStatus(string.format("3D метка поставлена (%.1f, %.1f).", px, py))
    return true
end

function SC:ClearCustomPin()
    SC.hud.pin = nil
    if hudFrame and hudFrame.pin then hudFrame.pin:Hide() end
    NotifyUI()
end

function SC:UpdateHUDTick()
    if not hudFrame or not hudFrame:IsShown() then return end
    local mac = rawget(_G, "IsMacClient")
    if type(mac) ~= "function" then
        hudFrame.dir:SetText("|cffff7070Указатель цели недоступен|r")
        hudFrame.pin:Hide()
        return
    end
    local okP, px, py, pz, pf = pcall(mac, "QNP")
    if not okP or not IsFiniteNum(px) or not IsFiniteNum(py) then
        hudFrame.dir:SetText("|cff94a3b8Нет 3D позиции|r")
        hudFrame.pin:Hide()
        return
    end
    local pzSafe = IsFiniteNum(pz) and pz or 0
    local pfSafe = IsFiniteNum(pf) and pf or 0

    local tx, ty, tz, label, col = nil, nil, nil, "", "|cffffd200"
    if SC.hud.pin and IsFiniteNum(SC.hud.pin.x) and IsFiniteNum(SC.hud.pin.y) then
        tx, ty, tz, label, col = SC.hud.pin.x, SC.hud.pin.y, SC.hud.pin.z, SC.hud.pin.label or "Метка", "|cff40ff40"
    else
        local gTarget = FormatQncGuid("target")
        if gTarget then
            local okT, ux, uy, uz = pcall(mac, "QNP", gTarget)
            if okT and IsFiniteNum(ux) and IsFiniteNum(uy) then
                tx, ty, tz, label = ux, uy, (IsFiniteNum(uz) and uz or pzSafe), (UnitName("target") or "Цель")
            end
        else
            local gFocus = FormatQncGuid("focus")
            if gFocus then
                local okT, ux, uy, uz = pcall(mac, "QNP", gFocus)
                if okT and IsFiniteNum(ux) and IsFiniteNum(uy) then
                    tx, ty, tz, label, col = ux, uy, (IsFiniteNum(uz) and uz or pzSafe), (UnitName("focus") or "Фокус"), "|cff38bdf8"
                end
            end
        end
    end

    if not IsFiniteNum(tx) or not IsFiniteNum(ty) then
        hudFrame.title:SetText("|cff38bdf8Указатель цели|r")
        hudFrame.dir:SetText("|cff94a3b8Выберите цель/фокус или поставьте метку|r")
        hudFrame.pin:Hide()
        return
    end

    local dx, dy = tx - px, ty - py
    local dz = (IsFiniteNum(tz) and tz or pzSafe) - pzSafe
    local dist = math_sqrt(dx * dx + dy * dy + dz * dz)
    if not IsFiniteNum(dist) then dist = 0 end
    local ang = NormalizeAngle(math_atan2(dy, dx) - pfSafe)
    local deg = math_floor(math.deg(ang) + 0.5)
    local arrow = (deg >= -25 and deg <= 25 and "^ ВПЕРЕД")
        or (deg > 25 and deg < 155 and "<- ВЛЕВО")
        or (deg < -25 and deg > -155 and "-> ВПРАВО")
        or "v НАЗАД"

    hudFrame.title:SetText(col .. Utf8CropChars(label, 24) .. "|r")
    hudFrame.dir:SetText(string.format("%s  |cffffffff%.1f м|r (%d град.)", arrow, dist, deg))

    local okW, sx, sy, _, front = pcall(mac, "QNW", tx, ty, IsFiniteNum(tz) and tz or pzSafe)
    if okW and front == 1 and IsFiniteNum(sx) and IsFiniteNum(sy) and sx >= -0.25 and sx <= 1.25 and sy >= -0.25 and sy <= 1.25 and UIParent then
        local sw, sh = UIParent:GetWidth() or 1024, UIParent:GetHeight() or 768
        hudFrame.pin:ClearAllPoints()
        hudFrame.pin:SetPoint("CENTER", UIParent, "BOTTOMLEFT", sx * sw, sy * sh)
        hudFrame.pin.lbl:SetText(string.format("%s%.0f м|r", col, dist))
        hudFrame.pin:Show()
    else
        hudFrame.pin:Hide()
    end
end

function SC:UpdateHUDVisibility()
    local db = EnsureSCDB()
    local hf = EnsureHUDFrame()
    if db.hudEnabled then hf:Show(); SC:UpdateHUDTick()
    else hf:Hide(); if hf.pin then hf.pin:Hide() end end
end

---------------------------------------------------------------------------
-- 6. Event Listener (CHAT_MSG_ADDON + Combat Metrics + Auto-Pepe Merchant)
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("MERCHANT_CLOSED")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "PLAYER_LOGIN" then
        EnsureSCDB()
        SC:RequestAllStates()
        SC:UpdateHUDVisibility()
        SC:RefreshQNCHighlight()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if SC.hud and SC.hud.pin then
            local curMap = (type(GetCurrentMapAreaID) == "function") and GetCurrentMapAreaID() or nil
            local curInst = (type(IsInInstance) == "function") and select(2, IsInInstance()) or nil
            if SC.hud.pin.instType ~= curInst or (curMap ~= nil and SC.hud.pin.mapId ~= nil and curMap ~= SC.hud.pin.mapId) then
                SC:ClearCustomPin()
            end
        end
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        SC:RefreshQNCHighlight()
        if hudFrame and hudFrame:IsShown() then SC:UpdateHUDTick() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        SC.mtr = { active = true, startAt = GetTime(), totalDmg = 0, peakHit = 0, dps = 0, lastHitAt = GetTime() }
        NotifyUI()
    elseif event == "MERCHANT_SHOW" then
        local db = EnsureSCDB()
        if db.autoPepeMerchant and not (InCombatLockdown and InCombatLockdown()) and (SC.pepe.mask or 0) > 0 then
            if SC.pepe.lastMerchSwap == nil then
                SC.pepe.lastMerchSwap = SC.pepe.sel
                SC.pepe.lastMerchWasOff = ((SC.pepe.cur or 0) == 0)
            end
            SC:ApplyPepePreset("merchant")
        end
    elseif event == "MERCHANT_CLOSED" then
        local db = EnsureSCDB()
        if db.autoPepeMerchant and SC.pepe.lastMerchSwap ~= nil and not (InCombatLockdown and InCombatLockdown()) then
            local prev = SC:SanitizePepeMask(SC.pepe.lastMerchSwap)
            local wasOff = SC.pepe.lastMerchWasOff
            SC.pepe.lastMerchSwap = nil
            SC.pepe.lastMerchWasOff = nil
            SC:SendPepeQueued("perks:" .. tostring(prev))
            SC.pepe.sel = prev
            if wasOff then
                SC:SendPepeQueued("off")
                SC.pepe.cur = 0
            end
        end
    elseif event == "CHAT_MSG_ADDON" and type(a1) == "string" then
        if a1 == "ASMSG_PRIMEMTR" then
            local sg, _, amtStr = strsplit("\t", tostring(a2 or ""))
            local amt = tonumber(amtStr)
            local myGuid = type(UnitGUID) == "function" and UnitGUID("player")
            if sg and amt and amt > 0 and myGuid and NormGuidHex(sg) == NormGuidHex(myGuid) then
                local now = GetTime()
                if not SC.mtr.active or (now - (SC.mtr.lastHitAt or 0)) > 15 then
                    SC.mtr.active = true
                    SC.mtr.startAt = now
                    SC.mtr.totalDmg = 0
                    SC.mtr.peakHit = 0
                end
                SC.mtr.totalDmg = SC.mtr.totalDmg + amt
                if amt > SC.mtr.peakHit then SC.mtr.peakHit = amt end
                SC.mtr.lastHitAt = now
                local dur = math_max(1, now - SC.mtr.startAt)
                SC.mtr.dps = SC.mtr.totalDmg / dur
                NotifyUI()
            end
            return
        end

        if not IsServerAddonMsg(a3, a4) then return end
        local msg = tostring(a2 or "")
        if a1 == "ASMSG_TALORIAN_STATE" then
            local m, au = msg:match("^(%-?%d+)%s+(%d+)")
            SC.tal.mask = tonumber(m) or tonumber(msg) or 0
            if au then SC.tal.auto = (au == "1") end
            SC.tal.loaded = true
            NotifyUI()
        elseif a1 == "ASMSG_TALORIAN_FAV" then
            SC.tal.fav = {}
            for nm in msg:gmatch("[^\t]+") do SC.tal.fav[nm] = true end
            NotifyUI()
        elseif a1 == "ASMSG_PRIMERET" then
            local f = { strsplit("\t", msg) }
            for k = 0, 3 do
                if tonumber(f[k + 1]) then SC.ret.slots[k] = tonumber(f[k + 1]) end
            end
            if f[5] ~= nil then SC.ret.resummon = (f[5] == "1") end
            SC.ret.loaded = true
            NotifyUI()
        elseif a1 == "ASMSG_GOLDVAULT" then
            local kind, val = strsplit("\t", msg)
            if kind == "BAL" then
                SC.gv.balance = tonumber(val) or 0
                SC.gv.lastErr = ""
            elseif kind == "ERR" then
                SC.gv.lastErr = tostring(val or "ошибка")
                SetStatus("Сейф золота (ошибка): " .. SC.gv.lastErr)
            end
            NotifyUI()
        elseif a1 == "ASMSG_PEPE_STATE" or a1 == "ASMSG_PEPE_OPEN" then
            local c, m, s, n = msg:match("^(%d+)%s+(%d+)%s*(%d*)%s*(%d*)")
            if c then
                SC.pepe.cur = tonumber(c) or 0
                SC.pepe.mask = tonumber(m) or 0
                SC.pepe.sel = tonumber(s) or 0
                SC.pepe.slots = tonumber(n) or math_min(5, CountBits(SC.pepe.mask))
                if SC.pepe.cur > 0 then SC.pepe.prevSkin = SC.pepe.cur end
                SC.pepe.loaded = true
                NotifyUI()
            end
        elseif a1 == "ASMSG_DUNGEON_LEVEL_INFO_RESPONSE" then
            local lv = tonumber(msg)
            if lv then SC.dung.tier = lv; NotifyUI() end
        elseif a1 == "ASMSG_AOE_LOOT_TOGGLE" then
            if msg == "1" or msg == "0" then SC.dung.aoeLoot = (msg == "1"); NotifyUI() end
        elseif a1 == "ASMSG_MPLUS_EPIC_OFF" then
            SC.dung.mythic = false
            NotifyUI()
        elseif a1 == "ASMSG_PARAGON_DATA_RESPONSE" or a1 == "ASMSG_PARAGON_XP" or a1 == "ASMSG_NECK_INFO" then
            local lvl, xp, nxt, mx, bp
            if a1 == "ASMSG_PARAGON_DATA_RESPONSE" then
                local kv = {}
                for k, v in msg:gmatch("([^:;]+):([^;]*)") do kv[k] = v end
                if kv.level == nil then return end
                lvl = tonumber(kv.level) or 0
                xp = tonumber(kv.experience) or 0
                nxt = tonumber(kv.expMax) or 0
                mx = 1000
                bp = 0
                SC.neck.isParagonHT = true
            elseif a1 == "ASMSG_PARAGON_XP" then
                local e, r, lv = strsplit("\t", msg)
                lvl = tonumber(lv) or 0
                xp = tonumber(e) or 0
                nxt = tonumber(r) or 0
                mx = 1000
                bp = 0
                SC.neck.isParagonHT = true
            else
                local sd = rawget(_G, "serverData")
                if SC.neck.isParagonHT or (type(sd) == "table" and (tonumber(sd.level) or 0) > 0) then
                    return
                end
                local l, x, nx, mxx, bpp = strsplit(":", msg)
                lvl = tonumber(l) or 0; xp = tonumber(x) or 0; nxt = tonumber(nx) or 0
                mx = tonumber(mxx) or 1000; bp = tonumber(bpp) or 0
            end
            local now = GetTime()
            if SC.neck.sessionStart == 0 then
                SC.neck.sessionStart = now
                SC.neck.prevAbs = xp
            else
                local delta = xp - (SC.neck.prevAbs or xp)
                if delta > 0 then
                    SC.neck.gainedXP = SC.neck.gainedXP + delta
                elseif delta < 0 and lvl > (SC.neck.level or 0) then
                    local prevRem = math_max(0, (SC.neck.nextXP or 0) - (SC.neck.prevAbs or 0))
                    SC.neck.gainedXP = SC.neck.gainedXP + prevRem + xp
                end
                SC.neck.prevAbs = xp
            end
            SC.neck.level = lvl; SC.neck.xp = xp; SC.neck.nextXP = nxt
            SC.neck.maxLvl = mx; SC.neck.bonusPct = bp
            local hrs = math_max(1 / 3600, (now - SC.neck.sessionStart) / 3600)
            SC.neck.ratePerHr = SC.neck.gainedXP / hrs
            SC.neck.etaSec = (SC.neck.ratePerHr > 0 and nxt > xp) and ((nxt - xp) / (SC.neck.ratePerHr / 3600)) or 0
            NotifyUI()
        end
    end
end)

---------------------------------------------------------------------------
-- 7. Tab 5 UI Builder ("Сервер и Билды") inside TalorianTP
---------------------------------------------------------------------------
function TTP.BuildServerCtrlPanel(parent, mainF)
    local PS = TTP.Skin
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel:Hide()
    SC.panel = panel

    local colW, colH, gap = 282, 386, 9
    local cols = {}
    for i = 1, 3 do
        local c = CreateFrame("Frame", nil, panel)
        c:SetSize(colW, colH)
        c:SetPoint("TOPLEFT", panel, "TOPLEFT", (i - 1) * (colW + gap), -2)
        PS.StyleBox(c, 0.48, false)
        cols[i] = c
    end
    local c1, c2, c3 = cols[1], cols[2], cols[3]

    local function AddColDiv(c, y)
        local d = c:CreateTexture(nil, "ARTWORK")
        d:SetTexture("Interface\\Buttons\\WHITE8X8")
        d:SetVertexColor(1, 1, 1, 0.08)
        d:SetHeight(1)
        d:SetPoint("TOPLEFT", c, "TOPLEFT", 10, y)
        d:SetPoint("TOPRIGHT", c, "TOPRIGHT", -10, y)
        return d
    end
    AddColDiv(c1, -208)
    AddColDiv(c1, -298)
    AddColDiv(c2, -156)
    AddColDiv(c2, -252)
    AddColDiv(c3, -208)

    local srvEmptyTxt = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    srvEmptyTxt:SetPoint("CENTER", panel, "CENTER", 0, 10)
    srvEmptyTxt:SetText("|cff94a3b8Все блоки вкладки «Спутники и Наборы» скрыты.\nВключить их можно в Настройках или командой /ttp blocks.|r")
    srvEmptyTxt:Hide()

    function panel:RefreshLayout()
        local vis = {}
        local keys = { "srvCol1", "srvCol2", "srvCol3" }
        for i = 1, 3 do
            local on = (type(TalorianTP.IsBlockEnabled) ~= "function") or TalorianTP:IsBlockEnabled(keys[i])
            if on then
                vis[#vis + 1] = cols[i]
                cols[i]:Show()
            else
                cols[i]:Hide()
            end
        end
        if #vis == 0 then
            srvEmptyTxt:Show()
            return
        end
        srvEmptyTxt:Hide()
        local totalW = #vis * colW + (#vis - 1) * gap
        local startX = math.max(0, math.floor((864 - totalW) / 2))
        for idx, c in ipairs(vis) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", panel, "TOPLEFT", startX + (idx - 1) * (colW + gap), -2)
        end
    end

    local function MakeBtn(p, x, y, w, h, label, kind, onClick, tipTitle, tipBody)
        local b = CreateFrame("Button", nil, p)
        b:SetSize(w, h)
        b:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
        PS.StyleBtn(b, kind or "dark")
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", 0, 0)
        fs:SetText(label)
        b.txt = fs
        if onClick then b:SetScript("OnClick", onClick) end
        if tipTitle then
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(tipTitle, 1, 0.82, 0)
                if tipBody then GameTooltip:AddLine(tipBody, 0.9, 0.9, 0.9, true) end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return b
    end

    -- ==== COLUMN 1: Talorian buffs + Retinue + Gold Vault ====
    local h1 = c1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h1:SetPoint("TOPLEFT", 10, -8)
    h1:SetText("|cffffd200Баффы помощника|r")

    local buffBtns = {}
    for i, bf in ipairs(TAL_BUFFS) do
        local col = (i - 1) % 2
        local row = math_floor((i - 1) / 2)
        local b = MakeBtn(c1, 8 + col * 135, -28 - row * 22, 131, 20, bf.label, "dark", function()
            SC:ToggleTalBuffBit(bf.bit, bf.pal)
        end)
        buffBtns[i] = { btn = b, info = bf }
    end

    local talAutoBtn = MakeBtn(c1, 8, -162, 131, 20, "Автобафф: ?", "dark", function()
        SC:SetTalAuto(not SC.tal.auto)
    end)
    MakeBtn(c1, 143, -162, 131, 20, "Баффнуть сейчас", "green", function()
        SC:CastTalBuffNow()
    end)

    local favBtn = MakeBtn(c1, 8, -185, 266, 20, "В избр.: ?", "dark", function()
        local cur = TalorianTP_DB and TalorianTP_DB.targetRaid
        if cur then SC:ToggleTalFav(cur) end
    end, "Избранный телепорт", "Добавить или убрать текущую выбранную цель из быстрого списка Талориана.")

    local retHdr = c1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    retHdr:SetPoint("TOPLEFT", 10, -214)
    retHdr:SetText("|cffffd200Дополнительные спутники|r")

    local retBtns = {}
    for i, rk in ipairs(RET_KINDS) do
        local col = (i - 1) % 2
        local row = math_floor((i - 1) / 2)
        local b = MakeBtn(c1, 8 + col * 135, -232 - row * 22, 131, 20, rk.label .. ": ?", "dark", function()
            SC:CycleRetinueSlot(rk.kind)
        end)
        retBtns[rk.kind] = { btn = b, label = rk.label }
    end
    local retAutoBtn = MakeBtn(c1, 8, -276, 184, 20, "Автопризыв: ?", "dark", function()
        SC:ToggleRetResummon()
    end)
    MakeBtn(c1, 196, -276, 78, 20, "Сброс", "dark", function() SC:ResetRetinue() end)

    local gvHdr = c1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gvHdr:SetPoint("TOPLEFT", 10, -304)
    gvHdr:SetText("|cffffd200Личный сейф золота|r")

    local gvBalTxt = c1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gvBalTxt:SetPoint("TOPLEFT", 10, -322)
    gvBalTxt:SetSize(262, 16)
    gvBalTxt:SetJustifyH("LEFT")

    MakeBtn(c1, 8, -340, 84, 20, "+1000 зол.", "dark", function() SC:GoldVaultTransfer("dep", 1000 * 10000) end,
        "Пополнить сейф", "Перевести 1 000 золотых из сумок в личный сейф.")
    MakeBtn(c1, 96, -340, 96, 20, "Сверх 5000", "green", function() SC:GoldVaultTransfer("dep_excess", 0) end,
        "Сдать излишек", "Оставить в сумках ровно 5 000 золотых, остальное перевести в сейф.")
    MakeBtn(c1, 196, -340, 78, 20, "-1000 зол.", "dark", function() SC:GoldVaultTransfer("wd", 1000 * 10000) end,
        "Снять из сейфа", "Забрать 1 000 золотых из сейфа в сумки.")

    MakeBtn(c1, 8, -362, 266, 18, "Обновить баланс и спутников", "dark", function() SC:RequestAllStates() end)

    -- ==== COLUMN 2: Talisman Presets + Dungeon/Loot + Metrics ====
    local h2 = c2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h2:SetPoint("TOPLEFT", 10, -8)
    h2:SetText("|cffffd200Талисман на голову и бонусы|r")

    local pepeInfo = c2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pepeInfo:SetPoint("TOPLEFT", 10, -26)
    pepeInfo:SetSize(262, 32)
    pepeInfo:SetJustifyH("LEFT")
    pepeInfo:SetJustifyV("TOP")

    local pepeToggleBtn = MakeBtn(c2, 8, -60, 131, 20, "Талисман: ?", "dark", function() SC:TogglePepeSummon() end,
        "Талисман (Пепе)", "Надеть или снять спутника с головы.")
    local pepeMerchBtn = MakeBtn(c2, 143, -60, 131, 20, "У торговца: ?", "dark", function()
        local db = EnsureSCDB()
        db.autoPepeMerchant = not db.autoPepeMerchant
        NotifyUI()
    end, "Режим у торговца", "При открытии торговца временно переключает бонусы на «Торг и Ремонт» (-5% цен и -50% ремонта), а после закрытия возвращает прежние.")

    MakeBtn(c2, 8, -84, 174, 20, "Набор: Путь и Фарм", "green", function() SC:ApplyPepePreset("travel") end)
    MakeBtn(c2, 186, -84, 88, 20, "Сохранить", "dark", function() SC:SavePepePreset("travel") end)

    MakeBtn(c2, 8, -108, 174, 20, "Набор: Торг и Ремонт", "green", function() SC:ApplyPepePreset("merchant") end)
    MakeBtn(c2, 186, -108, 88, 20, "Сохранить", "dark", function() SC:SavePepePreset("merchant") end)

    MakeBtn(c2, 8, -132, 174, 20, "Набор: Свой #3", "dark", function() SC:ApplyPepePreset("custom") end)
    MakeBtn(c2, 186, -132, 88, 20, "Сохранить", "dark", function() SC:SavePepePreset("custom") end)

    local dngHdr = c2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dngHdr:SetPoint("TOPLEFT", 10, -162)
    dngHdr:SetText("|cffffd200Сложность подземелий и автолут|r")

    local tierNames = { "Необычная", "Эпическая", "Легендарная", "Титаническая" }
    local tierTips = {
        {
            "|cff1eff001: Необычная сложность|r",
            "Вы: урон -20%, получаемое исцеление -15%, |cff40ff40опыт +30%|r\nПротивники: здоровье x1.48, удар >= 18% (боссы 36%), крит +20% (боссы +24%).",
        },
        {
            "|cffbb79e82: Эпическая сложность|r",
            "Вы: урон -40%, укл/пар/блок -15, броня -15%, хил -30%, |cff40ff40опыт +60%|r\nПротивники: здоровье x2.18, удар >= 60% (боссы 120%), крит +33% (боссы +40%).",
        },
        {
            "|cffff80003: Легендарная сложность|r",
            "Вы: урон -60%, укл/пар/блок -40, броня -45%, хил -50%, |cff40ff40опыт +120%|r\nПротивники: здоровье x2.96, удар >= 90% (боссы 180%), крит +42% (боссы +50%).",
        },
        {
            "|cff00ffcc4: Титаническая сложность|r",
            "Вы: урон -75%, укл/пар/блок -75, броня -65%, хил -80%, |cff40ff40опыт +200%|r\nПротивники: здоровье x3.80, удар >= 118% (боссы 236%), крит +48% (боссы +57.6%).",
        },
    }
    local tierBtns = {}
    for lv = 1, 4 do
        local col = (lv - 1) % 2
        local row = math_floor((lv - 1) / 2)
        local b = MakeBtn(c2, 8 + col * 135, -180 - row * 22, 131, 20, lv .. ": " .. tierNames[lv], "dark", function()
            SC:SetDungeonTier(lv)
        end, tierTips[lv][1], tierTips[lv][2])
        tierBtns[lv] = b
    end
    local mythicBtn = MakeBtn(c2, 8, -226, 131, 20, "Эпохальный: ?", "dark", function() SC:ToggleMythic() end,
        "Эпохальный режим", "Включает сложность подземелья для запуска ключей Mythic+ (вне группы и вне боя).")
    local aoeBtn = MakeBtn(c2, 143, -226, 131, 20, "Автосбор: ?", "dark", function() SC:ToggleAoELoot() end,
        "Автосбор добычи (AoE Loot)", "Включает или выключает автоматический сбор добычи со всех ближайших врагов.")

    local mtrHdr = c2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mtrHdr:SetPoint("TOPLEFT", 10, -258)
    mtrHdr:SetText("|cffffd200Счетчик урона и прогресс уровня|r")

    local mtrTxt = c2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mtrTxt:SetPoint("TOPLEFT", 10, -278)
    mtrTxt:SetSize(262, 96)
    mtrTxt:SetJustifyH("LEFT")
    mtrTxt:SetJustifyV("TOP")

    -- ==== COLUMN 3: Build Presets + 3D HUD ====
    local h3 = c3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h3:SetPoint("TOPLEFT", 10, -8)
    h3:SetText("|cffffd200Пресеты талантов и ковки|r")

    local buildRows = {}
    for idx = 1, 3 do
        local yBase = -30 - (idx - 1) * 58
        local lbl = c3:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl.idx = idx
        lbl:SetPoint("TOPLEFT", 10, yBase)
        lbl:SetSize(262, 26)
        lbl:SetJustifyH("LEFT")
        lbl:SetJustifyV("TOP")

        local appBtn = MakeBtn(c3, 8, yBase - 28, 131, 22, "Применить #" .. idx, "green", function() SC:ApplyBuildPreset(idx) end)
        local savBtn = MakeBtn(c3, 143, yBase - 28, 131, 22, "Сохранить #" .. idx, "dark", function() SC:CaptureBuildPreset(idx) end)
        buildRows[idx] = { lbl = lbl, app = appBtn, sav = savBtn }
    end

    local hudHdr = c3:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hudHdr:SetPoint("TOPLEFT", 10, -214)
    hudHdr:SetText("|cffffd200Указатель цели и подсветка|r")

    local hudToggleBtn = MakeBtn(c3, 8, -234, 266, 22, "Стрелка к цели: ?", "dark", function()
        local db = EnsureSCDB()
        db.hudEnabled = not db.hudEnabled
        SC:UpdateHUDVisibility()
        NotifyUI()
    end)
    local qncToggleBtn = MakeBtn(c3, 8, -260, 266, 22, "Подсветка цели и фокуса: ?", "dark", function()
        local db = EnsureSCDB()
        db.qncEnabled = not db.qncEnabled
        SC:RefreshQNCHighlight()
        NotifyUI()
    end)
    MakeBtn(c3, 8, -286, 131, 20, "Поставить метку", "dark", function() SC:SetCustomPinHere() end)
    MakeBtn(c3, 143, -286, 131, 20, "Снять метку", "dark", function() SC:ClearCustomPin() end)

    local scStatusTxt = c3:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scStatusTxt:SetPoint("TOPLEFT", 10, -314)
    scStatusTxt:SetSize(262, 62)
    scStatusTxt:SetJustifyH("LEFT")
    scStatusTxt:SetJustifyV("TOP")

    function panel:Refresh()
        if self.RefreshLayout then self:RefreshLayout() end
        local db = EnsureSCDB()
        SC:SyncPepeFromGlobal()

        for _, row in ipairs(buffBtns) do
            local on = HasBit(SC.tal.mask, row.info.bit)
            PS.PaintBtn(row.btn, on and "green" or "dark")
        end
        PS.PaintBtn(talAutoBtn, SC.tal.auto and "green" or "dark")
        talAutoBtn.txt:SetText("Автобафф: " .. (SC.tal.auto and "ВКЛ" or "ВЫКЛ"))

        local curDest = (TalorianTP_DB and TalorianTP_DB.targetRaid) or "Цитадель Ледяной Короны"
        local isFav = SC.tal.fav[curDest] == true
        PS.PaintBtn(favBtn, isFav and "gold" or "dark")
        favBtn.txt:SetText((isFav and "Убрать из избр.: " or "В избр.: ") .. Utf8CropChars(curDest, 22))

        for k, entry in pairs(retBtns) do
            local sIdx = SC.ret.slots[k] or 0
            entry.btn.txt:SetText(entry.label .. ": " .. (RET_SLOTS[sIdx] or "?"))
        end
        PS.PaintBtn(retAutoBtn, SC.ret.resummon and "green" or "dark")
        retAutoBtn.txt:SetText("Автопризыв: " .. (SC.ret.resummon and "ВКЛ" or "ВЫКЛ"))

        local balStr = (SC.gv.balance ~= nil) and FormatGold(SC.gv.balance) or "|cff94a3b8? (подойдите к банку)|r"
        gvBalTxt:SetText("В сейфе: |cffffd200" .. balStr .. "|r")

        local pActCnt = CountBits(SC.pepe.sel)
        local pNames = {}
        for i = 1, 21 do
            if HasBit(SC.pepe.sel, i - 1) then pNames[#pNames + 1] = ResolvePepePerkName(i) end
        end
        pepeInfo:SetText(string.format("%s | Бонусов: |cff40ff40%d/%d|r\n%s",
            ResolvePepeSkinName(SC.pepe.cur),
            pActCnt, SC.pepe.slots or 0,
            (#pNames > 0) and Utf8CropChars(table.concat(pNames, ", "), 46) or "|cff94a3b8Нет активных бонусов|r"))
        PS.PaintBtn(pepeToggleBtn, (SC.pepe.cur > 0) and "green" or "dark")
        pepeToggleBtn.txt:SetText("Талисман: " .. ((SC.pepe.cur > 0) and "ВКЛ" or "ВЫКЛ"))
        PS.PaintBtn(pepeMerchBtn, db.autoPepeMerchant and "green" or "dark")
        pepeMerchBtn.txt:SetText("У торговца: " .. (db.autoPepeMerchant and "ВКЛ" or "ВЫКЛ"))

        for lv = 1, 4 do
            PS.PaintBtn(tierBtns[lv], (SC.dung.tier == lv) and "gold" or "dark")
        end
        PS.PaintBtn(mythicBtn, SC.dung.mythic and "green" or "dark")
        mythicBtn.txt:SetText("Эпохальный: " .. (SC.dung.mythic and "ВКЛ" or "ВЫКЛ"))
        local aoeOn = (SC.dung.aoeLoot ~= nil) and SC.dung.aoeLoot or (type(GetCVar) == "function" and GetCVar("aoeLootEnabled") == "1")
        PS.PaintBtn(aoeBtn, aoeOn and "green" or "dark")
        aoeBtn.txt:SetText("Автосбор: " .. (aoeOn and "ВКЛ" or "ВЫКЛ"))

        local mtr = SC.mtr
        local nk = SC.neck
        local sd = rawget(_G, "serverData")
        if type(sd) == "table" and ((tonumber(sd.level) or 0) > 0 or (tonumber(sd.expMax) or 0) > 0) then
            local sl, sx, sn = tonumber(sd.level) or 0, tonumber(sd.experience) or 0, tonumber(sd.expMax) or 0
            if (nk.sessionStart or 0) == 0 then
                nk.sessionStart = GetTime and GetTime() or 1
                nk.prevAbs = sx
            end
            if sl > (nk.level or 0) or (sl == (nk.level or 0) and sx > (nk.xp or 0)) then
                nk.level = sl
                nk.xp = sx
                nk.nextXP = sn
            end
        end
        mtrTxt:SetText(string.format(
            "Общий урон: |cffffffff%s|r\nDPS: |cff40ff40%s/с|r | Пик: |cffff8040%s|r\nДоп. уровень: |cffffd200%d|r (%s / %s)\nТемп XP/ч: |cff38bdf8%s|r%s",
            FormatShortNum(mtr.totalDmg), FormatShortNum(mtr.dps), FormatShortNum(mtr.peakHit),
            nk.level, FormatShortNum(nk.xp), FormatShortNum(nk.nextXP),
            FormatShortNum(nk.ratePerHr), (nk.bonusPct > 0) and (" (+" .. nk.bonusPct .. "%)") or ""
        ))

        for idx = 1, 3 do
            local p = db.buildPresets[idx]
            local row = buildRows[idx]
            if p then
                row.lbl:SetText(string.format("|cff40ff40%s|r\nСпек #%d | Таланты: %d шт | Ковка: %d+%d",
                    tostring(p.name or ("Набор #" .. idx)), p.specGroup or 1, #(p.pearkSetIds or {}), p.sfV2 or 0, p.sfV4 or 0))
                PS.PaintBtn(row.app, "green")
            else
                row.lbl:SetText("|cff94a3b8Слот #" .. idx .. " пуст (сохраните активный спек)|r")
                PS.PaintBtn(row.app, "gray")
            end
        end

        PS.PaintBtn(hudToggleBtn, db.hudEnabled and "green" or "dark")
        hudToggleBtn.txt:SetText("Стрелка к цели: " .. (db.hudEnabled and "ВКЛ" or "ВЫКЛ"))
        PS.PaintBtn(qncToggleBtn, db.qncEnabled and "green" or "dark")
        qncToggleBtn.txt:SetText("Подсветка цели: " .. (db.qncEnabled and "ВКЛ" or "ВЫКЛ"))

        if SC.statusAt and SC.statusAt > 0 and (GetTime() - SC.statusAt) > 10 then
            SC.statusLine = ""
            SC.statusAt = 0
        end
        scStatusTxt:SetText((SC.statusLine ~= "" and SC.statusLine or "|cff94a3b8Готово. Метка на карте: " .. (SC.hud.pin and "установлена" or "нет") .. "|r"))
    end

    return panel
end

function TTP.OpenServerTab()
    TalorianTP_DB = TalorianTP_DB or {}
    TalorianTP_DB.activeTab = 5
    local ui = nil
    if type(TTP.OpenUI) == "function" then
        ui = TTP:OpenUI(5)
    elseif SlashCmdList and SlashCmdList["TALORIANTP"] then
        SlashCmdList["TALORIANTP"]("show")
    end
    return ui
end

---------------------------------------------------------------------------
-- 8. Slash command extensions (/ttp server|build|hud|pepe|gv)
---------------------------------------------------------------------------
do
    local origSlash = SlashCmdList and SlashCmdList["TALORIANTP"]
    if type(origSlash) == "function" then
        SlashCmdList["TALORIANTP"] = function(msg)
            local norm = msg and msg:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
            if norm == "server" or norm == "hub" or norm == "ctrl" or norm == "pepe" or norm == "build" or norm == "gv" then
                TTP.OpenServerTab()
                return
            elseif norm == "hud" then
                local db = EnsureSCDB()
                db.hudEnabled = not db.hudEnabled
                SC:UpdateHUDVisibility()
                NotifyUI()
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage("|cff38bdf8[Talorian]|r Указатель цели: " .. (db.hudEnabled and "ВКЛ" or "ВЫКЛ"))
                end
                return
            end
            return origSlash(msg)
        end
    end
end

end
