-- Reload the garage list when the player's job or gang can have changed.
local function refresh()
    if RefreshGarages then SetTimeout(1000, RefreshGarages) end
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', refresh) -- QBCore and Qbox
RegisterNetEvent('QBCore:Client:OnJobUpdate', refresh)
RegisterNetEvent('QBCore:Client:OnGangUpdate', refresh)
RegisterNetEvent('esx:playerLoaded', refresh)
RegisterNetEvent('esx:setJob', refresh)
RegisterNetEvent('asg:refresh', refresh)

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then refresh() end
end)
