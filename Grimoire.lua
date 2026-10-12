--[[----------------------------------------------------------------------------
  Grimoire v1.0.0 (WotLK 3.3.5a client, Grimfall server / Ascension core)

  Lists what your character has, with what each thing does, in a copyable
  window (and in SavedVariables, per character):

    Abilities  spellbook, grouped by tab, highest rank only. Text is read from
               the spell tooltip, so custom server spells come out right too.
    Talents    every talent tab via GetTalentInfo + the talent tooltip.
               Learned only by default; "Show all talents" lists unlearned too.
    Runes      Grimfall's rune window is custom (no known API), so runes are
               CAPTURED: turn on Capture, open the rune window, hover each rune.
               Whatever tooltip appears is stored by its first line (the name).
    Discovery  helpers to find the real rune API for a later version:
               /grim scan  -- global functions/tables/frames named like
                              rune/talent/advancement/mystic/essence, plus C_*
               /grim mouse -- the frame under the cursor, its parents and the
                              text inside it (type it while hovering the rune
                              window, then press Enter)

  Copy: click the text, Ctrl+A, Ctrl+C. The same data is in
  WTF\Account\<acct>\<realm>\<char>\SavedVariables\Grimoire.lua after logout.
------------------------------------------------------------------------------]]

local ADDON_NAME = "Grimoire"
local VERSION    = "1.0.0"
local BOOK       = BOOKTYPE_SPELL or "spell"

local DISCOVER_PATTERNS = { "rune", "talent", "advancement", "mystic", "essence" }

GrimoireDB     = GrimoireDB or {}
GrimoireCharDB = GrimoireCharDB or {}

local db, cdb
local capturing = false
local currentTab = "abilities"

local function say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffb48cffGrimoire|r: " .. msg)
end

-- Remove colour codes, textures and surrounding whitespace.
local function clean(s)
    if not s then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-------------------------------------------------------------------------------
-- Tooltip reading
-------------------------------------------------------------------------------

local scanTip = CreateFrame("GameTooltip", "GrimoireScanTip", nil, "GameTooltipTemplate")

local function prepScan()
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
end

-- { {l=left, r=right}, ... } for every non-empty line of a tooltip.
local function readTip(tip)
    local name, out = tip:GetName(), {}
    if not name then return out end
    for i = 1, tip:NumLines() do
        local L = _G[name .. "TextLeft" .. i]
        local R = _G[name .. "TextRight" .. i]
        local lt = L and clean(L:GetText()) or ""
        local rt = (R and R:IsShown()) and clean(R:GetText()) or ""
        if lt ~= "" or rt ~= "" then out[#out + 1] = { l = lt, r = rt } end
    end
    return out
end

local function lineText(ln)
    if ln.r ~= "" and ln.l ~= "" then return ln.l .. "  /  " .. ln.r end
    return ln.l ~= "" and ln.l or ln.r
end

-- Spell tooltips: name first, description last, cost/range/cast in between.
local function splitSpellTip(lines)
    local details = {}
    for i = 2, #lines - 1 do
        local t = lineText(lines[i])
        if not t:match("^Rank %d+$") then details[#details + 1] = t end
    end
    local desc = #lines > 1 and lineText(lines[#lines]) or ""
    if desc:match("^Rank %d+$") then desc = "" end
    return table.concat(details, " | "), desc
end

-------------------------------------------------------------------------------
-- Collectors
-------------------------------------------------------------------------------

local function collectAbilities()
    local tabs = {}
    for t = 1, (GetNumSpellTabs() or 0) do
        local tabName, _, offset, num = GetSpellTabInfo(t)
        local list, index = {}, {}
        for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
            local name, rank = GetSpellName(i, BOOK)
            if name then
                prepScan()
                scanTip:SetSpell(i, BOOK)
                local details, desc = splitSpellTip(readTip(scanTip))
                local entry = {
                    name = name,
                    rank = (rank and rank ~= "") and rank or nil,
                    passive = IsPassiveSpell(i, BOOK) and true or nil,
                    details = details ~= "" and details or nil,
                    desc = desc,
                }
                -- Ranks are separate spellbook entries; the later one is higher.
                if index[name] then
                    list[index[name]] = entry
                else
                    list[#list + 1] = entry
                    index[name] = #list
                end
            end
        end
        tabs[#tabs + 1] = { name = tabName or ("Tab " .. t), spells = list }
    end
    return tabs
end

local function collectTalents()
    local tabs = {}
    for tab = 1, (GetNumTalentTabs() or 0) do
        local tabName, _, spent = GetTalentTabInfo(tab)
        local list = {}
        for i = 1, (GetNumTalents(tab) or 0) do
            local name, _, tier, column, rank, maxRank = GetTalentInfo(tab, i)
            if name then
                prepScan()
                scanTip:SetTalent(tab, i)
                local lines = readTip(scanTip)
                local body, reqs = {}, {}
                for n = 2, #lines do
                    local t = lineText(lines[n])
                    if t:match("^Next [Rr]ank") then break end
                    if t:match("^Rank %d+/%d+") or t:match("^Click") then
                        -- shown separately / UI hint
                    elseif t:match("^Requires") then
                        reqs[#reqs + 1] = t
                    else
                        body[#body + 1] = t
                    end
                end
                list[#list + 1] = {
                    name = name, tier = tier or 0, column = column or 0,
                    rank = rank or 0, maxRank = maxRank or 0,
                    requires = #reqs > 0 and table.concat(reqs, " | ") or nil,
                    desc = table.concat(body, " "),
                }
            end
        end
        table.sort(list, function(a, b)
            if a.tier ~= b.tier then return a.tier < b.tier end
            return a.column < b.column
        end)
        tabs[#tabs + 1] = { name = tabName or ("Tree " .. tab), spent = spent or 0, talents = list }
    end
    return tabs
end

local function snapshot()
    cdb.abilities = collectAbilities()
    cdb.talents = collectTalents()
    cdb.updated = date("%Y-%m-%d %H:%M")
end

-------------------------------------------------------------------------------
-- Rune capture (tooltip hook)
-------------------------------------------------------------------------------

local pendingTip
local captureDriver = CreateFrame("Frame")
captureDriver:Hide()
captureDriver:SetScript("OnUpdate", function(self)
    -- Read one frame late: custom UIs often AddLine() after the first Show().
    self:Hide()
    local tip = pendingTip
    pendingTip = nil
    if not (capturing and tip and tip:IsShown()) then return end
    local lines = readTip(tip)
    local name = lines[1] and lineText(lines[1]) or ""
    if name == "" then return end
    local body = {}
    for i = 2, #lines do body[#body + 1] = lineText(lines[i]) end
    local isNew = cdb.runes[name] == nil
    cdb.runes[name] = { name = name, lines = body, captured = date("%Y-%m-%d %H:%M") }
    if isNew then
        say("captured |cffffd24a" .. name .. "|r")
        if GrimoireFrame and GrimoireFrame:IsShown() and currentTab == "runes" then
            Grimoire_Render()
        end
    end
end)

local function queueCapture(tip)
    if capturing and tip ~= GrimoireScanTip then
        pendingTip = tip
        captureDriver:Show()
    end
end

for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tip then
        tip:HookScript("OnShow", queueCapture)
        hooksecurefunc(tip, "Show", queueCapture)
    end
end

-------------------------------------------------------------------------------
-- Discovery
-------------------------------------------------------------------------------

local function matchesDiscover(key)
    local k = key:lower()
    for _, p in ipairs(DISCOVER_PATTERNS) do
        if k:find(p, 1, true) then return true end
    end
    return false
end

local function objType(v)
    if type(v) ~= "table" then return type(v) end
    if type(v.GetObjectType) == "function" then
        local ok, t = pcall(v.GetObjectType, v)
        if ok and t then return t end
    end
    return "table"
end

local function discoverScan()
    local found = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and (type(v) == "function" or type(v) == "table") then
            local isC = k:match("^C_") ~= nil
            if isC or matchesDiscover(k) then
                local t = objType(v)
                local entry = k .. "  (" .. t .. ")"
                if t == "table" then
                    local keys = {}
                    for kk, vv in pairs(v) do
                        if type(kk) == "string" and type(vv) == "function" then keys[#keys + 1] = kk end
                    end
                    table.sort(keys)
                    if #keys > 0 then entry = entry .. ": " .. table.concat(keys, ", ") end
                end
                found[#found + 1] = entry
            end
        end
    end
    table.sort(found)
    db.discover = found
    say(#found .. " matching globals stored (Discovery tab).")
end

local function frameLabel(f)
    local n = f.GetName and f:GetName()
    return n or ("<anonymous " .. objType(f) .. ">")
end

local function inspectMouse()
    local f = GetMouseFocus()
    if not f or f == WorldFrame then
        say("Nothing under the cursor. Hover the rune window, type /grim mouse, press Enter.")
        return
    end
    local out = { "Under cursor: " .. frameLabel(f) }
    local p, chain = f.GetParent and f:GetParent(), {}
    while p and p ~= UIParent do
        chain[#chain + 1] = frameLabel(p)
        p = p:GetParent()
    end
    if #chain > 0 then out[#out + 1] = "Parents: " .. table.concat(chain, " < ") end
    local function walk(frame, depth)
        if depth > 4 then return end
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then
                local t = clean(r:GetText())
                if t ~= "" then out[#out + 1] = string.rep("  ", depth) .. t end
            end
        end
        for _, c in ipairs({ frame:GetChildren() }) do walk(c, depth + 1) end
    end
    -- Walk the top-most named ancestor so the whole window's text is included.
    local root = f
    while root:GetParent() and root:GetParent() ~= UIParent do root = root:GetParent() end
    out[#out + 1] = "Text inside " .. frameLabel(root) .. ":"
    walk(root, 1)
    db.mouse = out
    say("Frame info stored (Discovery tab).")
    Grimoire_Show("discovery")
end

-------------------------------------------------------------------------------
-- Text rendering
-------------------------------------------------------------------------------

local function renderAbilities()
    local out = {}
    for _, tab in ipairs(cdb.abilities or {}) do
        out[#out + 1] = "== " .. tab.name .. " (" .. #tab.spells .. ") =="
        for _, s in ipairs(tab.spells) do
            local head = s.name
            if s.rank then head = head .. " [" .. s.rank .. "]" end
            if s.passive and not (s.rank or ""):find("Passive") then head = head .. " [Passive]" end
            out[#out + 1] = head
            if s.details then out[#out + 1] = "    " .. s.details end
            if s.desc ~= "" then out[#out + 1] = "    " .. s.desc end
        end
        out[#out + 1] = ""
    end
    if #out == 0 then out[1] = "No spellbook data. Press Refresh." end
    return out
end

local function renderTalents()
    local out, showAll = {}, db.showAllTalents
    for _, tab in ipairs(cdb.talents or {}) do
        out[#out + 1] = "== " .. tab.name .. " (" .. tab.spent .. " points) =="
        local shown = 0
        for _, t in ipairs(tab.talents) do
            if showAll or t.rank > 0 then
                shown = shown + 1
                out[#out + 1] = t.name .. " [" .. t.rank .. "/" .. t.maxRank .. "]"
                if t.requires then out[#out + 1] = "    " .. t.requires end
                if t.desc ~= "" then out[#out + 1] = "    " .. t.desc end
            end
        end
        if shown == 0 then out[#out + 1] = "    (no points in this tree)" end
        out[#out + 1] = ""
    end
    if #out == 0 then
        out[1] = "The client reported no talent trees."
        out[2] = "Grimfall may use a custom talent system: try /grim scan and check the Discovery tab."
    end
    return out
end

local function renderRunes()
    local out, names = {}, {}
    for name in pairs(cdb.runes) do names[#names + 1] = name end
    table.sort(names)
    out[1] = "Capture is " .. (capturing and "ON" or "OFF") .. ". " .. #names .. " rune(s) captured."
    out[2] = "To capture: press Capture, open the rune window and hover every rune."
    out[3] = ""
    for _, name in ipairs(names) do
        local r = cdb.runes[name]
        out[#out + 1] = r.name
        for _, l in ipairs(r.lines) do out[#out + 1] = "    " .. l end
    end
    return out
end

local function renderDiscovery()
    local out = { "/grim mouse  (hover a window, type it, press Enter)" }
    for _, l in ipairs(db.mouse or { "  nothing yet" }) do out[#out + 1] = l end
    out[#out + 1] = ""
    out[#out + 1] = "/grim scan  (globals named rune/talent/advancement/mystic/essence, plus C_*)"
    for _, l in ipairs(db.discover or { "  nothing yet" }) do out[#out + 1] = l end
    return out
end

local RENDER = {
    abilities = renderAbilities, talents = renderTalents,
    runes = renderRunes, discovery = renderDiscovery,
}

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------

local frame, edit, shownText, tabButtons, captureBtn, allBtn, stamp

local function setShown(obj, show)
    if show then obj:Show() else obj:Hide() end
end

local function makeButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width)
    b:SetHeight(22)
    b:SetText(text)
    return b
end

local function buildFrame()
    frame = CreateFrame("Frame", "GrimoireFrame", UIParent)
    frame:SetWidth(640)
    frame:SetHeight(520)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, "GrimoireFrame")

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Grimoire  |cff888888v" .. VERSION .. "|r")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    tabButtons = {}
    local prev
    for _, def in ipairs({ { "abilities", "Abilities" }, { "talents", "Talents" },
                            { "runes", "Runes" }, { "discovery", "Discovery" } }) do
        local b = makeButton(frame, def[2], 100)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 20, -44) end
        b:SetScript("OnClick", function() Grimoire_Show(def[1]) end)
        tabButtons[def[1]] = b
        prev = b
    end

    local refresh = makeButton(frame, "Refresh", 80)
    refresh:SetPoint("TOPRIGHT", -24, -44)
    refresh:SetScript("OnClick", function()
        snapshot()
        Grimoire_Render()
        say("refreshed.")
    end)

    captureBtn = makeButton(frame, "Capture", 110)
    captureBtn:SetPoint("BOTTOMLEFT", 20, 16)
    captureBtn:SetScript("OnClick", function() Grimoire_Capture() end)

    allBtn = makeButton(frame, "Show all talents", 130)
    allBtn:SetPoint("BOTTOMLEFT", 20, 16)
    allBtn:SetScript("OnClick", function()
        db.showAllTalents = not db.showAllTalents
        Grimoire_Render()
    end)

    stamp = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    stamp:SetPoint("BOTTOMRIGHT", -24, 22)
    stamp:SetText("Click text, Ctrl+A, Ctrl+C to copy")

    local scroll = CreateFrame("ScrollFrame", "GrimoireScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 22, -76)
    scroll:SetPoint("BOTTOMRIGHT", -40, 44)

    edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(570)
    edit:SetHeight(400)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Read-only: any typing is undone.
    edit:SetScript("OnTextChanged", function(self, user)
        if user and shownText then self:SetText(shownText) end
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, scroll) end
    end)
    edit:SetScript("OnCursorChanged", function(self, x, y, w, h)
        if ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged(self, x, y, w, h) end
    end)
    edit:SetScript("OnUpdate", function(self, elapsed)
        if ScrollingEdit_OnUpdate then ScrollingEdit_OnUpdate(self, elapsed, scroll) end
    end)
    scroll:SetScrollChild(edit)
end

function Grimoire_Render()
    if not frame then return end
    for key, b in pairs(tabButtons) do
        if key == currentTab then b:LockHighlight() else b:UnlockHighlight() end
    end
    setShown(captureBtn, currentTab == "runes")
    captureBtn:SetText(capturing and "Stop capture" or "Capture")
    setShown(allBtn, currentTab == "talents")
    allBtn:SetText(db.showAllTalents and "Learned only" or "Show all talents")
    local lines = RENDER[currentTab]()
    if cdb.updated and (currentTab == "abilities" or currentTab == "talents") then
        table.insert(lines, 1, UnitName("player") .. " - " .. (UnitClass("player") or "")
            .. " level " .. UnitLevel("player") .. " - scanned " .. cdb.updated)
        table.insert(lines, 2, "")
    end
    shownText = table.concat(lines, "\n")
    edit:SetText(shownText)
    edit:SetCursorPosition(0)
    GrimoireScrollScrollBar:SetValue(0)
end

function Grimoire_Show(tab)
    if not frame then buildFrame() end
    currentTab = tab or currentTab
    if (currentTab == "abilities" or currentTab == "talents") and not frame:IsShown() then
        snapshot()
    end
    frame:Show()
    Grimoire_Render()
end

function Grimoire_Capture(state)
    if state == nil then capturing = not capturing else capturing = state end
    if capturing then
        say("rune capture ON. Open the rune window and hover every rune. /grim capture to stop.")
    else
        say("rune capture OFF.")
    end
    if frame and frame:IsShown() then Grimoire_Render() end
end

-------------------------------------------------------------------------------
-- Events & slash
-------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
local loginDelay
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        db, cdb = GrimoireDB, GrimoireCharDB
        cdb.runes = cdb.runes or {}
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Snapshot once shortly after login so SavedVariables has data even
        -- if the window is never opened.
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        loginDelay = 5
        self:SetScript("OnUpdate", function(f, elapsed)
            loginDelay = loginDelay - elapsed
            if loginDelay <= 0 then
                f:SetScript("OnUpdate", nil)
                snapshot()
            end
        end)
    end
end)

SLASH_GRIMOIRE1 = "/grim"
SLASH_GRIMOIRE2 = "/grimoire"
SlashCmdList.GRIMOIRE = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        if frame and frame:IsShown() then frame:Hide() else Grimoire_Show() end
    elseif RENDER[msg] then
        Grimoire_Show(msg)
    elseif msg == "capture" then
        Grimoire_Capture()
    elseif msg == "runes clear" then
        wipe(cdb.runes)
        say("captured runes cleared.")
        if frame and frame:IsShown() then Grimoire_Render() end
    elseif msg == "scan" then
        discoverScan()
        Grimoire_Show("discovery")
    elseif msg == "mouse" then
        inspectMouse()
    else
        say("/grim - open/close the window")
        say("/grim abilities | talents | runes | discovery - open a tab")
        say("/grim capture - toggle rune capture (hover runes while ON)")
        say("/grim runes clear - forget captured runes")
        say("/grim scan - look for rune/talent APIs (Discovery tab)")
        say("/grim mouse - describe the window under the cursor")
    end
end
