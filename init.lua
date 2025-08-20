-- init.lua (fixed / executor-robust)

local environment = assert(getgenv, "<OH> ~ Your exploit is not supported")()

if oh then
    if type(oh.Exit) == "function" then
        pcall(function() oh.Exit() end)
    end
end

local web = true
local user = "authDet" -- change if you're using a fork
local branch = "revision"
local importCache = {}

-- safe fetch: supports many executor methods
local function fetch(url)
    -- prefer syn.request-like
    if type(syn) == "table" and type(syn.request) == "function" then
        local ok, res = pcall(syn.request, { Url = url, Method = "GET" })
        if ok and res and res.Body then return res.Body end
    end

    if type(http_request) == "function" then
        local ok, res = pcall(http_request, { Url = url, Method = "GET" })
        if ok and res and res.Body then return res.Body end
    end

    if type(request) == "function" then
        local ok, res = pcall(request, { Url = url, Method = "GET" })
        if ok and res and res.Body then return res.Body end
    end

    -- Some executors use http.request
    if type(http) == "table" and type(http.request) == "function" then
        local ok, res = pcall(http.request, { Url = url, Method = "GET" })
        if ok and res and (res.Body or res.body) then return res.Body or res.body end
    end

    -- Roblox game methods (method call style)
    if type(game) == "table" then
        -- prefer method call with colon
        if type(game.HttpGet) == "function" then
            local ok, res = pcall(function() return game:HttpGet(url) end)
            if ok and res then return res end
        end
        if type(game.HttpGetAsync) == "function" then
            local ok, res = pcall(function() return game:HttpGetAsync(url) end)
            if ok and res then return res end
        end
    end

    error("<OH> ~ No HTTP method available in this executor")
end

-- helper: return first non-nil argument
local function first(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil then return v end
    end
    return nil
end

local function hasMethods(methods)
    for name in pairs(methods) do
        if not environment[name] then
            return false
        end
    end
    return true
end

local function useMethods(module)
    for name, method in pairs(module) do
        if method then
            environment[name] = method
        end
    end
end

-- attempt to neutralize odd globals from certain environments
if Window and PROTOSMASHER_LOADED then
    getgenv().get_script_function = nil
end

-- dummy fallback
local function dummy(...) return false end

-- discover hook-related functions (various possible names)
local _hookFunction = first(hookFunction, hookfunction, detour_function, detourFunction)
local _hookMetaMethod = first(hookMetaMethod, hookmetamethod)

-- if no hookMetaMethod but hookFunction exists, try to synthesize one using metatable hooking
if not _hookMetaMethod and _hookFunction then
    local _getmt = first(getrawmetatable, (debug and debug.getmetatable))
    if _getmt then
        _hookMetaMethod = function(object, method, hook)
            local mt = _getmt(object)
            if not mt then return nil end
            local target = mt[method]
            if not target then return nil end
            -- try to hook the target via available hookFunction
            return _hookFunction(target, hook)
        end
    end
end

-- ensure safe fallbacks
if not _hookFunction then
    _hookFunction = function(...) warn("<OH> ~ hookFunction not available; operation skipped") return nil end
end
if not _hookMetaMethod then
    _hookMetaMethod = function(...) warn("<OH> ~ hookMetaMethod not available; operation skipped") return nil end
end

-- diagnostic prints (can be commented out later)
print("<OH> diag: hookFunction ->", tostring(_hookFunction))
print("<OH> diag: hookMetaMethod ->", tostring(_hookMetaMethod))

-- resolve many other environment functions with safe first(...)
local globalMethods = {
    checkCaller = first(checkcaller, checkCaller, dummy),
    newCClosure = first(newcclosure, newCClosure, dummy),
    hookFunction = _hookFunction,
    getGc = first(getgc, get_gc_objects, dummy),
    getInfo = first((debug and debug.getinfo), getinfo, dummy),
    getSenv = first(getsenv, getSenv, dummy),
    getMenv = first(getmenv, getsenv, dummy),
    getContext = first(getthreadcontext, get_thread_context, (syn and syn.get_thread_identity), dummy),
    getConnections = first(get_signal_cons, getconnections, dummy),
    getScriptClosure = first(getscriptclosure, get_script_function, dummy),
    getNamecallMethod = first(getnamecallmethod, get_namecall_method, dummy),
    getCallingScript = first(getcallingscript, get_calling_script, dummy),
    getLoadedModules = first(getloadedmodules, get_loaded_modules, dummy),
    getConstants = first((debug and debug.getconstants), getconstants, getconsts, dummy),
    getUpvalues = first((debug and debug.getupvalues), getupvalues, getupvals, dummy),
    getProtos = first((debug and debug.getprotos), getprotos, dummy),
    getStack = first((debug and debug.getstack), getstack, dummy),
    getConstant = first((debug and debug.getconstant), getconstant, getconst, dummy),
    getUpvalue = first((debug and debug.getupvalue), getupvalue, getupval, dummy),
    getProto = first((debug and debug.getproto), getproto, dummy),
    getMetatable = first(getrawmetatable, (debug and debug.getmetatable), dummy),
    getHui = first(get_hidden_gui, gethui, dummy),
    setClipboard = first(setclipboard, writeclipboard, dummy),
    setConstant = first((debug and debug.setconstant), setconstant, setconst, dummy),
    setContext = first(setthreadcontext, set_thread_context, (syn and syn.set_thread_identity), dummy),
    setUpvalue = first((debug and debug.setupvalue), setupvalue, setupval, dummy),
    setStack = first((debug and debug.setstack), setstack, dummy),
    setReadOnly = first(setreadonly, (make_writeable and function(t, readonly) if readonly then make_readonly(t) else make_writeable(t) end end), dummy),
    isLClosure = first(islclosure, is_l_closure, (iscclosure and function(closure) return not iscclosure(closure) end), dummy),
    isReadOnly = first(isreadonly, is_read_only, dummy),
    isXClosure = first(is_synapse_function, issentinelclosure, is_protosmasher_closure, is_sirhurt_closure, iselectronfunction, istempleclosure, checkclosure, dummy),
    hookMetaMethod = _hookMetaMethod,
    readFile = first(readfile, readFile),
    writeFile = first(writefile, writeFile),
    makeFolder = first(makefolder, makeFolder),
    isFolder = first(isfolder, isFolder),
    isFile = first(isfile, isFile),
}

-- special-case for PROTOSMASHER
if PROTOSMASHER_LOADED then
    globalMethods.getConstant = function(closure, index)
        return globalMethods.getConstants(closure)[index]
    end
end

-- adapt getUpvalue / getUpvalues to tables with Closure wrapper if present
local oldGetUpvalue = globalMethods.getUpvalue
local oldGetUpvalues = globalMethods.getUpvalues

globalMethods.getUpvalue = function(closure, index)
    if type(closure) == "table" and closure.Data then
        return oldGetUpvalue(closure.Data, index)
    end
    return oldGetUpvalue(closure, index)
end

globalMethods.getUpvalues = function(closure)
    if type(closure) == "table" and closure.Data then
        return oldGetUpvalues(closure.Data)
    end
    return oldGetUpvalues(closure)
end

-- export minimal helpers to environment
environment.hasMethods = hasMethods

-- build oh table
environment.oh = {
    Events = {},
    Hooks = {},
    Cache = importCache,
    Methods = globalMethods,
    Constants = {
        Types = {
            ["nil"] = "rbxassetid://4800232219",
            table = "rbxassetid://4666594276",
            string = "rbxassetid://4666593882",
            number = "rbxassetid://4666593882",
            boolean = "rbxassetid://4666593882",
            userdata = "rbxassetid://4666594723",
            vector = "rbxassetid://4666594723",
            ["function"] = "rbxassetid://4666593447",
            ["thread"] = "rbxassetid://4666593447",
            ["integral"] = "rbxassetid://4666593882"
        },
        Syntax = {
            ["nil"] = Color3.fromRGB(244, 135, 113),
            table = Color3.fromRGB(225, 225, 225),
            string = Color3.fromRGB(225, 150, 85),
            number = Color3.fromRGB(170, 225, 127),
            boolean = Color3.fromRGB(127, 200, 255),
            userdata = Color3.fromRGB(225, 225, 225),
            vector = Color3.fromRGB(225, 225, 225),
            ["function"] = Color3.fromRGB(225, 225, 225),
            ["thread"] = Color3.fromRGB(225, 225, 225),
            ["unnamed_function"] = Color3.fromRGB(175, 175, 175)
        }
    },
    Exit = function()
        for _i, event in pairs(oh.Events) do
            pcall(function() event:Disconnect() end)
        end
        for original, hook in pairs(oh.Hooks) do
            local hookType = type(hook)
            if hookType == "function" then
                if _hookFunction then pcall(function() _hookFunction(hook, original) end) end
            elseif hookType == "table" and hook.Closure and hook.Original and _hookFunction then
                pcall(function() _hookFunction(hook.Closure.Data, hook.Original) end)
            end
        end
        local ui = importCache["rbxassetid://11389137937"]
        local assets = importCache["rbxassetid://5042114982"]
        if ui and next(ui) then pcall(function() unpack(ui):Destroy() end) end
        if assets and next(assets) then pcall(function() unpack(assets):Destroy() end) end
    end
}

-- make global methods available before getConnections logic
useMethods(globalMethods)

-- getConnections handling (safe)
local getConnectionsFn = first(get_signal_cons, getconnections, function() return nil end)
if getConnectionsFn then
    local ScriptContext = game:GetService("ScriptContext")
    local ok, conns = pcall(function() return getConnectionsFn(ScriptContext.Error) end)
    if ok and type(conns) == "table" then
        for __, connection in pairs(conns) do
            local conn = first(getrawmetatable, (debug and debug.getmetatable)) and first(getrawmetatable, (debug and debug.getmetatable))(connection) or nil
            if conn then
                local old = conn.__index
                if PROTOSMASHER_LOADED ~= nil then
                    if setwriteable then pcall(function() setwriteable(conn) end) end
                else
                    if globalMethods.setReadOnly then pcall(function() globalMethods.setReadOnly(conn, false) end) end
                end

                if old then
                    if newcclosure then
                        conn.__index = newcclosure(function(t, k)
                            if k == "Connected" then return true end
                            return old(t, k)
                        end)
                    else
                        conn.__index = function(t, k)
                            if k == "Connected" then return true end
                            return old and old(t, k)
                        end
                    end
                end

                if PROTOSMASHER_LOADED ~= nil then
                    if connection.Disconnect then pcall(function() connection:Disconnect() end)
                    elseif connection.Disable then pcall(function() connection:Disable() end) end
                else
                    if connection.Disable then pcall(function() connection:Disable() end)
                    elseif connection.Disconnect then pcall(function() connection:Disconnect() end) end
                end
            end
        end
    end
end

-- loader fallback
local loader = first(loadstring, load)

-- environment.import always defined (supports filesystem caching if available)
function environment.import(asset)
    if importCache[asset] then
        return unpack(importCache[asset])
    end

    local assets
    if type(asset) == "string" and asset:find("rbxassetid://") then
        assets = { game:GetObjects(asset)[1] }
    elseif web then
        local content
        if type(readfile) == "function" and type(writefile) == "function" then
            local hasFolderFunctions = (type(isfolder) == "function" and type(makefolder) == "function")
            local file = (hasFolderFunctions and ("hydroxide/user/" .. user .. "/" .. asset .. ".lua")) or ("hydroxide-" .. user .. "-" .. asset:gsub("/", "-") .. ".lua")
            local ok, result = pcall(readfile, file)
            if not ok or not result then
                content = fetch("https://raw.githubusercontent.com/" .. user .. "/Hydroxide/" .. branch .. "/" .. asset .. ".lua")
                if content and type(writefile) == "function" then
                    pcall(function() writefile(file, content) end)
                end
            else
                content = result
            end
        else
            content = fetch("https://raw.githubusercontent.com/" .. user .. "/Hydroxide/" .. branch .. "/" .. asset .. ".lua")
        end

        if not content then error("<OH> ~ Failed to fetch asset: " .. tostring(asset)) end

        if not loader then error("<OH> ~ No loadstring/load available in this environment") end

        local ok, res = pcall(function()
            local f = loader(content, "@" .. asset)
            if type(f) ~= "function" then error("loader did not return function for " .. asset) end
            return f()
        end)
        if not ok then error("<OH> ~ Failed to execute asset '" .. asset .. "': " .. tostring(res)) end
        assets = { res }
    else
        -- offline: require readfile to exist
        if not loader then error("<OH> ~ No loadstring/load available in this environment") end
        local content = readfile("hydroxide/" .. asset .. ".lua")
        local f = loader(content, "@" .. asset)
        assets = { f() }
    end

    importCache[asset] = assets
    return unpack(assets)
end

-- optional: create folders if filesystem available
if type(readfile) == "function" and type(writefile) == "function" then
    local hasFolderFunctions = (type(isfolder) == "function" and type(makefolder) == "function")
    if hasFolderFunctions then
        local function createFolder(path) if not isfolder(path) then makefolder(path) end end
        createFolder("hydroxide")
        createFolder("hydroxide/user")
        createFolder("hydroxide/user/" .. user)
        createFolder("hydroxide/user/" .. user .. "/methods")
        createFolder("hydroxide/user/" .. user .. "/modules")
        createFolder("hydroxide/user/" .. user .. "/objects")
        createFolder("hydroxide/user/" .. user .. "/ui")
        createFolder("hydroxide/user/" .. user .. "/ui/controls")
        createFolder("hydroxide/user/" .. user .. "/ui/modules")
    end
end

-- import methods (these must exist in the repo)
useMethods(import("methods/string"))
useMethods(import("methods/table"))
useMethods(import("methods/userdata"))
useMethods(import("methods/environment"))

-- UI loading is left to the external loader if needed:
-- import("ui/main")

-- End of init.lua
