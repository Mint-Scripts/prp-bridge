local fw = {}

local function getCharacter()
    return LocalPlayer.state.Character
end

-- under "status:<NAME>" (see mythic-status)
local function getStatusValue(statusName, default)
    local value = LocalPlayer.state['status:' .. statusName]
    if value ~= nil then return value end
    return default
end

---@return number
function fw.getStress()
    return getStatusValue('PLAYER_STRESS', 0)
end

---@return number
function fw.getHunger()
    return getStatusValue('PLAYER_HUNGER', 100)
end

---@return number
function fw.getThirst()
    return getStatusValue('PLAYER_THIRST', 100)
end


-- Simple mapping for the default statuses, add more if needed.
local SET_STATUS_MAP <const> = {
    stress = 'PLAYER_STRESS',
    hunger = 'PLAYER_HUNGER',
    thirst = 'PLAYER_THIRST',
}

---@param statusType string
---@param value number
function fw.setStatus(statusType, value)
    local name = SET_STATUS_MAP[statusType]
    if not name then return end
    local Status = exports['mythic-base']:FetchComponent('Status')
    if not Status then return end
    -- Set:Single updates the statebag, syncs the value server-side, and refreshes the HUD
    Status.Set:Single(name, value)
end

function fw.applyBuff(buff, data) end
function fw.clearBuffs() end

---@param type 'inform' | 'error' | 'success'| 'warning'
---@param message string
---@param title? string
---@param duration? number
function fw.notify(type, message, title, duration)
    lib.notify({
        type        = type or "inform",
        title       = title or nil,
        description = message or "",
        duration    = duration or 3000,
    })
end

---@param text string
---@param options? table
function fw.showTextUI(text, options)
    lib.showTextUI(text, options)
end

function fw.hideTextUI()
    lib.hideTextUI()
end

---@return boolean, string | nil
function fw.isTextUIOpen()
    return lib.isTextUIOpen()
end

---@param payload FWProgressBar
---@return boolean?
function fw.progressBar(payload)
    local options = {
        duration      = payload.duration or 5000,
        label         = payload.label,
        useWhileDead  = false,
        allowRagdoll  = payload.allowRagdoll  or false,
        allowSwimming = payload.allowSwimming or false,
        allowCuffed   = payload.allowCuffed   or false,
        allowFalling  = payload.allowFalling  or false,
        canCancel     = payload.canCancel     or false,
        disable       = {}
    }

    if payload.controlDisables then
        if payload.controlDisables.disableMovement    then options.disable.move    = true end
        if payload.controlDisables.disableCarMovement then options.disable.car     = true end
        if payload.controlDisables.disableMouse       then options.disable.mouse   = true end
        if payload.controlDisables.disableCombat      then options.disable.combat  = true end
        if payload.controlDisables.disableSprint      then options.disable.sprint  = true end
    end

    if payload.animation then
        if payload.animation.animDict and payload.animation.animClip then
            options.anim = {
                dict  = payload.animation.animDict,
                clip  = payload.animation.animClip,
                flag  = payload.animation.animFlag or nil,
            }
        elseif payload.animation.scenario then
            options.anim = { scenario = payload.animation.scenario }
        end
    end

    return lib.progressBar(options)
end

---@param header string
---@param content string
---@param labels? table
---@param timeout? number
---@return 'cancel'|'confirm'|nil
function fw.confirmDialog(header, content, labels, timeout)
    return lib.alertDialog({
        header   = header,
        content  = content,
        centered = true,
        cancel   = true,
        labels   = labels or { cancel = locale("Cancel"), confirm = locale("Confirm") },
    }, timeout)
end

---@param heading string
---@param rows table
---@param options table?
---@return table | nil
function fw.inputDialog(heading, rows, options)
    return lib.inputDialog(heading, rows, options)
end

---@param payload table
function fw.contextMenu(payload)
    lib.registerContext(payload)
end

---@param contextId string
function fw.showContext(contextId)
    lib.showContext(contextId)
end

-- Handled server sided, this is just so it doesn't panic

---@return boolean
function fw.isOnDuty()
    local onDuty = LocalPlayer.state.onDuty
    return onDuty ~= nil and onDuty ~= false
end


---@param job string
---@param grade number?
---@param duty boolean?
---@return boolean
function fw.hasJob(job, grade, duty)
    local character = getCharacter()
    if not character then return false end

    local jobs = character:GetData('Jobs')
    if not jobs then return false end

    local foundJob = nil
    for _, jobData in ipairs(jobs) do
        if jobData.Id == job then
            foundJob = jobData
            break
        end
    end

    if not foundJob then return false end

    if grade and (not foundJob.Grade or (foundJob.Grade.Level or 0) < grade) then
        return false
    end

    -- onDuty check
    if duty and LocalPlayer.state.onDuty ~= job then
        return false
    end

    return true
end


---@return string?
function fw.getIdentifier()
    local character = getCharacter()
    if not character then return nil end
    local sid = character:GetData('SID')
    return sid ~= nil and tostring(sid) or nil
end

---@return string?
function fw.getCharacterName()
    local character = getCharacter()
    if not character then return nil end
    return ('%s %s'):format(character:GetData('First') or '', character:GetData('Last') or '')
end

---@return table?
function fw.getPlayerData()
    local character = getCharacter()
    return character and character:GetData() or nil
end

---@return table?
function fw.getJob()
    local character = getCharacter()
    return character and character:GetData('Jobs') or nil
end


if bridge.name == bridge.currentResource then
    RegisterNetEvent('Characters:Client:Spawned', function()
        TriggerEvent('prp-bridge:client:playerLoad')
    end)

    RegisterNetEvent('Characters:Client:Logout', function()
        TriggerEvent('prp-bridge:client:playerUnload')
    end)
end

return fw
