local string_lower = string.lower
local pairs = pairs

local w2l
local force_slk

local function add_obj(type, name, level_key, obj)
    local new_obj = {}
    for key, value in pairs(obj) do
        new_obj[string_lower(key)] = value
    end
    new_obj._id = name
    new_obj._max_level = obj[level_key]
    new_obj._type = type
    new_obj._obj = true
    if not w2l:is_usable_para(new_obj._parent) then
        force_slk = true
    end
    return new_obj
end

return function (w2l_, type, buf)
    w2l = w2l_
    local lni = w2l:parse_lni(buf)
    local level_key = w2l.info.key.max_level[type]
    local data = {}
    force_slk = false
    for name, obj in pairs(lni) do
        data[name] = add_obj(type, name, level_key, obj)
    end
    return data, force_slk
end
