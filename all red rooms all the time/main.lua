local mod = RegisterMod('All Red Rooms All The Time', 1)
local json = require('json')
local game = Game()

mod.enabledOptions = { 'disabled', 'normal + hard', 'normal + hard + challenges' }
mod.hasDataLoaded = false
mod.rng = RNG()
mod.rngShiftIdx = 35

mod.state = {}
mod.state.enabledOption = 'normal + hard'
mod.state.closeErrorDoors = true
mod.state.reloadFirstRoom = true
mod.state.perDimensionRng = false
mod.state.overrides = {
  normal = 0,
  normalMult = 0,
  normalMult2 = 0,
  angel = 0,
  arcade = 0,
  bedroomClean = 0,
  bedroomDirty = 0,
  curse = 0,
  devil = 0,
  dice = 0,
  library = 0,
  miniBoss = 0,
  planetarium = 0,
  sacrifice = 0,
  secret = 0,
  shop = 0,
  superSecret = 0,
  treasure = 0,
  vault = 0,
}

function mod:onGameStart()
  mod:loadData()
end

function mod:loadData()
  if mod.hasDataLoaded then
    return
  end
  
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if type(state.enabledOption) == 'string' and mod:getEnabledOptionsIndex(state.enabledOption) >= 1 then
        mod.state.enabledOption = state.enabledOption
      end
      for _, v in ipairs({ 'closeErrorDoors', 'reloadFirstRoom', 'perDimensionRng' }) do
        if type(state[v]) == 'boolean' then
          mod.state[v] = state[v]
        end
      end
      if type(state.overrides) == 'table' then
        for _, v in ipairs({ 'normal', 'normalMult', 'normalMult2', 'angel', 'arcade', 'bedroomClean', 'bedroomDirty', 'curse', 'devil', 'dice', 'library', 'miniBoss', 'planetarium', 'sacrifice', 'secret', 'shop', 'superSecret', 'treasure', 'vault' }) do
          if math.type(state.overrides[v]) == 'integer' and state.overrides[v] >= 0 and state.overrides[v] <= 10 then
            mod.state.overrides[v] = state.overrides[v]
          end
        end
      end
    end
  end
  
  mod.hasDataLoaded = true
end

function mod:save()
  mod:SaveData(json.encode(mod.state))
end

function mod:onGameExit()
  mod:save()
  mod:seedRng()
  mod.hasDataLoaded = false
end

function mod:onNewLevel()
  if mod:isDisabled() then
    return
  end
  
  mod:doRedRoomLogic() -- dimension 0
  mod:closeErrorDoors()
end

function mod:onNewRoom()
  if mod:isDisabled() then
    return
  end
  
  local currentDimension = mod:getCurrentDimension()
  
  if (currentDimension == 1 or currentDimension == 2) and mod:isNewDimension() then
    mod:doRedRoomLogic()
  end
  
  mod:closeErrorDoors()
end

function mod:onUpdate()
  if mod:isDisabled() then
    return
  end
  
  mod:closeErrorDoors()
end

function mod:isDisabled()
  mod:loadData()
  return mod.state.enabledOption == 'disabled' or
         (Isaac.GetChallenge() ~= Challenge.CHALLENGE_NULL and mod.state.enabledOption ~= 'normal + hard + challenges') or
         game:IsGreedMode()
end

function mod:reloadFirstRoom()
  if mod.state.reloadFirstRoom then
    local level = game:GetLevel()
    
    -- fix card reading
    -- subtypes: 0 = treasure, 1 = boss, 2 = secret
    local portals = Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.PORTAL_TELEPORT, -1, false, false)
    
    -- fix true co-op
    local trueCoopEnabled = game:GetStateFlag(GameStateFlag.STATE_BOSSPOOL_SWITCHED) == false -- repurposed
    
    level.LeaveDoor = DoorSlot.NO_DOOR_SLOT
    game:ChangeRoom(level:GetCurrentRoomIndex(), -1)
    
    if trueCoopEnabled then
      game:SetStateFlag(GameStateFlag.STATE_BOSSPOOL_SWITCHED, false)
    end
    
    for _, v in ipairs(portals) do
      game:Spawn(v.Type, v.Variant, v.Position, v.Velocity, nil, v.SubType, v.InitSeed) -- v.SpawnerEntity
    end
  end
end

function mod:closeErrorDoors()
  local level = game:GetLevel()
  local room = level:GetCurrentRoom()
  local roomDesc = level:GetCurrentRoomDesc()
  
  if roomDesc.GridIndex >= 0 then
    for i = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
      local door = room:GetDoor(i)
      
      if door and door.TargetRoomIndex == GridRooms.ROOM_ERROR_IDX then
        if door:IsOpen() and mod.state.closeErrorDoors then
          door:SetVariant(DoorVariant.DOOR_UNSPECIFIED) -- DOOR_UNLOCKED doesn't close correctly
          door:Close(true)
        elseif room:IsClear() and not door:IsOpen() and not mod.state.closeErrorDoors then
          door:SetVariant(DoorVariant.DOOR_UNLOCKED)
          door:Open()
        end
      end
    end
  end
end

function mod:doRedRoomLogic()
  local shouldReloadFirstRoom = mod:makeAllRedRoomDoors()
  mod:makeRedRoomsVisible() -- sometimes red rooms won't be visible even if you have mapping, this generally happens when you switch dimensions
  if shouldReloadFirstRoom then
    mod:reloadFirstRoom()
  end
end

function mod:makeAllRedRoomDoors()
  local seeds = game:GetSeeds()
  local level = game:GetLevel()
  local stage = level:GetStage()
  local stageType = level:GetStageType()
  local isRepentanceStageType = stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B
  local currentDimension = mod:getCurrentDimension()
  
  if stage == LevelStage.STAGE8 and currentDimension == 0 then -- home, red rooms are only available every other row and don't connect to each other
    level:MakeRedRoomDoor(95, DoorSlot.LEFT0) -- create the default red room closet
    return false
  elseif (stage == LevelStage.STAGE2_2 or (mod:isCurseOfTheLabyrinth() and stage == LevelStage.STAGE2_1)) and isRepentanceStageType and currentDimension == 1 then
    -- mines escape sequence
    return false
  else
    local illegalRedRooms = mod:getIllegalRedRooms()
    
    if REPENTOGON and mod:hasOverrides() then
      local rng = RNG(seeds:GetStageSeed(isRepentanceStageType and stage + 1 or stage), mod.state.perDimensionRng and mod.rngShiftIdx + currentDimension or mod.rngShiftIdx)
      local redRoomConfigs = {}
      
      for gridIdx = 0, 168 do
        local roomConfig = mod:makeRepentogonRedRoom(gridIdx, rng)
        if roomConfig then
          redRoomConfigs[gridIdx] = roomConfig
        end
      end
      if (stage == LevelStage.STAGE7 and currentDimension == 0) or -- the void
         ((stage == LevelStage.STAGE1_2 or (mod:isCurseOfTheLabyrinth() and stage == LevelStage.STAGE1_1)) and isRepentanceStageType and currentDimension == 1) -- level:HasMirrorDimension
      then
        -- workaround: TryPlaceRoom doesn't place rooms next to boss rooms in the void right now (or the mirror dimension)
        for gridIdx = 0, 168 do
          mod:makeRedRoomDoors(gridIdx, illegalRedRooms)
        end
        for gridIdx = 0, 168 do
          local roomConfig = redRoomConfigs[gridIdx]
          if roomConfig then
            mod:fixRepentogonRedRoom(gridIdx, roomConfig)
          end
        end
        if MinimapAPI then -- this workaround causes issues with minimap api
          MinimapAPI:ClearMap() -- MinimapAPI:ClearLevels()
          MinimapAPI:LoadDefaultMap()
          --MinimapAPI:updatePlayerPos()
          --MinimapAPI:UpdateExternalMap()
        end
      elseif stage ~= LevelStage.STAGE6 and stage ~= LevelStage.STAGE7 then -- not sheol/cathedral/void
        for _, gridIdx in ipairs({
                                   0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
                                   13, 25, 26, 38, 39, 51, 52, 64, 65, 77, 78, 90, 91, 103, 104, 116, 117, 129, 130, 142, 143, 155,
                                   156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168
                                })
        do
          mod:makeRedRoomDoors(gridIdx, illegalRedRooms) -- add red room doors leading to error rooms at the edge of the map
        end
      end
    else
      for gridIdx = 0, 168 do -- full grid
        mod:makeRedRoomDoors(gridIdx, illegalRedRooms)
      end
      mod:makeRedRoomDoors(0, illegalRedRooms) -- otherwise I AM ERROR rooms might not be available from this room
    end
    
    return true
  end
end

function mod:hasOverrides()
  local totalWeight = 0
  
  for k, v in pairs(mod.state.overrides) do
    if k ~= 'normalMult' and k ~= 'normalMult2' then
      totalWeight = totalWeight + v
    end
  end
  
  return totalWeight > 0
end

function mod:makeRepentogonRedRoom(gridIdx, rng)
  local level = game:GetLevel()
  local stage = level:GetStage()
  
  local configToRoomType = {
    normal       = RoomType.ROOM_DEFAULT,
    normalMult   = RoomType.ROOM_DEFAULT,
    normalMult2  = RoomType.ROOM_DEFAULT,
    angel        = RoomType.ROOM_ANGEL,
    arcade       = RoomType.ROOM_ARCADE,
    bedroomClean = RoomType.ROOM_ISAACS,
    bedroomDirty = RoomType.ROOM_BARREN,
    curse        = RoomType.ROOM_CURSE,
    devil        = RoomType.ROOM_DEVIL,
    dice         = RoomType.ROOM_DICE,
    library      = RoomType.ROOM_LIBRARY,
    miniBoss     = RoomType.ROOM_MINIBOSS,
    planetarium  = RoomType.ROOM_PLANETARIUM,
    sacrifice    = RoomType.ROOM_SACRIFICE,
    secret       = RoomType.ROOM_SECRET,
    shop         = RoomType.ROOM_SHOP,
    superSecret  = RoomType.ROOM_SUPERSECRET,
    treasure     = RoomType.ROOM_TREASURE,
    vault        = RoomType.ROOM_CHEST,
  }
  local overrides = {}
  table.insert(overrides, {
    roomType = RoomType.ROOM_DEFAULT,
    weight = mod.state.overrides.normal * (mod.state.overrides.normalMult + 1) * (mod.state.overrides.normalMult2 + 1)
  })
  for k, v in pairs(mod.state.overrides) do
    if configToRoomType[k] ~= RoomType.ROOM_DEFAULT then
      table.insert(overrides, { roomType = configToRoomType[k], weight = v })
    end
  end
  table.sort(overrides, function(a, b)
    return a.roomType < b.roomType
  end)
  
  local wop = WeightedOutcomePicker()
  for _, v in ipairs(overrides) do
    wop:AddOutcomeWeight(v.roomType, v.weight)
  end
  local roomType = wop:PickOutcome(rng)
  
  local seed = rng:Next()
  local reduceWeight = true
  local stbType = Isaac.GetCurrentStageConfigId()
  local roomShape = RoomShape.ROOMSHAPE_1x1
  local minVariant = 0
  local maxVariant = -1
  local minDifficulty = 0
  local maxDifficulty = game:IsHardMode() and 15 or 10 -- todo: more red room difficulty testing
  local requiredDoors = 1 << DoorSlot.LEFT0 | 1 << DoorSlot.UP0 | 1 << DoorSlot.RIGHT0 | 1 << DoorSlot.DOWN0
  local subType = -1
  local mode = -1
  
  if stage == LevelStage.STAGE7 then -- the void
    local stbTypes = {
      StbType.BASEMENT,
      StbType.CELLAR,
      StbType.BURNING_BASEMENT,
      StbType.CAVES,
      StbType.CATACOMBS,
      StbType.FLOODED_CAVES,
      StbType.DEPTHS,
      StbType.NECROPOLIS,
      StbType.DANK_DEPTHS,
      StbType.WOMB,
      StbType.UTERO,
      StbType.SCARRED_WOMB,
      StbType.SHEOL,
      StbType.CATHEDRAL,
      StbType.DARK_ROOM,
      StbType.CHEST,
    }
    if Options.BetterVoidGeneration then
      table.insert(stbTypes, StbType.DOWNPOUR)
      table.insert(stbTypes, StbType.DROSS)
      table.insert(stbTypes, StbType.MINES)
      table.insert(stbTypes, StbType.ASHPIT)
      table.insert(stbTypes, StbType.MAUSOLEUM)
      table.insert(stbTypes, StbType.GEHENNA)
      table.insert(stbTypes, StbType.CORPSE)
    end
    stbType = stbTypes[rng:RandomInt(#stbTypes) + 1]
    maxDifficulty = 20
  end
  
  if mod:getCurrentDimension() == 2 then -- death certificate
    stbType = StbType.HOME
    
    if roomType == RoomType.ROOM_DEFAULT then
      local subTypes = { 0, 2 } -- 0 = isaac's bedroom, 2 = mom's bedroom, 30s = death certificate rooms
      subType = subTypes[rng:RandomInt(#subTypes) + 1] -- can't set a subType range
    end
  end
  
  -- curse rooms: voodoo head (subtype=1) doesn't apply to red rooms
  -- treasure rooms: more options (subtype=1,3) applies automatically
  -- treasure rooms: pay to win (subtype=2,3) doesn't apply to red rooms
  -- shops: tainted keeper (subtype=1xx) doesn't apply to red rooms (check shop level?)
  -- arcades: cain birthright (subtype=1) doesn't apply to red rooms
  if roomType == RoomType.ROOM_DEVIL then
    if mod:hasTrinket(TrinketType.TRINKET_NUMBER_MAGNET) then
      subType = 1
    else
      subType = 0
    end
  elseif roomType == RoomType.ROOM_ANGEL then
    subType = 0 -- 1 is angel shop, 666 is sheol/cathedral portal
  elseif roomType == RoomType.ROOM_ISAACS then
    subType = 0 -- 99 is genesis room
  end
  
  local roomConfig = RoomConfigHolder.GetRandomRoom(seed, reduceWeight, stbType, roomType, roomShape, minVariant, maxVariant, minDifficulty, maxDifficulty, requiredDoors, subType, mode)
  if not roomConfig then
    roomConfig = RoomConfigHolder.GetRandomRoom(seed, reduceWeight, StbType.SPECIAL_ROOMS, roomType, roomShape, minVariant, maxVariant, minDifficulty, maxDifficulty, requiredDoors, subType, mode)
  end
  
  if roomConfig then
    local roomDesc = level:TryPlaceRoom(roomConfig, gridIdx, -1, 0, true, true, true)
    if roomDesc then
      roomDesc.Flags = roomDesc.Flags | RoomDescriptor.FLAG_RED_ROOM
    end
    
    return roomConfig
  end
end

function mod:fixRepentogonRedRoom(gridIdx, roomConfig)
  local level = game:GetLevel()
  local roomDesc = level:GetRoomByIdx(gridIdx, -1)
  
  if roomDesc.GridIndex >= 0 and roomDesc.Data and roomDesc.Data.Shape == RoomShape.ROOMSHAPE_1x1 and mod:isRedRoom(roomDesc) then
    if not (roomDesc.Data.StageID == roomConfig.StageID and roomDesc.Data.Type == roomConfig.Type and roomDesc.Data.Variant == roomConfig.Variant) then
      roomDesc.Data = roomConfig
    end
  end
end

function mod:makeRedRoomDoors(gridIdx, illegalRedRooms)
  local level = game:GetLevel()
  local roomDesc = level:GetRoomByIdx(gridIdx, -1)
  local roomType = nil
  local safeGridIdx
  local shape
  
  if roomDesc.GridIndex >= 0 then
    gridIdx = roomDesc.GridIndex
    safeGridIdx = roomDesc.SafeGridIndex
    roomType = roomDesc.Data.Type
    shape = roomDesc.Data.Shape
  else
    safeGridIdx = gridIdx
    shape = RoomShape.ROOMSHAPE_1x1
  end
  
  local doorSlots
  
  if shape == RoomShape.ROOMSHAPE_1x1 then
    doorSlots = { DoorSlot.LEFT0, DoorSlot.UP0, DoorSlot.RIGHT0, DoorSlot.DOWN0 }
  elseif shape == RoomShape.ROOMSHAPE_IH or shape == RoomShape.ROOMSHAPE_IIH then
    doorSlots = { DoorSlot.LEFT0, DoorSlot.RIGHT0 }
  elseif shape == RoomShape.ROOMSHAPE_IV or shape == RoomShape.ROOMSHAPE_IIV then
    doorSlots = { DoorSlot.UP0, DoorSlot.DOWN0 }
  elseif shape == RoomShape.ROOMSHAPE_1x2 then
    doorSlots = { DoorSlot.LEFT0, DoorSlot.UP0, DoorSlot.RIGHT0, DoorSlot.DOWN0, DoorSlot.LEFT1, DoorSlot.RIGHT1 }
  elseif shape == RoomShape.ROOMSHAPE_2x1 then
    doorSlots = { DoorSlot.LEFT0, DoorSlot.UP0, DoorSlot.RIGHT0, DoorSlot.DOWN0, DoorSlot.UP1, DoorSlot.DOWN1 }
  else -- ROOMSHAPE_2x2, ROOMSHAPE_LTL, ROOMSHAPE_LTR, ROOMSHAPE_LBL, ROOMSHAPE_LBR
    doorSlots = { DoorSlot.LEFT0, DoorSlot.UP0, DoorSlot.RIGHT0, DoorSlot.DOWN0, DoorSlot.LEFT1, DoorSlot.UP1, DoorSlot.RIGHT1, DoorSlot.DOWN1 }
  end
  
  for _, doorSlot in ipairs(doorSlots) do
    if not mod:wouldMakeIllegalRedRoom(gridIdx, roomType, shape, doorSlot, illegalRedRooms) then
      level:MakeRedRoomDoor(safeGridIdx, doorSlot)
    end
  end
end

function mod:makeRedRoomsVisible()
  local currentDimension = mod:getCurrentDimension()
  
  -- mapping isn't enabled in the death certificate dimension
  if currentDimension == 2 then
    return
  end
  
  local level = game:GetLevel()
  local rooms = level:GetRooms()
  
  local visible = 1 << 0
  local icon = 1 << 2
  
  local normalRoomDisplayFlags = 0
  local specialRoomDisplayFlags = 0
  local secretRoomDisplayFlags = 0
  local superSecretRoomDisplayFlags = 0
  
  local hasCompass = level:GetStateFlag(LevelStateFlag.STATE_COMPASS_EFFECT)
  local hasMap = level:GetStateFlag(LevelStateFlag.STATE_MAP_EFFECT)
  local hasBlueMap = level:GetStateFlag(LevelStateFlag.STATE_BLUE_MAP_EFFECT)
  local hasFullMap = level:GetStateFlag(LevelStateFlag.STATE_FULL_MAP_EFFECT)
  
  if hasCompass and hasMap then
    normalRoomDisplayFlags = normalRoomDisplayFlags | visible | icon
    specialRoomDisplayFlags = specialRoomDisplayFlags | visible | icon
  elseif hasCompass then
    specialRoomDisplayFlags = specialRoomDisplayFlags | visible | icon
  elseif hasMap then
    normalRoomDisplayFlags = normalRoomDisplayFlags | visible
    specialRoomDisplayFlags = specialRoomDisplayFlags | visible
  end
  
  if hasBlueMap then
    secretRoomDisplayFlags = secretRoomDisplayFlags | icon
    superSecretRoomDisplayFlags = superSecretRoomDisplayFlags | icon
  end
  
  if hasFullMap then
    normalRoomDisplayFlags = normalRoomDisplayFlags | visible | icon
    specialRoomDisplayFlags = specialRoomDisplayFlags | visible | icon
    secretRoomDisplayFlags = secretRoomDisplayFlags | icon
  end
  
  for i = 0, #rooms - 1 do
    local room = rooms:Get(i)
    
    if room.SafeGridIndex >= 0 and currentDimension == mod:getDimension(room) and mod:isRedRoom(room) and room.DisplayFlags == 0 then
      local roomType = room.Data.Type
      local roomDesc = level:GetRoomByIdx(room.SafeGridIndex, -1) -- writeable
      
      if roomType == RoomType.ROOM_DEFAULT then
        roomDesc.DisplayFlags = normalRoomDisplayFlags
      elseif roomType == RoomType.ROOM_ANGEL or
             roomType == RoomType.ROOM_ARCADE or
             roomType == RoomType.ROOM_BARREN or
             roomType == RoomType.ROOM_BOSS or
             roomType == RoomType.ROOM_CHALLENGE or
             roomType == RoomType.ROOM_CHEST or
             roomType == RoomType.ROOM_CURSE or
             roomType == RoomType.ROOM_DEVIL or
             roomType == RoomType.ROOM_DICE or
             roomType == RoomType.ROOM_ISAACS or
             roomType == RoomType.ROOM_LIBRARY or
             roomType == RoomType.ROOM_MINIBOSS or
             roomType == RoomType.ROOM_PLANETARIUM or
             roomType == RoomType.ROOM_SACRIFICE or
             roomType == RoomType.ROOM_SHOP or
             roomType == RoomType.ROOM_TREASURE
      then
        roomDesc.DisplayFlags = specialRoomDisplayFlags
      elseif roomType == RoomType.ROOM_SECRET then
        roomDesc.DisplayFlags = secretRoomDisplayFlags
      elseif roomType == RoomType.ROOM_SUPERSECRET then
        roomDesc.DisplayFlags = superSecretRoomDisplayFlags
      end
    end
  end
  
  level:UpdateVisibility()
end

-- pay attention to allowed door slots
function mod:getIllegalRedRooms()
  local level = game:GetLevel()
  local rooms = level:GetRooms()
  local currentDimension = mod:getCurrentDimension()
  
  local left = -1
  local right = 1
  local up = -13
  local down = 13
  
  local illegal = {}
  
  for i = 0, #rooms - 1 do
    local room = rooms:Get(i)
    local roomShape = room.Data.Shape
    local roomDoors = room.Data.Doors
    local roomGridIdx = room.GridIndex
    local roomDimension = mod:getDimension(room)
    
    if roomGridIdx >= 0 and roomDimension == currentDimension then
      local tbl = {}
      
      if roomShape == RoomShape.ROOMSHAPE_1x1 or roomShape == RoomShape.ROOMSHAPE_IH or roomShape == RoomShape.ROOMSHAPE_IV then
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)   and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT0) , index = roomGridIdx + left })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)    and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP0)   , index = roomGridIdx + up })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx)  and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT0), index = roomGridIdx + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN0) , index = roomGridIdx + down })
      elseif roomShape == RoomShape.ROOMSHAPE_1x2 or roomShape == RoomShape.ROOMSHAPE_IIV then
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT0) , index = roomGridIdx + left })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP0)   , index = roomGridIdx + up })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx)         and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT0), index = roomGridIdx + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx + down) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN0) , index = roomGridIdx + down + down })
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT1) , index = roomGridIdx + down + left })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx)         and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT1), index = roomGridIdx + down + right })
      elseif roomShape == RoomShape.ROOMSHAPE_2x1 or roomShape == RoomShape.ROOMSHAPE_IIH then
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT0) , index = roomGridIdx + left })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP0)   , index = roomGridIdx + up })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx + right) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT0), index = roomGridIdx + right + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx)        and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN0) , index = roomGridIdx + down })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP1)   , index = roomGridIdx + up + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx)        and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN1) , index = roomGridIdx + down + right })
      elseif roomShape == RoomShape.ROOMSHAPE_2x2 then
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT0) , index = roomGridIdx + left })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP0)   , index = roomGridIdx + up })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx + right) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT0), index = roomGridIdx + right + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx + down) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN0) , index = roomGridIdx + down + down })
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT1) , index = roomGridIdx + down + left })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP1)   , index = roomGridIdx + up + right })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx + right) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT1), index = roomGridIdx + down + right + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx + down) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN1) , index = roomGridIdx + down + down + right })
      elseif roomShape == RoomShape.ROOMSHAPE_LTL then
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT0) , index = roomGridIdx })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP0)   , index = roomGridIdx })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx + right) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT0), index = roomGridIdx + right + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx + down) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN0) , index = roomGridIdx + down + down })
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT1) , index = roomGridIdx + down + left })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP1)   , index = roomGridIdx + up + right })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx + right) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT1), index = roomGridIdx + down + right + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx + down) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN1) , index = roomGridIdx + down + down + right })
      elseif roomShape == RoomShape.ROOMSHAPE_LTR then
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT0) , index = roomGridIdx + left })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP0)   , index = roomGridIdx + up })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx + right) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT0), index = roomGridIdx + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx + down) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN0) , index = roomGridIdx + down + down })
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT1) , index = roomGridIdx + down + left })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP1)   , index = roomGridIdx + right })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx + right) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT1), index = roomGridIdx + down + right + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx + down) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN1) , index = roomGridIdx + down + down + right })
      elseif roomShape == RoomShape.ROOMSHAPE_LBL then
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT0) , index = roomGridIdx + left })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP0)   , index = roomGridIdx + up })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx + right) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT0), index = roomGridIdx + right + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx + down) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN0) , index = roomGridIdx + down })
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT1) , index = roomGridIdx + down })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP1)   , index = roomGridIdx + up + right })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx + right) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT1), index = roomGridIdx + down + right + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx + down) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN1) , index = roomGridIdx + down + down + right })
      elseif roomShape == RoomShape.ROOMSHAPE_LBR then
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT0) , index = roomGridIdx + left })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP0)   , index = roomGridIdx + up })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx + right) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT0), index = roomGridIdx + right + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx + down) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN0) , index = roomGridIdx + down + down })
        table.insert(tbl, { condition = not mod:isAgainstLeftEdge(roomGridIdx)          and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.LEFT1) , index = roomGridIdx + down + left })
        table.insert(tbl, { condition = not mod:isAgainstTopEdge(roomGridIdx)           and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.UP1)   , index = roomGridIdx + up + right })
        table.insert(tbl, { condition = not mod:isAgainstRightEdge(roomGridIdx + right) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.RIGHT1), index = roomGridIdx + down + right })
        table.insert(tbl, { condition = not mod:isAgainstBottomEdge(roomGridIdx + down) and not mod:isDoorSlotAllowed(roomDoors, DoorSlot.DOWN1) , index = roomGridIdx + down + right })
      end
      
      for _, v in ipairs(tbl) do
        if v.condition then
          if not mod:tableHasValue(illegal, v.index) and level:GetRoomByIdx(v.index, -1).GridIndex < 0 then
            table.insert(illegal, v.index)
          end
        end
      end
    end
  end
  
  return illegal
end

function mod:wouldMakeIllegalRedRoom(roomGridIdx, roomType, roomShape, doorSlot, illegalRedRooms)
  local left = -1
  local right = 1
  local up = -13
  local down = 13
  
  -- the game normally protects around boss rooms unless you're up against the edge of the map
  if roomType == RoomType.ROOM_BOSS then
    if roomShape == RoomShape.ROOMSHAPE_1x1 or roomShape == RoomShape.ROOMSHAPE_IH or roomShape == RoomShape.ROOMSHAPE_IV then
      if (doorSlot == DoorSlot.LEFT0  and mod:isAgainstLeftEdge(roomGridIdx))  or
         (doorSlot == DoorSlot.UP0    and mod:isAgainstTopEdge(roomGridIdx))   or
         (doorSlot == DoorSlot.RIGHT0 and mod:isAgainstRightEdge(roomGridIdx)) or
         (doorSlot == DoorSlot.DOWN0  and mod:isAgainstBottomEdge(roomGridIdx))
      then
        return true
      end
    elseif roomShape == RoomShape.ROOMSHAPE_1x2 or roomShape == RoomShape.ROOMSHAPE_IIV then
      if (doorSlot == DoorSlot.LEFT0  and mod:isAgainstLeftEdge(roomGridIdx))          or
         (doorSlot == DoorSlot.UP0    and mod:isAgainstTopEdge(roomGridIdx))           or
         (doorSlot == DoorSlot.RIGHT0 and mod:isAgainstRightEdge(roomGridIdx))         or
         (doorSlot == DoorSlot.DOWN0  and mod:isAgainstBottomEdge(roomGridIdx + down)) or
         (doorSlot == DoorSlot.LEFT1  and mod:isAgainstLeftEdge(roomGridIdx))          or
         (doorSlot == DoorSlot.RIGHT1 and mod:isAgainstRightEdge(roomGridIdx))
      then
        return true
      end
    elseif roomShape == RoomShape.ROOMSHAPE_2x1 or roomShape == RoomShape.ROOMSHAPE_IIH then
      if (doorSlot == DoorSlot.LEFT0  and mod:isAgainstLeftEdge(roomGridIdx))          or
         (doorSlot == DoorSlot.UP0    and mod:isAgainstTopEdge(roomGridIdx))           or
         (doorSlot == DoorSlot.RIGHT0 and mod:isAgainstRightEdge(roomGridIdx + right)) or
         (doorSlot == DoorSlot.DOWN0  and mod:isAgainstBottomEdge(roomGridIdx))        or
         (doorSlot == DoorSlot.UP1    and mod:isAgainstTopEdge(roomGridIdx))           or
         (doorSlot == DoorSlot.DOWN1  and mod:isAgainstBottomEdge(roomGridIdx))
      then
        return true
      end
    elseif roomShape == RoomShape.ROOMSHAPE_2x2 then -- there's no L shaped boss rooms
      if (doorSlot == DoorSlot.LEFT0  and mod:isAgainstLeftEdge(roomGridIdx))          or
         (doorSlot == DoorSlot.UP0    and mod:isAgainstTopEdge(roomGridIdx))           or
         (doorSlot == DoorSlot.RIGHT0 and mod:isAgainstRightEdge(roomGridIdx + right)) or
         (doorSlot == DoorSlot.DOWN0  and mod:isAgainstBottomEdge(roomGridIdx + down)) or
         (doorSlot == DoorSlot.LEFT1  and mod:isAgainstLeftEdge(roomGridIdx))          or
         (doorSlot == DoorSlot.UP1    and mod:isAgainstTopEdge(roomGridIdx))           or
         (doorSlot == DoorSlot.RIGHT1 and mod:isAgainstRightEdge(roomGridIdx + right)) or
         (doorSlot == DoorSlot.DOWN1  and mod:isAgainstBottomEdge(roomGridIdx + down))
      then
        return true
      end
    end
  end
  
  local calculated = -1
  
  if roomShape == RoomShape.ROOMSHAPE_1x1 or roomShape == RoomShape.ROOMSHAPE_IH or roomShape == RoomShape.ROOMSHAPE_IV then
    if doorSlot == DoorSlot.LEFT0 and not mod:isAgainstLeftEdge(roomGridIdx) then
      calculated = roomGridIdx + left
    elseif doorSlot == DoorSlot.UP0 and not mod:isAgainstTopEdge(roomGridIdx) then
      calculated = roomGridIdx + up
    elseif doorSlot == DoorSlot.RIGHT0 and not mod:isAgainstRightEdge(roomGridIdx) then
      calculated = roomGridIdx + right
    elseif doorSlot == DoorSlot.DOWN0 and not mod:isAgainstBottomEdge(roomGridIdx) then
      calculated = roomGridIdx + down
    end
  elseif roomShape == RoomShape.ROOMSHAPE_1x2 or roomShape == RoomShape.ROOMSHAPE_IIV then
    if doorSlot == DoorSlot.LEFT0 and not mod:isAgainstLeftEdge(roomGridIdx) then
      calculated = roomGridIdx + left
    elseif doorSlot == DoorSlot.UP0 and not mod:isAgainstTopEdge(roomGridIdx) then
      calculated = roomGridIdx + up
    elseif doorSlot == DoorSlot.RIGHT0 and not mod:isAgainstRightEdge(roomGridIdx) then
      calculated = roomGridIdx + right
    elseif doorSlot == DoorSlot.DOWN0 and not mod:isAgainstBottomEdge(roomGridIdx + down) then
      calculated = roomGridIdx + down + down
    elseif doorSlot == DoorSlot.LEFT1 and not mod:isAgainstLeftEdge(roomGridIdx) then
      calculated = roomGridIdx + down + left
    elseif doorSlot == DoorSlot.RIGHT1 and not mod:isAgainstRightEdge(roomGridIdx) then
      calculated = roomGridIdx + down + right
    end
  elseif roomShape == RoomShape.ROOMSHAPE_2x1 or roomShape == RoomShape.ROOMSHAPE_IIH then
    if doorSlot == DoorSlot.LEFT0 and not mod:isAgainstLeftEdge(roomGridIdx) then
      calculated = roomGridIdx + left
    elseif doorSlot == DoorSlot.UP0 and not mod:isAgainstTopEdge(roomGridIdx) then
      calculated = roomGridIdx + up
    elseif doorSlot == DoorSlot.RIGHT0 and not mod:isAgainstRightEdge(roomGridIdx + right) then
      calculated = roomGridIdx + right + right
    elseif doorSlot == DoorSlot.DOWN0 and not mod:isAgainstBottomEdge(roomGridIdx) then
      calculated = roomGridIdx + down
    elseif doorSlot == DoorSlot.UP1 and not mod:isAgainstTopEdge(roomGridIdx) then
      calculated = roomGridIdx + up + right
    elseif doorSlot == DoorSlot.DOWN1 and not mod:isAgainstBottomEdge(roomGridIdx) then
      calculated = roomGridIdx + down + right
    end
  elseif roomShape == RoomShape.ROOMSHAPE_2x2 or roomShape == RoomShape.ROOMSHAPE_LTL or roomShape == RoomShape.ROOMSHAPE_LTR or roomShape == RoomShape.ROOMSHAPE_LBL or roomShape == RoomShape.ROOMSHAPE_LBR then
    if doorSlot == DoorSlot.LEFT0 and not mod:isAgainstLeftEdge(roomGridIdx) then
      calculated = roomGridIdx + left
    elseif doorSlot == DoorSlot.UP0 and not mod:isAgainstTopEdge(roomGridIdx) then
      calculated = roomGridIdx + up
    elseif doorSlot == DoorSlot.RIGHT0 and not mod:isAgainstRightEdge(roomGridIdx + right) then
      calculated = roomGridIdx + right + right
    elseif doorSlot == DoorSlot.DOWN0 and not mod:isAgainstBottomEdge(roomGridIdx + down) then
      calculated = roomGridIdx + down + down
    elseif doorSlot == DoorSlot.LEFT1 and not mod:isAgainstLeftEdge(roomGridIdx) then
      calculated = roomGridIdx + down + left
    elseif doorSlot == DoorSlot.UP1 and not mod:isAgainstTopEdge(roomGridIdx) then
      calculated = roomGridIdx + up + right
    elseif doorSlot == DoorSlot.RIGHT1 and not mod:isAgainstRightEdge(roomGridIdx + right) then
      calculated = roomGridIdx + down + right + right
    elseif doorSlot == DoorSlot.DOWN1 and not mod:isAgainstBottomEdge(roomGridIdx + down) then
      calculated = roomGridIdx + down + down + right
    end
    
    if roomShape == RoomShape.ROOMSHAPE_LTL then
      if (doorSlot == DoorSlot.LEFT0 and not mod:isAgainstLeftEdge(roomGridIdx)) or
         (doorSlot == DoorSlot.UP0   and not mod:isAgainstTopEdge(roomGridIdx))
      then
        calculated = roomGridIdx
      end
    elseif roomShape == RoomShape.ROOMSHAPE_LTR then
      if (doorSlot == DoorSlot.RIGHT0 and not mod:isAgainstRightEdge(roomGridIdx + right)) or
         (doorSlot == DoorSlot.UP1    and not mod:isAgainstTopEdge(roomGridIdx))
      then
        calculated = roomGridIdx + right
      end
    elseif roomShape == RoomShape.ROOMSHAPE_LBL then
      if (doorSlot == DoorSlot.DOWN0 and not mod:isAgainstBottomEdge(roomGridIdx + down)) or
         (doorSlot == DoorSlot.LEFT1 and not mod:isAgainstLeftEdge(roomGridIdx))
      then
        calculated = roomGridIdx + down
      end
    elseif roomShape == RoomShape.ROOMSHAPE_LBR then
      if (doorSlot == DoorSlot.RIGHT1 and not mod:isAgainstRightEdge(roomGridIdx + right)) or
         (doorSlot == DoorSlot.DOWN1 and not mod:isAgainstBottomEdge(roomGridIdx + down))
      then
        calculated = roomGridIdx + down + right
      end
    end
  end
  
  for _, illegal in ipairs(illegalRedRooms) do
    if calculated == illegal then
      return true
    end
  end
  
  return false
end

function mod:isDoorSlotAllowed(doors, doorSlot)
  local val = 1 << doorSlot
  return doors & val == val
end

function mod:isAgainstLeftEdge(gridIdx)
  return gridIdx == 0 or
         gridIdx == 13 or
         gridIdx == 26 or
         gridIdx == 39 or
         gridIdx == 52 or
         gridIdx == 65 or
         gridIdx == 78 or
         gridIdx == 91 or
         gridIdx == 104 or
         gridIdx == 117 or
         gridIdx == 130 or
         gridIdx == 143 or
         gridIdx == 156
end

function mod:isAgainstRightEdge(gridIdx)
  return gridIdx == 12 or
         gridIdx == 25 or
         gridIdx == 38 or
         gridIdx == 51 or
         gridIdx == 64 or
         gridIdx == 77 or
         gridIdx == 90 or
         gridIdx == 103 or
         gridIdx == 116 or
         gridIdx == 129 or
         gridIdx == 142 or
         gridIdx == 155 or
         gridIdx == 168
end

function mod:isAgainstTopEdge(gridIdx)
  return gridIdx >= 0 and gridIdx <= 12
end

function mod:isAgainstBottomEdge(gridIdx)
  return gridIdx >= 156 and gridIdx <= 168
end

-- this doesn't work correctly in dimension 0 in the ascent because boss & treasure rooms will have counts carried over from before the ascent
function mod:isNewDimension()
  local level = game:GetLevel()
  local roomDesc = level:GetCurrentRoomDesc()
  
  if roomDesc.GridIndex < 0 then
    return false
  end
  
  local visitedCounts = 0
  local currentDimension = mod:getCurrentDimension()
  local rooms = level:GetRooms()
  
  for i = 0, #rooms - 1 do
    local room = rooms:Get(i)
    
    if currentDimension == mod:getDimension(room) then
      visitedCounts = visitedCounts + room.VisitedCount
      if visitedCounts > 1 then
        break
      end
    end
  end
  
  return visitedCounts <= 1
end

function mod:getCurrentDimension()
  local level = game:GetLevel()
  return mod:getDimension(level:GetCurrentRoomDesc())
end

function mod:getDimension(roomDesc)
  local level = game:GetLevel()
  local ptrHash = GetPtrHash(roomDesc)
  
  -- 0: main dimension
  -- 1: secondary dimension, used by downpour mirror dimension and mines escape sequence
  -- 2: death certificate dimension
  for i = 0, 2 do
    if ptrHash == GetPtrHash(level:GetRoomByIdx(roomDesc.SafeGridIndex, i)) then
      return i
    end
  end
  
  return -1
end

function mod:isRedRoom(roomDesc)
  return roomDesc.Flags & RoomDescriptor.FLAG_RED_ROOM == RoomDescriptor.FLAG_RED_ROOM
end

function mod:isCurseOfTheLabyrinth()
  local level = game:GetLevel()
  local curses = level:GetCurses()
  local curse = LevelCurse.CURSE_OF_LABYRINTH
  
  return curses & curse == curse
end

function mod:hasTrinket(trinket)
  for i = 0, game:GetNumPlayers() - 1 do
    local player = game:GetPlayer(i)
    
    if player:HasTrinket(trinket, false) then
      return true
    end
  end
  
  return false
end

function mod:getEnabledOptionsIndex(option)
  for i, value in ipairs(mod.enabledOptions) do
    if option == value then
      return i
    end
  end
  
  return -1
end

function mod:tableHasValue(tbl, val)
  for _, v in ipairs(tbl) do
    if v == val then
      return true
    end
  end
  
  return false
end

function mod:seedRng()
  repeat
    local rand = Random()  -- 0 to 2^32
    if rand > 0 then       -- if this is 0, it causes a crash later on
      mod.rng:SetSeed(rand, mod.rngShiftIdx)
    end
  until(rand > 0)
end

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  local category = 'ARRATT'
  for _, v in ipairs({ 'Settings', 'Overrides' }) do
    ModConfigMenu.RemoveSubcategory(category, v)
  end
  ModConfigMenu.AddTitle(category, 'Settings', mod.Name)
  ModConfigMenu.AddSpace(category, 'Settings')
  ModConfigMenu.AddText(category, 'Settings', 'Choose where to enable this mod:')
  ModConfigMenu.AddSetting(
    category,
    'Settings',
    {
      Type = ModConfigMenu.OptionType.NUMBER,
      CurrentSetting = function()
        return mod:getEnabledOptionsIndex(mod.state.enabledOption)
      end,
      Minimum = 1,
      Maximum = #mod.enabledOptions,
      Display = function()
        return mod.state.enabledOption
      end,
      OnChange = function(n)
        mod.state.enabledOption = mod.enabledOptions[n]
        mod:save()
      end,
      Info = { 'Red rooms are only created at the', 'start of a new level or dimension' }
    }
  )
  ModConfigMenu.AddSpace(category, 'Settings')
  ModConfigMenu.AddSetting(
    category,
    'Settings',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.closeErrorDoors
      end,
      Display = function()
        return 'I AM ERROR: ' .. (mod.state.closeErrorDoors and 'close' or 'open') .. ' doors'
      end,
      OnChange = function(b)
        mod.state.closeErrorDoors = b
        mod:save()
      end,
      Info = { 'Creating a red room door can lead', 'off the map to an I AM ERROR room' }
    }
  )
  ModConfigMenu.AddSetting(
    category,
    'Settings',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.reloadFirstRoom
      end,
      Display = function()
        return 'Reload first room: ' .. (mod.state.reloadFirstRoom and 'yes' or 'no')
      end,
      OnChange = function(b)
        mod.state.reloadFirstRoom = b
        mod:save()
      end,
      Info = { 'Yes: reload first room to fix transient issues', 'No: set this if you encounter any issues with yes', 'This applies to all first rooms in all levels' }
    }
  )
  ModConfigMenu.AddSetting(
    category,
    'Settings',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return mod.state.perDimensionRng
      end,
      Display = function()
        return 'RNG: per ' .. (mod.state.perDimensionRng and 'level + dimension' or 'level')
      end,
      OnChange = function(b)
        mod.state.perDimensionRng = b
        mod:save()
      end,
      Info = { 'Per dimension only works with overrides' }
    }
  )
  ModConfigMenu.AddSetting(
    category,
    'Overrides',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return false
      end,
      Display = function()
        return 'Reset'
      end,
      OnChange = function(b)
        for k, _ in pairs(mod.state.overrides) do
          mod.state.overrides[k] = 0
        end
        mod:save()
      end,
      Info = { 'Reset the values below to zero' }
    }
  )
  ModConfigMenu.AddSetting(
    category,
    'Overrides',
    {
      Type = ModConfigMenu.OptionType.BOOLEAN,
      CurrentSetting = function()
        return false
      end,
      Display = function()
        return 'Randomize'
      end,
      OnChange = function(b)
        for k, _ in pairs(mod.state.overrides) do
          mod.state.overrides[k] = mod.rng:RandomInt(11)
        end
        mod:save(true)
      end,
      Info = { 'Randomize the values below' }
    }
  )
  ModConfigMenu.AddSpace(category, 'Overrides')
  for _, v in ipairs({
                      { name = 'Normal room'       , field = 'normal' },
                      { name = 'Normal room (mult)', field = 'normalMult' },
                      { name = 'Normal room (mult)', field = 'normalMult2' },
                      { name = 'Angel room'        , field = 'angel' },
                      { name = 'Arcade'            , field = 'arcade' },
                      { name = 'Bedroom (clean)'   , field = 'bedroomClean' },
                      { name = 'Bedroom (dirty)'   , field = 'bedroomDirty' },
                      { name = 'Curse room'        , field = 'curse' },
                      { name = 'Devil room'        , field = 'devil' },
                      { name = 'Dice room'         , field = 'dice' },
                      { name = 'Library'           , field = 'library' },
                      { name = 'Mini-boss'         , field = 'miniBoss' },
                      { name = 'Planetarium'       , field = 'planetarium' },
                      { name = 'Sacrifice room'    , field = 'sacrifice' },
                      { name = 'Secret room'       , field = 'secret' },
                      { name = 'Shop'              , field = 'shop' },
                      { name = 'Super secret room' , field = 'superSecret' },
                      { name = 'Treasure room'     , field = 'treasure' },
                      { name = 'Vault'             , field = 'vault' },
                    })
  do
    ModConfigMenu.AddSetting(
      category,
      'Overrides',
      {
        Type = ModConfigMenu.OptionType.SCROLL,
        CurrentSetting = function()
          return mod.state.overrides[v.field]
        end,
        Display = function()
          local s = v.name .. ': $scroll' .. mod.state.overrides[v.field]
          if v.field == 'normal' then
            s = s .. ' ' .. mod.state.overrides.normal * (mod.state.overrides.normalMult + 1) * (mod.state.overrides.normalMult2 + 1)
          end
          return s
        end,
        OnChange = function(n)
          mod.state.overrides[v.field] = n
          mod:save()
        end,
        Info = { 'Choose relative weights for red room overrides', '(requires repentogon)' }
      }
    )
  end
end
-- end ModConfigMenu --

mod:seedRng()
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.onGameStart)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.onNewLevel)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)

if ModConfigMenu then
  mod:setupModConfigMenu()
end