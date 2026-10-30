-- Utilities & Waste Management: writing a new invoice and accepting one, step by step with the game's own
-- dialogs (choose from a list, type a number, yes/no).
-- New invoice: sell or buy -> other farm -> good -> amount -> price -> one-off / daily / weekly
--   -> buyer's choices (reserve, or the productions that get the electricity) -> confirm.
-- New standing order: offer (sell) or wanted (buy) -> good -> total amount -> price -> (wanted electricity: the
--   productions that get it) -> confirm. Trading on one: amount -> (buying electricity: productions) -> confirm.
-- The UWM CO-OP form (UWMOrderDialog) fills one invoice / standing order in one screen and joins these steps at
-- startForm; the old start functions (startNew / startListing) are no longer opened by the page.
-- Author: PropaineX

UWMWizard = {}
local UWMWizard_mt = Class(UWMWizard)

local function getText(key)
    return UtilitiesWasteManagement.getText(key)
end

-- electricity is counted in kWh: its texts have a "KWh" twin (uwm_wizard_liters -> uwm_wizard_litersKWh)
local function unitKey(invoice, key)
    if invoice.fillTypeIndex == FillType.ELECTRICCHARGE then
        return key .. "KWh"
    end
    return key
end

function UWMWizard.new()
    local self = setmetatable({}, UWMWizard_mt)
    self.farmId = UtilitiesWasteManagement.getLocalFarmId()
    self.invoice = UWMInvoice.new()
    self.targetPlaceables = {}  -- the buyer's chosen electricity productions (objects, see UWMRequestEvent)
    return self
end

function UWMWizard.startNew()
    local wizard = UWMWizard.new()
    wizard:askSide()
end

function UWMWizard.startListing()
    local wizard = UWMWizard.new()
    wizard:askListingKind()
end

-- buy from another farm's offer, or sell to its wanted order
function UWMWizard.startTrade(listing)
    local wizard = UWMWizard.new()
    wizard.tradeListing = listing
    wizard.invoice.fillTypeIndex = listing.fillTypeIndex
    wizard:askTradeAmount()
end

function UWMWizard.startAccept(invoice)
    local wizard = UWMWizard.new()
    wizard.acceptInvoice = invoice
    wizard.invoice.fillTypeIndex = invoice.fillTypeIndex
    if invoice.buyerFarmId == wizard.farmId then
        wizard:askBuyerOptions(function()
            wizard:confirmAccept()
        end)
    else
        wizard:confirmAccept()
    end
end

----------------------------------------------------------------------------------------------------------------
-- The UWM CO-OP form (gui/UWMOrderDialog): one item per invoice. The form gives the choices in one go, the rest
-- (buyer's reserve / electricity productions, confirm, request to the server) runs through the steps below.
-- form = {mode, otherFarmId, fillTypeIndex, amountAll, liters, pricePer1000, discountPercent, repeatDays}
-- (discount: invoices and requests only, not standing orders)
----------------------------------------------------------------------------------------------------------------

UWMWizard.FORM = {
    BILL = 1,       -- invoice a farm: we sell, they pay when they accept
    REQUEST = 2,    -- request an invoice: we buy, they approve
    WANTED = 3,     -- standing buy order on the market
    OFFER = 4       -- standing sell order on the market
}

function UWMWizard.getFormIsListing(mode)
    return mode == UWMWizard.FORM.WANTED or mode == UWMWizard.FORM.OFFER
end

-- nil = the form can be sent, else the l10n key of what's missing
function UWMWizard.getFormError(form)
    if not UWMWizard.getFormIsListing(form.mode) and form.otherFarmId == nil then
        return "uwm_error_formNoFarm"
    end
    if not UtilitiesWasteManagement.getIsTradable(form.fillTypeIndex) then
        return "uwm_error_formNoGood"
    end
    if form.isPallet and not UWMPallets.getIsPalletGood(form.fillTypeIndex) then
        return "uwm_error_formNoGood"
    end
    local allowAll = not UWMWizard.getFormIsListing(form.mode)
    if not (allowAll and form.amountAll) and (form.liters == nil or form.liters <= 0) then
        return "uwm_error_badAmount"
    end
    if form.pricePer1000 == nil or form.pricePer1000 < 0 then
        return "uwm_error_badPrice"
    end
    local discount = form.discountPercent or 0
    if not UWMWizard.getFormIsListing(form.mode) and not (discount >= 0 and discount < 100) then
        return "uwm_error_badDiscount"
    end
    return nil
end

function UWMWizard.startForm(form)
    local errorKey = UWMWizard.getFormError(form)
    if errorKey ~= nil then
        InfoDialog.show(getText(errorKey))
        return nil
    end

    local wizard = UWMWizard.new()
    local invoice = wizard.invoice
    invoice.fillTypeIndex = form.fillTypeIndex
    invoice.pricePer1000 = form.pricePer1000
    invoice.isPallet = form.isPallet == true
    invoice.palletSize = form.palletSize or UWMPallets.SIZES[1]

    if UWMWizard.getFormIsListing(form.mode) then
        wizard.listingKind = form.mode == UWMWizard.FORM.OFFER and UWMListing.KIND.OFFER or UWMListing.KIND.WANTED
        invoice.liters = form.liters
        if wizard.listingKind == UWMListing.KIND.WANTED and invoice.fillTypeIndex == FillType.ELECTRICCHARGE then
            wizard:askTargets(function()
                wizard:confirmListing()
            end)
        else
            wizard:confirmListing()
        end
        return wizard
    end

    wizard.isBill = form.mode == UWMWizard.FORM.BILL
    if wizard.isBill then
        invoice.sellerFarmId = wizard.farmId
        invoice.buyerFarmId = form.otherFarmId
    else
        invoice.sellerFarmId = form.otherFarmId
        invoice.buyerFarmId = wizard.farmId
    end
    if form.amountAll then
        invoice.amountMode = UWMInvoice.AMOUNT.ALL
    else
        invoice.amountMode = UWMInvoice.AMOUNT.FIXED
        invoice.liters = form.liters
    end
    invoice.repeatDays = form.repeatDays or UWMInvoice.REPEAT_ONCE
    invoice.discountPercent = form.discountPercent or 0

    if wizard.isBill then
        wizard:confirmNew()
    else
        wizard:askBuyerOptions(function()
            wizard:confirmNew()
        end)
    end
    return wizard
end

----------------------------------------------------------------------------------------------------------------
-- Steps
----------------------------------------------------------------------------------------------------------------

function UWMWizard:askSide()
    local options = {getText("uwm_wizard_sideSell"), getText("uwm_wizard_sideBuy")}
    OptionDialog.show(function(index)
        if index == 1 or index == 2 then
            self.isBill = index == 1
            self:askFarm()
        end
    end, getText("uwm_wizard_title"), getText("uwm_wizard_side"), options)
end

function UWMWizard:askListingKind()
    local kinds = {UWMListing.KIND.OFFER, UWMListing.KIND.WANTED}
    local options = {getText("uwm_wizard_kindOffer"), getText("uwm_wizard_kindWanted")}
    OptionDialog.show(function(index)
        if kinds[index] ~= nil then
            self.listingKind = kinds[index]
            self:askGood()
        end
    end, getText("uwm_wizard_listingTitle"), getText("uwm_wizard_kind"), options)
end

function UWMWizard:askFarm()
    local farms = {}
    local options = {}
    for _, farm in pairs(g_farmManager:getFarms()) do
        if farm.farmId ~= self.farmId and farm.farmId ~= FarmManager.SPECTATOR_FARM_ID then
            table.insert(farms, farm.farmId)
            table.insert(options, farm.name or tostring(farm.farmId))
        end
    end
    if #farms == 0 then
        InfoDialog.show(getText("uwm_wizard_noFarms"))
        return
    end
    OptionDialog.show(function(index)
        if farms[index] ~= nil then
            if self.isBill then
                self.invoice.sellerFarmId = self.farmId
                self.invoice.buyerFarmId = farms[index]
            else
                self.invoice.sellerFarmId = farms[index]
                self.invoice.buyerFarmId = self.farmId
            end
            self:askGood()
        end
    end, getText("uwm_wizard_title"), getText(self.isBill and "uwm_wizard_farmBuyer" or "uwm_wizard_farmSeller"), options)
end

function UWMWizard:askGood()
    local goods = UtilitiesWasteManagement.goods
    local options = {}
    for _, good in ipairs(goods) do
        table.insert(options, getText(good.textKey))
    end
    OptionDialog.show(function(index)
        if goods[index] ~= nil then
            self.invoice.fillTypeIndex = goods[index].fillTypeIndex
            if self.listingKind ~= nil then
                self:askLiters()
            else
                self:askAmountMode()
            end
        end
    end, getText("uwm_wizard_title"), getText("uwm_wizard_good"), options)
end

function UWMWizard:askAmountMode()
    local options = {getText("uwm_wizard_amountFixed"), getText("uwm_wizard_amountAll")}
    OptionDialog.show(function(index)
        if index == 1 then
            self.invoice.amountMode = UWMInvoice.AMOUNT.FIXED
            self:askLiters()
        elseif index == 2 then
            self.invoice.amountMode = UWMInvoice.AMOUNT.ALL
            self:askPrice()
        end
    end, getText("uwm_wizard_title"), getText("uwm_wizard_amount"), options)
end

local function parseNumber(text)
    if text == nil then
        return nil
    end
    local cleaned = text:gsub("[%s,']", "")
    return tonumber(cleaned)
end

function UWMWizard:askLiters()
    -- an offer can't be bigger than the free stock: suggest that
    local default = ""
    if self.listingKind == UWMListing.KIND.OFFER then
        default = tostring(math.floor(UWMStock.getAvailable(self.farmId, self.invoice.fillTypeIndex, nil)))
    end
    TextInputDialog.show(function(_, text, clickOk)
        if not clickOk then
            return
        end
        local liters = parseNumber(text)
        if liters == nil or liters <= 0 then
            InfoDialog.show(getText("uwm_error_badAmount"))
            return
        end
        self.invoice.liters = liters
        self:askPrice()
    end, self, default, getText(unitKey(self.invoice, "uwm_wizard_liters")), getText(unitKey(self.invoice, "uwm_wizard_liters")), 12, getText("uwm_button_next"))
end

-- the game's price for 1,000 liters, shown as a guide
function UWMWizard:getMarketPricePer1000()
    local fillType = g_fillTypeManager:getFillTypeByIndex(self.invoice.fillTypeIndex)
    if fillType ~= nil and fillType.pricePerLiter ~= nil and fillType.pricePerLiter > 0 then
        return fillType.pricePerLiter * 1000
    end
    return nil
end

function UWMWizard:askPrice()
    local prompt = getText(unitKey(self.invoice, "uwm_wizard_price"))
    local market = self:getMarketPricePer1000()
    if market ~= nil then
        prompt = prompt .. "\n" .. string.format(getText(unitKey(self.invoice, "uwm_wizard_marketHint")), UtilitiesWasteManagement.formatMoney(market))
    end
    local default = market ~= nil and tostring(math.floor(market + 0.5)) or ""

    TextInputDialog.show(function(_, text, clickOk)
        if not clickOk then
            return
        end
        local price = parseNumber(text)
        if price == nil or price < 0 then
            InfoDialog.show(getText("uwm_error_badPrice"))
            return
        end
        self.invoice.pricePer1000 = price
        if self.listingKind == nil then
            self:askRepeat()
        elseif self.listingKind == UWMListing.KIND.WANTED and self.invoice.fillTypeIndex == FillType.ELECTRICCHARGE then
            self:askTargets(function()
                self:confirmListing()
            end)
        else
            self:confirmListing()
        end
    end, self, default, prompt, getText(unitKey(self.invoice, "uwm_wizard_price")), 12, getText("uwm_button_next"))
end

function UWMWizard:askRepeat()
    local values = {UWMInvoice.REPEAT_ONCE, UWMInvoice.REPEAT_DAILY, UWMInvoice.REPEAT_WEEKLY}
    local options = {getText("uwm_repeat_once"), getText("uwm_repeat_daily"), getText("uwm_repeat_weekly")}
    OptionDialog.show(function(index)
        if values[index] ~= nil then
            self.invoice.repeatDays = values[index]
            if self.isBill then
                self:confirmNew()
            else
                self:askBuyerOptions(function()
                    self:confirmNew()
                end)
            end
        end
    end, getText("uwm_wizard_title"), getText("uwm_wizard_repeat"), options)
end

-- the receiving productions (electricity). Manure / slurry needs no choice any more: the seller's goods wait in the
-- depot for the buyer (user's rule 2026-10-28), so there is nothing left to reserve.
function UWMWizard:askBuyerOptions(onDone)
    if self.invoice.fillTypeIndex == FillType.ELECTRICCHARGE then
        self:askTargets(onDone)
        return
    end
    if UWMManager.getUsesDepot(self.invoice.fillTypeIndex) then
        onDone()
        return
    end
    local options = {getText("uwm_wizard_reserveNo"), getText("uwm_wizard_reserveYes")}
    OptionDialog.show(function(index)
        if index == 1 or index == 2 then
            self.invoice.reserve = index == 2
            onDone()
        end
    end, getText("uwm_wizard_title"), getText("uwm_wizard_reserve"), options)
end

-- pick one or more of the farm's productions that use electricity, filled in the order picked
function UWMWizard:askTargets(onDone)
    local candidates = UWMStock.getElectricityTargets(self.farmId)
    if #candidates == 0 then
        InfoDialog.show(getText("uwm_error_noTargets"))
        return
    end

    local chosen = self.targetPlaceables
    local function indexOf(placeable)
        for i, chosenPlaceable in ipairs(chosen) do
            if chosenPlaceable == placeable then
                return i
            end
        end
        return nil
    end

    local function show()
        local options = {string.format(getText("uwm_wizard_targetsDone"), #chosen)}
        for _, candidate in ipairs(candidates) do
            local position = indexOf(candidate.placeable)
            local mark = position ~= nil and string.format("[%d] ", position) or "[  ] "
            table.insert(options, mark .. candidate.name)
        end
        OptionDialog.show(function(index)
            if index == 1 then
                if #chosen == 0 then
                    InfoDialog.show(getText("uwm_error_noTargets"))
                else
                    onDone()
                end
            elseif candidates[index - 1] ~= nil then
                local placeable = candidates[index - 1].placeable
                local position = indexOf(placeable)
                if position ~= nil then
                    table.remove(chosen, position)
                elseif #chosen < UWMInvoice.MAX_TARGETS then
                    table.insert(chosen, placeable)
                end
                show()
            end
        end, getText("uwm_wizard_title"), getText("uwm_wizard_targets"), options)
    end

    show()
end

----------------------------------------------------------------------------------------------------------------
-- Confirm and send
----------------------------------------------------------------------------------------------------------------

function UWMWizard.getSummary(invoice, farmId, numTargets)
    local UWM = UtilitiesWasteManagement
    local lines = {}
    local isBuyer = invoice.buyerFarmId == farmId

    table.insert(lines, string.format(getText(isBuyer and "uwm_summary_buyFrom" or "uwm_summary_sellTo"),
        UWM.getGoodName(invoice.fillTypeIndex), UWMManager.getFarmName(invoice:getOtherFarmId(farmId))))

    if invoice.amountMode == UWMInvoice.AMOUNT.ALL then
        table.insert(lines, getText("uwm_summary_amountAll"))
    else
        table.insert(lines, string.format(getText("uwm_summary_amount"), UWM.formatAmount(invoice.fillTypeIndex, invoice.liters),
            UWM.formatMoney(invoice:getPrice(invoice.liters))))
    end
    table.insert(lines, string.format(getText(unitKey(invoice, "uwm_summary_price")), UWM.formatMoney(invoice.pricePer1000)))
    UWMFrame.addDiscountLines(lines, invoice, farmId)

    local repeatKey = "uwm_repeat_once"
    if invoice.repeatDays == UWMInvoice.REPEAT_DAILY then
        repeatKey = "uwm_repeat_daily"
    elseif invoice.repeatDays == UWMInvoice.REPEAT_WEEKLY then
        repeatKey = "uwm_repeat_weekly"
    end
    table.insert(lines, getText(repeatKey))

    if invoice.reserve then
        table.insert(lines, getText("uwm_summary_reserved"))
    end
    numTargets = numTargets or #invoice.targets
    if numTargets > 0 then
        table.insert(lines, string.format(getText("uwm_summary_targets"), numTargets))
    end

    return table.concat(lines, "\n")
end

function UWMWizard:confirmNew()
    local text = UWMWizard.getSummary(self.invoice, self.farmId, #self.targetPlaceables) .. "\n\n"
        .. getText(self.isBill and "uwm_confirm_sendBill" or "uwm_confirm_sendOrder")
    YesNoDialog.show(function(_, yes)
        if yes then
            UWMRequestEvent.sendRequest(UWMManager.ACTION.CREATE, {invoice = self.invoice, targetPlaceables = self.targetPlaceables})
        end
    end, self, text, getText("uwm_wizard_title"))
end

function UWMWizard:confirmAccept()
    local invoice = self.acceptInvoice
    local isBuyer = invoice.buyerFarmId == self.farmId

    -- show the buyer's new choices in the summary
    local shown = UWMInvoice.new()
    for key, value in pairs(invoice) do
        shown[key] = value
    end
    local numTargets = nil
    if isBuyer then
        shown.reserve = self.invoice.reserve
        numTargets = #self.targetPlaceables
    end

    local text = UWMWizard.getSummary(shown, self.farmId, numTargets) .. "\n\n" .. getText(isBuyer and "uwm_confirm_acceptPay" or "uwm_confirm_accept")
    YesNoDialog.show(function(_, yes)
        if yes then
            local data = {invoiceId = invoice.id}
            if isBuyer then
                data.reserve = self.invoice.reserve
                data.targetPlaceables = self.targetPlaceables
            end
            UWMRequestEvent.sendRequest(UWMManager.ACTION.ACCEPT, data)
        end
    end, self, text, getText("uwm_wizard_title"))
end


----------------------------------------------------------------------------------------------------------------
-- Standing orders
----------------------------------------------------------------------------------------------------------------

function UWMWizard:confirmListing()
    local UWM = UtilitiesWasteManagement
    local invoice = self.invoice
    local isOffer = self.listingKind == UWMListing.KIND.OFFER
    local lines = {
        string.format(getText(isOffer and "uwm_summary_listingOffer" or "uwm_summary_listingWanted"), UWM.getGoodName(invoice.fillTypeIndex)),
        string.format(getText("uwm_summary_amount"), UWM.formatAmount(invoice.fillTypeIndex, invoice.liters),
            UWM.formatMoney(invoice:getPrice(invoice.liters))),
        string.format(getText(unitKey(invoice, "uwm_summary_price")), UWM.formatMoney(invoice.pricePer1000))
    }
    if #self.targetPlaceables > 0 then
        table.insert(lines, string.format(getText("uwm_summary_targets"), #self.targetPlaceables))
    end
    table.insert(lines, "")
    table.insert(lines, getText(isOffer and "uwm_summary_listingStockHeld" or "uwm_summary_listingMoneyHeld"))
    table.insert(lines, "")
    table.insert(lines, getText("uwm_confirm_postListing"))

    YesNoDialog.show(function(_, yes)
        if yes then
            local listing = UWMListing.new()
            listing.kind = self.listingKind
            listing.fillTypeIndex = invoice.fillTypeIndex
            listing.liters = invoice.liters
            listing.pricePer1000 = invoice.pricePer1000
            listing.isPallet = invoice.isPallet
            listing.palletSize = invoice.palletSize
            UWMRequestEvent.sendRequest(UWMManager.ACTION.POST_LISTING, {listing = listing, targetPlaceables = self.targetPlaceables})
        end
    end, self, table.concat(lines, "\n"), getText("uwm_wizard_listingTitle"))
end

-- the most this farm can take / give on the order now
function UWMWizard.getTradeMax(listing, farmId)
    local most = listing.remaining
    if not listing:getIsOffer() then
        most = math.min(most, UWMStock.getAvailable(farmId, listing.fillTypeIndex, nil))
    end
    return math.max(math.floor(most), 0)
end

function UWMWizard:askTradeAmount()
    local UWM = UtilitiesWasteManagement
    local listing = self.tradeListing
    local most = UWMWizard.getTradeMax(listing, self.farmId)
    local ft = listing.fillTypeIndex
    local prompt = string.format(getText(listing:getIsOffer() and "uwm_wizard_tradeBuy" or "uwm_wizard_tradeSell"),
        UWM.formatAmount(ft, listing.remaining), UWMFrame.getPriceText(ft, listing.pricePer1000))
    if not listing:getIsOffer() then
        prompt = prompt .. "\n" .. string.format(getText("uwm_wizard_tradeYouHave"), UWM.formatAmount(ft, most))
    end

    TextInputDialog.show(function(_, text, clickOk)
        if not clickOk then
            return
        end
        local liters = parseNumber(text)
        if liters == nil or liters <= 0 then
            InfoDialog.show(getText("uwm_error_badAmount"))
            return
        end
        if liters > listing.remaining + 0.01 then
            InfoDialog.show(getText("uwm_error_listingTooMuch"))
            return
        end
        self.invoice.liters = liters
        if listing:getIsOffer() and listing:getIsElectricity() then
            self:askTargets(function()
                self:confirmTrade()
            end)
        else
            self:confirmTrade()
        end
    end, self, tostring(most), prompt, getText("uwm_wizard_listingTitle"), 12, getText("uwm_button_next"))
end

function UWMWizard:confirmTrade()
    local UWM = UtilitiesWasteManagement
    local listing = self.tradeListing
    local ft = listing.fillTypeIndex
    local liters = self.invoice.liters
    local isBuying = listing:getIsOffer()
    local lines = {
        string.format(getText(isBuying and "uwm_summary_tradeBuy" or "uwm_summary_tradeSell"), UWM.formatAmount(ft, liters),
            UWM.getGoodName(ft), UWMManager.getFarmName(listing.farmId), UWM.formatMoney(listing:getPrice(liters))),
        ""
    }
    local key
    if listing:getIsElectricity() then
        key = isBuying and "uwm_confirm_tradeBuyKWh" or "uwm_confirm_tradeSellKWh"
    else
        key = isBuying and "uwm_confirm_tradeBuy" or "uwm_confirm_tradeSell"
    end
    table.insert(lines, getText(key))

    YesNoDialog.show(function(_, yes)
        if yes then
            UWMRequestEvent.sendRequest(UWMManager.ACTION.TRADE_LISTING, {listingId = listing.id, liters = liters,
                targetPlaceables = isBuying and self.targetPlaceables or nil})
        end
    end, self, table.concat(lines, "\n"), getText("uwm_wizard_listingTitle"))
end
