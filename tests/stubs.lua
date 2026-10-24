-- fake game for headless tests of the Utilities & Waste Management scripts
function Class(members, baseClass)
    members = members or {}
    local mt = {__index = members}
    if baseClass ~= nil then setmetatable(members, {__index = baseClass}) end
    members.superClass = function() return baseClass end
    return mt
end
Event = {new = function(mt) return setmetatable({}, mt) end}
function InitEventClass() end
FillType = {UNKNOWN = 0, ELECTRICCHARGE = 1, LIQUIDMANURE = 2, MANURE = 3}
local FT_NAMES = {"ELECTRICCHARGE", "LIQUIDMANURE", "MANURE"}
g_fillTypeManager = {
    getFillTypeIndexByName = function(_, n) for i, v in ipairs(FT_NAMES) do if v == n then return i end end return nil end,
    getFillTypeByIndex = function(_, i) if FT_NAMES[i] then return {name = FT_NAMES[i], title = FT_NAMES[i], pricePerLiter = 0.02} end end
}
FarmManager = {SPECTATOR_FARM_ID = 0}
MoneyType = {SOLD_PRODUCTS = 1, BOUGHT_MATERIALS = 2, register = function(n) return n end}
Logging = {warning = function(f, ...) print("WARNING " .. string.format(f, ...)) end}
Utils = {
    prependedFunction = function(a, b) return function(...) b(...) return a(...) end end,
    appendedFunction = function(a, b) return function(...) local r = a(...) b(...) return r end end,
    overwrittenFunction = function(a, b) return function(s, ...) return b(s, a, ...) end end
}
FinanceStats = {statNames = {}, statNameToIndex = {}}
ItemSystem = {save = function() end}
FSBaseMission = {sendInitialClientState = function() end, INGAME_NOTIFICATION_INFO = 1, INGAME_NOTIFICATION_OK = 2, INGAME_NOTIFICATION_CRITICAL = 3}
Mission00 = {loadMission00Finished = function() end}
I18N = {getText = function(_, t) return t end}
function addModEventListener() end
g_currentModName = "FS25_UtilitiesWasteManagement"
g_currentModDirectory = ""
-- the ESC page: only its text builders are tested (gui/UWMFrame.lua is loaded after the scripts)
TabbedMenuFrameElement = {new = function() return {} end}
InputAction = {}

-- storages
Storage = {}
Storage.__index = Storage
function newStorage(levels, capacity)
    local s = setmetatable({fillLevels = {}, capacity = capacity or 100000}, Storage)
    for ft, l in pairs(levels) do s.fillLevels[ft] = l end
    return s
end
function Storage:getFillLevel(ft) return self.fillLevels[ft] or 0 end
function Storage:setFillLevel(l, ft) if self.fillLevels[ft] ~= nil then self.fillLevels[ft] = math.max(0, math.min(l, self.capacity)) end end
function Storage:getCapacity() return self.capacity end
function Storage:getFreeCapacity(ft) return self.capacity - self:getFillLevel(ft) end

local nextUid = 1
function newPlaceable(farmId, specName, spec, name)
    local p = {ownerFarmId = farmId, name = name or specName, uid = "p" .. nextUid}
    nextUid = nextUid + 1
    p[specName] = spec
    p.getOwnerFarmId = function(self) return self.ownerFarmId end
    p.getName = function(self) return self.name end
    p.getUniqueId = function(self) return self.uid end
    return p
end

-- farms / money
farms = {}
for id = 1, 3 do farms[id] = {farmId = id, name = "Farm" .. id, money = 10000, managers = {[id * 10] = true}} end
for _, f in pairs(farms) do f.getBalance = function(self) return self.money end; f.isUserFarmManager = function(self, u) return self.managers[u] == true end end
g_farmManager = {
    getFarmById = function(_, id) return farms[id] end,
    getFarmByUserId = function(_, u) for _, f in pairs(farms) do if f.managers[u] or (f.members and f.members[u]) then return f end end end,
    getFarms = function() return farms end
}

notifications = {}
g_currentMission = {
    placeableSystem = {placeables = {}, getPlaceableByUniqueId = function(self, id) for _, p in ipairs(self.placeables) do if p.uid == id then return p end end end},
    environment = {currentMonotonicDay = 1},
    missionDynamicInfo = {isMultiplayer = true},
    missionInfo = {savegameDirectory = nil},
    addMoney = function(_, amount, farmId) farms[farmId].money = farms[farmId].money + amount end,
    getIsServer = function() return true end,
    getIsClient = function() return false end,
    getFarmId = function() return 1 end,
    addIngameNotification = function() end,
}
g_messageCenter = {subscribe = function() end, unsubscribeAll = function() end}
MessageType = {DAY_CHANGED = 1, PERIOD_CHANGED = 2}
notificationDetails = {}
g_server = {broadcastEvent = function(_, ev) if ev.key then table.insert(notifications, ev.farmId .. ":" .. ev.key) table.insert(notificationDetails, ev.detail or "") end end}
-- texts: the real ones from modDesc.xml (run.py fills UWM_TEXTS), else the key
g_i18n = {getText = function(_, k) return (UWM_TEXTS ~= nil and UWM_TEXTS[k]) or k end, formatVolume = function(_, v) return tostring(v) end, formatMoney = function(_, v) return tostring(v) end, formatNumber = function(_, v) return tostring(v) end}

-- network stream: one queue
stream = {}
local function w(v) table.insert(stream, v) end
local function r() return table.remove(stream, 1) end
for _, n in ipairs({"Int32", "UInt8", "UInt16", "Float32", "String"}) do _G["streamWrite" .. n] = function(_, v) w(v) end; _G["streamRead" .. n] = function() return r() end end
function streamWriteBool(_, v) w(v and true or false) return v end
function streamReadBool() return r() end

-- loading station like the game's: only its owner farm may load, from its own storage
ToolType = {TRIGGER = 1}
LoadingStation = {}
function LoadingStation:getSupportedFillTypes() local s = {} for ft in pairs(self.storage.fillLevels) do s[ft] = true end return s end
function LoadingStation:getIsFillAllowedToFarm(farmId) return farmId == self.owningPlaceable:getOwnerFarmId() end
function LoadingStation:getAllFillLevels(farmId)
    if farmId ~= self.owningPlaceable:getOwnerFarmId() then return {}, 0 end
    local l = {} for ft, v in pairs(self.storage.fillLevels) do l[ft] = v end return l, self.storage.capacity
end
function LoadingStation:addFillLevelToFillableObject(object, fillUnitIndex, ft, delta)
    if object:getActiveFarm() ~= self.owningPlaceable:getOwnerFarmId() then return 0 end
    local take = math.min(delta, self.storage:getFillLevel(ft), object:getFillUnitFreeCapacity(fillUnitIndex))
    self.storage:setFillLevel(self.storage:getFillLevel(ft) - take, ft)
    return object:addFillUnitFillLevel(object:getActiveFarm(), fillUnitIndex, take, ft)
end
function newStation(placeable, storage) return setmetatable({isServer = true, owningPlaceable = placeable, storage = storage}, {__index = LoadingStation}) end
-- the depot's fill points: a loading station with no storage of its own (fillTypes from its XML)
function newDepotStation(placeable)
    return setmetatable({isServer = true, uwmIsDepot = true, owningPlaceable = placeable,
        storage = newStorage({[FillType.LIQUIDMANURE] = 0, [FillType.MANURE] = 0})}, {__index = LoadingStation})
end
-- a placed depot (what UWMDepot:onFinalizePlacement registers)
function newDepot(farmId, upkeep)
    local depot = newPlaceable(farmId, "spec_uwmDepot", {}, "Community Depot")
    depot.getDailyUpkeep = function() return upkeep or 0 end
    UWMDepot.placed[depot] = true
    return depot
end
function removeDepots() for depot in pairs(UWMDepot.placed) do UWMDepot.placed[depot] = nil end end
function newTanker(farmId, capacity)
    local v = {farmId = farmId, level = 0, capacity = capacity}
    v.getActiveFarm = function(self) return self.farmId end
    v.getFillUnitFreeCapacity = function(self) return self.capacity - self.level end
    v.addFillUnitFillLevel = function(self, _, _, delta) local add = math.min(delta, self.capacity - self.level) self.level = self.level + add return add end
    return v
end

-- network objects: written as a number, read back as the same object
local netObjects = {}
NetworkUtil = {
    writeNodeObject = function(_, object) table.insert(netObjects, object) w(#netObjects) end,
    readNodeObject = function() return netObjects[r()] end
}

-- XML file in memory
XMLFile = {files = {}}
XMLFile.__index = XMLFile
function XMLFile.create(_, filename) local x = setmetatable({filename = filename, data = {}}, XMLFile) return x end
function XMLFile.loadIfExists(_, filename) local d = XMLFile.files[filename] if d == nil then return nil end return setmetatable({filename = filename, data = d}, XMLFile) end
function XMLFile:save() XMLFile.files[self.filename] = self.data end
function XMLFile:delete() end
for _, n in ipairs({"Int", "Float", "String", "Bool"}) do
    XMLFile["set" .. n] = function(self, k, v) self.data[k] = v end
    XMLFile["get" .. n] = function(self, k, d) local v = self.data[k] if v == nil then return d end return v end
end
function XMLFile:iterate(base, fn)
    local i = 0
    while true do
        local key = string.format("%s(%d)", base, i)
        local found = false
        for k in pairs(self.data) do if k:sub(1, #key) == key then found = true break end end
        if not found then return end
        fn(i + 1, key)
        i = i + 1
    end
end
