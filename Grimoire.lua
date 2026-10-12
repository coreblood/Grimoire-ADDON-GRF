--[[----------------------------------------------------------------------------
  Grimoire v1.3.0 (WotLK 3.3.5a client, Grimfall server / Ascension core)

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

  Copy: click the text, Ctrl+A, Ctrl+C. The text is editable (trim it
  before copying); switching tabs or Refresh redraws it. The same data is in
  WTF\Account\<acct>\<realm>\<char>\SavedVariables\Grimoire.lua after logout.
------------------------------------------------------------------------------]]

local ADDON_NAME = "Grimoire"
local VERSION    = "1.3.0"
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

-- Talent tree backgrounds are named <Class><Tree> (e.g. "DeathKnightFrost"),
-- which tells apart Grimfall's same-named trees (Holy, Protection, Frost...).
local CLASS_PREFIXES = {
    { "DeathKnight", "Death Knight" }, { "Druid", "Druid" }, { "Hunter", "Hunter" },
    { "Mage", "Mage" }, { "Paladin", "Paladin" }, { "Priest", "Priest" },
    { "Rogue", "Rogue" }, { "Shaman", "Shaman" }, { "Warlock", "Warlock" },
    { "Warrior", "Warrior" },
}

local function classFromBackground(bg)
    if type(bg) ~= "string" then return nil end
    bg = bg:match("([^\\/]+)$") or bg
    for _, c in ipairs(CLASS_PREFIXES) do
        if bg:sub(1, #c[1]):lower() == c[1]:lower() then return c[2] end
    end
end

local function collectTalents()
    local tabs = {}
    for tab = 1, (GetNumTalentTabs() or 0) do
        local tabName, _, spent, background = GetTalentTabInfo(tab)
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
        tabs[#tabs + 1] = { name = tabName or ("Tree " .. tab), spent = spent or 0,
                            class = classFromBackground(background), talents = list }
    end
    table.sort(tabs, function(a, b)
        if (a.class or "") ~= (b.class or "") then return (a.class or "") < (b.class or "") end
        return a.name < b.name
    end)
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

-- Quality labels shown under each entry of the Classless "Active Runes"
-- list. The rune collection grid shows names only, so finding one of these
-- next to the hovered entry is how an ACTIVE rune is told apart.
local QUALITY_ORDER = { "Artifact", "Legendary", "Epic", "Rare", "Uncommon", "Common" }
local QUALITY_RANK = {}
for i, q in ipairs(QUALITY_ORDER) do QUALITY_RANK[q] = i end

local function findQualityLabel(f, depth)
    if not f or depth > 2 then return nil end
    if f.GetRegions then
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then
                local t = clean(r:GetText())
                if QUALITY_RANK[t] then return t end
            end
        end
    end
    if f.GetChildren then
        for _, c in ipairs({ f:GetChildren() }) do
            local q = findQualityLabel(c, depth + 1)
            if q then return q end
        end
    end
end

-- The hovered list entry is the tooltip owner, or (for icon sub-buttons) its parent.
local function activeRuneQuality(tip)
    local owner = tip.GetOwner and tip:GetOwner()
    if not owner then return nil end
    return findQualityLabel(owner, 0)
        or (owner.GetParent and findQualityLabel(owner:GetParent(), 1))
end

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
    local body, rank, maxRank = {}, nil, nil
    for i = 2, #lines do
        local t = lineText(lines[i])
        local r, m = t:match("^Rank (%d+)/(%d+)")
        if r then
            rank, maxRank = tonumber(r), tonumber(m)
        elseif t:match("^Next [Rr]ank") then
            break
        else
            body[#body + 1] = t
        end
    end
    -- Talent tooltips carry "Rank x/y"; rune (Mystic Enchant) names start "Rune of".
    local store, kind, quality
    if rank then
        store, kind = cdb.capturedTalents, "talent"
    elseif name:match("^Rune of") then
        -- Only runes in the Active Runes list (they carry a quality label);
        -- the collection grid on the left is ignored.
        quality = activeRuneQuality(tip)
        if not quality then return end
        store, kind = cdb.runes, "rune"
    else
        return
    end
    local isNew = store[name] == nil
    store[name] = { name = name, lines = body, rank = rank, maxRank = maxRank,
                    quality = quality, captured = date("%Y-%m-%d %H:%M") }
    if isNew then
        say("captured " .. kind .. " |cffffd24a" .. name .. "|r")
    end
    if GrimoireFrame and GrimoireFrame:IsShown() then Grimoire_Render() end
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

-- Grimfall's client extension (clientextensions.dll) registers these. Only
-- READ functions are listed: nothing here learns, rerolls, banishes, claims,
-- commits or requests anything.
local PROBE_FUNCS = {
    "IsClasslessEnabled", "IsCoAEnabled", "GetClasslessRole", "GetClasslessClassCreateIndex",
    "GetKnownClasslessSpellIds", "GetClasslessSpellEntrySpellIds", "GetClasslessSpellEntryRows",
    "GetClasslessSpecializationSkillLineIds", "GetClasslessSkillLineSpellIds",
    "GetClasslessSkillLineSpellEntryRows", "GetClasslessTalentTreeData",
    "GetClasslessTalentCurrentRankIndex", "GetClasslessTalentTabIdForSkillLine",
    "IsClasslessTalentConsideredAbility", "ClasslessIsSpellKnown", "ClasslessCanEverLearnSpell",
    "Ex_GetCoAClassInfo", "Ex_GetCoATalentCatalog", "Ex_GetCoATalentRevision", "Ex_GetCoATalentState",
    "MysticEnchant_GetAllMEInfo", "MysticEnchant_GetAllMESpellIds", "MysticEnchant_GetAllREInfo",
    "MysticEnchant_GetAllRESpellIds", "MysticEnchant_GetKnownMEInfo", "MysticEnchant_GetKnownREInfo",
    "MysticEnchant_GetKnownRESpellIds", "MysticEnchant_GetKnownRECountByQuality",
    "MysticEnchant_GetSpellQuality", "MysticEnchant_GetCurrentOffer",
    "SkillCard_GetCards", "SkillCard_GetNumActiveCards", "SkillCard_GetMaxActiveCards",
    "SkillCard_GetActiveCardBySlot", "GetActiveSpecializationIndex",
}

local probeBudget
-- Copy a value into something SavedVariables can store, with size limits.
local function storable(v, depth)
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" or t == "nil" then return v end
    if t ~= "table" then return "<" .. t .. ">" end
    if depth > 4 then return "<table: too deep>" end
    local out, n = {}, 0
    for k, vv in pairs(v) do
        n = n + 1
        probeBudget = probeBudget - 1
        if n > 400 or probeBudget <= 0 then out["..."] = "truncated"; break end
        out[type(k) == "number" and k or tostring(k)] = storable(vv, depth + 1)
    end
    return out
end

local function probeCall(fn, ...)
    local res = { pcall(fn, ...) }
    local entry = { ok = res[1], n = #res - 1 }
    if res[1] then
        entry.returns = {}
        for i = 2, #res do entry.returns[i - 1] = storable(res[i], 1) end
    else
        entry.err = tostring(res[2])
    end
    return entry
end

-- First number found in a probe result (to feed functions that need an id).
local function firstNumber(entry)
    if not (entry and entry.ok and entry.returns) then return nil end
    for _, r in ipairs(entry.returns) do
        if type(r) == "number" then return r end
        if type(r) == "table" then
            for _, x in pairs(r) do
                if type(x) == "number" then return x end
                if type(x) == "table" then
                    for _, y in pairs(x) do if type(y) == "number" then return y end end
                end
            end
        end
    end
end

local function probeApi()
    probeBudget = 20000
    local out, missing = {}, {}
    for _, name in ipairs(PROBE_FUNCS) do
        local fn = _G[name]
        if type(fn) == "function" then
            out[name] = { noArgs = probeCall(fn) }
        else
            missing[#missing + 1] = name
        end
    end
    -- Second pass with sample ids, for functions that want an argument.
    local spellId = firstNumber(out.GetKnownClasslessSpellIds and out.GetKnownClasslessSpellIds.noArgs)
    local skillLine = firstNumber(out.GetClasslessSpecializationSkillLineIds
        and out.GetClasslessSpecializationSkillLineIds.noArgs)
    local reId = firstNumber(out.MysticEnchant_GetKnownRESpellIds and out.MysticEnchant_GetKnownRESpellIds.noArgs)
    local function try(name, label, ...)
        if out[name] and select("#", ...) > 0 and (...) ~= nil then
            out[name][label] = probeCall(_G[name], ...)
        end
    end
    try("GetClasslessSkillLineSpellIds", "skillLine", skillLine)
    try("GetClasslessSkillLineSpellEntryRows", "skillLine", skillLine)
    try("GetClasslessTalentTabIdForSkillLine", "skillLine", skillLine)
    try("GetClasslessTalentTreeData", "skillLine", skillLine)
    try("GetClasslessTalentTreeData", "one", 1)
    try("GetClasslessTalentCurrentRankIndex", "spell", spellId)
    try("IsClasslessTalentConsideredAbility", "spell", spellId)
    try("ClasslessIsSpellKnown", "spell", spellId)
    try("GetClasslessSpellEntryRows", "spell", spellId)
    try("MysticEnchant_GetSpellQuality", "re", reId)
    try("SkillCard_GetActiveCardBySlot", "one", 1)
    for i = 1, (GetNumTalentTabs() or 0) do
        out["GetTalentTabInfo#" .. i] = { noArgs = probeCall(GetTalentTabInfo, i) }
        out["GetNumTalents#" .. i] = { noArgs = probeCall(GetNumTalents, i) }
    end
    out._numTalentTabs = GetNumTalentTabs()
    out._missing = missing
    out._when = date("%Y-%m-%d %H:%M")
    db.probe = out
    say("API probe saved. Type /reload so it is written to disk.")
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
    local total = 0
    for _, tab in ipairs(cdb.talents or {}) do
        local learned = {}
        for _, t in ipairs(tab.talents) do
            if showAll or t.rank > 0 then learned[#learned + 1] = t end
            total = total + t.rank
        end
        -- Only trees you have points in (all trees with "Show unlearned talents").
        if #learned > 0 then
            local title = tab.class and (tab.class .. " - " .. tab.name) or tab.name
            out[#out + 1] = "== " .. title .. " (" .. tab.spent .. " points) =="
            for _, t in ipairs(learned) do
                out[#out + 1] = t.name .. " [" .. t.rank .. "/" .. t.maxRank .. "]"
                if t.requires and showAll then out[#out + 1] = "    " .. t.requires end
                if t.desc ~= "" then out[#out + 1] = "    " .. t.desc end
            end
            out[#out + 1] = ""
        end
    end
    if #out > 0 then
        table.insert(out, 1, "Total talent points spent: " .. total)
        table.insert(out, 2, "")
    end
    local names = {}
    for name, t in pairs(cdb.capturedTalents) do
        if showAll or (t.rank or 0) > 0 then names[#names + 1] = name end
    end
    table.sort(names)
    -- Only needed if the talent API ever misses something: shown when non-empty.
    if #names > 0 then
        out[#out + 1] = "== Captured from the Classless window (" .. #names .. ") =="
    end
    for _, name in ipairs(names) do
        local t = cdb.capturedTalents[name]
        out[#out + 1] = t.name .. " [" .. (t.rank or 0) .. "/" .. (t.maxRank or "?") .. "]"
        for _, l in ipairs(t.lines) do out[#out + 1] = "    " .. l end
    end
    return out
end

-- Indent every line of a tooltip text, including its embedded line breaks.
local function addIndented(out, text)
    for piece in (text .. "\n"):gmatch("(.-)\n") do
        out[#out + 1] = (piece == "") and "" or ("    " .. piece)
    end
end

local function renderRunes()
    local out, names = {}, {}
    for name in pairs(cdb.runes) do names[#names + 1] = name end
    -- Grouped like the Active Runes column: Legendary first, then Epic, ...
    table.sort(names, function(a, b)
        local qa = QUALITY_RANK[cdb.runes[a].quality] or 99
        local qb = QUALITY_RANK[cdb.runes[b].quality] or 99
        if qa ~= qb then return qa < qb end
        return a < b
    end)
    out[1] = "Capture is " .. (capturing and "ON" or "OFF") .. ". " .. #names .. " active rune(s) captured."
    out[2] = "To capture: press Capture, open the Runes page and hover each rune in the Active Runes list."
    out[3] = "Swapped runes? /grim runes clear, then capture again."
    local group
    for _, name in ipairs(names) do
        local r = cdb.runes[name]
        if r.quality ~= group then
            group = r.quality
            if out[#out] ~= "" then out[#out + 1] = "" end
            out[#out + 1] = "== " .. (group or "Unknown quality") .. " =="
        end
        out[#out + 1] = r.name
        for _, l in ipairs(r.lines) do
            if l ~= r.quality then addIndented(out, l) end  -- quality is the group header
        end
        out[#out + 1] = ""
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
    stamp:SetText("Edit freely - Ctrl+A, Ctrl+C to copy - Refresh restores")

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
    -- Editable so you can trim the report before copying; switching tabs or
    -- Refresh redraws it from the scanned data.
    edit:SetScript("OnTextChanged", function(self)
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, scroll) end
    end)
    edit:SetScript("OnCursorChanged", function(self, x, y, w, h)
        if ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged(self, x, y, w, h) end
    end)
    edit:SetScript("OnUpdate", function(self, elapsed)
        if ScrollingEdit_OnUpdate then ScrollingEdit_OnUpdate(self, elapsed, scroll) end
    end)
    scroll:SetScrollChild(edit)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
end

function Grimoire_Render()
    if not frame then return end
    for key, b in pairs(tabButtons) do
        if key == currentTab then b:LockHighlight() else b:UnlockHighlight() end
    end
    setShown(captureBtn, currentTab == "runes" or currentTab == "talents")
    captureBtn:ClearAllPoints()
    captureBtn:SetPoint("BOTTOMLEFT", currentTab == "talents" and 156 or 20, 16)
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
        say("capture ON. Hover talents and runes in the Classless window. /grim capture to stop.")
    else
        say("capture OFF.")
    end
    -- Minimap tint and the options checkbox are created later in the file,
    -- so reach them through their global frame names.
    if GrimoireMinimapButton then
        if capturing then GrimoireMinimapButton.icon:SetVertexColor(1, 0.45, 0.45)
        else GrimoireMinimapButton.icon:SetVertexColor(1, 1, 1) end
    end
    if GrimoireOptCapture then GrimoireOptCapture:SetChecked(capturing) end
    if frame and frame:IsShown() then Grimoire_Render() end
end

-------------------------------------------------------------------------------
-- Minimap button (same texture layout and free-form drag as ScrollReader)
-------------------------------------------------------------------------------

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local minimapButton, optionsPanel

local function createMinimapButton()
    local mm = CreateFrame("Button", "GrimoireMinimapButton", Minimap)
    mm:SetWidth(31)
    mm:SetHeight(31)
    mm:SetFrameStrata("MEDIUM")
    mm:SetFrameLevel(8)
    mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mm:RegisterForDrag("LeftButton")
    mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = mm:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local background = mm:CreateTexture(nil, "BACKGROUND")
    background:SetWidth(20)
    background:SetHeight(20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = mm:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(17)
    icon:SetHeight(17)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)
    mm.icon = icon

    local function reposition()
        mm:ClearAllPoints()
        mm:SetPoint("CENTER", Minimap, "CENTER", db.minimap.x, db.minimap.y)
    end
    mm.Reposition = reposition

    local function onDragUpdate()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        db.minimap.x = px / scale - mx
        db.minimap.y = py / scale - my
        reposition()
    end
    mm:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mm:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            Grimoire_Capture()
        elseif frame and frame:IsShown() then
            frame:Hide()
        else
            Grimoire_Show()
        end
    end)
    mm:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Grimoire")
        GameTooltip:AddLine("Left-click: open / close", 1, 1, 1)
        GameTooltip:AddLine("Right-click: capture " .. (capturing and "|cffff7070ON|r" or "OFF"), 1, 1, 1)
        GameTooltip:AddLine("Drag: move", 1, 1, 1)
        GameTooltip:Show()
    end)
    mm:SetScript("OnLeave", function() GameTooltip:Hide() end)

    reposition()
    if db.minimap.hide then mm:Hide() end
    minimapButton = mm
end

local function setMinimapShown(show)
    db.minimap.hide = not show
    if minimapButton then
        if show then minimapButton.Reposition(); minimapButton:Show() else minimapButton:Hide() end
    end
end

-------------------------------------------------------------------------------
-- Interface Options panel (Esc > Interface > AddOns > Grimoire)
-------------------------------------------------------------------------------

local function createOptionsPanel()
    local p = CreateFrame("Frame", "GrimoireOptionsPanel", UIParent)
    p.name = "Grimoire"
    p:Hide()

    local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Grimoire  |cff888888v" .. VERSION .. "|r")
    local sub = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetText("Lists your abilities, talents and runes with what they do.")

    local checks = {}
    local function addCheck(key, label, tip, getter, setter, anchor)
        local cb = CreateFrame("CheckButton", "GrimoireOpt" .. key, p, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
        _G[cb:GetName() .. "Text"]:SetText(label)
        cb.tooltipText = tip
        cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
        cb.refresh = function() cb:SetChecked(getter()) end
        checks[#checks + 1] = cb
        return cb
    end

    local c1 = addCheck("Minimap", "Show minimap button", "Left-click opens Grimoire, right-click toggles capture.",
        function() return not db.minimap.hide end, setMinimapShown, sub)
    local c2 = addCheck("AllTalents", "Show unlearned talents", "List talents with 0 points too.",
        function() return db.showAllTalents end,
        function(v) db.showAllTalents = v; if frame and frame:IsShown() then Grimoire_Render() end end, c1)
    local c3 = addCheck("Capture", "Capture talents and runes from tooltips (this session)",
        "While on, hovering a talent or an Active Rune in the Classless window records it.",
        function() return capturing end, function(v) Grimoire_Capture(v) end, c2)

    local function addButton(text, width, anchor, x, y, onClick)
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetWidth(width)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, y)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end
    local open = addButton("Open Grimoire", 150, c3, 0, -18, function() Grimoire_Show() end)
    local probe = addButton("Run API probe", 150, open, 0, -8, function() SlashCmdList.GRIMOIRE("probe") end)
    local clrT = addButton("Clear captured talents", 170, open, 160, 22, function() SlashCmdList.GRIMOIRE("talents clear") end)
    addButton("Clear captured runes", 170, clrT, 0, -8, function() SlashCmdList.GRIMOIRE("runes clear") end)

    local hint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", probe, "BOTTOMLEFT", 0, -14)
    hint:SetText("Slash commands: /grim  (type /grim help for the list)")

    p:SetScript("OnShow", function() for _, cb in ipairs(checks) do cb.refresh() end end)
    InterfaceOptions_AddCategory(p)
    optionsPanel = p
end

local function openOptions()
    -- 3.3.5 needs two calls the first time the panel is opened.
    InterfaceOptionsFrame_OpenToCategory(optionsPanel)
    InterfaceOptionsFrame_OpenToCategory(optionsPanel)
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
        cdb.capturedTalents = cdb.capturedTalents or {}
        -- Runes captured before v1.3.0 have no quality and may come from the
        -- collection grid rather than the Active Runes list: drop them.
        for name, r in pairs(cdb.runes) do
            if not r.quality then cdb.runes[name] = nil end
        end
        db.minimap = db.minimap or { hide = false, x = -40, y = -72 }
        createMinimapButton()
        createOptionsPanel()
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
    elseif msg == "minimap" then
        setMinimapShown(db.minimap.hide)
        say("minimap button " .. (db.minimap.hide and "hidden" or "shown") .. ".")
    elseif msg == "options" or msg == "config" then
        openOptions()
    elseif msg == "probe" then
        probeApi()
    elseif msg == "talents clear" then
        wipe(cdb.capturedTalents)
        say("captured talents cleared.")
        if frame and frame:IsShown() then Grimoire_Render() end
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
        say("/grim capture - toggle capture (hover talents and runes while ON)")
        say("/grim minimap - show/hide the minimap button")
        say("/grim options - open the Interface options page")
        say("/grim runes clear | talents clear - forget captured runes/talents")
        say("/grim probe - test Grimfall's classless/rune functions, then /reload")
        say("/grim scan - look for rune/talent APIs (Discovery tab)")
        say("/grim mouse - describe the window under the cursor")
    end
end
