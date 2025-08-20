local environment = assert(getgenv, "<OH> ~ Your exploit is not supported")()

if oh then
    oh.Exit()
end

local web = true
local user = "authDet" -- change if you're using a fork
local branch = "revision"
local importCache = {}

-- دالة HTTP آمنة
local function fetch(url)
    if game and game.HttpGet then
        return game:HttpGet(url)  -- ✅ بدون تمرير game
    elseif game and game.HttpGetAsync then
        return game:HttpGetAsync(url)  -- ✅ نفس الشيء
    else
        error("<OH> ~ No HTTP method available in this executor")
    end
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

if Window and PROTOSMASHER_LOADED then
    getgenv().get_script_function = nil
end

local function dummy(...)
    return false
end

local globalMethods = {
    checkCaller = checkcaller,
    newCClosure = newcclosure,
    hookFunction = hookfunction or detour_function,
    getGc = getgc or get_gc_objects,
    getInfo = debug.getinfo or getinfo,
    getSenv = getsenv,
    getMenv = getmenv or getsenv,
    getContext = getthreadcontext or get_thread_context or (syn and syn.get_thread_identity),
    getConnections = get_signal_cons or getconnections,
    getScriptClosure = getscriptclosure or get_script_function,
    getNamecallMethod = getnamecallmethod or get_namecall_method,
    getCallingScript = getcallingscript or get_calling_script,
    getLoadedModules = getloadedmodules or get_loaded_modules,
    getConstants = debug.getconstants or getconstants or getconsts,
    getUpvalues = debug.getupvalues or getupvalues or getupvals,
    getProtos = debug.getprotos or getprotos,
    getStack = debug.getstack or getstack,
    getConstant = debug.getconstant or getconstant or getconst,
    getUpvalue = debug.getupvalue or getupvalue or getupval,
    getProto = debug.getproto or getproto,
    getMetatable = getrawmetatable or debug.getmetatable,
    getHui = get_hidden_gui or gethui,
    setClipboard = setclipboard or writeclipboard,
    setConstant = debug.setconstant or setconstant or setconst,
    setContext = setthreadcontext or set_thread_context or (syn and syn.set_thread_identity),
    setUpvalue = debug.setupvalue or setupvalue or setupval,
    setStack = debug.setstack or setstack,
    setReadOnly = setreadonly or (make_writeable and function(t, readonly) if readonly then make_readonly(t) else make_writeable(t) end end),
    isLClosure = islclosure or is_l_closure or (iscclosure and function(closure) return not iscclosure(closure) end),
    isReadOnly = isreadonly or is_readonly,
    is_synapse_function or issentinelclosure or is_protosmasher_closure or is_sirhurt_closure or iselectronfunction or istempleclosure or checkclosure or dummy,  -- fallback safe
    hookMetaMethod = hookmetamethod or (hookfunction and function(object, method, hook) local mt = (getrawmetatable or debug.getmetatable)(object); return mt and hookfunction(mt[method], hook) end),
    readFile = readfile,
    writeFile = writefile,
    makeFolder = makefolder,
    isFolder = isfolder,
    isFile = isfile,
}

if PROTOSMASHER_LOADED then
    globalMethods.getConstant = function(closure, index)
        return globalMethods.getConstants(closure)[index]
    end
end

local oldGetUpvalue = globalMethods.getUpvalue
local oldGetUpvalues = globalMethods.getUpvalues

globalMethods.getUpvalue = function(closure, index)
    if type(closure) == "table" then
        return oldGetUpvalue(closure.Data, index)
    end
    return oldGetUpvalue(closure, index)
end

globalMethods.getUpvalues = function(closure)
    if type(closure) == "table" then
        return oldGetUpvalues(closure.Data)
    end
    return oldGetUpvalues(closure)
end

environment.hasMethods = hasMethods
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
            event:Disconnect()
        end
        for original, hook in pairs(oh.Hooks) do
            local hookType = type(hook)
            if hookType == "function" then
                if hookfunction then hookfunction(hook, original) end
            elseif hookType == "table" and hook.Closure and hook.Original and hookfunction then
                hookfunction(hook.Closure.Data, hook.Original)
            end
        end
        local ui = importCache["rbxassetid://11389137937"]
        local assets = importCache["rbxassetid://5042114982"]
        if ui and next(ui) then unpack(ui):Destroy() end
        if assets and next(assets) then unpack(assets):Destroy() end
    end
}

-- اجعل الطرق العالمية متاحة قبل التعامل مع getConnections
useMethods(globalMethods)

if getConnections then
    for __, connection in pairs(getConnections(game:GetService("ScriptContext").Error)) do
        local conn = getrawmetatable and getrawmetatable(connection)
        if conn then
            local old = conn.__index
            if PROTOSMASHER_LOADED ~= nil then
                if setwriteable then setwriteable(conn) end
            else
                if setReadOnly then setReadOnly(conn, false) end
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
                if connection.Disconnect then connection:Disconnect()
                elseif connection.Disable then connection:Disable() end
            else
                if connection.Disable then connection:Disable()
                elseif connection.Disconnect then connection:Disconnect() end
            end
        end
    end
end

-- import موحدة دائماً
function environment.import(asset)
    if importCache[asset] then
        return unpack(importCache[asset])
    end

    local assets
    if asset:find("rbxassetid://") then
        assets = { game:GetObjects(asset)[1] }

    elseif web then
        local content
        if readFile and writeFile then
            local hasFolderFunctions = (isFolder and makeFolder) ~= nil
            local file = (hasFolderFunctions and "hydroxide/user/" .. user .. "/" .. asset .. ".lua")
                         or ("hydroxide-" .. user .. "-" .. asset:gsub("/", "-") .. ".lua")
            local ok, result = pcall(readFile, file)
            if not ok then
                content = fetch("https://raw.githubusercontent.com/" .. user .. "/Hydroxide/" .. branch .. "/" .. asset .. ".lua")
                writeFile(file, content)
            else
                content = result
            end
        else
            content = fetch("https://raw.githubusercontent.com/" .. user .. "/Hydroxide/" .. branch .. "/" .. asset .. ".lua")
        end
        assets = { loadstring(content, asset .. ".lua")() }

    else
        assets = { loadstring(readFile("hydroxide/" .. asset .. ".lua"), asset .. ".lua")() }
    end

    importCache[asset] = assets
    return unpack(assets)
end

-- المجلدات (اختياري)
if readFile and writeFile then
    local hasFolderFunctions = (isFolder and makeFolder) ~= nil
    if hasFolderFunctions then
        local function createFolder(path)
            if not isFolder(path) then makeFolder(path) end
        end
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

-- استيراد الميثودز
useMethods(import("methods/string"))
useMethods(import("methods/table"))
useMethods(import("methods/userdata"))
useMethods(import("methods/environment"))

-- import("ui/main")
