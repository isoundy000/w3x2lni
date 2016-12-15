local lpeg = require 'lpeg'
local w3xparser = require 'w3xparser'

local tonumber = tonumber
local wtonumber = w3xparser.tonumber
local ids
local line_count
local min = ('>I4'):unpack 'A000'

local function add_id(id)
    if #id ~= 4 then
        return
    end
    if id:find '%W' then
        return
    end
    ids[id] = true
end

local function fint1(str)
    local int = wtonumber(str)
    if int < min then
        return
    end
    add_id(('>I4'):pack(int))
end

local function fint3(str)
    fint1('0x'..str:sub(2))
end

local function fint4(str)
    add_id(str)
end

lpeg.locale(lpeg)
local S = lpeg.S
local P = lpeg.P
local R = lpeg.R

local nl1  = P'\r\n' + S'\r\n'
local com  = P'//' * (1-nl1)^0
local sp   = (S' \t' + P'\xEF\xBB\xBF' + com)^0
local sps  = (S' \t' + P'\xEF\xBB\xBF' + com)^1
local nl   = com^0 * nl1 / function() line_count = line_count + 1 end
local ign  = sps + nl
local quo  = P'"'
local iquo = P"'"
local esc  = P'\\'
local int1 = (P'-' * sp)^-1 * (P'0' + R'19' * R'09'^0) / fint1
local int2 = P'0' * S'xX' * R('af', 'AF', '09')^1 / fint1
local int3 = P'$' * R('af', 'AF', '09')^1 / fint3
local int_ = esc * P(1) + (1-iquo)
local int4 = iquo * int_^1^-4 * iquo / fint4
local int  = int4 + int3 + int2 + int1
local real = (P'-' * sp)^-1 * (P'.' * R'09'^1 + R'09'^1 * P'.' * R'09'^0)
local str1 = esc * P(1) + (1-quo)
local str  = quo * (nl + str1)^0 * quo
local id   = R('az', 'AZ') * R('az', 'AZ', '09', '__')^0

local function err(str)
    return ((1-nl)^1 + P(1)) / function(c) error(('line[%d]: %s:\n===========================\n%s\n==========================='):format(line_count, str, c)) end
end

local word = sp * (real + int + str + id) * sp
local pjass = (ign + word + S'=+-*/><!()[],' + err'语法不正确')^0

return function (w2l, jass)
    ids = {}
    line_count = 0
    pjass:match(jass)
    return ids
end