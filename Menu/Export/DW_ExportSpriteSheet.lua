ScriptName = "DW_ExportSpriteSheet"

DW_ExportSpriteSheet = {}

-- Shared storage: visible to both the script table and the
-- internal copy Moho makes when the dialog is shown.
DW_ExportSpriteSheet.values = {}
DW_ExportSpriteSheet.ctrls = {}

-- Random v4-style GUID, used to name the temporary frame folder so
-- concurrent runs never collide and old leftovers are easy to spot.
local function GUID()
    math.randomseed(os.time() + math.floor(os.clock() * 1000000))
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (template:gsub("[xy]", function(char)
        local randomValue = math.random(0, 15)
        local hexValue = (char == "x") and randomValue or (randomValue % 4 + 8)
        return string.format("%x", hexValue)
    end))
end

-- Path of the rendered frame for frame number frameIndex inside directory
local function framePath(directory, frameIndex)
    return string.format("%s/frame_%04d.png", directory, frameIndex)
end

local function mkdir(directory)
    os.execute('mkdir -p "' .. directory .. '"')
end

function DW_ExportSpriteSheet:Name()
    return "Export Sprite Sheet"
end

function DW_ExportSpriteSheet:Version()
    return "2.2"
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
    local document = moho.document

    -- Default output locations, derived from the saved project path
    local projectPath = document:Path()
    local projectDirectory = ""
    local projectBaseName = "sprite_sheet"
    if projectPath ~= nil and projectPath ~= "" then
        projectDirectory = projectPath:gsub("[^/\\]+$", "")
        projectBaseName = projectPath:sub(#projectDirectory + 1):gsub("%.moho$", "")
        if projectBaseName == "" then projectBaseName = "sprite_sheet" end
    end
    local defaultName = projectBaseName .. "_sheet.png"

    -- Build the dialog (prefilled with the last used values, else defaults)
    local values = DW_ExportSpriteSheet.values
    local dialog = LM.GUI.SimpleDialog("Export Sprite Sheet", self)
    local layout = dialog:GetLayout()
    local ctrls = DW_ExportSpriteSheet.ctrls
    ctrls.start = LM.GUI.TextControl(0, tostring(document:StartFrame()), 0, LM.GUI.FIELD_FLOAT, "Start frame:")
    ctrls.finish = LM.GUI.TextControl(0, tostring(document:EndFrame()), 0, LM.GUI.FIELD_FLOAT, "End frame:")
    ctrls.creator = LM.GUI.TextControl(0, values.creator or "David", 0, LM.GUI.FIELD_TEXT, "Creator:")
    ctrls.outDir = LM.GUI.TextControl(0, values.outDir or projectDirectory, 0, LM.GUI.FIELD_TEXT, "Output folder:")
    ctrls.sheetName = LM.GUI.TextControl(0, values.sheetName or defaultName, 0, LM.GUI.FIELD_TEXT, "Sheet name:")
    ctrls.magickPath = LM.GUI.TextControl(0, values.magickPath or "/usr/local/bin/magick", 0, LM.GUI.FIELD_TEXT, "ImageMagick path:")
    layout:AddChild(ctrls.start)
    layout:AddChild(ctrls.finish)
    layout:AddChild(ctrls.creator)
    layout:AddChild(ctrls.outDir)
    layout:AddChild(ctrls.sheetName)
    layout:AddChild(ctrls.magickPath)

    if dialog:DoModal() == 0 then
        return  -- user cancelled
    end

    -- Values were stashed by OnOK; fall back to document defaults
    local startFrame = values.start or document:StartFrame()
    local endFrame = values.finish or document:EndFrame()
    if endFrame < startFrame then startFrame, endFrame = endFrame, startFrame end
    print("Exporting frames " .. startFrame .. " to " .. endFrame)

    -- Output location: dialog values, else project-derived defaults
    local outDir = values.outDir or projectDirectory
    local sheetName = values.sheetName or defaultName
    if outDir == "" then
        print("Error: save the project first or set an output folder.")
        return
    end
    local lastChar = outDir:sub(-1)
    if lastChar == "/" or lastChar == "\\" then
        outDir = outDir:sub(1, -2)
    end
    if sheetName:sub(-4):lower() ~= ".png" then
        sheetName = sheetName .. ".png"
    end
    local sheetPath = outDir .. "/" .. sheetName

    local documentWidth = document:Width()
    local documentHeight = document:Height()
    local frameCount = endFrame - startFrame + 1

    -- Near-square grid sized to the frame count: cols*rows fits every
    -- frame with no extra empty rows, so the sheet is as small as
    -- possible for the given frame size
    local cols = math.ceil(math.sqrt(frameCount))
    local rows = math.ceil(frameCount / cols)

    -- Create the output directory and a hidden temp folder (unique GUID
    -- name) that holds the rendered frames only until the sheet is packed
    mkdir(outDir)
    local tmpBase = os.getenv("TMPDIR") or "/tmp/"
    if tmpBase:sub(-1) ~= "/" then tmpBase = tmpBase .. "/" end
    local exportDir = tmpBase .. ".DW_ExportSpriteSheet_" .. GUID()
    mkdir(exportDir)

    -- 1) Render each frame
    for frameIndex = startFrame, endFrame do
        moho:SetCurFrame(frameIndex)
        moho:FileRender(framePath(exportDir, frameIndex))
    end

    -- 2) Pack with ImageMagick (path from the dialog, else the default)
    --    +label stops montage from drawing filename labels under each frame,
    --    which would need a font and add extra pixels to the sheet
    local magick = values.magickPath or "/usr/local/bin/magick"

    -- Frame size as actually rendered (may differ from document:Width()/Height()
    -- if the render settings scale the output); fall back to the document size
    local frameWidth, frameHeight = documentWidth, documentHeight
    local firstFrame = framePath(exportDir, startFrame)
    local identifyHandle = io.popen('"' .. magick .. '" identify -format "%w %h" "' .. firstFrame .. '" 2>/dev/null')
    if identifyHandle then
        local identifyOutput = identifyHandle:read("*a")
        identifyHandle:close()
        local identifiedWidth, identifiedHeight = identifyOutput:match("^(%d+)%s+(%d+)")
        if identifiedWidth and identifiedHeight then frameWidth, frameHeight = tonumber(identifiedWidth), tonumber(identifiedHeight) end
    end

    local command = string.format(
        '"%s" montage +label "%s/frame_*.png" -tile %dx%d -geometry %dx%d+0+0 -background none "%s"',
        magick, exportDir, cols, rows, frameWidth, frameHeight, sheetPath)
    os.execute(command)

    -- 3) Verify by checking the output file exists (os.execute's return
    --    value is unreliable in Moho's Lua build)
    local sheetFile = io.open(sheetPath, "r")
    if sheetFile then
        sheetFile:close()
        os.execute('rm -rf "' .. exportDir .. '"')
        print(string.format("Done: %d frames (%dx%d, grid %dx%d) -> %dx%d sheet: %s",
            frameCount, frameWidth, frameHeight, cols, rows, cols * frameWidth, rows * frameHeight, sheetPath))
    else
        local commandHandle = io.popen(command .. " 2>&1")
        local errorOutput = commandHandle:read("*a")
        commandHandle:close()
        print("ImageMagick failed. Error output:\n" .. tostring(errorOutput))
        print("Frames were kept for inspection in: " .. exportDir)
    end
end

-- Called on the dialog's internal copy when the user presses OK.
-- self here is the copy, but DW_ExportSpriteSheet is the shared class
-- table, so we can reach the controls and publish the typed values.
function DW_ExportSpriteSheet:OnOK()
    local ctrls = DW_ExportSpriteSheet.ctrls
    local values = DW_ExportSpriteSheet.values
    local function read(control, fallback)
        local frameNumber = tonumber(control:Value())
        if frameNumber == nil then frameNumber = control:IntValue() end
        if frameNumber == nil or frameNumber == 0 then frameNumber = fallback end
        return math.floor(frameNumber)
    end
    local function readText(control)
        local text = control:Value()
        if text == nil then text = "" end
        text = text:gsub("^%s*(.-)%s*$", "%1")
        if text == "" then return nil end
        return text
    end
    values.start = read(ctrls.start, 1)
    values.finish = read(ctrls.finish, 0)
    values.creator = readText(ctrls.creator)
    values.outDir = readText(ctrls.outDir)
    values.sheetName = readText(ctrls.sheetName)
    values.magickPath = readText(ctrls.magickPath)
end
