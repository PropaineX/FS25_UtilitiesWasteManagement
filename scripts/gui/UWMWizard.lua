-- Utilities & Waste Management: writing a new invoice and accepting one, step by step with the game's own
-- dialogs (choose from a list, type a number, yes/no).
-- New invoice: sell or buy -> other farm -> good -> amount -> price -> one-off / daily / weekly
--   -> buyer's choices (reserve, or the productions that get the electricity) -> confirm.
-- Author: PropaineX

UWMWizard = {}
local UWMWizard_mt = Class(UWMWizard)

local function getText(key)
    return UtilitiesWasteManagement.getText(key)
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
            self:askAmountMode()
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
    end, self, "", getText("uwm_wizard_liters"), getText("uwm_wizard_liters"), 12, getText("uwm_button_next"))
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
    local prompt = getText("uwm_wizard_price")
    local market = self:getMarketPricePer1000()
    if market ~= nil then
        prompt = prompt .. "\n" .. string.format(getText("uwm_wizard_marketHint"), UtilitiesWasteManagement.formatMoney(market))
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
        self:askRepeat()
    end, self, default, prompt, getText("uwm_wizard_price"), 12, getText("uwm_button_next"))
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

-- reserve (manure / slurry) or the receiving productions (electricity)
function UWMWizard:askBuyerOptions(onDone)
    if self.invoice.fillTypeIndex == FillType.ELECTRICCHARGE then
        self:askTargets(onDone)
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
    table.insert(lines, string.format(getText("uwm_summary_price"), UWM.formatMoney(invoice.pricePer1000)))

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
