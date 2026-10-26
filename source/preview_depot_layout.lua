-- Preview the actual exported depot, with its runtime base-game Farma model.
local function find(node, name)
    if getName(node) == name then return node end
    for i = 0, getNumOfChildren(node)-1 do
        local found = find(getChildAt(node, i), name)
        if found ~= nil then return found end
    end
end
local depot = find(getRootNode(), "depot")
assert(depot ~= nil, "Open the exported depot.i3d first")
local farma = find(depot, "farma400")
if getNumOfChildren(farma) == 0 then
    local loaded = loadI3DFile("G:/SteamLibrary/steamapps/common/Farming Simulator 25/data/placeables/unia/farma/farma400/farma400.i3d")
    link(farma, getChildAt(loaded, 0))
    delete(loaded)
end
for _, name in ipairs({"pipeEffect", "pipeEffectSmoke", "loadingTrigger", "exactFillRootNode", "infoTrigger", "aiSpline"}) do
    local node = find(farma, name)
    if node ~= nil then setVisibility(node, false) end
end
local cam = createCamera("layoutPreview", math.rad(38), 0.1, 800)
link(getRootNode(), cam)
function depotLayoutView(overhead)
    if overhead then
        setTranslation(cam, -4, 68, -7)
        setDirection(cam, 0, 1, 0, 1, 0, 0)
    else
        setTranslation(cam, -47, 36, 12)
        setDirection(cam, -43, 32, 19, 0, 1, 0)
    end
    setCamera(cam)
end
depotLayoutView(false)
print("[UWM LAYOUT] actual model ready: manure pit + decorative pallet area")
