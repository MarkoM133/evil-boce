--[[
  GAME HELPERS (Global)

  Hero      = karta (bez taga Slot) koja se zove isto kao bakugan (core s tagom Core ili figurina)
  Karta     : HP -/+ i statovi DMG PWR RNG KB WT (klik +1, desni klik -1 na OSNOVNU vrijednost)
              ispod karte 3 utora za tokene; bonus tokena se dodaje statovima
  Tokeni    : efekt = prva linija opisa tokena, npr "DMG +1, RNG -1" (HP DMG PWR RNG KB WT)
              kopija bez opisa uzima efekt od tokena s istom slikom (izvorni "Vrsta A".."Vrsta J")
              bakugan takne token -> token ide u prvi slobodan utor svog heroja (pun -> inventar)
              desni klik -> U inventar / Na <heroj>; spusti token na utor = stavi ga tamo
  Bakugan   : iznad otvorene figurine HP i statovi; na hover tooltip sa statovima
              range krug kad mis stoji na bakuganu ili hero karti
  Battle    : zaustavljen bakugan s protivnikom u dometu (veci RNG od ta dva) se otvori,
              izvan dometa se zatvori (osim ako stoji na stage karti)
  Stage     : stage karta licem dolje s bakuganima obje strane -> okrene se licem gore
  Bacanje   : mis na core + Numpad 1 = ciljaj, Numpad 1 opet = baci, Numpad 2 = odustani
  Tezina    : WT -> masa (teze ga je odgurnuti) i sporije bacanje
  Nova igra : gumb gore na ekranu (2x klik)
  Ring-out  : bakugan u igri padne sa stola / izade s mape / stane u bacackoj zoni -> natrag u zonu

  Sve sto se moze stimati je u CONFIG ispod.
]]

---------------------------------------------------------------- CONFIG

local CFG = {
  BTN_SCALE        = 0.5,
  OVERHEAD_FONT    = 70,
  OVERHEAD_MARGIN  = 40,      -- UI jedinice iznad figurine (100 = 1 lokalna jedinica)

  SLOTS            = 3,       -- utora za tokene po heroju
  SLOT_SIZE        = 0.95,    -- velicina utora (kvadrat), jedinice stola; token se smanji da stane
  SLOT_GAP         = 0.3,     -- razmak od GORNJEG ruba karte do reda utora za tokene
  PZ_GAP           = 0.95,    -- power-up zona: pocinje ovoliko ispod donjeg ruba karte (ispod HP/statova)
  PZ_DEPTH         = 3.3,     -- power-up zona: dubina (karta je ~3.1)
  AZ_HALF_X        = 3.6,     -- Action zona: pola sirine oko Action Cards placeholdera
  AZ_HALF_Z        = 2.2,     -- Action zona: pola dubine
  PZ_WIDTH         = 5,       -- power-up zona: najveca sirina (suzi se da ne prelazi u susjednu hero kartu)
  SLOT_SIDE        = 0,       -- pomak cijelog reda lijevo/desno
  GEAR_RADIUS      = 3.5,     -- equipment karta do ovoliko od hero karte pripada tom heroju
  TOKEN_FACE_Z     = 0,       -- rotacija tokena u utoru: 0 = strana s brojevima gore (180 = obrnuto)

  MAP_NAME         = "Custom Mat",
  MAP_HALF_X       = nil,     -- nil = iz velicine mata; inace rucno (npr 22.9)
  MAP_HALF_Z       = 20.76,   -- arena do crvenih crta mata (10 % od ruba: 0.4 x 51.9); izmedu crvene crte i ruba su bacacke zone
  ZONE_DEPTH       = 5.2,     -- bacacka zona: od crvene crte do ruba mata (25.95 - 20.76); skrati se da ne ulazi u hand zone
  HIDE_ZONES       = false,   -- true = skrivene zone (protivnik ne vidi bakugan u tvojoj zoni)

  AIM_KEY          = 1,       -- Numpad 1
  CANCEL_KEY       = 2,       -- Numpad 2
  SLING_KEY        = 3,       -- Numpad 3 = prekidac praćka / ruka
  SLING_SCALE      = 2,       -- praćka: snaga = povuceno * ovo
  SLING_MIN        = 0.25,    -- praćka: povuceno manje od ovoga = obicno spustanje (premjestanje)
  AIM_MAX_LEN      = 14,      -- najdulja strelica (= puna snaga)
  SPEED_MIN        = 0.4,     -- najslabiji udarac (gurkanje)
  POWER_CURVE      = 1.6,     -- >1 = finija kontrola slabih udaraca
  SPEED_MAX        = 38,
  WT_BASE          = 2,       -- tezina na kojoj je bacanje "normalno"
  MASS_PER_WT      = 0.5,     -- masa = WT * ovo (default core ima masu 1)

  RANGE_UNIT       = nil,     -- 1 RNG = jedno polje grida; nil = velicina grida (Grid.sizeX, kod vas 2)
  BATTLE_OPEN      = true,    -- otvaranje/zatvaranje po dometu
  STAGE_FLIP       = true,    -- okretanje stage karte

  CORE_DRAG        = 0.2,
  CORE_ANG_DRAG    = 0.6,
  SETTLE_SPEED     = 0.5,     -- sporije od ovoga ...
  SETTLE_TIME      = 1.5,     -- ... ovoliko sekundi -> zaustavi
  MAX_ROLL_TIME    = 20,      -- nakon ovoliko sekundi kretanja bez drzanja -> zaustavi

  LAUNCH_DETECT    = 6,       -- brzina iznad koje se smatra da je bakugan bacen (i pinchom)
  RINGOUT_HP       = 0,       -- koliko HP-a gubi na ring-out (0 = nista)

  ENERGY_MAX       = 8,       -- max energy = broj turna, najvise ovoliko

  WALL_FIELDS      = 2,       -- zid: duljina u poljima grida
  WALL_HEIGHT      = 1.2,     -- zid: visina kad stoji (bakugan je ~0.6)
  WALL_THICK       = 0.3,     -- zid: debljina

  SERVER           = "http://localhost:5100",   -- lokalni server (web app, cards.json); Sync karata ga zove
  LIBRARY_POS      = {32, 3, -42},              -- gdje se prvi put stvori deck "Biblioteka karata" (poslije ostaje gdje ga stavis)
}

local HP_DEFAULT = {hp = 8, max = 8, dmg = 3, pwr = 3, rng = 4, kb = 3, wt = 2}
local STATS = { {"dmg", "DMG"}, {"pwr", "PWR"}, {"rng", "RNG"}, {"kb", "KB"}, {"wt", "WT"} }
local EFFECT_KEYS = {
  HP = "hp", HEALTH = "hp", ZDRAVLJE = "hp",
  DMG = "dmg", DAMAGE = "dmg",
  PWR = "pwr", POWER = "pwr", SNAGA = "pwr",
  RNG = "rng", RANGE = "rng", DOMET = "rng",
  KB = "kb", DEF = "kb", SHIELD = "kb", STIT = "kb",
  WT = "wt", WEIGHT = "wt", TEZINA = "wt",
}
local SLOT_BTN0 = 8                -- index gumba za zbirni tekst tokena (0-2 HP, 3-7 statovi)

---------------------------------------------------------------- state

stats = {}                         -- [ime] = {hp, max, dmg, pwr, rng, kb, wt, tint, hpBonus, baseDesc}
layout = nil                       -- spremljene pozicije (gumb "Spremi pozicije")
local tokenHome = {}               -- [token guid] = {x,y,z,rx,ry,rz}
local slotOf = {}                  -- [token guid] = {hero = ime, i = utor}
local otherSave = {}               -- tudji kljucevi iz starog Global statea (Chimera)
local heroCards = {}               -- [ime] = karta
local bodies = {}                  -- [ime] = core/figurina na stolu
local bonus = {}                   -- [ime] = {dmg=.., ...} zbroj tokena u utorima
local effectByImage = {}           -- [image url] = efekt tekst
local tokenCooldown = {}
local tokenMenu = {}
local lastDesc = {}
cardSig = {}

local aiming = {}                  -- [player color] = {obj, dir, len}
local hoverName = {}               -- [player color] = ime heroja za range krug
local inPlay = {}                  -- [ime] = true kad je bakugan u igri (izvan zone)
local slowSince = {}
local moveSince = {}
local ringoutLock = {}
local stateLock = {}               -- [ime] = Time.time zadnje promjene statea (battle)
local newGameArmed = 0
local map = nil
local lastAimAny = false
local slingMode = {}               -- [player color] = true kad je praćka ukljucena
local openedByBattle = {}          -- [ime] = true ako je figurinu otvorio battle range

-- energy / turn / setup coreova
energy = { p = { spent = 0 }, n = { spent = 0 } }  -- p = strana z>0, n = z<0
turnNo = 0
setupPhase = false
coreOwner = {}                     -- [token guid] = boja igraca koji ga je postavio
coreRealName = {}                  -- [token guid] = ime dok je token face down (skriveno kao "Core")
heroBase = {}                      -- [ime] = osnovni statsi heroja iz karte (Sync karata)
handPick = {}                      -- [card guid] = boja: karta uzeta iz ruke (za placanje costa)
energySig = {}

---------------------------------------------------------------- save / load

function onSave()
  local t = {}
  for k, v in pairs(otherSave) do t[k] = v end
  t.heroStats = stats
  t.tokenHome = tokenHome
  t.tokenSlots = slotOf
  t.layout = layout
  t.energy = energy
  t.turnNo = turnNo
  t.setupPhase = setupPhase
  t.coreOwner = coreOwner
  t.coreRealName = coreRealName
  t.heroBase = heroBase
  return JSON.encode(t)
end

function onLoad(save)
  if save and save ~= "" then
    local ok, data = pcall(JSON.decode, save)
    if ok and type(data) == "table" then
      for k, v in pairs(data) do
        if k == "heroStats" then stats = v
        elseif k == "tokenHome" then tokenHome = v
        elseif k == "tokenSlots" then slotOf = v
        elseif k == "layout" then layout = v
        elseif k == "energy" then energy = v
        elseif k == "turnNo" then turnNo = v
        elseif k == "setupPhase" then setupPhase = v
        elseif k == "coreOwner" then coreOwner = v
        elseif k == "coreRealName" then coreRealName = v
        elseif k == "heroBase" then heroBase = v
        else otherSave[k] = v end
      end
    end
  end

  Wait.frames(function()
    scanHeroes()
    for _, o in ipairs(getObjects()) do setupToken(o) end
    -- starije verzije su zakljucavale tokene u utorima: otkljucaj ih da se mogu maknuti
    for g, _ in pairs(slotOf) do
      local t = getObjectFromGUID(g)
      if t ~= nil then t.setLock(false) end
    end
    Wait.time(scanHeroes, 1, -1)
    if layout == nil then
      Wait.time(function()
        local n, d = saveLayout()
        print("[Evil Boce] Pocetni raspored spremljen (" .. n .. " objekata, " .. d .. " deckova). Gumb Spremi pozicije ga mijenja.")
      end, 3)
    end
    for _, w in ipairs(getObjectsWithTag("Wall")) do fitWall(w) end
    Wait.time(updateOverheads, 0.5, -1)
    Wait.time(refreshEnergySafe, 0.5, -1)
    Wait.time(physicsTick, 0.25, -1)
    Wait.time(aimTick, 0.05, -1)
    redrawLines()
  end, 30)
end

function onObjectSpawn(o)
  Wait.frames(function()
    if o ~= nil then setupToken(o) end
  end, 5)
end

function noop() end

---------------------------------------------------------------- helpers

local function copy(t)
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end

local function key(name)
  return (name:gsub("[^%w]", "_"))
end

local function isToken(o)
  return o ~= nil and o.getVar("IS_TOKEN") == true
end

-- zid: token koji bakugani ne skupljaju (ne ide na heroja ni u inventar)
local function isWall(o)
  if o == nil then return false end
  if o.hasTag("Wall") then return true end
  local ok, g = pcall(function() return o.getGMNotes() end)
  return o.getName() == "Wall" or (ok and g == "Wall")
end

local function isBody(o)
  if o == nil or o.type == "Card" or o.type == "Deck" then return false end
  return o.hasTag("Core") or o.hasTag("Bakugan") or o.type == "Figurine"
end

local function tokenLabel(t)
  local n = t.getName()
  if n == "" then n = "token " .. t.getGUID() end
  return n
end

local function near(a, b, r)
  return (a.x - b.x) ^ 2 + (a.z - b.z) ^ 2 < r * r
end

local function dist(a, b)
  return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

local function speedOf(o)
  local v = o.getVelocity()
  return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

-- "miruje": TTS resting ILI skoro nula brzine (na mapi koja nije savrseno ravna resting zna ostati false)
local function isStill(o)
  return o.resting or speedOf(o) < 0.3
end

-- setState samo ako taj state postoji i nije trenutni (inace TTS baca "state id does not exist")
local function safeSetState(o, id)
  if o == nil then return nil end
  local okc, cur = pcall(function() return o.getStateId() end)
  if not okc or cur == id then return nil end
  local oks, states = pcall(function() return o.getStates() end)
  if not oks or states == nil then return nil end
  for _, st in ipairs(states) do
    if st.id == id then return o.setState(id) end
  end
  return nil
end

local function heroOf(o)
  if o == nil then return nil end
  local n = o.getName()
  if n ~= "" and heroCards[n] ~= nil and stats[n] ~= nil then return n end
  return nil
end

local function sideOfHero(name)
  local c = heroCards[name]
  if c == nil then return nil end
  return c.getPosition().z >= 0 and 1 or -1
end

-- 1 RNG u jedinicama stola = velicina jednog polja grida
function rangeUnit()
  if CFG.RANGE_UNIT then return CFG.RANGE_UNIT end
  local ok, v = pcall(function() return Grid.sizeX end)
  if ok and type(v) == "number" and v > 0 then return v end
  return 2
end

-- efektivna vrijednost stata = osnova + tokeni
local function eff(name, k)
  local st = stats[name]
  if st == nil then return 0 end
  if k == "max" then return st.max + (st.hpBonus or 0) end
  return (st[k] or 0) + ((bonus[name] or {})[k] or 0)
end

---------------------------------------------------------------- mapa i zone

function getMap()
  if map ~= nil then return map end
  local mat
  for _, o in ipairs(getObjects()) do
    if o.getName() == CFG.MAP_NAME then mat = o break end
  end
  local cx, cz, hx, hz, top = 0, 0, 22.9, 22.9, 1.6
  if mat ~= nil then
    local b = mat.getBounds()
    if b.size.x > 5 and b.size.z > 5 then
      cx, cz, hx, hz = b.center.x, b.center.z, b.size.x / 2, b.size.z / 2
      top = b.center.y + b.size.y / 2
    else
      return { cx = 0, cz = 0, hx = CFG.MAP_HALF_X or 22.9, hz = CFG.MAP_HALF_Z or 22.9, top = 1.6 }
    end
  end
  map = { cx = cx, cz = cz, hx = CFG.MAP_HALF_X or hx, hz = CFG.MAP_HALF_Z or hz, top = top }
  print(string.format("Mapa: %.1f x %.1f. Bacacke zone su izvan mape uz gornji i donji rub.", map.hx * 2, map.hz * 2))
  return map
end

local function zoneDepth(side)
  local m = getMap()
  local edge = math.abs(m.cz + side * m.hz)
  local depth = CFG.ZONE_DEPTH
  local ok, hands = pcall(function() return Hands.getHands() end)
  if ok and hands then
    for _, h in ipairs(hands) do
      local p, s = h.getPosition(), h.getScale()
      if (p.z >= 0) == (side == 1) then
        local inner = math.abs(p.z) - s.z / 2
        if inner > edge then depth = math.min(depth, inner - edge - 0.3) end
      end
    end
  end
  return math.max(1.5, depth)
end

local function zoneRect(side)
  local m = getMap()
  local edge = m.cz + side * m.hz
  local outer = edge + side * zoneDepth(side)
  return {
    x1 = m.cx - m.hx, x2 = m.cx + m.hx,
    z1 = math.min(edge, outer), z2 = math.max(edge, outer),
  }
end

local function inRect(p, r)
  return p.x >= r.x1 and p.x <= r.x2 and p.z >= r.z1 and p.z <= r.z2
end

local function zoneAt(p)
  if inRect(p, zoneRect(1)) then return 1 end
  if inRect(p, zoneRect(-1)) then return -1 end
  return nil
end

local function offMap(p)
  local m = getMap()
  if p.y < m.top - 3 then return true end
  return math.abs(p.x - m.cx) > m.hx + 0.5 or math.abs(p.z - m.cz) > m.hz + 0.5
end

---------------------------------------------------------------- utori za tokene

local function cardHz(card)
  local size = card.getBoundsNormalized().size
  return size.z / card.getScale().z / 2
end

-- osi karte u svijetu (jedinicni vektori lokalnog x i z)
local function cardAxes(card)
  local o = card.getPosition()
  local function unit(v)
    local dx, dz = v.x - o.x, v.z - o.z
    local l = math.sqrt(dx * dx + dz * dz)
    if l < 1e-6 then return {x = 0, z = 0} end
    return {x = dx / l, z = dz / l}
  end
  return o, unit(card.positionToWorld({1, 0, 0})), unit(card.positionToWorld({0, 0, 1}))
end

-- centar utora i u svijetu (sve u jedinicama stola, neovisno o internom skaliranju karte)
-- utori su vodoravni red ispod karte; extra = dodatni pomak prema dolje (za tekst ispod reda)
local function slotWorldOf(card, i, extra)
  local o, ax, az = cardAxes(card)
  local half = card.getBoundsNormalized().size.z / 2
  local along = -(half + CFG.SLOT_GAP + CFG.SLOT_SIZE / 2 + (extra or 0))   -- negativno = iznad karte
  local lat = CFG.SLOT_SIDE + (i - (CFG.SLOTS + 1) / 2) * (CFG.SLOT_SIZE + 0.1)
  return Vector(o.x + az.x * along + ax.x * lat, o.y, o.z + az.z * along + ax.z * lat)
end

-- pola sirine zone: do pola puta do najblize susjedne hero karte u istom redu
local function pzHalfWidth(card)
  local o, ax, az = cardAxes(card)
  local w = CFG.PZ_WIDTH / 2
  for _, c2 in pairs(heroCards) do
    if c2 ~= nil and c2 ~= card then
      local q = c2.getPosition()
      local vx, vz = q.x - o.x, q.z - o.z
      local a = vx * az.x + vz * az.z
      local l = math.abs(vx * ax.x + vz * ax.z)
      if math.abs(a) < 2 and l > 0.5 then w = math.min(w, l / 2 - 0.05) end
    end
  end
  return w
end

-- power-up zona ispod karte (ispod HP/statova): je li tocka unutra
local function inPowerZone(card, p)
  local o, ax, az = cardAxes(card)
  local half = card.getBoundsNormalized().size.z / 2
  local vx, vz = p.x - o.x, p.z - o.z
  local a = vx * az.x + vz * az.z
  local l = vx * ax.x + vz * ax.z
  return a >= half + CFG.PZ_GAP - 0.5 and a <= half + CFG.PZ_GAP + CFG.PZ_DEPTH and math.abs(l) <= pzHalfWidth(card)
end

local function powerZoneCorners(card)
  local o, ax, az = cardAxes(card)
  local half = card.getBoundsNormalized().size.z / 2
  local a1, a2 = half + CFG.PZ_GAP, half + CFG.PZ_GAP + CFG.PZ_DEPTH
  local w = pzHalfWidth(card)
  local function pt(a, l) return {o.x + az.x * a + ax.x * l, o.z + az.z * a + ax.z * l} end
  return { pt(a1, -w), pt(a1, w), pt(a2, w), pt(a2, -w), pt(a1, -w) }
end

-- bonus s power-up karte: red sa statovima u opisu, npr. "Power +3000  DMG +2"
local CARD_KEYS = { HP = "hp", DMG = "dmg", POWER = "pwr", RANGE = "rng", KNOCKBACK = "kb" }
local function cardBonus(o)
  local fx, any = {}, false
  local d = o.getDescription() or ""
  for line in d:gmatch("[^\n]+") do
    for k, v in line:gmatch("(%a+)%s+([%+%-]%d+)") do
      local kk = CARD_KEYS[k:upper()]
      local n = tonumber(v)
      if kk and n then
        if kk == "pwr" then n = n / 1000 end
        if n % 1 == 0 then n = math.floor(n) end
        fx[kk] = (fx[kk] or 0) + n
        any = true
      end
    end
    if any then break end
  end
  return fx, any
end

powerCards = {}   -- [ime heroja] = lista karata u power-up zoni

---------------- action karte
actionTarget = {}     -- [guid karte] = ime heroja (rucno izabran cilj)
actionOwner = {}      -- [guid karte] = boja igraca koji ju je bacio
autoOff = {}          -- [boja] = true kad igrac iskljuci auto cilj
actionCards = {}      -- [guid] = {card, target} izracunato u recomputeBonus
local actionMenu = {}

local function actionZones()
  local list = {}
  for _, o in ipairs(getObjects()) do
    if o.type == "Card" and o.hasTag("Slot") and o.getName() == "Action Cards" then table.insert(list, o) end
  end
  return list
end

local function inActionZone(p)
  for _, z in ipairs(actionZones()) do
    local c = z.getPosition()
    if math.abs(p.x - c.x) <= CFG.AZ_HALF_X and math.abs(p.z - c.z) <= CFG.AZ_HALF_Z then return z end
  end
  return nil
end

local function slotWorld(name, i)
  local card = heroCards[name]
  if card == nil then return nil end
  return slotWorldOf(card, i)
end

-- token izlazi iz utora: vrati mu velicinu i otkljucaj
local function releaseToken(t)
  if t == nil then return end
  local g = t.getGUID()
  local s = slotOf[g]
  slotOf[g] = nil
  if s ~= nil then
    if s.sc then t.setScale({s.sc[1], s.sc[2], s.sc[3]}) end
    t.setLock(false)
  end
end

-- makni utore ciji token vise nije tamo (rucno maknut)
local function validateSlots()
  local now = Time.time
  for g, s in pairs(slotOf) do
    local t = getObjectFromGUID(g)
    local p = slotWorld(s.hero, s.i)
    local fresh = s.t ~= nil and now - s.t < 2   -- token jos leti prema utoru
    if t == nil or p == nil then
      slotOf[g] = nil
    elseif not fresh and not t.held_by_color and not near(t.getPosition(), p, CFG.SLOT_SIZE * 0.8) then
      releaseToken(t)
    end
  end
end

local function slotTaken(name, i, except)
  for g, s in pairs(slotOf) do
    if s.hero == name and s.i == i and g ~= except then return true end
  end
  return false
end

local function parseEffect(text)
  local fx, any = {}, false
  if text == nil or text == "" then return fx, false end
  local line = (text:match("^[^\n]*") or ""):gsub("Š", "S"):gsub("š", "s"):gsub("Ž", "Z"):gsub("ž", "z")
  local function add(k, v)
    local kk = EFFECT_KEYS[k:upper()]
    local n = tonumber((v:gsub("%s", "")))
    if kk and n then
      if kk == "pwr" and math.abs(n) >= 100 then n = n / 1000 end -- "+1000 Power" = +1 PWR
      if n % 1 == 0 then n = math.floor(n) end
      fx[kk] = (fx[kk] or 0) + n
      any = true
    end
  end
  -- "DMG +1" ili "DMG+1"
  for k, v in line:gmatch("(%a+)%s*([%+%-]%s*%d+)") do add(k, v) end
  -- "+1 DMG" ili "+1DMG" (samo ako prvi oblik nije nasao nista)
  if not any then
    for v, k in line:gmatch("([%+%-]%s*%d+)%s*(%a+)") do add(k, v) end
  end
  return fx, any
end

local function tokenImage(t)
  local ok, c = pcall(function() return t.getCustomObject() end)
  if ok and c and c.image then return c.image end
  return nil
end

-- tekst efekta tokena: vlastiti opis ili opis tokena s istom slikom
-- efekt tokena zivi u GM Notes (igraci ga ne vide); opis se pokazuje samo dok je token licem gore
local function tokenEffect(o)
  local g = o.getGMNotes()
  if g ~= nil and g ~= "" then return g end
  local d = o.getDescription()
  if d ~= nil and d ~= "" then return d end
  return nil
end

function syncTokenDesc(o)
  if not isToken(o) then return end
  local g = o.getGMNotes() or ""
  local d = o.getDescription() or ""
  if g == "" and d ~= "" then o.setGMNotes(d) g = d end  -- opis upisan rucno -> premjesti u GM Notes
  if g == "" then return end
  local want = o.is_face_down and "" or g
  if d ~= want then o.setDescription(want) end
  -- face down core: i ime skriveno (inace tooltip izda efekt)
  if isWall(o) or o.hasTag("Izvor") then return end
  local gid, nm = o.getGUID(), o.getName()
  if o.is_face_down then
    if nm ~= "Core" then
      coreRealName[gid] = nm
      o.setName("Core")
    end
  elseif nm == "Core" then
    local real = coreRealName[gid]
    if real == nil or real == "" then real = (effectLabelPlain and effectLabelPlain(g)) or g end
    o.setName(real)
    coreRealName[gid] = nil
  end
end

function onObjectRotate(o, spin, flip, color, oldSpin, oldFlip)
  if flip ~= oldFlip and isToken(o) then
    Wait.time(function() if o ~= nil then syncTokenDesc(o) end end, 0.6)
  end
end

local function tokenEffectText(t)
  local d = tokenEffect(t)
  if d ~= nil then return d end
  local img = tokenImage(t)
  if img then return effectByImage[img] end
  return nil
end

local function effectLabel(text)
  if text == nil or text == "" then return "?", {1, 1, 1} end
  local fx, any = parseEffect(text)
  if not any then
    local line = text:match("^[^\n]*") or ""
    if #line > 22 then line = line:sub(1, 21) .. "." end
    return line, {1, 1, 1}
  end
  local parts, pos, neg = {}, false, false
  for _, k in ipairs({"hp", "dmg", "pwr", "rng", "kb", "wt"}) do
    local v = fx[k]
    if v and v ~= 0 then
      table.insert(parts, (v > 0 and "+" or "") .. v .. " " .. k:upper())
      if v > 0 then pos = true else neg = true end
    end
  end
  local col = {1, 1, 1}
  if pos and not neg then col = {0.5, 1, 0.5} elseif neg and not pos then col = {1, 0.5, 0.5} end
  return table.concat(parts, "  "), col
end

function effectLabelPlain(text)
  local s = effectLabel(text)
  return s
end

function recomputeBonus()
  validateSlots()

  effectByImage = {}
  for _, o in ipairs(getObjects()) do
    if isToken(o) then
      syncTokenDesc(o)
      local d = tokenEffect(o)
      local img = tokenImage(o)
      if img and d ~= nil and d ~= "" and effectByImage[img] == nil then effectByImage[img] = d end
    end
  end

  local nb = {}
  for g, s in pairs(slotOf) do
    local t = getObjectFromGUID(g)
    if t ~= nil then
      local fx = parseEffect(tokenEffectText(t))
      nb[s.hero] = nb[s.hero] or {}
      for k, v in pairs(fx) do nb[s.hero][k] = (nb[s.hero][k] or 0) + v end
    end
  end
  -- power-up karte u zoni ispod hero karte
  powerCards = {}
  local heroCardSet = {}
  for _, c in pairs(heroCards) do if c ~= nil then heroCardSet[c] = true end end
  for _, o in ipairs(getObjects()) do
    if o.type == "Card" and not o.hasTag("Slot") and not heroCardSet[o] and not o.held_by_color then
      local p = o.getPosition()
      for name, card in pairs(heroCards) do
        if card ~= nil and inPowerZone(card, p) then
          local fx = cardBonus(o)
          nb[name] = nb[name] or {}
          for k, v in pairs(fx) do nb[name][k] = (nb[name][k] or 0) + v end
          powerCards[name] = powerCards[name] or {}
          table.insert(powerCards[name], o)
          break
        end
      end
    end
  end
  -- action karte u Action zonama
  actionCards = {}
  for _, o in ipairs(getObjects()) do
    if o.type == "Card" and not o.hasTag("Slot") and not o.hasTag("HeroCard") and not o.held_by_color then
      local z = inActionZone(o.getPosition())
      if z ~= nil then
        local g = o.getGUID()
        local target = actionTarget[g]
        if target == nil and not autoOff[actionOwner[g] or ""] then
          -- auto: tocno jedan heroj strane te zone u borbi (otvoren)
          local side = z.getPosition().z >= 0 and 1 or -1
          local found, count = nil, 0
          for n, b in pairs(bodies) do
            if b ~= nil and heroCards[n] ~= nil and sideOfHero(n) == side and b.getStateId() > 1 then
              found, count = n, count + 1
            end
          end
          if count == 1 then target = found end
        end
        actionCards[g] = { card = o, target = target }
        if target ~= nil and heroCards[target] ~= nil then
          local fx = cardBonus(o)
          nb[target] = nb[target] or {}
          for k, v in pairs(fx) do nb[target][k] = (nb[target][k] or 0) + v end
          powerCards[target] = powerCards[target] or {}
          table.insert(powerCards[target], o)
        end
        setupActionCard(o)
        labelActionCard(o, target)
      elseif o.getVar ~= nil and actionLabeled and actionLabeled[o.getGUID()] then
        labelActionCard(o, nil)
      end
    end
  end
  bonus = nb

  -- HP bonus: max raste i trenutni HP s njim; kad padne, trenutni se samo spusti na novi max
  for name, st in pairs(stats) do
    local newB = (bonus[name] or {}).hp or 0
    local oldB = st.hpBonus or 0
    if newB ~= oldB then
      st.hpBonus = newB
      if newB > oldB then st.hp = st.hp + (newB - oldB) end
      st.hp = math.max(0, math.min(st.hp, st.max + newB))
    end
  end
end

---------------------------------------------------------------- vector lines

local PCOLORS = {
  White = {1, 1, 1}, Brown = {0.44, 0.23, 0.09}, Red = {0.86, 0.1, 0.09}, Orange = {0.96, 0.39, 0.11},
  Yellow = {0.9, 0.9, 0.17}, Green = {0.19, 0.7, 0.17}, Teal = {0.13, 0.69, 0.61}, Blue = {0.12, 0.53, 1},
  Purple = {0.63, 0.12, 0.94}, Pink = {0.96, 0.44, 0.81},
}

local drawError = nil

function redrawLines()
  local ok, err = pcall(redrawLinesInner)
  if not ok and err ~= drawError then
    drawError = err
    print("[Evil Boce] greska u crtanju: " .. tostring(err))
  end
end

-- visina stola: po hero kartama (stoje na stolu), inace vrh mata
local function tableY()
  for _, c in pairs(heroCards) do
    if c ~= nil then return c.getPosition().y end
  end
  return getMap().top
end

-- stvarna povrsina ispod tocke (mat, podloga preko mata, karta...), zrakom odozgo;
-- uzima najvisi pogodak ispod "cap" (da ne pogodi hand zone i sl. iznad stola)
local SKIP_TYPES = { Hand = true, Scripting = true, Fog = true, FogOfWar = true, Zone = true }
local function surfaceY(x, z, cap, ignore)
  local ok, hits = pcall(function()
    return Physics.cast({ origin = {x, cap + 0.5, z}, direction = {0, -1, 0}, type = 1, max_distance = 40 })
  end)
  if ok and hits then
    local best = nil
    for _, h in ipairs(hits) do
      local o = h.hit_object
      local py = h.point and h.point.y
      if o ~= nil and py ~= nil and o ~= ignore and not SKIP_TYPES[o.type]
        and not isBody(o) and not isToken(o) and py <= cap then
        if best == nil or py > best then best = py end
      end
    end
    if best ~= nil then return best end
  end
  return nil
end

function redrawLinesInner()
  local lines = {}
  local m = getMap()
  local ty = tableY()

  -- bacacke zone
  for _, side in ipairs({1, -1}) do
    local r = zoneRect(side)
    local y = (surfaceY((r.x1 + r.x2) / 2, (r.z1 + r.z2) / 2, ty + 1) or ty) + 0.05
    table.insert(lines, {
      points = { {r.x1, y, r.z1}, {r.x2, y, r.z1}, {r.x2, y, r.z2}, {r.x1, y, r.z2}, {r.x1, y, r.z1} },
      color = {1, 1, 1, 0.35}, thickness = 0.08,
    })
  end

  -- utori za tokene ispod hero karata
  local h = CFG.SLOT_SIZE / 2
  for name, card in pairs(heroCards) do
    if card ~= nil then
      local y = card.getPosition().y + 0.02
      local _, ax, az = cardAxes(card)
      for i = 1, CFG.SLOTS do
        local c = slotWorldOf(card, i)
        local pts = {}
        for _, d in ipairs({ {-h, -h}, {h, -h}, {h, h}, {-h, h}, {-h, -h} }) do
          table.insert(pts, {c.x + ax.x * d[1] + az.x * d[2], y, c.z + ax.z * d[1] + az.z * d[2]})
        end
        table.insert(lines, { points = pts, color = {1, 0.85, 0.3, 0.6}, thickness = 0.06 })
      end
      local pz = {}
      for _, q in ipairs(powerZoneCorners(card)) do table.insert(pz, {q[1], y, q[2]}) end
      table.insert(lines, { points = pz, color = {0.45, 1, 0.55, 0.45}, thickness = 0.06 })
    end
  end

  -- Action zone i crte od akcije do cilja
  for _, z in ipairs(actionZones()) do
    local c = z.getPosition()
    local y = c.y + 0.02
    local hx, hz = CFG.AZ_HALF_X, CFG.AZ_HALF_Z
    table.insert(lines, { points = { {c.x - hx, y, c.z - hz}, {c.x + hx, y, c.z - hz}, {c.x + hx, y, c.z + hz}, {c.x - hx, y, c.z + hz}, {c.x - hx, y, c.z - hz} },
      color = {0.75, 0.55, 1, 0.5}, thickness = 0.06 })
  end
  for _, a in pairs(actionCards) do
    if a.card ~= nil and a.target ~= nil and heroCards[a.target] ~= nil then
      local p, q = a.card.getPosition(), heroCards[a.target].getPosition()
      local side = sideOfHero(a.target)
      local col = side == 1 and {0.35, 0.75, 1, 0.8} or {1, 0.45, 0.35, 0.8}
      table.insert(lines, { points = { {p.x, p.y + 0.1, p.z}, {q.x, q.y + 0.1, q.z} }, color = col, thickness = 0.08 })
    end
  end

  -- range krugovi: uvijek za otvorene (figurine), i za bakugan/kartu pod misem
  local shown = {}
  local function circle(name)
    if shown[name] then return end
    shown[name] = true
    local body = bodies[name]
    if body == nil then return end
    local c = body.getPosition()
    local r = eff(name, "rng") * rangeUnit()
    local side = sideOfHero(name)
    local col = side == 1 and {0.35, 0.75, 1, 0.9} or (side == -1 and {1, 0.45, 0.35, 0.9} or {0.9, 0.9, 0.9, 0.9})
    -- dno samog bakugana = povrsina na kojoj stoji (radi i za core i za figurinu, na bilo kojoj podlozi)
    local y
    local okb, b = pcall(function() return body.getBounds() end)
    if okb and b and b.size and b.size.y > 0 then
      y = b.center.y - b.size.y / 2 + 0.06
    else
      y = (surfaceY(c.x, c.z, c.y + 0.05, body) or math.max(ty, c.y - 0.3)) + 0.08
    end
    local pts = {}
    for i = 0, 48 do
      local a = i / 48 * 2 * math.pi
      table.insert(pts, {c.x + math.cos(a) * r, y, c.z + math.sin(a) * r})
    end
    table.insert(lines, { points = pts, color = col, thickness = 0.1 })
  end
  for name, body in pairs(bodies) do
    if body ~= nil and heroCards[name] ~= nil and body.getStateId() > 1 then circle(name) end
  end
  for _, name in pairs(hoverName) do
    if name then circle(name) end
  end

  -- setup coreova: dok netko drzi core, sredisnja crta + krug od 3 polja oko postavljenih coreova
  if setupPhase then
    local holding = false
    for _, t in ipairs(getObjects()) do
      if isToken(t) and t.held_by_color and not isWall(t) then holding = true break end
    end
    if holding then
      local y = ty + 0.06
      table.insert(lines, { points = { {m.cx - m.hx, y, m.cz}, {m.cx + m.hx, y, m.cz} }, color = {1, 1, 1, 0.7}, thickness = 0.12 })
      local r = 3 * rangeUnit()
      for _, t in ipairs(coresOnMap(nil)) do
        local c = t.getPosition()
        local pts = {}
        for i = 0, 40 do
          local a = i / 40 * 2 * math.pi
          table.insert(pts, {c.x + math.cos(a) * r, c.y - 0.03, c.z + math.sin(a) * r})
        end
        table.insert(lines, { points = pts, color = {1, 0.3, 0.25, 0.8}, thickness = 0.08 })
      end
    end
  end

  -- strelice za ciljanje
  for color, a in pairs(aiming) do
    if a.obj ~= nil and a.len and a.len > 0.05 and (not a.sling or (a.raw or 0) >= CFG.SLING_MIN) then
      local p = a.from or a.obj.getPosition()
      local y = p.y + 0.3
      local ex, ez = p.x + a.dir.x * a.len, p.z + a.dir.z * a.len
      local hx, hz = -a.dir.x, -a.dir.z
      local px, pz = -a.dir.z, a.dir.x
      local col = PCOLORS[color] or {1, 1, 1}
      table.insert(lines, { points = { {p.x, y, p.z}, {ex, y, ez} }, color = col, thickness = 0.2 })
      if a.sling and a.obj ~= nil and a.obj.held_by_color then
        local h = a.obj.getPosition()
        table.insert(lines, { points = { {p.x, y, p.z}, {h.x, y, h.z} }, color = {1, 1, 1, 0.5}, thickness = 0.08 })
      end
      table.insert(lines, {
        points = { {ex + (hx + px) * 0.8, y, ez + (hz + pz) * 0.8}, {ex, y, ez}, {ex + (hx - px) * 0.8, y, ez + (hz - pz) * 0.8} },
        color = col, thickness = 0.2,
      })
    end
  end

  -- salji samo kad se nesto promijenilo (svaka promjena ide preko mreze svim igracima)
  local sig = {}
  for _, l in ipairs(lines) do
    for _, q in ipairs(l.points) do
      table.insert(sig, string.format("%.2f,%.2f,%.2f", q[1], q[2], q[3]))
    end
    table.insert(sig, "|")
  end
  sig = table.concat(sig)
  if sig ~= lastLineSig then
    lastLineSig = sig
    Global.setVectorLines(lines)
  end
  lastLineCount = #lines
end

function onObjectHover(color, o)
  local before = hoverName[color]
  local name = nil
  if o ~= nil then
    local n = o.getName()
    if n ~= "" and stats[n] ~= nil and (isBody(o) or heroCards[n] == o) then name = n end
  end
  hoverName[color] = name
  if before ~= name then redrawLines() end
end

---------------------------------------------------------------- heroji

function scanHeroes()
  local found = {}
  for _, o in ipairs(getObjects()) do
    if isBody(o) and o.getName() ~= "" then found[o.getName()] = o end
  end
  bodies = found

  for _, o in ipairs(getObjects()) do
    if o.type == "Card" and not o.hasTag("Slot") then
      local n = o.getName()
      if n ~= "" and bodies[n] then
        heroCards[n] = o
        if not o.hasTag("HeroCard") then o.addTag("HeroCard") end
        if stats[n] == nil then
          stats[n] = copy(heroBase[n] or HP_DEFAULT)
          stats[n].hp = stats[n].max
        end
        if stats[n].wt == nil then stats[n].wt = HP_DEFAULT.wt end
        local b = o.getButtons()
        if b == nil or #b == 0 then decorateCard(o, n) end
      end
    end
  end

  recomputeBonus()

  for n, body in pairs(bodies) do
    if body.hasTag("Core") then
      if math.abs(body.drag - CFG.CORE_DRAG) > 0.001 then body.drag = CFG.CORE_DRAG end
      if math.abs(body.angular_drag - CFG.CORE_ANG_DRAG) > 0.001 then body.angular_drag = CFG.CORE_ANG_DRAG end
    end
    if stats[n] ~= nil and heroCards[n] ~= nil then
      local m = math.max(1, eff(n, "wt")) * CFG.MASS_PER_WT
      if math.abs(body.mass - m) > 0.001 then body.mass = m end
    end
  end

  for n, _ in pairs(heroCards) do refreshCard(n, true) end
  updateOverheads()
  redrawLines()
end

function decorateCard(card, name)
  local k = key(name)
  _G["hpMinus_" .. k] = function(_, _, alt) changeHP(name, alt and -5 or -1) end
  _G["hpPlus_" .. k]  = function(_, _, alt) changeHP(name, alt and 5 or 1) end
  _G["hpLabel_" .. k] = function(_, _, alt) changeHP(name, alt and 1 or -1) end
  for _, s in ipairs(STATS) do
    local sk = s[1]
    _G["st_" .. sk .. "_" .. k] = function(_, _, alt) changeStat(name, sk, alt and -1 or 1) end
  end

  card.clearButtons()
  cardSig[card.getGUID()] = nil
  local hz = cardHz(card)
  local z1, z2 = hz + 0.35, hz + 0.8
  local s3 = {CFG.BTN_SCALE, CFG.BTN_SCALE, CFG.BTN_SCALE}

  local function btn(fn, label, x, z, w, h, font, tip, bg)
    card.createButton({
      click_function = fn, function_owner = Global, label = label,
      position = {x, 0.3, z}, scale = s3, width = w, height = h, font_size = font,
      color = bg or {0.1, 0.1, 0.1, 0.9}, font_color = {1, 1, 1}, tooltip = tip or "",
    })
  end

  btn("hpMinus_" .. k, "-", -0.8, z1, 400, 400, 340, "-1 HP (desni klik: -5)")
  btn("hpLabel_" .. k, "", 0, z1, 1300, 400, 300, "Klik: -1 HP, desni klik: +1 HP")
  btn("hpPlus_" .. k, "+", 0.8, z1, 400, 400, 340, "+1 HP (desni klik: +5)")
  -- red statova uzi od karte (izmjereno u TTS-u: karta je ~2.1 lokalne jedinice siroka; 400 sirine gumba ~0.46)
  for i, s in ipairs(STATS) do
    btn("st_" .. s[1] .. "_" .. k, "", (i - (#STATS + 1) / 2) * 0.4, z2, 360, 300, 130, s[2])
  end
  local lp = card.positionToLocal(slotWorldOf(card, (CFG.SLOTS + 1) / 2, CFG.SLOT_SIZE / 2 + 0.3))
  btn("noop", "", lp.x, lp.z, 2200, 260, 150, "", {0, 0, 0, 0})

  card.addContextMenuItem("Bakugan na kartu", function() summonToCard(name) end)
  card.addContextMenuItem("HP: reset na max", function() local t = stats[name]; changeHP(name, eff(name, "max") - t.hp) end)
  card.addContextMenuItem("Max HP +1", function() local t = stats[name]; t.max = t.max + 1; refreshCard(name) end)
  card.addContextMenuItem("Max HP -1", function()
    local t = stats[name]
    t.max = math.max(1, t.max - 1)
    if t.hp > eff(name, "max") then t.hp = eff(name, "max") end
    refreshCard(name)
  end)

  if stats[name].hp == 0 then card.setColorTint({0.4, 0.4, 0.4}) end
end

function refreshCard(name, quiet)
  local card, st = heroCards[name], stats[name]
  if card == nil or st == nil then return end
  local btns = card.getButtons()
  if btns == nil or #btns < SLOT_BTN0 + 1 then return end

  local edits = {}
  local hb = st.hpBonus or 0
  table.insert(edits, {index = 1, label = "HP " .. st.hp .. " / " .. eff(name, "max"),
    font_color = st.hp > 0 and (hb > 0 and {0.5, 1, 0.5} or {1, 1, 1}) or {1, 0.3, 0.3},
    tooltip = hb ~= 0 and ("Max HP: osnova " .. st.max .. ", tokeni " .. (hb > 0 and "+" or "") .. hb) or "Klik: -1 HP, desni klik: +1 HP"})

  local b = bonus[name] or {}
  for i, s in ipairs(STATS) do
    local v = b[s[1]] or 0
    local col = v > 0 and {0.5, 1, 0.5} or (v < 0 and {1, 0.5, 0.5} or {1, 1, 1})
    table.insert(edits, {index = 2 + i, label = s[2] .. " " .. eff(name, s[1]), font_color = col,
      tooltip = s[2] .. ": osnova " .. (st[s[1]] or 0) .. (v ~= 0 and (", bonus (tokeni + karte) " .. (v > 0 and "+" or "") .. v) or "") .. "\nklik +1, desni klik -1 (osnova)"})
  end

  -- zbirni tekst ispod reda tokena
  local parts, tips, pos, neg = {}, {}, false, false
  for _, k in ipairs({"hp", "dmg", "pwr", "rng", "kb", "wt"}) do
    local v = b[k]
    if v and v ~= 0 then
      table.insert(parts, (v > 0 and "+" or "") .. v .. " " .. k:upper())
      if v > 0 then pos = true else neg = true end
    end
  end
  local inSlot = {}
  for g, s in pairs(slotOf) do
    if s.hero == name then inSlot[s.i] = g end
  end
  for i = 1, CFG.SLOTS do
    local t = inSlot[i] and getObjectFromGUID(inSlot[i])
    if t then
      local txt = tokenEffectText(t)
      local lbl = effectLabel(txt)
      table.insert(tips, tokenLabel(t) .. ": " .. lbl)
      local _, any = parseEffect(txt)
      if not any and lbl ~= "?" then table.insert(parts, lbl) end
    end
  end
  for _, c in ipairs(powerCards[name] or {}) do
    local fx, any = cardBonus(c)
    local ps = {}
    for _, k in ipairs({"hp", "dmg", "pwr", "rng", "kb"}) do
      if fx[k] then table.insert(ps, (fx[k] > 0 and "+" or "") .. fx[k] .. " " .. k:upper()) end
    end
    table.insert(tips, c.getName() .. ": " .. (any and table.concat(ps, " ") or "bez bonusa"))
  end
  local col = {1, 1, 1}
  if pos and not neg then col = {0.5, 1, 0.5} elseif neg and not pos then col = {1, 0.5, 0.5} end
  table.insert(edits, {index = SLOT_BTN0, label = table.concat(parts, "  "), font_color = col,
    tooltip = table.concat(tips, "\n")})

  -- editiraj samo ako se nesto promijenilo
  local sig = {}
  for _, e in ipairs(edits) do
    table.insert(sig, e.label .. "|" .. table.concat(e.font_color, ","))
  end
  sig = table.concat(sig, ";")
  if cardSig[card.getGUID()] ~= sig then
    cardSig[card.getGUID()] = sig
    for _, e in ipairs(edits) do card.editButton(e) end
  end

  if not quiet then
    updateOverheads()
    redrawLines()
  end
end

function changeHP(name, d)
  local st = stats[name]
  if st == nil then return end
  local before = st.hp
  st.hp = math.max(0, math.min(eff(name, "max"), st.hp + d))
  local card = heroCards[name]

  if before > 0 and st.hp == 0 then
    broadcastToAll(name .. " je KO!", {1, 0.3, 0.3})
    if card then
      local c = card.getColorTint()
      st.tint = {c.r, c.g, c.b}
      card.setColorTint({0.4, 0.4, 0.4})
    end
    local body = bodies[name]
    if body ~= nil and body.getStateId() > 1 then
      stateLock[name] = Time.time
      safeSetState(body, 1)
    end
    loseGear(name)   -- KO: equipment u graveyard, coreovi na vlasnikovu polovicu
  elseif before == 0 and st.hp > 0 then
    if card then card.setColorTint(st.tint or {1, 1, 1}) end
  end
  refreshCard(name)
end

function changeStat(name, k, d)
  local st = stats[name]
  if st == nil then return end
  local min = (k == "wt") and 1 or 0
  st[k] = math.max(min, (st[k] or 0) + d)
  refreshCard(name)
  if k == "wt" then scanHeroes() end
end

local function statLine(name)
  local st = stats[name]
  return "HP " .. st.hp .. "/" .. eff(name, "max") ..
    "  D" .. eff(name, "dmg") .. " P" .. eff(name, "pwr") .. " R" .. eff(name, "rng") .. " K" .. eff(name, "kb")
end

function updateOverheads()
  for name, st in pairs(stats) do
    local body = bodies[name]
    if body ~= nil and heroCards[name] ~= nil then
      local txt = statLine(name)

      -- tooltip (opis) na coreu i figurini: originalni opis + statovi
      if st.baseDesc == nil then
        local d = body.getDescription() or ""
        st.baseDesc = d:match("^(.-)\n%[") or d
      end
      local desc = (st.baseDesc ~= "" and (st.baseDesc .. "\n") or "") .. "[" .. txt .. "]"
      local g = body.getGUID()
      if lastDesc[g] ~= desc then
        body.setDescription(desc)
        lastDesc[g] = desc
      end

      -- natpis iznad otvorene figurine
      if body.getStateId() > 1 then
        if body.UI.getXml() == "" then
          local size = body.getBoundsNormalized().size
          local h = size.y / body.getScale().y * 100 + CFG.OVERHEAD_MARGIN
          body.UI.setXmlTable({{
            tag = "Text",
            attributes = {
              id = "hp", text = txt, position = "0 0 -" .. h, rotation = "-90 0 0",
              width = 900, height = 150, fontSize = CFG.OVERHEAD_FONT, fontStyle = "Bold",
              color = "#ffffff", outline = "#000000", outlineSize = "2 2",
            },
          }})
        else
          body.UI.setAttribute("hp", "text", txt)
        end
      end
    end
  end
end

---------------------------------------------------------------- bacanje (aim)

function toggleSling(color)
  slingMode[color] = not slingMode[color]
  broadcastToColor("Bacanje: " .. (slingMode[color] and "PRACKA (uhvati core, povuci unazad, pusti)" or "RUKA (normalno)"), color, {0.6, 0.9, 1})
end

function toggleSlingClick(player)
  toggleSling(player.color)
end

function onScriptingButtonDown(index, color)
  if index == CFG.SLING_KEY then
    toggleSling(color)
    return
  end
  if index == CFG.CANCEL_KEY then
    if aiming[color] then
      aiming[color] = nil
      redrawLines()
    end
    return
  end
  if index ~= CFG.AIM_KEY then return end

  local a = aiming[color]
  if a ~= nil then
    launch(color, a)
    return
  end

  local o = Player[color].getHoverObject()
  if o == nil or not o.hasTag("Core") or o.getStateId() > 1 then
    broadcastToColor("Stani misem na zatvoreni bakugan pa stisni Numpad " .. CFG.AIM_KEY .. ".", color, {1, 0.8, 0.3})
    return
  end
  if o.held_by_color then return end
  aiming[color] = { obj = o, dir = {x = 0, z = 1}, len = 0 }
end

function aimTick()
  local any = false
  for color, a in pairs(aiming) do
    if a.sling then
      if a.obj == nil then
        clearGhost(a)
        aiming[color] = nil
      elseif a.obj.held_by_color then
        any = true
        local c = a.obj.getPosition()
        local dx, dz = a.from.x - c.x, a.from.z - c.z
        local raw = math.sqrt(dx * dx + dz * dz)
        a.raw = raw
        if raw > 0.01 then
          a.dir = {x = dx / raw, z = dz / raw}
          a.len = math.min(raw * CFG.SLING_SCALE, CFG.AIM_MAX_LEN)
        end
      end
    elseif a.obj == nil or a.obj.held_by_color then
      aiming[color] = nil
    else
      any = true
      local p = a.obj.getPosition()
      local m = Player[color].getPointerPosition()
      if m ~= nil then
        local dx, dz = m.x - p.x, m.z - p.z
        local len = math.sqrt(dx * dx + dz * dz)
        if len > 0.01 then
          a.dir = {x = dx / len, z = dz / len}
          a.len = math.min(len, CFG.AIM_MAX_LEN)
        end
      end
    end
  end
  if any or lastAimAny then redrawLines() end
  lastAimAny = any
end

function launch(color, a)
  aiming[color] = nil
  local o = a.obj
  if o == nil then redrawLines() return end
  local power = (a.len or 0) / CFG.AIM_MAX_LEN
  local name = heroOf(o)
  local wt = name and math.max(1, eff(name, "wt")) or CFG.WT_BASE
  local speed = math.max(CFG.SPEED_MIN, CFG.SPEED_MAX * power ^ CFG.POWER_CURVE) * math.sqrt(CFG.WT_BASE / wt)

  o.use_gravity = true
  o.addForce({a.dir.x * speed, 0.5 * power, a.dir.z * speed}, 4) -- 4 = VelocityChange
  local radius = math.max(0.2, o.getBoundsNormalized().size.x / 2)
  o.setAngularVelocity({a.dir.z * speed / radius, 0, -a.dir.x * speed / radius})

  if name then inPlay[name] = true end
  moveSince[o.getGUID()] = Time.time
  redrawLines()
end

---------------------------------------------------------------- battle range i stage

-- stage karta ispod bakugana (karta bez Slot taga koja nije hero karta)
local function isStageCard(o)
  if o == nil or o.type ~= "Card" or o.hasTag("Slot") or o.hasTag("HeroCard") then return false end
  local d = o.getDescription() or ""
  return d:sub(1, 5) == "Stage"
end

local function stageUnder(body)
  local p = body.getPosition()
  for _, c in ipairs(getObjects()) do
    if isStageCard(c) and not c.held_by_color then
      local b = c.getBounds()
      if math.abs(p.x - b.center.x) <= b.size.x / 2 and math.abs(p.z - b.center.z) <= b.size.z / 2 and p.y > b.center.y - 0.5 then
        return c
      end
    end
  end
  local ok, hits = pcall(function()
    return Physics.cast({ origin = {p.x, p.y + 1, p.z}, direction = {0, -1, 0}, type = 1, max_distance = 4 })
  end)
  if not ok or hits == nil then return nil end
  for _, h in ipairs(hits) do
    local o = h.hit_object
    if isStageCard(o) then return o end
  end
  return nil
end

-- protivnici u dometu: lista {ime, objekt}
local function enemiesInRange(name, body)
  local list = {}
  local side = sideOfHero(name)
  if side == nil then return list end
  local p = body.getPosition()
  for en, eb in pairs(bodies) do
    if en ~= name and eb ~= nil and not eb.held_by_color and heroCards[en] ~= nil
      and sideOfHero(en) == -side and (stats[en].hp or 0) > 0 then
      local ep = eb.getPosition()
      if zoneAt(ep) == nil and not offMap(ep) then
        local r = math.max(eff(name, "rng"), eff(en, "rng")) * rangeUnit()
        if dist(p, ep) <= r then table.insert(list, {name = en, body = eb}) end
      end
    end
  end
  return list
end

local function openForBattle(name, body, now)
  stateLock[name] = now
  local rotY = body.getRotation().y
  local n = safeSetState(body, 2)
  if n ~= nil then
    n.setRotation({0, rotY, 0})
    if n.getName() == "" then n.setName(name) end
    openedByBattle[name] = true
    bodies[name] = n
  end
end

local function battleCheck(name, body, now)
  if not CFG.BATTLE_OPEN then return end
  if body.held_by_color or not isStill(body) then return end
  if now - (stateLock[name] or 0) < 2 then return end
  local p = body.getPosition()
  if zoneAt(p) ~= nil or offMap(p) then return end

  local open = body.getStateId() > 1
  local enemies = ((stats[name].hp or 0) > 0) and enemiesInRange(name, body) or {}

  -- borba = oba miruju u dometu (prolazak pored ne pokrece borbu)
  local still = {}
  for _, e in ipairs(enemies) do
    if e.body ~= nil and isStill(e.body) then table.insert(still, e) end
  end

  if not open and #still > 0 then
    openForBattle(name, body, now)
    for _, e in ipairs(still) do
      if e.body ~= nil and e.body.getStateId() == 1 and now - (stateLock[e.name] or 0) >= 2 then
        openForBattle(e.name, e.body, now)
      end
    end
  elseif open and #enemies == 0 and openedByBattle[name] and stageUnder(body) == nil then
    stateLock[name] = now
    openedByBattle[name] = nil
    local n = safeSetState(body, 1)
    if n ~= nil then bodies[name] = n end
  elseif not open then
    openedByBattle[name] = nil
  end
end

local function stageCheck()
  if not CFG.STAGE_FLIP then return end
  local sides = {}   -- [card guid] = {card, [1]=true, [-1]=true}
  for name, body in pairs(bodies) do
    if heroCards[name] ~= nil and body ~= nil and not body.held_by_color and isStill(body) then
      local s = stageUnder(body)
      local side = sideOfHero(name)
      if s ~= nil and side ~= nil then
        local g = s.getGUID()
        sides[g] = sides[g] or { card = s }
        sides[g][side] = true
      end
    end
  end
  for _, e in pairs(sides) do
    if e[1] and e[-1] and e.card.is_face_down then
      local r = e.card.getRotation()
      e.card.setRotation({r.x, r.y, 0})   -- otkriven i ostaje otkriven
      local d = e.card.getDescription() or ""
      local effect = d:match("\n\n(.+)$") or ""
      broadcastToAll("Stage otkriven: " .. (e.card.getName() ~= "" and e.card.getName() or "karta")
        .. (effect ~= "" and (" - " .. effect) or ""), {0.6, 0.8, 1})
    end
  end
end

---------------------------------------------------------------- fizika: smirivanje, ring-out, battle

function physicsTick()
  local now = Time.time
  for name, body in pairs(bodies) do
    if body ~= nil then
      local g = body.getGUID()
      local p = body.getPosition()

      if body.held_by_color or body.resting then
        slowSince[g], moveSince[g] = nil, nil
      else
        local s = speedOf(body)
        if s > CFG.LAUNCH_DETECT and heroOf(body) then inPlay[name] = true end
        moveSince[g] = moveSince[g] or now
        if s < CFG.SETTLE_SPEED then
          slowSince[g] = slowSince[g] or now
        else
          slowSince[g] = nil
        end
        if (slowSince[g] and now - slowSince[g] > CFG.SETTLE_TIME)
          or (now - moveSince[g] > CFG.MAX_ROLL_TIME) then
          body.setVelocity({0, 0, 0})
          body.setAngularVelocity({0, 0, 0})
          slowSince[g], moveSince[g] = nil, nil
        end
      end

      if heroOf(body) and not body.held_by_color then
        local z = zoneAt(p)
        if z == nil and not offMap(p) then
          inPlay[name] = true
          battleCheck(name, body, now)
        elseif inPlay[name] and (now - (ringoutLock[name] or 0) > 3) then
          local fell = p.y < getMap().top - 3
          if fell or isStill(body) then ringOut(name, body) end
        end
      end
    end
  end
  stageCheck()
  redrawLines()
end

local function spotInZone(side, idx, count)
  local r = zoneRect(side)
  local m = getMap()
  local w = r.x2 - r.x1
  local x = r.x1 + w * (idx - 0.5) / math.max(1, count)
  return {x, m.top + 1.2, (r.z1 + r.z2) / 2}
end

-- zatvori bakugana (ako je figurina) i postavi ga; novi state objekt treba par frameova prije pomicanja
local function closeAndPlace(name, body, pos, rot)
  stateLock[name] = Time.time
  inPlay[name] = false
  openedByBattle[name] = nil
  local function place(o)
    if o == nil then return end
    o.setVelocity({0, 0, 0})
    o.setAngularVelocity({0, 0, 0})
    o.setRotation(rot)
    o.setPosition(pos)
  end
  if body.getStateId() > 1 then
    local n = safeSetState(body, 1)
    if n ~= nil then bodies[name] = n end
    Wait.frames(function() place(n) end, 5)
  else
    place(body)
  end
end

function ringOut(name, body)
  ringoutLock[name] = Time.time
  stateLock[name] = Time.time
  inPlay[name] = false
  broadcastToAll(name .. " je ispao (ring-out)!", {1, 0.6, 0.2})
  if CFG.RINGOUT_HP > 0 then changeHP(name, -CFG.RINGOUT_HP) end
  loseGear(name)

  local side = sideOfHero(name)
  if side == nil then return end
  closeAndPlace(name, body, spotInZone(side, 1 + (#name % 5), 6), {0, body.getRotation().y, 0})
  ringoutLock[name] = Time.time
end

local function bodyDropped(o)
  local name = heroOf(o)
  if name == nil then return end
  if zoneAt(o.getPosition()) ~= nil then inPlay[name] = false end
end

---------------------------------------------------------------- nova igra

function novaIgraClick(player)
  if Time.time - newGameArmed > 5 then
    newGameArmed = Time.time
    broadcastToColor("Klikni Nova igra jos jednom za potvrdu.", player.color, {1, 0.8, 0.3})
    return
  end
  newGameArmed = 0
  novaIgra()
end

local function sideOfColor(color)
  local ok, t = pcall(function() return Player[color].getHandTransform(1) end)
  if not ok or t == nil then return nil end
  return t.position.z >= 0 and 1 or -1
end

local function rebuildZones()
  for _, z in ipairs(getObjectsWithTag("BacackaZona")) do z.destruct() end
  if not CFG.HIDE_ZONES then return end
  local m = getMap()

  local bySide = { [1] = {}, [-1] = {} }
  for _, p in ipairs(Player.getPlayers()) do
    if p.seated and p.color ~= "Grey" and p.color ~= "Black" then
      local s = sideOfColor(p.color)
      if s then table.insert(bySide[s], p.color) end
    end
  end

  for _, side in ipairs({1, -1}) do
    local colors = bySide[side]
    table.sort(colors)
    local r = zoneRect(side)
    local n = #colors
    for i, c in ipairs(colors) do
      local w = (r.x2 - r.x1) / n
      spawnObjectData({ data = {
        Name = "FogOfWarTrigger",
        Transform = {
          posX = r.x1 + w * (i - 0.5), posY = m.top + 2, posZ = (r.z1 + r.z2) / 2,
          rotX = 0, rotY = 0, rotZ = 0,
          scaleX = w, scaleY = 4, scaleZ = r.z2 - r.z1,
        },
        Nickname = "Bacacka zona " .. c,
        FogColor = c, FogHidePointers = false, FogReverseHiding = false, FogSeethrough = false,
        Tags = {"BacackaZona"}, Locked = true,
      }})
    end
  end
end

---------------------------------------------------------------- spremanje / vracanje pozicija

local SKIP_LAYOUT = { Infinite = true, Scripting = true, Hand = true, Fog = true, FogOfWar = true, Zone = true }

local function layoutable(o)
  if o == nil or SKIP_LAYOUT[o.type] then return false end
  local okl, locked = pcall(function() return o.getLock() end)
  if okl and locked then return false end
  if o.hasTag("BacackaZona") or o.hasTag("Inventar") or o.hasTag("Kopija") then return false end
  return true
end

local function rec(o)
  local p, r = o.getPosition(), o.getRotation()
  return {p.x, p.y, p.z, r.x, r.y, r.z}
end

function saveLayout()
  scanHeroes()
  local L = { objs = {}, decks = {}, heroes = {} }
  local nObj, nDeck = 0, 0
  for _, o in ipairs(getObjects()) do
    if layoutable(o) then
      local hn = heroOf(o)
      if hn and isBody(o) then
        L.heroes[hn] = rec(o)
      elseif o.type == "Deck" then
        local cards = {}
        for _, c in ipairs(o.getObjects()) do table.insert(cards, c.guid) end
        table.insert(L.decks, { g = o.getGUID(), r = rec(o), cards = cards })
        nDeck = nDeck + 1
      elseif o.getName() ~= "" or o.type == "Card" or isToken(o) then
        L.objs[o.getGUID()] = rec(o)
        nObj = nObj + 1
      end
    end
  end
  layout = L
  return nObj, nDeck
end

function saveLayoutClick(player)
  if Time.time - (saveArmed or 0) > 5 then
    saveArmed = Time.time
    broadcastToColor("Klikni Spremi pozicije jos jednom za potvrdu (Nova igra ce vracati na ovaj raspored).", player.color, {1, 0.8, 0.3})
    return
  end
  saveArmed = 0
  local n, d = saveLayout()
  broadcastToAll("Pozicije spremljene: " .. n .. " objekata, " .. d .. " deckova.", {0.4, 1, 0.4})
end

-- nadi objekt po guidu: na stolu, u ruci, ili ga izvadi iz decka/vrece gdje je sad
local function fetch(guid, r)
  local o = getObjectFromGUID(guid)
  if o ~= nil then return o end
  for _, c in ipairs(getObjects()) do
    if c.type == "Deck" or c.type == "Bag" then
      local ok, list = pcall(function() return c.getObjects() end)
      if ok and list then
        for _, it in ipairs(list) do
          if it.guid == guid then
            return c.takeObject({ guid = guid, position = {r[1], r[2] + 1, r[3]}, rotation = {r[4], r[5], r[6]}, smooth = false })
          end
        end
      end
    end
  end
  return nil
end

local function put(o, r, lift)
  o.setVelocity({0, 0, 0})
  o.setRotation({r[4], r[5], r[6]})
  o.setPosition({r[1], r[2] + (lift or 0), r[3]})
end

function restoreLayout()
  local L = layout
  if L == nil then return false end

  -- 1) obicni objekti (karte, tokeni, ...)
  for g, r in pairs(L.objs) do
    local o = fetch(g, r)
    if o ~= nil then put(o, r, 0.1) end
  end

  -- 2) deckovi s tocno onim kartama koje su imali
  for _, d in ipairs(L.decks) do
    local deck = getObjectFromGUID(d.g)
    local inside = {}
    if deck ~= nil then
      for _, it in ipairs(deck.getObjects()) do inside[it.guid] = true end
    end
    local loose = {}
    for _, cg in ipairs(d.cards) do
      if not inside[cg] then
        local c = fetch(cg, d.r)
        if c ~= nil then table.insert(loose, c) end
      end
    end
    if deck ~= nil then
      put(deck, d.r, 0.1)
      for _, c in ipairs(loose) do deck.putObject(c) end
    elseif #loose > 0 then
      for i, c in ipairs(loose) do put(c, d.r, 0.05 * i) end
      Wait.frames(function()
        local ok, groups = pcall(function() return group(loose) end)
        if ok and groups then
          for _, gobj in ipairs(groups) do
            if gobj ~= nil then gobj.setRotation({d.r[4], d.r[5], d.r[6]}) end
          end
        end
      end, 10)
    end
  end

  -- 3) bakugani (po imenu heroja), zatvoreni
  for name, r in pairs(L.heroes) do
    local body = bodies[name]
    if body ~= nil then closeAndPlace(name, body, {r[1], r[2] + 0.2, r[3]}, {r[4], r[5], r[6]}) end
  end
  return true
end

function novaIgra()
  scanHeroes()
  map = nil
  getMap()

  -- tokeni na pocetne pozicije, utori prazni; kopije uzete iz izvora se brisu
  for g, _ in pairs(slotOf) do releaseToken(getObjectFromGUID(g)) end
  slotOf = {}
  for _, t in ipairs(getObjectsWithTag("Kopija")) do
    if not t.held_by_color then t.destruct() end
  end
  local useLayout = layout ~= nil
  for g, h in pairs(useLayout and {} or tokenHome) do
    local t = getObjectFromGUID(g)
    if t ~= nil then
      t.setPositionSmooth({h[1], h[2] + 0.5, h[3]}, false, true)
      t.setRotationSmooth({h[4], h[5], h[6]}, false, true)
    end
  end
  recomputeBonus()

  -- HP reset
  for name, st in pairs(stats) do
    st.hp = eff(name, "max")
    local card = heroCards[name]
    if card ~= nil and st.tint then card.setColorTint(st.tint) end
    st.tint = nil
    refreshCard(name, true)
  end

  if useLayout then restoreLayout() end

  -- coreovi zatvoreni u bacacke zone svoje strane (bez spremljenih pozicija, ili heroji kojih nema u njima)
  local perSide = { [1] = {}, [-1] = {} }
  for name, body in pairs(bodies) do
    if useLayout and layout.heroes[name] ~= nil then body = nil end
    if body ~= nil then
    local side = sideOfHero(name)
    if side then table.insert(perSide[side], {name = name, body = body}) end
    end
  end
  for _, side in ipairs({1, -1}) do
    local list = perSide[side]
    table.sort(list, function(a, b) return a.name < b.name end)
    for i, e in ipairs(list) do
      closeAndPlace(e.name, e.body, spotInZone(side, i, #list), {0, side == 1 and 180 or 0, 0})
    end
  end

  Wait.time(function()
    for _, o in ipairs(getObjects()) do
      if o.type == "Deck" then o.shuffle() end
    end
  end, 1)

  -- energy, turn, setup coreova
  energy = { p = { spent = 0 }, n = { spent = 0 } }
  turnNo = 0
  setupPhase = true
  coreOwner = {}
  refreshEnergySafe()

  rebuildZones()
  updateOverheads()
  redrawLines()
  broadcastToAll("Nova igra! Setup: naizmjence postavite po 6 coreova (2 Buff, 2 Major, 2 Debuff) u PROTIVNICKU polovicu, min 3 polja razmaka - idu face down. Kad ste gotovi: Novi turn.", {0.4, 1, 0.4})
end

---------------------------------------------------------------- tokeni

function tokenTouched(p)
  local token, other = p.token, p.other
  if token == nil or other == nil or not isBody(other) then return end
  if isWall(token) then return end
  local name = other.getName()
  if name == "" then return end

  local g = token.getGUID()
  if (tokenCooldown[g] or 0) > Time.time then return end
  tokenCooldown[g] = Time.time + 2

  if heroCards[name] == nil then
    print(name .. " je taknuo " .. tokenLabel(token))
    return
  end
  if token.held_by_color or slotOf[g] ~= nil then return end
  local lbl = effectLabelPlain(tokenEffectText(token))
  if lbl == nil or lbl == "?" then lbl = tokenLabel(token) end
  broadcastToAll(name .. " je pokupio core: " .. lbl, {1, 0.85, 0.3})
  moveTokenToHero(token, name)
end

local function inventoryFor(token, name)
  local z = token.getPosition().z
  if name and heroCards[name] then z = heroCards[name].getPosition().z end
  local best
  for _, o in ipairs(getObjectsWithTag("Inventar")) do
    if best == nil or math.abs(o.getPosition().z - z) < math.abs(best.getPosition().z - z) then
      best = o
    end
  end
  return best
end

local function inventoryUnder(token)
  local p = token.getPosition()
  for _, o in ipairs(getObjectsWithTag("Inventar")) do
    local b = o.getBoundsNormalized()
    if math.abs(p.x - b.center.x) <= b.size.x / 2 and math.abs(p.z - b.center.z) <= b.size.z / 2 then
      return o
    end
  end
end

function placeInInventory(token, inv)
  releaseToken(token)
  local ts = token.getBoundsNormalized().size
  local step = math.max(ts.x, ts.z) + 0.15
  local ib = inv.getBoundsNormalized()
  local cols = math.max(1, math.floor(ib.size.x / step))
  local rows = math.max(1, math.floor(ib.size.z / step))
  local x0 = ib.center.x - ib.size.x / 2 + step / 2
  local z0 = ib.center.z - ib.size.z / 2 + step / 2
  local top = ib.center.y + ib.size.y / 2 + 0.3

  local taken = {}
  for _, o in ipairs(getObjects()) do
    if o ~= token and isToken(o) then table.insert(taken, o.getPosition()) end
  end

  local done = false
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      if not done then
        local p = Vector(x0 + c * step, top, z0 + r * step)
        local free = true
        for _, q in ipairs(taken) do
          if near(q, p, step * 0.45) then free = false break end
        end
        if free then
          token.setPositionSmooth(p, false, true)
          done = true
        end
      end
    end
  end
  if not done then
    token.setPositionSmooth(Vector(ib.center.x, top + 1, ib.center.z), false, true) -- pun inventar
  end
  Wait.time(function() recomputeBonus(); for n, _ in pairs(heroCards) do refreshCard(n) end end, 0.5)
end

local function putInSlot(token, name, i)
  local card = heroCards[name]
  releaseToken(token)
  local sc = token.getScale()
  local size = token.getBoundsNormalized().size
  local big = math.max(size.x, size.z)
  local f = (big > 0) and math.min(1, CFG.SLOT_SIZE * 0.85 / big) or 1
  token.setScale({sc.x * f, sc.y, sc.z * f})
  slotOf[token.getGUID()] = {hero = name, i = i, t = Time.time, sc = {sc.x, sc.y, sc.z}}

  local pos = slotWorld(name, i)
  pos.y = card.getPosition().y + 0.3
  token.setLock(false)
  token.setRotationSmooth({0, card.getRotation().y, CFG.TOKEN_FACE_Z}, false, true)
  token.setPositionSmooth(pos, false, true)
  Wait.time(function()
    recomputeBonus()
    refreshCard(name)
    if token ~= nil then
      local _, any = parseEffect(tokenEffectText(token))
      if not any then
        local img = tokenImage(token)
        local src = nil
        for _, o in ipairs(getObjects()) do
          if isToken(o) and o ~= token and tokenImage(o) == img and o.getName():find("^Vrsta") then src = o.getName() break end
        end
        broadcastToAll(tokenLabel(token) .. " nema efekt. Upisi ga u opis " .. (src or "tokena") .. ", npr. \"DMG +1\" ili \"+1000 Power\".", {1, 0.8, 0.3})
      end
    end
  end, 0.8)
end

function moveTokenToHero(token, name)
  if isWall(token) then return end
  if heroCards[name] == nil then return end
  validateSlots()
  local g = token.getGUID()
  for i = 1, CFG.SLOTS do
    if not slotTaken(name, i, g) then
      putInSlot(token, name, i)
      return
    end
  end
  broadcastToAll(name .. " ima pune utore, " .. tokenLabel(token) .. " ide u inventar.", {1, 0.8, 0.3})
  local inv = inventoryFor(token, name)
  if inv then placeInInventory(token, inv) end
end

function setupToken(o)
  if not isToken(o) or tokenMenu[o] then return end
  tokenMenu[o] = true

  local g = o.getGUID()
  if tokenHome[g] == nil then
    local p, r = o.getPosition(), o.getRotation()
    tokenHome[g] = {p.x, p.y, p.z, r.x, r.y, r.z}
  end

  if isWall(o) then return end
  o.addContextMenuItem("U inventar", function()
    local s = slotOf[o.getGUID()]
    local inv = inventoryFor(o, s and s.hero)
    if inv then placeInInventory(o, inv) end
  end)
  local names = {}
  for n, _ in pairs(heroCards) do table.insert(names, n) end
  table.sort(names)
  for _, n in ipairs(names) do
    o.addContextMenuItem("Na " .. n, function() moveTokenToHero(o, n) end)
  end
  o.addContextMenuItem("Postavi kao pocetnu poziciju", function()
    local p, r = o.getPosition(), o.getRotation()
    tokenHome[o.getGUID()] = {p.x, p.y, p.z, r.x, r.y, r.z}
    print(tokenLabel(o) .. ": pocetna pozicija spremljena.")
  end)
end

local ALL_COLORS = {"White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink", "Grey", "Black"}

-- praćka: duh (nepomicna kopija) na mjestu corea, pravi core nevidljiv dok se vuce
local function makeGhost(a)
  local o = a.obj
  local ok, data = pcall(function() return o.getData() end)
  if not ok or data == nil then return end
  data.Tags = nil
  data.States = nil
  data.LuaScript = ""
  data.LuaScriptState = ""
  data.XmlUI = ""
  data.Nickname = ""
  data.Description = ""
  data.Locked = true
  data.Hands = false
  local f = a.from
  a.ghost = spawnObjectData({ data = data, position = {f.x, f.y, f.z}, rotation = o.getRotation() })
  if a.ghost ~= nil then
    a.ghost.interactable = false
    a.ghost.setColorTint({0.7, 0.85, 1})
  end
  o.setInvisibleTo(ALL_COLORS)
end

local function clearGhost(a)
  if a == nil then return end
  if a.ghost ~= nil then a.ghost.destruct() end
  a.ghost = nil
  if a.obj ~= nil then a.obj.setInvisibleTo({}) end
end

-- beskonacni izvor: uhvaceni izvor postaje kopija, a na njegovom mjestu se stvori novi izvor
local function takeFromSource(o)
  local p, r = o.getPosition(), o.getRotation()
  local ok, data = pcall(function() return o.getData() end)
  if not ok or data == nil then return end
  local tags = {}
  for _, t in ipairs(data.Tags or {}) do if t ~= "Kopija" then table.insert(tags, t) end end
  data.Tags = tags
  data.Locked = false
  spawnObjectData({ data = data, position = {p.x, p.y, p.z}, rotation = {r.x, r.y, r.z} })
  o.removeTag("Izvor")
  o.addTag("Kopija")
end

function onObjectPickUp(color, o)
  if o ~= nil and o.type == "Card" then
    if inAnyHand(o.getPosition()) then handPick[o.getGUID()] = color end
  end
  if o ~= nil and isBody(o) and o.use_gravity == false then
    o.use_gravity = true
  end
  if o ~= nil and o.hasTag("Izvor") then
    takeFromSource(o)
    return
  end
  if isToken(o) and slotOf[o.getGUID()] ~= nil then
    local s = slotOf[o.getGUID()]
    releaseToken(o)
    recomputeBonus()
    refreshCard(s.hero)
    return
  end
  -- praćka: uzet zatvoreni core
  if slingMode[color] and o.hasTag("Core") and o.getStateId() == 1 then
    local p = o.getPosition()
    aiming[color] = { obj = o, sling = true, from = {x = p.x, y = p.y, z = p.z}, dir = {x = 0, z = 1}, len = 0, raw = 0 }
    makeGhost(aiming[color])
  end
end

local function slingRelease(color, o)
  local a = aiming[color]
  aiming[color] = nil
  clearGhost(a)
  if (a.raw or 0) < CFG.SLING_MIN then
    redrawLines()
    Wait.time(function() if o ~= nil then bodyDropped(o) end end, 0.2)
    return
  end
  local f = a.from
  o.setVelocity({0, 0, 0})
  o.setAngularVelocity({0, 0, 0})
  o.setPosition({f.x, f.y + 0.2, f.z})
  Wait.frames(function()
    if o == nil then return end
    o.setVelocity({0, 0, 0})
    o.setAngularVelocity({0, 0, 0})
    launch(color, a)
  end, 2)
end

-- karta/deck spusten na placeholder (Slot): poravnaj s njim i slozi na hrpu koja je vec tamo
local function snapToSlot(o, color)
  if o == nil or o.held_by_color then return end
  local p = o.getPosition()
  local slot, sd = nil, nil
  for _, s2 in ipairs(getObjects()) do
    if s2.type == "Card" and s2.hasTag("Slot") then
      local b = s2.getBounds()
      if math.abs(p.x - b.center.x) <= b.size.x / 2 + 0.2 and math.abs(p.z - b.center.z) <= b.size.z / 2 + 0.2 then
        local d = dist(p, b.center)
        if sd == nil or d < sd then slot, sd = s2, d end
      end
    end
  end
  if slot == nil or slot.getName() == "Action Cards" then return end

  local sp, sr = slot.getPosition(), slot.getRotation()
  local face = o.getRotation().z
  local sn = slot.getName()
  if sn == "Graveyard" or sn == "Stage" or sn == "Defeated Enemy" then face = 0 elseif sn == "Deck" then face = 180 end
  local rot = {0, sr.y, face}

  -- hrpa koja vec lezi na placeholderu
  local pile = nil
  for _, q in ipairs(getObjects()) do
    if q ~= o and (q.type == "Deck" or q.type == "Card") and not q.hasTag("Slot") and not q.held_by_color
      and near(q.getPosition(), sp, 0.8) then
      pile = q
      break
    end
  end

  o.setRotation(rot)
  if pile ~= nil and pile.type == "Deck" then
    pile.putObject(o)
  elseif pile ~= nil then
    local pp = pile.getPosition()
    pile.setRotation({0, sr.y, pile.getRotation().z})
    o.setPosition({sp.x, pp.y + 0.3, sp.z})
    Wait.frames(function()
      if o ~= nil and pile ~= nil then pcall(function() group({pile, o}) end) end
    end, 10)
  else
    o.setPosition({sp.x, sp.y + 0.2, sp.z})
  end
end

function onObjectDrop(color, o)
  if o ~= nil and o.type == "Card" then
    actionOwner[o.getGUID()] = color
    local fromHand = handPick[o.getGUID()]
    handPick[o.getGUID()] = nil
    if fromHand then payIfPlayed(o, color) end
    Wait.time(function() recomputeBonus(); for n, _ in pairs(heroCards) do refreshCard(n) end end, 0.5)
  end
  if o ~= nil and (o.type == "Card" or o.type == "Deck") and not o.hasTag("Slot") then
    Wait.frames(function() snapToSlot(o, color) end, 3)
  end
  local a = aiming[color]
  if a ~= nil and a.sling and a.obj == o then
    slingRelease(color, o)
    return
  end
  if isBody(o) then
    Wait.time(function() if o ~= nil then bodyDropped(o) end end, 0.2)
    return
  end
  if not isToken(o) then return end
  Wait.time(function()
    if o == nil then return end
    local g = o.getGUID()
    local p = o.getPosition()

    -- kopija vracena na izvor iste vrste -> vraceno u "vrecu"
    if o.hasTag("Kopija") then
      local img = tokenImage(o)
      for _, src in ipairs(getObjectsWithTag("Izvor")) do
        if src ~= o and tokenImage(src) == img and near(p, src.getPosition(), 0.9) then
          releaseToken(o)
          o.destruct()
          return
        end
      end
    end

    if isWall(o) then   -- zid ne ide u utore ni inventar
      if o.hasTag("Kopija") then standWall(o, color) end
      return
    end

    -- spusten na utor?
    for name, _ in pairs(heroCards) do
      for i = 1, CFG.SLOTS do
        local sp = slotWorld(name, i)
        if sp and near(p, sp, CFG.SLOT_SIZE * 0.7) then
          if slotTaken(name, i, g) then
            broadcastToColor("Utor je zauzet.", color, {1, 0.8, 0.3})
          else
            putInSlot(o, name, i)
          end
          return
        end
      end
    end

    local inv = inventoryUnder(o)
    if inv then placeInInventory(o, inv) return end
    if setupPhase and not o.hasTag("Izvor") then coreSetupDrop(o, color) end
    if slotOf[g] then
      local h = slotOf[g].hero
      slotOf[g] = nil
      recomputeBonus()
      refreshCard(h)
    end
  end, 0.3)
end

---------------------------------------------------------------- debug

-- u chat napisi: debug
function onChat(msg, player)
  if msg == "sync" then syncCards(player and player.color) return end
  if msg ~= "debug" then return end
  local m = getMap()
  print(string.format("Mapa centar %.1f,%.1f  pola %.1f x %.1f  vrh %.2f, stol %.2f, crta nacrtano: %s, greska crtanja: %s",
    m.cx, m.cz, m.hx, m.hz, m.top, tableY(), tostring(lastLineCount), tostring(drawError)))
  for name, body in pairs(bodies) do
    if heroCards[name] ~= nil and body ~= nil then
      local p = body.getPosition()
      local near_, nd = "-", 999
      for en, eb in pairs(bodies) do
        if en ~= name and eb ~= nil and heroCards[en] ~= nil and sideOfHero(en) ~= sideOfHero(name) then
          local d = dist(p, eb.getPosition())
          if d < nd then nd, near_ = d, en .. string.format(" %.1f (domet %d)", d, math.max(eff(name, "rng"), eff(en, "rng"))) end
        end
      end
      print(string.format("%s: strana %s, state %d, tip %s, y %.2f, povrsina %s, resting %s, brzina %.2f, zona %s, izvan mape %s, u igri %s, najblizi protivnik %s",
        name, tostring(sideOfHero(name)), body.getStateId(), tostring(body.type), p.y,
        tostring(surfaceY(p.x, p.z, p.y + 0.05, body)), tostring(body.resting), speedOf(body),
        tostring(zoneAt(p)), tostring(offMap(p)), tostring(inPlay[name]), near_))
    end
  end
end

---------------------------------------------------------------- ring-out: gubi tokene i equipment

local function isEquipment(o)
  if o == nil or o.type ~= "Card" or o.hasTag("Slot") then return false end
  local d = o.getDescription() or ""
  return d:sub(1, 9) == "Equipment"
end

-- najblizi "Graveyard" placeholder hero karti
local function graveyardFor(card)
  local best, bd = nil, nil
  local cp = card.getPosition()
  for _, o in ipairs(getObjects()) do
    if o.type == "Card" and o.hasTag("Slot") and o.getName() == "Graveyard" then
      local d = dist(cp, o.getPosition())
      if bd == nil or d < bd then best, bd = o, d end
    end
  end
  return best
end

function loseGear(name)
  local card = heroCards[name]
  if card == nil then return end

  -- 1) coreovi s heroja na vlasnikovu polovicu mape (licem gore, mogu se premjestiti)
  local nTok = 0
  local side = sideOfHero(name) or 1
  local avoid = {}
  local list = {}
  for g, s in pairs(slotOf) do
    if s.hero == name then table.insert(list, g) end
  end
  for _, g in ipairs(list) do
    local t = getObjectFromGUID(g)
    if t ~= nil then
      placeCoreOnSide(t, side, avoid)
      nTok = nTok + 1
    end
  end

  -- 2) equipment karte uz tog heroja na graveyard
  local cp = card.getPosition()
  local gear = {}
  for _, o in ipairs(getObjects()) do
    if isEquipment(o) and not o.held_by_color and (inPowerZone(card, o.getPosition()) or dist(cp, o.getPosition()) <= CFG.GEAR_RADIUS) then
      -- pripada najblizoj hero karti
      local mine = true
      for n2, c2 in pairs(heroCards) do
        if n2 ~= name and c2 ~= nil and dist(o.getPosition(), c2.getPosition()) < dist(o.getPosition(), cp) then mine = false end
      end
      if mine then table.insert(gear, o) end
    end
  end
  local gy = graveyardFor(card)
  if gy ~= nil and #gear > 0 then
    local gp = gy.getPosition()
    local gr = gy.getRotation()
    -- ako na graveyardu vec lezi deck, stavi u njega
    local pile = nil
    for _, o in ipairs(getObjects()) do
      if o.type == "Deck" and dist(o.getPosition(), gp) < 1 then pile = o break end
    end
    for i, c in ipairs(gear) do
      if pile ~= nil then
        pile.putObject(c)
      else
        c.setRotationSmooth({0, gr.y, 0}, false, true)
        c.setPositionSmooth({gp.x, gp.y + 0.3 + i * 0.1, gp.z}, false, true)
      end
    end
  end

  if nTok > 0 or #gear > 0 then
    broadcastToAll(name .. " gubi " .. nTok .. " core(a) (na svoju polovicu, mozete ih premjestiti) i " .. #gear .. " equipment kart(u/e) (na graveyard).", {1, 0.6, 0.2})
  end
  Wait.time(function() recomputeBonus(); refreshCard(name) end, 0.6)
end

---------------------------------------------------------------- bakugan na hero kartu

-- desni klik na hero kartu: njen bakugan (zatvoren) dolazi na kartu i stoji bez gravitacije dok ga ne uhvatis
function summonToCard(name)
  scanHeroes()
  local card, body = heroCards[name], bodies[name]
  if card == nil or body == nil then
    broadcastToAll("Ne nalazim bakugana za " .. name .. ".", {1, 0.6, 0.3})
    return
  end
  local cp, cr = card.getPosition(), card.getRotation()
  local function hold(o)
    if o == nil then return end
    local h = o.getBoundsNormalized().size.y / 2
    o.use_gravity = false
    o.setVelocity({0, 0, 0})
    o.setAngularVelocity({0, 0, 0})
    o.setRotation({0, cr.y, 0})
    o.setPosition({cp.x, cp.y + h + 0.05, cp.z})
    inPlay[name] = false
  end
  stateLock[name] = Time.time
  openedByBattle[name] = nil
  if body.getStateId() > 1 then
    local n = safeSetState(body, 1)
    if n ~= nil then bodies[name] = n end
    Wait.frames(function() hold(n) end, 5)
  else
    hold(body)
  end
end

---------------------------------------------------------------- action karte: meni, oznaka, prekidac

actionLabeled = {}

function setupActionCard(o)
  if actionMenu[o] then return end
  actionMenu[o] = true
  o.addContextMenuItem("Cilj: auto", function()
    actionTarget[o.getGUID()] = nil
    recomputeBonus(); for n, _ in pairs(heroCards) do refreshCard(n) end
  end)
  local names = {}
  for n, _ in pairs(heroCards) do table.insert(names, n) end
  table.sort(names)
  for _, n in ipairs(names) do
    o.addContextMenuItem("Cilj: " .. n, function()
      actionTarget[o.getGUID()] = n
      recomputeBonus(); for h, _ in pairs(heroCards) do refreshCard(h) end
    end)
  end
end

function labelActionCard(o, target)
  local g = o.getGUID()
  local want = target and ("-> " .. target) or nil
  if actionLabeled[g] == (want or false) then return end
  o.clearButtons()
  if want then
    o.createButton({ click_function = "noop", function_owner = Global, label = want,
      position = {0, 0.3, -1.25}, scale = {0.5, 0.5, 0.5}, width = 1200, height = 260, font_size = 200,
      color = {0, 0, 0, 0.75}, font_color = {1, 1, 1} })
    actionLabeled[g] = want
  else
    actionLabeled[g] = nil
  end
end

function toggleAutoActionsClick(player)
  local c = player.color
  autoOff[c] = not autoOff[c]
  broadcastToColor("Auto cilj akcija: " .. (autoOff[c] and "ISKLJUCEN (biras desnim klikom)" or "UKLJUCEN"), c, {0.75, 0.55, 1})
  recomputeBonus(); for n, _ in pairs(heroCards) do refreshCard(n) end
end

---------------------------------------------------------------- ruka (karta uzeta iz ruke)

function inAnyHand(p)
  local ok, hands = pcall(function() return Hands.getHands() end)
  if not ok or hands == nil then return false end
  for _, h in ipairs(hands) do
    local okh, hp, hs = pcall(function() return h.getPosition(), h.getScale() end)
    if okh and hp and hs then
      local sx, sz = hs.x, hs.z
      local okr, r = pcall(function() return h.getRotation() end)
      if okr and r and math.abs(((r.y % 180) - 90)) < 45 then sx, sz = sz, sx end
      if math.abs(p.x - hp.x) <= sx / 2 + 0.3 and math.abs(p.z - hp.z) <= sz / 2 + 0.3 then return true end
    end
  end
  return false
end

-- rezerva ako TTS javlja izlazak iz hand zone
function onObjectLeaveZone(zone, o)
  if zone == nil or o == nil or o.type ~= "Card" then return end
  local ok, t = pcall(function() return zone.type end)
  if ok and t == "Hand" then handPick[o.getGUID()] = o.held_by_color or "?" end
end

---------------------------------------------------------------- energy
-- Max energy = broj turna, najvise CFG.ENERGY_MAX (pravilo od 2026-10-23; nema energy karata ni hrpe).
-- Svaka strana trosi svoj; Novi turn podigne turn i napuni obje strane. Prikaz je traka na ekranu (XML: energyBar).

local function sideKey(side) return side == 1 and "p" or "n" end

function energyState(side)
  local k = sideKey(side)
  energy = energy or {}
  energy[k] = energy[k] or { spent = 0 }
  energy[k].spent = energy[k].spent or 0
  return energy[k]
end

function energyMax()
  return math.min(turnNo or 0, CFG.ENERGY_MAX)
end

function energyInfo(side)
  local e = energyState(side)
  local max = energyMax()
  if e.spent > max then e.spent = max end
  if e.spent < 0 then e.spent = 0 end
  return max - e.spent, max
end

-- Ime strane u traci: boje igraca koji sjede na toj strani (ruka), inace boje ruku te strane.
function energySideName(side)
  local names = {}
  for _, p in ipairs(Player.getPlayers()) do
    if p.seated and p.color ~= "Grey" and p.color ~= "Black" and sideOfColor(p.color) == side then
      table.insert(names, p.color)
    end
  end
  if #names == 0 then return side == 1 and "Green/Blue" or "Red/Yellow" end
  table.sort(names)
  return table.concat(names, "/")
end

function refreshEnergy()
  local turnText = setupPhase and "Setup" or (turnNo or 0) == 0 and "Prije igre" or ("Turn " .. turnNo)
  local parts = { turnText }
  local texts = {}
  for _, side in ipairs({1, -1}) do
    local free, max = energyInfo(side)
    texts[side] = { text = energySideName(side) .. "  " .. free .. " / " .. max, color = free > 0 and "#FFE680" or "#A6A6A6" }
    table.insert(parts, texts[side].text)
  end
  local sig = table.concat(parts, "|")
  if energySig.bar == sig then return end
  energySig.bar = sig
  UI.setAttribute("energyTurn", "text", turnText)
  UI.setAttribute("energyP", "text", texts[1].text)
  UI.setAttribute("energyP", "color", texts[1].color)
  UI.setAttribute("energyN", "text", texts[-1].text)
  UI.setAttribute("energyN", "color", texts[-1].color)
end

-- Gumbi u traci: - potrosi 1, + vrati 1 (recharge efekt ili ispravak).
function enSpend_p() energyAdjust(1, 1) end
function enGive_p() energyAdjust(1, -1) end
function enSpend_n() energyAdjust(-1, 1) end
function enGive_n() energyAdjust(-1, -1) end

function refreshEnergySafe()
  local ok, err = pcall(refreshEnergy)
  if not ok and err ~= energyError then
    energyError = err
    print("[Evil Boce] greska energy: " .. tostring(err))
  end
end

function energyAdjust(side, spend)
  local e = energyState(side)
  local _, max = energyInfo(side)
  e.spent = math.max(0, math.min(max, e.spent + spend))
  refreshEnergySafe()
end

function cardCost(o)
  local d = o.getDescription() or ""
  local c = d:match("Cost%s+(%d+)")
  return c and tonumber(c) or nil
end

-- je li karta spustena u igru (Action zona, power zona / na hero karti, Assist mjesto)
function playZoneOf(o)
  local p = o.getPosition()
  if inActionZone(p) then return "Action" end
  for name, card in pairs(heroCards) do
    if card ~= nil and (inPowerZone(card, p) or near(p, card.getPosition(), 1.4)) then return name end
  end
  for _, s in ipairs(getObjects()) do
    if s.type == "Card" and s.hasTag("Slot") and s.getName() == "Assist" and near(p, s.getPosition(), 1.4) then return "Assist" end
  end
  return nil
end

function payIfPlayed(o, color)
  if o == nil or color == nil then return end
  local cost = cardCost(o)
  if cost == nil or cost <= 0 then return end
  if playZoneOf(o) == nil then return end
  local side = sideOfColor(color)
  if side == nil then return end
  local e = energyState(side)
  local free, max = energyInfo(side)
  if free < cost then
    e.spent = max
    broadcastToAll(color .. ": " .. o.getName() .. " (cost " .. cost .. ") - NEMA dovoljno energyja (" .. free .. "/" .. max .. ")!", {1, 0.45, 0.3})
  else
    e.spent = e.spent + cost
    broadcastToAll(color .. ": " .. o.getName() .. " (cost " .. cost .. ") -> energy " .. (free - cost) .. "/" .. max, {1, 0.9, 0.4})
  end
  refreshEnergySafe()
end

---------------------------------------------------------------- zid
-- Zid (kopija s izvora) spusten na mapu stane uspravno i zakljuca se: tvrd je za bounce i ostaje do Nove igre
-- (Nova igra brise kopije). Okreni ga (Q/E) dok ga drzis. Mora biti u rangeu heroja strane koja ga stavlja:
-- skripta samo upozori, ne vraca ga. Desni klik "Makni zid" ga brise.
-- Zid je Custom Tile (Box) sa slikom zida; TTS mu osnovnu velicinu racuna iz slike, pa ga fitWall dovede na
-- WALL_FIELDS polja x WALL_HEIGHT x WALL_THICK (dok lezi: x = duljina, z = visina, y = debljina).

function fitWall(o)
  if o == nil or o.type ~= "Tile" then return end
  local b, s = o.getBoundsNormalized().size, o.getScale()
  if b.x <= 0 or b.y <= 0 or b.z <= 0 then return end
  local nx = s.x * CFG.WALL_FIELDS * rangeUnit() / b.x
  local ny = s.y * CFG.WALL_THICK / b.y
  local nz = s.z * CFG.WALL_HEIGHT / b.z
  if math.abs(nx - s.x) + math.abs(ny - s.y) + math.abs(nz - s.z) > 0.01 then o.setScale({nx, ny, nz}) end
end

function wallInRange(o, color)
  local side = sideOfColor(color)
  local p = o.getPosition()
  for name, body in pairs(bodies) do
    if body ~= nil and heroCards[name] ~= nil and (side == nil or sideOfHero(name) == side)
      and (stats[name].hp or 0) > 0 and zoneAt(body.getPosition()) == nil and not offMap(body.getPosition())
      and dist(p, body.getPosition()) <= eff(name, "rng") * rangeUnit() then
      return name
    end
  end
  return nil
end

function standWall(o, color)
  if offMap(o.getPosition()) then return end
  local r = o.getRotation()
  o.setLock(false)
  fitWall(o)
  o.setRotation({90, r.y, 0})
  Wait.frames(function()
    if o == nil then return end
    local q, b = o.getPosition(), o.getBounds()
    o.setPosition({q.x, getMap().top + b.size.y / 2 + 0.02, q.z})
    o.setLock(true)
  end, 2)
  o.clearContextMenu()
  o.addContextMenuItem("Makni zid", function() o.destruct() end)
  if color and wallInRange(o, color) == nil then
    broadcastToColor("Zid je izvan rangea tvojih heroja u igri (pravilo: u rangeu). Pomakni ga ili desni klik > Makni zid.", color, {1, 0.6, 0.2})
  end
end

---------------------------------------------------------------- novi turn

function noviTurnClick(player)
  turnNo = (turnNo or 0) + 1
  if setupPhase then
    setupPhase = false
    redrawLines()
  end
  for _, side in ipairs({1, -1}) do energyState(side).spent = 0 end
  refreshEnergySafe()
  broadcastToAll("Turn " .. turnNo .. " - Draw faza: svatko vuce 1 kartu, energy " .. energyMax() .. " / " .. energyMax() .. ".", {1, 0.9, 0.4})
end

---------------------------------------------------------------- coreovi: setup i KO

-- Buff / Major / Debuff po efektu
function coreVariant(o)
  local fx = parseEffect(tokenEffectText(o))
  for k, v in pairs(fx) do
    if v < 0 then return "Debuff" end
    if (k == "pwr" and v >= 4) or (k == "dmg" and v >= 4) or (k == "kb" and v >= 2) then return "Major" end
    return "Buff"
  end
  return nil
end

-- coreovi koji leze na mapi (ne u utoru, ne zid, ne izvor)
function coresOnMap(except)
  local r = {}
  for _, t in ipairs(getObjects()) do
    if t ~= except and isToken(t) and not isWall(t) and not t.hasTag("Izvor") and not t.held_by_color
      and slotOf[t.getGUID()] == nil then
      local p = t.getPosition()
      if not offMap(p) and zoneAt(p) == nil then table.insert(r, t) end
    end
  end
  return r
end

local function inventoryOfSide(side)
  for _, o in ipairs(getObjectsWithTag("Inventar")) do
    if (o.getPosition().z >= 0 and 1 or -1) == side then return o end
  end
  return nil
end

function coreSetupDrop(o, color)
  if o == nil or isWall(o) then return end
  local p = o.getPosition()
  if offMap(p) or zoneAt(p) ~= nil then return end
  local side = sideOfColor(color)
  if side == nil then return end
  local m = getMap()
  local problem = nil
  if ((p.z - m.cz) >= 0 and 1 or -1) == side then problem = "Core ide u PROTIVNICKU polovicu." end
  if problem == nil then
    local minD = 3 * rangeUnit()
    for _, t in ipairs(coresOnMap(o)) do
      if dist(p, t.getPosition()) < minD - 0.05 then problem = "Preblizu drugom coreu (min 3 polja)." break end
    end
  end
  if problem then
    local inv = inventoryOfSide(side)
    broadcastToColor(problem .. (inv and " Vracen u inventar." or ""), color, {1, 0.6, 0.2})
    if inv then placeInInventory(o, inv) end
    return
  end

  local g = o.getGUID()
  coreOwner[g] = color
  local r = o.getRotation()
  o.setRotationSmooth({0, r.y, (CFG.TOKEN_FACE_Z + 180) % 360}, false, true)
  Wait.time(function() if o ~= nil then syncTokenDesc(o) end end, 0.8)

  -- 2/2/2 po igracu (samo upozorenje)
  local cnt, total = { Buff = 0, Major = 0, Debuff = 0 }, 0
  for _, t in ipairs(coresOnMap(nil)) do
    if coreOwner[t.getGUID()] == color then
      local v = coreVariant(t)
      if v then cnt[v] = cnt[v] + 1 end
      total = total + 1
    end
  end
  local v = coreVariant(o)
  if total > 6 then
    broadcastToColor("Imas vec " .. total .. " coreova na mapi (pravilo: 6).", color, {1, 0.6, 0.2})
  elseif v and cnt[v] > 2 then
    broadcastToColor("Vec imas " .. cnt[v] .. " " .. v .. " corea (pravilo: 2 Buff, 2 Major, 2 Debuff).", color, {1, 0.6, 0.2})
  else
    broadcastToColor(string.format("Core postavljen (%d/6: Buff %d, Major %d, Debuff %d).", total, cnt.Buff, cnt.Major, cnt.Debuff), color, {0.6, 1, 0.6})
  end
end

-- KO / ring-out: core ide na vlasnikovu polovicu, sto dalje od ostalih coreova i bakugana
function placeCoreOnSide(t, side, avoid)
  releaseToken(t)
  local m = getMap()
  local minD = 3 * rangeUnit()
  local others = {}
  for _, q in ipairs(coresOnMap(t)) do table.insert(others, q.getPosition()) end
  for _, b in pairs(bodies) do if b ~= nil then table.insert(others, b.getPosition()) end end
  for _, a in ipairs(avoid or {}) do table.insert(others, a) end
  local best, bestD = nil, nil
  for _ = 1, 80 do
    local x = m.cx + (math.random() * 2 - 1) * (m.hx - 2)
    local z = m.cz + side * (1.5 + math.random() * (m.hz - 3.5))
    local d = 999
    for _, q in ipairs(others) do d = math.min(d, dist({x = x, z = z}, q)) end
    if bestD == nil or d > bestD then best, bestD = {x = x, z = z}, d end
    if d >= minD then break end
  end
  if avoid then table.insert(avoid, best) end
  local r = t.getRotation()
  t.setRotationSmooth({0, r.y, CFG.TOKEN_FACE_Z}, false, true)
  t.setPositionSmooth({best.x, m.top + 0.6, best.z}, false, true)
end

---------------------------------------------------------------- Sync karata (Faza 2)
-- Gumb "Sync karata" ili chat "sync": podaci s lokalnog servera (CFG.SERVER .. "/api/tts") se primijene na stol.
--   1. Steam URL-ovi koje je Cloud Manager upisao ("Upload All Loaded Files") prvo idu serveru,
--      da Sync ne vrati lokalne putanje.
--   2. Biblioteka: jedan zakljucan deck (tag Biblioteka) s master kopijom svake karte. Deck, a ne vreca:
--      TTS ucita slike svih karata u decku, pa ih Upload vidi (sadrzaj vrece se ne ucitava).
--   3. Klonovi na stolu i u deckovima (po GMNotes = kod karte): ime, opis, slika.
--   4. Heroji: osnovni statsi iz karte (max HP, DMG, PWR, RNG, KB, WT).
-- Karta u ruci se ne dira (TTS bi je izbacio iz ruke); poruka kaze koliko ih je ostalo.

local syncBusy = false
local DELETED_MARK = "[MAKNUTA] "

local function isCode(s)
  return type(s) == "string" and s:match("^%u%w*%-%d%d%d$") ~= nil
end

local function isSteam(u)
  return type(u) == "string" and u:find("^https://steamusercontent") ~= nil
end

local function faceOf(d)
  for _, v in pairs(d.CustomDeck or {}) do return v.FaceURL end
  return nil
end

local function memoOf(d)
  local ok, m = pcall(JSON.decode, d.Memo or "")
  return ok and type(m) == "table" and m or {}
end

local function customDeck(c, back)
  local cd = {}
  cd[c.deck] = { FaceURL = c.face or "", BackURL = back, NumWidth = 1, NumHeight = 1, BackIsHidden = true, UniqueBack = false, Type = 0 }
  return cd
end

local function masterData(c, back)
  return {
    Name = "CardCustom",
    Transform = { posX = 0, posY = 0, posZ = 0, rotX = 0, rotY = 180, rotZ = 180, scaleX = 1, scaleY = 1, scaleZ = 1 },
    Nickname = c.nickname,
    Description = (c.deleted and DELETED_MARK or "") .. c.description,
    GMNotes = c.id,
    Memo = JSON.encode({ key = c.key, rev = c.rev }),
    CardID = c.deck * 100,
    CustomDeck = customDeck(c, back),
    HideWhenFaceDown = true,
    Hands = true,
    SidewaysCard = c.sideways == true, -- landscape Hero (i Evolution dok nema rotirane slike) lezi polozeno
    ColorDiffuse = { r = 0.713, g = 0.713, b = 0.713 },
    Tags = {},
  }
end

-- Podaci jedne karte (sama ili unutar decka) prema karti s servera; true ako se nesto promijenilo.
local function applyCard(d, c, back)
  local cur = nil
  for _, v in pairs(d.CustomDeck or {}) do cur = v end
  local face = c.face or ""
  if d.Nickname == c.nickname and d.Description == c.description and cur ~= nil and cur.FaceURL == face
    and d.CardID == c.deck * 100 and (d.SidewaysCard == true) == (c.sideways == true) then
    return false
  end
  d.Nickname = c.nickname
  d.Description = c.description
  d.GMNotes = c.id
  d.Memo = JSON.encode({ key = c.key, rev = c.rev })
  d.CardID = c.deck * 100
  d.SidewaysCard = c.sideways == true
  d.CustomDeck = customDeck(c, (cur and cur.BackURL) or back)
  return true
end

-- Deck: karte unutra po kodu; CustomDeck i DeckIDs decka se slozi iz karata. Vraca broj promijenjenih karata.
local function applyDeck(d, byId, back)
  local changed = 0
  for _, e in ipairs(d.ContainedObjects or {}) do
    local c = isCode(e.GMNotes) and byId[e.GMNotes] or nil
    if c ~= nil and applyCard(e, c, back) then changed = changed + 1 end
  end
  if changed > 0 then
    local decks, ids = {}, {}
    for i, e in ipairs(d.ContainedObjects) do
      for k, v in pairs(e.CustomDeck or {}) do decks[k] = v end
      ids[i] = e.CardID
    end
    d.CustomDeck = decks
    d.DeckIDs = ids
  end
  return changed
end

-- Novi objekt s istim GUID-om (pozicije za Novu igru, utori i karte heroja ga pamte po GUID-u).
-- Stvara se frame kasnije: dok stari nije unisten, GUID je zauzet i TTS bi dao novi.
local function statesOf(d)
  local r = {}
  for _, s in pairs(d.States or {}) do table.insert(r, s) end
  return r
end

local function respawn(o, data)
  local p, r = o.getPosition(), o.getRotation()
  data.GUID = o.getGUID()
  o.destruct()
  Wait.frames(function()
    spawnObjectData({ data = data, position = { p.x, p.y, p.z }, rotation = { r.x, r.y, r.z } })
  end, 1)
end

function libraryDeck()
  return getObjectsWithTag("Biblioteka")[1]
end

-- Steam URL-ovi s mastera (i bakugana, vidi dolje) koje TTS jos nije javio serveru: { kljuc = url }.
function collectSteamUrls()
  local urls, n = {}, 0
  local lib = libraryDeck()
  if lib ~= nil then
    for _, e in ipairs(lib.getData().ContainedObjects or {}) do
      local m = memoOf(e)
      local f = faceOf(e)
      if m.key and isSteam(f) then urls[m.key] = f; n = n + 1 end
    end
  end
  for _, body in pairs(bodies) do
    if body ~= nil then
      local d = body.getData()
      local m = memoOf(d)
      for _, part in ipairs({ d, table.unpack(statesOf(d)) }) do
        if m.textureKey and part.CustomMesh and isSteam(part.CustomMesh.DiffuseURL) then urls[m.textureKey] = part.CustomMesh.DiffuseURL; n = n + 1 end
        if m.spriteKey and part.CustomImage and isSteam(part.CustomImage.ImageURL) then urls[m.spriteKey] = part.CustomImage.ImageURL; n = n + 1 end
      end
    end
  end
  return urls, n
end

local function syncMessage(msg, col)
  broadcastToAll("[Evil Boce] " .. msg, col or { 1, 0.9, 0.4 })
end

function syncCards(color)
  if syncBusy then return end
  syncBusy = true
  local function fail(msg)
    syncBusy = false
    syncMessage("Sync karata: " .. msg, { 1, 0.45, 0.3 })
  end
  local function fetch()
    WebRequest.get(CFG.SERVER .. "/api/tts", function(req)
      if req.is_error then return fail("server ne odgovara (" .. tostring(req.error) .. "). Je li upaljen?") end
      local ok, p = pcall(JSON.decode, req.text)
      if not ok or type(p) ~= "table" or type(p.cards) ~= "table" then return fail("neispravan odgovor servera") end
      local ok2, err = pcall(applySync, p)
      syncBusy = false
      if not ok2 then syncMessage("Sync karata: greska " .. tostring(err), { 1, 0.45, 0.3 }) end
    end)
  end
  local urls, n = collectSteamUrls()
  if n == 0 then return fetch() end
  WebRequest.custom(CFG.SERVER .. "/api/steam-urls", "POST", true, JSON.encode({ urls = urls }),
    { ["Content-Type"] = "application/json" }, function() fetch() end)
end

function syncCardsClick(player)
  syncCards(player and player.color)
end

function applySync(p)
  local byId = {}
  for _, c in ipairs(p.cards) do byId[c.id] = c end

  -- 1. Biblioteka: master kopija svake karte, iz pocetka (redom po kodu).
  local lib = libraryDeck()
  local before = {}
  if lib ~= nil then
    for _, e in ipairs(lib.getData().ContainedObjects or {}) do before[e.GMNotes] = e end
  end
  local masters, ids, decks = {}, {}, {}
  local nNew, nChanged, nDeleted = 0, 0, 0
  for i, c in ipairs(p.cards) do
    local m = masterData(c, p.back)
    local old = before[c.id]
    if old == nil then
      nNew = nNew + 1
    elseif old.Description ~= m.Description or old.Nickname ~= m.Nickname or faceOf(old) ~= (c.face or "") then
      if c.deleted and (old.Description or ""):sub(1, #DELETED_MARK) ~= DELETED_MARK then nDeleted = nDeleted + 1 else nChanged = nChanged + 1 end
    end
    masters[i] = m
    ids[i] = m.CardID
    decks[c.deck] = m.CustomDeck[c.deck]
  end
  local data = {
    Name = "Deck", Nickname = "Biblioteka karata",
    Description = "Master kopije svih karata (Sync karata). Ne vadi karte rucno; deck mozes pomaknuti.",
    Locked = true, Tags = { "Biblioteka" }, HideWhenFaceDown = true, Hands = false,
    Transform = { posX = 0, posY = 0, posZ = 0, rotX = 0, rotY = 180, rotZ = 180, scaleX = 1, scaleY = 1, scaleZ = 1 },
    ContainedObjects = masters, DeckIDs = ids, CustomDeck = decks,
  }
  if lib ~= nil then
    respawn(lib, data)
  else
    spawnObjectData({ data = data, position = CFG.LIBRARY_POS, rotation = { 0, 180, 180 } })
  end

  -- 2. Klonovi na stolu i u deckovima.
  local nClones, nHand = 0, 0
  for _, o in ipairs(getObjects()) do
    if o ~= lib and not o.hasTag("Biblioteka") then
      if o.type == "Card" and isCode(o.getGMNotes()) and byId[o.getGMNotes()] ~= nil then
        local d = o.getData()
        if applyCard(d, byId[o.getGMNotes()], p.back) then
          if inAnyHand(o.getPosition()) then
            nHand = nHand + 1
          else
            respawn(o, d)
            nClones = nClones + 1
          end
        end
      elseif o.type == "Deck" then
        local d = o.getData()
        local n = applyDeck(d, byId, p.back)
        if n > 0 then
          respawn(o, d)
          nClones = nClones + n
        end
      end
    end
  end

  -- 3. Heroji: osnovni statsi iz karte. Pun HP ostaje pun; inace se samo ogranici na novi max.
  for _, hero in ipairs(p.heroes or {}) do
    heroBase[hero.name] = copy(hero.stats)
    local st = stats[hero.name]
    if st ~= nil then
      local full = (st.hp or 0) >= (st.max or 0)
      for k, v in pairs(hero.stats) do st[k] = v end
      if full or st.hp > st.max then st.hp = st.max end
    end
  end
  local bakuganMsg = syncBakugans(p)
  -- gumbi heroja (HP, statsi) se nacrtaju iznova na svim karti heroja, pa i ostali igraci dobiju cist prikaz
  Wait.frames(function()
    for _, o in ipairs(getObjects()) do
      if o.type == "Card" and o.hasTag("HeroCard") then o.clearButtons() end
    end
    scanHeroes()
  end, 10)

  local parts = {}
  if lib == nil then
    table.insert(parts, "biblioteka napravljena (" .. #p.cards .. " karata)")
  else
    if nNew > 0 then table.insert(parts, nNew .. " nove") end
    if nChanged > 0 then table.insert(parts, nChanged .. " promijenjene") end
    if nDeleted > 0 then table.insert(parts, nDeleted .. " maknute") end
  end
  if nClones > 0 then table.insert(parts, "osvjezeno karata na stolu: " .. nClones) end
  if bakuganMsg ~= "" then table.insert(parts, bakuganMsg) end
  local msg = "Sync karata (baza v" .. tostring(p.version) .. "): " .. (#parts > 0 and table.concat(parts, ", ") or "nema promjena") .. "."
  if nHand > 0 then msg = msg .. " U rukama je " .. nHand .. " starih karata: vrati ih na stol i ponovi Sync." end
  if lib == nil or nNew > 0 or nChanged > 0 then
    msg = msg .. " Za Steam: Modding > Cloud Manager > Upload All Loaded Files, pa spremi save."
  end
  syncMessage(msg)
end

---------------------------------------------------------------- bakugani heroja (Sync karata)
-- Iz web appa: oblik (model iz Bakugan moda, siva tekstura) i boja (ColorDiffuse mnozi teksturu) za kuglu (stanje 1),
-- sprite za figurinu (stanje 2). Velicina i collider ostaju (svi modeli moda su 0.56 i dijele collider kugle).
-- Postojeci bakugan heroja se osvjezi; heroj bez bakugana dobije novog (kopija postojeceg kao predlozak),
-- zakljucanog pokraj biblioteke. Bakugan u igri ili u necijoj ruci se ne dira.

-- Kugla i figurina iz podataka objekta, bez obzira je li trenutno stanje 1 ili 2.
local function bakuganParts(d)
  local ball, fig
  if d.Name == "Custom_Model" then ball = d elseif d.Name == "Figurine_Custom" then fig = d end
  for _, s in pairs(d.States or {}) do
    if s.Name == "Custom_Model" then ball = s elseif s.Name == "Figurine_Custom" then fig = s end
  end
  return ball, fig
end

local BAKUGAN_SPECULAR = 0.25         -- jacina odsjaja obojanog bakugana (mod: 0.6, bijeli)
local BAKUGAN_FRESNEL = 0.3           -- posvjetljenje rubova (mod: 1)

local function sameColor(a, b)
  if a == nil or b == nil then return false end
  return math.abs((a.r or 0) - b.r) < 0.002 and math.abs((a.g or 0) - b.g) < 0.002 and math.abs((a.b or 0) - b.b) < 0.002
end

-- true ako se nesto promijenilo. figFallback: slika figurine za novog bakugana kad heroj nema sprite.
local function applyBakugan(d, hero, figFallback)
  local ball, fig = bakuganParts(d)
  local b = hero.bakugan
  local changed = false
  if ball ~= nil and b ~= nil then
    local col = { r = b.color[1], g = b.color[2], b = b.color[3] }
    ball.CustomMesh = ball.CustomMesh or {}
    -- Modovi bakugani imaju jak bijeli odsjaj (specular 0.6, fresnel 1); na sivoj teksturi puta boja on
    -- prekrije boju svugdje gdje pada svjetlo. Odsjaj zato u boji bakugana i slabiji.
    local sh = ball.CustomMesh.CustomShader or {}
    local shaderOk = sameColor(sh.SpecularColor, col) and math.abs((sh.SpecularIntensity or 0) - BAKUGAN_SPECULAR) < 0.01
      and math.abs((sh.FresnelStrength or 0) - BAKUGAN_FRESNEL) < 0.01
    if ball.CustomMesh.MeshURL ~= b.mesh or ball.CustomMesh.DiffuseURL ~= b.texture or not sameColor(ball.ColorDiffuse, col) or not shaderOk then
      ball.CustomMesh.MeshURL = b.mesh
      ball.CustomMesh.DiffuseURL = b.texture
      ball.ColorDiffuse = col
      ball.CustomMesh.CustomShader = { SpecularColor = col, SpecularIntensity = BAKUGAN_SPECULAR, SpecularSharpness = 6, FresnelStrength = BAKUGAN_FRESNEL }
      changed = true
    end
  end
  local img = hero.sprite or figFallback
  if fig ~= nil and img ~= nil then
    fig.CustomImage = fig.CustomImage or {}
    if fig.CustomImage.ImageURL ~= img then
      fig.CustomImage.ImageURL = img
      changed = true
    end
  end
  local memo = JSON.encode({ textureKey = b and b.textureKey or nil, spriteKey = hero.spriteKey })
  for _, part in ipairs({ d, ball, fig }) do
    if part ~= nil and part.Memo ~= memo then part.Memo = memo; changed = true end
  end
  return changed
end

local function stripGuids(d)
  d.GUID = nil
  for _, s in pairs(d.States or {}) do s.GUID = nil end
end

function syncBakugans(p)
  local faceById = {}
  for _, c in ipairs(p.cards or {}) do faceById[c.id] = c.face end
  local template = nil
  for _, body in pairs(bodies) do
    if body ~= nil then template = body.getData(); break end
  end
  local lib = libraryDeck()
  local base = lib and lib.getPosition() or { x = CFG.LIBRARY_POS[1], y = CFG.LIBRARY_POS[2], z = CFG.LIBRARY_POS[3] }
  local nUpdated, nNew, nSkipped, slot = 0, 0, 0, 0
  for _, hero in ipairs(p.heroes or {}) do
    local body = bodies[hero.name]
    if body ~= nil then
      if inPlay[hero.name] or body.held_by_color then
        nSkipped = nSkipped + 1
      else
        local d = body.getData()
        if applyBakugan(d, hero, nil) then
          local pos, rot = body.getPosition(), body.getRotation()
          d.GUID = body.getGUID()
          body.destruct()
          Wait.frames(function() spawnObjectData({ data = d, position = { pos.x, pos.y, pos.z }, rotation = { rot.x, rot.y, rot.z } }) end, 1)
          nUpdated = nUpdated + 1
        end
      end
    elseif hero.bakugan ~= nil and template ~= nil then
      local d = JSON.decode(JSON.encode(template))
      stripGuids(d)
      local ball, fig = bakuganParts(d)
      for _, part in ipairs({ d, ball, fig }) do
        if part ~= nil then part.Nickname = hero.name; part.Description = "" end
      end
      if ball ~= nil then ball.Tags = { "Core" } end
      if fig ~= nil then fig.Tags = { "Bakugan" } end
      d.Locked = true
      applyBakugan(d, hero, faceById[hero.id])
      slot = slot + 1
      spawnObjectData({ data = d, position = { base.x + 1.6 * slot, base.y + 1, base.z + 4 }, rotation = { 0, 180, 0 } })
      nNew = nNew + 1
    end
  end
  local parts = {}
  if nUpdated > 0 then table.insert(parts, "bakugani osvjezeni: " .. nUpdated) end
  if nNew > 0 then table.insert(parts, "novi bakugani pokraj biblioteke: " .. nNew) end
  if nSkipped > 0 then table.insert(parts, "bakugani u igri preskoceni: " .. nSkipped) end
  return table.concat(parts, ", ")
end
