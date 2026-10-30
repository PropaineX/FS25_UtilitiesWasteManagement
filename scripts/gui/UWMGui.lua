-- Utilities & Waste Management: our GUI image sheet (gui/uwm_ui.dds, drawn by previews/ui_atlas_v1.py) and the
-- UWM CO-OP theme colours. Every icon, tile and card fill on our pages is a white cell of the sheet, tinted.
-- (A button / bitmap tinted without an image of its own drew the whole game GUI atlas: in-game test 2026-10-28.)
-- Author: PropaineX

UWMGui = {}

UWMGui.FILENAME = "gui/uwm_ui.dds"
UWMGui.SIZE = 512
UWMGui.CELL = 64
-- cell order of the sheet (8 per row)
UWMGui.ICONS = {"solid", "tile", "bill", "tray", "cart", "tag", "slurry", "manure", "power", "bulk", "pallet", "farm", "depot",
    "arrow", "pencil", "drop", "pill"}

UWMGui.COLOR = {
    card = {0.110, 0.114, 0.106, 1},
    tint = {0.196, 0.235, 0.110, 1},
    tile = {0.157, 0.173, 0.133, 1},
    green = {0.525, 0.694, 0.067, 1},
    greenLight = {0.651, 0.784, 0.235, 1},
    dark = {0.110, 0.133, 0.047, 1},
    white = {0.922, 0.922, 0.922, 1},
    grey = {0.667, 0.667, 0.647, 1},
    dim = {0.431, 0.439, 0.412, 1},
    orange = {0.902, 0.667, 0.235, 1},
    blue = {0.431, 0.667, 0.902, 1}
}

-- goods -> icon
function UWMGui.getGoodsIcon(fillTypeIndex, isPallet)
    if isPallet then
        return "pallet"
    elseif fillTypeIndex == FillType.ELECTRICCHARGE then
        return "power"
    elseif fillTypeIndex == FillType.LIQUIDMANURE then
        return "slurry"
    elseif fillTypeIndex == FillType.MANURE then
        return "manure"
    end
    return "bulk"
end

local function getCellUVs(name)
    for i, iconName in ipairs(UWMGui.ICONS) do
        if iconName == name then
            local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
            local c = UWMGui.CELL
            return GuiUtils.getUVs({col * c, row * c, c, c}, {UWMGui.SIZE, UWMGui.SIZE})
        end
    end
    return nil
end

-- shows a cell of the sheet on a Bitmap (or any element with an image); only reloads when the cell changes
function UWMGui.setIcon(element, name)
    if element == nil or element.setImageFilename == nil or element.uwmIcon == name then
        return
    end
    local uvs = getCellUVs(name)
    if uvs == nil then
        return
    end
    element:setImageFilename(UtilitiesWasteManagement.modDirectory .. UWMGui.FILENAME)
    if element.setImageUVs ~= nil then
        element:setImageUVs(nil, unpack(uvs))
    end
    element.uwmIcon = name
end

function UWMGui.setColor(element, colorName)
    local c = UWMGui.COLOR[colorName]
    if element ~= nil and c ~= nil and element.setImageColor ~= nil then
        element:setImageColor(nil, c[1], c[2], c[3], c[4])
    end
end

function UWMGui.setTextColor(element, colorName)
    local c = UWMGui.COLOR[colorName]
    if element ~= nil and c ~= nil and element.setTextColor ~= nil then
        element:setTextColor(c[1], c[2], c[3], c[4])
    end
end

-- every element below `root` whose name / id starts with "uwmImg_<cell>" gets that cell (static parts of a page)
function UWMGui.applyStaticImages(root)
    if root == nil then
        return
    end
    local function walk(element)
        local key = element.name or element.id
        if type(key) == "string" then
            local cell = key:match("^uwmImg_(%a+)")
            if cell ~= nil then
                UWMGui.setIcon(element, cell)
            end
        end
        for _, child in ipairs(element.elements or {}) do
            walk(child)
        end
    end
    walk(root)
end
