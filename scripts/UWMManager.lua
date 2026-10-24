-- Utilities & Waste Management: all invoices, and everything that changes them. Changes run on the server only;
-- clients get a copy through UWMSyncEvent.
-- Author: PropaineX

UWMManager = {}
local UWMManager_mt = Class(UWMManager)

UWMManager.ACTION = {
    CREATE = 1,
    ACCEPT = 2,
    DECLINE = 3,
    CANCEL = 4,     -- pending: the sender takes it back; active: either farm ends it, unpaid-out liters refunded
    DELETE = 5,     -- a finished invoice leaves this farm's history (gone for good once both farms deleted it)
    CLEAR_HISTORY = 6 -- DELETE for every finished invoice of this farm
}

UWMManager.MAX_HISTORY = 100
UWMManager.SYNC_INTERVAL = 1000  -- ms between syncs while liters are being collected
UWMManager.EPSILON = 0.01

local STATE = UWMInvoice.STATE

function UWMManager.new(isServer)
    local self = setmetatable({}, UWMManager_mt)

    self.isServer = isServer
    self.invoices = {}          -- in creation order
    self.invoiceById = {}
    self.nextId = 1
    self.syncDirty = false
    self.syncTimer = 0
    self.listeners = {}

    return self
end

function UWMManager:delete()
    self.invoices = {}
    self.invoiceById = {}
    self.listeners = {}
end

-- GUI pages register here to redraw when the list changes
function UWMManager:addChangeListener(func, target)
    table.insert(self.listeners, {func = func, target = target})
end

function UWMManager:removeChangeListener(target)
    for i = #self.listeners, 1, -1 do
        if self.listeners[i].target == target then
            table.remove(self.listeners, i)
        end
    end
end

function UWMManager:raiseChanged()
    for _, listener in ipairs(self.listeners) do
        listener.func(listener.target)
    end
end

function UWMManager:getInvoice(id)
    return self.invoiceById[id]
end

function UWMManager:getInvoices()
    return self.invoices
end

function UWMManager:addInvoice(invoice)
    table.insert(self.invoices, invoice)
    self.invoiceById[invoice.id] = invoice
    self.nextId = math.max(self.nextId, invoice.id + 1)
end

function UWMManager:removeInvoice(invoice)
    for i, other in ipairs(self.invoices) do
        if other == invoice then
            table.remove(self.invoices, i)
            break
        end
    end
    self.invoiceById[invoice.id] = nil
end

-- liters of a seller's stock held for buyers who ticked Reserve
function UWMManager:getReservedLiters(farmId, fillTypeIndex, exceptInvoice)
    local reserved = 0
    for _, invoice in ipairs(self.invoices) do
        if invoice ~= exceptInvoice and invoice.sellerFarmId == farmId and invoice.fillTypeIndex == fillTypeIndex then
            reserved = reserved + invoice:getReservedLiters()
        end
    end
    return reserved
end

----------------------------------------------------------------------------------------------------------------
-- Farms, money, notifications
----------------------------------------------------------------------------------------------------------------

function UWMManager.getFarmName(farmId)
    local farm = g_farmManager:getFarmById(farmId)
    if farm ~= nil and farm.name ~= nil then
        return farm.name
    end
    return tostring(farmId)
end

function UWMManager.getFarmBalance(farmId)
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil then
        return 0
    end
    if farm.getBalance ~= nil then
        return farm:getBalance()
    end
    return farm.money or 0
end

function UWMManager.getIsTradingFarm(farmId)
    return farmId ~= nil and farmId ~= FarmManager.SPECTATOR_FARM_ID and g_farmManager:getFarmById(farmId) ~= nil
end

-- buyer -> seller (negative amount = refund seller -> buyer)
function UWMManager:transferMoney(invoice, amount)
    if math.abs(amount) < 0.005 then
        return
    end
    local mission = g_currentMission
    mission:addMoney(-amount, invoice.buyerFarmId, amount > 0 and MoneyType.UWM_EXPENSE or MoneyType.UWM_INCOME, true)
    mission:addMoney(amount, invoice.sellerFarmId, amount > 0 and MoneyType.UWM_INCOME or MoneyType.UWM_EXPENSE, true)
    invoice.totalMoney = invoice.totalMoney + amount
end

-- detail: optional text for a third %s (the numbers of a receipt)
function UWMManager:notify(farmId, key, invoice, detail)
    if farmId == nil or farmId == FarmManager.SPECTATOR_FARM_ID then
        return
    end
    local otherName = invoice ~= nil and UWMManager.getFarmName(invoice:getOtherFarmId(farmId)) or ""
    UWMNotifyEvent.sendEvent(farmId, key, otherName, invoice ~= nil and invoice.fillTypeIndex or FillType.UNKNOWN, detail)
end

-- "4,123 kWh delivered, $1,443 paid, $0 refunded" for the whole invoice so far
function UWMManager.getReceiptLine(invoice)
    local UWM = UtilitiesWasteManagement
    return string.format(UWM.getText("uwm_receipt_line"), UWM.formatAmount(invoice.fillTypeIndex, invoice.totalLiters),
        UWM.formatMoney(invoice.totalMoney), UWM.formatMoney(invoice.totalRefund))
end

-- both farms get the numbers when an invoice is over
function UWMManager:sendReceipt(invoice)
    local line = UWMManager.getReceiptLine(invoice)
    self:notify(invoice.sellerFarmId, "uwm_notify_receipt", invoice, line)
    self:notify(invoice.buyerFarmId, "uwm_notify_receipt", invoice, line)
end

function UWMManager:finish(invoice, state)
    invoice.state = state
    invoice.finishedDay = g_currentMission.environment.currentMonotonicDay
end

----------------------------------------------------------------------------------------------------------------
-- Requests (server)
----------------------------------------------------------------------------------------------------------------

-- the farm of the player behind a request, and whether that player is its farm manager
function UWMManager.getActor(userId)
    local farm = g_farmManager:getFarmByUserId(userId)
    if farm == nil then
        return nil, false
    end
    local isManager = not g_currentMission.missionDynamicInfo.isMultiplayer
    if not isManager and farm.isUserFarmManager ~= nil then
        isManager = farm:isUserFarmManager(userId)
    end
    return farm.farmId, isManager
end

-- data: {invoice = UWMInvoice for CREATE, invoiceId, reserve, targets}
-- returns ok, l10n key of the result for the player who asked
function UWMManager:handleRequest(action, userId, data)
    local ok, key = self:runRequest(action, userId, data)
    print(string.format("%s request %s by user %s (invoice %s, %d target(s)): %s %s", UtilitiesWasteManagement.TAG,
        tostring(action), tostring(userId), tostring(data.invoiceId or (data.invoice ~= nil and "new") or "-"),
        data.targets ~= nil and #data.targets or 0, ok and "OK" or "REFUSED", tostring(key)))
    return ok, key
end

function UWMManager:runRequest(action, userId, data)
    if not self.isServer then
        return false, "uwm_error_notServer"
    end

    local farmId, isManager = UWMManager.getActor(userId)
    if not UWMManager.getIsTradingFarm(farmId) then
        return false, "uwm_error_noFarm"
    end
    if not isManager then
        return false, "uwm_error_notManager"
    end

    if action == UWMManager.ACTION.CREATE then
        return self:createInvoice(farmId, data.invoice, data.targets)
    elseif action == UWMManager.ACTION.CLEAR_HISTORY then
        return self:clearHistory(farmId)
    end

    local invoice = self:getInvoice(data.invoiceId or 0)
    if invoice == nil then
        return false, "uwm_error_unknownInvoice"
    end
    if farmId ~= invoice.sellerFarmId and farmId ~= invoice.buyerFarmId then
        return false, "uwm_error_notYours"
    end

    if action == UWMManager.ACTION.ACCEPT then
        return self:acceptInvoice(farmId, invoice, data.reserve, data.targets)
    elseif action == UWMManager.ACTION.DECLINE then
        return self:declineInvoice(farmId, invoice)
    elseif action == UWMManager.ACTION.CANCEL then
        return self:cancelInvoice(farmId, invoice)
    elseif action == UWMManager.ACTION.DELETE then
        return self:deleteInvoice(farmId, invoice)
    end

    return false, "uwm_error_unknownAction"
end

function UWMManager:createInvoice(farmId, data, targets)
    if data == nil or UtilitiesWasteManagement.getGood(data.fillTypeIndex) == nil then
        return false, "uwm_error_badGood"
    end

    local isBill = data.sellerFarmId == farmId
    local otherFarmId = isBill and data.buyerFarmId or data.sellerFarmId
    if (not isBill and data.buyerFarmId ~= farmId) or otherFarmId == farmId or not UWMManager.getIsTradingFarm(otherFarmId) then
        return false, "uwm_error_badFarm"
    end
    if data.amountMode == UWMInvoice.AMOUNT.FIXED and not (data.liters > 0) then
        return false, "uwm_error_badAmount"
    end
    if not (data.pricePer1000 >= 0) then
        return false, "uwm_error_badPrice"
    end
    if data.repeatDays ~= UWMInvoice.REPEAT_ONCE and data.repeatDays ~= UWMInvoice.REPEAT_DAILY
        and data.repeatDays ~= UWMInvoice.REPEAT_WEEKLY then
        return false, "uwm_error_badRepeat"
    end

    local invoice = UWMInvoice.new()
    invoice.id = self.nextId
    invoice.creatorFarmId = farmId
    invoice.sellerFarmId = data.sellerFarmId
    invoice.buyerFarmId = data.buyerFarmId
    invoice.fillTypeIndex = data.fillTypeIndex
    invoice.amountMode = data.amountMode
    invoice.liters = data.amountMode == UWMInvoice.AMOUNT.FIXED and data.liters or 0
    invoice.pricePer1000 = data.pricePer1000
    invoice.repeatDays = data.repeatDays
    invoice.createdDay = g_currentMission.environment.currentMonotonicDay

    -- buyer's choices: on an order the buyer makes them now, on a bill when accepting
    if not isBill then
        invoice.reserve = data.reserve and not invoice:getIsElectricity()
        invoice.targets = targets or {}
    end

    self:addInvoice(invoice)
    self:notify(otherFarmId, isBill and "uwm_notify_newBill" or "uwm_notify_newOrder", invoice)
    self:setDirty()

    return true, isBill and "uwm_result_billSent" or "uwm_result_orderSent"
end

function UWMManager:acceptInvoice(farmId, invoice, reserve, targets)
    if invoice.state ~= STATE.PENDING then
        return false, "uwm_error_notPending"
    end
    if farmId == invoice.creatorFarmId then
        return false, "uwm_error_ownInvoice"
    end

    -- the buyer's choices only stick when the accept goes through
    local oldReserve, oldTargets = invoice.reserve, invoice.targets
    if farmId == invoice.buyerFarmId then
        invoice.reserve = reserve == true and not invoice:getIsElectricity()
        if targets ~= nil then
            invoice.targets = targets
        end
    end

    local ok, key = true, nil
    if invoice:getIsElectricity() and #UWMStock.resolveTargets(invoice) == 0 then
        ok, key = false, "uwm_error_noTargets"
    else
        ok, key = self:runPeriod(invoice)
    end
    if not ok then
        invoice.reserve, invoice.targets = oldReserve, oldTargets
        return false, key
    end

    if invoice.state == STATE.PENDING then
        invoice.state = STATE.ACTIVE
    end
    invoice.nextPeriodDay = g_currentMission.environment.currentMonotonicDay + invoice.repeatDays

    self:notify(invoice.creatorFarmId, "uwm_notify_accepted", invoice)
    if self:finishIfDone(invoice) then
        -- one-off electricity is delivered right away: the receipt says how much really arrived
        self:sendReceipt(invoice)
    end
    self:setDirty()

    return true, "uwm_result_accepted"
end

function UWMManager:declineInvoice(farmId, invoice)
    if invoice.state ~= STATE.PENDING or farmId == invoice.creatorFarmId then
        return false, "uwm_error_notPending"
    end
    self:finish(invoice, STATE.DECLINED)
    self:notify(invoice.creatorFarmId, "uwm_notify_declined", invoice)
    self:setDirty()
    return true, "uwm_result_declined"
end

function UWMManager:cancelInvoice(farmId, invoice)
    if invoice.state == STATE.PENDING then
        if farmId ~= invoice.creatorFarmId then
            return false, "uwm_error_ownInvoiceOnly"
        end
        self:finish(invoice, STATE.CANCELLED)
        self:notify(invoice:getOtherFarmId(farmId), "uwm_notify_withdrawn", invoice)
    elseif invoice.state == STATE.ACTIVE then
        self:refundOwed(invoice)
        self:finish(invoice, STATE.CANCELLED)
        self:notify(invoice:getOtherFarmId(farmId), "uwm_notify_ended", invoice)
        self:sendReceipt(invoice)
    else
        return false, "uwm_error_finished"
    end
    self:setDirty()
    return true, "uwm_result_cancelled"
end

-- a finished invoice leaves this farm's history; once both farms deleted it, it's gone
function UWMManager:hideFor(farmId, invoice)
    if farmId == invoice.sellerFarmId then
        invoice.hiddenBySeller = true
    end
    if farmId == invoice.buyerFarmId then
        invoice.hiddenByBuyer = true
    end
    if invoice.hiddenBySeller and invoice.hiddenByBuyer then
        self:removeInvoice(invoice)
    end
end

function UWMManager:deleteInvoice(farmId, invoice)
    if not invoice:getIsFinished() then
        return false, "uwm_error_notFinished"
    end
    self:hideFor(farmId, invoice)
    self:setDirty()
    return true, "uwm_result_deleted"
end

function UWMManager:clearHistory(farmId)
    local finished = {}
    for _, invoice in ipairs(self.invoices) do
        if invoice:getIsFinished() and (invoice.sellerFarmId == farmId or invoice.buyerFarmId == farmId)
            and not invoice:getIsHiddenFor(farmId) then
            table.insert(finished, invoice)
        end
    end
    for _, invoice in ipairs(finished) do
        self:hideFor(farmId, invoice)
    end
    self:setDirty()
    return true, "uwm_result_historyCleared"
end

-- money back for paid liters the buyer never collected
function UWMManager:refundOwed(invoice)
    if invoice.owedLiters > UWMManager.EPSILON then
        local refund = invoice:getPrice(invoice.owedLiters)
        self:transferMoney(invoice, -refund)
        invoice.totalRefund = invoice.totalRefund + refund
        invoice.refundedLiters = invoice.refundedLiters + invoice.owedLiters
        invoice.owedLiters = 0
    end
end

-- one delivery period: pay for the liters (manure / slurry) or deliver and pay for electricity
-- returns ok, l10n key of the problem, liters delivered / paid for, money paid
function UWMManager:runPeriod(invoice)
    local liters
    if invoice:getIsElectricity() then
        liters = invoice.amountMode == UWMInvoice.AMOUNT.FIXED and invoice.liters or math.huge
        liters = math.min(liters, UWMStock.getAvailable(invoice.sellerFarmId, invoice.fillTypeIndex, invoice))
        if liters <= UWMManager.EPSILON then
            return false, "uwm_error_noStock"
        end
        liters = math.min(liters, UWMStock.getElectricitySpace(invoice))
        if liters <= UWMManager.EPSILON then
            return false, "uwm_error_noSpace"
        end
        if invoice.pricePer1000 > 0 then
            liters = math.min(liters, UWMManager.getFarmBalance(invoice.buyerFarmId) / invoice.pricePer1000 * 1000)
        end
        if liters <= UWMManager.EPSILON then
            return false, "uwm_error_noMoney"
        end

        local taken = UWMStock.take(invoice.sellerFarmId, invoice.fillTypeIndex, liters)
        local added = UWMStock.putElectricity(invoice, taken)
        if added < taken - UWMManager.EPSILON then
            -- space changed while moving: give the rest back to the seller's first source
            UWMStock.giveBack(invoice.sellerFarmId, invoice.fillTypeIndex, taken - added)
        end
        self:transferMoney(invoice, invoice:getPrice(added))
        invoice.totalLiters = invoice.totalLiters + added
        invoice.statusKey = ""
        return true, nil, added, invoice:getPrice(added)
    else
        if invoice.amountMode == UWMInvoice.AMOUNT.ALL then
            -- liters already paid for and still waiting to be collected are part of the stock: don't bill them twice
            liters = UWMStock.getAvailable(invoice.sellerFarmId, invoice.fillTypeIndex, invoice) - invoice.owedLiters
            if liters <= UWMManager.EPSILON then
                return false, "uwm_error_noStock"
            end
        else
            liters = invoice.liters
        end

        local price = invoice:getPrice(liters)
        if price > UWMManager.getFarmBalance(invoice.buyerFarmId) then
            return false, "uwm_error_noMoney"
        end
        self:transferMoney(invoice, price)
        invoice.owedLiters = invoice.owedLiters + liters
        invoice.statusKey = ""
        return true, nil, liters, price
    end
end

function UWMManager:finishIfDone(invoice)
    if invoice.state == STATE.ACTIVE and invoice.repeatDays == UWMInvoice.REPEAT_ONCE
        and (invoice:getIsElectricity() or invoice.owedLiters <= UWMManager.EPSILON) then
        invoice.owedLiters = 0
        self:finish(invoice, STATE.DONE)
        return true
    end
    return false
end

----------------------------------------------------------------------------------------------------------------
-- Collecting at the seller's stations / the pickup building (server)
----------------------------------------------------------------------------------------------------------------

-- invoice belongs to this buyer and fill type (and seller, when one is given)
local function isCollectFor(invoice, farmId, fillTypeIndex, sellerFarmId)
    return invoice.buyerFarmId == farmId and invoice.fillTypeIndex == fillTypeIndex
        and (sellerFarmId == nil or invoice.sellerFarmId == sellerFarmId)
end

-- the buyer farm's paid, uncollected liters of a fill type (only from sellerFarmId, when given)
function UWMManager:getCollectableLiters(farmId, fillTypeIndex, sellerFarmId)
    local total = 0
    for _, invoice in ipairs(self.invoices) do
        if invoice.state == STATE.ACTIVE and isCollectFor(invoice, farmId, fillTypeIndex, sellerFarmId) then
            total = total + math.min(invoice.owedLiters, UWMStock.getAvailable(invoice.sellerFarmId, fillTypeIndex, invoice))
        end
    end
    return total
end

-- takes up to `liters` from the sellers' stock for the buyer's paid invoices, oldest invoice first;
-- returns the liters taken (the caller puts them into the buyer's vehicle)
function UWMManager:collect(farmId, fillTypeIndex, liters, sellerFarmId)
    local collected = 0
    for _, invoice in ipairs(self.invoices) do
        if collected >= liters then
            break
        end
        if invoice.state == STATE.ACTIVE and isCollectFor(invoice, farmId, fillTypeIndex, sellerFarmId)
            and invoice.owedLiters > UWMManager.EPSILON then
            local want = math.min(liters - collected, invoice.owedLiters,
                UWMStock.getAvailable(invoice.sellerFarmId, fillTypeIndex, invoice))
            if want > 0 then
                local taken = UWMStock.take(invoice.sellerFarmId, fillTypeIndex, want)
                invoice.owedLiters = math.max(invoice.owedLiters - taken, 0)
                invoice.totalLiters = invoice.totalLiters + taken
                collected = collected + taken
                if self:finishIfDone(invoice) then
                    self:notify(invoice.sellerFarmId, "uwm_notify_collected", invoice)
                    self:sendReceipt(invoice)
                end
                self.syncDirty = true
            end
        end
    end
    return collected
end

-- puts liters back (the vehicle took less than was drawn), into the buyer's newest invoice of that type
function UWMManager:returnCollected(farmId, fillTypeIndex, liters, sellerFarmId)
    for i = #self.invoices, 1, -1 do
        local invoice = self.invoices[i]
        if isCollectFor(invoice, farmId, fillTypeIndex, sellerFarmId) and invoice.totalLiters > 0 then
            local back = math.min(liters, invoice.totalLiters)
            UWMStock.giveBack(invoice.sellerFarmId, fillTypeIndex, back)
            invoice.totalLiters = invoice.totalLiters - back
            invoice.owedLiters = invoice.owedLiters + back
            if invoice.state == STATE.DONE then
                invoice.state = STATE.ACTIVE
                invoice.finishedDay = 0
            end
            self.syncDirty = true
            return
        end
    end
end

----------------------------------------------------------------------------------------------------------------
-- Contracts (server)
----------------------------------------------------------------------------------------------------------------

function UWMManager:onDayChanged()
    if not self.isServer then
        return
    end
    local today = g_currentMission.environment.currentMonotonicDay
    for _, invoice in ipairs(self.invoices) do
        if invoice.state == STATE.ACTIVE and invoice.repeatDays > 0 and today >= invoice.nextPeriodDay then
            invoice.nextPeriodDay = today + invoice.repeatDays
            local ok, key, liters, money = self:runPeriod(invoice)
            if ok then
                local UWM = UtilitiesWasteManagement
                local periodKey = invoice:getIsElectricity() and "uwm_receipt_periodDelivered" or "uwm_receipt_periodPaid"
                local line = string.format(UWM.getText(periodKey), UWM.formatAmount(invoice.fillTypeIndex, liters), UWM.formatMoney(money))
                self:notify(invoice.buyerFarmId, "uwm_notify_contractRun", invoice, line)
                self:notify(invoice.sellerFarmId, "uwm_notify_contractRun", invoice, line)
            else
                invoice.statusKey = key
                self:notify(invoice.buyerFarmId, "uwm_notify_contractFailed", invoice)
                self:notify(invoice.sellerFarmId, "uwm_notify_contractFailed", invoice)
            end
            self:setDirty()
        end
    end
end

----------------------------------------------------------------------------------------------------------------
-- Sync
----------------------------------------------------------------------------------------------------------------

function UWMManager:setDirty()
    self.syncDirty = true
    self.syncTimer = 0
end

function UWMManager:update(dt)
    if self.isServer and self.syncDirty then
        self.syncTimer = self.syncTimer - dt
        if self.syncTimer <= 0 then
            self.syncDirty = false
            self.syncTimer = UWMManager.SYNC_INTERVAL
            self:pruneHistory()
            if g_server ~= nil then
                g_server:broadcastEvent(UWMSyncEvent.new(self), false)
            end
            self:raiseChanged()
        end
    end
end

-- keeps the newest MAX_HISTORY finished invoices
function UWMManager:pruneHistory()
    local finished = 0
    for i = #self.invoices, 1, -1 do
        local invoice = self.invoices[i]
        if invoice:getIsFinished() then
            finished = finished + 1
            if finished > UWMManager.MAX_HISTORY then
                table.remove(self.invoices, i)
                self.invoiceById[invoice.id] = nil
            end
        end
    end
end

function UWMManager:writeStream(streamId)
    streamWriteInt32(streamId, self.nextId)
    streamWriteInt32(streamId, #self.invoices)
    for _, invoice in ipairs(self.invoices) do
        invoice:writeStream(streamId)
    end
end

function UWMManager:readStream(streamId)
    self.invoices = {}
    self.invoiceById = {}
    self.nextId = streamReadInt32(streamId)
    for _ = 1, streamReadInt32(streamId) do
        local invoice = UWMInvoice.new()
        invoice:readStream(streamId)
        self:addInvoice(invoice)
    end
    self:raiseChanged()
end

----------------------------------------------------------------------------------------------------------------
-- Savegame
----------------------------------------------------------------------------------------------------------------

function UWMManager:saveToXMLFile(filename)
    local xmlFile = XMLFile.create("uwmSave", filename, "utilitiesWasteManagement")
    if xmlFile == nil then
        Logging.warning("%s could not write %s", UtilitiesWasteManagement.TAG, filename)
        return
    end
    self:pruneHistory()
    xmlFile:setInt("utilitiesWasteManagement#nextId", self.nextId)
    for i, invoice in ipairs(self.invoices) do
        invoice:saveToXMLFile(xmlFile, string.format("utilitiesWasteManagement.invoices.invoice(%d)", i - 1))
    end
    xmlFile:save()
    xmlFile:delete()
end

function UWMManager:loadFromXMLFile(filename)
    local xmlFile = XMLFile.loadIfExists("uwmSave", filename)
    if xmlFile == nil then
        return
    end
    xmlFile:iterate("utilitiesWasteManagement.invoices.invoice", function(_, key)
        local invoice = UWMInvoice.new()
        if invoice:loadFromXMLFile(xmlFile, key) then
            self:addInvoice(invoice)
        else
            Logging.warning("%s skipped invoice %s (unknown fill type or id)", UtilitiesWasteManagement.TAG, key)
        end
    end)
    self.nextId = math.max(self.nextId, xmlFile:getInt("utilitiesWasteManagement#nextId", 1))
    xmlFile:delete()
    print(string.format("%s loaded %d invoice(s)", UtilitiesWasteManagement.TAG, #self.invoices))
end
