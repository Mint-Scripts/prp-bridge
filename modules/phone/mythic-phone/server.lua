local phone = {}

local Fetch, Phone, Database
local function FetchComponents()
    if Fetch and Phone and Database then
        return Fetch, Phone, Database
    end
    Fetch    = exports['mythic-base']:FetchComponent('Fetch')
    Phone    = exports['mythic-base']:FetchComponent('Phone')
    Database = exports['mythic-base']:FetchComponent('Database')
    return Fetch, Phone, Database
end

---@param src number
---@return string | number | nil
local function getPhoneNumber(src)
    -- Get phone number from their SID
    local fetch = FetchComponents()
    if not fetch then return nil end

    local player = fetch:Source(src)
    if not player then return nil end

    local char = player:GetData('Character')
    if not char then return nil end

    return char:GetData('Phone')
end

---@param src number
---@param from number
---@param message string
---@return boolean
function phone.sendMessage(src, from, message)
    local _, _, Database = FetchComponents()
    if not Database then return false end

    local number = getPhoneNumber(src)
    if not number then return false end

    -- The player's copy of the conversation. 'number' is the other server sending it
    local doc = {
        owner   = number,
        number  = tostring(from),
        message = message,
        time    = os.time() * 1000,
        method  = 0,
        unread  = true,
    }

    Database.Game:insertOne({
        collection = 'phone_messages',
        document   = doc,
    }, function(success)
        if success then
            -- Push it live so it shows instantly and plays the tone
            TriggerClientEvent('Phone:Client:Messages:Notify', src, doc, false)
        end
    end)

    return true
end

---@param src number
---@param from number
---@param coords vector3
---@return boolean
function phone.sendCoords(src, from, coords)
    local label = ('Shared Location: %.0f, %.0f'):format(coords.x, coords.y)
    return phone.sendMessage(src, from, label)
end

---@param src number
---@param title string
---@param content? string
function phone.sendNotification(src, title, content)
    local _, phoneComponent = components()
    if not phoneComponent then return end

    phoneComponent.Notification:Add(src, title, content or '', os.time() * 1000, 5000, 'messages')
end

return phone
