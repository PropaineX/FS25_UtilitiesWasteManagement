-- Utilities & Waste Management: network events.
-- UWMRequestEvent  client -> server  a farm manager's request (create, accept, decline, cancel)
-- UWMResultEvent   server -> client  the answer to that request
-- UWMSyncEvent     server -> clients the whole invoice list (on join and after every change)
-- UWMNotifyEvent   server -> clients a message for one farm
-- Author: PropaineX

UWMRequestEvent = {}
local UWMRequestEvent_mt = Class(UWMRequestEvent, Event)
InitEventClass(UWMRequestEvent, "UWMRequestEvent")

function UWMRequestEvent.emptyNew()
    return Event.new(UWMRequestEvent_mt)
end

-- data: {invoice = UWMInvoice (CREATE only), invoiceId, reserve, targetPlaceables}
-- The buyer's electricity productions travel as network objects: a placed building's uniqueId is NOT sent to
-- clients (Placeable:writeStream), each client makes up its own, so the server turns the objects into its own
-- uniqueIds (data.targets) when the request arrives.
function UWMRequestEvent.new(action, data)
    local self = UWMRequestEvent.emptyNew()
    self.action = action
    self.data = data
    return self
end

function UWMRequestEvent:writeStream(streamId, connection)
    local data = self.data
    streamWriteUInt8(streamId, self.action)
    streamWriteInt32(streamId, data.invoiceId or 0)
    if streamWriteBool(streamId, data.invoice ~= nil) then
        data.invoice:writeStream(streamId)
    end
    streamWriteBool(streamId, data.reserve == true)
    local placeables = data.targetPlaceables
    if streamWriteBool(streamId, placeables ~= nil) then
        local count = math.min(#placeables, UWMInvoice.MAX_TARGETS)
        streamWriteUInt8(streamId, count)
        for i = 1, count do
            NetworkUtil.writeNodeObject(streamId, placeables[i])
        end
    end
end

function UWMRequestEvent:readStream(streamId, connection)
    self.action = streamReadUInt8(streamId)
    self.data = {}
    self.data.invoiceId = streamReadInt32(streamId)
    if streamReadBool(streamId) then
        self.data.invoice = UWMInvoice.new()
        self.data.invoice:readStream(streamId)
    end
    self.data.reserve = streamReadBool(streamId)
    if streamReadBool(streamId) then
        local placeables = {}
        for _ = 1, streamReadUInt8(streamId) do
            local placeable = NetworkUtil.readNodeObject(streamId)
            if placeable ~= nil then
                table.insert(placeables, placeable)
            end
        end
        self.data.targets = UWMRequestEvent.getUniqueIds(placeables)
    end
    self:run(connection)
end

function UWMRequestEvent:run(connection)
    if connection:getIsServer() then
        return
    end
    local manager = UtilitiesWasteManagement.manager
    if manager == nil then
        return
    end
    local userId = g_currentMission.userManager:getUserIdByConnection(connection)
    local ok, key = manager:handleRequest(self.action, userId, self.data)
    connection:sendEvent(UWMResultEvent.new(ok, key))
end

-- server side: the placeables' uniqueIds as the server knows them
function UWMRequestEvent.getUniqueIds(placeables)
    local uniqueIds = {}
    for _, placeable in ipairs(placeables) do
        if placeable.getUniqueId ~= nil and placeable:getUniqueId() ~= nil then
            table.insert(uniqueIds, placeable:getUniqueId())
        end
    end
    return uniqueIds
end

-- runs the request straight away on a host / in singleplayer, else sends it to the server; the answer comes
-- back to UtilitiesWasteManagement.onRequestResult
function UWMRequestEvent.sendRequest(action, data)
    if g_server ~= nil then
        local manager = UtilitiesWasteManagement.manager
        if manager ~= nil then
            if data.targetPlaceables ~= nil then
                data.targets = UWMRequestEvent.getUniqueIds(data.targetPlaceables)
            end
            local ok, key = manager:handleRequest(action, g_currentMission.playerUserId, data)
            UtilitiesWasteManagement.onRequestResult(ok, key)
        end
    else
        g_client:getServerConnection():sendEvent(UWMRequestEvent.new(action, data))
    end
end


UWMResultEvent = {}
local UWMResultEvent_mt = Class(UWMResultEvent, Event)
InitEventClass(UWMResultEvent, "UWMResultEvent")

function UWMResultEvent.emptyNew()
    return Event.new(UWMResultEvent_mt)
end

function UWMResultEvent.new(ok, key)
    local self = UWMResultEvent.emptyNew()
    self.ok = ok
    self.key = key or ""
    return self
end

function UWMResultEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.ok)
    streamWriteString(streamId, self.key)
end

function UWMResultEvent:readStream(streamId, connection)
    self.ok = streamReadBool(streamId)
    self.key = streamReadString(streamId)
    self:run(connection)
end

function UWMResultEvent:run(connection)
    if connection:getIsServer() then
        UtilitiesWasteManagement.onRequestResult(self.ok, self.key)
    end
end


UWMSyncEvent = {}
local UWMSyncEvent_mt = Class(UWMSyncEvent, Event)
InitEventClass(UWMSyncEvent, "UWMSyncEvent")

function UWMSyncEvent.emptyNew()
    return Event.new(UWMSyncEvent_mt)
end

function UWMSyncEvent.new(manager)
    local self = UWMSyncEvent.emptyNew()
    self.manager = manager
    return self
end

function UWMSyncEvent:writeStream(streamId, connection)
    self.manager:writeStream(streamId)
end

function UWMSyncEvent:readStream(streamId, connection)
    -- read everything even without a manager, or the stream breaks
    local manager = UtilitiesWasteManagement.manager or UWMManager.new(false)
    manager:readStream(streamId)
end

function UWMSyncEvent:run(connection)
end


UWMNotifyEvent = {}
local UWMNotifyEvent_mt = Class(UWMNotifyEvent, Event)
InitEventClass(UWMNotifyEvent, "UWMNotifyEvent")

function UWMNotifyEvent.emptyNew()
    return Event.new(UWMNotifyEvent_mt)
end

function UWMNotifyEvent.new(farmId, key, farmName, fillTypeIndex)
    local self = UWMNotifyEvent.emptyNew()
    self.farmId = farmId
    self.key = key
    self.farmName = farmName or ""
    self.fillTypeIndex = fillTypeIndex or FillType.UNKNOWN
    return self
end

function UWMNotifyEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.farmId)
    streamWriteString(streamId, self.key)
    streamWriteString(streamId, self.farmName)
    streamWriteUInt16(streamId, self.fillTypeIndex)
end

function UWMNotifyEvent:readStream(streamId, connection)
    self.farmId = streamReadUInt8(streamId)
    self.key = streamReadString(streamId)
    self.farmName = streamReadString(streamId)
    self.fillTypeIndex = streamReadUInt16(streamId)
    self:run(connection)
end

function UWMNotifyEvent:run(connection)
    UtilitiesWasteManagement.showNotification(self.farmId, self.key, self.farmName, self.fillTypeIndex)
end

function UWMNotifyEvent.sendEvent(farmId, key, farmName, fillTypeIndex)
    if g_server ~= nil then
        g_server:broadcastEvent(UWMNotifyEvent.new(farmId, key, farmName, fillTypeIndex), false)
        -- a host / singleplayer player gets no broadcast of their own
        if g_currentMission:getIsClient() then
            UtilitiesWasteManagement.showNotification(farmId, key, farmName, fillTypeIndex)
        end
    end
end
