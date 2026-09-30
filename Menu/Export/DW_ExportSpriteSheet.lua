ScriptName = "DW_ExportSpriteSheet"

DW_ExportSpriteSheet = {}

-- Shared storage: visible to both the script table and the
-- internal copy Moho makes when the dialog is shown.
DW_ExportSpriteSheet.values = {}
DW_ExportSpriteSheet.ctrls = {}

-- Platform check: Windows runs shell commands through cmd.exe, which needs
-- different commands than a Unix shell. package.config starts with "\\" on
-- Windows; fall back to the OS environment variable in case Moho's Lua build
-- leaves package unavailable.
local isWindows = (package ~= nil and package.config ~= nil and package.config:sub(1, 1) == "\\")
    or (os.getenv("OS") == "Windows_NT")
-- /System/Library/CoreServices exists only on macOS (io.open succeeds on
-- Unix directories), which is how macOS is told apart from Linux here
local isMac = not isWindows and io.open("/System/Library/CoreServices", "rb") ~= nil
local SEP = isWindows and "\\" or "/"

-- cmd.exe strips the outermost quote pair when a command contains several
-- quoted arguments, which mangles quoted paths; an extra wrapping pair
-- survives the strip, so all shell commands go through these two functions
local function shell(command)
    if isWindows then command = '"' .. command .. '"' end
    return os.execute(command)
end

local function shellOut(command)
    if isWindows then command = '"' .. command .. '"' end
    return io.popen(command)
end

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
    return string.format("%s%sframe_%04d.png", directory, SEP, frameIndex)
end

-- Base directory for the temporary frame folder: TEMP/TMP on Windows
-- (TMPDIR only if some tool happened to set it), TMPDIR on macOS and
-- Linux, /tmp as a last resort
local function tempBase()
    local base
    if isWindows then
        base = os.getenv("TEMP") or os.getenv("TMP") or os.getenv("TMPDIR")
    else
        base = os.getenv("TMPDIR")
    end
    base = base or "/tmp/"
    local lastChar = base:sub(-1)
    if lastChar ~= "/" and lastChar ~= "\\" then
        base = base .. SEP
    end
    return base
end

local function mkdir(directory)
    if isWindows then
        -- cmd's mkdir builds intermediate directories but fails if the target
        -- already exists, so guard it (mkdir -p does both on Unix)
        shell('if not exist "' .. directory .. '" mkdir "' .. directory .. '"')
    else
        shell('mkdir -p "' .. directory .. '"')
    end
end

local function removeRecursively(directory)
    if isWindows then
        shell('rmdir /s /q "' .. directory .. '"')
    else
        shell('rm -rf "' .. directory .. '"')
    end
end

-- Default ImageMagick executable for this platform. ImageMagick 7 ships a
-- "magick" dispatcher; version 6 (still the default on many Linux distros)
-- has separate montage/identify tools, so fall back to those.
local function defaultMagickPath()
    if isWindows then
        return "magick"  -- the ImageMagick 7 installer adds it to PATH
    end
    local candidates = {
        "/usr/local/bin/magick",    -- Homebrew, Intel Mac
        "/opt/homebrew/bin/magick", -- Homebrew, Apple Silicon
        "/usr/bin/magick",          -- ImageMagick 7 distro package
        "/usr/bin/montage",         -- ImageMagick 6 distro package
    }
    for _, candidate in ipairs(candidates) do
        local file = io.open(candidate, "rb")
        if file then
            file:close()
            return candidate
        end
    end
    return candidates[1]
end

-- Command prefixes for ImageMagick's montage and identify operations: a
-- "magick" executable dispatches subcommands, any other executable (the
-- standalone montage of ImageMagick 6) is used directly, with identify
-- expected to live next to it
local function magickCommands(path)
    local name = (path:match("[^/\\]+$") or ""):lower():gsub("%.exe$", "")
    if name == "magick" then
        local quoted = '"' .. path .. '"'
        return quoted .. " montage", quoted .. " identify"
    end
    local directory = path:gsub("[^/\\]+$", "")
    return '"' .. path .. '"', '"' .. directory .. 'identify"'
end

function DW_ExportSpriteSheet:Name()
    return "Export Sprite Sheet"
end

function DW_ExportSpriteSheet:Version()
    return "2.4"
end

function DW_ExportSpriteSheet:Description()
    return "Exports a frame range as PNGs and packs them into a spritesheet using ImageMagick."
end

function DW_ExportSpriteSheet:Creator()
    return DW_ExportSpriteSheet.values.creator or ""
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
    local defaultMagick = defaultMagickPath()

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
    -- The ImageMagick override is only useful on macOS, which has no
    -- standard install location for it; other platforms find it through
    -- PATH or the distro package, so the field is not shown there
    if isMac then
        ctrls.magickPath = LM.GUI.TextControl(0, values.magickPath or defaultMagick, 0, LM.GUI.FIELD_TEXT, "ImageMagick path:")
    end
    layout:AddChild(ctrls.start)
    layout:AddChild(ctrls.finish)
    layout:AddChild(ctrls.creator)
    layout:AddChild(ctrls.outDir)
    layout:AddChild(ctrls.sheetName)
    if isMac then
        layout:AddChild(ctrls.magickPath)
    end

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
    local sheetPath = outDir .. SEP .. sheetName

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
    local exportDir = tempBase() .. ".DW_ExportSpriteSheet_" .. GUID()
    mkdir(exportDir)

    -- 1) Render each frame
    for frameIndex = startFrame, endFrame do
        moho:SetCurFrame(frameIndex)
        moho:FileRender(framePath(exportDir, frameIndex))
    end

    -- 2) Pack with ImageMagick (path from the dialog, else the platform default)
    --    +label stops montage from drawing filename labels under each frame,
    --    which would need a font and add extra pixels to the sheet
    local magick = (isMac and values.magickPath) or defaultMagick
    local montageCommand, identifyCommand = magickCommands(magick)

    -- Frame size as actually rendered (may differ from document:Width()/Height()
    -- if the render settings scale the output); fall back to the document size.
    -- Width and height are identified in separate calls with a single % format
    -- each: cmd.exe would read the two percent signs of a "%w %h" format as an
    -- environment variable reference and could expand them.
    local frameWidth, frameHeight = documentWidth, documentHeight
    local firstFrame = framePath(exportDir, startFrame)
    local identifiedWidth, identifiedHeight
    for _, format in ipairs({ "%w", "%h" }) do
        local redirect = isWindows and " 2>nul" or " 2>/dev/null"
        local handle = shellOut(identifyCommand .. ' -format "' .. format .. '" "' .. firstFrame .. '"' .. redirect)
        if handle then
            local output = handle:read("*a")
            handle:close()
            local dimension = tonumber((output or ""):match("%d+"))
            if identifiedWidth == nil then
                identifiedWidth = dimension
            else
                identifiedHeight = dimension
            end
        end
    end
    if identifiedWidth and identifiedHeight then
        frameWidth, frameHeight = identifiedWidth, identifiedHeight
    end

    local command = string.format(
        '%s +label "%s" -tile %dx%d -geometry %dx%d+0+0 -background none "%s"',
        montageCommand, exportDir .. SEP .. "frame_*.png", cols, rows, frameWidth, frameHeight, sheetPath)
    shell(command)

    -- 3) Verify by checking the output file exists (os.execute's return
    --    value is unreliable in Moho's Lua build)
    local sheetFile = io.open(sheetPath, "r")
    if sheetFile then
        sheetFile:close()
        removeRecursively(exportDir)
        print(string.format("Done: %d frames (%dx%d, grid %dx%d) -> %dx%d sheet: %s",
            frameCount, frameWidth, frameHeight, cols, rows, cols * frameWidth, rows * frameHeight, sheetPath))
    else
        local commandHandle = shellOut(command .. " 2>&1")
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
    if ctrls.magickPath then
        values.magickPath = readText(ctrls.magickPath)
    end
end
