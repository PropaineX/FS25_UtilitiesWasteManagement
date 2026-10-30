-- Utilities & Waste Management: pallet goods (user, 2026-10-28). Sold by the liter like everything else.
-- Selling takes the liters off the seller's own pallets on the map (empty pallets are removed); the buyer gets new
-- pallets on the depot's pallet pad, filled up to the chosen pallet size (1,000 or 5,000 l, never more than the
-- game's pallet for that good holds). Unsold pallet goods going home also come out on the pad, for the seller.
-- Pallets inside a logistics building (object storage) are not read yet: their stored-object class isn't in the
-- game files we have, so probeObjectStorages() writes one to the log on the first in-game test.
-- Author: PropaineX

UWMPallets = {}

UWMPallets.SIZES = {1000, 5000}
UWMPallets.RETRY_MS = 30000     -- pad full / pallet limit: try again after this
UWMPallets.queue = {}           -- {farmId, fillTypeIndex, liters, size, onDelivered(liters), tag, waitUntil}
UWMPallets.busy = false

-- goods the game sells on pallets (a pallet file), apart from our own three goods
function UWMPallets.getIsPalletGood(fillTypeIndex)
    if fillTypeIndex == nil or fillTypeIndex == FillType.UNKNOWN or UtilitiesWasteManagement.getGood(fillTypeIndex) ~= nil then
        return false
    end
    local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    return fillType ~= nil and fillType.palletFilename ~= nil
end

local function getVehicles()
    local mission = g_currentMission
    if mission == nil then
        return {}
    end
    if mission.vehicleSystem ~= nil and mission.vehicleSystem.vehicles ~= nil then
        return mission.vehicleSystem.vehicles
    end
    return mission.vehicles or {}
end

-- the farm's pallets of this good standing on the map (not in a building): {vehicle, fillUnitIndex, liters}
function UWMPallets.getPallets(farmId, fillTypeIndex)
    local pallets = {}
    for _, vehicle in pairs(getVehicles()) do
        if vehicle.isPallet and not vehicle.isDeleted and vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() == farmId then
            local fillUnitIndex = vehicle.spec_pallet ~= nil and vehicle.spec_pallet.fillUnitIndex or 1
            if vehicle:getFillUnitFillType(fillUnitIndex) == fillTypeIndex then
                local liters = vehicle:getFillUnitFillLevel(fillUnitIndex) or 0
                if liters > 0 then
                    table.insert(pallets, {vehicle = vehicle, fillUnitIndex = fillUnitIndex, liters = liters})
                end
            end
        end
    end
    -- the fullest last, so part pallets are used up first
    table.sort(pallets, function(a, b)
        return a.liters < b.liters
    end)
    return pallets
end

function UWMPallets.getStock(farmId, fillTypeIndex)
    local total = 0
    for _, pallet in ipairs(UWMPallets.getPallets(farmId, fillTypeIndex)) do
        total = total + pallet.liters
    end
    return total
end

-- the farm's pallet goods it can sell now: {fillTypeIndex, name, liters, count}, A - Z
function UWMPallets.getGoods(farmId)
    local byType = {}
    for _, vehicle in pairs(getVehicles()) do
        if vehicle.isPallet and not vehicle.isDeleted and vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() == farmId then
            local fillUnitIndex = vehicle.spec_pallet ~= nil and vehicle.spec_pallet.fillUnitIndex or 1
            local fillTypeIndex = vehicle:getFillUnitFillType(fillUnitIndex)
            local liters = vehicle:getFillUnitFillLevel(fillUnitIndex) or 0
            if liters > 0 and UWMPallets.getIsPalletGood(fillTypeIndex) then
                local entry = byType[fillTypeIndex]
                if entry == nil then
                    entry = {fillTypeIndex = fillTypeIndex, name = UtilitiesWasteManagement.getGoodName(fillTypeIndex), liters = 0, count = 0}
                    byType[fillTypeIndex] = entry
                end
                entry.liters = entry.liters + liters
                entry.count = entry.count + 1
            end
        end
    end
    local goods = {}
    for _, entry in pairs(byType) do
        table.insert(goods, entry)
    end
    table.sort(goods, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return goods
end

-- every pallet good in the game, A - Z (a standing buy order has no seller to check yet)
function UWMPallets.getAllGoods()
    local goods = {}
    for _, fillType in ipairs(g_fillTypeManager:getFillTypes()) do
        if UWMPallets.getIsPalletGood(fillType.index) then
            table.insert(goods, {fillTypeIndex = fillType.index, name = UtilitiesWasteManagement.getGoodName(fillType.index)})
        end
    end
    table.sort(goods, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return goods
end

-- takes the liters off the farm's pallets (server); empty pallets are removed. Returns the liters taken.
function UWMPallets.take(farmId, fillTypeIndex, liters)
    local taken = 0
    for _, pallet in ipairs(UWMPallets.getPallets(farmId, fillTypeIndex)) do
        if taken >= liters - 0.001 then
            break
        end
        local want = math.min(pallet.liters, liters - taken)
        local vehicle = pallet.vehicle
        local delta = vehicle:addFillUnitFillLevel(farmId, pallet.fillUnitIndex, -want, fillTypeIndex, ToolType.UNDEFINED)
        taken = taken + math.min(math.abs(delta or 0), want)
        if (vehicle:getFillUnitFillLevel(pallet.fillUnitIndex) or 0) < 0.5 and not vehicle.isDeleted then
            vehicle:delete()
        end
    end
    return taken
end

-- the most one new pallet of this good can hold at this pallet size
function UWMPallets.getPalletLiters(fillTypeIndex, size)
    -- the spawner read each pallet file's capacity (server; clients show the chosen size)
    local spawner = UWMDepot ~= nil and UWMDepot.getPalletSpawner ~= nil and UWMDepot.getPalletSpawner() or nil
    local pallet = spawner ~= nil and spawner.fillTypeIdToPallet ~= nil and spawner.fillTypeIdToPallet[fillTypeIndex] or nil
    local capacity = pallet ~= nil and pallet.capacity or nil
    if capacity ~= nil and capacity > 0 then
        return math.min(size or UWMPallets.SIZES[1], capacity)
    end
    return size or UWMPallets.SIZES[1]
end

-- hands `liters` out as new pallets on the depot's pad for farmId (server). onDelivered(liters) is called for every
-- pallet filled. tag lets a finished invoice drop what is still waiting.
function UWMPallets.deliver(farmId, fillTypeIndex, liters, size, onDelivered, tag)
    if liters < 0.5 then
        return
    end
    table.insert(UWMPallets.queue, {farmId = farmId, fillTypeIndex = fillTypeIndex, liters = liters, size = size or UWMPallets.SIZES[1],
        onDelivered = onDelivered, tag = tag, waitUntil = 0})
end

function UWMPallets.cancel(tag)
    for i = #UWMPallets.queue, 1, -1 do
        if UWMPallets.queue[i].tag == tag then
            table.remove(UWMPallets.queue, i)
        end
    end
end

-- liters still waiting to come out for this tag
function UWMPallets.getQueued(tag)
    local liters = 0
    for _, entry in ipairs(UWMPallets.queue) do
        if entry.tag == tag then
            liters = liters + entry.liters
        end
    end
    return liters
end

function UWMPallets.reset()
    UWMPallets.queue = {}
    UWMPallets.busy = false
end

-- server: one pallet at a time
function UWMPallets.update(dt)
    if UWMPallets.busy or #UWMPallets.queue == 0 then
        return
    end
    local now = g_time or 0
    local entry = nil
    for _, candidate in ipairs(UWMPallets.queue) do
        if candidate.waitUntil <= now then
            entry = candidate
            break
        end
    end
    if entry == nil then
        return
    end
    local spawner = UWMDepot ~= nil and UWMDepot.getPalletSpawner() or nil
    if spawner == nil then
        entry.waitUntil = now + UWMPallets.RETRY_MS
        return
    end
    UWMPallets.busy = true
    spawner:spawnPallet(entry.farmId, entry.fillTypeIndex, function(_, pallet, result)
        UWMPallets.onPalletSpawned(entry, pallet, result)
    end, nil)
end

function UWMPallets.onPalletSpawned(entry, pallet, result)
    UWMPallets.busy = false
    if pallet == nil then
        -- pad full, pallet limit or no pallet for this good: wait and try again (no pallet file: drop it)
        if result == PalletSpawner.NO_PALLET_FOR_FILLTYPE then
            Logging.warning("%s no pallet for fill type %s, %.0f l not handed out", UtilitiesWasteManagement.TAG,
                tostring(g_fillTypeManager:getFillTypeNameByIndex(entry.fillTypeIndex)), entry.liters)
            UWMPallets.cancelEntry(entry)
        else
            entry.waitUntil = (g_time or 0) + UWMPallets.RETRY_MS
        end
        return
    end
    if result == PalletSpawner.RESULT_SUCCESS and pallet.emptyAllFillUnits ~= nil then
        pallet:emptyAllFillUnits(true)
    end
    local fillUnitIndex = pallet.spec_pallet ~= nil and pallet.spec_pallet.fillUnitIndex or 1
    local want = math.min(entry.liters, entry.size)
    local delta = pallet:addFillUnitFillLevel(entry.farmId, fillUnitIndex, want, entry.fillTypeIndex, ToolType.UNDEFINED) or 0
    if delta <= 0 then
        Logging.warning("%s the pallet took no %s, %.0f l not handed out", UtilitiesWasteManagement.TAG,
            tostring(g_fillTypeManager:getFillTypeNameByIndex(entry.fillTypeIndex)), entry.liters)
        pallet:delete()
        UWMPallets.cancelEntry(entry)
        return
    end
    entry.liters = entry.liters - delta
    if entry.onDelivered ~= nil then
        entry.onDelivered(delta)
    end
    if entry.liters < 0.5 then
        UWMPallets.cancelEntry(entry)
    end
end

function UWMPallets.cancelEntry(entry)
    for i, candidate in ipairs(UWMPallets.queue) do
        if candidate == entry then
            table.remove(UWMPallets.queue, i)
            return
        end
    end
end

-- first in-game test: what a pallet stored in a logistics building looks like (fields only, written to the log once)
function UWMPallets.probeObjectStorages(farmId)
    if UWMPallets.probed then
        return
    end
    UWMPallets.probed = true
    local placeableSystem = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if placeableSystem == nil then
        return
    end
    for _, placeable in ipairs(placeableSystem.placeables or {}) do
        local spec = placeable.spec_objectStorage
        if spec ~= nil and spec.storedObjects ~= nil and #spec.storedObjects > 0 then
            local object = spec.storedObjects[1]
            print(string.format("%s PROBE object storage '%s' farm %s: %d stored objects", UtilitiesWasteManagement.TAG,
                tostring(placeable:getName()), tostring(placeable:getOwnerFarmId()), #spec.storedObjects))
            for key, value in pairs(object) do
                print(string.format("%s PROBE   %s = %s (%s)", UtilitiesWasteManagement.TAG, tostring(key), tostring(value), type(value)))
                if type(value) == "table" then
                    for subKey, subValue in pairs(value) do
                        print(string.format("%s PROBE     %s.%s = %s", UtilitiesWasteManagement.TAG, tostring(key), tostring(subKey), tostring(subValue)))
                    end
                end
            end
            local mt = getmetatable(object)
            if mt ~= nil and type(mt.__index) == "table" then
                for name in pairs(mt.__index) do
                    print(string.format("%s PROBE   method %s", UtilitiesWasteManagement.TAG, tostring(name)))
                end
            end
            return
        end
    end
end
