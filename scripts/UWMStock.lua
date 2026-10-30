-- Utilities & Waste Management: a farm's stock of the traded goods, taking it out and putting electricity in.
-- Author: PropaineX
--
-- Stock = every storage on a placeable the farm owns: animal pens (slurry pits) and manure heaps first, then
-- silos / silo extensions, then production points. Electricity only comes out of production points that make it
-- and only goes into the buyer's chosen production points that use it.

UWMStock = {}

UWMStock.KIND_ANIMALS = 1
UWMStock.KIND_SILO = 2
UWMStock.KIND_PRODUCTION = 3

-- true while this mod moves goods itself, so the reservation guard lets it through
UWMStock.isMovingGoods = false

-- ProductionChainManager handles automatic output sales/distribution outside LoadingStation.
-- Give that synchronous update a storage view containing only unreserved output. Writes translate
-- back to the real storage, so both the quantity sold and the money earned exclude held goods.
-- The real storage is never emptied temporarily; loading stations and save/network state keep it.
function UWMStock.updateProductionSales(chain, superFunc, ...)
    local manager = UtilitiesWasteManagement.manager
    if not chain.isServer or manager == nil then
        return superFunc(chain, ...)
    end
    local heldByStorage = {}
    for _, good in ipairs(UtilitiesWasteManagement.goods) do
        local ft = good.fillTypeIndex
        local farms = {}
        for _, point in pairs(chain.productionPoints or {}) do
            farms[point:getOwnerFarmId()] = true
        end
        for farmId in pairs(farms) do
            local left = manager:getReservedLiters(farmId, ft)
            if left > 0 then
                for _, entry in ipairs(UWMStock.getSourceStorages(farmId, ft)) do
                    local held = math.min(left, entry.storage:getFillLevel(ft) or 0)
                    if held > 0 then
                        heldByStorage[entry.storage] = heldByStorage[entry.storage] or {}
                        heldByStorage[entry.storage][ft] = held
                        left = left - held
                    end
                    if left <= 0 then break end
                end
            end
        end
    end

    local replaced = {}
    for _, point in pairs(chain.productionPoints or {}) do
        local storage = point.storage
        local held = heldByStorage[storage]
        if held ~= nil then
            local view = {}
            function view:getFillLevel(ft)
                return math.max((storage:getFillLevel(ft) or 0) - (held[ft] or 0), 0)
            end
            function view:getFillLevels()
                local levels = {}
                for ft in pairs(storage.fillLevels) do levels[ft] = self:getFillLevel(ft) end
                return levels
            end
            function view:getCapacity(ft)
                return math.max(storage:getCapacity(ft) - (held[ft] or 0), 0)
            end
            function view:setFillLevel(level, ft, ...)
                return storage:setFillLevel(math.max(level, 0) + (held[ft] or 0), ft, ...)
            end
            setmetatable(view, {__index = function(_, key)
                if key == "fillLevels" then return view:getFillLevels() end
                local value = storage[key]
                if type(value) == "function" then
                    return function(_, ...) return value(storage, ...) end
                end
                return value
            end})
            table.insert(replaced, {point = point, storage = storage})
            point.storage = view
        end
    end
    -- Restore object identity even if another mod or the game throws during the update.
    local function pack(...) return {n = select("#", ...), ...} end
    local result = pack(pcall(superFunc, chain, ...))
    for _, entry in ipairs(replaced) do entry.point.storage = entry.storage end
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, result.n)
end

function UWMStock.installProductionHooks()
    if ProductionChainManager == nil or ProductionChainManager.update == nil then return end
    ProductionChainManager.uwmSalesHandler = UWMStock.updateProductionSales
    if not ProductionChainManager.uwmSalesHooked then
        ProductionChainManager.uwmSalesHooked = true
        ProductionChainManager.update = Utils.overwrittenFunction(ProductionChainManager.update, function(chain, superFunc, ...)
            return ProductionChainManager.uwmSalesHandler(chain, superFunc, ...)
        end)
    end
end

local function getFillLevel(storage, fillTypeIndex)
    local fillLevel = storage:getFillLevel(fillTypeIndex)
    return fillLevel or 0
end

-- does a production point use (inputs) / make (outputs) this fill type?
-- Field names come from mods that read production points (not in the stripped game source); when none of
-- them is there, a production that can store the fill type counts.
local function getProductionUses(productionPoint, fillTypeIndex, listName, setName)
    local set = productionPoint[setName]
    if type(set) == "table" and set[fillTypeIndex] then
        return true
    end

    local found = false
    local productions = productionPoint.productions
    if type(productions) == "table" then
        for _, production in ipairs(productions) do
            local items = production[listName]
            if type(items) == "table" then
                found = true
                for _, item in ipairs(items) do
                    if item.type == fillTypeIndex then
                        return true
                    end
                end
            end
        end
    end

    if not found and type(set) ~= "table" then
        local storage = productionPoint.storage
        return storage ~= nil and storage.fillLevels ~= nil and storage.fillLevels[fillTypeIndex] ~= nil
    end

    return false
end

function UWMStock.getProductionUsesInput(productionPoint, fillTypeIndex)
    return getProductionUses(productionPoint, fillTypeIndex, "inputs", "inputFillTypeIds")
end

function UWMStock.getProductionMakesOutput(productionPoint, fillTypeIndex)
    return getProductionUses(productionPoint, fillTypeIndex, "outputs", "outputFillTypeIds")
end

-- list of {storage, kind, placeable} for every storage of the farm, in draw order
function UWMStock.getStorages(farmId)
    local entries = {}
    local seen = {}

    local function add(storage, kind, placeable)
        if storage ~= nil and not seen[storage] and storage.getFillLevel ~= nil and storage.setFillLevel ~= nil then
            seen[storage] = true
            table.insert(entries, {storage = storage, kind = kind, placeable = placeable})
        end
    end

    local placeableSystem = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if placeableSystem == nil or placeableSystem.placeables == nil then
        return entries
    end

    for _, placeable in ipairs(placeableSystem.placeables) do
        if placeable:getOwnerFarmId() == farmId then
            local spec = placeable.spec_husbandry
            if spec ~= nil then
                add(spec.storage, UWMStock.KIND_ANIMALS, placeable)
            end
            spec = placeable.spec_manureHeap
            if spec ~= nil then
                add(spec.manureHeap, UWMStock.KIND_ANIMALS, placeable)
            end
            spec = placeable.spec_silo
            if spec ~= nil and spec.storages ~= nil then
                for _, storage in ipairs(spec.storages) do
                    add(storage, UWMStock.KIND_SILO, placeable)
                end
            end
            spec = placeable.spec_siloExtension
            if spec ~= nil then
                add(spec.storage, UWMStock.KIND_SILO, placeable)
            end
            spec = placeable.spec_productionPoint
            if spec ~= nil and spec.productionPoint ~= nil then
                add(spec.productionPoint.storage, UWMStock.KIND_PRODUCTION, placeable)
            end
        end
    end

    table.sort(entries, function(a, b)
        return a.kind < b.kind
    end)

    return entries
end

-- storages the seller's goods of this type can be taken from
function UWMStock.getSourceStorages(farmId, fillTypeIndex)
    local sources = {}
    for _, entry in ipairs(UWMStock.getStorages(farmId)) do
        local usable = true
        if fillTypeIndex == FillType.ELECTRICCHARGE then
            usable = entry.kind == UWMStock.KIND_PRODUCTION
                and UWMStock.getProductionMakesOutput(entry.placeable.spec_productionPoint.productionPoint, fillTypeIndex)
        elseif UtilitiesWasteManagement.getIsBulk(fillTypeIndex) then
            -- bulk: only what can be taken out to sell - silos, and what productions made (not their inputs,
            -- not animal pens: user, 2026-10-28 "I don't need to see my goat milk in my dairy")
            usable = UWMStock.getIsSellableSource(entry, fillTypeIndex)
        end
        if usable and getFillLevel(entry.storage, fillTypeIndex) > 0 then
            table.insert(sources, entry)
        end
    end
    return sources
end

function UWMStock.getIsSellableSource(entry, fillTypeIndex)
    if entry.kind == UWMStock.KIND_SILO then
        return true
    elseif entry.kind == UWMStock.KIND_PRODUCTION then
        return UWMStock.getProductionMakesOutput(entry.placeable.spec_productionPoint.productionPoint, fillTypeIndex)
    end
    return false
end

-- the farm's bulk goods it can sell now: {fillTypeIndex, name, liters} with liters = free stock, A - Z
function UWMStock.getBulkGoods(farmId)
    local found = {}
    for _, entry in ipairs(UWMStock.getStorages(farmId)) do
        local levels = entry.storage.fillLevels
        if levels ~= nil then
            for fillTypeIndex in pairs(levels) do
                if not found[fillTypeIndex] and UtilitiesWasteManagement.getIsBulk(fillTypeIndex)
                    and UWMStock.getIsSellableSource(entry, fillTypeIndex) then
                    found[fillTypeIndex] = true
                end
            end
        end
    end
    local goods = {}
    for fillTypeIndex in pairs(found) do
        local liters = UWMStock.getAvailable(farmId, fillTypeIndex, nil)
        if liters >= 1 then
            table.insert(goods, {fillTypeIndex = fillTypeIndex, name = UtilitiesWasteManagement.getGoodName(fillTypeIndex), liters = liters})
        end
    end
    table.sort(goods, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return goods
end

-- every bulk good in the game, A - Z (a standing buy order has no seller to check yet)
function UWMStock.getAllBulkGoods()
    local goods = {}
    for _, fillType in ipairs(g_fillTypeManager:getFillTypes()) do
        if UtilitiesWasteManagement.getIsBulk(fillType.index) then
            table.insert(goods, {fillTypeIndex = fillType.index, name = UtilitiesWasteManagement.getGoodName(fillType.index)})
        end
    end
    table.sort(goods, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return goods
end

function UWMStock.getStock(farmId, fillTypeIndex)
    local total = 0
    for _, entry in ipairs(UWMStock.getSourceStorages(farmId, fillTypeIndex)) do
        total = total + getFillLevel(entry.storage, fillTypeIndex)
    end
    return total
end

-- liters the farm may still hand out: stock minus what is reserved for buyers (an invoice's own reservation
-- doesn't count against itself)
function UWMStock.getAvailable(farmId, fillTypeIndex, exceptInvoice)
    local reserved = 0
    if UtilitiesWasteManagement.manager ~= nil then
        reserved = UtilitiesWasteManagement.manager:getReservedLiters(farmId, fillTypeIndex, exceptInvoice)
    end
    return math.max(UWMStock.getStock(farmId, fillTypeIndex) - reserved, 0)
end

-- takes up to `liters` out of the farm's stock, returns what was taken (server only)
function UWMStock.take(farmId, fillTypeIndex, liters)
    local taken = 0
    UWMStock.isMovingGoods = true
    for _, entry in ipairs(UWMStock.getSourceStorages(farmId, fillTypeIndex)) do
        if taken >= liters then
            break
        end
        local fillLevel = getFillLevel(entry.storage, fillTypeIndex)
        local amount = math.min(fillLevel, liters - taken)
        entry.storage:setFillLevel(fillLevel - amount, fillTypeIndex)
        -- never count more than was asked (a storage over its capacity clamps lower when set)
        taken = taken + math.min(fillLevel - getFillLevel(entry.storage, fillTypeIndex), amount)
    end
    UWMStock.isMovingGoods = false
    return taken
end

-- puts liters back into the farm's storages that hold this fill type; returns what didn't fit
function UWMStock.giveBack(farmId, fillTypeIndex, liters)
    local left = liters
    UWMStock.isMovingGoods = true
    for _, entry in ipairs(UWMStock.getStorages(farmId)) do
        if left <= 0 then
            break
        end
        local storage = entry.storage
        if storage.fillLevels ~= nil and storage.fillLevels[fillTypeIndex] ~= nil then
            local fillLevel = getFillLevel(storage, fillTypeIndex)
            storage:setFillLevel(fillLevel + left, fillTypeIndex)
            left = left - (getFillLevel(storage, fillTypeIndex) - fillLevel)
        end
    end
    UWMStock.isMovingGoods = false
    return math.max(left, 0)
end

-- the buyer's production points that can take electricity: {placeable, storage, name}
function UWMStock.getElectricityTargets(farmId)
    local targets = {}
    for _, entry in ipairs(UWMStock.getStorages(farmId)) do
        if entry.kind == UWMStock.KIND_PRODUCTION then
            local productionPoint = entry.placeable.spec_productionPoint.productionPoint
            if UWMStock.getProductionUsesInput(productionPoint, FillType.ELECTRICCHARGE) then
                table.insert(targets, {placeable = entry.placeable, storage = entry.storage, name = entry.placeable:getName()})
            end
        end
    end
    return targets
end

local function getFreeCapacity(storage, fillTypeIndex)
    if storage.getFreeCapacity ~= nil then
        return math.max(storage:getFreeCapacity(fillTypeIndex) or 0, 0)
    end
    return math.max(storage:getCapacity(fillTypeIndex) - getFillLevel(storage, fillTypeIndex), 0)
end

-- the invoice's chosen targets that still exist and belong to the buyer, in the order the buyer picked
function UWMStock.resolveTargets(invoice)
    local resolved = {}
    local placeableSystem = g_currentMission.placeableSystem
    for _, uniqueId in ipairs(invoice.targets) do
        local placeable = placeableSystem:getPlaceableByUniqueId(uniqueId)
        if placeable ~= nil and placeable:getOwnerFarmId() == invoice.buyerFarmId and placeable.spec_productionPoint ~= nil
            and placeable.spec_productionPoint.productionPoint ~= nil then
            table.insert(resolved, placeable.spec_productionPoint.productionPoint.storage)
        end
    end
    return resolved
end

function UWMStock.getElectricitySpace(invoice)
    local space = 0
    for _, storage in ipairs(UWMStock.resolveTargets(invoice)) do
        space = space + getFreeCapacity(storage, FillType.ELECTRICCHARGE)
    end
    return space
end

-- fills the targets in order with up to `liters`, returns what went in (server only)
function UWMStock.putElectricity(invoice, liters)
    local added = 0
    UWMStock.isMovingGoods = true
    for _, storage in ipairs(UWMStock.resolveTargets(invoice)) do
        if added >= liters then
            break
        end
        local fillLevel = getFillLevel(storage, FillType.ELECTRICCHARGE)
        local amount = math.min(getFreeCapacity(storage, FillType.ELECTRICCHARGE), liters - added)
        if amount > 0 then
            storage:setFillLevel(fillLevel + amount, FillType.ELECTRICCHARGE)
            added = added + (getFillLevel(storage, FillType.ELECTRICCHARGE) - fillLevel)
        end
    end
    UWMStock.isMovingGoods = false
    return added
end

-- Reservation guard: the seller's OWN vehicles can't load reserved liters out of the seller's stations (silos,
-- slurry pits, manure heaps). The game fills the vehicle through LoadingStation:addFillLevelToFillableObject
-- (called from LoadTrigger:update); the amount is cut down to what isn't reserved. Buyers collecting there go
-- through UWMPickup instead, which installs the hook and calls this for everyone else.
function UWMStock.addFillLevelToFillableObject(station, superFunc, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta, ...)
    local manager = UtilitiesWasteManagement.manager
    if manager ~= nil and station.isServer and not UWMStock.isMovingGoods and fillDelta ~= nil and fillDelta > 0
        and station.owningPlaceable ~= nil then
        local farmId = station.owningPlaceable:getOwnerFarmId()
        if UWMPickup.getFarmIdForObject(fillableObject) == farmId and manager:getReservedLiters(farmId, fillTypeIndex, nil) > 0 then
            local available = UWMStock.getAvailable(farmId, fillTypeIndex, nil)
            if available <= 0.001 then
                return 0
            end
            fillDelta = math.min(fillDelta, available)
        end
    end
    return superFunc(station, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta, ...)
end
