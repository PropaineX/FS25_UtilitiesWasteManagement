# Utilities & Waste Management (FS25)

Farming Simulator 25 mod by PropaineX. Version 0.6.0.0 (work in progress).

Farms trade **electricity, slurry and manure** with each other through invoices, in multiplayer or with
several farms in singleplayer.

- A **Utilities** page in the ESC menu. The farm manager sends a bill (to sell) or an order (to buy) to
  another farm; that farm's manager accepts or declines. Only farm managers can trade.
- Set an amount, or take **all of it** (everything the seller has in stock). Your own price per 1,000 liters
  (or kWh), with the game's price shown as a guide. One-off, or a standing contract every day or every week.
- **Electricity** goes straight from the seller's power-producing productions into the buyer's chosen
  productions, and is paid for as it arrives.
- **Slurry and manure** are paid for up front. Anyone on the buying farm collects them at the community depot:
  slurry at the tank coupling, manure at the open end of the manure pit. The R list shows only what was paid for, and the liters come out of the
  seller's stock. The buyer can **reserve** the liters so the seller can't use them. Liters never collected are
  refunded when the invoice ends.
- **Details** on every invoice: ordered, delivered / collected, refunded, what the buyer paid and the seller got.
  Finished invoices can be deleted from your own list (or the whole history cleared).
- Payments show on the finance page as "Utility sales" / "Utility purchases". Everything is saved with the
  savegame and synced to every player.

The depot includes the slurry tank, UNIA silos/dryer, office, and a concrete manure pit facing the same way as
the office door. Manure pickup is available only at the pit entrance. The UNIA silos/dryer are decorative,
with no active storage or pickup. The concrete pallet area beside the office is also decorative for now.
The 0.6.0.0 layout was exported and visually checked in GIANTS Editor; the relocated manure pickup still needs
an in-game check. A 0.6.0.0 testing ZIP has been built; see `RELEASE_NOTES.md` for validation and its SHA-256.

## Files
- `modDesc.xml` - mod description and all texts
- `scripts/UtilitiesWasteManagement.lua` - startup, saving, join sync, notifications, finance rows
- `scripts/UWMInvoice.lua` - one invoice: fields, network and savegame read/write
- `scripts/UWMManager.lua` - the trading rules (server side)
- `scripts/UWMStock.lua` - a farm's storages, taking goods out, putting electricity in, reservations
- `scripts/UWMPickup.lua` - buyers collecting paid goods at the depot
- `scripts/UWMEvents.lua` - network events
- `scripts/gui/UWMFrame.lua`, `gui/UWMFrame.xml` - the ESC menu page
- `scripts/gui/UWMWizard.lua` - the new-invoice / accept steps
- `icon_UtilitiesWasteManagement.dds` - mod icon (`.png` = its source)
- `tests/` - headless tests of the trading logic (Lua 5.1 via the Python package `lupa`), not part of the mod
- `tools/build_zip.py` - builds the mod zip from the shipped files
- `previews/` - icon drafts and the scripts that drew them
- `DESIGN.md` - the design and the rules it follows

## Install
Run `python tools/build_zip.py FS25_UtilitiesWasteManagement.zip` (or zip `modDesc.xml`, the icon `.dds`,
`gui/` and `scripts/` with forward-slash paths, modDesc.xml at the top) and put the zip in the FS25 `mods`
folder. Don't rename the zip.

## Tests
`python tests/run.py <folder with lupa> . tests` runs the trading scenarios; `python tests/check.py <folder with
lupa> .` checks Lua syntax, XML and that every text key exists.

## License
MIT, see `LICENSE`.
