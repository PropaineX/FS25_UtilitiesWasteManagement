-- Utilities & Waste Management: the "Utilities" page in the ESC menu.
-- Tabs (user's layout, 2026-10-24): INCOMING (invoices other farms sent you), OUTGOING (sent by you), STANDING ORDERS
-- with sub-tabs MARKET (other farms' open standing orders + your open deals), MY ORDERS, MY DEALS. Only the farm
-- manager gets the trade buttons. The header shows the farm's depot status and balance; the Depot button answers the
-- membership offer, asks to join, pays arrears, and (server admin) switches "more than one depot".
-- Author: PropaineX

UWMFrame = {}
local UWMFrame_mt = Class(UWMFrame, TabbedMenuFrameElement)

UWMFrame.PAGE_NAME = "pageUtilitiesWasteManagement"
UWMFrame.ICON_FILENAME = "gui/uwm_tabIcon.dds"
UWMFrame.ICON_SIZE = 256

UWMFrame.TAB_INCOMING = 1
UWMFrame.TAB_OUTGOING = 2
UWMFrame.TAB_BOARD = 3

UWMFrame.SUB_MARKET = 1
UWMFrame.SUB_MY_ORDERS = 2
UWMFrame.SUB_MY_DEALS = 3

-- status colors (text color of the status cell; the other cells keep their profile color)
UWMFrame.COLOR_GOOD = {0.47, 0.70, 0.06, 1}
UWMFrame.COLOR_WARN = {0.91, 0.69, 0.13, 1}
UWMFrame.COLOR_DIM = {0.55, 0.55, 0.55, 1}

UWMFrame.instance = nil

local STATE = UWMInvoice.STATE
local LSTATE = UWMListing.STATE

function UWMFrame.new()
    local self = UWMFrame:superClass().new(nil, UWMFrame_mt)

    self.hasCustomMenuButtons = true
    self.tab = UWMFrame.TAB_INCOMING
    self.subTab = UWMFrame.SUB_MARKET
    self.lists = UWMFrame.buildLists(nil, 0)
    self.selected = nil         -- the invoice or standing order picked in the visible list

    return self
end

----------------------------------------------------------------------------------------------------------------
-- Adding the page to the ESC menu
----------------------------------------------------------------------------------------------------------------

local function moveToPosition(list, item, position, getItem)
    for i = 1, #list do
        if getItem(list[i]) == item then
            local entry = table.remove(list, i)
            table.insert(list, math.min(position, #list + 1), entry)
            return
        end
    end
end

function UWMFrame.getIconUVs()
    local size = UWMFrame.ICON_SIZE
    return GuiUtils.getUVs({0, 0, size, size}, {size, size})
end

function UWMFrame.register()
    if UWMFrame.instance ~= nil then
        return
    end
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if inGameMenu == nil or inGameMenu.pagingElement == nil or inGameMenu.registerPage == nil or inGameMenu.addPageTab == nil then
        Logging.warning("%s the ESC menu can't take new pages, the Utilities page is not added", UtilitiesWasteManagement.TAG)
        return
    end

    local frame = UWMFrame.new()
    g_gui:loadGui(UtilitiesWasteManagement.modDirectory .. "gui/UWMFrame.xml", "UWMFrame", frame, true)

    local pageName = UWMFrame.PAGE_NAME
    inGameMenu.controlIDs[pageName] = nil
    inGameMenu[pageName] = frame
    inGameMenu.pagingElement:addElement(frame)
    inGameMenu:exposeControlsAsFields(pageName)

    -- right after the finances page, or at the end
    local position = #inGameMenu.pagingElement.elements
    for i, element in ipairs(inGameMenu.pagingElement.elements) do
        if element == inGameMenu.pageFinances then
            position = i + 1
            break
        end
    end

    moveToPosition(inGameMenu.pagingElement.elements, frame, position, function(element) return element end)
    moveToPosition(inGameMenu.pagingElement.pages, frame, position, function(page) return page.element end)
    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()

    -- the tab only shows while a depot stands on the map (user's rule); the menu asks again every time it opens
    inGameMenu:registerPage(frame, position, UWMFrame.getIsPageEnabled)
    -- tab icon: our water drop with a lightning bolt (user, 2026-10-24)
    inGameMenu:addPageTab(frame, UtilitiesWasteManagement.modDirectory .. UWMFrame.ICON_FILENAME, UWMFrame.getIconUVs())
    if inGameMenu.pageFrames ~= nil then
        moveToPosition(inGameMenu.pageFrames, frame, position, function(element) return element end)
    end
    inGameMenu:rebuildTabList()

    frame:initialize()
    UWMFrame.instance = frame
    print(UtilitiesWasteManagement.TAG .. " Utilities page added to the ESC menu")
end

function UWMFrame.getIsPageEnabled()
    local manager = UtilitiesWasteManagement.manager
    return manager ~= nil and manager:getHasDepot()
end

function UWMFrame.unregister()
    UWMFrame.instance = nil
end

-- the office door at the depot opens the ESC menu on this page
function UWMFrame.open()
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if UWMFrame.instance == nil or inGameMenu == nil then
        return
    end
    g_gui:showGui("InGameMenu")
    if inGameMenu.goToPage ~= nil then
        inGameMenu:goToPage(UWMFrame.instance)
    end
end

----------------------------------------------------------------------------------------------------------------
-- What goes in which list (no GUI: tested headless)
----------------------------------------------------------------------------------------------------------------

local function isMine(invoice, farmId)
    return (invoice.sellerFarmId == farmId or invoice.buyerFarmId == farmId) and not invoice:getIsHiddenFor(farmId)
end

-- waiting / running first, finished after; newest first in each
local function invoiceRank(invoice)
    if invoice.state == STATE.PENDING then
        return 1
    elseif invoice.state == STATE.ACTIVE then
        return 2
    end
    return 3
end

local function sortInvoices(invoices)
    table.sort(invoices, function(a, b)
        local ra, rb = invoiceRank(a), invoiceRank(b)
        if ra ~= rb then
            return ra < rb
        end
        return a.id > b.id
    end)
end

local function sortListings(listings)
    table.sort(listings, function(a, b)
        local oa, ob = a:getIsOpen() and 1 or 2, b:getIsOpen() and 1 or 2
        if oa ~= ob then
            return oa < ob
        end
        return a.id > b.id
    end)
end

-- {incoming, outgoing, market, myOrders, myDeals, openDeals} for one farm
function UWMFrame.buildLists(manager, farmId)
    local lists = {incoming = {}, outgoing = {}, market = {}, myOrders = {}, myDeals = {}, openDeals = {}}
    if manager == nil then
        return lists
    end
    for _, invoice in ipairs(manager:getInvoices()) do
        if isMine(invoice, farmId) then
            if invoice.listingId > 0 then
                table.insert(lists.myDeals, invoice)
                if invoice.state == STATE.ACTIVE then
                    table.insert(lists.openDeals, invoice)
                end
            elseif invoice.creatorFarmId == farmId then
                table.insert(lists.outgoing, invoice)
            else
                table.insert(lists.incoming, invoice)
            end
        end
    end
    for _, listing in ipairs(manager:getListings()) do
        if listing.farmId == farmId then
            table.insert(lists.myOrders, listing)
        elseif listing:getIsOpen() then
            table.insert(lists.market, listing)
        end
    end
    sortInvoices(lists.incoming)
    sortInvoices(lists.outgoing)
    sortInvoices(lists.myDeals)
    sortInvoices(lists.openDeals)
    sortListings(lists.myOrders)
    sortListings(lists.market)
    return lists
end

-- finished invoices and standing orders Clear history would remove for this farm
function UWMFrame.getFinishedCount(manager, farmId)
    local count = 0
    for _, invoice in ipairs(manager:getInvoices()) do
        if invoice:getIsFinished() and isMine(invoice, farmId) then
            count = count + 1
        end
    end
    for _, listing in ipairs(manager:getListings()) do
        if listing.farmId == farmId and not listing:getIsOpen() then
            count = count + 1
        end
    end
    return count
end

----------------------------------------------------------------------------------------------------------------
-- Row texts (no GUI: tested headless)
----------------------------------------------------------------------------------------------------------------

local function getText(key)
    return UtilitiesWasteManagement.getText(key)
end

function UWMFrame.getInvoiceNumber(invoice)
    return string.format("UWM-%03d", invoice.id)
end

function UWMFrame.getListingNumber(listing)
    return string.format("SO-%03d", listing.id)
end

function UWMFrame.getDayText(day)
    return string.format(getText("uwm_cell_day"), day)
end

function UWMFrame.getPriceText(fillTypeIndex, pricePer1000)
    local key = fillTypeIndex == FillType.ELECTRICCHARGE and "uwm_pricePer1000kWh" or "uwm_pricePer1000"
    return string.format(getText(key), UtilitiesWasteManagement.formatMoney(pricePer1000))
end

function UWMFrame.getRepeatText(invoice)
    if invoice.repeatDays == UWMInvoice.REPEAT_DAILY then
        return getText("uwm_repeat_daily")
    elseif invoice.repeatDays == UWMInvoice.REPEAT_WEEKLY then
        return getText("uwm_repeat_weekly")
    end
    return getText("uwm_repeat_once")
end

-- "Slurry, 10,000 l (you buy)"
function UWMFrame.getDescriptionText(invoice, farmId)
    local UWM = UtilitiesWasteManagement
    local amount
    if invoice.amountMode == UWMInvoice.AMOUNT.ALL then
        amount = getText("uwm_amount_all")
    else
        amount = UWM.formatAmount(invoice.fillTypeIndex, invoice.liters)
    end
    local key = invoice.buyerFarmId == farmId and "uwm_cell_descBuy" or "uwm_cell_descSell"
    local text = string.format(getText(key), UWM.getGoodName(invoice.fillTypeIndex), amount)
    if invoice.discountPercent > 0 then
        text = text .. string.format(getText("uwm_cell_discount"), UWMManager.formatPercent(invoice.discountPercent))
    end
    return text
end

-- money of the invoice: the agreed total, or what was paid so far for "all of it"
function UWMFrame.getAmountText(invoice)
    if invoice.amountMode == UWMInvoice.AMOUNT.FIXED then
        return UtilitiesWasteManagement.formatMoney(invoice:getPrice(invoice.liters))
    elseif invoice.totalMoney > 0 then
        return UtilitiesWasteManagement.formatMoney(invoice.totalMoney)
    end
    return "-"
end

function UWMFrame.getStatusText(invoice, farmId)
    local UWM = UtilitiesWasteManagement
    local parts = {}

    if invoice.state == STATE.PENDING then
        local waitingForYou = farmId ~= nil and invoice.creatorFarmId ~= farmId
        table.insert(parts, getText(waitingForYou and "uwm_state_waitingForYou" or "uwm_state_pending"))
    elseif invoice.state == STATE.ACTIVE then
        if invoice:getIsElectricity() then
            table.insert(parts, string.format(getText("uwm_status_delivered"), UWM.formatAmount(invoice.fillTypeIndex, invoice.totalLiters)))
        elseif invoice.owedLiters > 0.5 then
            table.insert(parts, string.format(getText("uwm_status_toCollect"), UWM.formatAmount(invoice.fillTypeIndex, invoice.owedLiters)))
        else
            table.insert(parts, getText("uwm_state_active"))
        end
    else
        local stateKeys = {[STATE.DONE] = "uwm_state_done", [STATE.DECLINED] = "uwm_state_declined", [STATE.CANCELLED] = "uwm_state_cancelled"}
        table.insert(parts, getText(stateKeys[invoice.state] or "uwm_state_done"))
        if invoice.totalLiters > 0 then
            table.insert(parts, UWM.formatAmount(invoice.fillTypeIndex, invoice.totalLiters))
        end
    end

    if invoice.reserve and invoice.state ~= STATE.DONE then
        table.insert(parts, getText("uwm_status_reserved"))
    end
    if invoice.totalRefund > 0 then
        table.insert(parts, string.format(getText("uwm_status_refunded"), UWM.formatMoney(invoice.totalRefund)))
    end
    if invoice.statusKey ~= "" and invoice.state == STATE.ACTIVE then
        table.insert(parts, getText(invoice.statusKey))
    end

    return table.concat(parts, ", ")
end

function UWMFrame.getStatusColor(invoice, farmId)
    if invoice.state == STATE.PENDING then
        return invoice.creatorFarmId ~= farmId and UWMFrame.COLOR_WARN or nil
    elseif invoice.state == STATE.ACTIVE then
        if invoice.statusKey ~= "" or (not invoice:getIsElectricity() and invoice.owedLiters > 0.5) then
            return UWMFrame.COLOR_WARN
        end
        return UWMFrame.COLOR_GOOD
    end
    return UWMFrame.COLOR_DIM
end

-- INCOMING / OUTGOING: # | day | farm | description | repeats | status | amount
function UWMFrame.getInvoiceRow(invoice, farmId)
    return {
        UWMFrame.getInvoiceNumber(invoice),
        UWMFrame.getDayText(invoice.createdDay),
        UWMManager.getFarmName(invoice:getOtherFarmId(farmId)),
        UWMFrame.getDescriptionText(invoice, farmId),
        UWMFrame.getRepeatText(invoice),
        UWMFrame.getStatusText(invoice, farmId),
        UWMFrame.getAmountText(invoice)
    }, 6, UWMFrame.getStatusColor(invoice, farmId)
end

-- an invoice as a card (Utilities page, user OK'd mock-up previews/menu_v4_incoming.png):
-- {icon, title, sub, status, statusColor (UWMGui.COLOR name), amount}
function UWMFrame.getInvoiceCard(invoice, farmId)
    local UWM = UtilitiesWasteManagement
    local ft = invoice.fillTypeIndex
    local amount = invoice.amountMode == UWMInvoice.AMOUNT.ALL and getText("uwm_amount_all") or UWM.formatAmount(ft, invoice.liters)
    local title = string.format(getText(invoice.isPallet and "uwm_card_titlePallets" or "uwm_card_title"), UWM.getGoodName(ft), amount)

    local isBuyer = invoice.buyerFarmId == farmId
    local parts = {
        UWMFrame.getInvoiceNumber(invoice),
        string.format(getText(isBuyer and "uwm_card_from" or "uwm_card_to"), UWMManager.getFarmName(invoice:getOtherFarmId(farmId))),
        UWMFrame.getDayText(invoice.createdDay),
        UWMFrame.getRepeatText(invoice)
    }
    if invoice.discountPercent > 0 then
        table.insert(parts, string.format(getText("uwm_card_discount"), UWMManager.formatPercent(invoice.discountPercent)))
    end
    if UWMManager.getUsesDepot(ft) then
        table.insert(parts, getText(UWMOrderDialog.getPickupPointKey(ft, invoice.isPallet)))
    end

    local color = "dim"
    if invoice.state == STATE.PENDING then
        color = invoice.creatorFarmId ~= farmId and "greenLight" or "grey"
    elseif invoice.state == STATE.ACTIVE then
        local toCollect = not invoice:getIsElectricity() and invoice.owedLiters > 0.5
        color = (invoice.statusKey ~= "" or toCollect) and "orange" or "blue"
    end

    return {
        icon = UWMGui.getGoodsIcon(ft, invoice.isPallet),
        title = title,
        sub = table.concat(parts, "  -  "),
        status = UWMFrame.getStatusText(invoice, farmId),
        statusColor = color,
        amount = UWMFrame.getAmountText(invoice)
    }
end

-- the four summary cards: waiting for you, running, at the depot for you, your goods for sale (texts)
function UWMFrame.getSummary(manager, farmId)
    local UWM = UtilitiesWasteManagement
    local waiting, running, toCollect = 0, 0, 0
    if manager ~= nil then
        for _, invoice in ipairs(manager.invoices) do
            local mine = invoice.sellerFarmId == farmId or invoice.buyerFarmId == farmId
            if mine and invoice.state == STATE.PENDING and invoice.creatorFarmId ~= farmId then
                waiting = waiting + 1
            elseif mine and invoice.state == STATE.ACTIVE then
                running = running + 1
            end
            if invoice.buyerFarmId == farmId and invoice.state == STATE.ACTIVE and UWMManager.getUsesDepot(invoice.fillTypeIndex) then
                toCollect = toCollect + math.min(invoice.owedLiters, invoice.depotLiters)
            end
        end
    end
    local forSale = 0
    if manager ~= nil then
        for _, invoice in ipairs(manager.invoices) do
            if invoice.sellerFarmId == farmId then
                forSale = forSale + invoice.depotLiters
            end
        end
        for _, listing in ipairs(manager.listings) do
            if listing.farmId == farmId then
                forSale = forSale + listing.depotLiters
            end
        end
    end
    return {
        {value = tostring(waiting), sub = getText("uwm_sum_waitingSub")},
        {value = tostring(running), sub = getText("uwm_sum_runningSub")},
        {value = UWM.formatAmount(FillType.UNKNOWN, toCollect), sub = getText("uwm_sum_collectSub")},
        {value = UWM.formatAmount(FillType.UNKNOWN, forSale), sub = getText("uwm_sum_forSaleSub")}
    }
end

function UWMFrame.getListingTypeText(listing)
    return getText(listing:getIsOffer() and "uwm_type_forSale" or "uwm_type_wanted")
end

-- MARKET: farm | type | product | left | of | price | held
function UWMFrame.getMarketRow(listing)
    local UWM = UtilitiesWasteManagement
    local ft = listing.fillTypeIndex
    return {
        UWMManager.getFarmName(listing.farmId),
        UWMFrame.getListingTypeText(listing),
        UWM.getGoodName(ft),
        UWM.formatAmount(ft, listing.remaining),
        UWM.formatAmount(ft, listing.liters),
        UWMFrame.getPriceText(ft, listing.pricePer1000),
        getText(listing:getIsOffer() and "uwm_held_stock" or "uwm_held_money")
    }, 2, listing:getIsOffer() and UWMFrame.COLOR_GOOD or UWMFrame.COLOR_WARN
end

function UWMFrame.getListingStatusText(listing)
    if listing.state == LSTATE.OPEN then
        return getText("uwm_listing_open")
    elseif listing.state == LSTATE.DONE then
        return getText("uwm_listing_done")
    end
    return getText("uwm_listing_withdrawn")
end

-- MY ORDERS: # | type | product | left | of | deals | price | status
function UWMFrame.getOrderRow(listing)
    local UWM = UtilitiesWasteManagement
    local ft = listing.fillTypeIndex
    local color = UWMFrame.COLOR_GOOD
    if listing.state == LSTATE.DONE then
        color = UWMFrame.COLOR_DIM
    elseif listing.state == LSTATE.CANCELLED then
        color = UWMFrame.COLOR_WARN
    end
    return {
        UWMFrame.getListingNumber(listing),
        UWMFrame.getListingTypeText(listing),
        UWM.getGoodName(ft),
        listing:getIsOpen() and UWM.formatAmount(ft, listing.remaining) or "-",
        UWM.formatAmount(ft, listing.liters),
        tostring(listing.trades),
        UWMFrame.getPriceText(ft, listing.pricePer1000),
        UWMFrame.getListingStatusText(listing)
    }, 8, color
end

-- MY DEALS: # | day | farm | product | volume | amount | you | status
function UWMFrame.getDealRow(invoice, farmId)
    local UWM = UtilitiesWasteManagement
    return {
        UWMFrame.getInvoiceNumber(invoice),
        UWMFrame.getDayText(invoice.createdDay),
        UWMManager.getFarmName(invoice:getOtherFarmId(farmId)),
        UWM.getGoodName(invoice.fillTypeIndex),
        UWM.formatAmount(invoice.fillTypeIndex, invoice.liters),
        UWMFrame.getAmountText(invoice),
        getText(invoice.buyerFarmId == farmId and "uwm_role_bought" or "uwm_role_sold"),
        UWMFrame.getStatusText(invoice, farmId)
    }, 8, UWMFrame.getStatusColor(invoice, farmId)
end

-- MARKET, lower panel: farm | product | volume | amount | to collect
function UWMFrame.getOpenDealRow(invoice, farmId)
    local UWM = UtilitiesWasteManagement
    local ft = invoice.fillTypeIndex
    local toCollect = "-"
    if not invoice:getIsElectricity() then
        toCollect = UWM.formatAmount(ft, invoice.owedLiters)
        if invoice.sellerFarmId == farmId then
            toCollect = string.format(getText("uwm_cell_theyCollect"), toCollect)
        end
    end
    return {
        UWMManager.getFarmName(invoice:getOtherFarmId(farmId)),
        UWM.getGoodName(ft),
        UWM.formatAmount(ft, invoice.liters),
        UWMFrame.getAmountText(invoice),
        toCollect
    }
end

UWMFrame.BOARD_COLUMNS = {
    [UWMFrame.SUB_MY_ORDERS] = {"uwm_column_order", "uwm_column_type", "uwm_column_product", "uwm_column_left", "uwm_column_of",
        "uwm_column_deals", "uwm_column_price", "uwm_column_status"},
    [UWMFrame.SUB_MY_DEALS] = {"uwm_column_number", "uwm_column_day", "uwm_column_farm", "uwm_column_product", "uwm_column_volume",
        "uwm_column_amount", "uwm_column_you", "uwm_column_status"}
}

----------------------------------------------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------------------------------------------

local function button(inputAction, textKey, callback)
    return {inputAction = inputAction, text = textKey ~= nil and getText(textKey) or "", callback = callback}
end

function UWMFrame:initialize()
    self.backButtonInfo = {inputAction = InputAction.MENU_BACK}
    self.newButtonInfo = button(InputAction.MENU_ACTIVATE, "uwm_button_new", function() self:onClickNew() end)
    self.mainButtonInfo = button(InputAction.MENU_ACCEPT, nil, function() self:onClickMain() end)
    self.detailsButtonInfo = button(InputAction.MENU_EXTRA_1, "uwm_button_details", function() self:onClickDetails() end)
    self.secondButtonInfo = button(InputAction.MENU_EXTRA_2, nil, function() self:onClickSecond() end)
    self.depotButtonInfo = button(InputAction.MENU_CANCEL, "uwm_button_depot", function() self:onClickDepot() end)

    if self.headerIcon ~= nil then
        self.headerIcon:setImageFilename(UtilitiesWasteManagement.modDirectory .. UWMFrame.ICON_FILENAME)
        self.headerIcon:setImageUVs(nil, unpack(UWMFrame.getIconUVs()))
    end
    if self.mainPaging ~= nil then
        self.mainPaging:setTexts({getText("uwm_tab_incoming"), getText("uwm_tab_outgoing"), getText("uwm_tab_board")})
    end
    if self.boardPaging ~= nil then
        self.boardPaging:setTexts({getText("uwm_tab_market"), getText("uwm_tab_myOrders"), getText("uwm_tab_myDeals")})
    end
    if self.invoiceEmpty ~= nil then
        self.invoiceEmpty:setText(getText("uwm_empty_invoices"))
    end
    if self.marketEmpty ~= nil then
        self.marketEmpty:setText(getText("uwm_empty_market"))
    end
    if self.dealsEmpty ~= nil then
        self.dealsEmpty:setText(getText("uwm_empty_openDeals"))
    end

    self:updateButtons()
end

function UWMFrame:onGuiSetupFinished()
    UWMFrame:superClass().onGuiSetupFinished(self)
    UWMGui.applyStaticImages(self)
    for _, list in ipairs({self.invoiceList, self.marketList, self.dealsList, self.boardList}) do
        list:setDataSource(self)
        list:setDelegate(self)
    end
end

function UWMFrame:onFrameOpen(element)
    UWMFrame:superClass().onFrameOpen(self)
    local manager = UtilitiesWasteManagement.manager
    if manager ~= nil then
        manager:removeChangeListener(self)
        manager:addChangeListener(self.refresh, self)
    end
    if MessageType.MONEY_CHANGED ~= nil then
        g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.updateBalance, self)
    end
    self:showTab(self.tab, self.subTab)
end

function UWMFrame:onFrameClose()
    UWMFrame:superClass().onFrameClose(self)
    local manager = UtilitiesWasteManagement.manager
    if manager ~= nil then
        manager:removeChangeListener(self)
    end
    g_messageCenter:unsubscribeAll(self)
end

function UWMFrame:updateBalance()
    if self.balanceText ~= nil then
        local farmId = UtilitiesWasteManagement.getLocalFarmId()
        self.balanceText:setText(UtilitiesWasteManagement.formatMoney(UWMManager.getFarmBalance(farmId)))
    end
end

-- the list that belongs to the open tab
function UWMFrame:getActiveList()
    if self.tab ~= UWMFrame.TAB_BOARD then
        return self.invoiceList
    elseif self.subTab == UWMFrame.SUB_MARKET then
        return self.marketList
    end
    return self.boardList
end

-- the items of a list element as shown now
function UWMFrame:getItems(list)
    local lists = self.lists
    if list == self.invoiceList then
        return self.tab == UWMFrame.TAB_OUTGOING and lists.outgoing or lists.incoming
    elseif list == self.marketList then
        return lists.market
    elseif list == self.dealsList then
        return lists.openDeals
    elseif list == self.boardList then
        return self.subTab == UWMFrame.SUB_MY_ORDERS and lists.myOrders or lists.myDeals
    end
    return {}
end

local function setVisible(element, visible)
    if element ~= nil then
        element:setVisible(visible)
    end
end

function UWMFrame:showTab(tab, subTab)
    self.tab = tab
    self.subTab = subTab or self.subTab
    self.selected = nil

    local isBoard = tab == UWMFrame.TAB_BOARD
    local isMarket = isBoard and self.subTab == UWMFrame.SUB_MARKET
    local isBoardList = isBoard and not isMarket

    for i, tabButton in ipairs(self.mainTabs or {}) do
        tabButton:setSelected(i == tab)
    end
    for i, tabButton in ipairs(self.boardTabs or {}) do
        tabButton:setSelected(i == self.subTab)
    end
    if self.mainPaging ~= nil then
        self.mainPaging:setState(tab)
    end
    if self.boardPaging ~= nil then
        self.boardPaging:setState(self.subTab)
    end

    for _, element in ipairs({self.invoiceList, self.invoiceSlider, self.summaryBox}) do
        setVisible(element, not isBoard)
    end
    for _, element in ipairs({self.boardTabBox, self.boardTabLine, self.boardPaging}) do
        setVisible(element, isBoard)
    end
    for _, element in ipairs({self.marketHeader, self.marketHeaderLine, self.marketList, self.dealsHeader, self.dealsList}) do
        setVisible(element, isMarket)
    end
    for _, element in ipairs({self.boardHeader, self.boardHeaderLine, self.boardList, self.boardSlider}) do
        setVisible(element, isBoardList)
    end
    if isBoardList then
        for i, key in ipairs(UWMFrame.BOARD_COLUMNS[self.subTab]) do
            if self.boardColumns ~= nil and self.boardColumns[i] ~= nil then
                self.boardColumns[i]:setText(getText(key))
            end
        end
    end

    self:refresh()
    FocusManager:setFocus(self:getActiveList())
end

-- the summary cards and the counts on the tabs
function UWMFrame:updateSummary(manager, farmId)
    local summary = UWMFrame.getSummary(manager, farmId)
    for i, entry in ipairs(summary) do
        if self.sumValue ~= nil and self.sumValue[i] ~= nil then
            self.sumValue[i]:setText(entry.value)
            self.sumSub[i]:setText(entry.sub)
        end
    end
    local counts = {#self.lists.incoming, #self.lists.outgoing, #self.lists.myOrders}
    local keys = {"uwm_tab_incoming", "uwm_tab_outgoing", "uwm_tab_board"}
    for i, tabButton in ipairs(self.mainTabs or {}) do
        if tabButton.setText ~= nil and keys[i] ~= nil then
            tabButton:setText(string.format(getText("uwm_tab_count"), getText(keys[i]), counts[i]))
        end
    end
end

function UWMFrame:refresh()
    local farmId = UtilitiesWasteManagement.getLocalFarmId()
    local manager = UtilitiesWasteManagement.manager
    self.lists = UWMFrame.buildLists(manager, farmId)

    if self.managerText ~= nil then
        local key = UtilitiesWasteManagement.getLocalIsManager() and "uwm_managerYes" or "uwm_managerNo"
        self.managerText:setText(getText(key))
    end
    if self.depotText ~= nil then
        self.depotText:setText(UWMFrame.getDepotStatusText(farmId))
    end
    self:updateBalance()
    self:updateSummary(manager, farmId)

    -- keep the same item selected after a reload
    local selected = self.selected
    self.selected = nil
    for _, list in ipairs({self.invoiceList, self.marketList, self.dealsList, self.boardList}) do
        list:reloadData()
    end
    local active = self:getActiveList()
    local items = self:getItems(active)
    if selected ~= nil and active.setSelectedItem ~= nil then
        for index, item in ipairs(items) do
            if item.id == selected.id and item.isListing == selected.isListing then
                active:setSelectedItem(1, index, nil, true)
                self.selected = item
            end
        end
    end
    if self.selected == nil then
        self.selected = items[1]
    end

    local isBoard = self.tab == UWMFrame.TAB_BOARD
    local isMarket = isBoard and self.subTab == UWMFrame.SUB_MARKET
    setVisible(self.invoiceEmpty, not isBoard and #items == 0)
    setVisible(self.marketEmpty, isMarket and #items == 0)
    setVisible(self.dealsEmpty, isMarket and #self.lists.openDeals == 0)
    setVisible(self.boardEmpty, isBoard and not isMarket and #items == 0)
    if self.boardEmpty ~= nil then
        self.boardEmpty:setText(getText(self.subTab == UWMFrame.SUB_MY_ORDERS and "uwm_empty_myOrders" or "uwm_empty_myDeals"))
    end

    self:updateButtons()
end

-- what the buttons do for the selection (everyone gets Details; only the farm manager the rest):
--   incoming, waiting:  Accept (and pay) / Decline        sent, waiting: Withdraw     running: End and refund
--   finished:           Delete (one, or all finished)     market: Buy / Sell to them     my open order: Withdraw
-- returns mainKey or nil, secondKey or nil (l10n keys of the button texts)
function UWMFrame.getActions(item, farmId, isManager)
    if item == nil or not isManager then
        return nil, nil
    end
    if item.isListing then
        if item.farmId ~= farmId then
            if item:getIsOpen() then
                return item:getIsOffer() and "uwm_button_buy" or "uwm_button_sellTo", nil
            end
            return nil, nil
        end
        return nil, item:getIsOpen() and "uwm_button_withdraw" or "uwm_button_delete"
    end
    if item.state == STATE.PENDING then
        if item.creatorFarmId ~= farmId then
            return item.buyerFarmId == farmId and "uwm_button_acceptPay" or "uwm_button_accept", "uwm_button_decline"
        end
        return nil, "uwm_button_withdraw"
    elseif item.state == STATE.ACTIVE then
        return nil, "uwm_button_end"
    end
    return nil, "uwm_button_delete"
end

function UWMFrame:updateButtons()
    local buttons = {self.backButtonInfo}
    local farmId = UtilitiesWasteManagement.getLocalFarmId()
    local isManager = UtilitiesWasteManagement.getLocalIsManager()
    local item = self.selected

    if isManager then
        self.newButtonInfo.text = getText("uwm_button_new")
        table.insert(buttons, self.newButtonInfo)
    end
    if item ~= nil then
        local mainKey, secondKey = UWMFrame.getActions(item, farmId, isManager)
        if mainKey ~= nil then
            self.mainButtonInfo.text = getText(mainKey)
            table.insert(buttons, self.mainButtonInfo)
        end
        table.insert(buttons, self.detailsButtonInfo)
        if secondKey ~= nil then
            self.secondButtonInfo.text = getText(secondKey)
            table.insert(buttons, self.secondButtonInfo)
        end
    end
    if #UWMFrame.getDepotOptions(farmId, isManager, UWMFrame.getLocalIsAdmin()) > 0 then
        table.insert(buttons, self.depotButtonInfo)
    end

    self.menuButtons = buttons
    self:setMenuButtonInfo(buttons)
    self:setMenuButtonInfoDirty()
end

-- SmoothList data source

function UWMFrame:getNumberOfSections()
    return 1
end

function UWMFrame:getNumberOfItemsInSection(list, section)
    return #self:getItems(list)
end

local function fillCells(cell, texts, colorIndex, color)
    for i, text in ipairs(texts) do
        local element = cell:getAttribute("c" .. i)
        if element ~= nil then
            element:setText(text)
            if element.setTextColor ~= nil and element.textColor ~= nil then
                -- remember the profile color once, cells are reused for other rows
                element.uwmDefaultColor = element.uwmDefaultColor or {unpack(element.textColor)}
                local c = (i == colorIndex and color) or element.uwmDefaultColor
                element:setTextColor(c[1], c[2], c[3], c[4])
            end
        end
    end
end

function UWMFrame.fillInvoiceCard(cell, card)
    UWMGui.applyStaticImages(cell)
    UWMGui.setIcon(cell:getAttribute("icon"), card.icon)
    cell:getAttribute("title"):setText(card.title)
    cell:getAttribute("sub"):setText(card.sub)
    local status = cell:getAttribute("status")
    status:setText(card.status)
    UWMGui.setTextColor(status, card.statusColor)
    cell:getAttribute("amount"):setText(card.amount)
end

function UWMFrame:populateCellForItemInSection(list, section, index, cell)
    local item = self:getItems(list)[index]
    if item == nil then
        return
    end
    local farmId = UtilitiesWasteManagement.getLocalFarmId()
    if list == self.invoiceList then
        UWMFrame.fillInvoiceCard(cell, UWMFrame.getInvoiceCard(item, farmId))
    elseif list == self.marketList then
        fillCells(cell, UWMFrame.getMarketRow(item))
    elseif list == self.dealsList then
        fillCells(cell, UWMFrame.getOpenDealRow(item, farmId))
    elseif self.subTab == UWMFrame.SUB_MY_ORDERS then
        fillCells(cell, UWMFrame.getOrderRow(item))
    else
        fillCells(cell, UWMFrame.getDealRow(item, farmId))
    end
end

-- SmoothList delegate

function UWMFrame:onListSelectionChanged(list, section, index)
    if list ~= self:getActiveList() then
        return
    end
    self.selected = self:getItems(list)[index]
    self:updateButtons()
end

-- Tabs (the tab buttons and the arrows of the paging elements)

function UWMFrame:onClickTabIncoming()
    self:showTab(UWMFrame.TAB_INCOMING)
end

function UWMFrame:onClickTabOutgoing()
    self:showTab(UWMFrame.TAB_OUTGOING)
end

function UWMFrame:onClickTabBoard()
    self:showTab(UWMFrame.TAB_BOARD)
end

function UWMFrame:onClickTabMarket()
    self:showTab(UWMFrame.TAB_BOARD, UWMFrame.SUB_MARKET)
end

function UWMFrame:onClickTabMyOrders()
    self:showTab(UWMFrame.TAB_BOARD, UWMFrame.SUB_MY_ORDERS)
end

function UWMFrame:onClickTabMyDeals()
    self:showTab(UWMFrame.TAB_BOARD, UWMFrame.SUB_MY_DEALS)
end

function UWMFrame:onClickMainPaging(state)
    if state ~= self.tab then
        self:showTab(state)
    end
end

function UWMFrame:onClickBoardPaging(state)
    if state ~= self.subTab then
        self:showTab(UWMFrame.TAB_BOARD, state)
    end
end

-- Buttons

-- the UWM CO-OP dialog: invoice / request / standing buy or sell order, on every tab
function UWMFrame:onClickNew()
    UWMCoopDialog.show()
end

function UWMFrame:onClickMain()
    local item = self.selected
    if item == nil then
        return
    end
    if item.isListing then
        UWMWizard.startTrade(item)
    else
        UWMWizard.startAccept(item)
    end
end

function UWMFrame:onClickDetails()
    local item = self.selected
    if item == nil then
        return
    end
    local farmId = UtilitiesWasteManagement.getLocalFarmId()
    if item.isListing then
        InfoDialog.show(UWMFrame.getListingDetailsText(item, farmId))
    else
        InfoDialog.show(UWMFrame.getDetailsText(item, farmId))
    end
end

local function confirm(target, text, onYes)
    YesNoDialog.show(function(_, yes)
        if yes then
            onYes()
        end
    end, target, text)
end

-- the C button: decline / withdraw / end / delete, whatever fits the selection
function UWMFrame:onClickSecond()
    local item = self.selected
    if item == nil then
        return
    end
    local _, secondKey = UWMFrame.getActions(item, UtilitiesWasteManagement.getLocalFarmId(), true)
    local ACTION = UWMManager.ACTION

    if secondKey == "uwm_button_delete" then
        self:askDelete(item)
    elseif item.isListing then
        local key = item:getIsOffer() and "uwm_confirm_withdrawOffer" or "uwm_confirm_withdrawWanted"
        confirm(self, string.format(getText(key), UtilitiesWasteManagement.formatMoney(item:getHeldMoney())), function()
            UWMRequestEvent.sendRequest(ACTION.WITHDRAW_LISTING, {listingId = item.id})
        end)
    elseif secondKey == "uwm_button_decline" then
        confirm(self, getText("uwm_confirm_decline"), function()
            UWMRequestEvent.sendRequest(ACTION.DECLINE, {invoiceId = item.id})
        end)
    else
        local key = "uwm_confirm_withdraw"
        if item.state == STATE.ACTIVE then
            key = item:getIsElectricity() and "uwm_confirm_endContract" or "uwm_confirm_end"
        end
        confirm(self, getText(key), function()
            UWMRequestEvent.sendRequest(ACTION.CANCEL, {invoiceId = item.id})
        end)
    end
end

-- delete this one, or everything finished (Clear history)
function UWMFrame:askDelete(item)
    local manager = UtilitiesWasteManagement.manager
    local count = manager ~= nil and UWMFrame.getFinishedCount(manager, UtilitiesWasteManagement.getLocalFarmId()) or 0
    local options = {getText("uwm_delete_one"), string.format(getText("uwm_delete_all"), count)}
    local ACTION = UWMManager.ACTION
    OptionDialog.show(function(index)
        if index == 1 then
            if item.isListing then
                UWMRequestEvent.sendRequest(ACTION.DELETE_LISTING, {listingId = item.id})
            else
                UWMRequestEvent.sendRequest(ACTION.DELETE, {invoiceId = item.id})
            end
        elseif index == 2 then
            confirm(self, string.format(getText("uwm_confirm_clearHistory"), count), function()
                UWMRequestEvent.sendRequest(ACTION.CLEAR_HISTORY, {})
            end)
        end
    end, getText("uwm_button_delete"), getText("uwm_delete_question"), options)
end

-- everything about one invoice, for the Details box
-- discount: the percent and the money it takes off, worded for the seller or the buyer, then what is paid.
-- A set amount: worked out from the liters (per delivery on a contract); "all of it": from what was paid so far.
function UWMFrame.addDiscountLines(lines, invoice, farmId)
    if invoice.discountPercent <= 0 then
        return
    end
    local UWM = UtilitiesWasteManagement
    local isBuyer = invoice.buyerFarmId == farmId
    local discount, paid
    if invoice.amountMode == UWMInvoice.AMOUNT.FIXED then
        discount, paid = invoice:getDiscount(invoice.liters), invoice:getPrice(invoice.liters)
    else
        discount, paid = invoice:getDiscountOnPaid(invoice.totalMoney), invoice.totalMoney
    end
    local percent = UWMManager.formatPercent(invoice.discountPercent)
    table.insert(lines, string.format(getText(isBuyer and "uwm_details_discountBuyer" or "uwm_details_discountSeller"),
        percent, UWM.formatMoney(discount)))
    table.insert(lines, string.format(getText(isBuyer and "uwm_details_youPay" or "uwm_details_buyerPays"), UWM.formatMoney(paid)))
end

function UWMFrame.getDetailsText(invoice, farmId)
    local UWM = UtilitiesWasteManagement
    local ft = invoice.fillTypeIndex
    local isElectricity = invoice:getIsElectricity()
    local lines = {}
    local function add(key, ...)
        table.insert(lines, string.format(getText(key), ...))
    end

    add("uwm_details_title", invoice.id, UWM.getGoodName(ft))
    add("uwm_details_seller", UWMManager.getFarmName(invoice.sellerFarmId))
    add("uwm_details_buyer", UWMManager.getFarmName(invoice.buyerFarmId))
    if invoice.listingId > 0 then
        add("uwm_details_fromListing", invoice.listingId)
    end
    table.insert(lines, "")

    local ordered = invoice.amountMode == UWMInvoice.AMOUNT.ALL and getText("uwm_amount_all") or UWM.formatAmount(ft, invoice.liters)
    add("uwm_details_ordered", ordered)
    add("uwm_details_price", UWMFrame.getPriceText(ft, invoice.pricePer1000))
    UWMFrame.addDiscountLines(lines, invoice, farmId)
    add("uwm_details_repeats", UWMFrame.getRepeatText(invoice))
    if invoice.reserve then
        table.insert(lines, getText("uwm_summary_reserved"))
    end
    table.insert(lines, "")

    if isElectricity then
        add("uwm_details_delivered", UWM.formatAmount(ft, invoice.totalLiters))
    else
        add("uwm_details_paidFor", UWM.formatAmount(ft, invoice.totalLiters + invoice.owedLiters + invoice.refundedLiters))
        add("uwm_details_collected", UWM.formatAmount(ft, invoice.totalLiters))
        if invoice.owedLiters > 0.5 then
            add("uwm_details_toCollect", UWM.formatAmount(ft, invoice.owedLiters))
        end
        if invoice.refundedLiters > 0.5 then
            add("uwm_details_refundedLiters", UWM.formatAmount(ft, invoice.refundedLiters))
        end
    end
    add("uwm_details_buyerPaid", UWM.formatMoney(invoice.totalMoney + invoice.totalRefund))
    add("uwm_details_refunded", UWM.formatMoney(invoice.totalRefund))
    add("uwm_details_sellerGot", UWM.formatMoney(invoice.totalMoney))
    if isElectricity and invoice.amountMode == UWMInvoice.AMOUNT.FIXED and invoice.state ~= STATE.PENDING
        and invoice.totalLiters < invoice.liters - 0.5 then
        table.insert(lines, getText("uwm_details_electricityShort"))
    end
    table.insert(lines, "")

    add("uwm_details_status", UWMFrame.getStatusText(invoice, farmId))
    add("uwm_details_sentDay", invoice.createdDay)
    if invoice.finishedDay > 0 then
        add("uwm_details_finishedDay", invoice.finishedDay)
    end

    return table.concat(lines, "\n")
end

-- everything about one standing order
function UWMFrame.getListingDetailsText(listing, farmId)
    local UWM = UtilitiesWasteManagement
    local ft = listing.fillTypeIndex
    local lines = {}
    local function add(key, ...)
        table.insert(lines, string.format(getText(key), ...))
    end

    add("uwm_details_listingTitle", listing.id, UWM.getGoodName(ft))
    add(listing:getIsOffer() and "uwm_details_listingOffer" or "uwm_details_listingWanted", UWMManager.getFarmName(listing.farmId))
    table.insert(lines, "")
    add("uwm_details_listingTotal", UWM.formatAmount(ft, listing.liters))
    add("uwm_details_price", UWMFrame.getPriceText(ft, listing.pricePer1000))
    if listing:getIsOpen() then
        add("uwm_details_listingLeft", UWM.formatAmount(ft, listing.remaining))
    end
    add("uwm_details_listingTraded", UWM.formatAmount(ft, listing.tradedLiters), listing.trades)
    add("uwm_details_listingMoney", UWM.formatMoney(listing.totalMoney))
    if listing:getIsOpen() then
        if listing:getIsOffer() then
            add("uwm_details_listingStockHeld", UWM.formatAmount(ft, listing.remaining))
        else
            add("uwm_details_listingMoneyHeld", UWM.formatMoney(listing:getHeldMoney()))
        end
    end
    table.insert(lines, "")
    add("uwm_details_status", UWMFrame.getListingStatusText(listing))
    add("uwm_details_postedDay", listing.createdDay)
    if listing.finishedDay > 0 then
        add("uwm_details_finishedDay", listing.finishedDay)
    end

    return table.concat(lines, "\n")
end


----------------------------------------------------------------------------------------------------------------
-- Depot
----------------------------------------------------------------------------------------------------------------

function UWMFrame.getLocalIsAdmin()
    local mission = g_currentMission
    if not mission.missionDynamicInfo.isMultiplayer then
        return true
    end
    return mission:getIsServer() or mission.isMasterUser == true
end

-- one line for the header
function UWMFrame.getDepotStatusText(farmId)
    local UWM = UtilitiesWasteManagement
    local manager = UWM.manager
    if manager == nil or not manager:getHasDepot() then
        return UWM.getText("uwm_depot_none")
    end
    if not UWMManager.getIsTradingFarm(farmId) then
        return ""
    end
    local share = UWM.formatMoney(manager:getDailyShare(farmId))
    if manager:getOwnsDepot(farmId) then
        return string.format(UWM.getText("uwm_depot_owner"), share)
    end
    local member = manager:getMember(farmId)
    if member == nil then
        return UWM.getText("uwm_depot_waiting")
    elseif member.state == UWMManager.MEMBER.OFFERED then
        return string.format(UWM.getText("uwm_depot_offered"), share)
    elseif member.state == UWMManager.MEMBER.DECLINED and member.rejoinWait > 0 then
        return string.format(UWM.getText("uwm_depot_left"), member.rejoinWait)
    elseif member.state == UWMManager.MEMBER.DECLINED then
        return UWM.getText("uwm_depot_declined")
    elseif member.suspended then
        return string.format(UWM.getText("uwm_depot_suspended"), UWM.formatMoney(member.arrears))
    elseif member.arrears >= 0.5 then
        return string.format(UWM.getText("uwm_depot_memberOwes"), share, UWM.formatMoney(member.arrears))
    end
    return string.format(UWM.getText("uwm_depot_member"), share)
end

-- what the Depot button offers this player: list of {text, action, flag}
function UWMFrame.getDepotOptions(farmId, isManager, isAdmin)
    local UWM = UtilitiesWasteManagement
    local manager = UWM.manager
    local options = {}
    if manager == nil then
        return options
    end
    local ACTION = UWMManager.ACTION
    if isManager and manager:getHasDepot() and not manager:getOwnsDepot(farmId) then
        local member = manager:getMember(farmId)
        local share = UWM.formatMoney(manager:getDailyShare(farmId))
        if member ~= nil and member.state == UWMManager.MEMBER.OFFERED then
            table.insert(options, {text = string.format(UWM.getText("uwm_depot_optionJoin"), share), action = ACTION.JOIN_DEPOT})
            table.insert(options, {text = UWM.getText("uwm_depot_optionDecline"), action = ACTION.DECLINE_DEPOT})
        elseif member ~= nil and member.state == UWMManager.MEMBER.DECLINED and member.rejoinWait == 0 then
            table.insert(options, {text = UWM.getText("uwm_depot_optionRequest"), action = ACTION.REQUEST_DEPOT})
        elseif member ~= nil and member.state == UWMManager.MEMBER.MEMBER then
            table.insert(options, {text = string.format(UWM.getText("uwm_depot_optionLeave"), UWMManager.REJOIN_WAIT_MONTHS),
                action = ACTION.LEAVE_DEPOT})
        end
    end
    if isManager then
        local member = manager:getMember(farmId)
        if member ~= nil and member.arrears >= 0.5 then
            table.insert(options, {text = string.format(UWM.getText("uwm_depot_optionPay"), UWM.formatMoney(member.arrears)), action = ACTION.PAY_ARREARS})
        end
    end
    if isAdmin then
        local key = manager.allowMultipleDepots and "uwm_depot_optionOneOnly" or "uwm_depot_optionMultiple"
        table.insert(options, {text = UWM.getText(key), action = ACTION.SET_MULTIPLE_DEPOTS, flag = not manager.allowMultipleDepots})
    end
    return options
end

function UWMFrame:onClickDepot()
    local UWM = UtilitiesWasteManagement
    local farmId = UWM.getLocalFarmId()
    local options = UWMFrame.getDepotOptions(farmId, UWM.getLocalIsManager(), UWMFrame.getLocalIsAdmin())
    if #options == 0 then
        return
    end
    local texts = {}
    for _, option in ipairs(options) do
        table.insert(texts, option.text)
    end
    OptionDialog.show(function(index)
        local option = options[index]
        if option == nil then
            return
        end
        if option.action == UWMManager.ACTION.LEAVE_DEPOT then
            confirm(self, string.format(UWM.getText("uwm_confirm_leaveDepot"), UWMManager.REJOIN_WAIT_MONTHS), function()
                UWMRequestEvent.sendRequest(option.action, {})
            end)
        else
            UWMRequestEvent.sendRequest(option.action, {flag = option.flag})
        end
    end, UWM.getText("uwm_depot_title"), UWMFrame.getDepotStatusText(farmId), texts)
end
