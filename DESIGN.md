# Utilities & Waste Management (FS25) - design

Author PropaineX. Started 2026-10-23. Status: stages 1, 2 and 4 written (v0.1.0.0, untested in game); stage 3
(the pickup building) not started. File notes in CLAUDE.md.

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
