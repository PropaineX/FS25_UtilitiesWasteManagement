-- Utilities & Waste Management: buyers collect paid manure / slurry at the SELLER's own loading points (slurry
-- pits, manure heaps, silos). The game only lets a station's own farm load there; for a farm with paid,
-- uncollected liters from that station's owner this mod answers the three questions the load trigger asks:
--   getIsFillAllowedToFarm  -> yes, while something is left to collect
--   getAllFillLevels        -> only the goods paid for, with the liters left to collect (the R list)
--   addFillLevelToFillableObject (server) -> take it from the seller's stock and count it against the invoice
-- Everything else stays the game's own code. (The pickup building, later, uses the same collect code.)
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

function UWMPickup.getStationOwner(station)
    if station.owningPlaceable ~= nil then
        return station.owningPlaceable:getOwnerFarmId()
    end
    return nil
end

-- fill type -> liters the buyer may collect here (paid for, from this station's owner, and in the seller's stock)
function UWMPickup.getCollectable(station, buyerFarmId)
    local manager = UtilitiesWasteManagement.manager
    local sellerFarmId = UWMPickup.getStationOwner(station)
    if manager == nil or sellerFarmId == nil or buyerFarmId == nil or buyerFarmId == sellerFarmId then
        return nil
    end
    local supported = station.getSupportedFillTypes ~= nil and station:getSupportedFillTypes() or nil

    local collectable = nil
    for _, good in ipairs(UtilitiesWasteManagement.goods) do
        local fillTypeIndex = good.fillTypeIndex
        if fillTypeIndex ~= FillType.ELECTRICCHARGE and (supported == nil or supported[fillTypeIndex]) then
            local liters = manager:getCollectableLiters(buyerFarmId, fillTypeIndex, sellerFarmId)
            if liters > 0.5 then
                collectable = collectable or {}
                collectable[fillTypeIndex] = liters
            end
        end
    end
    return collectable
end

function UWMPickup.getIsFillAllowedToFarm(station, superFunc, farmId, ...)
    if superFunc(station, farmId, ...) then
        return true
    end
    return UWMPickup.getCollectable(station, farmId) ~= nil
end

function UWMPickup.getAllFillLevels(station, superFunc, farmId, ...)
    local fillLevels, capacity = superFunc(station, farmId, ...)
    local collectable = UWMPickup.getCollectable(station, farmId)
    if collectable == nil then
        return fillLevels, capacity
    end
    -- a buyer at someone else's station sees only what he paid for
    return collectable, capacity
end

-- server: a buyer's vehicle loading at the seller's station
function UWMPickup.addFillLevelToFillableObject(station, superFunc, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta, fillInfo, toolType, ...)
    local manager = UtilitiesWasteManagement.manager
    local buyerFarmId = UWMPickup.getFarmIdForObject(fillableObject)
    local sellerFarmId = UWMPickup.getStationOwner(station)

    if manager ~= nil and station.isServer and fillDelta ~= nil and fillDelta > 0 and buyerFarmId ~= nil
        and sellerFarmId ~= nil and buyerFarmId ~= sellerFarmId
        and manager:getCollectableLiters(buyerFarmId, fillTypeIndex, sellerFarmId) > 0 then

        local free = fillableObject:getFillUnitFreeCapacity(fillUnitIndex, fillTypeIndex, buyerFarmId) or fillDelta
        local want = math.min(fillDelta, free)
        if want <= 0 then
            return 0
        end
        local taken = manager:collect(buyerFarmId, fillTypeIndex, want, sellerFarmId)
        if taken <= 0 then
            return 0
        end
        local added = fillableObject:addFillUnitFillLevel(buyerFarmId, fillUnitIndex, taken, fillTypeIndex,
            toolType or ToolType.TRIGGER, fillInfo) or 0
        if added < taken - 0.001 then
            manager:returnCollected(buyerFarmId, fillTypeIndex, taken - added, sellerFarmId)
        end
        return added
    end

    -- everyone else, incl. the seller's own vehicles (reservation guard)
    return UWMStock.addFillLevelToFillableObject(station, superFunc, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta,
        fillInfo, toolType, ...)
end

-- Installed once per game run on LoadingStation, dispatching through LoadingStation.uwmPickupHandler (set and
-- cleared per mission) so a hook left from an earlier savegame never runs stale code.
function UWMPickup.installHooks()
    if LoadingStation == nil then
        print(UtilitiesWasteManagement.TAG .. " LoadingStation not found, buyers can't collect at the seller's stations")
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
            print(string.format("%s LoadingStation.%s not found, collecting at the seller's stations may not work", UtilitiesWasteManagement.TAG, name))
        end
    end
    print(UtilitiesWasteManagement.TAG .. " buyers can collect at the seller's loading stations")
end

function UWMPickup.removeHooks()
    if LoadingStation ~= nil then
        LoadingStation.uwmPickupHandler = nil
    end
end
