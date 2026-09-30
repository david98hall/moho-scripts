ScriptName = "DW_ExportSpriteSheet"

DW_ExportSpriteSheet = {}

-- Shared storage: visible to both the script table and the
-- internal copy Moho makes when the dialog is shown.
DW_ExportSpriteSheet.values = {}
DW_ExportSpriteSheet.ctrls = {}

function DW_ExportSpriteSheet:Name()
    return "Export Sprite Sheet"
end

function DW_ExportSpriteSheet:Version()
    return "2.1"
end

function DW_ExportSpriteSheet:Description()
    return "Exports a frame range as PNGs and packs them into a spritesheet using ImageMagick."
end

function DW_ExportSpriteSheet:Creator()
    return "David"
end

function DW_ExportSpriteSheet:UILabel(moho)
    return "Export Sprite Sheet"
end

function DW_ExportSpriteSheet:Run(moho)
    local doc = moho.document

    -- Build the dialog
    local dialog = LM.GUI.SimpleDialog("Export Sprite Sheet", self)
    local layout = dialog:GetLayout()
    DW_ExportSpriteSheet.ctrls.start = LM.GUI.TextControl(0, tostring(doc:StartFrame()), 0, LM.GUI.FLOAT, "Start frame:")
    DW_ExportSpriteSheet.ctrls.finish = LM.GUI.TextControl(0, tostring(doc:EndFrame()), 0, LM.GUI.FLOAT, "End frame:")
    layout:AddChild(DW_ExportSpriteSheet.ctrls.start)
    layout:AddChild(DW_ExportSpriteSheet.ctrls.finish)

    if dialog:DoModal() == 0 then
        return  -- user cancelled
    end

    -- Values were stashed by OnOK; fall back to document defaults
    local startFrame = DW_ExportSpriteSheet.values.start or doc:StartFrame()
    local endFrame = DW_ExportSpriteSheet.values.finish or doc:EndFrame()
    if endFrame < startFrame then startFrame, endFrame = endFrame, startFrame end
    print("Exporting frames " .. startFrame .. " to " .. endFrame)

    local w = doc:Width()
    local h = doc:Height()
    local frameCount = endFrame - startFrame + 1

    -- Power-of-two grid: smallest n where n*n fits all frames
    local n = 1
    while n * n < frameCount do n = n * 2 end
    local cols, rows = n, n

    local projPath = doc:Path()
    if projPath == "" or projPath == nil then
        print("Error: save the project first - cannot determine export path.")
        return
    end
    local base = projPath:gsub("%.moho$", "")
    local exportDir = base .. "_frames"
    local sheetPath = base .. "_sheet.png"

    -- Create output directory
    os.execute('mkdir -p "' .. exportDir .. '"')

    -- 1) Render each frame
    for i = startFrame, endFrame do
        moho:SetCurFrame(i)
        moho:FileRender(string.format("%s/frame_%04d.png", exportDir, i))
    end

    -- 2) Pack with ImageMagick (hardcoded known-good path from `which magick`)
    local magick = "/usr/local/bin/magick"
    local cmd = string.format(
        '"%s" montage "%s/frame_*.png" -tile %dx%d -geometry %dx%d+0+0 -background none "%s"',
        magick, exportDir, cols, rows, w, h, sheetPath)
    os.execute(cmd)

    -- 3) Verify by checking the output file exists (os.execute's return
    --    value is unreliable in Moho's Lua build)
    local f = io.open(sheetPath, "r")
    if f then
        f:close()
        print(string.format("Done: %d frames (%dx%d) -> %dx%d sheet: %s",
            frameCount, w, h, cols * w, rows * h, sheetPath))
    else
        local handle = io.popen(cmd .. " 2>&1")
        local err = handle:read("*a")
        handle:close()
        print("ImageMagick failed. Error output:\n" .. tostring(err))
    end
end

-- Called on the dialog's internal copy when the user presses OK.
-- self here is the copy, but DW_ExportSpriteSheet is the shared class
-- table, so we can reach the controls and publish the typed values.
function DW_ExportSpriteSheet:OnOK()
    local c = DW_ExportSpriteSheet.ctrls
    local function read(ctrl, fallback)
        local v = tonumber(ctrl:Value())
        if v == nil then v = ctrl:IntValue() end
        if v == nil or v == 0 then v = fallback end
        return math.floor(v)
    end
    DW_ExportSpriteSheet.values.start = read(c.start, 1)
    DW_ExportSpriteSheet.values.finish = read(c.finish, 0)
end