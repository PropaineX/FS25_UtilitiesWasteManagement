-- Utilities & Waste Management: the "Utilities" page in the ESC menu.
-- Sections: waiting for your answer, sent by you, active, history. Only the farm manager gets the trade buttons.
-- Author: PropaineX

UWMFrame = {}
local UWMFrame_mt = Class(UWMFrame, TabbedMenuFrameElement)

UWMFrame.PAGE_NAME = "pageUtilitiesWasteManagement"
UWMFrame.TAB_ICON_SLICE = "gui.icon_ingameMenu_contracts"

UWMFrame.SECTION_INCOMING = 1
UWMFrame.SECTION_SENT = 2
UWMFrame.SECTION_ACTIVE = 3
UWMFrame.SECTION_HISTORY = 4
UWMFrame.SECTION_TITLES = {"uwm_section_incoming", "uwm_section_sent", "uwm_section_active", "uwm_section_history"}

UWMFrame.instance = nil

local STATE = UWMInvoice.STATE

function UWMFrame.new()
    local self = UWMFrame:superClass().new(nil, UWMFrame_mt)

    self.hasCustomMenuButtons = true
    self.sections = {{}, {}, {}, {}}
    self.selectedInvoice = nil

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

    inGameMenu:registerPage(frame, position, function()
        return true
    end)
    inGameMenu:addPageTab(frame, nil, nil, UWMFrame.TAB_ICON_SLICE)
    if inGameMenu.pageFrames ~= nil then
        moveToPosition(inGameMenu.pageFrames, frame, position, function(element) return element end)
    end
    inGameMenu:rebuildTabList()

    frame:initialize()
    UWMFrame.instance = frame
    print(UtilitiesWasteManagement.TAG .. " Utilities page added to the ESC menu")
end

function UWMFrame.unregister()
    UWMFrame.instance = nil
end

----------------------------------------------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------------------------------------------

function UWMFrame:initialize()
    local getText = UtilitiesWasteManagement.getText

    self.backButtonInfo = {inputAction = InputAction.MENU_BACK}
    self.newButtonInfo = {
        inputAction = InputAction.MENU_ACTIVATE,
        text = getText("uwm_button_new"),
        callback = function()
            self:onClickNew()
        end
    }
    self.acceptButtonInfo = {
        inputAction = InputAction.MENU_ACCEPT,
        text = getText("uwm_button_accept"),
        callback = function()
            self:onClickAccept()
        end
    }
    self.declineButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_1,
        text = getText("uwm_button_decline"),
        callback = function()
            self:onClickDecline()
        end
    }
    self.cancelButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_2,
        text = getText("uwm_button_cancel"),
        callback = function()
            self:onClickCancel()
        end
    }
    -- Details sits on MENU_ACCEPT, except for invoices waiting for your answer (Accept is there)
    self.detailsButtonInfo = {
        inputAction = InputAction.MENU_ACCEPT,
        text = getText("uwm_button_details"),
        callback = function()
            self:onClickDetails()
        end
    }
    self.detailsIncomingButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_2,
        text = getText("uwm_button_details"),
        callback = function()
            self:onClickDetails()
        end
    }
    self.deleteButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_1,
        text = getText("uwm_button_delete"),
        callback = function()
            self:onClickDelete()
        end
    }
    self.clearHistoryButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_2,
        text = getText("uwm_button_clearHistory"),
        callback = function()
            self:onClickClearHistory()
        end
    }

    self:updateButtons()
end

function UWMFrame:onGuiSetupFinished()
    UWMFrame:superClass().onGuiSetupFinished(self)
    self.invoiceList:setDataSource(self)
    self.invoiceList:setDelegate(self)
end

function UWMFrame:onFrameOpen(element)
    UWMFrame:superClass().onFrameOpen(self)
    local manager = UtilitiesWasteManagement.manager
    if manager ~= nil then
        manager:removeChangeListener(self)
        manager:addChangeListener(self.refresh, self)
    end
    self:refresh()
    FocusManager:setFocus(self.invoiceList)
end

function UWMFrame:onFrameClose()
    UWMFrame:superClass().onFrameClose(self)
    local manager = UtilitiesWasteManagement.manager
    if manager ~= nil then
        manager:removeChangeListener(self)
    end
end

function UWMFrame:refresh()
    local farmId = UtilitiesWasteManagement.getLocalFarmId()
    self.sections = {{}, {}, {}, {}}

    local manager = UtilitiesWasteManagement.manager
    if manager ~= nil then
        for _, invoice in ipairs(manager:getInvoices()) do
            if (invoice.sellerFarmId == farmId or invoice.buyerFarmId == farmId) and not invoice:getIsHiddenFor(farmId) then
                local section
                if invoice.state == STATE.PENDING then
                    section = invoice.creatorFarmId == farmId and UWMFrame.SECTION_SENT or UWMFrame.SECTION_INCOMING
                elseif invoice.state == STATE.ACTIVE then
                    section = UWMFrame.SECTION_ACTIVE
                else
                    section = UWMFrame.SECTION_HISTORY
                end
                table.insert(self.sections[section], invoice)
            end
        end
    end

    -- newest first in the history
    local history = self.sections[UWMFrame.SECTION_HISTORY]
    for i = 1, math.floor(#history / 2) do
        history[i], history[#history - i + 1] = history[#history - i + 1], history[i]
    end

    if self.managerText ~= nil then
        local key = UtilitiesWasteManagement.getLocalIsManager() and "uwm_managerYes" or "uwm_managerNo"
        self.managerText:setText(UtilitiesWasteManagement.getText(key))
    end

    -- keep the same invoice selected after a reload
    local selected = self.selectedInvoice
    self.selectedInvoice = nil
    self.invoiceList:reloadData()
    if selected ~= nil and self.invoiceList.setSelectedItem ~= nil then
        for section, invoices in ipairs(self.sections) do
            for index, invoice in ipairs(invoices) do
                if invoice.id == selected.id then
                    self.invoiceList:setSelectedItem(section, index, nil, true)
                    self.selectedInvoice = invoice
                end
            end
        end
    end
    self:updateButtons()
end

-- buttons per selection (everyone sees Details; only the farm manager gets the rest):
--   waiting for your answer: Accept, Decline, Details      sent by you / active: Details, Withdraw / End
--   history: Details, Delete, Clear history
function UWMFrame:updateButtons()
    local buttons = {self.backButtonInfo}
    local farmId = UtilitiesWasteManagement.getLocalFarmId()
    local isManager = UtilitiesWasteManagement.getLocalIsManager()
    local invoice = self.selectedInvoice
    local isIncoming = invoice ~= nil and invoice.state == STATE.PENDING and invoice.creatorFarmId ~= farmId

    if isManager then
        table.insert(buttons, self.newButtonInfo)
    end

    if invoice ~= nil then
        if isIncoming and isManager then
            table.insert(buttons, self.acceptButtonInfo)
            table.insert(buttons, self.declineButtonInfo)
            table.insert(buttons, self.detailsIncomingButtonInfo)
        else
            table.insert(buttons, self.detailsButtonInfo)
        end

        if isManager and not isIncoming then
            if invoice.state == STATE.PENDING then
                self.cancelButtonInfo.text = UtilitiesWasteManagement.getText("uwm_button_withdraw")
                table.insert(buttons, self.cancelButtonInfo)
            elseif invoice.state == STATE.ACTIVE then
                self.cancelButtonInfo.text = UtilitiesWasteManagement.getText("uwm_button_end")
                table.insert(buttons, self.cancelButtonInfo)
            elseif invoice:getIsFinished() then
                table.insert(buttons, self.deleteButtonInfo)
                table.insert(buttons, self.clearHistoryButtonInfo)
            end
        end
    elseif isManager and #self.sections[UWMFrame.SECTION_HISTORY] > 0 then
        table.insert(buttons, self.clearHistoryButtonInfo)
    end

    self.menuButtons = buttons
    self:setMenuButtonInfo(buttons)
    self:setMenuButtonInfoDirty()
end

-- SmoothList data source

function UWMFrame:getNumberOfSections()
    return #self.sections
end

function UWMFrame:getTitleForSectionHeader(list, section)
    return string.format("%s (%d)", UtilitiesWasteManagement.getText(UWMFrame.SECTION_TITLES[section]), #self.sections[section])
end

function UWMFrame:getNumberOfItemsInSection(list, section)
    return #self.sections[section]
end

function UWMFrame:populateCellForItemInSection(list, section, index, cell)
    local invoice = self.sections[section][index]
    if invoice == nil then
        return
    end
    local UWM = UtilitiesWasteManagement
    local farmId = UWM.getLocalFarmId()
    local isBuyer = invoice.buyerFarmId == farmId

    cell:getAttribute("good"):setText(UWM.getGoodName(invoice.fillTypeIndex))
    cell:getAttribute("farm"):setText(UWMManager.getFarmName(invoice:getOtherFarmId(farmId)))
    cell:getAttribute("role"):setText(UWM.getText(isBuyer and "uwm_role_buying" or "uwm_role_selling"))

    local amount
    if invoice.amountMode == UWMInvoice.AMOUNT.ALL then
        amount = UWM.getText("uwm_amount_all")
    else
        amount = UWM.formatAmount(invoice.fillTypeIndex, invoice.liters)
    end
    cell:getAttribute("amount"):setText(amount)

    local priceKey = invoice:getIsElectricity() and "uwm_pricePer1000kWh" or "uwm_pricePer1000"
    cell:getAttribute("price"):setText(string.format(UWM.getText(priceKey), UWM.formatMoney(invoice.pricePer1000)))

    local repeatKey = "uwm_repeat_once"
    if invoice.repeatDays == UWMInvoice.REPEAT_DAILY then
        repeatKey = "uwm_repeat_daily"
    elseif invoice.repeatDays == UWMInvoice.REPEAT_WEEKLY then
        repeatKey = "uwm_repeat_weekly"
    end
    cell:getAttribute("repeat"):setText(UWM.getText(repeatKey))

    cell:getAttribute("status"):setText(UWMFrame.getStatusText(invoice))
end

function UWMFrame.getStatusText(invoice)
    local UWM = UtilitiesWasteManagement
    local parts = {}

    if invoice.state == STATE.PENDING then
        table.insert(parts, UWM.getText("uwm_state_pending"))
    elseif invoice.state == STATE.ACTIVE then
        if invoice:getIsElectricity() then
            table.insert(parts, string.format(UWM.getText("uwm_status_delivered"), UWM.formatAmount(invoice.fillTypeIndex, invoice.totalLiters)))
        else
            table.insert(parts, string.format(UWM.getText("uwm_status_toCollect"), UWM.formatAmount(invoice.fillTypeIndex, invoice.owedLiters)))
        end
    else
        local stateKeys = {[STATE.DONE] = "uwm_state_done", [STATE.DECLINED] = "uwm_state_declined", [STATE.CANCELLED] = "uwm_state_cancelled"}
        table.insert(parts, UWM.getText(stateKeys[invoice.state] or "uwm_state_done"))
        if invoice.totalLiters > 0 then
            table.insert(parts, UWM.formatAmount(invoice.fillTypeIndex, invoice.totalLiters))
        end
    end

    if invoice.reserve then
        table.insert(parts, UWM.getText("uwm_status_reserved"))
    end
    if invoice.totalRefund > 0 then
        table.insert(parts, string.format(UWM.getText("uwm_status_refunded"), UWM.formatMoney(invoice.totalRefund)))
    end
    if invoice.statusKey ~= "" and invoice.state == STATE.ACTIVE then
        table.insert(parts, UWM.getText(invoice.statusKey))
    end

    return table.concat(parts, ", ")
end

-- SmoothList delegate

function UWMFrame:onListSelectionChanged(list, section, index)
    local invoices = self.sections[section]
    self.selectedInvoice = invoices ~= nil and invoices[index] or nil
    self:updateButtons()
end

-- Buttons

function UWMFrame:onClickNew()
    UWMWizard.startNew()
end

function UWMFrame:onClickAccept()
    if self.selectedInvoice ~= nil then
        UWMWizard.startAccept(self.selectedInvoice)
    end
end

function UWMFrame:onClickDecline()
    local invoice = self.selectedInvoice
    if invoice ~= nil then
        YesNoDialog.show(function(_, yes)
            if yes then
                UWMRequestEvent.sendRequest(UWMManager.ACTION.DECLINE, {invoiceId = invoice.id})
            end
        end, self, UtilitiesWasteManagement.getText("uwm_confirm_decline"))
    end
end

function UWMFrame:onClickDetails()
    if self.selectedInvoice ~= nil then
        InfoDialog.show(UWMFrame.getDetailsText(self.selectedInvoice, UtilitiesWasteManagement.getLocalFarmId()))
    end
end

function UWMFrame:onClickDelete()
    local invoice = self.selectedInvoice
    if invoice ~= nil then
        YesNoDialog.show(function(_, yes)
            if yes then
                UWMRequestEvent.sendRequest(UWMManager.ACTION.DELETE, {invoiceId = invoice.id})
            end
        end, self, UtilitiesWasteManagement.getText("uwm_confirm_delete"))
    end
end

function UWMFrame:onClickClearHistory()
    local count = #self.sections[UWMFrame.SECTION_HISTORY]
    YesNoDialog.show(function(_, yes)
        if yes then
            UWMRequestEvent.sendRequest(UWMManager.ACTION.CLEAR_HISTORY, {})
        end
    end, self, string.format(UtilitiesWasteManagement.getText("uwm_confirm_clearHistory"), count))
end

-- everything about one invoice, for the Details box
function UWMFrame.getDetailsText(invoice, farmId)
    local UWM = UtilitiesWasteManagement
    local getText = UWM.getText
    local ft = invoice.fillTypeIndex
    local isElectricity = invoice:getIsElectricity()
    local lines = {}
    local function add(key, ...)
        table.insert(lines, string.format(getText(key), ...))
    end

    add("uwm_details_title", invoice.id, UWM.getGoodName(ft))
    add("uwm_details_seller", UWMManager.getFarmName(invoice.sellerFarmId))
    add("uwm_details_buyer", UWMManager.getFarmName(invoice.buyerFarmId))
    table.insert(lines, "")

    local ordered = invoice.amountMode == UWMInvoice.AMOUNT.ALL and getText("uwm_amount_all") or UWM.formatAmount(ft, invoice.liters)
    add("uwm_details_ordered", ordered)
    local priceKey = isElectricity and "uwm_pricePer1000kWh" or "uwm_pricePer1000"
    add("uwm_details_price", string.format(getText(priceKey), UWM.formatMoney(invoice.pricePer1000)))
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

    add("uwm_details_status", UWMFrame.getStatusText(invoice))
    add("uwm_details_sentDay", invoice.createdDay)
    if invoice.finishedDay > 0 then
        add("uwm_details_finishedDay", invoice.finishedDay)
    end

    return table.concat(lines, "\n")
end

function UWMFrame.getRepeatText(invoice)
    if invoice.repeatDays == UWMInvoice.REPEAT_DAILY then
        return UtilitiesWasteManagement.getText("uwm_repeat_daily")
    elseif invoice.repeatDays == UWMInvoice.REPEAT_WEEKLY then
        return UtilitiesWasteManagement.getText("uwm_repeat_weekly")
    end
    return UtilitiesWasteManagement.getText("uwm_repeat_once")
end

function UWMFrame:onClickCancel()
    local invoice = self.selectedInvoice
    if invoice ~= nil then
        local key = "uwm_confirm_withdraw"
        if invoice.state == STATE.ACTIVE then
            key = invoice:getIsElectricity() and "uwm_confirm_endContract" or "uwm_confirm_end"
        end
        YesNoDialog.show(function(_, yes)
            if yes then
                UWMRequestEvent.sendRequest(UWMManager.ACTION.CANCEL, {invoiceId = invoice.id})
            end
        end, self, UtilitiesWasteManagement.getText(key))
    end
end
