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
    return DW_ExportSpriteSheet.values.creator or "David"
end

function DW_ExportSpriteSheet:UILabel(moho)
    return "Export Sprite Sheet"
end

function DW_ExportSpriteSheet:Run(moho)
    local doc = moho.document

    -- Default output locations, derived from the saved project path
    local projPath = doc:Path()
    local projDir = ""
    local projBase = "sprite_sheet"
    if projPath ~= nil and projPath ~= "" then
        projDir = projPath:gsub("[^/\\]+$", "")
        projBase = projPath:sub(#projDir + 1):gsub("%.moho$", "")
        if projBase == "" then projBase = "sprite_sheet" end
    end
    local defaultDir = projDir
    local defaultName = projBase .. "_sheet.png"

    -- Build the dialog (prefilled with the last used values, else defaults)
    local v = DW_ExportSpriteSheet.values
    local dialog = LM.GUI.SimpleDialog("Export Sprite Sheet", self)
    local layout = dialog:GetLayout()
    local c = DW_ExportSpriteSheet.ctrls
    c.start = LM.GUI.TextControl(0, tostring(doc:StartFrame()), 0, LM.GUI.FIELD_FLOAT, "Start frame:")
    c.finish = LM.GUI.TextControl(0, tostring(doc:EndFrame()), 0, LM.GUI.FIELD_FLOAT, "End frame:")
    c.creator = LM.GUI.TextControl(0, v.creator or "David", 0, LM.GUI.FIELD_TEXT, "Creator:")
    c.outDir = LM.GUI.TextControl(0, v.outDir or defaultDir, 0, LM.GUI.FIELD_TEXT, "Output folder:")
    c.sheetName = LM.GUI.TextControl(0, v.sheetName or defaultName, 0, LM.GUI.FIELD_TEXT, "Sheet name:")
    layout:AddChild(c.start)
    layout:AddChild(c.finish)
    layout:AddChild(c.creator)
    layout:AddChild(c.outDir)
    layout:AddChild(c.sheetName)

    if dialog:DoModal() == 0 then
        return  -- user cancelled
    end

    -- Values were stashed by OnOK; fall back to document defaults
    local startFrame = v.start or doc:StartFrame()
    local endFrame = v.finish or doc:EndFrame()
    if endFrame < startFrame then startFrame, endFrame = endFrame, startFrame end
    print("Exporting frames " .. startFrame .. " to " .. endFrame)

    -- Output location: dialog values, else project-derived defaults
    local outDir = v.outDir or defaultDir
    local sheetName = v.sheetName or defaultName
    if outDir == "" then
        print("Error: save the project first or set an output folder.")
        return
    end
    if outDir:sub(-1) == "/" or outDir:sub(-1) == "\\" then
        outDir = outDir:sub(1, -2)
    end
    if sheetName:sub(-4):lower() ~= ".png" then
        sheetName = sheetName .. ".png"
    end
    local exportDir = outDir .. "/" .. sheetName:gsub("%.png$", "") .. "_frames"
    local sheetPath = outDir .. "/" .. sheetName

    local w = doc:Width()
    local h = doc:Height()
    local frameCount = endFrame - startFrame + 1

    -- Power-of-two grid: smallest n where n*n fits all frames
    local n = 1
    while n * n < frameCount do n = n * 2 end
    local cols, rows = n, n

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
    local function readText(ctrl)
        local s = ctrl:Value()
        if s == nil then s = "" end
        s = s:gsub("^%s*(.-)%s*$", "%1")
        if s == "" then return nil end
        return s
    end
    DW_ExportSpriteSheet.values.start = read(c.start, 1)
    DW_ExportSpriteSheet.values.finish = read(c.finish, 0)
    DW_ExportSpriteSheet.values.creator = readText(c.creator)
    DW_ExportSpriteSheet.values.outDir = readText(c.outDir)
    DW_ExportSpriteSheet.values.sheetName = readText(c.sheetName)
end