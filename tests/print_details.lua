-- prints the Details box text for two example invoices (used for the preview picture)
local A = UWMManager.ACTION
UtilitiesWasteManagement:loadMap("")
local M = UtilitiesWasteManagement.manager
farms[1].name, farms[2].name = "Farm A", "Farm B"
local function add(p) table.insert(g_currentMission.placeableSystem.placeables, p) return p end
add(newPlaceable(1, "spec_productionPoint", {productionPoint = {storage = newStorage({[FillType.ELECTRICCHARGE] = 4123}), outputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}, inputFillTypeIds = {}}}, "bga1"))
local malt = add(newPlaceable(2, "spec_productionPoint", {productionPoint = {storage = newStorage({[FillType.ELECTRICCHARGE] = 0}), inputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}, outputFillTypeIds = {}}}, "Malzfabrik"))
local barn = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 50000})}, "cowBarn"))
g_currentMission.environment.currentMonotonicDay = 138

local function make(ft, liters, price)
    local inv = UWMInvoice.new()
    inv.sellerFarmId, inv.buyerFarmId, inv.fillTypeIndex = 1, 2, ft
    inv.amountMode, inv.liters, inv.pricePer1000, inv.repeatDays = UWMInvoice.AMOUNT.FIXED, liters, price, 0
    M:handleRequest(A.CREATE, 10, {invoice = inv})
    return M.invoices[#M.invoices]
end

local power = make(FillType.ELECTRICCHARGE, 10000, 350)
M:handleRequest(A.ACCEPT, 20, {invoiceId = power.id, targets = {malt.uid}})
print("=====POWER")
print(UWMFrame.getDetailsText(power, 2))

local slurry = make(FillType.LIQUIDMANURE, 10000, 33)
slurry.reserve = true
M:handleRequest(A.ACCEPT, 20, {invoiceId = slurry.id, reserve = true})
newStation(barn, barn.spec_husbandry.storage):addFillLevelToFillableObject(newTanker(2, 4000), 1, FillType.LIQUIDMANURE, 9999, nil, ToolType.TRIGGER)
g_currentMission.environment.currentMonotonicDay = 139
M:handleRequest(A.CANCEL, 20, {invoiceId = slurry.id})
print("=====SLURRY")
print(UWMFrame.getDetailsText(slurry, 1))
return 0
