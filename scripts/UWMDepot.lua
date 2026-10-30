-- Utilities & Waste Management: the community depot (placeable specialization "uwmDepot").
-- One building: tank, manure pit, office, pallet pad (pallets spawn there) and the base-game Farma 400 (bulk pickup).
-- The Farma model has no silo/storage specialization or active pickup; manure loads only at the pit.
-- Slurry is collected at the tank's coupling, manure at the open end of the manure pit, and the office door opens
-- the Utilities page. The two pickups are a game LoadingStation without storages of its own (flag uwmIsDepot):
-- UWMPickup tells the load trigger what a farm may load and takes the liters live from the sellers' stock.
-- Invoices only work while a depot stands on the map (UWMManager). Only one depot per map unless the server admin
-- allows more (setting on the Utilities page).
-- Author: PropaineX

UWMDepot = {}

UWMDepot.MOD_NAME = g_currentModName
UWMDepot.SPEC = "spec_" .. tostring(g_currentModName) .. ".uwmDepot"

-- every depot that is really placed (not the shop preview), on server and clients
UWMDepot.placed = UWMDepot.placed or {}

-- the Farma 400's loading-pipe effect meshes: hidden unless loading (GE and the game show them as a grey tube)
UWMDepot.FARMA_EFFECT_NODES = {"pipeEffect", "pipeEffectSmoke"}
UWMDepot.FARMA_FILENAME = "$data/placeables/unia/farma/farma400/farma400.i3d"
-- its silo trigger, grain pit tip target, info trigger and AI spline (no silo script runs on them here)
UWMDepot.FARMA_UNUSED_NODES = {"loadingTrigger", "exactFillRootNode", "infoTrigger", "aiSpline"}

function UWMDepot.prerequisitesPresent(specializations)
    return true
end

function UWMDepot.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(placeableType, "uwmOfficeTriggerCallback", UWMDepot.uwmOfficeTriggerCallback)
end

function UWMDepot.registerOverwrittenFunctions(placeableType)
    SpecializationUtil.registerOverwrittenFunction(placeableType, "collectPickObjects", UWMDepot.collectPickObjects)
    SpecializationUtil.registerOverwrittenFunction(placeableType, "canBuy", UWMDepot.canBuy)
    SpecializationUtil.registerOverwrittenFunction(placeableType, "getCanBePlacedAt", UWMDepot.getCanBePlacedAt)
end

function UWMDepot.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad", UWMDepot)
    SpecializationUtil.registerEventListener(placeableType, "onDelete", UWMDepot)
    SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", UWMDepot)
    SpecializationUtil.registerEventListener(placeableType, "onReadStream", UWMDepot)
    SpecializationUtil.registerEventListener(placeableType, "onWriteStream", UWMDepot)
end

function UWMDepot.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("UWMDepot")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".uwmDepot#officeTrigger", "Player trigger at the office door (opens the Utilities page)")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".uwmDepot#farmaNode", "The referenced Farma 400 (its pipe effect meshes are kept hidden)")
    LoadingStation.registerXMLPaths(schema, basePath .. ".uwmDepot.loadingStation")
    PalletSpawner.registerXMLPaths(schema, basePath .. ".uwmDepot.palletSpawner")
    schema:setXMLSpecializationType()
end

-- the game stores a mod specialization as "spec_<modName>.<name>"; found by its ending if the mod name differs
local function getSpec(placeable)
    local spec = placeable[UWMDepot.SPEC]
    if spec == nil then
        for key, value in pairs(placeable) do
            if type(key) == "string" and key:sub(1, 5) == "spec_" and key:sub(-9) == ".uwmDepot" then
                UWMDepot.SPEC = key
                return value
            end
        end
    end
    return spec
end

-- depots standing on the map, in placing order of this session
function UWMDepot.getDepots()
    local depots = {}
    for placeable in pairs(UWMDepot.placed) do
        if not placeable.isDeleted and not placeable.markedForDeletion then
            table.insert(depots, placeable)
        end
    end
    table.sort(depots, function(a, b)
        return (a.uwmDepotIndex or 0) < (b.uwmDepotIndex or 0)
    end)
    return depots
end

local function findChild(node, name)
    if getName(node) == name then
        return node
    end
    for i = 0, getNumOfChildren(node) - 1 do
        local found = findChild(getChildAt(node, i), name)
        if found ~= nil then
            return found
        end
    end
    return nil
end

function UWMDepot:onLoad(savegame)
    local spec = getSpec(self)
    local xmlFile = self.xmlFile

    -- The Farma 400 comes from the game's own files, loaded into our empty link node before the loading station
    -- reads its pipe-effect nodes (depot.xml maps them through it). Loaded without physics: the placeable adds its
    -- whole tree to physics when it is placed. (A ReferenceNode in the i3d shows in GIANTS Editor but the game
    -- loaded it empty - first in-game test.)
    spec.farmaNode = xmlFile:getValue("placeable.uwmDepot#farmaNode", nil, self.components, self.i3dMappings)
    if spec.farmaNode ~= nil then
        local filename = Utils.getFilename(UWMDepot.FARMA_FILENAME, self.baseDirectory)
        local i3dNode, sharedLoadRequestId = g_i3DManager:loadSharedI3DFile(filename, false, false)
        if i3dNode ~= nil and i3dNode ~= 0 then
            spec.farmaSharedLoadRequestId = sharedLoadRequestId
            link(spec.farmaNode, getChildAt(i3dNode, 0))
            delete(i3dNode)
            -- The old silo loading effect is unused; manure now loads at the pit entrance.
            for _, name in ipairs(UWMDepot.FARMA_EFFECT_NODES) do
                local node = findChild(spec.farmaNode, name)
                if node ~= nil then
                    setVisibility(node, false)
                end
            end
        else
            Logging.xmlError(xmlFile, "%s could not load the Farma 400 (%s)", UtilitiesWasteManagement.TAG, filename)
        end
    end

    spec.loadingStation = LoadingStation.new(self.isServer, self.isClient)
    spec.loadingStation:load(self.components, xmlFile, "placeable.uwmDepot.loadingStation", self.customEnvironment, self.i3dMappings, self.components[1].node)

    -- the Farma's own trigger and tip-target shapes have no script here: out (after the station read its nodes,
    -- since removing them shifts child indices)
    if spec.farmaNode ~= nil then
        for _, name in ipairs(UWMDepot.FARMA_UNUSED_NODES) do
            local node = findChild(spec.farmaNode, name)
            if node ~= nil then
                delete(node)
            end
        end
    end
    spec.loadingStation.owningPlaceable = self
    spec.loadingStation.uwmIsDepot = true
    -- the fill dialog's title: the depot's own (renamable) name
    spec.loadingStation.getName = function()
        return self:getName()
    end

    spec.officeTrigger = xmlFile:getValue("placeable.uwmDepot#officeTrigger", nil, self.components, self.i3dMappings)
    spec.activatable = UWMDepotActivatable.new(self)

    -- the pallet pad (server spawns): paid pallet goods appear here for the buyer
    if self.isServer and PalletSpawner ~= nil then
        spec.palletSpawner = PalletSpawner.new(self.baseDirectory)
        if not spec.palletSpawner:load(self.components, xmlFile, "placeable.uwmDepot.palletSpawner", self.customEnvironment, self.i3dMappings) then
            Logging.xmlWarning(xmlFile, "%s pallet pad could not be loaded, pallet goods can't be handed out", UtilitiesWasteManagement.TAG)
            spec.palletSpawner = nil
        end
    end
end

-- the pallet spawner of the first depot on the map (server), nil without one
function UWMDepot.getPalletSpawner()
    for _, depot in ipairs(UWMDepot.getDepots()) do
        local spec = getSpec(depot)
        if spec ~= nil and spec.palletSpawner ~= nil then
            return spec.palletSpawner
        end
    end
    return nil
end

function UWMDepot:onFinalizePlacement()
    local spec = getSpec(self)

    spec.loadingStation:register(true)

    if spec.officeTrigger ~= nil then
        addTrigger(spec.officeTrigger, "uwmOfficeTriggerCallback", self)
    end

    UWMDepot.nextIndex = (UWMDepot.nextIndex or 0) + 1
    self.uwmDepotIndex = UWMDepot.nextIndex
    UWMDepot.placed[self] = true
    UWMDepot.raiseDepotsChanged()
end

function UWMDepot:onDelete()
    local spec = getSpec(self)

    UWMDepot.placed[self] = nil

    if spec ~= nil then
        if spec.officeTrigger ~= nil then
            removeTrigger(spec.officeTrigger)
            spec.officeTrigger = nil
        end
        if spec.activatable ~= nil then
            g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
        end
        if spec.loadingStation ~= nil then
            spec.loadingStation:delete()
            spec.loadingStation = nil
        end
        if spec.farmaSharedLoadRequestId ~= nil then
            g_i3DManager:releaseSharedI3DFile(spec.farmaSharedLoadRequestId)
            spec.farmaSharedLoadRequestId = nil
        end
    end

    UWMDepot.raiseDepotsChanged()
end

function UWMDepot.raiseDepotsChanged()
    local UWM = UtilitiesWasteManagement
    if UWM ~= nil and UWM.manager ~= nil then
        UWM.manager:onDepotsChanged()
    end
end

function UWMDepot:onReadStream(streamId, connection)
    local spec = getSpec(self)
    local loadingStationId = NetworkUtil.readNodeObjectId(streamId)
    spec.loadingStation:readStream(streamId, connection)
    g_client:finishRegisterObject(spec.loadingStation, loadingStationId)
end

function UWMDepot:onWriteStream(streamId, connection)
    local spec = getSpec(self)
    NetworkUtil.writeNodeObjectId(streamId, NetworkUtil.getObjectId(spec.loadingStation))
    spec.loadingStation:writeStream(streamId, connection)
    g_server:registerObjectInStream(connection, spec.loadingStation)
end

-- the load triggers register their own nodes; keep them out of the placeable's pick objects (as PlaceableSilo does)
function UWMDepot:collectPickObjects(superFunc, node)
    local spec = getSpec(self)
    if spec ~= nil and spec.loadingStation ~= nil and spec.loadingStation.loadTriggers ~= nil then
        for _, loadTrigger in ipairs(spec.loadingStation.loadTriggers) do
            if node == loadTrigger.triggerNode then
                return
            end
        end
    end
    superFunc(self, node)
end

-- only one depot on the map, unless the server admin allows more
function UWMDepot.getPlacingBlocked(placeable)
    local manager = UtilitiesWasteManagement.manager
    if manager ~= nil and manager.allowMultipleDepots then
        return false
    end
    for _, depot in ipairs(UWMDepot.getDepots()) do
        if depot ~= placeable then
            return true
        end
    end
    return false
end

function UWMDepot:canBuy(superFunc)
    local canBuy, warning = superFunc(self)
    if not canBuy then
        return false, warning
    end
    if UWMDepot.getPlacingBlocked(self) then
        return false, UtilitiesWasteManagement.getText("uwm_warning_oneDepot")
    end
    return true, nil
end

function UWMDepot:getCanBePlacedAt(superFunc, x, y, z, farmId)
    if UWMDepot.getPlacingBlocked(self) then
        return false, UtilitiesWasteManagement.getText("uwm_warning_oneDepot")
    end
    return superFunc(self, x, y, z, farmId)
end

-- office door: every farm's players may open the Utilities page here
function UWMDepot:uwmOfficeTriggerCallback(triggerId, otherActorId, onEnter, onLeave, onStay, otherShapeId)
    if (onEnter or onLeave) and g_localPlayer ~= nil and otherActorId == g_localPlayer.rootNode then
        local spec = getSpec(self)
        if onEnter then
            g_currentMission.activatableObjectsSystem:addActivatable(spec.activatable)
        else
            g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
        end
    end
end


UWMDepotActivatable = {}
local UWMDepotActivatable_mt = Class(UWMDepotActivatable)

function UWMDepotActivatable.new(placeable)
    local self = setmetatable({}, UWMDepotActivatable_mt)
    self.placeable = placeable
    self.activateText = UtilitiesWasteManagement.getText("uwm_action_openDepot")
    return self
end

function UWMDepotActivatable:getIsActivatable()
    return g_currentMission:getFarmId() ~= FarmManager.SPECTATOR_FARM_ID
end

function UWMDepotActivatable:run()
    UWMFrame.open()
end
