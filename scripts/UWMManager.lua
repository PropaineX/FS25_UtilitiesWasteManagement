-- Utilities & Waste Management: all invoices, the depot membership, and everything that changes them. Changes run
-- on the server only; clients get a copy through UWMSyncEvent.
-- Depot rules (user's, 2026-10-23): no depot on the map = no invoices at all. Every farm that doesn't own a depot
-- gets a membership offer (answered by its farm manager); members and depot owners share the depots' upkeep
-- equally, taken automatically every day. A member who can't pay builds up arrears; two months in a row ending
-- with arrears = suspended until the arrears are paid. Farms that declined or are suspended can't send or accept
-- invoices (invoices already paid can still be collected or ended).
-- Standing orders (UWMListing, user's idea 2026-10-24): an offer or a wanted order open to every farm; each deal on
-- it becomes a normal paid invoice. An offer holds the poster's stock, a wanted order holds the poster's money.
-- Author: PropaineX

UWMManager = {}
local UWMManager_mt = Class(UWMManager)

UWMManager.ACTION = {
    CREATE = 1,
    ACCEPT = 2,
    DECLINE = 3,
    CANCEL = 4,     -- pending: the sender takes it back; active: either farm ends it, unpaid-out liters refunded
    DELETE = 5,     -- a finished invoice leaves this farm's history (gone for good once both farms deleted it)
    CLEAR_HISTORY = 6, -- DELETE for every finished invoice of this farm
    JOIN_DEPOT = 7,     -- answer Yes to the membership offer
    DECLINE_DEPOT = 8,  -- answer No
    REQUEST_DEPOT = 9,  -- a farm that said No asks again: it gets a new offer
    PAY_ARREARS = 10,   -- pay the depot what the farm owes, lifts a suspension
    SET_MULTIPLE_DEPOTS = 11, -- server admin: allow more than one depot on the map (data.flag)
    LEAVE_DEPOT = 12,   -- a member leaves; it can't ask to rejoin for REJOIN_WAIT_MONTHS
    POST_LISTING = 13,      -- put a standing order on the board (data.listing)
    TRADE_LISTING = 14,     -- buy from an offer / sell to a wanted order (data.listingId, data.liters)
    WITHDRAW_LISTING = 15,  -- the poster takes it off the board; held stock is freed, held money comes back
    DELETE_LISTING = 16     -- a finished standing order leaves the poster's history
}

-- a farm's depot membership (farms that own a depot take part without one)
UWMManager.MEMBER = {
    OFFERED = 1,
    MEMBER = 2,
    DECLINED = 3
}
UWMManager.MEMBERSHIP_CHECK_INTERVAL = 2000  -- ms: offers to new farms / after a depot was placed
UWMManager.REJOIN_WAIT_MONTHS = 6            -- after leaving (user's rule, 2026-10-24)

UWMManager.MAX_HISTORY = 100
UWMManager.SYNC_INTERVAL = 1000  -- ms between syncs while liters are being collected
UWMManager.EPSILON = 0.01

local STATE = UWMInvoice.STATE
local LSTATE = UWMListing.STATE

function UWMManager.new(isServer)
    local self = setmetatable({}, UWMManager_mt)

    self.isServer = isServer
    self.invoices = {}          -- in creation order
    self.invoiceById = {}
    self.nextId = 1
    self.listings = {}          -- standing orders, in posting order
    self.listingById = {}
    self.nextListingId = 1
    self.syncDirty = false
    self.syncTimer = 0
    self.listeners = {}

    self.members = {}           -- farmId -> {state, arrears, missedMonths, suspended}
    self.allowMultipleDepots = false
    self.membershipTimer = 0

    return self
end

function UWMManager:delete()
    self.invoices = {}
    self.invoiceById = {}
    self.listings = {}
    self.listingById = {}
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

function UWMManager:getListing(id)
    return self.listingById[id]
end

function UWMManager:getListings()
    return self.listings
end

function UWMManager:addListing(listing)
    table.insert(self.listings, listing)
    self.listingById[listing.id] = listing
    self.nextListingId = math.max(self.nextListingId, listing.id + 1)
end

function UWMManager:removeListing(listing)
    for i, other in ipairs(self.listings) do
        if other == listing then
            table.remove(self.listings, i)
            break
        end
    end
    self.listingById[listing.id] = nil
end

-- liters of a seller's stock held for buyers who ticked Reserve, and for the seller's open standing offers
function UWMManager:getReservedLiters(farmId, fillTypeIndex, exceptInvoice)
    local reserved = 0
    for _, invoice in ipairs(self.invoices) do
        if invoice ~= exceptInvoice and invoice.sellerFarmId == farmId and invoice.fillTypeIndex == fillTypeIndex then
            reserved = reserved + invoice:getReservedLiters()
        end
    end
    for _, listing in ipairs(self.listings) do
        if listing.farmId == farmId and listing.fillTypeIndex == fillTypeIndex then
            reserved = reserved + listing:getReservedLiters()
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

-- buyer -> seller (negative amount = refund seller -> buyer). A prepaid invoice (from a wanted order) pays the
-- seller out of the money the buyer already handed over when posting the order.
function UWMManager:transferMoney(invoice, amount)
    if math.abs(amount) < 0.005 then
        return
    end
    local mission = g_currentMission
    if not (invoice.prepaid and amount > 0) then
        mission:addMoney(-amount, invoice.buyerFarmId, amount > 0 and MoneyType.UWM_EXPENSE or MoneyType.UWM_INCOME, true)
    end
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

    if action == UWMManager.ACTION.SET_MULTIPLE_DEPOTS then
        if not UWMManager.getIsAdmin(userId) then
            return false, "uwm_error_notAdmin"
        end
        self.allowMultipleDepots = data.flag == true
        self:setDirty()
        return true, self.allowMultipleDepots and "uwm_result_multipleOn" or "uwm_result_multipleOff"
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
    elseif action == UWMManager.ACTION.POST_LISTING then
        return self:postListing(farmId, data.listing, data.targets)
    elseif action == UWMManager.ACTION.TRADE_LISTING or action == UWMManager.ACTION.WITHDRAW_LISTING
        or action == UWMManager.ACTION.DELETE_LISTING then
        local listing = self:getListing(data.listingId or 0)
        if listing == nil then
            return false, "uwm_error_unknownListing"
        end
        if action == UWMManager.ACTION.TRADE_LISTING then
            return self:tradeListing(farmId, listing, data.liters, data.targets)
        elseif action == UWMManager.ACTION.WITHDRAW_LISTING then
            return self:withdrawListing(farmId, listing)
        end
        return self:deleteListing(farmId, listing)
    elseif action == UWMManager.ACTION.CLEAR_HISTORY then
        return self:clearHistory(farmId)
    elseif action == UWMManager.ACTION.JOIN_DEPOT or action == UWMManager.ACTION.DECLINE_DEPOT then
        return self:answerMembership(farmId, action == UWMManager.ACTION.JOIN_DEPOT)
    elseif action == UWMManager.ACTION.REQUEST_DEPOT then
        return self:requestMembership(farmId)
    elseif action == UWMManager.ACTION.PAY_ARREARS then
        return self:payArrears(farmId)
    elseif action == UWMManager.ACTION.LEAVE_DEPOT then
        return self:leaveMembership(farmId)
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
    local canTrade, tradeKey = self:getCanTrade(farmId, otherFarmId)
    if not canTrade then
        return false, tradeKey
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
    local canTrade, tradeKey = self:getCanTrade(farmId, invoice:getOtherFarmId(farmId))
    if not canTrade then
        return false, tradeKey
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
    for i = #self.listings, 1, -1 do
        local listing = self.listings[i]
        if listing.farmId == farmId and not listing:getIsOpen() then
            self:removeListing(listing)
        end
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
        if invoice.pricePer1000 > 0 and not invoice.prepaid then
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
        if not invoice.prepaid and price > UWMManager.getFarmBalance(invoice.buyerFarmId) then
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
-- Standing orders (server)
----------------------------------------------------------------------------------------------------------------

-- "50,000 l for $500"
local function getDealText(fillTypeIndex, liters, money)
    local UWM = UtilitiesWasteManagement
    return string.format(UWM.getText("uwm_receipt_deal"), UWM.formatAmount(fillTypeIndex, liters), UWM.formatMoney(money))
end

function UWMManager:finishListing(listing, state)
    listing.state = state
    listing.finishedDay = g_currentMission.environment.currentMonotonicDay
end

-- data: UWMListing with kind, fillTypeIndex, liters, pricePer1000; targets: WANTED electricity, the poster's productions
function UWMManager:postListing(farmId, data, targets)
    if data == nil or UtilitiesWasteManagement.getGood(data.fillTypeIndex) == nil then
        return false, "uwm_error_badGood"
    end
    if data.kind ~= UWMListing.KIND.OFFER and data.kind ~= UWMListing.KIND.WANTED then
        return false, "uwm_error_unknownAction"
    end
    if not (data.liters > 0) then
        return false, "uwm_error_badAmount"
    end
    if not (data.pricePer1000 >= 0) then
        return false, "uwm_error_badPrice"
    end
    local canTrade, tradeKey = self:getCanTrade(farmId, nil)
    if not canTrade then
        return false, tradeKey
    end

    local listing = UWMListing.new()
    listing.id = self.nextListingId
    listing.farmId = farmId
    listing.kind = data.kind
    listing.fillTypeIndex = data.fillTypeIndex
    listing.liters = data.liters
    listing.remaining = data.liters
    listing.pricePer1000 = data.pricePer1000
    listing.createdDay = g_currentMission.environment.currentMonotonicDay

    if listing:getIsOffer() then
        -- the whole amount must be free in stock now: from here on it is held for the buyers
        if UWMStock.getAvailable(farmId, listing.fillTypeIndex, nil) < listing.liters - UWMManager.EPSILON then
            return false, "uwm_error_listingNoStock"
        end
    else
        if listing:getIsElectricity() then
            listing.targets = targets or {}
            if #UWMStock.resolveTargets({targets = listing.targets, buyerFarmId = farmId}) == 0 then
                return false, "uwm_error_noTargets"
            end
        end
        -- the money for the whole order is taken now and held; sellers are paid from it
        local held = listing:getPrice(listing.liters)
        if held > UWMManager.getFarmBalance(farmId) then
            return false, "uwm_error_listingNoMoney"
        end
        if held >= 0.005 then
            g_currentMission:addMoney(-held, farmId, MoneyType.UWM_EXPENSE, true)
        end
    end

    self:addListing(listing)

    local key = listing:getIsOffer() and "uwm_notify_listingOffer" or "uwm_notify_listingWanted"
    local UWM = UtilitiesWasteManagement
    local detail = string.format(UWM.getText(listing:getIsElectricity() and "uwm_receipt_atPriceKWh" or "uwm_receipt_atPrice"),
        UWM.formatAmount(listing.fillTypeIndex, listing.liters), UWM.formatMoney(listing.pricePer1000))
    for _, farm in pairs(g_farmManager:getFarms()) do
        if farm.farmId ~= farmId and UWMManager.getIsTradingFarm(farm.farmId) then
            UWMNotifyEvent.sendEvent(farm.farmId, key, UWMManager.getFarmName(farmId), listing.fillTypeIndex, detail)
        end
    end
    self:setDirty()

    return true, "uwm_result_listingPosted"
end

-- another farm buys `liters` from an offer, or sells `liters` to a wanted order. The deal is a normal invoice,
-- already paid: slurry / manure reserved for the buyer to collect at the depot, electricity delivered now.
-- targets: OFFER electricity, the buyer's productions
function UWMManager:tradeListing(farmId, listing, liters, targets)
    if not listing:getIsOpen() then
        return false, "uwm_error_listingClosed"
    end
    if farmId == listing.farmId then
        return false, "uwm_error_ownListing"
    end
    local canTrade, tradeKey = self:getCanTrade(farmId, listing.farmId)
    if not canTrade then
        return false, tradeKey
    end
    if liters == nil or not (liters > 0) then
        return false, "uwm_error_badAmount"
    end
    if liters > listing.remaining + UWMManager.EPSILON then
        return false, "uwm_error_listingTooMuch"
    end
    liters = math.min(liters, listing.remaining)

    local isOffer = listing:getIsOffer()
    local invoice = UWMInvoice.new()
    invoice.id = self.nextId
    invoice.creatorFarmId = listing.farmId
    invoice.sellerFarmId = isOffer and listing.farmId or farmId
    invoice.buyerFarmId = isOffer and farmId or listing.farmId
    invoice.fillTypeIndex = listing.fillTypeIndex
    invoice.amountMode = UWMInvoice.AMOUNT.FIXED
    invoice.liters = liters
    invoice.pricePer1000 = listing.pricePer1000
    invoice.repeatDays = UWMInvoice.REPEAT_ONCE
    invoice.createdDay = g_currentMission.environment.currentMonotonicDay
    invoice.reserve = not invoice:getIsElectricity()
    invoice.targets = isOffer and (targets or {}) or listing.targets
    invoice.listingId = listing.id
    invoice.prepaid = not isOffer
    invoice.state = STATE.ACTIVE

    if invoice:getIsElectricity() and #UWMStock.resolveTargets(invoice) == 0 then
        return false, "uwm_error_noTargets"
    end

    -- what the offer held for this deal moves over to the new invoice
    local before = listing.remaining
    listing.remaining = before - liters
    if UWMStock.getAvailable(invoice.sellerFarmId, invoice.fillTypeIndex, invoice) < liters - UWMManager.EPSILON then
        listing.remaining = before
        return false, isOffer and "uwm_error_noStock" or "uwm_error_listingNoStock"
    end
    local ok, key, moved, money = self:runPeriod(invoice)
    if not ok then
        listing.remaining = before
        return false, key
    end
    -- electricity: only what fitted into the buyer's productions counts
    listing.remaining = math.max(before - moved, 0)
    listing.trades = listing.trades + 1
    listing.tradedLiters = listing.tradedLiters + moved
    listing.totalMoney = listing.totalMoney + money

    self:addInvoice(invoice)
    if self:finishIfDone(invoice) then
        self:sendReceipt(invoice)
    end

    local farmName = UWMManager.getFarmName(farmId)
    UWMNotifyEvent.sendEvent(listing.farmId, isOffer and "uwm_notify_listingBought" or "uwm_notify_listingSold", farmName,
        listing.fillTypeIndex, getDealText(listing.fillTypeIndex, moved, money))
    if listing.remaining <= UWMManager.EPSILON then
        listing.remaining = 0
        self:finishListing(listing, LSTATE.DONE)
        UWMNotifyEvent.sendEvent(listing.farmId, "uwm_notify_listingComplete", farmName, listing.fillTypeIndex,
            getDealText(listing.fillTypeIndex, listing.tradedLiters, listing.totalMoney))
    end
    self:setDirty()

    return true, isOffer and "uwm_result_listingBought" or "uwm_result_listingSold"
end

function UWMManager:withdrawListing(farmId, listing)
    if farmId ~= listing.farmId then
        return false, "uwm_error_notYourListing"
    end
    if not listing:getIsOpen() then
        return false, "uwm_error_listingClosed"
    end
    local held = listing:getHeldMoney()
    if held >= 0.005 then
        g_currentMission:addMoney(held, farmId, MoneyType.UWM_INCOME, true)
    end
    self:finishListing(listing, LSTATE.CANCELLED)
    self:setDirty()
    return true, "uwm_result_listingWithdrawn"
end

function UWMManager:deleteListing(farmId, listing)
    if farmId ~= listing.farmId then
        return false, "uwm_error_notYourListing"
    end
    if listing:getIsOpen() then
        return false, "uwm_error_notFinished"
    end
    self:removeListing(listing)
    self:setDirty()
    return true, "uwm_result_listingDeleted"
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
    self:chargeDepotShares()
    local today = g_currentMission.environment.currentMonotonicDay
    for _, invoice in ipairs(self.invoices) do
        if invoice.state == STATE.ACTIVE and invoice.repeatDays > 0 and today >= invoice.nextPeriodDay then
            invoice.nextPeriodDay = today + invoice.repeatDays
            -- no depot, or a farm not (or no longer) allowed to trade: this period is skipped
            local ok, key = self:getCanTrade(invoice.sellerFarmId, invoice.buyerFarmId)
            local liters, money
            if ok then
                ok, key, liters, money = self:runPeriod(invoice)
            end
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
-- Depot: lock, membership, shared upkeep (server decides; the state is synced to clients for the page)
----------------------------------------------------------------------------------------------------------------

function UWMManager.newMember(state)
    -- rejoinWait: in-game months before a farm that left may ask to join again
    return {state = state, arrears = 0, missedMonths = 0, suspended = false, rejoinWait = 0}
end

-- the server admin (master user); in singleplayer the player
function UWMManager.getIsAdmin(userId)
    if not g_currentMission.missionDynamicInfo.isMultiplayer then
        return true
    end
    local user = g_currentMission.userManager:getUserByUserId(userId)
    return user ~= nil and user.getIsMasterUser ~= nil and user:getIsMasterUser()
end

function UWMManager:getMemberFarmIds()
    local farmIds = {}
    for farmId in pairs(self.members) do
        table.insert(farmIds, farmId)
    end
    table.sort(farmIds)
    return farmIds
end

function UWMManager.getDepots()
    if UWMDepot == nil then
        return {}
    end
    return UWMDepot.getDepots()
end

function UWMManager:getHasDepot()
    return #UWMManager.getDepots() > 0
end

-- farms that own a depot: farmId -> its depots' daily upkeep; plus the total
function UWMManager:getDepotUpkeep()
    local owners, total = {}, 0
    for _, depot in ipairs(UWMManager.getDepots()) do
        local farmId = depot:getOwnerFarmId()
        if UWMManager.getIsTradingFarm(farmId) then
            local upkeep = depot.getDailyUpkeep ~= nil and depot:getDailyUpkeep() or 0
            owners[farmId] = (owners[farmId] or 0) + upkeep
            total = total + upkeep
        end
    end
    return owners, total
end

function UWMManager:getOwnsDepot(farmId)
    local owners = self:getDepotUpkeep()
    return owners[farmId] ~= nil
end

function UWMManager:getMember(farmId)
    return self.members[farmId]
end

-- a depot owner, or a farm that joined
function UWMManager:getIsParticipant(farmId)
    if self:getOwnsDepot(farmId) then
        return true
    end
    local member = self.members[farmId]
    return member ~= nil and member.state == UWMManager.MEMBER.MEMBER
end

function UWMManager:getIsSuspended(farmId)
    local member = self.members[farmId]
    return member ~= nil and member.suspended and not self:getOwnsDepot(farmId)
end

-- may farmId trade with otherFarmId? returns ok, l10n key of the reason
function UWMManager:getCanTrade(farmId, otherFarmId)
    if not self:getHasDepot() then
        return false, "uwm_error_noDepot"
    end
    if not self:getIsParticipant(farmId) then
        return false, "uwm_error_notMember"
    end
    if self:getIsSuspended(farmId) then
        return false, "uwm_error_suspended"
    end
    if otherFarmId ~= nil and (not self:getIsParticipant(otherFarmId) or self:getIsSuspended(otherFarmId)) then
        return false, "uwm_error_otherNotMember"
    end
    return true, nil
end

-- owners + members who pay: every participant pays the same share of the total upkeep
function UWMManager:getParticipantCount()
    local owners = self:getDepotUpkeep()
    local count = 0
    for _ in pairs(owners) do
        count = count + 1
    end
    for farmId, member in pairs(self.members) do
        if member.state == UWMManager.MEMBER.MEMBER and owners[farmId] == nil and UWMManager.getIsTradingFarm(farmId) then
            count = count + 1
        end
    end
    return count
end

-- a participant's daily share now; for a farm not taking part: what it would be after joining
function UWMManager:getDailyShare(farmId)
    local _, total = self:getDepotUpkeep()
    local count = self:getParticipantCount()
    if not self:getIsParticipant(farmId) then
        count = count + 1
    end
    if count == 0 then
        return 0
    end
    return total / count
end

function UWMManager:getDepotOwnerNames()
    local owners = self:getDepotUpkeep()
    local farmIds = {}
    for farmId in pairs(owners) do
        table.insert(farmIds, farmId)
    end
    table.sort(farmIds)
    local names = {}
    for _, farmId in ipairs(farmIds) do
        table.insert(names, UWMManager.getFarmName(farmId))
    end
    return table.concat(names, ", ")
end

-- message about the depot: first %s = the depot owner(s), second %s = detail (an amount)
function UWMManager:notifyDepot(farmId, key, detail)
    if farmId == nil or farmId == FarmManager.SPECTATOR_FARM_ID then
        return
    end
    UWMNotifyEvent.sendEvent(farmId, key, self:getDepotOwnerNames(), FillType.UNKNOWN, detail)
end

-- a depot was placed or removed (server and clients)
function UWMManager:onDepotsChanged()
    if self.isServer then
        self.membershipTimer = 0
        self:setDirty()
    else
        self:raiseChanged()
    end
end

-- server: every farm without a depot and without an answer yet gets the offer; farms that are gone are dropped
function UWMManager:updateMemberships()
    local changed = false
    if self:getHasDepot() then
        for _, farm in pairs(g_farmManager:getFarms()) do
            local farmId = farm.farmId
            if UWMManager.getIsTradingFarm(farmId) and self.members[farmId] == nil and not self:getOwnsDepot(farmId) then
                self.members[farmId] = UWMManager.newMember(UWMManager.MEMBER.OFFERED)
                changed = true
                self:notifyDepot(farmId, "uwm_notify_depotOffer", UtilitiesWasteManagement.formatMoney(self:getDailyShare(farmId)))
            end
        end
    end
    for _, farmId in ipairs(self:getMemberFarmIds()) do
        if g_farmManager:getFarmById(farmId) == nil then
            self.members[farmId] = nil
            changed = true
        end
    end
    if changed then
        self:setDirty()
    end
end

function UWMManager:answerMembership(farmId, join)
    local member = self.members[farmId]
    if member == nil or member.state ~= UWMManager.MEMBER.OFFERED then
        return false, "uwm_error_noOffer"
    end
    if not self:getHasDepot() then
        return false, "uwm_error_noDepot"
    end
    member.state = join and UWMManager.MEMBER.MEMBER or UWMManager.MEMBER.DECLINED
    if join then
        for ownerFarmId in pairs((self:getDepotUpkeep())) do
            self:notifyDepot(ownerFarmId, "uwm_notify_depotJoined", UWMManager.getFarmName(farmId))
        end
    end
    self:setDirty()
    return true, join and "uwm_result_joined" or "uwm_result_notJoined"
end

-- a farm that said No asks to join: the depot sends it a new offer
function UWMManager:requestMembership(farmId)
    if not self:getHasDepot() then
        return false, "uwm_error_noDepot"
    end
    if self:getIsParticipant(farmId) then
        return false, "uwm_error_alreadyMember"
    end
    local member = self.members[farmId]
    if member ~= nil and member.state == UWMManager.MEMBER.OFFERED then
        return false, "uwm_error_offerOpen"
    end
    if member ~= nil and member.rejoinWait > 0 then
        return false, "uwm_error_rejoinWait"
    end
    member = member or UWMManager.newMember(UWMManager.MEMBER.OFFERED)
    member.state = UWMManager.MEMBER.OFFERED
    self.members[farmId] = member
    self:notifyDepot(farmId, "uwm_notify_depotOffer", UtilitiesWasteManagement.formatMoney(self:getDailyShare(farmId)))
    self:setDirty()
    return true, "uwm_result_requested"
end

-- member -> depot owners, split by each owner's part of the upkeep
function UWMManager:payDepotOwners(farmId, amount, owners, total)
    local mission = g_currentMission
    mission:addMoney(-amount, farmId, MoneyType.UWM_DEPOT_EXPENSE, true)
    for ownerFarmId, upkeep in pairs(owners) do
        local part = total > 0 and amount * upkeep / total or 0
        if part > 0 then
            mission:addMoney(part, ownerFarmId, MoneyType.UWM_DEPOT_INCOME, true)
        end
    end
end

-- a member leaves: no more shares from tomorrow, no invoices, and no new offer for REJOIN_WAIT_MONTHS months.
-- Any debt to the depot is taken from the farm's account right away, even into the negative (user's rule,
-- 2026-10-24). Invoices already paid can still be collected or ended.
function UWMManager:leaveMembership(farmId)
    local member = self.members[farmId]
    if member == nil or member.state ~= UWMManager.MEMBER.MEMBER or self:getOwnsDepot(farmId) then
        return false, "uwm_error_notMember"
    end
    if member.arrears >= 0.5 then
        local owners, total = self:getDepotUpkeep()
        if total > 0 then
            self:payDepotOwners(farmId, member.arrears, owners, total)
        end
        self:notifyDepot(farmId, "uwm_notify_depotDebtTaken", UtilitiesWasteManagement.formatMoney(member.arrears))
    end
    member.arrears = 0
    member.missedMonths = 0
    member.suspended = false
    member.state = UWMManager.MEMBER.DECLINED
    member.rejoinWait = UWMManager.REJOIN_WAIT_MONTHS
    for ownerFarmId in pairs((self:getDepotUpkeep())) do
        self:notifyDepot(ownerFarmId, "uwm_notify_depotLeft", UWMManager.getFarmName(farmId))
    end
    self:setDirty()
    return true, "uwm_result_left"
end

function UWMManager:payArrears(farmId)
    local member = self.members[farmId]
    if member == nil or member.arrears < 0.5 then
        return false, "uwm_error_noArrears"
    end
    if UWMManager.getFarmBalance(farmId) < member.arrears then
        return false, "uwm_error_noMoney"
    end
    local owners, total = self:getDepotUpkeep()
    if total > 0 then
        self:payDepotOwners(farmId, member.arrears, owners, total)
    end
    -- with no depot left there is nobody to pay: the debt is simply gone
    member.arrears = 0
    member.missedMonths = 0
    member.suspended = false
    self:setDirty()
    return true, "uwm_result_arrearsPaid"
end

-- server, every in-game day: each member pays the owners an equal share of the day's upkeep (the game charges the
-- owners the full upkeep), so everyone taking part pays the same; a member short of money builds up arrears
function UWMManager:chargeDepotShares()
    local owners, total = self:getDepotUpkeep()
    if total <= 0 then
        return
    end
    local share = total / math.max(self:getParticipantCount(), 1)
    for _, farmId in ipairs(self:getMemberFarmIds()) do
        local member = self.members[farmId]
        if member.state == UWMManager.MEMBER.MEMBER and owners[farmId] == nil and UWMManager.getIsTradingFarm(farmId) then
            if UWMManager.getFarmBalance(farmId) >= share then
                self:payDepotOwners(farmId, share, owners, total)
            else
                member.arrears = member.arrears + share
                self:notifyDepot(farmId, "uwm_notify_depotUnpaid", UtilitiesWasteManagement.formatMoney(member.arrears))
                self:setDirty()
            end
        end
    end
end

-- server, every in-game month: a member whose month ends with arrears missed a payment; two in a row = suspended
function UWMManager:onPeriodChanged()
    if not self.isServer then
        return
    end
    for _, farmId in ipairs(self:getMemberFarmIds()) do
        local member = self.members[farmId]
        if member.rejoinWait > 0 then
            member.rejoinWait = member.rejoinWait - 1
            self:setDirty()
        end
        if member.state == UWMManager.MEMBER.MEMBER then
            if member.arrears >= 0.5 then
                member.missedMonths = member.missedMonths + 1
                local owed = UtilitiesWasteManagement.formatMoney(member.arrears)
                if member.missedMonths >= 2 and not member.suspended then
                    member.suspended = true
                    self:notifyDepot(farmId, "uwm_notify_depotSuspended", owed)
                else
                    self:notifyDepot(farmId, "uwm_notify_depotArrears", owed)
                end
            else
                member.missedMonths = 0
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
    if self.isServer then
        self.membershipTimer = self.membershipTimer - dt
        if self.membershipTimer <= 0 then
            self.membershipTimer = UWMManager.MEMBERSHIP_CHECK_INTERVAL
            self:updateMemberships()
        end
    end
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

-- keeps the newest MAX_HISTORY finished invoices (and finished standing orders)
function UWMManager:pruneHistory()
    local finishedListings = 0
    for i = #self.listings, 1, -1 do
        local listing = self.listings[i]
        if not listing:getIsOpen() then
            finishedListings = finishedListings + 1
            if finishedListings > UWMManager.MAX_HISTORY then
                table.remove(self.listings, i)
                self.listingById[listing.id] = nil
            end
        end
    end
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
    streamWriteBool(streamId, self.allowMultipleDepots)
    local farmIds = self:getMemberFarmIds()
    streamWriteUInt8(streamId, #farmIds)
    for _, farmId in ipairs(farmIds) do
        local member = self.members[farmId]
        streamWriteUInt8(streamId, farmId)
        streamWriteUInt8(streamId, member.state)
        streamWriteFloat32(streamId, member.arrears)
        streamWriteUInt8(streamId, member.missedMonths)
        streamWriteBool(streamId, member.suspended)
        streamWriteUInt8(streamId, member.rejoinWait)
    end
    streamWriteInt32(streamId, self.nextListingId)
    streamWriteInt32(streamId, #self.listings)
    for _, listing in ipairs(self.listings) do
        listing:writeStream(streamId)
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
    self.allowMultipleDepots = streamReadBool(streamId)
    self.members = {}
    for _ = 1, streamReadUInt8(streamId) do
        local farmId = streamReadUInt8(streamId)
        local member = UWMManager.newMember(streamReadUInt8(streamId))
        member.arrears = streamReadFloat32(streamId)
        member.missedMonths = streamReadUInt8(streamId)
        member.suspended = streamReadBool(streamId)
        member.rejoinWait = streamReadUInt8(streamId)
        self.members[farmId] = member
    end
    self.listings = {}
    self.listingById = {}
    self.nextListingId = streamReadInt32(streamId)
    for _ = 1, streamReadInt32(streamId) do
        local listing = UWMListing.new()
        listing:readStream(streamId)
        self:addListing(listing)
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
    xmlFile:setBool("utilitiesWasteManagement.depot#allowMultiple", self.allowMultipleDepots)
    for i, farmId in ipairs(self:getMemberFarmIds()) do
        local member = self.members[farmId]
        local key = string.format("utilitiesWasteManagement.depot.member(%d)", i - 1)
        xmlFile:setInt(key .. "#farmId", farmId)
        xmlFile:setInt(key .. "#state", member.state)
        xmlFile:setFloat(key .. "#arrears", member.arrears)
        xmlFile:setInt(key .. "#missedMonths", member.missedMonths)
        xmlFile:setBool(key .. "#suspended", member.suspended)
        xmlFile:setInt(key .. "#rejoinWait", member.rejoinWait)
    end
    xmlFile:setInt("utilitiesWasteManagement.listings#nextId", self.nextListingId)
    for i, listing in ipairs(self.listings) do
        listing:saveToXMLFile(xmlFile, string.format("utilitiesWasteManagement.listings.listing(%d)", i - 1))
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
    self.allowMultipleDepots = xmlFile:getBool("utilitiesWasteManagement.depot#allowMultiple", false)
    xmlFile:iterate("utilitiesWasteManagement.depot.member", function(_, key)
        local farmId = xmlFile:getInt(key .. "#farmId", 0)
        local member = UWMManager.newMember(xmlFile:getInt(key .. "#state", UWMManager.MEMBER.OFFERED))
        member.arrears = xmlFile:getFloat(key .. "#arrears", 0)
        member.missedMonths = xmlFile:getInt(key .. "#missedMonths", 0)
        member.suspended = xmlFile:getBool(key .. "#suspended", false)
        member.rejoinWait = xmlFile:getInt(key .. "#rejoinWait", 0)
        if farmId > 0 then
            self.members[farmId] = member
        end
    end)
    xmlFile:iterate("utilitiesWasteManagement.listings.listing", function(_, key)
        local listing = UWMListing.new()
        if listing:loadFromXMLFile(xmlFile, key) then
            self:addListing(listing)
        else
            Logging.warning("%s skipped standing order %s (unknown fill type or id)", UtilitiesWasteManagement.TAG, key)
        end
    end)
    self.nextListingId = math.max(self.nextListingId, xmlFile:getInt("utilitiesWasteManagement.listings#nextId", 1))
    xmlFile:delete()
    print(string.format("%s loaded %d invoice(s), %d standing order(s)", UtilitiesWasteManagement.TAG, #self.invoices, #self.listings))
end
