local mod = RegisterMod('All Red Rooms All The Time', 1)
local json = require('json')
local game = Game()

mod.playerPosition = nil
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

function mod:onGameExit()
  mod:SaveData(json.encode(mod.state))
end

function mod:onNewLevel()
  if mod:isDisabled() then
    return
  end
  
  local shouldReloadFirstRoom = mod:makeAllRedRoomDoors()
  mod:makeRedRoomsVisible()
  if shouldReloadFirstRoom then
    mod:reloadFirstRoom()
  end
  mod:closeErrorDoors()
end

function mod:onNewRoom()
  if mod:isDisabled() then
    return
  end
  
  local currentDimension = mod:getCurrentDimension()
  
  if mod.playerPosition then
    for i = 0, game:GetNumPlayers() - 1 do
      local player = game:GetPlayer(i)
      player.Position = Vector(mod.playerPosition.X, mod.playerPosition.Y)
    end
    mod.playerPosition = nil
  elseif (currentDimension == 1 or currentDimension == 2) and mod:isNewDimension() then
    local shouldReloadFirstRoom = mod:makeAllRedRoomDoors()
    mod:makeRedRoomsVisible() -- sometimes red rooms won't be visible even if you have mapping, this generally happens when you switch dimensions
    if shouldReloadFirstRoom then
      mod:reloadFirstRoom()
    end
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
    
    local player = game:GetPlayer(0)
    mod.playerPosition = Vector(player.Position.X, player.Position.Y)
    
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
    local illegalDoorSlots = mod:getIllegalDoorSlots()
    
    for gridIdx = 0, 168 do -- full grid
      mod:makeRedRoomDoors(gridIdx, illegalDoorSlots)
    end
    mod:makeRedRoomDoors(0, illegalDoorSlots) -- otherwise I AM ERROR rooms might not be available from this room
    
    return true
  end
end

function mod:makeRedRoomDoors(gridIdx, illegalDoorSlots)
  local level = game:GetLevel()
  local roomDesc = level:GetRoomByIdx(gridIdx, -1)
  local safeGridIdx
  local shape
  
  if roomDesc.GridIndex >= 0 then
    gridIdx = roomDesc.GridIndex
    safeGridIdx = roomDesc.SafeGridIndex
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
    if not mod:isIllegalDoorSlot(gridIdx, doorSlot, illegalDoorSlots) then
      level:MakeRedRoomDoor(safeGridIdx, doorSlot)
    end
  end
end

function mod:isIllegalDoorSlot(gridIdx, doorSlot, illegalDoorSlots)
  for _, illegal in ipairs(illegalDoorSlots) do
    if illegal.gridIdx == gridIdx and illegal.doorSlot == doorSlot then
      return true
    end
  end
  
  return false
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
  
  -- there's also STATE_FULL_MAP_EFFECT
  local hasCompass = level:GetStateFlag(LevelStateFlag.STATE_COMPASS_EFFECT)
  local hasMap = level:GetStateFlag(LevelStateFlag.STATE_MAP_EFFECT)
  local hasBlueMap = level:GetStateFlag(LevelStateFlag.STATE_BLUE_MAP_EFFECT)
  
  for i = 0, #rooms - 1 do
    local room = rooms:Get(i)
    
    if room.SafeGridIndex >= 0 and currentDimension == mod:getDimension(room) and mod:isRedRoom(room) and room.DisplayFlags == 0 then
      local roomType = room.Data.Type
      local roomDesc = level:GetRoomByIdx(room.SafeGridIndex, -1) -- writeable
      
      if hasMap and hasCompass then
        if roomType ~= RoomType.ROOM_SECRET and
           roomType ~= RoomType.ROOM_SUPERSECRET and
           roomType ~= RoomType.ROOM_ULTRASECRET
        then
          roomDesc.DisplayFlags = visible | icon
        end
      elseif hasMap then
        if roomType ~= RoomType.ROOM_SECRET and
           roomType ~= RoomType.ROOM_SUPERSECRET and
           roomType ~= RoomType.ROOM_ULTRASECRET
        then
          roomDesc.DisplayFlags = visible
        end
      elseif hasCompass then
        if roomType == RoomType.ROOM_ANGEL or
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
          roomDesc.DisplayFlags = visible | icon
        end
      end
      
      if hasBlueMap then
        if roomType == RoomType.ROOM_SECRET or
           roomType == RoomType.ROOM_SUPERSECRET
        then
          roomDesc.DisplayFlags = icon
        end
      end
      
      level:UpdateVisibility()
    end
  end
end

-- for whatever reason the game will create bad red room doors at the mirror & secret entrances, which breaks them
-- also filter boss rooms so we don't remove any slots that might be needed for angel/devil rooms
function mod:getIllegalDoorSlots()
  local level = game:GetLevel()
  local rooms = level:GetRooms()
  local stage = level:GetStage()
  local stageType = level:GetStageType()
  local currentDimension = mod:getCurrentDimension()
  
  local illegal = {}
  
  for i = 0, #rooms - 1 do
    local room = rooms:Get(i)
    local roomType = room.Data.Type
    local roomShape = room.Data.Shape
    local roomDimension = mod:getDimension(room)
    
    if room.GridIndex >= 0 and currentDimension == roomDimension then
      if (stage == LevelStage.STAGE1_2 or (mod:isCurseOfTheLabyrinth() and stage == LevelStage.STAGE1_1)) and (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B) and
         (roomDimension == 0 or roomDimension == 1) and room.Data.Name == 'Mirror Room'
      then
        if room.Data.Variant == 10000 then -- mirror on right
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.RIGHT0 })
          if not mod:isAgainstRightEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex + 1, doorSlot = DoorSlot.LEFT0 })
          end
        elseif room.Data.Variant == 10001 then -- mirror on left
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.LEFT0 })
          if not mod:isAgainstLeftEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex - 1, doorSlot = DoorSlot.RIGHT0 })
          end
        end
      elseif (stage == LevelStage.STAGE2_2 or (mod:isCurseOfTheLabyrinth() and stage == LevelStage.STAGE2_1)) and (stageType == StageType.STAGETYPE_REPENTANCE or stageType == StageType.STAGETYPE_REPENTANCE_B) and
             roomDimension == 0 and room.Data.Name == 'Secret Entrance'
      then
        table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.UP0 }) -- mines entrance is up
        if not mod:isAgainstTopEdge(room.GridIndex) then
          table.insert(illegal, { gridIdx = room.GridIndex - 13, doorSlot = DoorSlot.DOWN0 })
        end
      elseif roomType == RoomType.ROOM_BOSS and stage ~= LevelStage.STAGE7 and roomDimension == 0 then -- don't need to filter boss rooms in the void or mirror dimension
        if roomShape == RoomShape.ROOMSHAPE_1x1 or roomShape == RoomShape.ROOMSHAPE_IH or roomShape == RoomShape.ROOMSHAPE_IV then
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.LEFT0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.UP0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.RIGHT0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.DOWN0 })
          if not mod:isAgainstLeftEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex - 1, doorSlot = DoorSlot.RIGHT0 })
          end
          if not mod:isAgainstTopEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex - 13, doorSlot = DoorSlot.DOWN0 })
          end
          if not mod:isAgainstRightEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex + 1, doorSlot = DoorSlot.LEFT0 })
          end
          if not mod:isAgainstBottomEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex + 13, doorSlot = DoorSlot.UP0 })
          end
        elseif roomShape == RoomShape.ROOMSHAPE_1x2 then
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.LEFT0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.UP0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.RIGHT0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.DOWN0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.LEFT1 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.RIGHT1 })
          if not mod:isAgainstLeftEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex - 1, doorSlot = DoorSlot.RIGHT0 })
            table.insert(illegal, { gridIdx = room.GridIndex + 13 - 1, doorSlot = DoorSlot.RIGHT0 })
          end
          if not mod:isAgainstTopEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex - 13, doorSlot = DoorSlot.DOWN0 })
          end
          if not mod:isAgainstRightEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex + 1, doorSlot = DoorSlot.LEFT0 })
            table.insert(illegal, { gridIdx = room.GridIndex + 13 + 1, doorSlot = DoorSlot.LEFT0 })
          end
          if not mod:isAgainstBottomEdge(room.GridIndex + 13) then
            table.insert(illegal, { gridIdx = room.GridIndex + 13 + 13, doorSlot = DoorSlot.UP0 })
          end
        elseif roomShape == RoomShape.ROOMSHAPE_2x1 then
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.LEFT0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.UP0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.RIGHT0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.DOWN0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.UP1 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.DOWN1 })
          if not mod:isAgainstLeftEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex - 1, doorSlot = DoorSlot.RIGHT0 })
          end
          if not mod:isAgainstTopEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex - 13, doorSlot = DoorSlot.DOWN0 })
            table.insert(illegal, { gridIdx = room.GridIndex - 13 + 1, doorSlot = DoorSlot.DOWN0 })
          end
          if not mod:isAgainstRightEdge(room.GridIndex + 1) then
            table.insert(illegal, { gridIdx = room.GridIndex + 1 + 1, doorSlot = DoorSlot.LEFT0 })
          end
          if not mod:isAgainstBottomEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex + 13, doorSlot = DoorSlot.UP0 })
            table.insert(illegal, { gridIdx = room.GridIndex + 13 + 1, doorSlot = DoorSlot.UP0 })
          end
        elseif roomShape == RoomShape.ROOMSHAPE_2x2 then
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.LEFT0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.UP0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.RIGHT0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.DOWN0 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.LEFT1 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.UP1 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.RIGHT1 })
          table.insert(illegal, { gridIdx = room.GridIndex, doorSlot = DoorSlot.DOWN1 })
          if not mod:isAgainstLeftEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex - 1, doorSlot = DoorSlot.RIGHT0 })
            table.insert(illegal, { gridIdx = room.GridIndex + 13 - 1, doorSlot = DoorSlot.RIGHT0 })
          end
          if not mod:isAgainstTopEdge(room.GridIndex) then
            table.insert(illegal, { gridIdx = room.GridIndex - 13, doorSlot = DoorSlot.DOWN0 })
            table.insert(illegal, { gridIdx = room.GridIndex - 13 + 1, doorSlot = DoorSlot.DOWN0 })
          end
          if not mod:isAgainstRightEdge(room.GridIndex + 1) then
            table.insert(illegal, { gridIdx = room.GridIndex + 1 + 1, doorSlot = DoorSlot.LEFT0 })
            table.insert(illegal, { gridIdx = room.GridIndex + 13 + 1 + 1, doorSlot = DoorSlot.LEFT0 })
          end
          if not mod:isAgainstBottomEdge(room.GridIndex + 13) then
            table.insert(illegal, { gridIdx = room.GridIndex + 13 + 13, doorSlot = DoorSlot.UP0 })
            table.insert(illegal, { gridIdx = room.GridIndex + 13 + 13 + 1, doorSlot = DoorSlot.UP0 })
          end
        end
      end
    end
  end
  
  return illegal
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

-- start ModConfigMenu --
function mod:setupModConfigMenu()
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
      end,
      Info = { 'Yes: reload first room to fix transient issues', 'No: set this if you\'re trying to play true co-op' }
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