function L(key, ...)
    local lang = Locales[Config.Locale] or Locales.en
    local str = lang[key] or Locales.en[key] or key
    if select('#', ...) > 0 then return str:format(...) end
    return str
end

-- Trim and upper-case so ESX's padded plates and QB's plates compare equal.
function NormPlate(plate)
    return (tostring(plate or ''):gsub('^%s+', ''):gsub('%s+$', '')):upper()
end

function Debug(...)
    if Config.Debug then print('[as-garages]', ...) end
end
