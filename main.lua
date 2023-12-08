local start = tick()
local client = game:GetService('Players').LocalPlayer;
local set_identity = (type(syn) == 'table' and syn.set_thread_identity) or setidentity or setthreadcontext
local executor = identifyexecutor and identifyexecutor() or 'Unknown'

local function fail(r) return client:Kick(r) end

-- gracefully handle errors when loading external scripts
-- added a cache to make hot reloading a bit faster
local usedCache = shared.__urlcache and next(shared.__urlcache) ~= nil

shared.__urlcache = shared.__urlcache or {}
local function urlLoad(url)
    local success, result

    if shared.__urlcache[url] then
        success, result = true, shared.__urlcache[url]
    else
        success, result = pcall(game.HttpGet, game, url)
    end

    if (not success) then
        return fail(string.format('Failed to GET url %q for reason: %q', url, tostring(result)))
    end

    local fn, err = loadstring(result)
    if (type(fn) ~= 'function') then
        return fail(string.format('Failed to loadstring url %q for reason: %q', url, tostring(err)))
    end

    local results = { pcall(fn) }
    if (not results[1]) then
        return fail(string.format('Failed to initialize url %q for reason: %q', url, tostring(results[2])))
    end

    shared.__urlcache[url] = result
    return unpack(results, 2)
end

-- attempt to block imcompatible exploits
-- rewrote because old checks literally did not work
if type(set_identity) ~= 'function' then return fail('Unsupported exploit (missing "set_thread_identity")') end
if type(getconnections) ~= 'function' then return fail('Unsupported exploit (missing "getconnections")') end
if type(getloadedmodules) ~= 'function' then return fail('Unsupported exploit (misssing "getloadedmodules")') end
if type(getgc) ~= 'function' then   return fail('Unsupported exploit (misssing "getgc")') end

local getinfo = debug.getinfo or getinfo;
local getupvalue = debug.getupvalue or getupvalue;
local getupvalues = debug.getupvalues or getupvalues;
local setupvalue = debug.setupvalue or setupvalue;

if type(setupvalue) ~= 'function' then return fail('Unsupported exploit (misssing "debug.setupvalue")') end
if type(getupvalue) ~= 'function' then return fail('Unsupported exploit (misssing "debug.getupvalue")') end
if type(getupvalues) ~= 'function' then return fail('Unsupported exploit (missing "debug.getupvalues")') end

-- free exploit bandaid fix
if type(getinfo) ~= 'function' then
    local debug_info = debug.info;
    if type(debug_info) ~= 'function' then
        -- if your exploit doesnt have getrenv you have no hope
        if type(getrenv) ~= 'function' then return fail('Unsupported exploit (missing "getrenv")') end
        debug_info = getrenv().debug.info
    end
    getinfo = function(f)
        assert(type(f) == 'function', string.format('Invalid argument #1 to debug.getinfo (expected %s got %s', 'function', type(f)))
        local results = { debug.info(f, 'slnfa') }
        local _, upvalues = pcall(getupvalues, f)
        if type(upvalues) ~= 'table' then
            upvalues = {}
        end
        local nups = 0
        for k in next, upvalues do
            nups = nups + 1
        end
        -- winning code
        return {
            source      = '@' .. results[1],
            short_src   = results[1],
            what        = results[1] == '[C]' and 'C' or 'Lua',
            currentline = results[2],
            name        = results[3],
            func        = results[4],
            numparams   = results[5],
            is_vararg   = results[6], -- 'a' argument returns 2 values :)
            nups        = nups,     
        }
    end
end

local UI = urlLoad("https://raw.githubusercontent.com/wally-rblx/LinoriaLib/main/Library.lua")
local metadata = urlLoad("https://raw.githubusercontent.com/wally-rblx/funky-friday-autoplay/main/metadata.lua")
local httpService = game:GetService('HttpService')

local framework, scrollHandler, network
local counter = 0

while true do
    for _, obj in next, getgc(true) do
        if type(obj) == 'table' then 
            if rawget(obj, 'GameUI') then
                framework = obj;
            elseif type(rawget(obj, 'Server')) == 'table' then
                network = obj;     
            end
        end

        if network and framework then break end
    end

    for _, module in next, getloadedmodules() do
        if module.Name == 'ScrollHandler' then
            scrollHandler = module;
            break;
        end
    end 

    if (type(framework) == 'table' and typeof(scrollHandler) == 'Instance' and type(network) == 'table') then
        break
    end

    counter = counter + 1
    if counter > 6 then
        fail(string.format('Failed to load game dependencies. Details: %s, %s, %s', type(framework), typeof(scrollHandler), type(network)))
    end
    wait(1)
end

local runService = game:GetService('RunService')
local userInputService = game:GetService('UserInputService')
local virtualInputManager = game:GetService('VirtualInputManager')

local random = Random.new()

local task = task or getrenv().task;
local fastWait, fastSpawn = task.wait, task.spawn;

-- firesignal implementation
-- hitchance rolling
local fireSignal, rollChance do
    -- updated for script-ware or whatever
    -- attempted to update for krnl

    function fireSignal(target, signal, ...)
        -- getconnections with InputBegan / InputEnded does not work without setting Synapse to the game's context level
        set_identity(2)
        local didFire = false
        for _, signal in next, getconnections(signal) do
            if type(signal.Function) == 'function' and islclosure(signal.Function) then
                local scr = rawget(getfenv(signal.Function), 'script')
                if scr == target then
                    didFire = true
                    pcall(signal.Function, ...)
                end
            end
        end
        -- if not didFire then fail"couldnt fire input signal" end
        set_identity(7)
    end

    -- uses a weighted random system
    -- its a bit scuffed rn but it works good enough

    function rollChance()
        -- if (//library.flags.autoPlayerMode == 'Manual') then
        if Options.AutoplayerMode.Value == 'Manual' then
            if (Options.SickBind:GetState()) then return 'Sick' end
            if (Options.GoodBind:GetState()) then return 'Good' end
            if (Options.OkayBind:GetState()) then return 'Ok' end
            if (Options.BadBind:GetState()) then return 'Bad' end

            return 'Bad' -- incase if it cant find one
        end

        local chances = {
            { 'Sick', Options.SickChance.Value },
            { 'Good', Options.GoodChance.Value },
            { 'Ok', Options.OkChance.Value },
            { 'Bad', Options.BadChance.Value },
            { 'Miss' , Options.MissChance.Value },
        }

        table.sort(chances, function(a, b)
            return a[2] > b[2]
        end)

        local sum = 0;
        for i = 1, #chances do
            sum += chances[i][2]
        end

        if sum == 0 then
            return chances[random:NextInteger(1, #chances)][1]
        end

        local initialWeight = random:NextInteger(0, sum)
        local weight = 0;

        for i = 1, #chances do
            weight = weight + chances[i][2]

            if weight > initialWeight then
                return chances[i][1]
            end
        end

        return 'Sick'
    end
end

-- autoplayer
local chanceValues do
    chanceValues = { 
        Sick = 96,
        Good = 92,
        Ok = 87,
        Bad = 75,
    }

    local keyCodeMap = {}
    for _, enum in next, Enum.KeyCode:GetEnumItems() do
        keyCodeMap[enum.Value] = enum
    end

    if shared._unload then
        pcall(shared._unload)
    end

    function shared._unload()
        if shared._id then
            pcall(runService.UnbindFromRenderStep, runService, shared._id)
        end

        UI:Unload()

        for i = 1, #shared.threads do
            coroutine.close(shared.threads[i])
        end

        for i = 1, #shared.callbacks do
            task.spawn(shared.callbacks[i])
        end
    end

    shared.threads = {}
    shared.callbacks = {}

    shared._id = httpService:GenerateGUID(false)

    local rng = Random.new()
    runService:BindToRenderStep(shared._id, 1, function()
        --if (not library.flags.autoPlayer) then return end
        
        if (not Toggles.Autoplayer) or (not Toggles.Autoplayer.Value) then 
            return 
        end

        local currentlyPlaying = framework.SongPlayer.CurrentlyPlaying

        if typeof(currentlyPlaying) ~= 'Instance' or not currentlyPlaying:IsA('Sound') then 
            return 
        end

        local arrows = {}
        for _, obj in next, framework.UI.ActiveSections do
            arrows[#arrows + 1] = obj;
        end

        local count = framework.SongPlayer:GetKeyCount()
        local mode = count .. 'Key'

        local arrowData = framework.ArrowData[mode].Arrows

        for idx = 1, #arrows do
            local arrow = arrows[idx]
            if type(arrow) ~= 'table' then
                continue
            end

            local ignoredNoteTypes = { Death = true, ['Pea Note'] = true }

            if type(arrow.NoteDataConfigs) == 'table' then 
                if ignoredNoteTypes[arrow.NoteDataConfigs.Type] then 
                    continue
                end
            end

            if (arrow.Side == framework.UI.CurrentSide) and (not arrow.Marked) and currentlyPlaying.TimePosition > 0 then
                local position = (arrow.Data.Position % count) .. '' 

                local hitboxOffset = 0 do
                    local settings = framework.Settings;
                    local offset = type(settings) == 'table' and settings.HitboxOffset;
                    local value = type(offset) == 'table' and offset.Value;

                    if type(value) == 'number' then
                        hitboxOffset = value;
                    end

                    hitboxOffset = hitboxOffset / 1000
                end

                local songTime = framework.SongPlayer.CurrentTime do
                    local configs = framework.SongPlayer.CurrentSongConfigs
                    local playbackSpeed = type(configs) == 'table' and configs.PlaybackSpeed

                    if type(playbackSpeed) ~= 'number' then
                        playbackSpeed = 1
                    end

                    songTime = songTime /  playbackSpeed
                end

                local noteTime = math.clamp((1 - math.abs(arrow.Data.Time - (songTime + hitboxOffset))) * 100, 0, 100)

                local result = rollChance()
                arrow._hitChance = arrow._hitChance or result;

                local hitChance = (Options.AutoplayerMode.Value == 'Manual' and result or arrow._hitChance)
                if hitChance ~= "Miss" and noteTime >= chanceValues[arrow._hitChance] then
                    fastSpawn(function()
                        arrow.Marked = true;
                        local keyCode = keyCodeMap[arrowData[position].Keybinds.Keyboard[1]]

                        if Toggles.SecondaryPress.Value then
                            virtualInputManager:SendKeyEvent(true, keyCode, false, nil)
                        else
                            fireSignal(scrollHandler, userInputService.InputBegan, { KeyCode = keyCode, UserInputType = Enum.UserInputType.Keyboard }, false)
                        end

                        local arrowLength = arrow.Data.Length or 0
                        local isHeld = arrowLength > 0

                        local delayMode = Options.DelayMode.Value

                        local minDelay = isHeld and Options.HeldDelayMin or Options.NoteDelayMin;
                        local maxDelay = isHeld and Options.HeldDelayMax or Options.NoteDelayMax;
                        local noteDelay = isHeld and Options.HeldDelay or Options.ReleaseDelay
   
                        if Options.DelayMode.Value == 'Random' then
                            task.wait(arrowLength + rng:NextNumber(minDelay.Value, maxDelay.Value) / 1000)
                        else
                            task.wait(arrowLength + (noteDelay.Value / 1000))
                        end

                        if Toggles.SecondaryPress.Value then
                            virtualInputManager:SendKeyEvent(false, keyCode, false, nil)
                        else
                            fireSignal(scrollHandler, userInputService.InputEnded, { KeyCode = keyCode, UserInputType = Enum.UserInputType.Keyboard }, false)
                        end

                        arrow.Marked = nil;
                    end)
                end
            end
        end
    end)
end

local ActivateUnlockables do
    -- Note: I know you can do this with UserId but it only works if you run it before opening the notes menu
    -- My script should work no matter the order of which you run things :)

    local loadStyle = nil
    local function loadStyleProxy(...)
        -- This forces the styles to reload every time
            
        local upvalues = getupvalues(loadStyle)
        for i, upvalue in next, upvalues do
            if type(upvalue) == 'table' and rawget(upvalue, 'Style') then
                rawset(upvalue, 'Style', nil);
                setupvalue(loadStyle, i, upvalue)
            end
        end

        return loadStyle(...)
    end

    local function applyLoadStyleProxy(...)
        local gc = getgc()
        for i = 1, #gc do
            local obj = gc[i]
            if type(obj) == 'function' then
                local nups = getinfo(obj).nups;
                for i = 1, nups do
                    local upv = getupvalue(obj, i)
                    if type(upv) == 'function' and getinfo(upv).name == 'LoadStyle' then
                        -- ugly but it works
                        if getinfo(obj).source:match('%.ArrowSelector%.Customize$') and getinfo(upv).source:match('%.ArrowSelector%.Customize$') then
                            -- avoid non-game functions :)

                            loadStyle = loadStyle or upv
                            setupvalue(obj, i, loadStyleProxy)

                            table.insert(shared.callbacks, function()
                                assert(pcall(setupvalue, obj, i, loadStyle))
                            end)
                        end
                    end
                end
            end
        end
    end

    local success, error = pcall(applyLoadStyleProxy)
    if not success then
        return fail(string.format('Failed to hook LoadStyle function. Error(%q)\nExecutor(%q)\n', error, executor))
    end

    function ActivateUnlockables()
        local idx = table.find(framework.SongsWhitelist, client.UserId)
        if idx then return end

        UI:Notify('Developer arrows have been unlocked!', 3)
        table.insert(framework.SongsWhitelist, client.UserId)
    end
end

-- UpdateScore hook
do
    local roundManager = network.Server.RoundManager
    local oldUpdateScore = type(roundManager) == 'table' and roundManager.UpdateScore;

    function roundManager.UpdateScore(...)
        local args = { ... }
        local score = args[2]

        if type(score) == 'number' and Options.ScoreModifier then
            if Options.ScoreModifier.Value == 'No decrease on miss' then
                args[2] = 0
            elseif Options.ScoreModifier.Value == 'Increase score on miss' then
                args[2] = math.abs(score)
            end
        end

        return oldUpdateScore(unpack(args))
    end

    table.insert(shared.callbacks, function()
        roundManager.UpdateScore = oldUpdateScore
    end)
end

local SaveManager = {} do
    SaveManager.Ignore = {}
    SaveManager.Parser = {
        Toggle = {
            Save = function(idx, object) 
                return { type = 'Toggle', idx = idx, value = object.Value } 
            end,
            Load = function(idx, data)
                if Toggles[idx] then 
                    Toggles[idx]:SetValue(data.value)
                end
            end,
        },
        Slider = {
            Save = function(idx, object)
                return { type = 'Slider', idx = idx, value = tostring(object.Value) }
            end,
            Load = function(idx, data)
                if Options[idx] then 
                    Options[idx]:SetValue(data.value)
                end
            end,
        },
        Dropdown = {
            Save = function(idx, object)
                return { type = 'Dropdown', idx = idx, value = object.Value, mutli = object.Multi }
            end,
            Load = function(idx, data)
                if Options[idx] then 
                    Options[idx]:SetValue(data.value)
                end
            end,
        },
        ColorPicker = {
            Save = function(idx, object)
                return { type = 'ColorPicker', idx = idx, value = object.Value:ToHex() }
            end,
            Load = function(idx, data)
                if Options[idx] then 
                    Options[idx]:SetValueRGB(Color3.fromHex(data.value))
                end
            end,
        },
        KeyPicker = {
            Save = function(idx, object)
                return { type = 'KeyPicker', idx = idx, mode = object.Mode, key = object.Value }
            end,
            Load = function(idx, data)
                if Options[idx] then 
                    Options[idx]:SetValue({ data.key, data.mode })
                end
            end,
        }
    }

    function SaveManager:Save(name)
        local fullPath = 'funky_friday_autoplayer/configs/' .. name .. '.json'

        local data = {
            version = 2,
            objects = {}
        }

        for idx, toggle in next, Toggles do
            if self.Ignore[idx] then continue end
            table.insert(data.objects, self.Parser[toggle.Type].Save(idx, toggle))
        end

        for idx, option in next, Options do
            if not self.Parser[option.Type] then continue end
            if self.Ignore[idx] then continue end

            table.insert(data.objects, self.Parser[option.Type].Save(idx, option))
        end 

        local success, encoded = pcall(httpService.JSONEncode, httpService, data)
        if not success then
            return false, 'failed to encode data'
        end

        writefile(fullPath, encoded)
        return true
    end

    function SaveManager:Load(name)
        local file = 'funky_friday_autoplayer/configs/' .. name .. '.json'
        if not isfile(file) then return false, 'invalid file' end

        local success, decoded = pcall(httpService.JSONDecode, httpService, readfile(file))
        if not success then return false, 'decode error' end
        if decoded.version ~= 2 then return false, 'invalid version' end

        for _, option in next, decoded.objects do
            if self.Parser[option.type] then
                self.Parser[option.type].Load(option.idx, option)
            end
        end

        return true
    end

    function SaveManager.Refresh()
        local list = listfiles('funky_friday_autoplayer/configs')

        local out = {}
        for i = 1, #list do
            local file = list[i]
            if file:sub(-5) == '.json' then
                -- i hate this but it has to be done ...

                local pos = file:find('.json', 1, true)
                local start = pos

                local char = file:sub(pos, pos)
                while char ~= '/' and char ~= '\\' and char ~= '' do
                    pos = pos - 1
                    char = file:sub(pos, pos)
                end

                if char == '/' or char == '\\' then
                    table.insert(out, file:sub(pos + 1, start - 1))
                end
            end
        end
        
        Options.ConfigList.Values = out;
        Options.ConfigList:SetValues()

        return out
    end

    function SaveManager.Check()
        local list = listfiles('funky_friday_autoplayer/configs')

        for _, file in next, list do
            if isfolder(file) then continue end

            local data = readfile(file)
            local success, decoded = pcall(httpService.JSONDecode, httpService, data)

            if success and type(decoded) == 'table' and decoded.version ~= 2 then
                pcall(delfile, file)
            end
        end
    end
end

UI.AccentColor = Color3.fromRGB(255, 65, 65)
UI.AccentColorDark = UI:GetDarkerColor(UI.AccentColor);
UI:UpdateColorsUsingRegistry()

local Window = UI:CreateWindow({
    Title = string.format('funky friday autoplayer - version %s | updated: %s', metadata.version, metadata.updated),
    AutoShow = true,
    
    Center = true,
    Size = UDim2.fromOffset(550, 610),
})

local Tabs = {}
Tabs.Main = Window:AddTab('Main')

local Groups = {}
Groups.Autoplayer = Tabs.Main:AddLeftGroupbox('Autoplayer')
    Groups.Autoplayer:AddToggle('Autoplayer', { Text = 'Autoplayer' }):AddKeyPicker('AutoplayerBind', { Default = 'End', NoUI = true, SyncToggleState = true })
    Groups.Autoplayer:AddToggle('SecondaryPress', { Text = 'Seconary press mode', Tooltip = 'Enable this only if the primary autoplayer does not work.' })

    Groups.Autoplayer:AddDivider()
    Groups.Autoplayer:AddDropdown('AutoplayerMode', { Text = 'Autoplayer mode', Default = 1, Values = { 'Chances', 'Manual' } })
    Groups.Autoplayer:AddDropdown('DelayMode', { Text = 'Delay mode', Default = 1, Values = { 'Manual', 'Random' } })

    Groups.Autoplayer:AddDivider()
    Groups.Autoplayer:AddDropdown('ScoreModifier', { 
        Text = 'Score modifications', 
        Default = 1, 
        Values = { 'Do nothing', 'No decrease on miss', 'Increase score on miss' },
        Tooltip = 'Modifies certain game functions to help you keep your score up!',
    })

Groups.HitChances = Tabs.Main:AddLeftGroupbox('Hit chances')
    Groups.HitChances:AddSlider('SickChance',   { Text = 'Sick chance', Min = 0, Max = 100, Default = 100, Suffix = '%', Rounding = 0 })
    Groups.HitChances:AddSlider('GoodChance',   { Text = 'Good chance', Min = 0, Max = 100, Default = 0, Suffix = '%', Rounding = 0 })
    Groups.HitChances:AddSlider('OkChance',     { Text = 'Ok chance',   Min = 0, Max = 100, Default = 0, Suffix = '%', Rounding = 0 })
    Groups.HitChances:AddSlider('BadChance',    { Text = 'Bad chance',  Min = 0, Max = 100, Default = 0, Suffix = '%', Rounding = 0 })
    Groups.HitChances:AddSlider('MissChance',   { Text = 'Miss chance', Min = 0, Max = 100, Default = 0, Suffix = '%', Rounding = 0 })

Groups.HitTiming = Tabs.Main:AddRightTabbox('Hit timing')
    Groups.ManualTiming = Groups.HitTiming:AddTab('Manual delay')
        Groups.ManualTiming:AddSlider('ReleaseDelay',   { Text = 'Release delay (ms)',  Min = 0,   Max = 500, Default = 20, Rounding = 0 })
        Groups.ManualTiming:AddSlider('HeldDelay',      { Text = 'Held delay (ms)',     Min = -20, Max = 100, Default = 0,  Rounding = 0 })
    
    Groups.RandomTiming = Groups.HitTiming:AddTab('Random delay')
        Groups.RandomTiming:AddSlider('NoteDelayMin',   { Text = 'Minimum note delay (ms)', Min = 0, Max = 500, Default = 0,    Rounding = 0 })
        Groups.RandomTiming:AddSlider('NoteDelayMax',   { Text = 'Maximum note delay (ms)', Min = 0, Max = 100, Default = 20,   Rounding = 0 })

        Groups.RandomTiming:AddSlider('HeldDelayMin',   { Text = 'Minimum held note delay (ms)', Min = 0, Max = 500, Default = 0,   Rounding = 0 })
        Groups.RandomTiming:AddSlider('HeldDelayMax',   { Text = 'Maximum held note delay (ms)', Min = 0, Max = 100, Default = 20,  Rounding = 0 })

Groups.Keybinds = Tabs.Main:AddLeftGroupbox('Keybinds')
    Groups.Keybinds:AddLabel('Sick'):AddKeyPicker('SickBind', { Default = 'One', NoUI = true })
    Groups.Keybinds:AddLabel('Good'):AddKeyPicker('GoodBind', { Default = 'Two', NoUI = true })
    Groups.Keybinds:AddLabel('Ok'):AddKeyPicker('OkayBind', { Default = 'Three', NoUI = true })
    Groups.Keybinds:AddLabel('Bad'):AddKeyPicker('BadBind', { Default = 'Four', NoUI = true })

Groups.Credits = Tabs.Main:AddRightGroupbox('Credits')
    Groups.Credits:AddLabel('<font color="#3da5ff">wally</font> - script')
    Groups.Credits:AddLabel('<font color="#de6cff">Sezei</font> - contributor')
    Groups.Credits:AddLabel('Inori - ui library')
    Groups.Credits:AddLabel('Jan - old ui library')

Groups.Unlockables = Tabs.Main:AddRightGroupbox('Unlockables')
    Groups.Unlockables:AddButton('Unlock developer notes', ActivateUnlockables)

Groups.Misc = Tabs.Main:AddRightGroupbox('Miscellaneous')
    Groups.Misc:AddLabel(metadata.message or 'no message found!', true)

    Groups.Misc:AddDivider()
    Groups.Misc:AddButton('Unload script', function() pcall(shared._unload) end)
    Groups.Misc:AddButton('Copy discord', function()
        if pcall(setclipboard, "https://wally.cool/discord") then
            UI:Notify('Successfully copied discord link to your clipboard!', 5)
        end
    end)

    Groups.Misc:AddLabel('Menu toggle'):AddKeyPicker('MenuToggle', { Default = 'Delete', NoUI = true })

    UI.ToggleKeybind = Options.MenuToggle

if type(readfile) == 'function' and type(writefile) == 'function' and type(makefolder) == 'function' and type(isfolder) == 'function' then
    Tabs.Settings = Window:AddTab('Settings')
    Groups.Configs = Tabs.Settings:AddLeftGroupbox('Configs')

    makefolder('funky_friday_autoplayer')
    makefolder('funky_friday_autoplayer\\configs')

    Groups.Configs:AddDropdown('ConfigList', { Text = 'Config list', Values = {} })
    Groups.Configs:AddInput('ConfigName',    { Text = 'Config name' })

    Groups.Configs:AddDivider()

    Groups.Configs:AddButton('Save config', function()
        local name = Options.ConfigName.Value;
        if name:gsub(' ', '') == '' then
            return UI:Notify('Invalid config name.', 3)
        end

        local success, err = SaveManager:Save(name)
        if not success then
            return UI:Notify(tostring(err), 5)
        end

        UI:Notify(string.format('Saved config %q', name), 5)
        task.defer(SaveManager.Refresh)
    end)

    Groups.Configs:AddButton('Load config', function()
        local name = Options.ConfigList.Value
        local success, err = SaveManager:Load(name)
        if not success then
            return UI:Notify(tostring(err), 5)
        end

        UI:Notify(string.format('Loaded config %q', name), 5)
    end)

    Groups.Configs:AddButton('Refresh list', SaveManager.Refresh)

    task.defer(SaveManager.Refresh)
    task.defer(SaveManager.Check)
else
    UI:Notify('Failed to create configs tab due to your exploit missing certain file functions.', 2)
end


UI:Notify(string.format('Loaded script in %.4f second(s)!', tick() - start), 3)
