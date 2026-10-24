local A = UWMManager.ACTION
local M
local passed, failed = 0, 0
local function check(name, cond, info)
    if cond then passed = passed + 1 print("PASS " .. name)
    else failed = failed + 1 print("FAIL " .. name .. (info and ("  " .. tostring(info)) or "")) end
end
local function near(a, b) return math.abs(a - b) < 0.01 end

local function reset()
    g_currentMission.placeableSystem.placeables = {}
    for _, f in pairs(farms) do f.money = 10000 end
    notifications = {}
    UtilitiesWasteManagement:loadMap("")
    M = UtilitiesWasteManagement.manager
end
local function add(p) table.insert(g_currentMission.placeableSystem.placeables, p) return p end
local function order(user, sellerFarm, buyerFarm, ft, mode, liters, price, rep, reserve, targets)
    local inv = UWMInvoice.new()
    inv.sellerFarmId, inv.buyerFarmId, inv.fillTypeIndex = sellerFarm, buyerFarm, ft
    inv.amountMode, inv.liters, inv.pricePer1000, inv.repeatDays = mode, liters, price, rep or 0
    inv.reserve = reserve or false
    return M:handleRequest(A.CREATE, user, {invoice = inv, targets = targets})
end
local function last() return M.invoices[#M.invoices] end

-- 1. order of manure, fixed amount, collect part, end -> refund
reset()
local pit = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.MANURE] = 20000, [FillType.LIQUIDMANURE] = 0})}))
local ok, key = order(20, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 10000, 50)
check("order created", ok and last().state == UWMInvoice.STATE.PENDING, key)
local inv = last()
ok, key = M:handleRequest(A.ACCEPT, 20, {invoiceId = inv.id})
check("buyer can't accept own order", not ok and key == "uwm_error_ownInvoice", key)
ok, key = M:handleRequest(A.ACCEPT, 10, {invoiceId = inv.id})
check("seller accepts, buyer pays 500 up front", ok and near(farms[2].money, 9500) and near(farms[1].money, 10500), key)
check("10000 l owed", near(inv.owedLiters, 10000))
check("collectable 10000", near(M:getCollectableLiters(2, FillType.MANURE), 10000))
local got = M:collect(2, FillType.MANURE, 4000)
check("collect 4000 from seller stock", near(got, 4000) and near(pit.spec_husbandry.storage:getFillLevel(FillType.MANURE), 16000))
ok, key = M:handleRequest(A.CANCEL, 20, {invoiceId = inv.id})
check("buyer ends: 6000 l refunded = 300", ok and near(farms[2].money, 9800) and near(farms[1].money, 10200) and inv.state == UWMInvoice.STATE.CANCELLED, farms[2].money)
check("refund recorded", near(inv.totalRefund, 300))

-- 2. one-off finished by collecting everything
reset()
pit = add(newPlaceable(1, "spec_manureHeap", {manureHeap = newStorage({[FillType.MANURE] = 5000})}))
order(20, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 3000, 100)
inv = last(); M:handleRequest(A.ACCEPT, 10, {invoiceId = inv.id})
got = M:collect(2, FillType.MANURE, 99999)
check("collect stops at paid 3000", near(got, 3000) and near(pit.spec_manureHeap.manureHeap:getFillLevel(FillType.MANURE), 2000))
check("one-off done after full collection", inv.state == UWMInvoice.STATE.DONE)

-- 3. shortfall: stock runs out, rest refunded on end
reset()
pit = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 1000})}))
order(20, 1, 2, FillType.LIQUIDMANURE, UWMInvoice.AMOUNT.FIXED, 4000, 10)
inv = last(); M:handleRequest(A.ACCEPT, 10, {invoiceId = inv.id})
got = M:collect(2, FillType.LIQUIDMANURE, 4000)
check("only 1000 in stock collected", near(got, 1000) and near(inv.owedLiters, 3000))
ok = M:handleRequest(A.CANCEL, 10, {invoiceId = inv.id})
check("seller ends: buyer refunded 30", ok and near(farms[2].money, 10000 - 40 + 30))

-- 4. bill, all of it, reserve chosen by buyer at accept; seller's own loading blocked
reset()
pit = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 8000})}))
ok = order(10, 1, 2, FillType.LIQUIDMANURE, UWMInvoice.AMOUNT.ALL, 0, 20)   -- user 10 = farm 1 manager: a bill
inv = last()
check("bill created by seller", ok and inv:getIsBill())
ok, key = M:handleRequest(A.ACCEPT, 20, {invoiceId = inv.id, reserve = true})
check("all of it = 8000 at payment, 160 paid", ok and near(inv.owedLiters, 8000) and near(farms[2].money, 9840), key)
check("reserved 8000", near(M:getReservedLiters(1, FillType.LIQUIDMANURE), 8000))
local station = {isServer = true, owningPlaceable = pit}
local super = function(_, _, _, _, delta) return delta end
local r = UWMStock.addFillLevelToFillableObject(station, super, newTanker(1, 99999), 1, FillType.LIQUIDMANURE, 500)
check("seller's own load trigger blocked while reserved", r == 0)
pit.spec_husbandry.storage.fillLevels[FillType.LIQUIDMANURE] = 9000   -- animals made 1000 more
r = UWMStock.addFillLevelToFillableObject(station, super, newTanker(1, 99999), 1, FillType.LIQUIDMANURE, 5000)
check("seller can load the unreserved 1000 only", near(r, 1000))
got = M:collect(2, FillType.LIQUIDMANURE, 8000)
check("buyer collects the reserved liters", near(got, 8000) and inv.state == UWMInvoice.STATE.DONE)

-- 5. rules: not manager, no money, all of it with empty stock
reset()
farms[2].members = {[21] = true}
add(newPlaceable(1, "spec_silo", {storages = {newStorage({[FillType.MANURE] = 100})}}))
ok, key = order(21, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 10, 1)
check("non-manager can't create", not ok and key == "uwm_error_notManager", key)
order(20, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 1000000, 100)
ok, key = M:handleRequest(A.ACCEPT, 10, {invoiceId = last().id})
check("buyer without money can't be billed", not ok and key == "uwm_error_noMoney" and last().state == UWMInvoice.STATE.PENDING, key)
order(20, 3, 2, FillType.MANURE, UWMInvoice.AMOUNT.ALL, 0, 1)
ok, key = M:handleRequest(A.ACCEPT, 30, {invoiceId = last().id})
check("all of it with nothing in stock refused", not ok and key == "uwm_error_noStock", key)
ok, key = M:handleRequest(A.DECLINE, 30, {invoiceId = last().id})
check("seller declines", ok and last().state == UWMInvoice.STATE.DECLINED, key)
ok, key = order(20, 2, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 10, 1)
check("can't trade with own farm", not ok, key)

-- 6. electricity daily contract into chosen productions
reset()
local plant = add(newPlaceable(1, "spec_productionPoint", {productionPoint = {storage = newStorage({[FillType.ELECTRICCHARGE] = 5000}), outputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}, inputFillTypeIds = {}}}, "Biogas"))
local bakery = add(newPlaceable(2, "spec_productionPoint", {productionPoint = {storage = newStorage({[FillType.ELECTRICCHARGE] = 0}, 3000), inputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}, outputFillTypeIds = {}}}, "Bakery"))
local targets = UWMStock.getElectricityTargets(2)
check("buyer's electricity users found", #targets == 1 and targets[1].name == "Bakery")
ok, key = order(20, 1, 2, FillType.ELECTRICCHARGE, UWMInvoice.AMOUNT.ALL, 0, 100, UWMInvoice.REPEAT_DAILY, false, {bakery.uid})
inv = last()
ok, key = M:handleRequest(A.ACCEPT, 10, {invoiceId = inv.id})
local bStore = bakery.spec_productionPoint.productionPoint.storage
local pStore = plant.spec_productionPoint.productionPoint.storage
check("delivered 3000 (target space), paid 300", ok and near(bStore:getFillLevel(FillType.ELECTRICCHARGE), 3000) and near(pStore:getFillLevel(FillType.ELECTRICCHARGE), 2000) and near(farms[2].money, 9700), key)
check("contract active", inv.state == UWMInvoice.STATE.ACTIVE and inv.nextPeriodDay == 2)
g_currentMission.environment.currentMonotonicDay = 2
M:onDayChanged()
check("day 2: target full -> no delivery, status noSpace", inv.statusKey == "uwm_error_noSpace" and near(farms[2].money, 9700), inv.statusKey)
bStore.fillLevels[FillType.ELECTRICCHARGE] = 1000
g_currentMission.environment.currentMonotonicDay = 3
M:onDayChanged()
check("day 3: 2000 delivered, 200 paid", near(bStore:getFillLevel(FillType.ELECTRICCHARGE), 3000) and near(farms[2].money, 9500) and inv.statusKey == "")
g_currentMission.environment.currentMonotonicDay = 1

-- 7. weekly manure contract: all of it each period, unpaid uncollected carries over
reset()
pit = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.MANURE] = 1000})}))
order(20, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.ALL, 0, 100, UWMInvoice.REPEAT_WEEKLY)
inv = last(); M:handleRequest(A.ACCEPT, 10, {invoiceId = inv.id})
check("week 1 pays for 1000 in stock", near(inv.owedLiters, 1000) and near(farms[2].money, 9900))
M:collect(2, FillType.MANURE, 1000)
pit.spec_husbandry.storage.fillLevels[FillType.MANURE] = 2500
g_currentMission.environment.currentMonotonicDay = 8
M:onDayChanged()
check("week 2 pays for 2500 in stock then", near(inv.owedLiters, 2500) and near(farms[2].money, 9650) and inv.state == UWMInvoice.STATE.ACTIVE)
pit.spec_husbandry.storage.fillLevels[FillType.MANURE] = 3000   -- 500 new, 2500 still waiting for the buyer
g_currentMission.environment.currentMonotonicDay = 15
M:onDayChanged()
check("week 3 pays only for the 500 not already paid for", near(inv.owedLiters, 3000) and near(farms[2].money, 9600), inv.owedLiters)
g_currentMission.environment.currentMonotonicDay = 1

-- 8. sync stream and save/load round trip
reset()
bakery = add(newPlaceable(2, "spec_productionPoint", {productionPoint = {storage = newStorage({[FillType.ELECTRICCHARGE] = 0}), inputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}}}, "Bakery"))
order(20, 1, 2, FillType.ELECTRICCHARGE, UWMInvoice.AMOUNT.FIXED, 500, 7, UWMInvoice.REPEAT_DAILY, false, {bakery.uid})
order(20, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 300, 9, 0, true)
local before = #M.invoices
stream = {}
M:writeStream(0)
local copy = UWMManager.new(false)
copy:readStream(0)
check("stream round trip", #copy.invoices == before and copy.invoices[1].targets[1] == bakery.uid and copy.invoices[2].reserve and #stream == 0)
M:saveToXMLFile("save/utilitiesWasteManagement.xml")
local loaded = UWMManager.new(true)
loaded:loadFromXMLFile("save/utilitiesWasteManagement.xml")
local a, b = M.invoices[1], loaded.invoices[1]
check("save/load round trip", #loaded.invoices == before and b.fillTypeIndex == a.fillTypeIndex and b.targets[1] == a.targets[1]
    and near(b.pricePer1000, 7) and loaded.invoices[2].reserve and loaded.nextId == M.nextId)

-- 9. notifications go to the right farm
check("notifications sent", #notifications > 0 and notifications[1] == "1:uwm_notify_newOrder", table.concat(notifications, " "))

-- 10. a REMOTE buyer accepts a bill for electricity: the chosen production travels as a network object and the
--     server uses its own uniqueId (in game the client's uniqueIds differ from the server's - the 0.1.0.0 bug)
reset()
add(newPlaceable(1, "spec_productionPoint", {productionPoint = {storage = newStorage({[FillType.ELECTRICCHARGE] = 2650}), outputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}, inputFillTypeIds = {}}}, "bga1"))
bakery = add(newPlaceable(2, "spec_productionPoint", {productionPoint = {storage = newStorage({[FillType.ELECTRICCHARGE] = 0}), inputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}, outputFillTypeIds = {}}}, "Malzfabrik"))
order(10, 1, 2, FillType.ELECTRICCHARGE, UWMInvoice.AMOUNT.ALL, 0, 350)   -- seller's bill, no targets yet
inv = last()
stream = {}
local request = UWMRequestEvent.new(A.ACCEPT, {invoiceId = inv.id, targetPlaceables = {bakery}})
request:writeStream(0, nil)
local answers = {}
local fromClient = {getIsServer = function() return false end, sendEvent = function(_, ev) table.insert(answers, ev) end}
g_currentMission.userManager = {getUserIdByConnection = function() return 20 end}
local received = UWMRequestEvent.emptyNew()
received:readStream(0, fromClient)
check("remote accept: answer sent back OK", answers[1] ~= nil and answers[1].ok, answers[1] and answers[1].key)
check("remote accept: target resolved to the server's uniqueId", inv.targets[1] == bakery.uid)
order(30, 3, 2, FillType.ELECTRICCHARGE, UWMInvoice.AMOUNT.ALL, 0, 350)   -- farm 3 (user 30) has no power at all
local empty = last()
ok, key = M:handleRequest(A.ACCEPT, 20, {invoiceId = empty.id, reserve = false, targets = {bakery.uid}})
check("refused accept leaves the buyer's choices off the invoice", not ok and #empty.targets == 0 and empty.state == UWMInvoice.STATE.PENDING, key)
check("remote accept: 2650 kWh moved, 927.50 paid", near(bakery.spec_productionPoint.productionPoint.storage:getFillLevel(FillType.ELECTRICCHARGE), 2650)
    and near(farms[2].money, 10000 - 927.5) and near(farms[1].money, 10000 + 927.5) and inv.state == UWMInvoice.STATE.DONE)

-- 11. the buyer collects at the SELLER's own slurry pit (what the buyer tried in the first multiplayer test)
reset()
local barn = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 50000, [FillType.MANURE] = 0})}, "cowBarn"))
local pitStation = newStation(barn, barn.spec_husbandry.storage)
local tanker = newTanker(2, 6000)
check("before paying: buyer may not load at the seller's pit", not pitStation:getIsFillAllowedToFarm(2))
order(20, 1, 2, FillType.LIQUIDMANURE, UWMInvoice.AMOUNT.FIXED, 10000, 33, 0, true)
inv = last(); M:handleRequest(A.ACCEPT, 10, {invoiceId = inv.id})
check("after paying: buyer may load there", pitStation:getIsFillAllowedToFarm(2))
local list = pitStation:getAllFillLevels(2)
check("R list shows only the paid slurry, 10000 l", near(list[FillType.LIQUIDMANURE] or 0, 10000) and list[FillType.MANURE] == nil)
local own = pitStation:getAllFillLevels(1)
check("the seller still sees his whole pit", near(own[FillType.LIQUIDMANURE], 50000))
got = pitStation:addFillLevelToFillableObject(tanker, 1, FillType.LIQUIDMANURE, 4000, nil, ToolType.TRIGGER)
check("buyer loads 4000: tanker +4000, pit -4000, 6000 left", near(got, 4000) and near(tanker.level, 4000)
    and near(barn.spec_husbandry.storage:getFillLevel(FillType.LIQUIDMANURE), 46000) and near(inv.owedLiters, 6000))
got = pitStation:addFillLevelToFillableObject(tanker, 1, FillType.LIQUIDMANURE, 4000, nil, ToolType.TRIGGER)
check("tanker full at 6000: only 2000 more taken", near(got, 2000) and near(tanker.level, 6000) and near(inv.owedLiters, 4000)
    and near(barn.spec_husbandry.storage:getFillLevel(FillType.LIQUIDMANURE), 44000))
local sellerTanker = newTanker(1, 99999)
got = pitStation:addFillLevelToFillableObject(sellerTanker, 1, FillType.LIQUIDMANURE, 99999, nil, ToolType.TRIGGER)
check("seller's own tanker can't take the buyer's reserved 4000", near(got, 40000)
    and near(barn.spec_husbandry.storage:getFillLevel(FillType.LIQUIDMANURE), 4000))
local secondTanker = newTanker(2, 99999)
got = pitStation:addFillLevelToFillableObject(secondTanker, 1, FillType.LIQUIDMANURE, 99999, nil, ToolType.TRIGGER)
check("buyer's second trip takes the last 4000, invoice done", near(got, 4000) and inv.state == UWMInvoice.STATE.DONE)
check("done: buyer no longer allowed at the pit", not pitStation:getIsFillAllowedToFarm(2))
local stranger = newTanker(3, 99999)
check("a farm with no invoice gets nothing", pitStation:addFillLevelToFillableObject(stranger, 1, FillType.LIQUIDMANURE, 1000) == 0)

local function contains(text, part) return text:find(part, 1, true) ~= nil end

-- 12. the first MP case: 10,000 kWh ordered, the seller only had 4,123 -> details + receipt show it
reset()
notificationDetails = {}
add(newPlaceable(1, "spec_productionPoint", {productionPoint = {storage = newStorage({[FillType.ELECTRICCHARGE] = 4123}), outputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}, inputFillTypeIds = {}}}, "bga1"))
bakery = add(newPlaceable(2, "spec_productionPoint", {productionPoint = {storage = newStorage({[FillType.ELECTRICCHARGE] = 0}), inputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}, outputFillTypeIds = {}}}, "Malzfabrik"))
order(10, 1, 2, FillType.ELECTRICCHARGE, UWMInvoice.AMOUNT.FIXED, 10000, 350)
inv = last()
M:handleRequest(A.ACCEPT, 20, {invoiceId = inv.id, targets = {bakery.uid}})
check("short electricity: 4123 delivered, 1443.05 paid, done", near(inv.totalLiters, 4123) and near(inv.totalMoney, 1443.05) and inv.state == UWMInvoice.STATE.DONE)
local details = UWMFrame.getDetailsText(inv, 2)
check("details: ordered 10000, delivered 4123", contains(details, "Ordered: 10000") and contains(details, "Delivered: 4123"), details)
check("details: buyer paid / seller received 1443.05, refunded 0", contains(details, "Buyer paid: 1443.05") and contains(details, "Seller received: 1443.05")
    and contains(details, "Refunded to the buyer: 0"), details)
check("details: says the seller was short", contains(details, "only what was delivered is paid for"), details)
check("details: price per 1,000 kWh", contains(details, "350 / 1,000 kWh"), details)
local receipts = 0
for i, key in ipairs(notifications) do
    if key:find("uwm_notify_receipt", 1, true) and contains(notificationDetails[i], "4123") and contains(notificationDetails[i], "1443.05") then
        receipts = receipts + 1
    end
end
check("both farms got the receipt numbers", receipts == 2, table.concat(notificationDetails, " | "))

-- 13. slurry: paid 10000, collected 4000, ended -> 6000 refunded, all on the details
reset()
barn = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 50000})}, "cowBarn"))
pitStation = newStation(barn, barn.spec_husbandry.storage)
order(20, 1, 2, FillType.LIQUIDMANURE, UWMInvoice.AMOUNT.FIXED, 10000, 33)
inv = last(); M:handleRequest(A.ACCEPT, 10, {invoiceId = inv.id})
pitStation:addFillLevelToFillableObject(newTanker(2, 4000), 1, FillType.LIQUIDMANURE, 9999, nil, ToolType.TRIGGER)
M:handleRequest(A.CANCEL, 20, {invoiceId = inv.id})
details = UWMFrame.getDetailsText(inv, 1)
check("slurry details: paid for 10000, collected 4000, refunded 6000 l", contains(details, "Paid for: 10000") and contains(details, "Collected: 4000")
    and contains(details, "Not collected, refunded: 6000"), details)
check("slurry details: buyer paid 330, refunded 198, seller got 132", contains(details, "Buyer paid: 330") and contains(details, "Refunded to the buyer: 198")
    and contains(details, "Seller received: 132"), details)
check("finished day recorded", inv.finishedDay == 1 and contains(details, "Finished on day 1"), details)

-- 14. deleting finished invoices: each farm only clears its own list
local finishedId = inv.id
ok, key = M:handleRequest(A.DELETE, 10, {invoiceId = finishedId})
check("seller deletes: hidden for the seller only", ok and inv.hiddenBySeller and not inv.hiddenByBuyer and M:getInvoice(finishedId) ~= nil, key)
ok, key = M:handleRequest(A.DELETE, 20, {invoiceId = finishedId})
check("buyer deletes too: invoice gone", ok and M:getInvoice(finishedId) == nil, key)
order(20, 1, 2, FillType.LIQUIDMANURE, UWMInvoice.AMOUNT.FIXED, 100, 1)
local active = last(); M:handleRequest(A.ACCEPT, 10, {invoiceId = active.id})
ok, key = M:handleRequest(A.DELETE, 20, {invoiceId = active.id})
check("an active invoice can't be deleted", not ok and key == "uwm_error_notFinished", key)
ok, key = M:handleRequest(A.DELETE, 21, {invoiceId = active.id})
check("only the farm manager deletes", not ok and key == "uwm_error_notManager", key)
order(20, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 5, 1); M:handleRequest(A.DECLINE, 10, {invoiceId = last().id})
order(20, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 6, 1); M:handleRequest(A.CANCEL, 20, {invoiceId = last().id})
ok = M:handleRequest(A.CLEAR_HISTORY, 20, {})
local visible, kept = 0, 0
for _, invoice in ipairs(M.invoices) do
    if invoice:getIsFinished() and not invoice:getIsHiddenFor(2) then visible = visible + 1 end
    if invoice:getIsFinished() and not invoice:getIsHiddenFor(1) then kept = kept + 1 end
end
check("buyer clears history: none left for him, seller still sees 2", ok and visible == 0 and kept == 2 and active.state == UWMInvoice.STATE.ACTIVE)
stream = {}
M:writeStream(0)
copy = UWMManager.new(false); copy:readStream(0)
check("hidden flags and refund liters travel to clients", copy.invoices[#copy.invoices].hiddenByBuyer and #stream == 0)

print(string.format("%d passed, %d failed", passed, failed))
return failed
