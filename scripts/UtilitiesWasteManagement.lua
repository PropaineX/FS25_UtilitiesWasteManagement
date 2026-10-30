-- Utilities & Waste Management: farms trade electricity, slurry and manure through invoices.
-- Author: PropaineX
--
-- Startup, savegame, sync for joining players, notifications and the finance rows. The trading and depot rules
-- are in UWMManager, the storages in UWMStock, the depot building in UWMDepot (a placeable specialization), the
-- ESC page in gui/UWMFrame.lua.

UtilitiesWasteManagement = {}
local UWM = UtilitiesWasteManagement

UWM.modName = g_currentModName
UWM.modDirectory = g_currentModDirectory
UWM.TAG = "[UtilitiesWasteManagement]"
UWM.SAVE_FILENAME = "utilitiesWasteManagement.xml"

-- the traded goods, in menu order; fill types missing from the game are left out at load
UWM.GOODS_DEFINITION = {
    {fillTypeName = "ELECTRICCHARGE", textKey = "uwm_good_electricity"},
    {fillTypeName = "LIQUIDMANURE", textKey = "uwm_good_slurry"},
    {fillTypeName = "MANURE", textKey = "uwm_good_manure"}
}
UWM.goods = {}

UWM.manager = nil

-- Finance page rows: the stat names must exist before farms build their statistics
local function registerFinanceStat(statName)
    if FinanceStats ~= nil and FinanceStats.statNameToIndex[statName] == nil then
        table.insert(FinanceStats.statNames, statName)
        FinanceStats.statNameToIndex[statName] = #FinanceStats.statNames
    end
end
registerFinanceStat("uwmIncome")
registerFinanceStat("uwmExpense")
registerFinanceStat("uwmDepotIncome")
registerFinanceStat("uwmDepotExpense")

function UWM.getText(key)
    return g_i18n:getText(key, UWM.modName)
end

function UWM.getGood(fillTypeIndex)
    for _, good in ipairs(UWM.goods) do
        if good.fillTypeIndex == fillTypeIndex then
            return good
        end
    end
    return nil
end

-- bulk goods (user, 2026-10-28): anything the game files under BULK (grain, root crops, lime, woodchips ...),
-- picked from the Bulk list; our own three goods keep their own rows (manure is BULK in the game too)
function UWM.getIsBulk(fillTypeIndex)
    if fillTypeIndex == nil or fillTypeIndex == FillType.UNKNOWN or UWM.getGood(fillTypeIndex) ~= nil then
        return false
    end
    return g_fillTypeManager.getIsFillTypeInCategory ~= nil and g_fillTypeManager:getIsFillTypeInCategory(fillTypeIndex, "BULK")
end

-- may this be put on an invoice / standing order?
function UWM.getIsTradable(fillTypeIndex)
    return UWM.getGood(fillTypeIndex) ~= nil or UWM.getIsBulk(fillTypeIndex) or UWMPallets.getIsPalletGood(fillTypeIndex)
end

function UWM.getGoodName(fillTypeIndex)
    local good = UWM.getGood(fillTypeIndex)
    if good ~= nil then
        return UWM.getText(good.textKey)
    end
    local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    return fillType ~= nil and fillType.title or "?"
end

function UWM.formatAmount(fillTypeIndex, liters)
    if fillTypeIndex == FillType.ELECTRICCHARGE then
        local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
        local unit = fillType ~= nil and fillType.unitShort or nil
        if unit ~= nil and unit ~= "" then
            return string.format("%s %s", g_i18n:formatNumber(liters, 0), unit)
        end
    end
    return g_i18n:formatVolume(liters, 0)
end

function UWM.formatMoney(amount)
    return g_i18n:formatMoney(amount, 0, true, true)
end

-- current local player: farm id and whether they may trade for it
function UWM.getLocalFarmId()
    return g_currentMission:getFarmId()
end

function UWM.getLocalIsManager()
    local farmId = UWM.getLocalFarmId()
    if not UWMManager.getIsTradingFarm(farmId) then
        return false
    end
    if not g_currentMission.missionDynamicInfo.isMultiplayer then
        return true
    end
    local farm = g_farmManager:getFarmById(farmId)
    return farm ~= nil and farm.isUserFarmManager ~= nil and farm:isUserFarmManager(g_currentMission.playerUserId)
end

----------------------------------------------------------------------------------------------------------------
-- Mod event listener
----------------------------------------------------------------------------------------------------------------

function UWM:loadMap(filename)
    UWM.goods = {}
    for _, definition in ipairs(UWM.GOODS_DEFINITION) do
        local fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(definition.fillTypeName)
        if fillTypeIndex ~= nil then
            table.insert(UWM.goods, {fillTypeIndex = fillTypeIndex, textKey = definition.textKey})
        else
            print(string.format("%s fill type %s not in this game, %s can't be traded", UWM.TAG, definition.fillTypeName, definition.textKey))
        end
    end

    if MoneyType.UWM_INCOME == nil and MoneyType.register ~= nil then
        MoneyType.UWM_INCOME = MoneyType.register("uwmIncome", "uwm_finance_income")
        MoneyType.UWM_EXPENSE = MoneyType.register("uwmExpense", "uwm_finance_expense")
    end
    if MoneyType.UWM_DEPOT_INCOME == nil and MoneyType.register ~= nil then
        MoneyType.UWM_DEPOT_INCOME = MoneyType.register("uwmDepotIncome", "uwm_finance_depotIncome")
        MoneyType.UWM_DEPOT_EXPENSE = MoneyType.register("uwmDepotExpense", "uwm_finance_depotExpense")
    end
    MoneyType.UWM_INCOME = MoneyType.UWM_INCOME or MoneyType.SOLD_PRODUCTS
    MoneyType.UWM_EXPENSE = MoneyType.UWM_EXPENSE or MoneyType.BOUGHT_MATERIALS
    MoneyType.UWM_DEPOT_INCOME = MoneyType.UWM_DEPOT_INCOME or MoneyType.PROPERTY_INCOME or MoneyType.UWM_INCOME
    MoneyType.UWM_DEPOT_EXPENSE = MoneyType.UWM_DEPOT_EXPENSE or MoneyType.PROPERTY_MAINTENANCE or MoneyType.UWM_EXPENSE

    local isServer = g_currentMission:getIsServer()
    UWM.manager = UWMManager.new(isServer)

    if isServer then
        local directory = g_currentMission.missionInfo.savegameDirectory
        if directory ~= nil then
            UWM.manager:loadFromXMLFile(directory .. "/" .. UWM.SAVE_FILENAME)
        end
    end
    -- clients need it too: the load trigger asks the station whether the player's vehicle may load, and for the list
    UWMPickup.installHooks()
    UWMStock.installProductionHooks()

    g_messageCenter:subscribe(MessageType.DAY_CHANGED, UWM.onDayChanged, UWM)
    if MessageType.PERIOD_CHANGED ~= nil then
        g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, UWM.onPeriodChanged, UWM)
    end

    print(string.format("%s loaded (%d goods)", UWM.TAG, #UWM.goods))
end

function UWM:deleteMap()
    g_messageCenter:unsubscribeAll(UWM)
    UWMPickup.removeHooks()
    if UWM.manager ~= nil then
        UWM.manager:delete()
        UWM.manager = nil
    end
    UWMFrame.unregister()
end

function UWM:update(dt)
    if UWM.manager ~= nil then
        UWM.manager:update(dt)
    end
end

function UWM:onDayChanged()
    if UWM.manager ~= nil then
        UWM.manager:onDayChanged()
    end
end

function UWM:onPeriodChanged()
    if UWM.manager ~= nil then
        UWM.manager:onPeriodChanged()
    end
end

addModEventListener(UWM)

----------------------------------------------------------------------------------------------------------------
-- Messages to the player
----------------------------------------------------------------------------------------------------------------

function UWM.showNotification(farmId, key, farmName, fillTypeIndex, detail)
    if g_currentMission == nil or not g_currentMission:getIsClient() or farmId ~= UWM.getLocalFarmId() then
        return
    end
    local text
    if key:find("^uwm_notify_depot") ~= nil then
        -- depot messages: the depot owner(s), then an amount or a farm name
        text = string.format(UWM.getText(key), farmName, detail or "")
    else
        text = string.format(UWM.getText(key), farmName, UWM.getGoodName(fillTypeIndex), detail or "")
    end
    local notificationType = FSBaseMission.INGAME_NOTIFICATION_INFO
    if key == "uwm_notify_contractFailed" or key == "uwm_notify_depotUnpaid" or key == "uwm_notify_depotSuspended"
        or key == "uwm_notify_depotArrears" then
        notificationType = FSBaseMission.INGAME_NOTIFICATION_CRITICAL
    end
    g_currentMission:addIngameNotification(notificationType, text)
end

-- the server's answer to this player's own request
function UWM.onRequestResult(ok, key)
    if key == nil or key == "" then
        return
    end
    local notificationType = ok and FSBaseMission.INGAME_NOTIFICATION_OK or FSBaseMission.INGAME_NOTIFICATION_CRITICAL
    g_currentMission:addIngameNotification(notificationType, UWM.getText(key))
end

----------------------------------------------------------------------------------------------------------------
-- Game hooks
----------------------------------------------------------------------------------------------------------------

-- Saving: written next to items.xml from ItemSystem.save, so it lands in the folder the game is really writing
-- (the game saves into a temporary folder and swaps it in; FSBaseMission.saveSavegame can miss that).
local function onItemSystemSave(itemSystem, xmlFilename, ...)
    if UWM.manager ~= nil and UWM.manager.isServer and xmlFilename ~= nil then
        local directory = xmlFilename:match("^(.*)[/\\][^/\\]*$")
        if directory ~= nil then
            UWM.manager:saveToXMLFile(directory .. "/" .. UWM.SAVE_FILENAME)
        end
    end
end

local function onSendInitialClientState(mission, connection, user, farm)
    if UWM.manager ~= nil and connection ~= nil then
        connection:sendEvent(UWMSyncEvent.new(UWM.manager))
    end
end

local function onLoadMission00Finished(mission)
    UWMFrame.register()
    UWMOrderDialog.register()
    UWMCoopDialog.register()
end

-- the finance page asks for "finance_<stat>" without a mod environment; answer ours from this mod's texts
local FINANCE_TEXTS = {finance_uwmIncome = true, finance_uwmExpense = true, uwm_finance_income = true, uwm_finance_expense = true,
    finance_uwmDepotIncome = true, finance_uwmDepotExpense = true, uwm_finance_depotIncome = true, uwm_finance_depotExpense = true}
local function getText(i18n, superFunc, text, modEnv)
    if modEnv == nil and FINANCE_TEXTS[text] then
        return superFunc(i18n, text, UWM.modName)
    end
    return superFunc(i18n, text, modEnv)
end

-- Class hooks dispatch through these handler fields, set again by each run of this file, so hooks left from an
-- earlier savegame call the current code.
ItemSystem.uwmSaveHandler = onItemSystemSave
FSBaseMission.uwmJoinHandler = onSendInitialClientState
Mission00.uwmLoadedHandler = onLoadMission00Finished
I18N.uwmTextHandler = getText

if not ItemSystem.uwmHooked then
    ItemSystem.uwmHooked = true
    ItemSystem.save = Utils.prependedFunction(ItemSystem.save, function(...)
        if ItemSystem.uwmSaveHandler ~= nil then
            ItemSystem.uwmSaveHandler(...)
        end
    end)
    FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, function(...)
        if FSBaseMission.uwmJoinHandler ~= nil then
            FSBaseMission.uwmJoinHandler(...)
        end
    end)
    Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function(...)
        if Mission00.uwmLoadedHandler ~= nil then
            Mission00.uwmLoadedHandler(...)
        end
    end)
    I18N.getText = Utils.overwrittenFunction(I18N.getText, function(i18n, superFunc, text, modEnv)
        if I18N.uwmTextHandler ~= nil then
            return I18N.uwmTextHandler(i18n, superFunc, text, modEnv)
        end
        return superFunc(i18n, text, modEnv)
    end)
end
