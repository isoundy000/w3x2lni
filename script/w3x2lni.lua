require 'utility'
local uni = require 'ffi.unicode'
local w3xparser = require 'w3xparser'
local lni = require 'lni-c'
local slk = w3xparser.slk
local txt = w3xparser.txt
local ini = w3xparser.ini
local pairs = pairs
local string_lower = string.lower

local mt = {}

local metadata
local keydata
local editstring
local default
local miscnames
local wts

function mt:parse_lni(...)
    return lni(...)
end

function mt:parse_slk(buf)
    return slk(buf)
end

function mt:parse_txt(...)
    return txt(...)
end

function mt:parse_ini(buf)
    return ini(buf)
end

function mt:metadata()
    if not metadata then
        metadata = lni(io.load(self.defined / 'metadata.ini'))
    end
    return metadata
end

function mt:keydata()
    if not keydata then
        keydata = lni(io.load(self.defined / 'keydata.ini'))
    end
    return keydata
end

function mt:miscnames()
    if not miscnames then
        miscnames = lni(io.load(self.defined / 'miscnames.ini'))
    end
    return miscnames
end

function mt:editstring(str)
    -- TODO: WESTRING不区分大小写，不过我们把WorldEditStrings.txt改了，暂时不会出现问题
    if not editstring then
        editstring = ini(io.load(self.mpq / 'ui' / 'WorldEditStrings.txt'))['WorldEditStrings']
    end
    if not editstring[str] then
        return str
    end
    repeat
        str = editstring[str]
    until not editstring[str]
    return str:gsub('%c+', '')
end

local function create_default(w2l)
    return {
        ability      = lni(io.load(w2l.default / 'ability.ini')),
        buff         = lni(io.load(w2l.default / 'buff.ini')),
        unit         = lni(io.load(w2l.default / 'unit.ini')),
        item         = lni(io.load(w2l.default / 'item.ini')),
        upgrade      = lni(io.load(w2l.default / 'upgrade.ini')),
        doodad       = lni(io.load(w2l.default / 'doodad.ini')),
        destructable = lni(io.load(w2l.default / 'destructable.ini')),
        txt          = lni(io.load(w2l.default / 'txt.ini')),
        misc         = lni(io.load(w2l.default / 'misc.ini')),
    }
end

function mt:get_default(create)
    if create then
        return create_default(self)
    end
    if not default then
        default = create_default(self)
    end
    return default
end

-- 同时有英文逗号和英文双引号的字符串存在txt里会解析出错
-- 包含右大括号的字符串存在wts里会解析出错
-- 超过256字节的字符串存在二进制里会崩溃
function mt:load_wts(wts, content, max, reason)
    return content:gsub('TRIGSTR_(%d+)', function(i)
        local str_data = wts[i]
        if not str_data then
            message('-report|9其他', '没有找到字符串定义:', ('TRIGSTR_%03d'):format(i))
            return
        end
        local text = str_data.text
        if max and #text > max then
            str_data.mark = true
            message('-report|7保存到wts中的文本', reason)
            message('-tip', '文本保存在wts中会导致加载速度变慢: ', (text:sub(1, 1000):gsub('\r\n', ' ')))
            return
        end
        return text
    end)
end

function mt:save_wts(wts, value, reason)
    message('-report|7保存到wts中的文本', reason)
    message('-tip', '文本保存在wts中会导致加载速度变慢: ', (value:sub(1, 1000):gsub('\r\n', ' ')))
    for i = 1, 999999 do
        local index = ('%03d'):format(i)
        if not wts[index] then
            if value:find('}', 1, false) then
                message('-report|2警告', '文本中的"}"被修改为了"|"')
                message('-tip', (value:sub(1, 1000):gsub('\r\n', ' ')))
                value = value:gsub('}', '|')
            end
            wts[index] = {
                index  = i,
                text   = value,
                mark   = true,
            }
            wts[#wts+1] = wts[index]
            return 'TRIGSTR_' .. i
        end
    end
    message('-report|2警告', '保存在wts里的字符串太多了')
    message('-tip', '字符串被丢弃了:' .. (value:sub(1, 1000):gsub('\r\n', ' ')))
end

function mt:refresh_wts(wts)
    local lines    = {}
    for i, t in ipairs(wts) do
        if t and t.mark then
            lines[#lines+1] = ('STRING %d\r\n{\r\n%s\r\n}'):format(t.index, t.text)
        end
    end

    return table.concat(lines, '\r\n\r\n')
end

function mt:initialize(root)
    if self.initialized then
        return
    end
    self.initialized = true
    self.root = root or fs.path(uni.a2u(arg[0])):remove_filename()
    self.template = self.root / 'template'
    self.mpq = self.root / 'script' / 'mpq'
    self.prebuilt = self.root / 'script' / 'prebuilt'
    self.default = self.prebuilt / 'default'
    self.defined = self.prebuilt / 'defined'
    self.info   = lni(assert(io.load(self.root / 'script' / 'info.ini')), 'info')
    self.config = lni(assert(io.load(self.root / 'config.ini')), 'config')
    local fmt = self.config.target_format
    self.config = self.config[fmt]
    self.config.target_format = fmt
end

-- 加载脚本
local convertors = {
    'frontend', 
    'frontend_wts',
    'frontend_slk', 
    'frontend_lni', 
    'frontend_obj',
    'frontend_misc',
    'frontend_updateobj',
    'frontend_updatelni',
    'frontend_merge',
    'backend',
    'backend_mark',
    'backend_lni',
    'backend_slk',
    'backend_txt',
    'backend_obj',
    'backend_searchjass',
    'backend_convertjass',
    'backend_searchdoo',
    'backend_computed',
    'backend_extra_txt',
    'backend_txtlni',
    'backend_misc',
    'backend_skin',
    'backend_searchparent',
    'backend_cleanobj',
}

for _, name in ipairs(convertors) do
    mt[name] = require('slk.' .. name)
end

local convertors = {
    'lni2w3i', 'read_w3i', 'w3i2lni',
    'create_unitsdoo',
}

for _, name in ipairs(convertors) do
    mt[name] = require('other.' .. name)
end

return mt
