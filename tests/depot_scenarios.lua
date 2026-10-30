-- Goods in the depot (user's rule 2026-10-28): manure / slurry put up for sale leave the seller's storage and wait
-- in the depot; unsold goods go back home; each depot part holds 100,000,000 l for all farms together.
local A = UWMManager.ACTION
local passed, failed = 0, 0
local function check(name, cond, info)
    if cond then passed = passed + 1 print("PASS " .. name)
    else failed = failed + 1 print("FAIL " .. name .. (info and ("  " .. tostring(info)) or "")) end
end
local function near(a, b) return math.abs(a - b) < 0.01 end

local M
local function reset()
    g_currentMission.placeableSystem.placeables = {}
    for _, f in pairs(farms) do f.money = 10000000 end
    UtilitiesWasteManagement:loadMap("")
    M = UtilitiesWasteManagement.manager
    removeDepots()
    newDepot(1, 0)
    M.members[2] = UWMManager.newMember(UWMManager.MEMBER.MEMBER)
    M.members[3] = UWMManager.newMember(UWMManager.MEMBER.MEMBER)
end
local function add(p) table.insert(g_currentMission.placeableSystem.placeables, p) return p end
local function bill(user, seller, buyer, ft, liters, price)
    local inv = UWMInvoice.new()
    inv.sellerFarmId, inv.buyerFarmId, inv.fillTypeIndex = seller, buyer, ft
    inv.amountMode, inv.liters, inv.pricePer1000 = UWMInvoice.AMOUNT.FIXED, liters, price
    return M:handleRequest(A.CREATE, user, {invoice = inv})
end
local function post(user, ft, liters, price)
    local l = UWMListing.new()
    l.kind, l.fillTypeIndex, l.liters, l.pricePer1000 = UWMListing.KIND.OFFER, ft, liters, price
    return M:handleRequest(A.POST_LISTING, user, {listing = l})
end
local function last() return M.invoices[#M.invoices] end

-- a bill moves its goods when sent; declining sends them home
reset()
local pit = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 20000, [FillType.MANURE] = 0}, 100000)}))
local store = pit.spec_husbandry.storage
local ok, key = bill(10, 1, 2, FillType.LIQUIDMANURE, 15000, 10)
check("bill sent: 15000 leave the farm for the depot", ok and near(store:getFillLevel(FillType.LIQUIDMANURE), 5000)
    and near(last().depotLiters, 15000) and near(M:getDepotUsed("tank"), 15000), key)
ok, key = bill(10, 1, 3, FillType.LIQUIDMANURE, 6000, 10)
check("a second bill can't use goods already in the depot", not ok and key == "uwm_error_noStock", key)
M:handleRequest(A.DECLINE, 20, {invoiceId = last().id})
check("declined: the 15000 come back home, depot empty", near(store:getFillLevel(FillType.LIQUIDMANURE), 20000)
    and last().depotLiters == 0 and near(M:getDepotUsed("tank"), 0))

-- the seller withdraws a pending bill: same
bill(10, 1, 2, FillType.LIQUIDMANURE, 8000, 10)
M:handleRequest(A.CANCEL, 10, {invoiceId = last().id})
check("withdrawn bill: goods back home", near(store:getFillLevel(FillType.LIQUIDMANURE), 20000))

-- accepted bill: the goods already in the depot are what the buyer pays for (nothing more leaves the farm)
bill(10, 1, 2, FillType.LIQUIDMANURE, 10000, 10)
local inv = last()
ok, key = M:handleRequest(A.ACCEPT, 20, {invoiceId = inv.id})
check("accepted: paid for the 10000 in the depot, farm still has 10000", ok and near(inv.owedLiters, 10000) and near(inv.depotLiters, 10000)
    and near(store:getFillLevel(FillType.LIQUIDMANURE), 10000), key)
check("the buyer may load them at the depot", near(M:getCollectableLiters(2, FillType.LIQUIDMANURE), 10000))
check("the seller's own stock no longer counts them", near(UWMStock.getAvailable(1, FillType.LIQUIDMANURE), 10000))

-- no room at home: the goods wait in the depot and go home when there is room
reset()
pit = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.MANURE] = 9000, [FillType.LIQUIDMANURE] = 0}, 10000)}))
store = pit.spec_husbandry.storage
post(10, FillType.MANURE, 9000, 5)
local offer = M.listings[#M.listings]
check("offer: 9000 moved to the depot", near(offer.depotLiters, 9000) and near(store:getFillLevel(FillType.MANURE), 0))
store.fillLevels[FillType.MANURE] = 7000   -- the animals filled the heap again
M:handleRequest(A.WITHDRAW_LISTING, 10, {listingId = offer.id})
check("withdrawn: 3000 fit at home, 6000 wait in the depot", near(store:getFillLevel(FillType.MANURE), 10000)
    and #M.depotReturns == 1 and near(M.depotReturns[1].liters, 6000) and near(M:getDepotLitersOf(1, FillType.MANURE), 6000))
M:saveToXMLFile("save/depot.xml")
local loaded = UWMManager.new(true)
loaded:loadFromXMLFile("save/depot.xml")
check("waiting goods are saved and loaded", #loaded.depotReturns == 1 and near(loaded.depotReturns[1].liters, 6000)
    and loaded.depotReturns[1].fillTypeIndex == FillType.MANURE and not loaded.needsDepotMove)
store.fillLevels[FillType.MANURE] = 2000   -- farm used some
M:onDayChanged()
check("next day: 6000 more go home, nothing waits", near(store:getFillLevel(FillType.MANURE), 8000) and #M.depotReturns == 0)

-- each depot part holds 100,000,000 l for all farms
reset()
local big = add(newPlaceable(1, "spec_silo", {storages = {newStorage({[FillType.LIQUIDMANURE] = 150000000, [FillType.MANURE] = 0}, 200000000)}}))
ok, key = post(10, FillType.LIQUIDMANURE, 99000000, 1)
check("99,000,000 l fit in the slurry tank", ok, key)
ok, key = post(10, FillType.LIQUIDMANURE, 2000000, 1)
check("2,000,000 more would pass 100,000,000: depot full", not ok and key == "uwm_error_depotFull", key)
add(newPlaceable(2, "spec_silo", {storages = {newStorage({[FillType.MANURE] = 5000000, [FillType.LIQUIDMANURE] = 0}, 10000000)}}))
ok, key = post(20, FillType.MANURE, 5000000, 1)
check("the manure pit has its own 100,000,000", ok and near(M:getDepotUsed("pit"), 5000000), key)
check("and the tank still counts only slurry", near(M:getDepotUsed("tank"), 99000000))
check("electricity never goes to the depot", not UWMManager.getUsesDepot(FillType.ELECTRICCHARGE))

-- an older save: open sales had their goods at the sellers' farms; the first update moves them
reset()
pit = add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.LIQUIDMANURE] = 50000, [FillType.MANURE] = 0}, 100000)}))
store = pit.spec_husbandry.storage
local old = UWMInvoice.new()
old.id, old.sellerFarmId, old.buyerFarmId, old.creatorFarmId = 77, 1, 2, 2
old.fillTypeIndex, old.liters, old.owedLiters, old.state = FillType.LIQUIDMANURE, 12000, 12000, UWMInvoice.STATE.ACTIVE
M:addInvoice(old)
local oldOffer = UWMListing.new()
oldOffer.id, oldOffer.farmId, oldOffer.fillTypeIndex, oldOffer.liters, oldOffer.remaining = 5, 1, FillType.LIQUIDMANURE, 30000, 30000
M:addListing(oldOffer)
M.needsDepotMove = true
M:update(0)
check("old save: paid 12000 + offered 30000 moved to the depot", near(old.depotLiters, 12000) and near(oldOffer.depotLiters, 30000)
    and near(store:getFillLevel(FillType.LIQUIDMANURE), 8000) and not M.needsDepotMove)
check("old save: the buyer can load the 12000 now", near(M:getCollectableLiters(2, FillType.LIQUIDMANURE), 12000))
XMLFile.files["save/old.xml"] = {["utilitiesWasteManagement#nextId"] = 1}
loaded = UWMManager.new(true)
loaded:loadFromXMLFile("save/old.xml")
check("a save without the depot mark asks for the move", loaded.needsDepotMove)

-- BULK goods (user, 2026-10-28): the list shows only what the seller can take out to sell - silos and what
-- productions made; not animal pens (goat milk in the dairy), not production inputs; A - Z; loads at the silo
reset()
local silo = add(newPlaceable(1, "spec_silo", {storages = {newStorage({[FillType.WHEAT] = 40000, [FillType.BARLEY] = 0}, 1000000)}}))
add(newPlaceable(1, "spec_husbandry", {storage = newStorage({[FillType.GOATMILK] = 9000, [FillType.LIQUIDMANURE] = 0}, 100000)}))
local mill = add(newPlaceable(1, "spec_productionPoint", {productionPoint = {storage = newStorage({[FillType.BARLEY] = 5000, [FillType.WHEAT] = 7000}, 100000),
    inputFillTypeIds = {[FillType.WHEAT] = true}, outputFillTypeIds = {[FillType.BARLEY] = true}}}, "Mill"))
check("wheat is bulk, goat milk isn't, our manure keeps its own row", UtilitiesWasteManagement.getIsBulk(FillType.WHEAT)
    and not UtilitiesWasteManagement.getIsBulk(FillType.GOATMILK) and not UtilitiesWasteManagement.getIsBulk(FillType.MANURE))
local goods = UWMStock.getBulkGoods(1)
check("bulk list: barley (mill output) + wheat (silo), A - Z", #goods == 2 and goods[1].fillTypeIndex == FillType.BARLEY
    and goods[2].fillTypeIndex == FillType.WHEAT, #goods)
check("the mill's input wheat doesn't count, only the silo's", near(goods[2].liters, 40000) and near(goods[1].liters, 5000))
local milkListed = false
for _, g in ipairs(goods) do milkListed = milkListed or g.fillTypeIndex == FillType.GOATMILK end
check("goat milk in the dairy is not on the list", not milkListed)
check("standing buy order: every bulk good in the game", #UWMStock.getAllBulkGoods() == 2)
ok, key = bill(10, 1, 2, FillType.WHEAT, 30000, 200)
inv = last()
check("bill for 30000 wheat: out of the silo, into the depot silo part", ok and near(silo.spec_silo.storages[1]:getFillLevel(FillType.WHEAT), 10000)
    and near(M:getDepotUsed("silo"), 30000) and near(mill.spec_productionPoint.productionPoint.storage:getFillLevel(FillType.WHEAT), 7000), key)
check("now only 10000 wheat left to sell", near(UWMStock.getBulkGoods(1)[2].liters, 10000))
M:handleRequest(A.ACCEPT, 20, {invoiceId = inv.id})
local depotStation = newDepotStation(depot or UWMManager.getDepots()[1])
local trailer = newTanker(2, 50000)
got = depotStation:addFillLevelToFillableObject(trailer, 1, FillType.WHEAT, 50000, nil, ToolType.TRIGGER)
check("the buyer loads the 30000 wheat at the depot", near(got, 30000) and inv.state == UWMInvoice.STATE.DONE, got)
ok, key = bill(10, 1, 2, FillType.GOATMILK, 100, 1)
check("goat milk can't be sold through the co-op", not ok and key == "uwm_error_badGood", key)

-- PALLETS (user, 2026-10-28): sold by the liter; taken off the seller's pallets on the map; the buyer gets new
-- pallets on the depot's pad, filled to the chosen size (1,000 or 5,000 l, capped by the game's pallet)
reset()
UWMPallets.reset()
g_currentMission.vehicleSystem.vehicles = {}
fakeSpawner.spawned, fakeSpawner.full, fakeSpawner.capacity = {}, false, 1000
UWMDepot.getPalletSpawner = function() return fakeSpawner end
local function runQueue() for _ = 1, 50 do M:update(0) end end
local p1 = newPallet(1, FillType.HONEY, 1000)
local p2 = newPallet(1, FillType.HONEY, 600)
newPallet(2, FillType.HONEY, 1000)              -- another farm's pallet
newPallet(1, FillType.WHEAT, 800)               -- a wheat bag
check("honey and wheat bags are pallet goods, slurry isn't", UWMPallets.getIsPalletGood(FillType.HONEY)
    and UWMPallets.getIsPalletGood(FillType.WHEAT) and not UWMPallets.getIsPalletGood(FillType.LIQUIDMANURE))
goods = UWMPallets.getGoods(1)
check("pallet list: honey 1600 l on 2 pallets, wheat 800 l on 1, A - Z", #goods == 2 and goods[1].fillTypeIndex == FillType.HONEY
    and near(goods[1].liters, 1600) and goods[1].count == 2 and goods[2].count == 1, #goods)
local function palletBill(liters, size)
    local inv = UWMInvoice.new()
    inv.sellerFarmId, inv.buyerFarmId, inv.fillTypeIndex = 1, 2, FillType.HONEY
    inv.amountMode, inv.liters, inv.pricePer1000, inv.isPallet, inv.palletSize = UWMInvoice.AMOUNT.FIXED, liters, 3000, true, size
    return M:handleRequest(A.CREATE, 10, {invoice = inv})
end
ok, key = palletBill(2000, 1000)
check("can't bill 2000 l of honey with 1600 l on pallets", not ok and key == "uwm_error_noStock", key)
ok, key = palletBill(1200, 1000)
inv = last()
check("bill for 1200 l: taken off the part pallet first, emptied pallets removed", ok and p2.isDeleted and near(p1.level, 400)
    and near(inv.depotLiters, 1200) and near(M:getDepotUsed("pallets"), 1200) and near(M:getDepotUsed("silo"), 0), key)
check("pallet goods never load at the silo / pit triggers", M:getCollectableLiters(2, FillType.HONEY) == 0)
M:handleRequest(A.ACCEPT, 20, {invoiceId = inv.id})
runQueue()
check("paid: 2 new pallets for farm 2 on the pad (1000 + 200 l), invoice done", #fakeSpawner.spawned == 2
    and fakeSpawner.spawned[1].farmId == 2 and near(fakeSpawner.spawned[1].level, 1000) and near(fakeSpawner.spawned[2].level, 200)
    and inv.state == UWMInvoice.STATE.DONE and near(inv.totalLiters, 1200), #fakeSpawner.spawned)

-- 5,000 l pallets: a pallet that holds 2,000 is filled to 2,000 and more come out
fakeSpawner.spawned, fakeSpawner.capacity = {}, 2000
newPallet(1, FillType.HONEY, 1000); newPallet(1, FillType.HONEY, 1000); newPallet(1, FillType.HONEY, 1000)
ok, key = palletBill(3000, 5000)
inv = last()
M:handleRequest(A.ACCEPT, 20, {invoiceId = inv.id})
runQueue()
check("5,000 l size, pallet holds 2,000: 2000 + 1000", ok and #fakeSpawner.spawned == 2 and near(fakeSpawner.spawned[1].level, 2000)
    and near(fakeSpawner.spawned[2].level, 1000) and inv.state == UWMInvoice.STATE.DONE,
    "n=" .. #fakeSpawner.spawned .. " l1=" .. tostring(fakeSpawner.spawned[1] and fakeSpawner.spawned[1].level) .. " l2=" .. tostring(fakeSpawner.spawned[2] and fakeSpawner.spawned[2].level) .. " st=" .. inv.state .. " owed=" .. inv.owedLiters)

-- pad full: the pallets wait and come out later
fakeSpawner.spawned, fakeSpawner.capacity, fakeSpawner.full = {}, 1000, true
newPallet(1, FillType.HONEY, 900)
ok = palletBill(900, 1000)
inv = last()
M:handleRequest(A.ACCEPT, 20, {invoiceId = inv.id})
runQueue()
check("pad full: nothing spawned yet, still owed", #fakeSpawner.spawned == 0 and near(inv.owedLiters, 900) and inv.state == UWMInvoice.STATE.ACTIVE)
fakeSpawner.full = false
g_time = g_time + UWMPallets.RETRY_MS + 1
runQueue()
check("pad free again: the pallet comes out", #fakeSpawner.spawned == 1 and inv.state == UWMInvoice.STATE.DONE, "n=" .. #fakeSpawner.spawned .. " st=" .. inv.state .. " q=" .. #UWMPallets.queue .. " busy=" .. tostring(UWMPallets.busy))

-- withdrawn pallet offer: the unsold liters go home as pallets on the pad for the seller
fakeSpawner.spawned = {}
newPallet(1, FillType.HONEY, 1000); newPallet(1, FillType.HONEY, 1000)
local l = UWMListing.new()
l.kind, l.fillTypeIndex, l.liters, l.pricePer1000, l.isPallet, l.palletSize = UWMListing.KIND.OFFER, FillType.HONEY, 2000, 3000, true, 1000
ok, key = M:handleRequest(A.POST_LISTING, 10, {listing = l})
offer = M.listings[#M.listings]
check("pallet offer posted: 2000 l off the pallets into the depot (400 l left on the older part pallet)", ok and offer.isPallet
    and near(offer.depotLiters, 2000) and near(UWMPallets.getStock(1, FillType.HONEY), 400), tostring(key) .. " depot=" .. offer.depotLiters .. " stock=" .. UWMPallets.getStock(1, FillType.HONEY))
M:handleRequest(A.TRADE_LISTING, 20, {listingId = offer.id, liters = 500})
runQueue()
check("farm 2 buys 500 l: one 500 l pallet for farm 2", #fakeSpawner.spawned == 1 and fakeSpawner.spawned[1].farmId == 2
    and near(fakeSpawner.spawned[1].level, 500) and last().isPallet)
M:handleRequest(A.WITHDRAW_LISTING, 10, {listingId = offer.id})
runQueue()
check("withdrawn: the unsold 1500 l come out for farm 1 (1000 + 500)", #fakeSpawner.spawned == 3
    and fakeSpawner.spawned[2].farmId == 1 and near(fakeSpawner.spawned[2].level + fakeSpawner.spawned[3].level, 1500)
    and #M.depotReturns == 0)
ok, key = (function() local i = UWMInvoice.new() i.sellerFarmId, i.buyerFarmId, i.fillTypeIndex = 1, 2, FillType.LIQUIDMANURE
    i.amountMode, i.liters, i.pricePer1000, i.isPallet = UWMInvoice.AMOUNT.FIXED, 10, 1, true
    return M:handleRequest(A.CREATE, 10, {invoice = i}) end)()
check("slurry can't be sold as pallets", not ok and key == "uwm_error_badGood", key)
stream = {}
inv = last()
inv:writeStream(0)
local copyInv = UWMInvoice.new(); copyInv:readStream(0)
check("pallet flag and size travel to clients", copyInv.isPallet and copyInv.palletSize == inv.palletSize and #stream == 0)

-- the Utilities page cards (UWM CO-OP theme): texts, icon, status colour; the summary numbers
local card = UWMFrame.getInvoiceCard(inv, 2)
check("card: honey on pallets, from farm 1, pallet icon", card.icon == "pallet" and card.title:find("on pallets", 1, true) ~= nil
    and card.sub:find("from Farm1", 1, true) ~= nil and card.sub:find("Pallet pad", 1, true) ~= nil, card.title .. " | " .. card.sub)
check("card: the seller sees 'to'", UWMFrame.getInvoiceCard(inv, 1).sub:find("to Farm2", 1, true) ~= nil)
check("card: finished = grey", card.statusColor == "dim")
local pend = UWMInvoice.new()
pend.sellerFarmId, pend.buyerFarmId, pend.creatorFarmId, pend.fillTypeIndex, pend.liters = 1, 2, 1, FillType.WHEAT, 5000
check("card: waiting for the buyer = green, bulk icon, silo pipe", UWMFrame.getInvoiceCard(pend, 2).statusColor == "greenLight"
    and UWMFrame.getInvoiceCard(pend, 2).icon == "bulk" and UWMFrame.getInvoiceCard(pend, 2).sub:find("Farma silo pipe", 1, true) ~= nil)
check("card: the sender sees it grey", UWMFrame.getInvoiceCard(pend, 1).statusColor == "grey")
local sum = UWMFrame.getSummary(M, 2)
check("summary: four cards with texts", #sum == 4 and sum[1].value ~= nil and sum[4].sub == "at the depot")

print(string.format("depot: %d passed, %d failed", passed, failed))
return failed
