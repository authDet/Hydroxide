-- modules/RemoteSpy.lua (fixed)

local RemoteSpy = {}
local Remote = import("objects/Remote")

-- safety: resolve hooks and helpers from global environment (expected to be provided by init.lua)
local _hookFunction = (hookFunction ~= nil) and hookFunction or (hookfunction or detour_function)
local _hookMetaMethod = (hookMetaMethod ~= nil) and hookMetaMethod or (hookmetamethod)
local _newCClosure = (newCClosure ~= nil) and newCClosure or (newcclosure)
local _getNamecallMethod = (getNamecallMethod ~= nil) and getNamecallMethod or (getnamecallmethod or get_namecall_method)
local _getCallingScript = (getCallingScript ~= nil) and getCallingScript or (getcallingscript or get_calling_script)
local _getInfo = (getInfo ~= nil) and getInfo or (debug and debug.getinfo) or getinfo
local _typeof = typeof or function(v) return type(v) end

-- required method names (for external checking)
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

-- quick guard: if critical functions missing, return safe empty module
local function missingCritical()
    if not _hookFunction then
        warn("[RemoteSpy] hookFunction not available — RemoteSpy disabled")
        return true
    end
    if not _newCClosure then
        warn("[RemoteSpy] newCClosure not available — RemoteSpy disabled")
        return true
    end
    if not _getInfo then
        warn("[RemoteSpy] getInfo not available — RemoteSpy disabled")
        return true
    end
    return false
end

if missingCritical() then
    -- export minimal safe interface so callers don't crash
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

-- method hooks: use prototype functions (these are methods, not called here)
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
    -- safe connect
    pcall(function() remoteDataEvent.Event:Connect(callback) end)
    eventSet = true
end

-- nmc trampoline (namecall hooking) — use hookMetaMethod if available, otherwise fall back to hookFunction on metamethod
local nmcTrampoline
do
    local hooker = _hookMetaMethod or function(obj, method, fn)
        -- try to emulate by hooking the metamethod using hookFunction on the metamethod function
        local getmt = (getrawmetatable or (debug and debug.getmetatable))
        if not getmt then
            warn("[RemoteSpy] No getrawmetatable/debug.getmetatable available to synthesize hookMetaMethod")
            return nil
        end
        local mt = getmt(obj)
        if not mt or not mt[method] then
            return nil
        end
        return _hookFunction(mt[method], fn)
    end

    local ok, trampolineOrErr = pcall(function()
        return hooker(game, "__namecall", function(...)
            local instance = select(1, ...)
            -- if instance is not a Roblox Instance, forward call
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
                    -- Remote.new may error; pcall to be safe
                    local ok2, r = pcall(function() return Remote.new(instance) end)
                    if ok2 and r then
                        remote = r
                        currentRemotes[instance] = remote
                    end
                end

                local remoteIgnored, remoteBlocked, argsIgnored, argsBlocked = false, false, false, false
                if remote then
                    -- support both :method and .method(self, ...) styles defensively
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

                    if remote and pcall(function() remote:IncrementCalls(call) end) then end
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
        -- if hooking failed, set to noop to avoid nil calls
        nmcTrampoline = function(...) end
        if not ok then warn("[RemoteSpy] hook namecall failed:", trampolineOrErr) end
    end
end

-- vuln fix and method hooking
local pcall_local = pcall

local function checkPermission(instance)
    -- placeholder for potential permission checks; keep simple to avoid breaking
    return true
end

for _name, hook in pairs(methodHooks) do
    local originalMethod = nil

    -- ensure hook target is a function
    if type(hook) ~= "function" then
        warn("[RemoteSpy] methodHooks entry for", _name, "is not a function; skipping")
    else
        local ok, ret = pcall(function()
            return _hookFunction(hook, _newCClosure and _newCClosure(function(...)
                local instance = select(1, ...)

                if _typeof(instance) ~= "Instance" then
                    if type(originalMethod) == "function" then
                        return originalMethod(...)
                    end
                    return
                end

                local okperm = pcall_local(checkPermission, instance)
                if not okperm then
                    if type(originalMethod) == "function" then
                        return originalMethod(...)
                    end
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

                        if remote and pcall(function() remote:IncrementCalls(call) end) then end
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
            end))
        end)

        if ok and ret then
            originalMethod = ret
            -- store hook mapping for cleanup: map originalMethod -> hook (the function we hooked)
            oh.Hooks[originalMethod] = hook
        else
            warn("[RemoteSpy] Failed to hook method for", _name, ":", ret)
        end
    end
end

-- expose
RemoteSpy.RemotesViewing = remotesViewing
RemoteSpy.CurrentRemotes = currentRemotes
RemoteSpy.ConnectEvent = connectEvent
RemoteSpy.RequiredMethods = requiredMethods

return RemoteSpy
