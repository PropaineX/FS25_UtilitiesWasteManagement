import sys, pathlib
sys.path.insert(0, sys.argv[1])
from lupa import lua51

mod, tests = pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
lua = lua51.LuaRuntime()
runner = lua.execute("return function(s, n) local f, e = loadstring(s, n) if not f then error(e) end return f() end")

def run(path):
    return runner(path.read_text(encoding="utf-8"), "@" + path.name)

# the real English texts from modDesc.xml, so tests can check what players will read
import xml.etree.ElementTree as ET
texts = lua.table_from({e.get("name"): e.findtext("en") for e in ET.parse(mod / "modDesc.xml").iter("text")})
lua.globals().UWM_TEXTS = texts

run(tests / "stubs.lua")
for name in ["UWMInvoice", "UWMListing", "UWMStock", "UWMPallets", "UWMManager", "UWMEvents", "UWMPickup", "UWMDepot", "UtilitiesWasteManagement", "gui/UWMFrame", "gui/UWMGui", "gui/UWMWizard", "gui/UWMOrderDialog", "gui/UWMCoopDialog"]:
    run(mod / "scripts" / (name + ".lua"))
failed = run(tests / "scenarios.lua")
failed = failed + run(tests / "form_scenarios.lua")
failed = failed + run(tests / "depot_scenarios.lua")
sys.exit(1 if failed else 0)
