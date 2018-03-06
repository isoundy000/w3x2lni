(function()
    local exepath = package.cpath:sub(1, (package.cpath:find(';') or 0)-6)
    package.path = package.path .. ';' .. exepath .. '..\\script\\?.lua;' .. exepath .. '..\\script\\?\\init.lua;' .. exepath .. '..\\script\\core\\?.lua;' .. exepath .. '..\\script\\core\\?\\init.lua'
end)()

require 'filesystem'
require 'utility'
local uni = require 'ffi.unicode'
local sleep = require 'ffi.sleep'
local w3x2lni = require 'w3x2lni'
local archive = require 'archive'
local save_map = require 'save_map'
local ui = require 'ui-builder'
local w2l = w3x2lni()

local std_print = print
function print(...)
    if select(1, ...) == '-progress' then
        return
    end
    local tbl = {...}
    local count = select('#', ...)
    for i = 1, count do
        tbl[i] = uni.u2a(tostring(tbl[i])):gsub('[\r\n]', ' ')
    end
    std_print(table.concat(tbl, ' '))
end

local function task(f, ...)
    for i = 1, 99 do
        if pcall(f, ...) then
            return
        end
        sleep(10)
    end
    f(...)
end

if arg[3] == 'ansi' then
	arg[1] = uni.a2u(arg[1])
end
local map_path = fs.path(arg[1])
local ydwe_path = fs.path(arg[2])
local mpq_path = ydwe_path / 'share' / 'ui'
local map_name = map_path:stem():string()

local function string_trim (self) 
	return self:gsub("^%s*(.-)%s*$", "%1")
end

local loader = {}

function loader:config()
	self.list = {}
	local f, err = io.open((mpq_path / 'config'):string(), 'r')
	if not f then
		error('Open ' .. (mpq_path / 'config'):string() .. ' failed.')
		return false
    end
    local global_config = w2l:parse_lni(io.load(ydwe_path / "bin" / "EverConfig.cfg"))
	local enable_ydtrigger = true
	local enable_japi = true
	for line in f:lines() do
		if not enable_ydtrigger and (string_trim(line) == 'ydtrigger') then
			-- do nothing
		elseif not enable_japi and (string_trim(line) == 'japi') then
			-- do nothing
		elseif string_trim(line) == map_name then
			-- do nothing
		else
			table.insert(self.list, mpq_path / string_trim(line))
		end
	end
	f:close()
	return true
end

function loader:triggerdata()
	if #self.list == 0 then
		return nil
	end
	local t = nil
	for _, path in ipairs(self.list) do
		if fs.exists(path / 'ui') then
			t = ui.merge(t, ui.old_reader(function(filename)
				return io.load(path / 'ui' / filename)
			end))
		else
			t = ui.merge(t, ui.new_reader(function(filename)
				return io.load(path / filename)
			end))
		end
	end
	return t
end

local function new_config()
	local lines = {}
	local f = io.open((mpq_path / 'config'):string(), 'r')
	if not f then
		return nil
	end
	for line in f:lines() do
		if string_trim(line) == map_name then
			return nil
		end
		table.insert(lines, line)
	end
	table.insert(lines, map_name)
	return table.concat(lines, '\n')
end

--w2l:set_messager(print)
loader:config()
local state = loader:triggerdata()

local clock = os.clock()
local map = archive(map_path)
local wtg = map:get 'war3map.wtg'
if not wtg or not state then
    return false
end
local wct = map:get 'war3map.wct'
print('打开地图用时：', os.clock() - clock)

local clock = os.clock()
local suc = w2l:wtg_checker(wtg, state)
print('检查wtg结果：', suc, '用时：', os.clock() - clock)

local clock = os.clock()
local wtg_data, fix = w2l:wtg_reader(wtg, state)
print('修复wtg用时：', os.clock() - clock)

ui.merge(state, fix)
local bufs = {ui.new_writer(fix)}
fs.create_directories(map_path:parent_path() / map_name)
io.save(map_path:parent_path() / map_name / 'define.txt',    bufs[1])
io.save(map_path:parent_path() / map_name / 'event.txt',     bufs[2])
io.save(map_path:parent_path() / map_name / 'condition.txt', bufs[3])
io.save(map_path:parent_path() / map_name / 'action.txt',    bufs[4])
io.save(map_path:parent_path() / map_name / 'call.txt',      bufs[5])

local config = new_config()
if config then
	io.save(map_path:parent_path() / 'config', config)
end

print('成功，修复wtg总用时：', os.clock() - clock)

local clock = os.clock()
local wtg_data = w2l:frontend_wtg(wtg, state)
print('读取wtg用时：', os.clock() - clock)

local clock = os.clock()
local wct_data = w2l:frontend_wct(wct)
print('读取wct用时：', os.clock() - clock)

local clock = os.clock()
local files = w2l:backend_lml(wtg_data, wct_data)
print('转换wtg用时：', os.clock() - clock)
local dir = map_path:parent_path() / '触发器'

local err_files = {}

local function test_wtg(wtg, wct)
	local new_files = w2l:backend_lml(w2l:frontend_wtg(wtg, state), w2l:frontend_wct(wct))
	for name, buf in pairs(files) do
		if buf ~= new_files[name] then
			print('测试-文件转换后出现差异：', name)
			err_files[name..'.diff'] = new_files[name]
		end
	end
end

local function eq(t1, t2)
	local mark = {}
	for k, v in pairs(t1) do
		mark[k] = true
		if type(v) == 'table' then
			if type(t2[k]) ~= 'table' or not eq(v, t2[k]) then
				return false
			end
		elseif v ~= t2[k] then
			return false
		end
	end
	for k in pairs(t2) do
		if not mark[k] then
			return false
		end
	end
	return true
end

local clock = os.clock()
test_wtg(w2l:backend_wtg(wtg_data, state), w2l:backend_wct(wct_data))
print('测试1用时：', os.clock() - clock)

local clock = os.clock()
local new_wtg_data, new_wct_data = w2l:frontend_lml(function (filename)
	return files[filename]
end)
if not eq(wtg_data, new_wtg_data) then
	print('测试-文件转换后语法树出现差异：wtg')
end
if not eq(wct_data, new_wct_data) then
	print('测试-文件转换后语法树出现差异：wct')
end
test_wtg(w2l:backend_wtg(new_wtg_data, state), w2l:backend_wct(new_wct_data))
print('测试2用时：', os.clock() - clock)


local clock = os.clock()
task(fs.remove_all, dir)
print('清空目录用时：', os.clock() - clock)

for name, buf in pairs(err_files) do
	files[name] = buf
end

local clock = os.clock()
task(fs.create_directories, dir)
for filename, buf in pairs(files) do
	fs.create_directories((dir / filename):parent_path())
	io.save(dir / filename, buf)
end
print('创建文件用时：', os.clock() - clock)
