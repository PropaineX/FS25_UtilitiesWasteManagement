# 0.6.0.0 — October 26, 2026

The depot now includes the approved manure pit in front of the slurry tank. Its open end faces the same
direction as the office door, with manure pickup at that entrance. The UNIA silos/dryer and the marked
pallet pad beside the office are decorative for now; the pad does not spawn pallets.

The pit has building and tip collisions on all three walls. Placement and ground preparation cover the
new layout, and the shop picture shows the updated model. Export regenerates the depot's XML node mappings.

Standing offers also protect reserved stock during the production chain's automatic output processing.
The headless scenario for 1,000,000 charge stored and 500,000 offered sells only the other 500,000;
new surplus remains available and withdrawing the offer releases its unsold reservation.

Validation: 184 headless scenarios pass; Lua syntax, XML and localization checks pass; all 21 depot node
mappings resolve. The exported model was visually checked in GIANTS Editor. The relocated manure pickup,
placement and automatic production sale integration still require in-game testing.

Testing artifact: `FS25_UtilitiesWasteManagement.zip`, 13,072,296 bytes, 46 runtime files, each verified
against source. Source tools, tests and previews are excluded from the ZIP.

SHA-256: `72332267af80c7bd828bacdca6d403495403f67f9afe789d70426d323b004910`
