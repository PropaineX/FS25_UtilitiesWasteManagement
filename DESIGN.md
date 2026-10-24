# Utilities & Waste Management (FS25) - design

Author PropaineX. Started 2026-10-23. Status 2026-10-24: all stages written; the depot (stage 3) is in 0.4.0.0
(source only, not yet tried in game). File notes in CLAUDE.md.

Farms trade **electricity, slurry and manure** with each other through invoices. (Propane removed by the user,
2026-10-23.)
Money only moves between farms (never from the game's market). Multiplayer first; works in singleplayer with
several farms too.

Zip / mod name: `FS25_UtilitiesWasteManagement.zip` (FS25 mod names allow only letters, digits and `_`; the
`&` in this folder name can't be in the zip name). Title: "Utilities & Waste Management".

## Goods

| Good | Fill type | Delivery |
|---|---|---|
| Electricity | `ELECTRICCHARGE` (base game; Fed pack productions use it) | Automatic: taken from the seller's productions, put into the buyer's productions the buyer picked |
| Slurry | `LIQUIDMANURE` | Buyer collects at the building's liquid fill point, drawn from the seller's stock |
| Manure | `MANURE` | Buyer collects at the building's bulk fill point, drawn from the seller's stock |

Digestate (`DIGESTATE`) could be added later on the slurry point if wanted (not planned).

## Invoices

- **Either side starts:** the seller sends a *bill* (offer) or the buyer sends an *order*. The other farm accepts or
  declines. **Only the farm manager** of each farm can send, accept, decline or cancel (user's rule, 2026-10-23).
  Other players on the farm can view the invoices, nothing more. Checked on the server with
  `farm:isUserFarmManager(userId)` for the player who sent the request (the client only greys out the buttons).
  **Once the invoice is paid, anyone on the buying farm can do the hauling** (load out at the building) (user's
  rule, 2026-10-23). Before it is paid, nobody can load.
- Fields: good, liters, price per 1,000 L (free; the current market sell price is shown next to it as a guide),
  and for electricity the buyer's receiving productions.
- **One-off or recurring**, chosen per invoice. Recurring = a standing contract: "X L every in-game day / week
  at $Y", runs until either side cancels.
- States: Pending -> Accepted -> (Delivering) -> Done, or Declined / Cancelled / Failed (e.g. seller short of stock or
  buyer short of money; partial deliveries are billed for what was actually delivered).
- Payment:
  - Manure / slurry: the buyer pays the full invoice when it is accepted (contracts: each period), because hauling
    only opens after payment. If the trade ends with liters never handed over (seller short of stock, invoice
    cancelled), the buyer gets back the money for the liters not loaded.
  - Electricity: paid as it is delivered (delivery is instant), only for what actually arrived.
  - Shows in the finance page as its own income/expense rows.

## Standing orders (user's idea, 2026-10-24)

An order put up for **every farm** instead of billed to one farm. Two kinds, all three goods:
- **Standing offer (selling):** "I have 1,000,000 l of slurry". Any farm buys **any amount** up to what's left (no
  minimum, no maximum, one farm may take it all) and pays at once; the poster is paid for each purchase.
- **Standing order (buying, "wanted"):** "I want 1,000,000 l". Any farm sells **any amount it has** up to what's
  left and is paid at once. When it reaches the full amount it stops: complete.
- **Anyone can see and use it** (user): every depot member; same depot lock as invoices.
- **The offer freezes the poster's stock** (user: "freeze my stock or reserve it"): from posting until sold out or
  withdrawn, what's left can't be loaded out, sold by invoice or put on another offer.
- Claude's mirror of that for wanted orders (2026-10-24, tell the user): the **money for the whole order is taken
  when posting and held**; sellers are paid from it; withdrawing gives back what's still held.
- Every purchase / sale is a normal paid invoice between the poster and that farm (reserved for the buyer, collected
  at the depot; electricity goes straight into the buyer's productions, paid only for what fits).
- Only the poster's farm manager withdraws it; finished ones go to the poster's history (Delete / Clear history).

**Page layout (user, 2026-10-24, from screenshots of another mod's invoicing page: "very similar, don't copy"):**
menu driven with tabs, not one long list. Mock-up `previews/menu_v1_*.png` (`previews/menu_mockup_v1.py`), OK'd by
the user and built in 0.5.0.0: header (icon, title, depot status, BALANCE box), tabs INCOMING / OUTGOING / STANDING ORDERS, the
last with sub-tabs MARKET / MY ORDERS / MY DEALS, column headings, empty-list line, key hints at the bottom.
ESC menu tab icon: a water drop with a lightning bolt inside (user, 2026-10-24), also the page header icon.

## Collecting manure and slurry (user's rule, 2026-10-23)

**Two places to collect (user's choice, 2026-10-23, after the first MP test):** (1) at the SELLER's own loading
points (slurry pit, manure heap, silo) - built in 0.2.0.0; (2) at a pickup building (depot) any farm can place on
its own land, so the buyer doesn't have to drive to the seller - still to build. Both draw from the seller's stock.

### The pickup building

The building is **only a pickup spot**; it stores nothing. When the buyer loads at the building, every liter that
flows into the buyer's vehicle is deducted live from the seller's own stock (silos, production points, animal
manure heaps / slurry pits). The seller never hauls. (Replaces the earlier "depot or draw, per invoice" choice:
there is no depot mode.)

The fill point only offers a farm what it has paid for and not yet collected (the R list shows those goods only),
and loading stops when the paid liters are collected or the seller's stock runs out.

**Community depot (user's rules, 2026-10-23):**
- It's the server's "community government central" for waste management and electricity. **Any farm can collect
  any paid invoice at the depot**, whoever placed it and whoever the seller is; the R list shows each buyer their own
  paid goods from all their sellers.
- **Price $268,000, upkeep 0.1 % = $268 per in-game day** (user, 2026-10-24: "use the game's 0.1 %", the base-game
  silo rate - Farma 400 $120/day on $117,000; earlier tries 1 % and 0.17 % dropped). On the user's server one
  month is one day (every sleep = a new day = a new month), so daily and monthly are the same. The upkeep is split
  equally between the owner and every farm that agreed to be a member. Placeable XML: dailyUpkeep 268.
- **What each part does** (user, 2026-10-24): the tank's pump coupling = **slurry** pickup, the Farma 400's
  loading pipe = **manure** pickup (its pipe effect runs while loading, otherwise hidden), the office door =
  opens the **Utilities** page.
- **One farm owns it and pays the bills** (price + upkeep). Sharing the cost is up to the owner: free, or a
  **recurring cost-share invoice** that splits the cost between the farms (e.g. three ways) and bills them every month.
- **Only one depot on the map.** A setting, default ON; when it's off, more can be placed. It's a **server
  setting: only the server admin can switch it** (user, 2026-10-23).

**Depot membership (user's flow, 2026-10-23):**
1. One farm builds the depot. The depot then **sends a membership invoice to every other farm on the map**, and to
   **every farm created later**: "Do you want to use this depot?", showing what it will cost. Yes / No.
2. **No** = that farm can't use the depot, until it **files a request**; the depot then sends it a new membership
   invoice.
3. **Upkeep is shared equally and taken automatically, like any building's upkeep - no invoice** (user's rule,
   2026-10-23). Everyone participating (the owner and every member) pays the same share. Claude's choice of timing:
   the game charges the owner the depot's normal upkeep; each in-game day (also when sleeping skips to the next
   day) every member pays the owner his equal share of that day's upkeep, so in the end all pay the same.
4. **Two missed monthly payments in a row = suspended**: can't use the depot until the late payments are paid. The
   depot sends an invoice for what is owed. With automatic payment, "missed" = the member didn't have the money
   when his share was due; the unpaid shares add up as arrears. A month with unpaid arrears at its end counts as
   missed; two such months in a row suspend the farm, and paying the arrears invoice lifts it.

5. **"Using the depot" = buying and selling through it** (user, 2026-10-23). A farm that said No or is suspended
   can't buy or sell at the depot: its paid manure/slurry can't be collected there, and its goods can't be picked up
   there by others. **The mod blocks only two things for such a farm: the invoices and the depot** (user,
   2026-10-23): it can't send or accept invoices of this mod (electricity included), so it also gets no invoice
   pickups at a seller's barn. Nothing else in the game is blocked. Private deals between farms are their own
   business: how the product moves and how money changes hands is up to them, not the mod.
   Invoices already paid before a farm was suspended can still be finished (collected, or ended with a refund);
   only new ones are blocked (confirmed by the user).
6. **The depot works like a sell point** (user: "I can't sell to the farmer's market if the farmer's market isn't
   built"): the whole invoicing and selling can't happen until the depot is built. So the next build is the depot
   itself, with the invoice lock and the barn-pickup removal in the same build.
   **The invoices are tied to the depot** (user, 2026-10-23): **no depot on the map = no invoice system at all**
   ("without the depot you're doing things old school"). **No pick-up or delivery at individual farms**: the
   collecting at the seller's own barn / pit / heap (built in 0.2.0.0) is to be REMOVED; paid manure and slurry
   are collected only at the depot. **Electricity stays as it is** (user: "we can't physically touch that"):
   delivered straight from the seller's productions into the buyer's chosen productions, no depot pickup. It still
   needs a depot on the map and depot membership, like every invoice.

**As built in 0.4.0.0 (Claude's choices where the rules left room, 2026-10-24):**
- Membership is to "the depot" as a whole (one depot per map by default). With more depots allowed, the members'
  shares are split between the owners by each owner's part of the total upkeep; owners don't settle with each other.
- The share is taken on every in-game day; a member short of money pays nothing that day and the share goes on its
  arrears. Month end = the game's PERIOD_CHANGED. Arrears are paid in one go (Depot button), which lifts a suspension.
- No depot, or a seller/buyer not allowed to trade: a standing contract skips that period (status shows why).
- The farm manager answers the offer, asks again and pays arrears; the "more than one depot" switch is for the server
  admin (master user; the host / singleplayer player).
- The Utilities tab in the ESC menu is hidden until a depot stands on the map (user, 2026-10-24).
- **Leaving** (user, 2026-10-24): a member can leave (Depot button, confirmed with Yes/No); it then can't ask to rejoin
  for 6 in-game months (counted on PERIOD_CHANGED) and gets no automatic offer. Any debt to the depot is taken from
  the farm's account when it leaves, even into the negative (user, 2026-10-24); paid invoices can still be collected
  or ended. Depot owners get a message.

### Buyer's options on a manure / slurry invoice (user's rules, 2026-10-23)

- **Amount:** either a set number of liters, or **"I'll take all of it"** = everything the seller has in stock.
  "All of it" is fixed at the seller's stock at the moment the invoice is paid (only what's really in stock is
  billed, never more). On a standing contract, "all of it" = everything in stock at the start of each period
  (confirmed by the user).
- **Reserve:** a tick box the buyer can choose. When ticked, the paid liters are held for the buyer: the seller
  can't load out, sell or otherwise take their stock below the reserved amount until the buyer has collected or
  the invoice ends. Not ticked = the seller's stock stays free to use.
- **Shortfall:** if the buyer collects less than was paid for (stock ran out, invoice cancelled), the money for
  the missing liters is refunded to the buyer automatically.
- **No time limit to collect:** a paid invoice stays open until it is collected or cancelled (confirmed).

Reserve, implementation note: blocks the seller's own load triggers, sales and production use of that fill type
below the reserved level. Manure/slurry that the seller's animals keep adding is never blocked.

## Electricity

On each delivery (once on accept for one-off, every period for contracts): take ELECTRICCHARGE from the seller's
production-point storages, then fill the productions the buyer chose on the invoice, in the listed order, up to each
one's free capacity. Leftover that fits nowhere stays with the seller and is not billed.

## Where players manage it

- **ESC menu page "Utilities"**: new invoice, incoming, outgoing, contracts, history.
- **The building** (placeable): walking up opens the same screen, plus the bulk and liquid fill points.
  Placed by any farm, usable by every farm.

## Multiplayer / saving

- The server owns all invoices. Clients send requests as events (create, accept, decline, cancel); the server checks
  rights, stock and money, moves goods/money, and sends the new state to everyone.
- Invoices, contracts and liters still to collect are saved in the savegame (`utilitiesWasteManagement.xml`) and sent to
  players who join.

## Build order

1. Core: invoice data, events, server checks, money + goods transfer, save/load, electricity delivery.
2. ESC menu page.
3. Building: model (preview first), fill points drawing from the seller's stock.
4. Contracts (recurring), finance rows, notifications.

## Open questions

- Building look (to be shown as a preview before it's made).
