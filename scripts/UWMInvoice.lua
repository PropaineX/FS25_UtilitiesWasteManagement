-- Utilities & Waste Management: one invoice (a one-off trade or a standing contract) between two farms.
-- Author: PropaineX

UWMInvoice = {}
local UWMInvoice_mt = Class(UWMInvoice)

UWMInvoice.STATE = {
    PENDING = 1,    -- sent, waiting for the other farm's manager
    ACTIVE = 2,     -- accepted: paid liters can be collected / contract runs
    DONE = 3,
    DECLINED = 4,
    CANCELLED = 5
}

UWMInvoice.AMOUNT = {
    FIXED = 1,      -- a set number of liters
    ALL = 2         -- "I'll take all of it": everything the seller has in stock when paid
}

-- days between deliveries; 0 = one-off
UWMInvoice.REPEAT_ONCE = 0
UWMInvoice.REPEAT_DAILY = 1
UWMInvoice.REPEAT_WEEKLY = 7

UWMInvoice.MAX_TARGETS = 32

function UWMInvoice.new()
    local self = setmetatable({}, UWMInvoice_mt)

    self.id = 0
    self.creatorFarmId = 0
    self.sellerFarmId = 0
    self.buyerFarmId = 0
    self.fillTypeIndex = FillType.UNKNOWN
    self.amountMode = UWMInvoice.AMOUNT.FIXED
    self.liters = 0
    self.pricePer1000 = 0         -- the full price; the buyer pays this less discountPercent
    self.discountPercent = 0      -- 0..100, set by whoever writes the invoice (both farms see it)
    self.reserve = false
    self.repeatDays = UWMInvoice.REPEAT_ONCE
    self.targets = {}           -- electricity: uniqueIds of the buyer's productions, in fill order

    self.state = UWMInvoice.STATE.PENDING
    self.createdDay = 0
    self.nextPeriodDay = 0
    self.owedLiters = 0         -- paid for, not yet collected (manure / slurry)
    self.depotLiters = 0        -- the seller's goods moved into the depot for this invoice (paid or not yet)
    self.totalLiters = 0        -- delivered or collected so far
    self.totalMoney = 0         -- paid by the buyer so far, refunds taken off
    self.totalRefund = 0
    self.refundedLiters = 0     -- liters paid for, never collected, money given back
    self.finishedDay = 0
    self.hiddenBySeller = false -- a farm deleted it from its own history (removed once both have)
    self.hiddenByBuyer = false
    self.statusKey = ""         -- l10n key of the last problem, "" = none
    self.listingId = 0          -- made from this standing order (0 = a normal invoice)
    self.prepaid = false        -- the buyer paid up front by posting a wanted order: the seller is paid from that
    self.isPallet = false       -- pallet goods: taken off the seller's pallets, handed out as pallets on the pad
    self.palletSize = 1000      -- liters per new pallet (1,000 or 5,000; capped by the game's pallet)

    return self
end

function UWMInvoice:getIsFinished()
    return self.state == UWMInvoice.STATE.DONE or self.state == UWMInvoice.STATE.DECLINED
        or self.state == UWMInvoice.STATE.CANCELLED
end

function UWMInvoice:getIsElectricity()
    return self.fillTypeIndex == FillType.ELECTRICCHARGE
end

function UWMInvoice:getIsBill()
    return self.creatorFarmId == self.sellerFarmId
end

function UWMInvoice:getOtherFarmId(farmId)
    if farmId == self.sellerFarmId then
        return self.buyerFarmId
    end
    return self.sellerFarmId
end

function UWMInvoice:getIsHiddenFor(farmId)
    return (farmId == self.sellerFarmId and self.hiddenBySeller) or (farmId == self.buyerFarmId and self.hiddenByBuyer)
end

-- the price per 1,000 after the discount: what is really paid
function UWMInvoice:getPaidPricePer1000()
    return self.pricePer1000 * (1 - self.discountPercent / 100)
end

-- what the buyer pays for these liters (discount taken off)
function UWMInvoice:getPrice(liters)
    return liters * self:getPaidPricePer1000() / 1000
end

-- the same liters at the full price, and what the discount takes off that
function UWMInvoice:getFullPrice(liters)
    return liters * self.pricePer1000 / 1000
end

function UWMInvoice:getDiscount(liters)
    return self:getFullPrice(liters) - self:getPrice(liters)
end

-- the discount on money already paid (paid = full price less discount)
function UWMInvoice:getDiscountOnPaid(paid)
    if self.discountPercent <= 0 or self.discountPercent >= 100 then
        return 0
    end
    return paid * self.discountPercent / (100 - self.discountPercent)
end

-- manure / slurry for sale sits in the depot (depotLiters), not in the seller's storage, so nothing is held there
function UWMInvoice:getReservedLiters()
    if not self:getIsElectricity() then
        return 0
    end
    if self.reserve and self.state == UWMInvoice.STATE.ACTIVE then
        return self.owedLiters
    end
    return 0
end

function UWMInvoice:writeStream(streamId)
    streamWriteInt32(streamId, self.id)
    streamWriteUInt8(streamId, self.creatorFarmId)
    streamWriteUInt8(streamId, self.sellerFarmId)
    streamWriteUInt8(streamId, self.buyerFarmId)
    streamWriteUInt16(streamId, self.fillTypeIndex)
    streamWriteUInt8(streamId, self.amountMode)
    streamWriteFloat32(streamId, self.liters)
    streamWriteFloat32(streamId, self.pricePer1000)
    streamWriteFloat32(streamId, self.discountPercent)
    streamWriteBool(streamId, self.reserve)
    streamWriteUInt8(streamId, self.repeatDays)
    UWMInvoice.writeTargets(streamId, self.targets)
    streamWriteUInt8(streamId, self.state)
    streamWriteInt32(streamId, self.createdDay)
    streamWriteInt32(streamId, self.nextPeriodDay)
    streamWriteFloat32(streamId, self.owedLiters)
    streamWriteFloat32(streamId, self.depotLiters)
    streamWriteFloat32(streamId, self.totalLiters)
    streamWriteFloat32(streamId, self.totalMoney)
    streamWriteFloat32(streamId, self.totalRefund)
    streamWriteFloat32(streamId, self.refundedLiters)
    streamWriteInt32(streamId, self.finishedDay)
    streamWriteBool(streamId, self.hiddenBySeller)
    streamWriteBool(streamId, self.hiddenByBuyer)
    streamWriteString(streamId, self.statusKey)
    streamWriteInt32(streamId, self.listingId)
    streamWriteBool(streamId, self.prepaid)
    streamWriteBool(streamId, self.isPallet)
    streamWriteInt32(streamId, self.palletSize)
end

function UWMInvoice:readStream(streamId)
    self.id = streamReadInt32(streamId)
    self.creatorFarmId = streamReadUInt8(streamId)
    self.sellerFarmId = streamReadUInt8(streamId)
    self.buyerFarmId = streamReadUInt8(streamId)
    self.fillTypeIndex = streamReadUInt16(streamId)
    self.amountMode = streamReadUInt8(streamId)
    self.liters = streamReadFloat32(streamId)
    self.pricePer1000 = streamReadFloat32(streamId)
    self.discountPercent = streamReadFloat32(streamId)
    self.reserve = streamReadBool(streamId)
    self.repeatDays = streamReadUInt8(streamId)
    self.targets = UWMInvoice.readTargets(streamId)
    self.state = streamReadUInt8(streamId)
    self.createdDay = streamReadInt32(streamId)
    self.nextPeriodDay = streamReadInt32(streamId)
    self.owedLiters = streamReadFloat32(streamId)
    self.depotLiters = streamReadFloat32(streamId)
    self.totalLiters = streamReadFloat32(streamId)
    self.totalMoney = streamReadFloat32(streamId)
    self.totalRefund = streamReadFloat32(streamId)
    self.refundedLiters = streamReadFloat32(streamId)
    self.finishedDay = streamReadInt32(streamId)
    self.hiddenBySeller = streamReadBool(streamId)
    self.hiddenByBuyer = streamReadBool(streamId)
    self.statusKey = streamReadString(streamId)
    self.listingId = streamReadInt32(streamId)
    self.prepaid = streamReadBool(streamId)
    self.isPallet = streamReadBool(streamId)
    self.palletSize = streamReadInt32(streamId)
end

function UWMInvoice.writeTargets(streamId, targets)
    local count = math.min(#targets, UWMInvoice.MAX_TARGETS)
    streamWriteUInt8(streamId, count)
    for i = 1, count do
        streamWriteString(streamId, targets[i])
    end
end

function UWMInvoice.readTargets(streamId)
    local targets = {}
    for _ = 1, streamReadUInt8(streamId) do
        table.insert(targets, streamReadString(streamId))
    end
    return targets
end

function UWMInvoice:saveToXMLFile(xmlFile, key)
    local fillType = g_fillTypeManager:getFillTypeByIndex(self.fillTypeIndex)

    xmlFile:setInt(key .. "#id", self.id)
    xmlFile:setInt(key .. "#creatorFarmId", self.creatorFarmId)
    xmlFile:setInt(key .. "#sellerFarmId", self.sellerFarmId)
    xmlFile:setInt(key .. "#buyerFarmId", self.buyerFarmId)
    xmlFile:setString(key .. "#fillType", fillType ~= nil and fillType.name or "UNKNOWN")
    xmlFile:setInt(key .. "#amountMode", self.amountMode)
    xmlFile:setFloat(key .. "#liters", self.liters)
    xmlFile:setFloat(key .. "#pricePer1000", self.pricePer1000)
    xmlFile:setFloat(key .. "#discountPercent", self.discountPercent)
    xmlFile:setBool(key .. "#reserve", self.reserve)
    xmlFile:setInt(key .. "#repeatDays", self.repeatDays)
    xmlFile:setInt(key .. "#state", self.state)
    xmlFile:setInt(key .. "#createdDay", self.createdDay)
    xmlFile:setInt(key .. "#nextPeriodDay", self.nextPeriodDay)
    xmlFile:setFloat(key .. "#owedLiters", self.owedLiters)
    xmlFile:setFloat(key .. "#depotLiters", self.depotLiters)
    xmlFile:setFloat(key .. "#totalLiters", self.totalLiters)
    xmlFile:setFloat(key .. "#totalMoney", self.totalMoney)
    xmlFile:setFloat(key .. "#totalRefund", self.totalRefund)
    xmlFile:setFloat(key .. "#refundedLiters", self.refundedLiters)
    xmlFile:setInt(key .. "#finishedDay", self.finishedDay)
    xmlFile:setBool(key .. "#hiddenBySeller", self.hiddenBySeller)
    xmlFile:setBool(key .. "#hiddenByBuyer", self.hiddenByBuyer)
    xmlFile:setString(key .. "#statusKey", self.statusKey)
    xmlFile:setInt(key .. "#listingId", self.listingId)
    xmlFile:setBool(key .. "#prepaid", self.prepaid)
    xmlFile:setBool(key .. "#isPallet", self.isPallet)
    xmlFile:setInt(key .. "#palletSize", self.palletSize)

    for i, uniqueId in ipairs(self.targets) do
        xmlFile:setString(string.format("%s.target(%d)#uniqueId", key, i - 1), uniqueId)
    end
end

-- returns false when the invoice can't be used (e.g. its fill type is gone from this game)
function UWMInvoice:loadFromXMLFile(xmlFile, key)
    self.fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName(xmlFile:getString(key .. "#fillType", ""))
    if self.fillTypeIndex == nil then
        return false
    end

    self.id = xmlFile:getInt(key .. "#id", 0)
    self.creatorFarmId = xmlFile:getInt(key .. "#creatorFarmId", 0)
    self.sellerFarmId = xmlFile:getInt(key .. "#sellerFarmId", 0)
    self.buyerFarmId = xmlFile:getInt(key .. "#buyerFarmId", 0)
    self.amountMode = xmlFile:getInt(key .. "#amountMode", UWMInvoice.AMOUNT.FIXED)
    self.liters = xmlFile:getFloat(key .. "#liters", 0)
    self.pricePer1000 = xmlFile:getFloat(key .. "#pricePer1000", 0)
    self.discountPercent = xmlFile:getFloat(key .. "#discountPercent", 0) -- older saves: none
    self.reserve = xmlFile:getBool(key .. "#reserve", false)
    self.repeatDays = xmlFile:getInt(key .. "#repeatDays", UWMInvoice.REPEAT_ONCE)
    self.state = xmlFile:getInt(key .. "#state", UWMInvoice.STATE.PENDING)
    self.createdDay = xmlFile:getInt(key .. "#createdDay", 0)
    self.nextPeriodDay = xmlFile:getInt(key .. "#nextPeriodDay", 0)
    self.owedLiters = xmlFile:getFloat(key .. "#owedLiters", 0)
    self.depotLiters = xmlFile:getFloat(key .. "#depotLiters", 0)
    self.totalLiters = xmlFile:getFloat(key .. "#totalLiters", 0)
    self.totalMoney = xmlFile:getFloat(key .. "#totalMoney", 0)
    self.totalRefund = xmlFile:getFloat(key .. "#totalRefund", 0)
    -- older saves (0.1/0.2) have no refundedLiters: work it out from the money
    local paidPrice = self:getPaidPricePer1000()
    local defaultRefundLiters = paidPrice > 0 and self.totalRefund / paidPrice * 1000 or 0
    self.refundedLiters = xmlFile:getFloat(key .. "#refundedLiters", defaultRefundLiters)
    self.finishedDay = xmlFile:getInt(key .. "#finishedDay", 0)
    self.hiddenBySeller = xmlFile:getBool(key .. "#hiddenBySeller", false)
    self.hiddenByBuyer = xmlFile:getBool(key .. "#hiddenByBuyer", false)
    self.statusKey = xmlFile:getString(key .. "#statusKey", "")
    self.listingId = xmlFile:getInt(key .. "#listingId", 0)
    self.prepaid = xmlFile:getBool(key .. "#prepaid", false)
    self.isPallet = xmlFile:getBool(key .. "#isPallet", false)
    self.palletSize = xmlFile:getInt(key .. "#palletSize", 1000)

    self.targets = {}
    xmlFile:iterate(key .. ".target", function(_, targetKey)
        local uniqueId = xmlFile:getString(targetKey .. "#uniqueId")
        if uniqueId ~= nil then
            table.insert(self.targets, uniqueId)
        end
    end)

    return self.id > 0
end
