-- Utilities & Waste Management: buyers collect paid manure / slurry at the community depot (UWMDepot). The depot's
-- fill points are a game LoadingStation with no storages of its own (flag uwmIsDepot); for those this mod answers
-- the three questions the load trigger asks:
--   getIsFillAllowedToFarm  -> yes, while the farm has paid liters left to collect
--   getAllFillLevels        -> only the goods paid for, with the liters left to collect (the R list)
--   addFillLevelToFillableObject (server) -> take them from the sellers' stock, oldest invoice first
-- Every other loading station stays the game's own, plus the reservation guard (UWMStock) for the seller's own
-- vehicles. (0.2/0.3 let buyers load at the seller's pits, heaps and silos; since 0.4 the depot is the only
-- pickup - user's rule.)
-- Author: PropaineX

UWMPickup = {}

-- the farm a vehicle loads for (same rule as LoadTrigger:farmIdForFillableObject)
function UWMPickup.getFarmIdForObject(object)
    if object == nil then
        return nil
    end
    if object.getActiveFarm ~= nil then
        local farmId = object:getActiveFarm()
        if farmId ~= nil then
            return farmId
        end
    end
    if object.getOwnerFarmId ~= nil then
        return object:getOwnerFarmId()
    end
    return nil
end

-- fill type -> liters the farm may collect at this depot station (paid for and in the sellers' stock, any seller)
function UWMPickup.getCollectable(station, buyerFarmId)
    local manager = UtilitiesWasteManagement.manager
    if manager == nil or not station.uwmIsDepot or buyerFarmId == nil then
        return nil
    end
    local supported = station.getSupportedFillTypes ~= nil and station:getSupportedFillTypes() or nil

    local collectable = nil
    for _, good in ipairs(UtilitiesWasteManagement.goods) do
        local fillTypeIndex = good.fillTypeIndex
        if fillTypeIndex ~= FillType.ELECTRICCHARGE and (supported == nil or supported[fillTypeIndex]) then
            local liters = manager:getCollectableLiters(buyerFarmId, fillTypeIndex)
            if liters > 0.5 then
                collectable = collectable or {}
                collectable[fillTypeIndex] = liters
            end
        end
    end
    return collectable
end

function UWMPickup.getIsFillAllowedToFarm(station, superFunc, farmId, ...)
    if station.uwmIsDepot then
        return UWMPickup.getCollectable(station, farmId) ~= nil
    end
    return superFunc(station, farmId, ...)
end

function UWMPickup.getAllFillLevels(station, superFunc, farmId, ...)
    local fillLevels, capacity = superFunc(station, farmId, ...)
    if station.uwmIsDepot then
        -- the depot holds nothing itself: a farm sees what it paid for
        return UWMPickup.getCollectable(station, farmId) or {}, capacity
    end
    return fillLevels, capacity
end

-- server: a vehicle loading at the depot draws its farm's paid liters from the sellers' stock
function UWMPickup.addFillLevelToFillableObject(station, superFunc, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta, fillInfo, toolType, ...)
    if not station.uwmIsDepot then
        -- everyone at an ordinary station, incl. the seller's own vehicles (reservation guard)
        return UWMStock.addFillLevelToFillableObject(station, superFunc, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta,
            fillInfo, toolType, ...)
    end

    local manager = UtilitiesWasteManagement.manager
    local buyerFarmId = UWMPickup.getFarmIdForObject(fillableObject)
    if manager == nil or not station.isServer or fillDelta == nil or fillDelta <= 0 or buyerFarmId == nil
        or manager:getCollectableLiters(buyerFarmId, fillTypeIndex) <= 0 then
        return 0
    end

    local free = fillableObject:getFillUnitFreeCapacity(fillUnitIndex, fillTypeIndex, buyerFarmId) or fillDelta
    local want = math.min(fillDelta, free)
    if want <= 0 then
        return 0
    end
    local taken = manager:collect(buyerFarmId, fillTypeIndex, want)
    if taken <= 0 then
        return 0
    end
    local added = fillableObject:addFillUnitFillLevel(buyerFarmId, fillUnitIndex, taken, fillTypeIndex,
        toolType or ToolType.TRIGGER, fillInfo) or 0
    if added < taken - 0.001 then
        manager:returnCollected(buyerFarmId, fillTypeIndex, taken - added)
    end
    return added
end

-- Installed once per game run on LoadingStation, dispatching through LoadingStation.uwmPickupHandler (set and
-- cleared per mission) so a hook left from an earlier savegame never runs stale code.
function UWMPickup.installHooks()
    if LoadingStation == nil then
        print(UtilitiesWasteManagement.TAG .. " LoadingStation not found, nothing can be collected at the depot")
        return
    end
    LoadingStation.uwmPickupHandler = UWMPickup
    if LoadingStation.uwmPickupHooked then
        return
    end
    LoadingStation.uwmPickupHooked = true

    for _, name in ipairs({"getIsFillAllowedToFarm", "getAllFillLevels", "addFillLevelToFillableObject"}) do
        if LoadingStation[name] ~= nil then
            LoadingStation[name] = Utils.overwrittenFunction(LoadingStation[name], function(station, superFunc, ...)
                local handler = LoadingStation.uwmPickupHandler
                if handler ~= nil then
                    return handler[name](station, superFunc, ...)
                end
                return superFunc(station, ...)
            end)
        else
            print(string.format("%s LoadingStation.%s not found, collecting at the depot may not work", UtilitiesWasteManagement.TAG, name))
        end
    end
    print(UtilitiesWasteManagement.TAG .. " paid manure and slurry can be collected at the depot")
end

function UWMPickup.removeHooks()
    if LoadingStation ~= nil then
        LoadingStation.uwmPickupHandler = nil
    end
end
