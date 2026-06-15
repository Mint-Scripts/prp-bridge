local DEFAULT_GARAGE_ID <const> = "motelgarage"

local fw = {}

local Fetch, Jobs, Banking, Database, Inventory, Vehicles

AddEventHandler('Core:Shared:Ready', function()
    Fetch     = exports['mythic-base']:FetchComponent('Fetch')
    Jobs      = exports['mythic-base']:FetchComponent('Jobs')
    Banking   = exports['mythic-base']:FetchComponent('Banking')
    Database  = exports['mythic-base']:FetchComponent('Database')
    Inventory = exports['mythic-base']:FetchComponent('Inventory')
    Vehicles  = exports['mythic-base']:FetchComponent('Vehicles')
end)


local function getMythicPlayerFromSID(SID)
    local players = Fetch:All()
    for _, plr in pairs(players) do
        local char = plr:GetData('Character')
        if char and char:GetData('SID') == SID then
            return char
        end
    end
end

function fw.getIdentifier(source)
    if not Fetch then return end
    local Player = Fetch:Source(source)
    if not Player then return end
    local Character = Player:GetData('Character')
    if not Character then return end
    return tostring(Character:GetData('SID'))
end

function fw.getSrcFromIdentifier(identifier)
    local char = getMythicPlayerFromSID(tonumber(identifier))
    if not char then return end
    return char.Owner
end

function fw.getCharacterName(identifier)
    local char = getMythicPlayerFromSID(tonumber(identifier))
    if not char then return end
    return ('%s %s'):format(char:GetData('First') or '', char:GetData('Last') or '')
end

function fw.isPlayerOnline(source)
    return Fetch:Source(source) ~= nil
end

function fw.addMoney(source, type, amount)
    local player = Fetch:Source(source)
    if not player then return end
    local char = player:GetData('Character')
    if not char then return end

    if type == "cash" then
        local current = char:GetData('Cash') or 0
        char:SetData('Cash', current + amount)
    elseif type == "bank" then
        local account = Banking.Accounts:GetPersonal(char:GetData('SID'))
        if not account then return end
        Banking.Balance:Deposit(account.Account, amount, {
            type               = 'deposit',
            title              = 'Money Added',
            description        = 'Money added by State',
            transactionAccount = false,
            data               = {}
        })
    end
end

---@return boolean
function fw.removeMoney(source, moneyType, moneyAmount, reason)
    local player = Fetch:Source(tonumber(source))
    if not player then return false end
    local char = player:GetData('Character')
    if not char then return false end

    if moneyType == "cash" then
        local current = char:GetData('Cash') or 0
        if current < moneyAmount then return false end
        char:SetData('Cash', current - moneyAmount)
        return true
    elseif moneyType == "bank" then
        local account = Banking.Accounts:GetPersonal(char:GetData('SID'))
        if not account then return false end
        local result = Banking.Balance:Charge(account.Account, moneyAmount, {
            type               = 'withdraw',
            title              = reason or 'Money Removed',
            description        = reason or 'Money removed by State',
            transactionAccount = false,
            data               = {}
        })
        return result ~= false
    end

    return false
end

function fw.getMoney(source, type)
    local player = Fetch:Source(source)
    if not player then return 0 end
    local char = player:GetData('Character')
    if not char then return 0 end

    if type == "cash" then
        return char:GetData('Cash') or 0
    elseif type == "bank" then
        local account = Banking.Accounts:GetPersonal(char:GetData('SID'))
        if not account then return 0 end
        return Banking.Balance:Get(account.Account) or 0
    end

    return 0
end

function fw.notify(source, type, message, title, duration)
    TriggerClientEvent("prp-bridge:notify", source, type, message, title, duration)
end

function fw.registerCommand(commandName, helpText, params, restrictedGroup, callback)
    lib.addCommand(commandName, {
        help       = helpText,
        params     = params,
        restricted = restrictedGroup,
    }, callback)
end

---@return boolean
function fw.isAdmin(source)
    local player = Fetch:Source(source)
    if not player then return false end
    return player.Permissions:IsAdmin()
end

function fw.setMetadata(source, payload)
    local player = Fetch:Source(tonumber(source))
    if not player then return end
    local char = player:GetData('Character')
    if not char then return end

    for key, data in pairs(payload) do
        if data.type == "add" or data.type == "remove" then
            local current = char:GetData(key) or 0
            local new = data.type == "add" and (current + data.value) or (current - data.value)
            if new > 100 then new = 100 elseif new < 0 then new = 0 end
            char:SetData(key, new)
        else
            char:SetData(key, data.value)
        end
    end
end

function fw.addRep(source, rep, amount, reason) end
function fw.removeRep(source, rep, amount, reason) end

---@return boolean
function fw.hasJob(source, job, grade, duty)
    if not Jobs then return false end
    -- HasJob(source, jobId, workplaceId, gradeId, gradeLevel, checkDuty) on-duty checks internally.
    return Jobs.Permissions:HasJob(source, job, nil, nil, grade, duty) ~= false
end

function fw.getDutyCountJob(jobName)
    if not Jobs then return 0 end
    local dutyData = Jobs.Duty:GetDutyData(jobName)
    if not dutyData then return 0 end
    return dutyData.Count or #(dutyData.DutyPlayers or {})
end

function fw.getPlayersOnDuty(jobName)
    local formatted = {}
    if not Jobs then return formatted end
    local dutyData = Jobs.Duty:GetDutyData(jobName)
    if not dutyData or not dutyData.DutyPlayers then return formatted end
    for _, src in ipairs(dutyData.DutyPlayers) do
        formatted[src] = true
    end
    return formatted
end

local useableItems = {}

CreateThread(function()
    -- Just basic ox_inventory double checking.
    while GetResourceState('ox_inventory') ~= 'started' do Wait(500) end

    AddEventHandler('ox_inventory:usedItem', function(inventoryId, itemName, slot, metadata)
        local cb = useableItems[itemName]
        if not cb then return end

        local source  = tonumber(inventoryId)
        if not source then return end

        local item = exports.ox_inventory:GetSlot(source, slot)
        local data = {
            name     = itemName,
            label    = item and item.label or itemName,
            metaData = metadata,
            slot     = slot,
            count    = item and item.count or 1,
        }

        local s, e = pcall(cb, source, data)
        if not s then
            print(('[prp-bridge] Error in item use handler for %s: %s'):format(itemName, e))
        end
    end)
end)

function fw.registerItemUse(itemName, cb)
    useableItems[itemName] = cb
end

---@param plate string
---@param returnEmpty? boolean
---@return table | nil
function fw.getOwnedVehicleByPlate(plate, returnEmpty)
    local result = nil

    -- Search by RegisteredPlate in the vehicles DB
    local p = promise.new()
    Database.Game:findOne({
        collection = 'vehicles',
        query      = { RegisteredPlate = plate },
    }, function(success, doc)
        if success and doc then result = doc end
        p:resolve(true)
    end)
    Citizen.Await(p)

    if not result then
        return returnEmpty and {
            label = locale and locale("UNKNOWN") or "Unknown",
            class = "OPEN",
            plate = plate,
        } or nil
    end

    local vehicleModel = result.Model
    if not BridgeConfig or not BridgeConfig.VehicleData or not BridgeConfig.VehicleData[joaat(vehicleModel)] then
        return nil
    end

    local vehData = lib.table.deepclone(BridgeConfig.VehicleData[joaat(vehicleModel)])
    return lib.table.merge(vehData, result, false)
end

---@param identifier number  SID of the character
---@param classes? string | table<string>
---@return table | nil
function fw.getAllOwnedVehicles(identifier, classes)
    if not Vehicles then return nil end

    local p = promise.new()
    Vehicles:GetAll(nil, 0, tonumber(identifier), function(result)
        p:resolve(result)
    end)
    local vehicles = Citizen.Await(p)

    if not vehicles then return nil end

    if not classes then return vehicles end

    local filtered = {}
    for _, vehicle in ipairs(vehicles) do
        local vehData = BridgeConfig and BridgeConfig.VehicleData and BridgeConfig.VehicleData[joaat(vehicle.Model)]
        if vehData and vehData.class and (
            type(classes) == "table" and lib.table.contains(classes, vehData.class)
            or vehData.class == classes
        ) then
            local newData = lib.table.deepclone(vehData)
            filtered[#filtered + 1] = lib.table.merge(newData, vehicle, false)
        end
    end

    return filtered
end

---@param source number | string
---@param vehicleName string
---@return integer?, string?
function fw.addOwnedVehicle(source, vehicleName)
    if not Vehicles then return nil, "VEHICLE_SYSTEM_UNAVAILABLE" end

    local stateId = fw.getIdentifier(source)
    if not stateId then return nil, "CHARACTER_NOT_LOGGED_IN" end

    -- Little Janky but it works!
    local p = promise.new()
    Vehicles:AddToCharacter(
        tonumber(stateId),
        GetHashKey(vehicleName),
        0,
        {
            make  = vehicleName,
            model = vehicleName,
            class = 'Unknown',
            value = 0,
        },
        function(success, vehicleData)
            if success and vehicleData then
                p:resolve(vehicleData.VIN)
            else
                p:resolve(nil)
            end
        end,
        nil,
        { Type = 1, Id = DEFAULT_GARAGE_ID }
    )

    local insertVIN = Citizen.Await(p)
    if not insertVIN then
        return nil, "VEHICLE_ADD_FAILED"
    end

    return insertVIN
end

---@param plate string
---@param identifier number  new owner SID
---@return boolean, string?
function fw.updateVehicleOwner(plate, identifier)
    local vehicle = fw.getOwnedVehicleByPlate(plate)
    if not vehicle then return false, "VEHICLE_NOT_FOUND" end

    Database.Game:updateOne({
        collection = 'vehicles',
        query      = { RegisteredPlate = plate },
        update     = { ['$set'] = { ['Owner.Id'] = tonumber(identifier) } }
    }, function() end)

    return true
end

function fw.updateDisconnectLocation(identifier, coords)
    local sid = tonumber(identifier)
    local player = Fetch:SID(sid)
    if player then
        local char = player:GetData('Character')
        if char then
            char:SetData('position', coords)
            return
        end
    end

    Database.Game:updateOne({
        collection = 'characters',
        query      = { SID = sid },
        update     = { ['$set'] = { position = coords } }
    })
end

function fw.isExplosionAllowed(explosionType) return true end
function fw.allowExplosion(explosionType, time) end

if bridge.name == bridge.currentResource then
    AddEventHandler('Core:Shared:Ready', function()
        local Middleware = exports['mythic-base']:FetchComponent('Middleware')

        Middleware:Add('Characters:CharacterSelected', function(source)
            TriggerEvent('prp-bridge:server:playerLoad', source)
        end)

        Middleware:Add('Characters:Logout', function(source)
            TriggerEvent('prp-bridge:server:playerUnload', source)
        end)

        Middleware:Add('playerDropped', function(source)
            TriggerEvent('prp-bridge:server:playerUnload', source)
        end)
    end)
end

return fw
