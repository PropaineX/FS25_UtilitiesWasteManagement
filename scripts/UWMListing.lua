-- Utilities & Waste Management: one standing order on the board, open to every farm (user's idea, 2026-10-24).
-- OFFER  = "I have 1,000,000 l to sell": the poster's stock is held for it; any farm buys any part of what's left.
-- WANTED = "I want 1,000,000 l": the poster's money for the whole amount is held; any farm sells any part of it.
-- Every deal becomes a normal paid invoice between the poster and that farm; the order counts down to 0 = complete.
-- Author: PropaineX

UWMListing = {}
local UWMListing_mt = Class(UWMListing)

UWMListing.KIND = {
    OFFER = 1,      -- the poster sells
    WANTED = 2      -- the poster buys
}

UWMListing.STATE = {
    OPEN = 1,
    DONE = 2,       -- nothing left: sold out / fully delivered
    CANCELLED = 3   -- withdrawn by the poster
}

function UWMListing.new()
    local self = setmetatable({}, UWMListing_mt)

    self.isListing = true
    self.id = 0
    self.farmId = 0
    self.kind = UWMListing.KIND.OFFER
    self.fillTypeIndex = FillType.UNKNOWN
    self.liters = 0             -- the whole order
    self.remaining = 0          -- still open for other farms
    self.pricePer1000 = 0
    self.targets = {}           -- WANTED electricity: uniqueIds of the poster's productions, in fill order

    self.state = UWMListing.STATE.OPEN
    self.createdDay = 0
    self.finishedDay = 0
    self.trades = 0             -- deals made on it
    self.tradedLiters = 0
    self.totalMoney = 0         -- paid to / by the poster through those deals

    return self
end

function UWMListing:getIsOffer()
    return self.kind == UWMListing.KIND.OFFER
end

function UWMListing:getIsOpen()
    return self.state == UWMListing.STATE.OPEN
end

function UWMListing:getIsElectricity()
    return self.fillTypeIndex == FillType.ELECTRICCHARGE
end

function UWMListing:getPrice(liters)
    return liters * self.pricePer1000 / 1000
end

-- an open offer holds the poster's stock for what's left
function UWMListing:getReservedLiters()
    if self:getIsOffer() and self:getIsOpen() then
        return self.remaining
    end
    return 0
end

-- an open wanted order holds the poster's money for what's left
function UWMListing:getHeldMoney()
    if not self:getIsOffer() and self:getIsOpen() then
        return self:getPrice(self.remaining)
    end
    return 0
end

function UWMListing:writeStream(streamId)
    streamWriteInt32(streamId, self.id)
    streamWriteUInt8(streamId, self.farmId)
    streamWriteUInt8(streamId, self.kind)
    streamWriteUInt16(streamId, self.fillTypeIndex)
    streamWriteFloat32(streamId, self.liters)
    streamWriteFloat32(streamId, self.remaining)
    streamWriteFloat32(streamId, self.pricePer1000)
    UWMInvoice.writeTargets(streamId, self.targets)
    streamWriteUInt8(streamId, self.state)
    streamWriteInt32(streamId, self.createdDay)
    streamWriteInt32(streamId, self.finishedDay)
    streamWriteInt32(streamId, self.trades)
    streamWriteFloat32(streamId, self.tradedLiters)
    streamWriteFloat32(streamId, self.totalMoney)
end

function UWMListing:readStream(streamId)
    self.id = streamReadInt32(streamId)
    self.farmId = streamReadUInt8(streamId)
    self.kind = streamReadUInt8(streamId)
    self.fillTypeIndex = streamReadUInt16(streamId)
    self.liters = streamReadFloat32(streamId)
    self.remaining = streamReadFloat32(streamId)
    self.pricePer1000 = streamReadFloat32(streamId)
    self.targets = UWMInvoice.readTargets(streamId)
    self.state = streamReadUInt8(streamId)
    self.createdDay = streamReadInt32(streamId)
    self.finishedDay = streamReadInt32(streamId)
    self.trades = streamReadInt32(streamId)
    self.tradedLiters = streamReadFloat32(streamId)
    self.totalMoney = streamReadFloat32(streamId)
end

function UWMListing:saveToXMLFile(xmlFile, key)
    local fillType = g_fillTypeManager:getFillTypeByIndex(self.fillTypeIndex)

    xmlFile:setInt(key .. "#id", self.id)
    xmlFile:setInt(key .. "#farmId", self.farmId)
    xmlFile:setInt(key .. "#kind", self.kind)
    xmlFile:setString(key .. "#fillType", fillType ~= nil and fillType.name or "UNKNOWN")
    xmlFile:setFloat(key .. "#liters", self.liters)
    xmlFile:setFloat(key .. "#remaining", self.remaining)
    xmlFile:setFloat(key .. "#pricePer1000", self.pricePer1000)
    xmlFile:setInt(key .. "#state", self.state)
    xmlFile:setInt(key .. "#createdDay", self.createdDay)
    xmlFile:setInt(key .. "#finishedDay", self.finishedDay)
    xmlFile:setInt(key .. "#trades", self.trades)
    xmlFile:setFloat(key .. "#tradedLiters", self.tradedLiters)
    xmlFile:setFloat(key .. "#totalMoney", self.totalMoney)

    for i, uniqueId in ipairs(self.targets) do
        xmlFile:setString(string.format("%s.target(%d)#uniqueId", key, i - 1), uniqueId)
    end
end

-- returns false when the order can't be used (e.g. its fill type is gone from this game)
function UWMListing:loadFromXMLFile(xmlFile, key)
    self.fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(xmlFile:getString(key .. "#fillType", ""))
    if self.fillTypeIndex == nil then
        return false
    end

    self.id = xmlFile:getInt(key .. "#id", 0)
    self.farmId = xmlFile:getInt(key .. "#farmId", 0)
    self.kind = xmlFile:getInt(key .. "#kind", UWMListing.KIND.OFFER)
    self.liters = xmlFile:getFloat(key .. "#liters", 0)
    self.remaining = xmlFile:getFloat(key .. "#remaining", 0)
    self.pricePer1000 = xmlFile:getFloat(key .. "#pricePer1000", 0)
    self.state = xmlFile:getInt(key .. "#state", UWMListing.STATE.OPEN)
    self.createdDay = xmlFile:getInt(key .. "#createdDay", 0)
    self.finishedDay = xmlFile:getInt(key .. "#finishedDay", 0)
    self.trades = xmlFile:getInt(key .. "#trades", 0)
    self.tradedLiters = xmlFile:getFloat(key .. "#tradedLiters", 0)
    self.totalMoney = xmlFile:getFloat(key .. "#totalMoney", 0)

    self.targets = {}
    xmlFile:iterate(key .. ".target", function(_, targetKey)
        local uniqueId = xmlFile:getString(targetKey .. "#uniqueId")
        if uniqueId ~= nil then
            table.insert(self.targets, uniqueId)
        end
    end)

    return self.id > 0 and self.farmId > 0
end
