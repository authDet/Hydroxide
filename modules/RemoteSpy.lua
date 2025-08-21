-- modules/RemoteSpy.lua (executor-adapted, safe)

local RemoteSpy = {}
local Remote = import("objects/Remote")

-- helper: choose first non-nil
local function first(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil then return v end
    end
    return nil
end

-- resolve names (prefer the exact names your executor provides)
local _hookFunction     = first(hookFunction, hookfunction, replaceclosure, replaceClosure, detour_function)
local _hookMetaMethod   = first(hookMetaMethod, hookmetamethod)
local _newcclosure      = first(newcclosure, newCClosure, newcclosure) -- prefer lowercase newcclosure
local _getNamecallMethod= first(getNamecallMethod, getnamecallmethod, get_namecall_method)
local _getCallingScript = first(getCallingScript, getcallingscript, get_calling_script)
local _getInfo          = first(getInfo, (debug and debug.getinfo), getinfo)
local _typeof           = first(typeof, type)

-- required method names (for external checks)
local requiredMethods = {
    ["checkCaller"] = true,
    ["newCClosure"] = true,
    ["hookFunction"] = true,
    ["isReadOnly"] = true,
    ["setReadOnly"] = true,
    ["getInfo"] = true,
    ["getMetatable"] = true,
    ["setClipboard"] = true,
    ["getNamecallMethod"] = true,
    ["getCallingScript"] = true,
}

-- quick guard: ensure critical functions exist and are callable
local function missingCritical()
    if type(_hookFunction) ~= "function" then
        warn("[RemoteSpy] hookFunction missing - RemoteSpy disabled")
        return true
    end

    if type(_newcclosure) ~= "function" then
        warn("[RemoteSpy] newcclosure missing - RemoteSpy disabled")
        return true
    end

    if type(_getInfo) ~= "function" then
        warn("[RemoteSpy] getInfo missing - RemoteSpy disabled")
        return true
    end

    return false
end

if missingCritical() then
    -- provide safe no-op interface so callers don't crash
    RemoteSpy.RemotesViewing = {}
    RemoteSpy.CurrentRemotes = {}
    RemoteSpy.ConnectEvent = function() end
    RemoteSpy.RequiredMethods = requiredMethods
    return RemoteSpy
end

local remoteMethods = {
    FireServer = true,
    InvokeServer = true,
    Fire = true,
    Invoke = true
}

local remotesViewing = {
    RemoteEvent = true,
    RemoteFunction = false,
    BindableEvent = false,
    BindableFunction = false
}

-- prototype method references (we hook the prototype method functions)
local methodHooks = {
    RemoteEvent = Instance.new("RemoteEvent").FireServer,
    RemoteFunction = Instance.new("RemoteFunction").InvokeServer,
    BindableEvent = Instance.new("BindableEvent").Fire,
    BindableFunction = Instance.new("BindableFunction").Invoke
}

local currentRemotes = {}
local remoteDataEvent = Instance.new("BindableEvent")
local eventSet = false

local function connectEvent(callback)
    if type(callback) ~= "function" then return end
    pcall(function() remoteDataEvent.Event:Connect(callback) end)
    eventSet = true
end

-- namecall hooking (use hookMetaMethod if available, otherwise synthesize via metatable hooking)
local nmcTrampoline
do
    local hooker
    if type(_hookMetaMethod) == "function" then
        hooker = _hookMetaMethod
    else
        -- synthesize: get metatable function and hook it with hookFunction
        local getmt = first(getrawmetatable, (debug and debug.getmetatable))
        if type(getmt) == "function" then
            hooker = function(obj, method, fn)
                local ok, mt = pcall(getmt, obj)
                if not ok or type(mt) ~= "table" or type(mt[method]) ~= "function" then
                    return nil
                end
                return _hookFunction(mt[method], fn)
            end
        else
            hooker = nil
        end
    end

    local ok, trampolineOrErr = pcall(function()
        if not hooker then error("no hooker available") end
        return hooker(game, "__namecall", function(...)
            local instance = select(1, ...)
            if _typeof(instance) ~= "Instance" then
                if type(nmcTrampoline) == "function" then
                    return nmcTrampoline(...)
                end
                return
            end

            local method = (_getNamecallMethod and _getNamecallMethod()) or "unknown"
            if method == "fireServer" then method = "FireServer" end
            if method == "invokeServer" then method = "InvokeServer" end

            if remotesViewing[instance.ClassName] and instance ~= remoteDataEvent and remoteMethods[method] then
                local remote = currentRemotes[instance]
                local vargs = { select(2, ...) }

                if not remote then
                    local ok2, r = pcall(function() return Remote.new(instance) end)
                    if ok2 and r then
                        remote = r
                        currentRemotes[instance] = remote
                    end
                end

                local remoteIgnored, remoteBlocked, argsIgnored, argsBlocked = false, false, false, false
                if remote then
                    local ok3, res
                    ok3, res = pcall(function() return remote.Ignored end)
                    if ok3 then remoteIgnored = res end
                    ok3, res = pcall(function() return remote.Blocked end)
                    if ok3 then remoteBlocked = res end

                    ok3, res = pcall(function() return remote:AreArgsIgnored(vargs) end)
                    if ok3 then argsIgnored = res end
                    ok3, res = pcall(function() return remote:AreArgsBlocked(vargs) end)
                    if ok3 then argsBlocked = res end
                end

                if eventSet and (not remoteIgnored and not argsIgnored) then
                    local call = {
                        script = (_getCallingScript and _getCallingScript((PROTOSMASHER_LOADED ~= nil and 2) or nil)) or nil,
                        args = vargs,
                        func = (_getInfo and _getInfo(3) and _getInfo(3).func) or nil
                    }

                    if remote then pcall(function() remote:IncrementCalls(call) end) end
                    pcall(function() remoteDataEvent:Fire(instance, call) end)
                end

                if remoteBlocked or argsBlocked then
                    return
                end
            end

            if type(nmcTrampoline) == "function" then
                return nmcTrampoline(...)
            end
        end)
    end)

    if ok and trampolineOrErr then
        nmcTrampoline = trampolineOrErr
    else
        nmcTrampoline = function(...) end
        if not ok then warn("[RemoteSpy] hook namecall failed:", trampolineOrErr) end
    end
end

-- hooking prototype methods (RemoteEvent.FireServer etc.)
local pcall_local = pcall
local function checkPermission(instance)
    return true
end

for _name, hook in pairs(methodHooks) do
    local originalMethod = nil

    if type(hook) ~= "function" then
        warn("[RemoteSpy] methodHooks entry for", _name, "is not a function; skipping")
    else
        local ok, ret = pcall(function()
            -- create closure to run when the method is called
            local hookClosure = _newcclosure(function(...)
                local instance = select(1, ...)
                if _typeof(instance) ~= "Instance" then
                    if type(originalMethod) == "function" then return originalMethod(...) end
                    return
                end

                local okperm = pcall_local(checkPermission, instance)
                if not okperm then
                    if type(originalMethod) == "function" then return originalMethod(...) end
                    return
                end

                if instance.ClassName == _name and remotesViewing[instance.ClassName] and instance ~= remoteDataEvent then
                    local remote = currentRemotes[instance]
                    local vargs = { select(2, ...) }

                    if not remote then
                        local ok2, r = pcall(function() return Remote.new(instance) end)
                        if ok2 and r then
                            remote = r
                            currentRemotes[instance] = remote
                        end
                    end

                    local remoteIgnored, argsIgnored = false, false
                    if remote then
                        local ok3, res
                        ok3, res = pcall(function() return remote.Ignored end)
                        if ok3 then remoteIgnored = res end
                        ok3, res = pcall(function() return remote:AreArgsIgnored(vargs) end)
                        if ok3 then argsIgnored = res end
                    end

                    if eventSet and (not remoteIgnored and not argsIgnored) then
                        local call = {
                            script = (_getCallingScript and _getCallingScript((PROTOSMASHER_LOADED ~= nil and 2) or nil)) or nil,
                            args = vargs,
                            func = (_getInfo and _getInfo(3) and _getInfo(3).func) or nil
                        }

                        if remote then pcall(function() remote:IncrementCalls(call) end) end
                        pcall(function() remoteDataEvent:Fire(instance, call) end)
                    end

                    local blocked = false
                    if remote then
                        local okb, rb = pcall(function() return remote.Blocked end)
                        if okb then blocked = rb end
                        local okb2, rb2 = pcall(function() return remote:AreArgsBlocked(vargs) end)
                        if okb2 and rb2 then blocked = true end
                    end

                    if blocked then
                        return
                    end
                end

                if type(originalMethod) == "function" then
                    return originalMethod(...)
                end
            end)

            return _hookFunction(hook, hookClosure)
        end)

        if ok and ret then
            originalMethod = ret
            -- register for cleanup if global oh exists
            if type(oh) == "table" and type(oh.Hooks) == "table" then
                oh.Hooks[originalMethod] = hook
            end
        else
            warn("[RemoteSpy] Failed to hook method for", _name, ":", ret)
        end
    end
end

-- expose module
RemoteSpy.RemotesViewing = remotesViewing
RemoteSpy.CurrentRemotes = currentRemotes
RemoteSpy.ConnectEvent = connectEvent
RemoteSpy.RequiredMethods = requiredMethods

return RemoteSpy
