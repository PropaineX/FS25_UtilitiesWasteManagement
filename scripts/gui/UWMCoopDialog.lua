-- Utilities & Waste Management: the UWM CO-OP dialog, opened by "New" on the Utilities page.
-- Invoice a farm / request an invoice / standing buy order / standing sell order -> the form (UWMOrderDialog).
-- Author: PropaineX

UWMCoopDialog = {}
local UWMCoopDialog_mt = Class(UWMCoopDialog, MessageDialog)

UWMCoopDialog.NAME = "UWMCoopDialog"

function UWMCoopDialog.new(target, customMt)
    return MessageDialog.new(target, customMt or UWMCoopDialog_mt)
end

function UWMCoopDialog.register()
    local dialog = UWMCoopDialog.new()
    g_gui:loadGui(UtilitiesWasteManagement.modDirectory .. "gui/UWMCoopDialog.xml", UWMCoopDialog.NAME, dialog)
    UWMCoopDialog.instance = dialog
end

function UWMCoopDialog.show()
    if UWMCoopDialog.instance ~= nil then
        g_gui:showDialog(UWMCoopDialog.NAME)
    end
end

function UWMCoopDialog:onGuiSetupFinished()
    UWMCoopDialog:superClass().onGuiSetupFinished(self)
    UWMGui.applyStaticImages(self.dialogElement)
end

function UWMCoopDialog:onOpen()
    UWMCoopDialog:superClass().onOpen(self)
    for _, name in ipairs(UWMCoopDialog.CARDS) do
        self:setCardFocused(name, false)
    end
    if self.cardBill ~= nil then
        FocusManager:setFocus(self.cardBill)
        self:setCardFocused("Bill", true)
    end
end

UWMCoopDialog.CARDS = {"Bill", "Request", "Wanted", "Offer"}

-- focused card: green outline + fill, solid green tile with a dark icon, green arrow (CO-OP v6 mock-up)
function UWMCoopDialog:setCardFocused(name, focused)
    if self["focus" .. name] ~= nil then
        self["focus" .. name]:setVisible(focused)
    end
    UWMGui.setColor(self["tile" .. name], focused and "green" or "tile")
    UWMGui.setColor(self["icon" .. name], focused and "dark" or "greenLight")
    UWMGui.setColor(self["arrow" .. name], focused and "greenLight" or "dim")
end

local function getCardName(element)
    local id = element ~= nil and element.id or nil
    return id ~= nil and id:match("^card(%a+)$") or nil
end

function UWMCoopDialog:onCardFocus(element)
    local name = getCardName(element)
    if name ~= nil then
        -- one highlighted card at a time (mouse over one, keyboard focus on another)
        for _, other in ipairs(UWMCoopDialog.CARDS) do
            self:setCardFocused(other, other == name)
        end
    end
end

function UWMCoopDialog:onCardLeave(element)
    local name = getCardName(element)
    if name ~= nil and FocusManager:getFocusedElement() ~= element then
        self:setCardFocused(name, false)
        -- the keyboard-focused card lights up again
        local focused = getCardName(FocusManager:getFocusedElement())
        if focused ~= nil then
            self:setCardFocused(focused, true)
        end
    end
end

function UWMCoopDialog:choose(mode)
    self:close()
    UWMOrderDialog.show(mode)
end

function UWMCoopDialog:onClickBill()
    self:choose(UWMWizard.FORM.BILL)
end

function UWMCoopDialog:onClickRequest()
    self:choose(UWMWizard.FORM.REQUEST)
end

function UWMCoopDialog:onClickWanted()
    self:choose(UWMWizard.FORM.WANTED)
end

function UWMCoopDialog:onClickOffer()
    self:choose(UWMWizard.FORM.OFFER)
end

function UWMCoopDialog:onClickBack()
    self:close()
end
