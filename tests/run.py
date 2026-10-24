import sys, pathlib
sys.path.insert(0, sys.argv[1])
from lupa import lua51

mod, tests = pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
lua = lua51.LuaRuntime()
runner = lua.execute("return function(s, n) local f, e = loadstring(s, n) if not f then error(e) end return f() end")

def run(path):
    return runner(path.read_text(encoding="utf-8"), "@" + path.name)

run(tests / "stubs.lua")
for name in ["UWMInvoice", "UWMStock", "UWMManager", "UWMEvents", "UWMPickup", "UtilitiesWasteManagement"]:
    run(mod / "scripts" / (name + ".lua"))
sys.exit(1 if run(tests / "scenarios.lua") else 0)
