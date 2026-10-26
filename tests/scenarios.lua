local A = UWMManager.ACTION
local M
local passed, failed = 0, 0
local function check(name, cond, info)
    if cond then passed = passed + 1 print("PASS " .. name)
    else failed = failed + 1 print("FAIL " .. name .. (info and ("  " .. tostring(info)) or "")) end
end
local function near(a, b) return math.abs(a - b) < 0.01 end

local depot
local function reset(noDepot)
    g_currentMission.placeableSystem.placeables = {}
    for _, f in pairs(farms) do f.money = 10000 end
    notifications = {}
    UtilitiesWasteManagement:loadMap("")
    M = UtilitiesWasteManagement.manager
    removeDepots()
    depot = nil
    if not noDepot then
        depot = newDepot(1, 0)
        M.members[2] = UWMManager.newMember(UWMManager.MEMBER.MEMBER)
        M.members[3] = UWMManager.newMember(UWMManager.MEMBER.MEMBER)
    end
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

-- 11. the buyer collects at the DEPOT; the seller's own slurry pit no longer serves buyers (removed in 0.4)
reset()
local barn = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 50000, [FillType.MANURE] = 0})}, "cowBarn"))
local barnStation = newStation(barn, barn.spec_husbandry.storage)
local pitStation = newDepotStation(depot)
local tanker = newTanker(2, 6000)
check("before paying: buyer may not load at the depot", not pitStation:getIsFillAllowedToFarm(2))
order(20, 1, 2, FillType.LIQUIDMANURE, UWMInvoice.AMOUNT.FIXED, 10000, 33, 0, true)
inv = last(); M:handleRequest(A.ACCEPT, 10, {invoiceId = inv.id})
check("after paying: buyer may load at the depot", pitStation:getIsFillAllowedToFarm(2))
check("but not at the seller's own pit any more", not barnStation:getIsFillAllowedToFarm(2)
    and barnStation:addFillLevelToFillableObject(newTanker(2, 999), 1, FillType.LIQUIDMANURE, 500) == 0)
local list = pitStation:getAllFillLevels(2)
check("R list shows only the paid slurry, 10000 l", near(list[FillType.LIQUIDMANURE] or 0, 10000) and list[FillType.MANURE] == nil)
local own = barnStation:getAllFillLevels(1)
check("the seller still sees his whole pit", near(own[FillType.LIQUIDMANURE], 50000))
got = pitStation:addFillLevelToFillableObject(tanker, 1, FillType.LIQUIDMANURE, 4000, nil, ToolType.TRIGGER)
check("buyer loads 4000: tanker +4000, pit -4000, 6000 left", near(got, 4000) and near(tanker.level, 4000)
    and near(barn.spec_husbandry.storage:getFillLevel(FillType.LIQUIDMANURE), 46000) and near(inv.owedLiters, 6000))
got = pitStation:addFillLevelToFillableObject(tanker, 1, FillType.LIQUIDMANURE, 4000, nil, ToolType.TRIGGER)
check("tanker full at 6000: only 2000 more taken", near(got, 2000) and near(tanker.level, 6000) and near(inv.owedLiters, 4000)
    and near(barn.spec_husbandry.storage:getFillLevel(FillType.LIQUIDMANURE), 44000))
local sellerTanker = newTanker(1, 99999)
got = barnStation:addFillLevelToFillableObject(sellerTanker, 1, FillType.LIQUIDMANURE, 99999, nil, ToolType.TRIGGER)
check("seller's own tanker can't take the buyer's reserved 4000", near(got, 40000)
    and near(barn.spec_husbandry.storage:getFillLevel(FillType.LIQUIDMANURE), 4000))
local secondTanker = newTanker(2, 99999)
got = pitStation:addFillLevelToFillableObject(secondTanker, 1, FillType.LIQUIDMANURE, 99999, nil, ToolType.TRIGGER)
check("buyer's second trip takes the last 4000, invoice done", near(got, 4000) and inv.state == UWMInvoice.STATE.DONE)
check("done: buyer no longer allowed at the depot", not pitStation:getIsFillAllowedToFarm(2))
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
pitStation = newDepotStation(depot)
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


-- 15. no depot on the map: no invoices at all, contracts skip their period
reset(true)
pit = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.MANURE] = 5000})}))
ok, key = order(20, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 1000, 10)
check("no depot: order refused", not ok and key == "uwm_error_noDepot" and #M.invoices == 0, key)
check("no depot: the Utilities tab is hidden", UWMFrame.getIsPageEnabled() == false)
check("no depot: header says so", UWMFrame.getDepotStatusText(2) == UWM_TEXTS.uwm_depot_none, UWMFrame.getDepotStatusText(2))
depot = newDepot(1, 0)
check("depot built: the tab shows", UWMFrame.getIsPageEnabled() == true)
M.members[2] = UWMManager.newMember(UWMManager.MEMBER.MEMBER)
order(20, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 1000, 10, UWMInvoice.REPEAT_DAILY)
inv = last(); M:handleRequest(A.ACCEPT, 10, {invoiceId = inv.id})
check("with a depot: daily contract runs, 10 paid", inv.state == UWMInvoice.STATE.ACTIVE and near(farms[2].money, 9990))
removeDepots()
g_currentMission.environment.currentMonotonicDay = 2
M:onDayChanged()
check("depot sold: contract period skipped, nothing paid", near(farms[2].money, 9990) and inv.statusKey == "uwm_error_noDepot", inv.statusKey)
g_currentMission.environment.currentMonotonicDay = 1

-- 16. a depot is placed: every other farm gets the offer; Yes / No / ask again; only the manager answers
reset(true)
depot = newDepot(1, 268)
M:updateMemberships()
check("farms 2 and 3 offered, the owner not", M.members[2].state == UWMManager.MEMBER.OFFERED and M.members[3].state == UWMManager.MEMBER.OFFERED
    and M.members[1] == nil)
local offers = 0
for _, n in ipairs(notifications) do if n == "2:uwm_notify_depotOffer" or n == "3:uwm_notify_depotOffer" then offers = offers + 1 end end
check("both got the offer message", offers == 2, table.concat(notifications, " "))
check("the offer shows the share after joining: 268 / 2 = 134", near(M:getDailyShare(2), 134))
check("header: offered", UWMFrame.getDepotStatusText(2) == string.format(UWM_TEXTS.uwm_depot_offered, "134"), UWMFrame.getDepotStatusText(2))
ok, key = order(20, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 10, 1)
check("not yet a member: can't order", not ok and key == "uwm_error_notMember", key)
farms[2].members = {[21] = true}
ok, key = M:handleRequest(A.JOIN_DEPOT, 21, {})
check("a non-manager can't answer", not ok and key == "uwm_error_notManager", key)
ok, key = M:handleRequest(A.JOIN_DEPOT, 20, {})
check("farm 2 joins", ok and M:getIsParticipant(2) and key == "uwm_result_joined", key)
ok, key = M:handleRequest(A.DECLINE_DEPOT, 30, {})
check("farm 3 says no", ok and M.members[3].state == UWMManager.MEMBER.DECLINED, key)
ok, key = order(20, 3, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 10, 1)
check("member can't trade with a farm that said no", not ok and key == "uwm_error_otherNotMember", key)
ok, key = order(20, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 10, 1)
check("member trades with the owner", ok, key)
local opts = UWMFrame.getDepotOptions(3, true, false)
check("Depot button for farm 3: ask to join", #opts == 1 and opts[1].action == A.REQUEST_DEPOT)
ok, key = M:handleRequest(A.REQUEST_DEPOT, 30, {})
check("farm 3 asks again: new offer", ok and M.members[3].state == UWMManager.MEMBER.OFFERED, key)
M:updateMemberships()
check("no double offers", M.members[3].state == UWMManager.MEMBER.OFFERED)
opts = UWMFrame.getDepotOptions(3, true, false)
check("Depot button for farm 3 now: join / don't join", #opts == 2 and opts[1].action == A.JOIN_DEPOT and opts[2].action == A.DECLINE_DEPOT)
check("owner: no membership options, header says owner", #UWMFrame.getDepotOptions(1, true, false) == 0
    and UWMFrame.getDepotStatusText(1) == string.format(UWM_TEXTS.uwm_depot_owner, "134"), UWMFrame.getDepotStatusText(1))

-- 17. upkeep shared equally every day; a broke member builds arrears; two months with arrears = suspended
reset(true)
depot = newDepot(1, 270)
M.members[2] = UWMManager.newMember(UWMManager.MEMBER.MEMBER)
M.members[3] = UWMManager.newMember(UWMManager.MEMBER.MEMBER)
farms[3].money = 50
M:onDayChanged()
check("member 2 paid its share 90 to the owner", near(farms[2].money, 9910) and near(farms[1].money, 10090), farms[1].money)
check("member 3 couldn't pay: owes 90", near(farms[3].money, 50) and near(M.members[3].arrears, 90))
M:onPeriodChanged()
check("month 1 ends with arrears: missed 1, not suspended", M.members[3].missedMonths == 1 and not M.members[3].suspended)
check("member 2 has no arrears: missed 0", M.members[2].missedMonths == 0)
M:onDayChanged()
M:onPeriodChanged()
check("month 2 too: suspended, owes 180", M.members[3].suspended and near(M.members[3].arrears, 180))
ok, key = order(30, 1, 3, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 10, 1)
check("suspended farm can't order", not ok and key == "uwm_error_suspended", key)
ok, key = order(20, 3, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 10, 1)
check("others can't trade with it either", not ok and key == "uwm_error_otherNotMember", key)
check("header: suspended, owes 180", UWMFrame.getDepotStatusText(3) == string.format(UWM_TEXTS.uwm_depot_suspended, "180"), UWMFrame.getDepotStatusText(3))
ok, key = M:handleRequest(A.PAY_ARREARS, 30, {})
check("can't pay 180 with 50", not ok and key == "uwm_error_noMoney", key)
farms[3].money = 1000
local ownerBefore = farms[1].money
ok, key = M:handleRequest(A.PAY_ARREARS, 30, {})
check("pays 180: suspension lifted, owner gets it", ok and not M.members[3].suspended and M.members[3].arrears == 0
    and near(farms[3].money, 820) and near(farms[1].money, ownerBefore + 180), key)
ok, key = order(30, 1, 3, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 10, 1)
check("trading again after paying", ok, key)

-- 18. one depot per map unless the server admin allows more
reset(true)
depot = newDepot(1, 0)
check("a second depot is blocked", UWMDepot.getPlacingBlocked({}) == true)
check("the placed one itself is not", UWMDepot.getPlacingBlocked(depot) == false)
g_currentMission.userManager = {getUserByUserId = function(_, u) return {getIsMasterUser = function() return u == 99 end} end}
ok, key = M:handleRequest(A.SET_MULTIPLE_DEPOTS, 20, {flag = true})
check("a farm manager is not the server admin", not ok and key == "uwm_error_notAdmin", key)
ok, key = M:handleRequest(A.SET_MULTIPLE_DEPOTS, 99, {flag = true})
check("admin allows more depots", ok and M.allowMultipleDepots and UWMDepot.getPlacingBlocked({}) == false, key)
opts = UWMFrame.getDepotOptions(0, false, true)
check("admin's Depot button switches it back", #opts == 1 and opts[1].action == A.SET_MULTIPLE_DEPOTS and opts[1].flag == false)

-- 19. membership and the setting travel to clients and into the savegame
reset(true)
depot = newDepot(1, 0)
M.members[2] = UWMManager.newMember(UWMManager.MEMBER.MEMBER)
M.members[2].arrears, M.members[2].missedMonths, M.members[2].suspended = 45.5, 2, true
M.members[3] = UWMManager.newMember(UWMManager.MEMBER.DECLINED)
M.allowMultipleDepots = true
stream = {}
M:writeStream(0)
copy = UWMManager.new(false); copy:readStream(0)
check("members stream to clients", #stream == 0 and copy.allowMultipleDepots and copy.members[2].suspended and near(copy.members[2].arrears, 45.5)
    and copy.members[2].missedMonths == 2 and copy.members[3].state == UWMManager.MEMBER.DECLINED)
M:saveToXMLFile("save/depot.xml")
loaded = UWMManager.new(true)
loaded:loadFromXMLFile("save/depot.xml")
check("members saved and loaded", loaded.allowMultipleDepots and loaded.members[2].suspended and near(loaded.members[2].arrears, 45.5)
    and loaded.members[3].state == UWMManager.MEMBER.DECLINED)

-- 20. at the depot a buyer sees the goods paid for from ALL its sellers; farms 2 and 3 sell to farm 1
reset()
local pit2 = add(newPlaceable(2, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 3000})}))
local heap3 = add(newPlaceable(3, "spec_manureHeap", {manureHeap = newStorage({[FillType.MANURE] = 8000})}))
order(10, 2, 1, FillType.LIQUIDMANURE, UWMInvoice.AMOUNT.FIXED, 2000, 10)
M:handleRequest(A.ACCEPT, 20, {invoiceId = last().id})
order(10, 3, 1, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 5000, 10)
M:handleRequest(A.ACCEPT, 30, {invoiceId = last().id})
local station = newDepotStation(depot)
list = station:getAllFillLevels(1)
check("depot owner as buyer: R list = 2000 slurry + 5000 manure", near(list[FillType.LIQUIDMANURE] or 0, 2000) and near(list[FillType.MANURE] or 0, 5000))
check("farm 2 paid for nothing: empty list, not allowed", next((station:getAllFillLevels(2))) == nil and not station:getIsFillAllowedToFarm(2))
local spreader = newTanker(1, 20000)
got = station:addFillLevelToFillableObject(spreader, 1, FillType.MANURE, 20000, nil, ToolType.TRIGGER)
check("manure comes out of farm 3's heap", near(got, 5000) and near(heap3.spec_manureHeap.manureHeap:getFillLevel(FillType.MANURE), 3000)
    and near(pit2.spec_husbandry.storage:getFillLevel(FillType.LIQUIDMANURE), 3000))

-- 21. a member leaves: no more shares, no invoices, can't ask to rejoin for 6 months (user's rule)
reset(true)
depot = newDepot(1, 300)
M.members[2] = UWMManager.newMember(UWMManager.MEMBER.MEMBER)
M.members[3] = UWMManager.newMember(UWMManager.MEMBER.MEMBER)
opts = UWMFrame.getDepotOptions(2, true, false)
check("member's Depot button offers Leave", #opts == 1 and opts[1].action == A.LEAVE_DEPOT)
ok, key = M:handleRequest(A.LEAVE_DEPOT, 10, {})
check("the owner can't leave", not ok and key == "uwm_error_notMember", key)
ok, key = M:handleRequest(A.LEAVE_DEPOT, 20, {})
check("farm 2 leaves", ok and key == "uwm_result_left" and M.members[2].rejoinWait == 6 and not M:getIsParticipant(2), key)
M:onDayChanged()
check("after leaving: share split owner + farm 3 only (150 each), farm 2 pays nothing", near(farms[2].money, 10000) and near(farms[3].money, 9850))
ok, key = order(20, 1, 2, FillType.MANURE, UWMInvoice.AMOUNT.FIXED, 10, 1)
check("no invoices after leaving", not ok and key == "uwm_error_notMember", key)
check("no Ask to join button while waiting", #UWMFrame.getDepotOptions(2, true, false) == 0)
check("header counts the months", UWMFrame.getDepotStatusText(2) == string.format(UWM_TEXTS.uwm_depot_left, 6), UWMFrame.getDepotStatusText(2))
ok, key = M:handleRequest(A.REQUEST_DEPOT, 20, {})
check("can't ask to rejoin yet", not ok and key == "uwm_error_rejoinWait", key)
M:updateMemberships()
check("no automatic new offer either", M.members[2].state == UWMManager.MEMBER.DECLINED)
for _ = 1, 5 do M:onPeriodChanged() end
check("5 months on: still 1 to wait", M.members[2].rejoinWait == 1 and not M:handleRequest(A.REQUEST_DEPOT, 20, {}))
stream = {}
M:writeStream(0)
copy = UWMManager.new(false); copy:readStream(0)
M:saveToXMLFile("save/leave.xml"); loaded = UWMManager.new(true); loaded:loadFromXMLFile("save/leave.xml")
check("the wait travels to clients and the savegame", #stream == 0 and copy.members[2].rejoinWait == 1 and loaded.members[2].rejoinWait == 1)
M:onPeriodChanged()
ok, key = M:handleRequest(A.REQUEST_DEPOT, 20, {})
check("6 months on: may ask again, gets a new offer", ok and M.members[2].state == UWMManager.MEMBER.OFFERED, key)

-- 22. leaving with a debt: taken from the account at once, even into the negative (user's rule)
reset(true)
depot = newDepot(1, 300)
M.members[2] = UWMManager.newMember(UWMManager.MEMBER.MEMBER)
M.members[2].arrears, M.members[2].missedMonths, M.members[2].suspended = 450, 2, true
farms[2].money = 100
ok, key = M:handleRequest(A.LEAVE_DEPOT, 20, {})
check("a suspended member can leave", ok, key)
check("debt 450 taken: 100 -> -350, owner +450", near(farms[2].money, -350) and near(farms[1].money, 10450), farms[2].money)
check("nothing owed any more, not suspended, 6 months wait", M.members[2].arrears == 0 and not M.members[2].suspended
    and M.members[2].rejoinWait == 6)
local told = false
for _, n in ipairs(notifications) do if n == "2:uwm_notify_depotDebtTaken" then told = true end end
check("the farm is told what was taken", told, table.concat(notifications, " "))

-- 23. standing OFFER: farm 1 puts 1,000,000 l of slurry up for anyone; farms 2 and 3 buy parts (user's idea)
local function post(user, kind, ft, liters, price, targets)
    local l = UWMListing.new()
    l.kind, l.fillTypeIndex, l.liters, l.pricePer1000 = kind, ft, liters, price
    return M:handleRequest(A.POST_LISTING, user, {listing = l, targets = targets})
end
local function lastListing() return M.listings[#M.listings] end
reset()
barn = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 1200000}, 2000000)}, "cowBarn"))
ok, key = post(10, UWMListing.KIND.OFFER, FillType.LIQUIDMANURE, 2000000, 1)
check("offer: can't offer more than in stock", not ok and key == "uwm_error_listingNoStock", key)
ok, key = post(10, UWMListing.KIND.OFFER, FillType.LIQUIDMANURE, 1000000, 1)
local offer = lastListing()
check("offer posted, open, 1,000,000 left", ok and offer:getIsOpen() and near(offer.remaining, 1000000), key)
local told2, told3 = false, false
for _, n in ipairs(notifications) do told2 = told2 or n == "2:uwm_notify_listingOffer"; told3 = told3 or n == "3:uwm_notify_listingOffer" end
check("every other farm is told", told2 and told3, table.concat(notifications, " "))
check("offer holds the stock: only 200,000 free", near(UWMStock.getAvailable(1, FillType.LIQUIDMANURE), 200000))
local r2 = UWMStock.addFillLevelToFillableObject({isServer = true, owningPlaceable = barn}, function(_, _, _, _, d) return d end, newTanker(1, 9999999), 1, FillType.LIQUIDMANURE, 500000)
check("seller's own tanker can't load the held stock", near(r2, 200000), r2)
ok, key = M:handleRequest(A.TRADE_LISTING, 10, {listingId = offer.id, liters = 10})
check("can't buy from your own offer", not ok and key == "uwm_error_ownListing", key)
ok, key = M:handleRequest(A.TRADE_LISTING, 20, {listingId = offer.id, liters = 50000})
inv = last()
check("farm 2 buys 50,000 for 50: paid now", ok and near(farms[2].money, 9950) and near(farms[1].money, 10050), key)
check("deal = paid, reserved invoice to collect at the depot", inv.listingId == offer.id and inv.state == UWMInvoice.STATE.ACTIVE
    and inv.reserve and near(inv.owedLiters, 50000) and inv.buyerFarmId == 2 and inv.sellerFarmId == 1)
check("950,000 left, still all held", near(offer.remaining, 950000) and near(M:getReservedLiters(1, FillType.LIQUIDMANURE), 1000000))
ok, key = M:handleRequest(A.TRADE_LISTING, 30, {listingId = offer.id, liters = 960000})
check("can't buy more than is left", not ok and key == "uwm_error_listingTooMuch", key)
farms[3].money = 100000
ok, key = M:handleRequest(A.TRADE_LISTING, 30, {listingId = offer.id, liters = 100000})
check("farm 3 buys 100,000", ok and near(offer.remaining, 850000) and near(farms[3].money, 99900), key)
farms[2].money = 1000000
ok, key = M:handleRequest(A.TRADE_LISTING, 20, {listingId = offer.id, liters = 850000})
check("someone buys the rest: offer complete", ok and offer.state == UWMListing.STATE.DONE and offer.trades == 3
    and near(offer.tradedLiters, 1000000) and near(offer.totalMoney, 1000), key)
ok, key = M:handleRequest(A.TRADE_LISTING, 30, {listingId = offer.id, liters = 1})
check("a finished offer takes no more deals", not ok and key == "uwm_error_listingClosed", key)
local station = newDepotStation(depot)
got = station:addFillLevelToFillableObject(newTanker(3, 30000), 1, FillType.LIQUIDMANURE, 30000, nil, ToolType.TRIGGER)
check("buyer collects at the depot from the seller's barn", near(got, 30000) and near(barn.spec_husbandry.storage:getFillLevel(FillType.LIQUIDMANURE), 1170000))

-- 24. withdrawing an offer frees the held stock; paid deals stay
reset()
barn = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.MANURE] = 5000})}, "cowBarn"))
post(10, UWMListing.KIND.OFFER, FillType.MANURE, 4000, 10)
offer = lastListing()
M:handleRequest(A.TRADE_LISTING, 20, {listingId = offer.id, liters = 1000})
ok, key = M:handleRequest(A.WITHDRAW_LISTING, 20, {listingId = offer.id})
check("only the poster withdraws", not ok and key == "uwm_error_notYourListing", key)
ok, key = M:handleRequest(A.WITHDRAW_LISTING, 10, {listingId = offer.id})
check("withdrawn: 3000 freed, the 1000 sold stays reserved", ok and offer.state == UWMListing.STATE.CANCELLED
    and near(M:getReservedLiters(1, FillType.MANURE), 1000) and last().state == UWMInvoice.STATE.ACTIVE, key)
ok, key = M:handleRequest(A.DELETE_LISTING, 10, {listingId = offer.id})
check("finished offer deleted from history", ok and M:getListing(offer.id) == nil, key)

-- 25. standing WANTED order: farm 2 wants 1,000,000 l of slurry; money held up front; sellers paid from it
reset()
farms[2].money = 5000
ok, key = post(20, UWMListing.KIND.WANTED, FillType.LIQUIDMANURE, 1000000, 10)
check("wanted: can't post without the money for all of it", not ok and key == "uwm_error_listingNoMoney", key)
farms[2].money = 20000
ok, key = post(20, UWMListing.KIND.WANTED, FillType.LIQUIDMANURE, 1000000, 10)
local wanted = lastListing()
check("wanted posted: 10,000 held from the poster", ok and near(farms[2].money, 10000) and near(wanted:getHeldMoney(), 10000), key)
local pit1 = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 300000})}))
add(newPlaceable(3, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 900000})}))
ok, key = M:handleRequest(A.TRADE_LISTING, 10, {listingId = wanted.id, liters = 400000})
check("a seller can't sell more than it has", not ok and key == "uwm_error_listingNoStock" and near(wanted.remaining, 1000000), key)
ok, key = M:handleRequest(A.TRADE_LISTING, 10, {listingId = wanted.id, liters = 300000})
inv = last()
check("farm 1 sells 300,000: paid 3,000 from the held money", ok and near(farms[1].money, 13000) and near(farms[2].money, 10000), key)
check("deal invoice: prepaid, reserved for farm 2 to collect", inv.prepaid and inv.reserve and inv.buyerFarmId == 2
    and near(inv.owedLiters, 300000) and near(M:getReservedLiters(1, FillType.LIQUIDMANURE), 300000))
ok, key = M:handleRequest(A.TRADE_LISTING, 30, {listingId = wanted.id, liters = 700000})
check("farm 3 fills the rest: order complete, 7,000 paid", ok and wanted.state == UWMListing.STATE.DONE and near(farms[3].money, 17000)
    and near(farms[2].money, 10000), key)
local completeTold = false
for _, n in ipairs(notifications) do completeTold = completeTold or n == "2:uwm_notify_listingComplete" end
check("the poster is told it's complete", completeTold, table.concat(notifications, " "))
M:handleRequest(A.CANCEL, 20, {invoiceId = inv.id})
check("ending a prepaid deal refunds the uncollected liters to the poster", near(farms[2].money, 13000) and near(farms[1].money, 10000))

-- 26. wanted order withdrawn half-way: the held money for the rest comes back
reset()
post(20, UWMListing.KIND.WANTED, FillType.MANURE, 10000, 100)
wanted = lastListing()
add(newPlaceable(3, "spec_manureHeap", {manureHeap = newStorage({[FillType.MANURE] = 4000})}))
M:handleRequest(A.TRADE_LISTING, 30, {listingId = wanted.id, liters = 4000})
check("4000 sold for 400", near(farms[3].money, 10400) and near(farms[2].money, 9000) and near(wanted.remaining, 6000))
ok, key = M:handleRequest(A.WITHDRAW_LISTING, 20, {listingId = wanted.id})
check("withdrawn: 600 held comes back", ok and near(farms[2].money, 9600) and near(wanted:getHeldMoney(), 0), key)

-- 27. electricity both ways: offer into the buyer's productions, wanted order into the poster's
reset()
add(newPlaceable(1, "spec_productionPoint", {productionPoint = {storage = newStorage({[FillType.ELECTRICCHARGE] = 10000}), outputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}, inputFillTypeIds = {}}}, "bga1"))
bakery = add(newPlaceable(2, "spec_productionPoint", {productionPoint = {storage = newStorage({[FillType.ELECTRICCHARGE] = 0}, 3000), inputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}, outputFillTypeIds = {}}}, "Bakery"))
post(10, UWMListing.KIND.OFFER, FillType.ELECTRICCHARGE, 8000, 100)
offer = lastListing()
ok, key = M:handleRequest(A.TRADE_LISTING, 20, {listingId = offer.id, liters = 5000, targets = {bakery.uid}})
check("power offer: only 3000 fit, 300 paid, 5000 left", ok and near(farms[2].money, 9700)
    and near(offer.remaining, 5000) and last().state == UWMInvoice.STATE.DONE, key)
bakery.spec_productionPoint.productionPoint.storage.fillLevels[FillType.ELECTRICCHARGE] = 0
ok, key = post(20, UWMListing.KIND.WANTED, FillType.ELECTRICCHARGE, 3000, 100, {bakery.uid})
wanted = lastListing()
ok, key = M:handleRequest(A.TRADE_LISTING, 10, {listingId = wanted.id, liters = 3000})
check("7000 kWh left, 5000 held by its own offer: can't sell 3000", not ok and key == "uwm_error_listingNoStock", key)
M:handleRequest(A.WITHDRAW_LISTING, 10, {listingId = offer.id})
ok, key = M:handleRequest(A.TRADE_LISTING, 10, {listingId = wanted.id, liters = 3000})
check("after withdrawing: 3000 kWh delivered, paid from the held 300", ok and wanted.state == UWMListing.STATE.DONE
    and near(bakery.spec_productionPoint.productionPoint.storage:getFillLevel(FillType.ELECTRICCHARGE), 3000) and near(farms[1].money, 10600), key)

-- 28. standing orders travel to clients and into the savegame
reset()
add(newPlaceable(1, "spec_silo", {storages = {newStorage({[FillType.MANURE] = 9000})}}))
post(10, UWMListing.KIND.OFFER, FillType.MANURE, 9000, 12)
M:handleRequest(A.TRADE_LISTING, 20, {listingId = lastListing().id, liters = 1000})
stream = {}
M:writeStream(0)
copy = UWMManager.new(false); copy:readStream(0)
check("listing streams to clients", #stream == 0 and #copy.listings == 1 and near(copy.listings[1].remaining, 8000)
    and copy.invoices[1].listingId == copy.listings[1].id)
M:saveToXMLFile("save/listings.xml"); loaded = UWMManager.new(true); loaded:loadFromXMLFile("save/listings.xml")
check("listing saved and loaded, still holding stock", #loaded.listings == 1 and loaded.listings[1].trades == 1
    and near(loaded:getReservedLiters(1, FillType.MANURE), 9000) and loaded.nextListingId == M.nextListingId)
stream = {}
local req = UWMRequestEvent.new(A.TRADE_LISTING, {listingId = 5, liters = 1234})
req:writeStream(0, nil)
local back = UWMRequestEvent.emptyNew()
back.run = function() end
back:readStream(0, nil)
check("trade request travels: listing id + amount", back.data.listingId == 5 and near(back.data.liters, 1234) and #stream == 0)

-- 29. the tabbed page: what goes in which tab, row texts, and which buttons each selection gets
reset()
add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 500000, [FillType.MANURE] = 0})}))
add(newPlaceable(2, "spec_manureHeap", {manureHeap = newStorage({[FillType.MANURE] = 9000})}))
order(20, 1, 2, FillType.LIQUIDMANURE, UWMInvoice.AMOUNT.FIXED, 10000, 33)      -- farm 2 orders from farm 1
local pendingOrder = last()
order(10, 1, 2, FillType.LIQUIDMANURE, UWMInvoice.AMOUNT.FIXED, 2000, 10)       -- farm 1 bills farm 2
local bill = last()
post(10, UWMListing.KIND.OFFER, FillType.LIQUIDMANURE, 400000, 10)
offer = lastListing()
post(20, UWMListing.KIND.WANTED, FillType.MANURE, 1000, 5)
wanted = lastListing()
M:handleRequest(A.TRADE_LISTING, 20, {listingId = offer.id, liters = 50000})
local deal = last()
local L1 = UWMFrame.buildLists(M, 1)
local L2 = UWMFrame.buildLists(M, 2)
check("farm 1 INCOMING = the order from farm 2", #L1.incoming == 1 and L1.incoming[1] == pendingOrder)
check("farm 1 OUTGOING = its bill", #L1.outgoing == 1 and L1.outgoing[1] == bill)
check("farm 2 sees them the other way round", L2.incoming[1] == bill and L2.outgoing[1] == pendingOrder)
check("MARKET shows other farms' open orders only", #L1.market == 1 and L1.market[1] == wanted and #L2.market == 1 and L2.market[1] == offer)
check("MY ORDERS = own standing orders", #L1.myOrders == 1 and L1.myOrders[1] == offer and L2.myOrders[1] == wanted)
check("deals go to MY DEALS (both farms), not to incoming/outgoing", L1.myDeals[1] == deal and L2.myDeals[1] == deal
    and #L2.openDeals == 1)
local row, colorIndex, color = UWMFrame.getInvoiceRow(pendingOrder, 1)
check("invoice row: number, farm, description, status, amount", row[1] == "UWM-001" and row[3] == "Farm2"
    and row[4] == "Slurry, 10000 (you sell)" and row[6] == "Waiting for you" and row[7] == "330" and colorIndex == 6
    and color == UWMFrame.COLOR_WARN, table.concat(row, " | "))
row = UWMFrame.getMarketRow(offer)
check("market row: farm, for sale, left / of, price, held stock", row[1] == "Farm1" and row[2] == "For sale" and row[4] == "350000"
    and row[5] == "400000" and row[6] == "10 / 1,000 l" and row[7] == "Stock", table.concat(row, " | "))
row = UWMFrame.getOrderRow(wanted)
check("my order row: SO number, wanted, status open", row[1] == "SO-002" and row[2] == "Wanted" and row[8] == "Open", table.concat(row, " | "))
row = UWMFrame.getOpenDealRow(deal, 1)
check("open deal row for the seller: the buyer collects", row[1] == "Farm2" and row[5] == "50000 (buyer)", table.concat(row, " | "))
local function acts(item, farmId, manager) local a, b = UWMFrame.getActions(item, farmId, manager ~= false) return (a or "") .. "," .. (b or "") end
check("incoming bill: Accept and pay / Decline", acts(bill, 2) == "uwm_button_acceptPay,uwm_button_decline", acts(bill, 2))
check("incoming order: Accept / Decline", acts(pendingOrder, 1) == "uwm_button_accept,uwm_button_decline")
check("sent, waiting: Withdraw only", acts(bill, 1) == ",uwm_button_withdraw")
check("running deal: End", acts(deal, 2) == ",uwm_button_end")
check("other farm's offer: Buy; wanted: Sell to them", acts(offer, 2) == "uwm_button_buy," and acts(wanted, 1) == "uwm_button_sellTo,")
check("own open order: Withdraw", acts(offer, 1) == ",uwm_button_withdraw")
check("not the farm manager: no trade buttons", acts(offer, 2, false) == ",")
M:handleRequest(A.WITHDRAW_LISTING, 10, {listingId = offer.id})
check("own finished order: Delete", acts(offer, 1) == ",uwm_button_delete")
check("finished count for Clear history", UWMFrame.getFinishedCount(M, 1) == 1)
details = UWMFrame.getListingDetailsText(wanted, 2)
check("standing order details", contains(details, "Standing order SO-002") and contains(details, "Wanted by: Farm2")
    and contains(details, "Money held for the rest: 5"), details)
details = UWMFrame.getDetailsText(deal, 2)
check("deal details say which standing order", contains(details, "From standing order SO-001"), details)

-- Automatic production output must leave standing offers intact and pay only for the surplus.
reset()
local powerStorage = newStorage({[FillType.ELECTRICCHARGE] = 1000000}, 2000000)
local powerPoint = {storage = powerStorage, outputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}, inputFillTypeIds = {}}
powerPoint.getOwnerFarmId = function() return 1 end
add(newPlaceable(1, "spec_productionPoint", {productionPoint = powerPoint}))
post(10, UWMListing.KIND.OFFER, FillType.ELECTRICCHARGE, 500000, 100)
local powerOffer = lastListing()
local chain = {isServer = true, productionPoints = {powerPoint}}
local sold = 0
local function autoSell(c)
    for _, point in ipairs(c.productionPoints) do
        local levels = point.storage:getFillLevels()
        local amount = levels[FillType.ELECTRICCHARGE] or 0
        sold = sold + amount
        point.storage:setFillLevel(0, FillType.ELECTRICCHARGE)
        g_currentMission:addMoney(amount * 0.1, point:getOwnerFarmId())
    end
    return "sold", nil, 42
end
local balance = farms[1].money
local a, b, c = UWMStock.updateProductionSales(chain, autoSell)
check("auto sell: 1 million stock, 500000 offered, sells only 500000", near(sold, 500000)
    and near(powerStorage:getFillLevel(FillType.ELECTRICCHARGE), 500000))
check("auto sell pays only for the unreserved electricity", near(farms[1].money - balance, 50000))
check("production storage identity and return values restored", powerPoint.storage == powerStorage and a == "sold" and b == nil and c == 42)
UWMStock.updateProductionSales(chain, autoSell)
check("next auto sell leaves the reservation untouched", near(sold, 500000) and near(powerOffer.remaining, 500000))
powerStorage:setFillLevel(600000, FillType.ELECTRICCHARGE)
UWMStock.updateProductionSales(chain, autoSell)
check("newly generated surplus can still auto sell", near(sold, 600000) and near(powerStorage:getFillLevel(FillType.ELECTRICCHARGE), 500000))
local extraStorage = newStorage({[FillType.ELECTRICCHARGE] = 250000}, 2000000)
local extraPoint = {storage = extraStorage, outputFillTypeIds = {[FillType.ELECTRICCHARGE] = true}, inputFillTypeIds = {}, getOwnerFarmId = function() return 1 end}
add(newPlaceable(1, "spec_productionPoint", {productionPoint = extraPoint}))
table.insert(chain.productionPoints, extraPoint)
UWMStock.updateProductionSales(chain, autoSell)
check("multiple productions reserve 500000 once across the farm", near(sold, 850000)
    and near(UWMStock.getStock(1, FillType.ELECTRICCHARGE), 500000))
local success = pcall(UWMStock.updateProductionSales, chain, function() error("test failure") end)
check("failed auto sell restores the real storage", not success and powerPoint.storage == powerStorage and extraPoint.storage == extraStorage)
M:handleRequest(A.WITHDRAW_LISTING, 10, {listingId = powerOffer.id})
UWMStock.updateProductionSales(chain, autoSell)
check("canceling the standing offer releases electricity to auto sell", near(sold, 1350000) and near(UWMStock.getStock(1, FillType.ELECTRICCHARGE), 0))

print(string.format("%d passed, %d failed", passed, failed))
return failed
