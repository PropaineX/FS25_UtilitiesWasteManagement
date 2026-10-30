-- Utilities & Waste Management: the UWM CO-OP form. One item per invoice (or standing order): farm, goods,
-- price, amount, repeat; the pickup is always the depot on the map. Send hands the choices to UWMWizard.startForm,
-- which runs the same steps and server request as before.
-- Author: PropaineX

UWMOrderDialog = {}
local UWMOrderDialog_mt = Class(UWMOrderDialog, MessageDialog)

UWMOrderDialog.NAME = "UWMOrderDialog"
UWMOrderDialog.REPEATS = {
    {days = UWMInvoice.REPEAT_ONCE, textKey = "uwm_repeat_once"},
    {days = UWMInvoice.REPEAT_DAILY, textKey = "uwm_repeat_daily"},
    {days = UWMInvoice.REPEAT_WEEKLY, textKey = "uwm_repeat_weekly"}
}

local FORM = UWMWizard.FORM

local MODE_TEXTS = {
    [FORM.BILL] = {title = "uwm_form_titleBill", send = "uwm_form_sendBill", farm = "uwm_form_customer"},
    [FORM.REQUEST] = {title = "uwm_form_titleRequest", send = "uwm_form_sendRequest", farm = "uwm_form_seller"},
    [FORM.WANTED] = {title = "uwm_form_titleWanted", send = "uwm_form_post", farm = "uwm_form_market"},
    [FORM.OFFER] = {title = "uwm_form_titleOffer", send = "uwm_form_post", farm = "uwm_form_market"}
}

local function getText(key)
    return UtilitiesWasteManagement.getText(key)
end

local function unitKey(fillTypeIndex, key)
    if fillTypeIndex == FillType.ELECTRICCHARGE then
        return key .. "KWh"
    end
    return key
end

local function parseNumber(text)
    if text == nil then
        return nil
    end
    return tonumber((text:gsub("[%s,']", "")))
end

function UWMOrderDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or UWMOrderDialog_mt)
    self.mode = FORM.BILL
    self.farms = {}
    self.goods = {}
    self.farmIndex = 1
    self.goodIndex = 1
    self.amountAll = false
    self.repeatIndex = 1
    return self
end

function UWMOrderDialog.register()
    local dialog = UWMOrderDialog.new()
    g_gui:loadGui(UtilitiesWasteManagement.modDirectory .. "gui/UWMOrderDialog.xml", UWMOrderDialog.NAME, dialog)
    UWMOrderDialog.instance = dialog
end

function UWMOrderDialog.show(mode)
    local dialog = UWMOrderDialog.instance
    if dialog == nil then
        return
    end
    local farmId = UtilitiesWasteManagement.getLocalFarmId()
    if not UWMWizard.getFormIsListing(mode) and #UWMOrderDialog.getFarms(farmId) == 0 then
        InfoDialog.show(getText("uwm_wizard_noFarms"))
        return
    end
    dialog.mode = mode
    g_gui:showDialog(UWMOrderDialog.NAME)
end

----------------------------------------------------------------------------------------------------------------
-- What the form shows (no GUI: tested headless)
----------------------------------------------------------------------------------------------------------------

-- the other farms, by name
function UWMOrderDialog.getFarms(farmId)
    local farms = {}
    for _, farm in pairs(g_farmManager:getFarms()) do
        if farm.farmId ~= farmId and farm.farmId ~= FarmManager.SPECTATOR_FARM_ID then
            table.insert(farms, {farmId = farm.farmId, name = farm.name or tostring(farm.farmId)})
        end
    end
    table.sort(farms, function(a, b)
        return a.farmId < b.farmId
    end)
    return farms
end

-- whose stock the goods come out of: ours when we sell, the chosen farm's when we ask them; nil = any seller
function UWMOrderDialog.getSellerFarmId(mode, farmId, otherFarmId)
    if mode == FORM.BILL or mode == FORM.OFFER then
        return farmId
    elseif mode == FORM.REQUEST then
        return otherFarmId
    end
    return nil
end

function UWMOrderDialog.getPickupPointKey(fillTypeIndex, isPallet)
    if isPallet then
        return "uwm_form_pointPallets"
    elseif fillTypeIndex == FillType.ELECTRICCHARGE then
        return "uwm_form_pointDirect"
    elseif fillTypeIndex == FillType.MANURE then
        return "uwm_form_pointManure"
    elseif UtilitiesWasteManagement.getIsBulk(fillTypeIndex) then
        return "uwm_form_pointSilo"
    end
    return "uwm_form_pointSlurry"
end

-- the Pallet list: the seller's pallet goods now (free liters and number of pallets), or every pallet good
function UWMOrderDialog.getPalletChoices(sellerFarmId)
    if sellerFarmId == nil then
        return UWMPallets.getAllGoods()
    end
    return UWMPallets.getGoods(sellerFarmId)
end

-- the Bulk list: what the seller can sell now (with the free amount), or - no seller yet (standing buy order) -
-- every bulk good in the game; A - Z
function UWMOrderDialog.getBulkChoices(sellerFarmId)
    if sellerFarmId == nil then
        return UWMStock.getAllBulkGoods()
    end
    return UWMStock.getBulkGoods(sellerFarmId)
end

-- 03 Pickup: the depot's name, {key, value} rows and the note under them
function UWMOrderDialog.getPickupInfo(mode, sellerFarmId, fillTypeIndex, isPallet)
    local UWM = UtilitiesWasteManagement
    local depots = UWMManager.getDepots()
    local depot = depots[1]
    local depotName = getText("uwm_form_depot")
    if depot ~= nil and depot.getName ~= nil then
        depotName = depot:getName() or depotName
    end

    -- every co-op farm shares the upkeep, so the depot belongs to the community (user, 2026-10-28)
    local rows = {
        {getText("uwm_form_owner"), getText("uwm_form_community")},
        {getText("uwm_form_point"), getText(UWMOrderDialog.getPickupPointKey(fillTypeIndex, isPallet))}
    }
    if sellerFarmId ~= nil then
        local stock = isPallet and UWMPallets.getStock(sellerFarmId, fillTypeIndex) or UWMStock.getStock(sellerFarmId, fillTypeIndex)
        local free = isPallet and stock or UWMStock.getAvailable(sellerFarmId, fillTypeIndex, nil)
        table.insert(rows, {getText(mode == FORM.REQUEST and "uwm_form_theirStock" or "uwm_form_yourStock"), UWM.formatAmount(fillTypeIndex, stock)})
        if UWMManager.getUsesDepot(fillTypeIndex) then
            -- goods for sale already wait in the depot (they left the farm)
            local atDepot = UWM.manager ~= nil and UWM.manager:getDepotLitersOf(sellerFarmId, fillTypeIndex, isPallet == true) or 0
            table.insert(rows, {getText("uwm_form_atDepot"), UWM.formatAmount(fillTypeIndex, atDepot)})
        else
            table.insert(rows, {getText("uwm_form_reserved"), UWM.formatAmount(fillTypeIndex, math.max(stock - free, 0))})
        end
        table.insert(rows, {getText("uwm_form_free"), UWM.formatAmount(fillTypeIndex, free)})
    end

    local noteKey = "uwm_form_noteDepot"
    if isPallet then
        noteKey = "uwm_form_notePallets"
    elseif fillTypeIndex == FillType.ELECTRICCHARGE then
        noteKey = "uwm_form_noteElectricity"
    end
    local note = getText(noteKey)
    return depotName, rows, note
end

-- the money of one delivery: paid (discount off), full price, discount (nil = can't be worked out yet, e.g. "all of it")
function UWMOrderDialog.getTotals(form)
    if form.amountAll or form.liters == nil or form.pricePer1000 == nil then
        return nil
    end
    local full = form.liters * form.pricePer1000 / 1000
    local discount = full * math.max(math.min(form.discountPercent or 0, 100), 0) / 100
    return full - discount, full, discount
end

----------------------------------------------------------------------------------------------------------------
-- GUI
----------------------------------------------------------------------------------------------------------------

function UWMOrderDialog:onGuiSetupFinished()
    UWMOrderDialog:superClass().onGuiSetupFinished(self)
    for _, list in ipairs({self.farmList, self.goodsList}) do
        list:setDataSource(self)
        list:setDelegate(self)
    end
    UWMGui.applyStaticImages(self.dialogElement)
    -- our drop-and-bolt icon in the header tile (the ESC tab's image)
    if self.headIcon ~= nil and self.headIcon.setImageFilename ~= nil then
        self.headIcon:setImageFilename(UtilitiesWasteManagement.modDirectory .. UWMFrame.ICON_FILENAME)
        self.headIcon:setImageUVs(nil, unpack(UWMFrame.getIconUVs()))
    end
end

function UWMOrderDialog:onOpen()
    UWMOrderDialog:superClass().onOpen(self)
    local texts = MODE_TEXTS[self.mode] or MODE_TEXTS[FORM.BILL]
    self.farmId = UtilitiesWasteManagement.getLocalFarmId()
    self.isListing = UWMWizard.getFormIsListing(self.mode)
    self.farms = self.isListing and {} or UWMOrderDialog.getFarms(self.farmId)
    -- our three goods, then a Bulk row that opens the list of bulk goods
    self.goods = {}
    for _, good in ipairs(UtilitiesWasteManagement.goods) do
        table.insert(self.goods, good)
    end
    table.insert(self.goods, {isBulk = true})
    table.insert(self.goods, {isPallet = true})
    self.bulkFillType = nil
    self.palletFillType = nil
    self.palletSizeIndex = 1
    self.isPicking = false
    self.farmIndex = 1
    self.goodIndex = 1
    UWMPallets.probeObjectStorages(self.farmId)
    self.amountAll = false
    self.repeatIndex = 1

    self.titleText:setText(getText(texts.title))
    self.farmColumnTitle:setText(getText(texts.farm))
    self.sendButton:setText(getText(texts.send))
    self.farmList:setVisible(not self.isListing)
    self.farmNote:setVisible(self.isListing)
    self.farmNote:setText(getText("uwm_form_marketNote"))
    self.amountButton:setDisabled(self.isListing)
    self.repeatButton:setDisabled(self.isListing)

    self.farmList:reloadData()
    self.goodsList:reloadData()
    self:resetPrice()
    self.qtyInput:setText("")
    self.discountInput:setText("")
    self.discountInput:setDisabled(self.isListing)
    self:updateAll()
    FocusManager:setFocus(self.isListing and self.goodsList or self.farmList)
end

function UWMOrderDialog:getFillTypeIndex()
    local good = self.goods[self.goodIndex]
    if good ~= nil and good.isBulk then
        return self.bulkFillType or FillType.UNKNOWN
    elseif good ~= nil and good.isPallet then
        return self.palletFillType or FillType.UNKNOWN
    end
    return good ~= nil and good.fillTypeIndex or FillType.UNKNOWN
end

function UWMOrderDialog:getIsPallet()
    local good = self.goods[self.goodIndex]
    return good ~= nil and good.isPallet == true
end

-- the Bulk / Pallet list (the game's list dialog), A - Z with what can be sold
function UWMOrderDialog:openGoodsList(isPallet)
    if self.isPicking then
        return
    end
    local UWM = UtilitiesWasteManagement
    local sellerFarmId = UWMOrderDialog.getSellerFarmId(self.mode, self.farmId, self:getOtherFarmId())
    local choices = isPallet and UWMOrderDialog.getPalletChoices(sellerFarmId) or UWMOrderDialog.getBulkChoices(sellerFarmId)
    if #choices == 0 then
        local key = isPallet and "uwm_form_noPallets" or "uwm_form_noBulk"
        InfoDialog.show(getText(self.mode == FORM.REQUEST and key .. "Them" or key))
        return
    end
    local options = {}
    for _, choice in ipairs(choices) do
        local text = choice.name
        if choice.count ~= nil then
            text = string.format(getText("uwm_form_palletChoice"), choice.name, UWM.formatAmount(choice.fillTypeIndex, choice.liters), choice.count)
        elseif choice.liters ~= nil then
            text = string.format(getText("uwm_form_bulkChoice"), choice.name, UWM.formatAmount(choice.fillTypeIndex, choice.liters))
        end
        table.insert(options, text)
    end
    self.isPicking = true
    OptionDialog.show(function(index)
        self.isPicking = false
        local choice = choices[index]
        if choice ~= nil then
            if isPallet then
                self.palletFillType = choice.fillTypeIndex
            else
                self.bulkFillType = choice.fillTypeIndex
            end
            self:resetPrice()
            self.goodsList:reloadData()
            self:updateAll()
        end
    end, getText(isPallet and "uwm_form_palletTitle" or "uwm_form_bulkTitle"),
        getText(sellerFarmId == nil and (isPallet and "uwm_form_palletAll" or "uwm_form_bulkAll") or (isPallet and "uwm_form_palletText" or "uwm_form_bulkText")), options)
end

function UWMOrderDialog:openBulkList()
    self:openGoodsList(false)
end

-- 1,000 / 5,000 l per pallet
function UWMOrderDialog:onClickPalletSize()
    self.palletSizeIndex = self.palletSizeIndex % #UWMPallets.SIZES + 1
    self:updateAll()
end

function UWMOrderDialog:getOtherFarmId()
    local farm = self.farms[self.farmIndex]
    return farm ~= nil and farm.farmId or nil
end

function UWMOrderDialog:getMarketPricePer1000(fillTypeIndex)
    local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    if fillType ~= nil and fillType.pricePerLiter ~= nil and fillType.pricePerLiter > 0 then
        return fillType.pricePerLiter * 1000
    end
    return nil
end

-- the game's price as a start, whenever the goods change
function UWMOrderDialog:resetPrice()
    local market = self:getMarketPricePer1000(self:getFillTypeIndex())
    self.priceInput:setText(market ~= nil and tostring(math.floor(market + 0.5)) or "")
end

function UWMOrderDialog:getForm()
    return {
        mode = self.mode,
        otherFarmId = self:getOtherFarmId(),
        fillTypeIndex = self:getFillTypeIndex(),
        amountAll = self.amountAll and not self.isListing,
        liters = parseNumber(self.qtyInput:getText()),
        pricePer1000 = parseNumber(self.priceInput:getText()),
        discountPercent = self.isListing and 0 or (parseNumber(self.discountInput:getText()) or 0),
        isPallet = self:getIsPallet(),
        palletSize = UWMPallets.SIZES[self.palletSizeIndex],
        repeatDays = self.isListing and UWMInvoice.REPEAT_ONCE or UWMOrderDialog.REPEATS[self.repeatIndex].days
    }
end

function UWMOrderDialog:updateAll()
    local UWM = UtilitiesWasteManagement
    local form = self:getForm()
    local ft = form.fillTypeIndex
    local farmName = form.otherFarmId ~= nil and UWMManager.getFarmName(form.otherFarmId) or getText("uwm_form_anyFarm")
    local myName = UWMManager.getFarmName(self.farmId)

    -- 03 pickup
    local sellerFarmId = UWMOrderDialog.getSellerFarmId(self.mode, self.farmId, form.otherFarmId)
    local depotName, rows, note = UWMOrderDialog.getPickupInfo(self.mode, sellerFarmId, ft, form.isPallet)
    self.depotName:setText(depotName)
    for i = 1, 5 do
        local row = rows[i]
        self["infoKey" .. i]:setText(row ~= nil and row[1] or "")
        self["infoValue" .. i]:setText(row ~= nil and row[2] or "")
    end
    self.pickupNote:setText(note)
    -- pallet goods: the size of the new pallets on the pad
    self.palletSizeBox:setVisible(form.isPallet)
    self.palletSizeValue:setText(UWM.formatAmount(ft, UWMPallets.getPalletLiters(ft, form.palletSize)))

    -- issuer / customer: the seller issues the invoice
    local seller, buyer = myName, farmName
    if self.mode == FORM.REQUEST or self.mode == FORM.WANTED then
        seller, buyer = farmName, myName
    end
    self.issuerText:setText(seller)
    self.customerText:setText(string.format(getText("uwm_form_buyer"), buyer))

    -- the line
    local repeatText = getText(UWMOrderDialog.REPEATS[self.repeatIndex].textKey)
    local money, fullMoney, discountMoney = UWMOrderDialog.getTotals(form)
    local hasDiscount = (form.discountPercent or 0) > 0
    self.rowGood:setText(UWM.getGoodName(ft))
    UWMGui.setIcon(self.rowIcon, UWMGui.getGoodsIcon(ft, form.isPallet))
    local pickupKey = form.isPallet and "uwm_form_rowPallets" or (ft == FillType.ELECTRICCHARGE and "uwm_form_rowDirect" or "uwm_form_rowDepot")
    self.rowPickup:setText(getText(pickupKey))
    self.rowQty:setText(form.amountAll and getText("uwm_form_all") or (form.liters ~= nil and g_i18n:formatNumber(form.liters, 0) or "-"))
    self.rowUnit:setText(getText(ft == FillType.ELECTRICCHARGE and "uwm_form_unitKWh" or "uwm_form_unitL"))
    self.rowPrice:setText(form.pricePer1000 ~= nil and UWMFrame.getPriceText(ft, form.pricePer1000) or "-")
    self.rowDiscount:setText(hasDiscount and string.format(getText("uwm_form_percent"), UWMManager.formatPercent(form.discountPercent)) or "-")
    self.rowRepeat:setText(self.isListing and "-" or repeatText)
    self.rowAmount:setText(money ~= nil and UWM.formatMoney(money) or "-")

    -- inputs
    self.priceLabel:setText(getText(unitKey(ft, "uwm_wizard_price")))
    self.qtyLabel:setText(getText(unitKey(ft, "uwm_wizard_liters")))
    self.qtyInput:setDisabled(form.amountAll)
    self.amountButton:setText(getText(form.amountAll and "uwm_form_all" or "uwm_form_setAmount"))
    self.repeatButton:setText(self.isListing and "-" or repeatText)
    local market = self:getMarketPricePer1000(ft)
    self.priceHint:setText(market ~= nil and string.format(getText(unitKey(ft, "uwm_wizard_marketHint")), UWM.formatMoney(market)) or "")

    -- total
    local repeating = not self.isListing and UWMOrderDialog.REPEATS[self.repeatIndex].days ~= UWMInvoice.REPEAT_ONCE
    self.totalLabel:setText(getText(repeating and "uwm_form_totalEach" or "uwm_form_total"))
    local percentText = UWMManager.formatPercent(form.discountPercent or 0)
    if form.amountAll then
        self.totalDetail:setText(getText("uwm_form_totalAll"))
        self.totalDiscount:setText(hasDiscount and string.format(getText("uwm_form_discountOff"), percentText) or "")
    elseif hasDiscount and fullMoney ~= nil then
        self.totalDetail:setText(string.format(getText("uwm_form_subtotal"), UWM.formatMoney(fullMoney)))
        self.totalDiscount:setText(string.format(getText("uwm_form_discountLine"), percentText, UWM.formatMoney(discountMoney)))
    else
        self.totalDetail:setText(repeating and (repeatText .. " - " .. getText("uwm_form_untilEnded")) or "")
        self.totalDiscount:setText("")
    end
    self.totalValue:setText(money ~= nil and UWM.formatMoney(money) or "-")
    self.totalPill:setText(hasDiscount and string.format(getText("uwm_form_offPill"), percentText) or "")
end

-- SmoothList data source / delegate

function UWMOrderDialog:getNumberOfItemsInSection(list, section)
    if list == self.farmList then
        return #self.farms
    end
    return #self.goods
end

function UWMOrderDialog:populateCellForItemInSection(list, section, index, cell)
    UWMGui.applyStaticImages(cell)
    local name = cell:getAttribute("name")
    if list == self.farmList then
        local farm = self.farms[index]
        name:setText(farm ~= nil and farm.name or "")
        UWMGui.setIcon(cell:getAttribute("icon"), "farm")
        return
    end
    local good = self.goods[index]
    if good == nil then
        return
    end
    local icon = good.isBulk and "bulk" or (good.isPallet and "pallet" or UWMGui.getGoodsIcon(good.fillTypeIndex))
    UWMGui.setIcon(cell:getAttribute("icon"), icon)
    local arrow = cell:getAttribute("arrow")
    if arrow ~= nil then
        UWMGui.setIcon(arrow, "arrow")
        arrow:setVisible(good.isBulk == true or good.isPallet == true)
    end
    local price = cell:getAttribute("price")
    if good.isBulk or good.isPallet then
        local picked = good.isBulk and self.bulkFillType or self.palletFillType
        name:setText(getText(good.isBulk and "uwm_form_bulk" or "uwm_form_pallet"))
        price:setText(picked ~= nil and UtilitiesWasteManagement.getGoodName(picked) or getText("uwm_form_bulkPick"))
        return
    end
    name:setText(getText(good.textKey))
    local market = self:getMarketPricePer1000(good.fillTypeIndex)
    price:setText(market ~= nil and UWMFrame.getPriceText(good.fillTypeIndex, market) or "")
end

function UWMOrderDialog:onListSelectionChanged(list, section, index)
    if list == self.farmList then
        self.farmIndex = index
    elseif list == self.goodsList then
        if index ~= self.goodIndex then
            self.goodIndex = index
            self:resetPrice()
            local good = self.goods[index]
            if good ~= nil and good.isBulk and self.bulkFillType == nil then
                self:openGoodsList(false)
            elseif good ~= nil and good.isPallet and self.palletFillType == nil then
                self:openGoodsList(true)
            end
        end
    end
    self:updateAll()
end

-- clicking the Bulk row again opens the list again (to pick something else)
function UWMOrderDialog:onClickGoods(list, section, index)
    local good = self.goods[index or self.goodIndex]
    if good ~= nil and (good.isBulk or good.isPallet) then
        self:openGoodsList(good.isPallet == true)
    end
end

-- inputs and buttons

function UWMOrderDialog:onInputChanged()
    self:updateAll()
end

function UWMOrderDialog:onClickAmount()
    if not self.isListing then
        self.amountAll = not self.amountAll
        self:updateAll()
    end
end

function UWMOrderDialog:onClickRepeat()
    if not self.isListing then
        self.repeatIndex = self.repeatIndex % #UWMOrderDialog.REPEATS + 1
        self:updateAll()
    end
end

function UWMOrderDialog:onClickSend()
    local form = self:getForm()
    local errorKey = UWMWizard.getFormError(form)
    if errorKey ~= nil then
        InfoDialog.show(getText(errorKey))
        return
    end
    self:close()
    UWMWizard.startForm(form)
end

function UWMOrderDialog:onClickBack()
    self:close()
end
