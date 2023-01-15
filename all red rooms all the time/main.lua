local mod = RegisterMod('All Red Rooms All The Time', 1)
local json = require('json')
local game = Game()

mod.enabledOptions = { 'disabled', 'normal + hard', 'normal + hard + challenges' }

mod.state = {}
mod.state.enabledOption = 'normal + hard'
mod.state.closeErrorDoors = true
mod.state.reloadFirstRoom = true

function mod:loadData()
  if mod:HasData() then
    local _, state = pcall(json.decode, mod:LoadData())
    
    if type(state) == 'table' then
      if type(state.enabledOption) == 'string' and mod:getEnabledOptionsIndex(state.enabledOption) >= 1 then
        mod.state.enabledOption = state.enabledOption
      end
      if type(state.closeErrorDoors) == 'boolean' then
        mod.state.closeErrorDoors = state.closeErrorDoors
      end
      if type(state.reloadFirstRoom) == 'boolean' then
        mod.state.reloadFirstRoom = state.reloadFirstRoom
      end
    end
  end
end

function mod:save()
  mod:SaveData(json.encode(mod.state))
end

function mod:onGameExit()
  mod:save()
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
  return mod.state.enabledOption == 'disabled' or
         (Isaac.GetChallenge() ~= Challenge.CHALLENGE_NULL and mod.state.enabledOption ~= 'normal + hard + challenges') or
         game:IsGreedMode()
end

function mod:reloadFirstRoom()
  if mod.state.reloadFirstRoom then
    local level = game:GetLevel()
    
    level.LeaveDoor = DoorSlot.NO_DOOR_SLOT
    game:ChangeRoom(level:GetCurrentRoomIndex(), -1)
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
  local level = game:GetLevel()
  local stage = level:GetStage()
  local stageType = level:GetStageType()
  local currentDimension = mod:getCurrentDimension()
  
  if stage == LevelStage.STAGE8 and currentDimension == 0 then -- home, red rooms are only available every other row and don't connect to each other
    level:MakeRedRoomDoor(95, DoorSlot.LEFT0) -- create the default red room closet
    return false
  elseif (stage == LevelStage.STAGE2_2 or (mod:isCurseOfTheLabyrinth() and stage == LevelStage.STAGE2_1)) and (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B) and
         currentDimension == 1
  then
    -- mines escape sequence
    return false
  else
    local illegalRedRooms = mod:getIllegalRedRooms()
    
    for gridIdx = 0, 168 do -- full grid
      mod:makeRedRoomDoors(gridIdx, illegalRedRooms)
    end
    mod:makeRedRoomDoors(0, illegalRedRooms) -- otherwise I AM ERROR rooms might not be available from this room
    
    return true
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

-- start ModConfigMenu --
function mod:setupModConfigMenu()
  for _, v in ipairs({ 'ARRATT' }) do
    ModConfigMenu.RemoveSubcategory(v, mod.Name)
  end
  ModConfigMenu.AddText('ARRATT', mod.Name, 'Choose where to enable this mod:')
  ModConfigMenu.AddSetting(
    'ARRATT',
    mod.Name,
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
  ModConfigMenu.AddSpace('ARRATT', mod.Name)
  ModConfigMenu.AddSetting(
    'ARRATT',
    mod.Name,
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
    'ARRATT',
    mod.Name,
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
      Info = { 'Yes: reload first room to fix transient issues', 'No: set this if you\'re trying to play true co-op', 'This applies to all first rooms in all levels' }
    }
  )
end
-- end ModConfigMenu --

mod:loadData()
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.onGameExit)
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.onNewLevel)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)

if ModConfigMenu then
  mod:setupModConfigMenu()
end