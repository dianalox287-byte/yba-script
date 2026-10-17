-- OVERDRIVE X | YBA
    -- syntax-complete build

    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local TweenService = game:GetService("TweenService")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local ProximityPromptService = game:GetService("ProximityPromptService")
    local CoreGui = game:GetService("CoreGui")
    local ScriptContext = game:GetService("ScriptContext")
    local HttpService = game:GetService("HttpService")
    local TeleportService = game:GetService("TeleportService")
    local SoundService = game:GetService("SoundService")
    local UserGameSettings = nil
    pcall(function() UserGameSettings = UserSettings():GetService("UserGameSettings") end)
    local TextChatService = game:GetService("TextChatService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = Players.LocalPlayer

    local function odxCompile(src)
        local compiler = loadstring or load
        if type(compiler) ~= "function" then
            pcall(function()
                local env = getgenv and getgenv()
                if type(env) == "table" then
                    compiler = env.loadstring or env.load or compiler
                end
            end)
        end
        if type(compiler) ~= "function" then
            return nil, "loadstring/load is nil"
        end
        local fn, err = compiler(src)
        if not fn then return nil, tostring(err) end
        return fn, nil
    end

    local function odxHttpGet(url)
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and type(body) == "string" and #body > 40 then return body end
        ok, body = pcall(function()
            if type(request) == "function" then
                local r = request({ Url = url, Method = "GET" })
                return r and (r.Body or r.body)
            end
            if type(http_request) == "function" then
                local r = http_request({ Url = url, Method = "GET" })
                return r and (r.Body or r.body)
            end
            return nil
        end)
        if ok and type(body) == "string" and #body > 40 then return body end
        return nil
    end

    local function odxLoadRemote(url)
        local src = odxHttpGet(url)
        if not src then return nil, "HttpGet failed: " .. tostring(url) end
        local fn, err = odxCompile(src)
        if not fn then return nil, "compile: " .. tostring(err) end
        local ok, result = pcall(fn)
        if not ok then return nil, "run: " .. tostring(result) end
        return result, nil
    end

    --// SBR SMART RECOVERY (v1.3)
    --// Keeps a stable runtime position when the character enters ragdoll/falling
    --// states. No saved coordinates are used; the safe point exists only for the
    --// current SBR run/server.
    _G.ODXSBRRecovery = _G.ODXSBRRecovery or {
        Active = false,
        SafeCFrame = nil,
        LastStable = 0,
        Recoveries = 0,
        Epoch = 0,
        StableSince = 0,
        ConfigRef = nil,
        CurrentTween = nil,
        MonitorConnection = nil,
    }

    _G.ODXStartSBRRecoveryMonitor = function()
        local state = _G.ODXSBRRecovery
        if state.MonitorConnection then
            return
        end

        state.MonitorConnection = RunService.Heartbeat:Connect(function()
            local cfg = state.ConfigRef
            if not cfg or not cfg.Enabled or not _G.ODXScriptActive then
                state.Active = false
                return
            end

            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hum or not hrp or hum.Health <= 0 then
                return
            end

            local stateType = hum:GetState()
            local ragdollState =
                stateType == Enum.HumanoidStateType.Ragdoll
                or stateType == Enum.HumanoidStateType.FallingDown
                or stateType == Enum.HumanoidStateType.Physics

            local safe = state.SafeCFrame
            local tooFarBelow = safe and (hrp.Position.Y < safe.Position.Y - 12)
            local catastrophicFall = math.abs(hrp.AssemblyLinearVelocity.Y) > 120
                and hrp.AssemblyLinearVelocity.Y < 0

            if not state.Active and (ragdollState or tooFarBelow or catastrophicFall) then
                if safe then
                    state.Active = true
                    state.Recoveries = state.Recoveries + 1
                    state.Epoch = state.Epoch + 1
                    state.StableSince = 0

                    if state.CurrentTween then
                        pcall(function() state.CurrentTween:Cancel() end)
                        state.CurrentTween = nil
                    end

                    pcall(function()
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                        hrp.CFrame = safe
                    end)
                    pcall(function()
                        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end)
                end
                return
            end

            if state.Active then
                -- Hold the last known good position until the humanoid is stable.
                if safe then
                    pcall(function()
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                        hrp.CFrame = safe
                    end)
                end

                local stableState =
                    stateType == Enum.HumanoidStateType.Running
                    or stateType == Enum.HumanoidStateType.RunningNoPhysics
                    or stateType == Enum.HumanoidStateType.GettingUp
                    or stateType == Enum.HumanoidStateType.Landed

                if stableState then
                    if state.StableSince == 0 then
                        state.StableSince = os.clock()
                    elseif os.clock() - state.StableSince >= 0.35 then
                        state.Active = false
                        state.StableSince = 0
                        state.LastStable = os.clock()
                    end
                else
                    state.StableSince = 0
                end
                return
            end

            -- Only refresh the safe point while the character is healthy and not
            -- undergoing a recovery. This is intentionally runtime-only.
            if stateType ~= Enum.HumanoidStateType.Ragdoll
                and stateType ~= Enum.HumanoidStateType.FallingDown
                and stateType ~= Enum.HumanoidStateType.Physics then
                local velocity = hrp.AssemblyLinearVelocity
                if velocity.Magnitude < 160 then
                    state.SafeCFrame = hrp.CFrame
                    state.LastStable = os.clock()
                end
            end
        end)
    end

    _G.ODXStopSBRRecoveryMonitor = function()
        local state = _G.ODXSBRRecovery
        if state.MonitorConnection then
            pcall(function() state.MonitorConnection:Disconnect() end)
            state.MonitorConnection = nil
        end
        state.Active = false
        state.SafeCFrame = nil
        state.CurrentTween = nil
        state.StableSince = 0
    end


    -- OVERDRIVE X loading screen
    -- Uses the Catbox logo with local caching when the executor exposes
    -- writefile/getcustomasset (Real Executor supports this path).
    local ODX_LOGO_URL = "https://files.catbox.moe/a31jks.png"
    local ODX_LOGO_FILE = "OVERDRIVE_X/logo_a31jks.png"
    local ODX_SPLASH_URL = "https://files.catbox.moe/gm3reh.png"
    local ODX_SPLASH_FILE = "OVERDRIVE_X/splash_gm3reh.png"
    local ODX_HALLOWEEN_THEME = true

    -- Halloween: Zane (pumpkin) only — embedded, written once to disk
    _G.ODXHalloweenAssetPaths = {
        Pumpkin = "OVERDRIVE_X/halloween_pumpkin.png",
    }

    _G.ODXHalloweenDecodeB64 = function(data)
        local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        data = data:gsub("[^" .. chars .. "=]", "")
        return (data:gsub("....", function(chunk)
            if #chunk < 2 then return "" end
            local a = chars:find(chunk:sub(1, 1), 1, true) or 1
            local b = chars:find(chunk:sub(2, 2), 1, true) or 1
            local c = chunk:sub(3, 3)
            local d = chunk:sub(4, 4)
            c = c == "=" and 1 or (chars:find(c, 1, true) or 1)
            d = d == "=" and 1 or (chars:find(d, 1, true) or 1)
            local n = (a - 1) * 262144 + (b - 1) * 4096 + (c - 1) * 64 + (d - 1)
            local o1 = math.floor(n / 65536) % 256
            local o2 = math.floor(n / 256) % 256
            local o3 = n % 256
            if chunk:sub(4, 4) == "=" then return string.char(o1, o2)
            elseif chunk:sub(3, 3) == "=" then return string.char(o1) end
            return string.char(o1, o2, o3)
        end))
    end

    _G.ODXHalloweenAssets = {}

    task.spawn(function()
        pcall(function()
            local path = _G.ODXHalloweenAssetPaths.Pumpkin
            if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("OVERDRIVE_X") then
                makefolder("OVERDRIVE_X")
            end
            if type(writefile) == "function" and type(isfile) == "function" and not isfile(path) then
                writefile(path, _G.ODXHalloweenDecodeB64("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"))
            end
            local getter = getcustomasset or getsynasset
            if type(getter) == "function" and type(isfile) == "function" and isfile(path) then
                local ok, asset = pcall(getter, path)
                if ok then _G.ODXHalloweenAssets.Pumpkin = asset end
            end
        end)
    end)

    local ODX_SOUND_URL = "https://files.catbox.moe/mjbv3y.mp3"
    local ODX_SOUND_FILE = "OVERDRIVE_X/loading_sound_mjbv3y"

    -- Script-owned audio settings. These control OVERDRIVE X audio separately
    -- from other Sound objects in the game. Roblox's global/master audio controls
    -- can still affect all in-game audio at the engine level.
    local ODX_AUDIO_SETTINGS_FILE = "OVERDRIVE_X/audio_settings.json"
    local ODXAudioSettings = {
        LoadingVolume = 0.35,
        PlayerVolume = 0.35,
    }

    _G.ODXFn_ODXLoadAudioSettings = function()
        if type(isfile) ~= "function" or type(readfile) ~= "function" then
            return
        end
        local okExists, exists = pcall(isfile, ODX_AUDIO_SETTINGS_FILE)
        if not okExists or not exists then
            return
        end
        local okRead, body = pcall(readfile, ODX_AUDIO_SETTINGS_FILE)
        if not okRead or type(body) ~= "string" or body == "" then
            return
        end
        local okDecode, data = pcall(function()
            return HttpService:JSONDecode(body)
        end)
        if okDecode and type(data) == "table" then
            ODXAudioSettings.LoadingVolume = math.clamp(tonumber(data.LoadingVolume) or 0.35, 0, 1)
            ODXAudioSettings.PlayerVolume = math.clamp(tonumber(data.PlayerVolume) or 0.35, 0, 1)
        end
    end

    _G.ODXFn_ODXSaveAudioSettings = function()
        if type(writefile) ~= "function" or type(HttpService.JSONEncode) ~= "function" then
            return
        end
        pcall(function()
            if type(isfolder) == "function" and type(makefolder) == "function" then
                local okFolder, exists = pcall(isfolder, "OVERDRIVE_X")
                if not okFolder or not exists then
                    pcall(makefolder, "OVERDRIVE_X")
                end
            elseif type(makefolder) == "function" then
                pcall(makefolder, "OVERDRIVE_X")
            end
            local encoded = HttpService:JSONEncode(ODXAudioSettings)
            writefile(ODX_AUDIO_SETTINGS_FILE, encoded)
        end)
    end

    _G.ODXFn_ODXLoadAudioSettings()

    _G.ODXFn_ODXGetOrCreateSoundGroup = function(name)
        local existing = SoundService:FindFirstChild(name)
        if existing and existing:IsA("SoundGroup") then
            return existing
        end
        local group = Instance.new("SoundGroup")
        group.Name = name
        group.Parent = SoundService
        return group
    end

    local ODXLoadingSoundGroup = _G.ODXFn_ODXGetOrCreateSoundGroup("OVERDRIVE_X_Loading")
    local ODXPlayerSoundGroup = _G.ODXFn_ODXGetOrCreateSoundGroup("OVERDRIVE_X_Player")
    pcall(function() ODXLoadingSoundGroup.Volume = ODXAudioSettings.LoadingVolume end)
    pcall(function() ODXPlayerSoundGroup.Volume = ODXAudioSettings.PlayerVolume end)

    -- Roblox's MasterVolume is the client-wide mixer, so Sound/SoundGroup
    -- volume cannot bypass a 0% Roblox volume. For zero-volume users, OVERDRIVE X
    -- can temporarily force the master mixer back to 100% and mute the game's
    -- own audio objects, leaving only OVERDRIVE X audio audible.
    local ODXIndependentAudio = {
        Active = false,
        ForcedMaster = false,
        SavedMaster = nil,
        MutedSounds = {},
        MutedAudioPlayers = {},
        AddedConnections = {},
        MonitorConnection = nil,
        WarnedUnsupported = false,
    }

    _G.ODXFn_ODXGetMasterVolume = function()
        if not UserGameSettings then
            return nil
        end

        local ok, value = pcall(function()
            return UserGameSettings.MasterVolume
        end)
        if ok and tonumber(value) ~= nil then
            return tonumber(value)
        end

        local env = {}
        pcall(function()
            if type(getgenv) == "function" then
                env = getgenv() or {}
            end
        end)
        local getter = rawget(env, "gethiddenproperty") or rawget(_G, "gethiddenproperty")
        if type(getter) == "function" then
            local hiddenOk, hiddenValue = pcall(getter, UserGameSettings, "MasterVolume")
            if hiddenOk and tonumber(hiddenValue) ~= nil then
                return tonumber(hiddenValue)
            end
        end

        return nil
    end

    _G.ODXFn_ODXTrySetMasterVolume = function(value)
        if not UserGameSettings then
            return false
        end

        local ok = pcall(function()
            UserGameSettings.MasterVolume = value
        end)
        if ok then
            return true
        end

        local env = {}
        pcall(function()
            if type(getgenv) == "function" then
                env = getgenv() or {}
            end
        end)
        local setter = rawget(env, "sethiddenproperty") or rawget(_G, "sethiddenproperty")
        if type(setter) == "function" then
            local hiddenOk = pcall(setter, UserGameSettings, "MasterVolume", value)
            if hiddenOk then
                return true
            end
        end

        return false
    end

    _G.ODXFn_ODXMuteGameAudioObject = function(obj)
        if not obj or not obj.Parent then
            return
        end
        if obj.Name:sub(1, 4) == "ODX_" then
            return
        end

        if obj:IsA("Sound") then
            if ODXIndependentAudio.MutedSounds[obj] == nil then
                ODXIndependentAudio.MutedSounds[obj] = obj.Volume
                pcall(function() obj.Volume = 0 end)
            end
        elseif obj:IsA("AudioPlayer") then
            if ODXIndependentAudio.MutedAudioPlayers[obj] == nil then
                local ok, volume = pcall(function() return obj.Volume end)
                if ok then
                    ODXIndependentAudio.MutedAudioPlayers[obj] = volume
                    pcall(function() obj.Volume = 0 end)
                end
            end
        end
    end

    _G.ODXFn_ODXScanGameAudio = function()
        pcall(function()
            for _, root in ipairs({Workspace, SoundService}) do
                for _, obj in ipairs(root:GetDescendants()) do
                    _G.ODXFn_ODXMuteGameAudioObject(obj)
                end
            end
        end)
    end

    _G.ODXFn_ODXEnableIndependentAudio = function()
        if ODXIndependentAudio.Active then
            return true
        end

        local master = _G.ODXFn_ODXGetMasterVolume()
        if master == nil then
            if not ODXIndependentAudio.WarnedUnsupported then
                ODXIndependentAudio.WarnedUnsupported = true
                warn("[OVERDRIVE X] Independent audio: MasterVolume is protected by Roblox; executor cannot override it.")
            end
            return false
        end

        ODXIndependentAudio.SavedMaster = master
        ODXIndependentAudio.Active = true

        -- Keep OVERDRIVE X music independent from Roblox's master volume:
        -- while the player is active, game audio is muted and the client mixer
        -- is temporarily kept at 100%. The original master volume is restored
        -- when playback stops.
        _G.ODXFn_ODXScanGameAudio()
        ODXIndependentAudio.ForcedMaster = _G.ODXFn_ODXTrySetMasterVolume(1)

        local function onAdded(obj)
            if ODXIndependentAudio.Active then
                _G.ODXFn_ODXMuteGameAudioObject(obj)
            end
        end
        table.insert(ODXIndependentAudio.AddedConnections, Workspace.DescendantAdded:Connect(onAdded))
        table.insert(ODXIndependentAudio.AddedConnections, SoundService.DescendantAdded:Connect(onAdded))

        ODXIndependentAudio.MonitorConnection = RunService.Heartbeat:Connect(function()
            if not ODXIndependentAudio.Active then
                return
            end
            if ODXIndependentAudio.ForcedMaster then
                local current = _G.ODXFn_ODXGetMasterVolume()
                if current ~= nil and current < 0.999 then
                    _G.ODXFn_ODXTrySetMasterVolume(1)
                end
            end
        end)

        if not ODXIndependentAudio.ForcedMaster and not ODXIndependentAudio.WarnedUnsupported then
            ODXIndependentAudio.WarnedUnsupported = true
            warn("[OVERDRIVE X] Independent audio: executor cannot override Roblox MasterVolume; MP3 will follow Roblox volume.")
        end

        return ODXIndependentAudio.ForcedMaster
    end

    _G.ODXFn_ODXDisableIndependentAudio = function()
        if not ODXIndependentAudio.Active then
            return
        end

        if ODXIndependentAudio.MonitorConnection then
            pcall(function() ODXIndependentAudio.MonitorConnection:Disconnect() end)
            ODXIndependentAudio.MonitorConnection = nil
        end
        for _, connection in ipairs(ODXIndependentAudio.AddedConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(ODXIndependentAudio.AddedConnections)

        for obj, volume in pairs(ODXIndependentAudio.MutedSounds) do
            if obj and obj.Parent then
                pcall(function() obj.Volume = volume end)
            end
        end
        table.clear(ODXIndependentAudio.MutedSounds)

        for obj, volume in pairs(ODXIndependentAudio.MutedAudioPlayers) do
            if obj and obj.Parent then
                pcall(function() obj.Volume = volume end)
            end
        end
        table.clear(ODXIndependentAudio.MutedAudioPlayers)

        if ODXIndependentAudio.ForcedMaster and ODXIndependentAudio.SavedMaster ~= nil then
            _G.ODXFn_ODXTrySetMasterVolume(ODXIndependentAudio.SavedMaster)
        end

        ODXIndependentAudio.Active = false
        ODXIndependentAudio.ForcedMaster = false
        ODXIndependentAudio.SavedMaster = nil
    end

    local ODXLoadingFinished = Instance.new("BindableEvent")
    local ODXLoadingFinishedFlag = false

    _G.ODXFn_ODXGetAsset = function(path)
        local getter = rawget(getgenv and getgenv() or _G, "getcustomasset")
            or rawget(getgenv and getgenv() or _G, "getsynasset")
        if type(getter) ~= "function" then
            getter = getcustomasset or getsynasset
        end
        if type(getter) == "function" then
            local ok, asset = pcall(getter, path)
            if ok and asset then
                return asset
            end
        end
        return nil
    end

    _G.ODXFn_ODXEnsureLogo = function()
        if type(writefile) ~= "function" then
            return nil
        end
        local exists = false
        if type(isfile) == "function" then
            local ok, result = pcall(isfile, ODX_LOGO_FILE)
            exists = ok and result == true
        end
        if not exists then
            local ok, body = pcall(function()
                return game:HttpGet(ODX_LOGO_URL)
            end)
            if ok and type(body) == "string" and #body > 1000 then
                pcall(function()
                    if type(isfolder) == "function" and type(makefolder) == "function" then
                        local folderOk, folderExists = pcall(isfolder, "OVERDRIVE_X")
                        if not folderOk or not folderExists then
                            pcall(makefolder, "OVERDRIVE_X")
                        end
                    end
                    writefile(ODX_LOGO_FILE, body)
                end)
            end
        end
        return _G.ODXFn_ODXGetAsset(ODX_LOGO_FILE)
    end

    _G.ODXFn_ODXEnsureSplash = function()
        if type(writefile) ~= "function" then
            return nil
        end
        local exists = false
        if type(isfile) == "function" then
            local ok, result = pcall(isfile, ODX_SPLASH_FILE)
            exists = ok and result == true
        end
        if not exists then
            local ok, body = pcall(function()
                return game:HttpGet(ODX_SPLASH_URL)
            end)
            if ok and type(body) == "string" and #body > 1000 then
                pcall(function()
                    if type(isfolder) == "function" and type(makefolder) == "function" then
                        local folderOk, folderExists = pcall(isfolder, "OVERDRIVE_X")
                        if not folderOk or not folderExists then
                            pcall(makefolder, "OVERDRIVE_X")
                        end
                    end
                    writefile(ODX_SPLASH_FILE, body)
                end)
            end
        end
        return _G.ODXFn_ODXGetAsset(ODX_SPLASH_FILE)
    end

    _G.ODXFn_ODXGetSoundAsset = function()
        if ODX_SOUND_URL == "" or type(writefile) ~= "function" then
            return nil
        end

        local extension = ODX_SOUND_URL:match("%.([%w]+)$") or "mp3"
        extension = extension:lower()
        if extension ~= "mp3" and extension ~= "ogg" and extension ~= "wav" then
            extension = "mp3"
        end
        local file = ODX_SOUND_FILE .. "." .. extension
        -- Always (re)download requested splash sound so a previous cache cannot stick
        local ok, body = pcall(function()
            return game:HttpGet(ODX_SOUND_URL)
        end)
        if ok and type(body) == "string" and #body > 500 then
            pcall(function()
                if type(isfolder) == "function" and type(makefolder) == "function" then
                    local folderOk, folderExists = pcall(isfolder, "OVERDRIVE_X")
                    if not folderOk or not folderExists then
                        pcall(makefolder, "OVERDRIVE_X")
                    end
                end
                writefile(file, body)
            end)
        end

        local asset = _G.ODXFn_ODXGetAsset(file)
        if asset then
            return asset
        end
        -- Last resort: some executors accept the remote URL as SoundId
        return ODX_SOUND_URL
    end

    _G.ODXFn_ODXCreateLoading = function()
        local old = CoreGui:FindFirstChild("OVERDRIVE_X_Loading")
        if old then
            old:Destroy()
        end

        local gui = Instance.new("ScreenGui")
        gui.Name = "OVERDRIVE_X_Loading"
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 999999
        gui.ResetOnSpawn = false
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.Parent = CoreGui

        local function odxTween(obj, info, props)
            local tw = TweenService:Create(obj, info, props)
            tw:Play()
            return tw
        end

        -- Centered splash image (not fullscreen) + requested sound
        local splashAsset = nil
        pcall(function() splashAsset = _G.ODXFn_ODXEnsureSplash() end)
        local soundAsset = nil
        pcall(function() soundAsset = _G.ODXFn_ODXGetSoundAsset() end)

        local dim = Instance.new("Frame")
        dim.Name = "ODXDim"
        dim.Size = UDim2.fromScale(1, 1)
        dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        dim.BackgroundTransparency = 1
        dim.BorderSizePixel = 0
        dim.ZIndex = 1
        dim.Parent = gui

        local splashImg = Instance.new("ImageLabel")
        splashImg.Name = "ODXSplashImage"
        splashImg.AnchorPoint = Vector2.new(0.5, 0.5)
        splashImg.Position = UDim2.fromScale(0.5, 0.5)
        -- Centered card size (not full screen)
        splashImg.Size = UDim2.fromOffset(720, 405)
        splashImg.BackgroundTransparency = 1
        splashImg.BorderSizePixel = 0
        splashImg.ScaleType = Enum.ScaleType.Fit
        splashImg.ImageTransparency = 1
        splashImg.ZIndex = 2
        if splashAsset then
            splashImg.Image = splashAsset
        else
            splashImg.Image = ODX_SPLASH_URL
        end
        splashImg.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = splashImg

        local loadingSound = nil
        if soundAsset then
            loadingSound = Instance.new("Sound")
            loadingSound.Name = "ODX_LoadingSound"
            loadingSound.SoundId = soundAsset
            loadingSound.Volume = 1
            loadingSound.Looped = false
            loadingSound.RollOffMode = Enum.RollOffMode.Linear
            loadingSound.RollOffMaxDistance = 100000
            loadingSound.SoundGroup = ODXLoadingSoundGroup
            -- Force audible intro (ignore muted saved volume for splash)
            pcall(function() ODXLoadingSoundGroup.Volume = 1 end)
            loadingSound.Volume = 1
            loadingSound.Parent = SoundService
            pcall(_G.ODXFn_ODXEnableIndependentAudio)
            -- Some executors need a short delay before Play after setting SoundId
            task.wait(0.1)
        end

        -- Smooth fade IN
        odxTween(dim, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.35})
        odxTween(splashImg, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = 0})
        if loadingSound then
            pcall(function() loadingSound:Play() end)
        end

        -- Hold for sound duration (fallback if TimeLength not ready)
        local hold = 6
        if loadingSound then
            local t0 = os.clock()
            while (not loadingSound.IsLoaded or loadingSound.TimeLength <= 0) and os.clock() - t0 < 3 do
                task.wait(0.05)
            end
            if loadingSound.TimeLength and loadingSound.TimeLength > 0.5 then
                hold = math.clamp(loadingSound.TimeLength - 0.85, 2, 25)
            end
        end
        task.wait(hold)

        -- Smooth fade OUT
        odxTween(splashImg, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {ImageTransparency = 1})
        odxTween(dim, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1})
        task.wait(0.9)

        pcall(function()
            if loadingSound then
                loadingSound:Stop()
                loadingSound:Destroy()
            end
            pcall(_G.ODXFn_ODXDisableIndependentAudio)
            gui:Destroy()
        end)

        ODXLoadingFinishedFlag = true
        pcall(function() ODXLoadingFinished:Fire() end)
    end

    task.spawn(function()
        local ok, err = xpcall(_G.ODXFn_ODXCreateLoading, debug.traceback)
        if not ok then
            warn("[OVERDRIVE X] Loading screen error: " .. tostring(err))
            pcall(function()
                local stuck = CoreGui:FindFirstChild("OVERDRIVE_X_Loading")
                if stuck then stuck:Destroy() end
            end)
            ODXLoadingFinishedFlag = true
            pcall(function() ODXLoadingFinished:Fire() end)
        end
    end)

    -- Hard timeout safety: even if an executor breaks a tween/event, never deadlock the script.
    -- Splash (sound length) + loading card need more headroom than the old 10s.
    task.delay(35, function()
        if not ODXLoadingFinishedFlag then
            warn("[OVERDRIVE X] Loading screen timeout; continuing without blocking the main UI.")
            ODXLoadingFinishedFlag = true
            pcall(function()
                local stuck = CoreGui:FindFirstChild("OVERDRIVE_X_Loading")
                if stuck then stuck:Destroy() end
            end)
            pcall(function() ODXLoadingFinished:Fire() end)
        end
    end)

    -- Yield so loading screen can finish painting before heavy UI compile
    task.wait(0.15)

    local Library, libErr = odxLoadRemote("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua")
    if not Library then
        Library, libErr = odxLoadRemote("https://raw.githubusercontent.com/deividcomsono/Obsidian/main/Library.lua")
    end
    if not Library then
        warn("[OVERDRIVE X] Failed to load Obsidian Library: " .. tostring(libErr))
        return
    end

    task.wait()

    local SaveManager = select(1, odxLoadRemote("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/addons/SaveManager.lua"))
        or select(1, odxLoadRemote("https://raw.githubusercontent.com/deividcomsono/Obsidian/main/addons/SaveManager.lua"))

    local ThemeManager = select(1, odxLoadRemote("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/addons/ThemeManager.lua"))
        or select(1, odxLoadRemote("https://raw.githubusercontent.com/deividcomsono/Obsidian/main/addons/ThemeManager.lua"))

    if ThemeManager and Library then
        pcall(function() ThemeManager:SetLibrary(Library) end)
    end

    task.wait()

    local ItemConfig

    local activeItemTween = nil

    _G.ODXFn_CancelItemTween = function()
        if activeItemTween then
            pcall(function() activeItemTween:Cancel() end)
            activeItemTween = nil
        end
    end

    _G.ODXFn_ItemTP = function(cf)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp or not cf then return nil end
        cf = typeof(cf) == "CFrame" and cf or CFrame.new(cf)
        _G.ODXFn_CancelItemTween()

        local speed = ItemConfig.ItemTweenSpeed or 300
        local maxStep = 14
        local finished = false
        local done = Instance.new("BindableEvent")
        local conn
        conn = RunService.Heartbeat:Connect(function(dt)
            if not hrp.Parent or not ItemConfig.Enabled then
                finished = true
                conn:Disconnect()
                done:Fire()
                return
            end
            local pos = hrp.Position
            local goal = cf.Position
            local offset = goal - pos
            local dist = offset.Magnitude
            if dist <= 2 then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                hrp.CFrame = CFrame.new(goal)
                finished = true
                conn:Disconnect()
                done:Fire()
                return
            end
            local step = math.min(dist, speed * math.clamp(dt, 0.008, 0.05), maxStep)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.CFrame = CFrame.new(pos + offset.Unit * step)
        end)
        local tween = {
            PlaybackState = Enum.PlaybackState.Playing,
            Completed = done.Event,
            Play = function() end,
            Cancel = function()
                finished = true
                if conn then conn:Disconnect() end
                done:Fire()
            end,
        }
        task.spawn(function()
            while not finished and ItemConfig.Enabled do
                task.wait(0.05)
            end
            tween.PlaybackState = Enum.PlaybackState.Completed
        end)
        activeItemTween = tween
        return tween
    end

    local activeSellerTween = nil

    _G.ODXFn_CancelSellerTween = function()
        if activeSellerTween then
            pcall(function() activeSellerTween:Cancel() end)
            activeSellerTween = nil
        end
    end

    _G.ODXFn_SellerTP = function(cf)
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp or not cf then
            return false
        end

        cf = typeof(cf) == "CFrame" and cf or CFrame.new(cf)
        _G.ODXFn_CancelSellerTween()

        local distance = (hrp.Position - cf.Position).Magnitude
        local speed = 120
        local duration = math.clamp(distance / speed, 0.03, 10)

        local tween = TweenService:Create(
            hrp,
            TweenInfo.new(duration, Enum.EasingStyle.Linear),
            {CFrame = cf}
        )

        activeSellerTween = tween
        tween:Play()
        tween.Completed:Wait()

        if activeSellerTween == tween then
            activeSellerTween = nil
        end

        return true
    end

    local Connections = {}
    local ScriptActive = true
    local TerminalLogs = {}

    _G.ODXFn_fnError = function(msg)
        table.insert(TerminalLogs, "[" .. os.date("%H:%M:%S") .. "] " .. tostring(msg))
        if #TerminalLogs > 15 then
            table.remove(TerminalLogs, 1)
        end
    end

    table.insert(Connections, ScriptContext.Error:Connect(function(message, _, scriptObj)
        if ScriptActive and (scriptObj == nil or tostring(scriptObj) == "") then
            _G.ODXFn_fnError("Script Error: " .. tostring(message))
        end
    end))

    -- Wait for splash, but never deadlock (timeout 40s)
    if not ODXLoadingFinishedFlag then
        local t0 = os.clock()
        while not ODXLoadingFinishedFlag and os.clock() - t0 < 40 do
            task.wait(0.1)
        end
        ODXLoadingFinishedFlag = true
    end
    pcall(function() ODXLoadingFinished:Destroy() end)

    local Window
    local okWin, winOrErr = pcall(function()
        return Library:CreateWindow({
            Title = "OVERDRIVE X | YBA",
            Footer = "by stendexe",
            ToggleKeybind = Enum.KeyCode.RightShift,
        })
    end)
    if not okWin or not winOrErr then
        warn("[OVERDRIVE X] CreateWindow failed: " .. tostring(winOrErr))
        return
    end
    Window = winOrErr
    task.wait()

    --// HOME: Executor check
    local DiscordInvite = "https://discord.gg/FFYMQ3Han"
    local function getExecutorName()
        local ok, name = pcall(function()
            if identifyexecutor then return identifyexecutor() end
            if getexecutorname then return getexecutorname() end
            if syn and syn.request then return "Synapse" end
        end)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
        return "Unknown"
    end

    local executorName = getExecutorName()
    local executorLower = string.lower(tostring(executorName or "Unknown"))

    -- Kick clearly broken free executors. Real is allowed.
    local badExecutors = { "solara", "jjsploit", "xeno" }
    local isBad = false
    for _, bad in ipairs(badExecutors) do
        if executorLower:find(bad, 1, true) then
            isBad = true
            break
        end
    end

    if isBad then
        pcall(function()
            if setclipboard then setclipboard(DiscordInvite) end
        end)
        pcall(function()
            LocalPlayer:Kick("Unsupported executor. Join discord for supported list: " .. DiscordInvite)
        end)
        return
    end

    local goodExecutors = { "potassium", "madium", "nexomia", "delta", "arceus", "real", "wave", "seliware" }
    local isGood = false
    for _, good in ipairs(goodExecutors) do
        if executorLower:find(good, 1, true) then
            isGood = true
            break
        end
    end


    -- Zane only (no web/bat/popup chrome)
    pcall(function()
        local mainFrame = Library.ScreenGui and Library.ScreenGui:FindFirstChild("Main")
        if not mainFrame then return end
        _G.ODXHalloweenMainFrame = mainFrame

        local pumpkinAsset = _G.ODXHalloweenAssets and _G.ODXHalloweenAssets.Pumpkin
        if pumpkinAsset then
            local pumpkin = Instance.new("ImageButton")
            pumpkin.Name = "ZaneThePumpkin"
            pumpkin.AnchorPoint = Vector2.new(0, 1)
            pumpkin.Position = UDim2.new(0, 8, 1, -8)
            pumpkin.Size = UDim2.fromOffset(62, 56)
            pumpkin.BackgroundTransparency = 1
            pumpkin.Image = pumpkinAsset
            pumpkin.ImageTransparency = 0.02
            pumpkin.ScaleType = Enum.ScaleType.Fit
            pumpkin.AutoButtonColor = false
            pumpkin.Active = true
            pumpkin.Selectable = true
            pumpkin.ZIndex = 100
            pumpkin.Parent = mainFrame

            pumpkin.MouseButton1Click:Connect(function()
                pcall(function()
                    _G.ODXPumpkinClickAnimationSerial = (_G.ODXPumpkinClickAnimationSerial or 0) + 1
                    local serial = _G.ODXPumpkinClickAnimationSerial

                    if _G.ODXPumpkinPressTween then
                        pcall(function() _G.ODXPumpkinPressTween:Cancel() end)
                    end
                    if _G.ODXPumpkinReleaseTween then
                        pcall(function() _G.ODXPumpkinReleaseTween:Cancel() end)
                    end

                    pcall(function() _G.ODXPumpkinShowClickMessage(pumpkin) end)

                    local originalSize = UDim2.fromOffset(62, 56)
                    pumpkin.Size = originalSize
                    pumpkin.Rotation = 0

                    local pressTween = TweenService:Create(
                        pumpkin,
                        TweenInfo.new(0.055, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                        {
                            Size = UDim2.fromOffset(54, 49),
                            Rotation = -8,
                        }
                    )
                    _G.ODXPumpkinPressTween = pressTween
                    pressTween:Play()

                    task.delay(0.06, function()
                        if serial ~= _G.ODXPumpkinClickAnimationSerial then
                            return
                        end
                        if not pumpkin or not pumpkin.Parent then
                            return
                        end
                        local releaseTween = TweenService:Create(
                            pumpkin,
                            TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                            {
                                Size = originalSize,
                                Rotation = 0,
                            }
                        )
                        _G.ODXPumpkinReleaseTween = releaseTween
                        releaseTween:Play()
                    end)
                end)
            end)
        end
    end)

    local Tabs = {
        Home = Window:AddTab({ Name = "Home", Icon = "home" }),
        Main = Window:AddTab({ Name = "Main (Farm)", Icon = "swords" }),
        Items = Window:AddTab({ Name = "Items", Icon = "package" }),
        Character = Window:AddTab({ Name = "Character", Icon = "user" }),
        Players = Window:AddTab({ Name = "Players & ESP", Icon = "users" }),
        SBR = Window:AddTab({ Name = "SBR", Icon = "map" }),
        QOL = Window:AddTab({ Name = "QOL", Icon = "sparkles" }),
        System = Window:AddTab({ Name = "System", Icon = "monitor" }),
        Config = Window:AddTab({ Name = "Config", Icon = "folder-cog" }),
        Credits = Window:AddTab({ Name = "Credits", Icon = "info" }),
    }

    --// HOME TAB
    local HomeLeft = Tabs.Home:AddGroupbox({ Side = "Left", Name = "Discord" })

    -- Real Discord invite screenshot
    local inviteImage = Instance.new("ImageLabel")
    inviteImage.Name = "DiscordInvite"
    inviteImage.Size = UDim2.new(1, -8, 0, 160)
    inviteImage.BackgroundTransparency = 1
    inviteImage.ScaleType = Enum.ScaleType.Fit
    inviteImage.Image = "rbxassetid://0"

    -- Parent into the groupbox frame properly
    local targetParent = HomeLeft
    if type(HomeLeft) == "table" then
        targetParent = HomeLeft.Container or HomeLeft.Holder or HomeLeft.Frame or HomeLeft
    end
    if typeof(targetParent) == "Instance" then
        inviteImage.Parent = targetParent
    else
        -- Fallback: find the groupbox UI after a short delay
        task.spawn(function()
            task.wait(0.3)
            local main = Library.ScreenGui and Library.ScreenGui:FindFirstChild("Main")
            if main then
                for _, d in ipairs(main:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Text == "Discord" then
                        local box = d.Parent
                        if box and box:IsA("Frame") then
                            inviteImage.Parent = box
                            break
                        end
                    end
                end
            end
        end)
    end

    task.spawn(function()
        pcall(function()
            local url = "https://files.catbox.moe/lwtdsw.png"
            if type(writefile) == "function" and type(getcustomasset) == "function" then
                local imgPath = "OVERDRIVE_X/discord_invite_v2.png"
                if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("OVERDRIVE_X") then
                    makefolder("OVERDRIVE_X")
                end
                -- Force re-download
                local data = game:HttpGet(url)
                if data then
                    writefile(imgPath, data)
                end
                if type(isfile) == "function" and isfile(imgPath) then
                    inviteImage.Image = getcustomasset(imgPath)
                end
            end
        end)
    end)

    HomeLeft:AddLabel("Join our discord!")

    HomeLeft:AddButton({
        Text = "Copy Link",
        Func = function()
            pcall(function()
                if setclipboard then setclipboard(DiscordInvite) end
            end)
            Library:Notify("Discord link copied")
        end,
    })

    local HomeExec = Tabs.Home:AddGroupbox({ Side = "Left", Name = "Executor" })
    HomeExec:AddLabel("Executor: " .. tostring(executorName or "Unknown"))
    if isGood then
        HomeExec:AddLabel("Status: Supported")
    else
        HomeExec:AddLabel("Status: Unknown (allowed)")
    end

    local HomePlayer = Tabs.Home:AddGroupbox({ Side = "Right", Name = "Player" })
    HomePlayer:AddLabel("Display Name: " .. LocalPlayer.DisplayName)
    HomePlayer:AddLabel("Username: " .. LocalPlayer.Name)
    HomePlayer:AddLabel("User ID: " .. tostring(LocalPlayer.UserId))
    HomePlayer:AddLabel("Account Age: " .. tostring(LocalPlayer.AccountAge) .. " days")
    HomePlayer:AddLabel("Team: " .. (LocalPlayer.Team and LocalPlayer.Team.Name or "None"))

    local HomeServer = Tabs.Home:AddGroupbox({ Side = "Right", Name = "Server" })
    local playersHomeLabel = HomeServer:AddLabel("Players: " .. #Players:GetPlayers())
    local placeHomeLabel = HomeServer:AddLabel("Place ID: " .. tostring(game.PlaceId))
    local jobHomeLabel = HomeServer:AddLabel("Job ID: " .. tostring(game.JobId):sub(1, 12) .. "...")

    task.spawn(function()
        while true do
            task.wait(2)
            pcall(function()
                if playersHomeLabel and playersHomeLabel.SetText then
                    playersHomeLabel:SetText("Players: " .. #Players:GetPlayers())
                end
            end)
        end
    end)

    local LeftMainGroup = Tabs.Main:AddGroupbox({ Side = "Left", Name = "Farm Settings" })
    local RightMainGroup = Tabs.Main:AddGroupbox({ Side = "Right", Name = "Combat Settings" })
    LeftMainGroup:AddLabel("REQUIRES STAND TO WORK CORRECTLY")

    -- Zane's speech bubble should never remain visible while the OVERDRIVE X menu is hidden.
    if not _G.ODXZaneBubbleVisibilityWatcher then
        _G.ODXZaneBubbleVisibilityWatcher = true
        task.spawn(function()
            while ScriptActive do
                task.wait(0.08)

                local main = _G.ODXHalloweenMainFrame
                local menuVisible = true

                pcall(function()
                    if Library.Toggled == false then
                        menuVisible = false
                    end
                end)

                pcall(function()
                    if main and main.Parent and main.Visible == false then
                        menuVisible = false
                    end
                end)

                if not menuVisible and type(_G.ODXPumpkinDestroyBubble) == "function" then
                    pcall(_G.ODXPumpkinDestroyBubble)
                end
            end

            _G.ODXZaneBubbleVisibilityWatcher = nil
        end)
    end

    -- Continue with QOL controls.

    -- QOL / Performance settings
    local QOLConfig = {
        HalloweenTheme = true,
        BlackScreen = false,
        PotatoGraphics = false,
        PotatoMode = "Off",
    }

    local QOLState = {
        Rendering3D = true,
        GlobalShadows = nil,
        TerrainDecoration = nil,
        Effects = {},
        QualityLevel = nil,
        Captured = false,
    }

    _G.ODXFn_QOLSet3DRendering = function(enabled)
        pcall(function()
            RunService:Set3dRenderingEnabled(enabled)
        end)
    end

    _G.ODXQOLCaptureState = function()
        if QOLState.Captured then return end
        QOLState.Captured = true

        pcall(function()
            if settings and settings().Rendering then
                QOLState.QualityLevel = settings().Rendering.QualityLevel
            end
        end)
        pcall(function()
            QOLState.GlobalShadows = Lighting.GlobalShadows
        end)
        pcall(function()
            local terrain = Workspace:FindFirstChildOfClass("Terrain")
            if terrain then
                QOLState.TerrainDecoration = terrain.Decoration
            end
        end)

        table.clear(QOLState.Effects)
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
                or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles")
                or obj:IsA("PostEffect") then
                local ok, old = pcall(function() return obj.Enabled end)
                if ok then
                    QOLState.Effects[obj] = old
                end
            end
        end
    end

    _G.ODXQOLRestoreState = function()
        if not QOLState.Captured then return end
        if QOLState.QualityLevel then
            pcall(function() settings().Rendering.QualityLevel = QOLState.QualityLevel end)
        end
        if QOLState.GlobalShadows ~= nil then
            pcall(function() Lighting.GlobalShadows = QOLState.GlobalShadows end)
        end
        pcall(function()
            local terrain = Workspace:FindFirstChildOfClass("Terrain")
            if terrain and QOLState.TerrainDecoration ~= nil then
                terrain.Decoration = QOLState.TerrainDecoration
            end
        end)
        for obj, old in pairs(QOLState.Effects) do
            if obj and obj.Parent then
                pcall(function() obj.Enabled = old end)
            end
        end
        table.clear(QOLState.Effects)
        QOLState.Captured = false
    end

    _G.ODXQOLDisableEffectClass = function(className)
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA(className) then
                pcall(function() obj.Enabled = false end)
            end
        end
    end

    _G.ODXQOLApplyPotato = function(mode)
        mode = mode or "Off"
        if mode == "Off" then
            _G.ODXQOLRestoreState()
            QOLConfig.PotatoGraphics = false
            QOLConfig.PotatoMode = "Off"
            return
        end

        -- Switching tiers starts from the original graphics state, so a weaker
        -- mode never inherits disabled effects from a stronger mode.
        if QOLState.Captured and QOLConfig.PotatoMode ~= mode then
            _G.ODXQOLRestoreState()
        end
        _G.ODXQOLCaptureState()
        QOLConfig.PotatoGraphics = true
        QOLConfig.PotatoMode = mode

        local quality = Enum.QualityLevel.Level10
        if mode == "Light" then
            quality = Enum.QualityLevel.Level08
        elseif mode == "Medium" then
            quality = Enum.QualityLevel.Level04
        elseif mode == "High" then
            quality = Enum.QualityLevel.Level01
        end

        pcall(function() settings().Rendering.QualityLevel = quality end)

        -- LIGHT: small visual cut, keeps the game looking mostly normal.
        if mode == "Light" then
            pcall(function() Lighting.GlobalShadows = false end)
            pcall(function()
                local terrain = Workspace:FindFirstChildOfClass("Terrain")
                if terrain then terrain.Decoration = true end
            end)
            _G.ODXQOLDisableEffectClass("PostEffect")
            return
        end

        -- MEDIUM: removes the expensive world effects while retaining most geometry.
        pcall(function() Lighting.GlobalShadows = false end)
        pcall(function()
            local terrain = Workspace:FindFirstChildOfClass("Terrain")
            if terrain then terrain.Decoration = false end
        end)
        _G.ODXQOLDisableEffectClass("ParticleEmitter")
        _G.ODXQOLDisableEffectClass("Trail")
        _G.ODXQOLDisableEffectClass("Beam")
        _G.ODXQOLDisableEffectClass("PostEffect")

        if mode == "Medium" then
            return
        end

        -- HIGH: maximum visual reduction / lowest quality.
        _G.ODXQOLDisableEffectClass("Smoke")
        _G.ODXQOLDisableEffectClass("Fire")
        _G.ODXQOLDisableEffectClass("Sparkles")
    end

    local QOLGroup = Tabs.QOL:AddGroupbox({ Side = "Left", Name = "Performance / Multi Account" })

    local ODXHalloweenOriginalScheme = {}
    if Library and Library.Scheme then
        for key, value in pairs(Library.Scheme) do
            ODXHalloweenOriginalScheme[key] = value
        end
    end

    if ThemeManager and Library then
        pcall(function()
            ThemeManager.BuiltInThemes["Halloween"] = {
                19,
                {
                    FontColor = "fff4e6",
                    MainColor = "211225",
                    AccentColor = "ff6a00",
                    BackgroundColor = "100812",
                    OutlineColor = "4a2455",
                    BackgroundImage = "",
                },
            }
        end)
    end

    _G.ODXApplyHalloweenTheme = function(enabled)
        QOLConfig.HalloweenTheme = enabled == true
        if ThemeManager and Library then
            if QOLConfig.HalloweenTheme then
                pcall(function() ThemeManager:ApplyTheme("Halloween") end)
            else
                pcall(function()
                    for key, value in pairs(ODXHalloweenOriginalScheme) do
                        Library.Scheme[key] = value
                    end
                    Library:UpdateColorsUsingRegistry()
                end)
            end
        end
        pcall(function()
            Library:Notify(QOLConfig.HalloweenTheme and "Halloween Theme: ON" or "Halloween Theme: OFF")
        end)
    end

    QOLGroup:AddLabel("HALLOWEEN EDITION: ORANGE / PURPLE / BLACK")
    pcall(function() _G.ODXApplyHalloweenTheme(true) end)

    QOLGroup:AddToggle("BlackScreenToggle", {
        Text = "Black Screen",
        Default = false,
        Tooltip = "Disables 3D rendering while keeping the OVERDRIVE X menu visible.",
        Callback = function(Value)
            QOLConfig.BlackScreen = Value
            _G.ODXFn_QOLSet3DRendering(not Value)
            Library:Notify(Value and "Black Screen: ON — menu remains visible" or "Black Screen: OFF")
        end,
    })
    QOLGroup:AddLabel("BLACK SCREEN: 3D OFF / UI ON")

    _G.ODXPotatoLightToggle = nil
    _G.ODXPotatoMediumToggle = nil
    _G.ODXPotatoHighToggle = nil
    _G.ODXPotatoUpdating = false

    _G.ODXSetPotatoMode = function(mode, value)
        if _G.ODXPotatoUpdating then return end
        _G.ODXPotatoUpdating = true

        if mode == "Light" and value then
            if _G.ODXPotatoMediumToggle then pcall(function() _G.ODXPotatoMediumToggle:SetValue(false) end) end
            if _G.ODXPotatoHighToggle then pcall(function() _G.ODXPotatoHighToggle:SetValue(false) end) end
            _G.ODXQOLApplyPotato("Light")
        elseif mode == "Medium" and value then
            if _G.ODXPotatoLightToggle then pcall(function() _G.ODXPotatoLightToggle:SetValue(false) end) end
            if _G.ODXPotatoHighToggle then pcall(function() _G.ODXPotatoHighToggle:SetValue(false) end) end
            _G.ODXQOLApplyPotato("Medium")
        elseif mode == "High" and value then
            if _G.ODXPotatoLightToggle then pcall(function() _G.ODXPotatoLightToggle:SetValue(false) end) end
            if _G.ODXPotatoMediumToggle then pcall(function() _G.ODXPotatoMediumToggle:SetValue(false) end) end
            _G.ODXQOLApplyPotato("High")
        elseif not value then
            if QOLConfig.PotatoMode == mode then
                _G.ODXQOLApplyPotato("Off")
            end
        end

        _G.ODXPotatoUpdating = false
    end

    _G.ODXPotatoLightToggle = QOLGroup:AddToggle("PotatoLightToggle", {
        Text = "Light Potato",
        Default = false,
        Tooltip = "Light optimization: lower quality + shadows off, while keeping terrain and most effects.",
        Callback = function(Value) _G.ODXSetPotatoMode("Light", Value) end,
    })

    _G.ODXPotatoMediumToggle = QOLGroup:AddToggle("PotatoMediumToggle", {
        Text = "Medium Potato",
        Default = false,
        Tooltip = "Medium optimization: lower quality + no shadows + terrain/effects reduction.",
        Callback = function(Value) _G.ODXSetPotatoMode("Medium", Value) end,
    })

    _G.ODXPotatoHighToggle = QOLGroup:AddToggle("PotatoHighToggle", {
        Text = "High Potato",
        Default = false,
        Tooltip = "Maximum optimization: lowest quality + no shadows + terrain and heavy effects disabled.",
        Callback = function(Value) _G.ODXSetPotatoMode("High", Value) end,
    })

    QOLGroup:AddLabel("POTATO MODE: LIGHT / MEDIUM / HIGH (ONE AT A TIME)")

    -- Halloween pumpkin popup easter egg.
    -- Normal odds: 1 / 1000 once every 30 seconds.
    _G.ODXPumpkinClickRNG = Random.new()
    _G.ODXPumpkinMessageRNG = Random.new()

    _G.ODXPumpkinClickPhrases = {
        "happy halloween!",
        "argh!",
        "stop!",
        "stop that!",
        "it hurts!",
        "join script discord!",
        "hey!",
        "ow!",
        "ouch!",
        "why did you do that?",
        "leave me alone!",
        "not again!",
        "please stop!",
        "that tickles!",
        "hey, careful!",
        "rude!",
        "what was that?!",
        "you clicked me!",
        "don't touch me!",
        "hands off!",
        "ouchie!",
        "that hurt!",
        "hey pumpkin here!",
        "boo!",
        "spooky!",
        "trick or treat!",
        "have some candy!",
        "happy halloween, nerd!",
        "wrong pumpkin!",
        "seriously?",
        "again?!",
        "really?!",
        "why?!",
        "help!",
        "someone clicked me!",
        "i felt that!",
        "hey you!",
        "stop poking me!",
        "quit it!",
        "enough!",
        "no more!",
        "i'm warning you!",
        "that wasn't nice!",
        "mean!",
        "ouch, dude!",
        "argh, stop!",
        "aw!",
        "ow, my pumpkin!",
        "my face!",
        "my poor face!",
        "careful with the pumpkin!",
        "you scared me!",
        "boo... got you!",
        "spooky click!",
        "pumpkin power!",
        "pumpkin says no!",
        "don't press me!",
        "i'm sensitive!",
        "too much!",
        "one more click and...",
        "okay, that's enough!",
        "why are you like this?",
        "you again?",
        "i remember you!",
        "caught you!",
        "nice try!",
        "stop clicking!",
        "click somewhere else!",
        "i'm not a button!",
        "well, technically i am.",
        "this is harassment!",
        "pumpkin abuse!",
        "call the pumpkin police!",
        "send help!",
        "i need a break!",
        "give me candy instead!",
        "where's my candy?",
        "no touching!",
        "personal space!",
        "hey! my shell!",
        "my face hurts!",
        "that was a direct hit!",
        "critical pumpkin damage!",
        "ouch, critical!",
        "you got me!",
        "okay, okay!",
        "i surrender!",
        "mercy!",
        "please!",
        "that was unnecessary!",
        "why would you do that?",
        "i felt the click!",
        "click attack detected!",
        "pumpkin under attack!",
        "intruder!",
        "who gave you permission?",
        "i'm watching you!",
        "spooky police incoming!",
        "this pumpkin has feelings!",
        "be nice!",
        "creator named me zane the pumpkin, so call me zane!",
    }

    _G.ODXPumpkinBubbleSerial = 0
    _G.ODXPumpkinBubbleGui = nil

    _G.ODXPumpkinDestroyBubble = function()
        _G.ODXPumpkinBubbleSerial += 1

        if _G.ODXPumpkinBubbleGui then
            pcall(function()
                _G.ODXPumpkinBubbleGui:Destroy()
            end)
            _G.ODXPumpkinBubbleGui = nil
        end

        local function destroyNamedGui(parent)
            if not parent then return end
            for _, child in ipairs(parent:GetChildren()) do
                if child.Name == "ODXPumpkinClickBubbleGui" then
                    pcall(function()
                        child:Destroy()
                    end)
                end
            end
        end

        pcall(function() destroyNamedGui(CoreGui) end)
        pcall(function()
            local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
            destroyNamedGui(playerGui)
        end)
    end

    _G.ODXPumpkinShowClickMessage = function(pumpkin)
        pcall(function()
            -- Every new click immediately kills the previous bubble and its fade timer.
            _G.ODXPumpkinDestroyBubble()

            local rare = _G.ODXPumpkinMessageRNG:NextInteger(1, 200) == 1
            local message
            if rare then
                message = "theres small chance for somenthing special every 30 seconds"
            else
                local list = _G.ODXPumpkinClickPhrases
                message = list[_G.ODXPumpkinMessageRNG:NextInteger(1, #list)]
            end

            local serial = _G.ODXPumpkinBubbleSerial

            local bubbleGui = Instance.new("ScreenGui")
            bubbleGui.Name = "ODXPumpkinClickBubbleGui"
            bubbleGui.IgnoreGuiInset = true
            bubbleGui.ResetOnSpawn = false
            bubbleGui.DisplayOrder = 1000000
            bubbleGui.ZIndexBehavior = Enum.ZIndexBehavior.Global

            local parentGui = nil
            pcall(function() bubbleGui.Parent = CoreGui end)
            if bubbleGui.Parent then
                parentGui = CoreGui
            else
                pcall(function()
                    parentGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
                    bubbleGui.Parent = parentGui
                end)
            end
            if not bubbleGui.Parent then
                bubbleGui:Destroy()
                return
            end

            _G.ODXPumpkinBubbleGui = bubbleGui

            local bubble = Instance.new("Frame")
            bubble.Name = "ODXPumpkinClickBubble"
            bubble.AnchorPoint = Vector2.new(0, 1)
            bubble.Size = UDim2.fromOffset(250, 68)
            bubble.BackgroundColor3 = Color3.fromRGB(20, 8, 26)
            bubble.BackgroundTransparency = 0.02
            bubble.BorderSizePixel = 0
            bubble.ZIndex = 900

            local camera = Workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
            local pumpkinPos = pumpkin and pumpkin.AbsolutePosition or Vector2.new(8, viewport.Y - 70)
            local x = math.clamp(pumpkinPos.X + 68, 8, math.max(8, viewport.X - 258))
            local y = math.clamp(pumpkinPos.Y + 34, 92, math.max(92, viewport.Y - 8))
            bubble.Position = UDim2.fromOffset(x, y)
            bubble.Parent = bubbleGui

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 12)
            corner.Parent = bubble

            local stroke = Instance.new("UIStroke")
            stroke.Color = Color3.fromRGB(255, 106, 0)
            stroke.Thickness = 2
            stroke.Transparency = 0.05
            stroke.Parent = bubble

            local padding = Instance.new("UIPadding")
            padding.PaddingLeft = UDim.new(0, 10)
            padding.PaddingRight = UDim.new(0, 10)
            padding.PaddingTop = UDim.new(0, 6)
            padding.PaddingBottom = UDim.new(0, 6)
            padding.Parent = bubble

            local label = Instance.new("TextLabel")
            label.Name = "Text"
            label.Size = UDim2.fromScale(1, 1)
            label.BackgroundTransparency = 1
            label.Text = message
            label.TextColor3 = Color3.fromRGB(255, 235, 210)
            label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            label.TextStrokeTransparency = 0.35
            label.Font = Enum.Font.GothamBold
            label.TextSize = 14
            label.TextWrapped = true
            label.TextScaled = false
            label.TextXAlignment = Enum.TextXAlignment.Center
            label.TextYAlignment = Enum.TextYAlignment.Center
            label.ZIndex = 901
            label.Parent = bubble

            local tail = Instance.new("Frame")
            tail.Name = "Tail"
            tail.AnchorPoint = Vector2.new(0.5, 0)
            tail.Position = UDim2.new(0, 18, 1, -3)
            tail.Size = UDim2.fromOffset(14, 14)
            tail.BackgroundColor3 = Color3.fromRGB(20, 8, 26)
            tail.BorderSizePixel = 0
            tail.Rotation = 45
            tail.ZIndex = 899
            tail.Parent = bubble

            local scale = Instance.new("UIScale")
            scale.Scale = 0.72
            scale.Parent = bubble

            TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Scale = 1,
            }):Play()

            task.delay(2.2, function()
                if serial ~= _G.ODXPumpkinBubbleSerial then
                    return
                end

                if bubble and bubble.Parent then
                    local fade = TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                        Scale = 0.82,
                    })
                    fade:Play()
                end

                task.delay(0.2, function()
                    if serial == _G.ODXPumpkinBubbleSerial then
                        if _G.ODXPumpkinBubbleGui == bubbleGui then
                            _G.ODXPumpkinBubbleGui = nil
                        end
                        pcall(function()
                            if bubbleGui and bubbleGui.Parent then
                                bubbleGui:Destroy()
                            end
                        end)
                    end
                end)
            end)
        end)
    end





    local MobsList = {
        "Yoshikage Kira", "Thug", "Corrupt Police", "Alpha Thug", "Zombie Henchmen", "Vampire", "Dio", "Heaven Ascension DIO", "Jotaro", "Jotaro Kujo"
    }

    local QuestNPCs = {
        ["Yoshikage Kira"] = "Kira Quest NPC",
        ["Thug"] = "Officer Sam",
        ["Corrupt Police"] = "Deputy Bertrude",
        ["Alpha Thug"] = "Abbacchio's Partner",
        ["Zombie Henchmen"] = "Dracula",
        ["Vampire"] = "William Zeppeli",
        ["Dio"] = "Doppio",
        ["Jotaro"] = "__COORDS__",
        ["Jotaro Kujo"] = nil,
    }

    _G.ODXQuestNPCsRef = QuestNPCs

    local JotaroQuestCoords = Vector3.new(313.75, -25.79, 483.00)

    local QuestRetakeKeywords = {
        "can i take this job again", "take this job again", "job again",
        "i want to help more", "want to help more", "help more",
        "i'll take down", "ill take down", "take down 5", "take down", "more alpha thugs",
        "i can defeat more", "can defeat more", "defeat more", "zombie henchmen for you",
        "can i help out again", "help out again", "help out",
        "may i take the job again", "what job", "very well",
    }

    local QuestOtherKeywords = {
        "no problem", "thank you", "accept", "yes", "sure", "ok", "okay", "alright",
        "job", "quest", "take", "confirm", "continue", "start",
    }

    local ITEMS = {
        ["Mysterious Arrow"] = Color3.fromRGB(255, 215, 0),
        ["Rokakaka"] = Color3.fromRGB(220, 20, 60),
        ["Gold Coin"] = Color3.fromRGB(218, 215, 32),
        ["Diamond"] = Color3.fromRGB(0, 191, 255),
        ["Stone Mask"] = Color3.fromRGB(128, 128, 128),
        ["Quinton's Glove"] = Color3.fromRGB(139, 69, 19),
        ["Steel Ball"] = Color3.fromRGB(192, 192, 192),
        ["Dio's Diary"] = Color3.fromRGB(148, 0, 211),
        ["Pure Rokakaka"] = Color3.fromRGB(255, 255, 255),
        ["Lucky Arrow"] = Color3.fromRGB(0, 255, 127),
        ["Rib Cage of The Saint's Corpse"] = Color3.fromRGB(255, 69, 0),
        ["Pelvis of The Saint's Corpse"] = Color3.fromRGB(255, 140, 90),
        ["Heart of The Saint's Corpse"] = Color3.fromRGB(180, 20, 40),
        ["Left Arm of The Saint's Corpse"] = Color3.fromRGB(210, 120, 70),
        ["Ancient Scroll"] = Color3.fromRGB(74, 25, 234),
        ["Caesar's Headband"] = Color3.fromRGB(0, 17, 255),
        ["Clackers"] = Color3.fromRGB(15, 233, 128),
        ["Zeppeli's Hat"] = Color3.fromRGB(205, 133, 63),
        ["Zeppeli's Headband"] = Color3.fromRGB(0, 140, 255),
        ["Red Candy"] = Color3.fromRGB(255, 60, 60),
        ["Blue Candy"] = Color3.fromRGB(60, 120, 255),
        ["Green Candy"] = Color3.fromRGB(60, 220, 80),
        ["Yellow Candy"] = Color3.fromRGB(255, 220, 60),
        ["Candy"] = Color3.fromRGB(255, 140, 180),
    }

    local STACK_RADIUS = 0.85
    local lastItemPickupTime = 0
    local MIN_PICKUP_INTERVAL = 0.65

    ItemConfig = {
        Trackers = {},
        Enabled = false,
        SelectedItems = {
            ["Mysterious Arrow"] = true,
            ["Rokakaka"] = true,
            ["Gold Coin"] = true,
            ["Pure Rokakaka"] = true,
            ["Lucky Arrow"] = true,
            ["Zeppeli's Hat"] = true,
            ["Zeppeli's Headband"] = true,
            ["Dio's Diary"] = true,
        },
        ItemTweenSpeed = 300,
        DeadZone = Vector3.new(-0.12, 1.44, 0.00),
        AutoSellEnabled = false,
        HopWhenEmpty = false,
        AutoBuyLucky = false,
        AutoCandyExchange = false,
        SellWhitelist = {
            ["Gold Coin"] = true,
            ["Stone Mask"] = true,
            ["Steel Ball"] = true,
            ["Quinton's Glove"] = true,
            ["Clackers"] = true,
            ["Zeppeli's Hat"] = true,
            ["Zeppeli's Headband"] = true,
            ["Dio's Diary"] = true,
            ["Caesar's Headband"] = true,
            ["Pelvis of The Saint's Corpse"] = true,
            ["Heart of The Saint's Corpse"] = true,
            ["Left Arm of The Saint's Corpse"] = true,
        },
    }

    local Config = {
        TweenSpeed = 50,
        AutoFarmMob = false,
        StandFarm = false,
        StandFarmTarget = "Whitesnake",
        AutoPrestige = false,
        AutoAttack = true,
        SelectedMob = "Thug",
        BehindDistance = 3.0,
        TargetPlayerName = "",
        EnableTargetKill = false,
        ESP_Players = false,
        ESP_PlayerDist = false,
        InfJump = false,
        GlobalNoclip = false,
        FlyEnabled = false,
        StandPilot = false,
        StandPilotSpeed = 50,
        FlySpeed = 50,
        SpeedEnabled = false,
        CustomWalkSpeed = 22,
        MethodBehind = true,
        MethodAbove = false,
        FOVEnabled = false,
        FOVValue = 70,
        StandAttach = false,
        StandAttachDistance = 1,
        StandControl = false,
        StandControlSpeed = 60,
        AutoRun = false,
        AntiAFK = false,
        WatermarkEnabled = true,
        AutoMenuFlow = true,
        ESP_RGB = false,
    }

    _G.ODXConfigRef = Config

    local autoAttackToggleObj, itemFarmToggleObj = nil, nil
    local methodBehindToggleObj, methodAboveToggleObj, flyToggleObj = nil, nil, nil
    local targetDropdown = nil

    local activeMobTarget, activePlayerTarget, lockedTargetPart = nil, nil, nil
    local isArrivedAtTarget, isBarraging = false, false
    local needsQuestGrab, isDoingQuest = true, false
    local lastSelectedMob = Config.SelectedMob
    local lastAutoRun = 0
    local lastBlockPress = 0
    local isSellingItems = false
    local isGuiOpen = false

    _G.ODXFn_HSVToRGB = function(h, s, v)
        local i = math.floor(h * 6)
        local f = h * 6 - i
        local p = v * (1 - s)
        local q = v * (1 - f * s)
        local t = v * (1 - (1 - f) * s)
        i = i % 6
        if i == 0 then return Color3.new(v, t, p)
        elseif i == 1 then return Color3.new(q, v, p)
        elseif i == 2 then return Color3.new(p, v, t)
        elseif i == 3 then return Color3.new(p, q, v)
        elseif i == 4 then return Color3.new(t, p, v)
        else return Color3.new(v, p, q) end
    end

    _G.ODXFn_GetESPColor = function()
        if Config.ESP_RGB then
            return _G.ODXFn_HSVToRGB((tick() * 0.25) % 1, 1, 1)
        end
        return Color3.fromRGB(0, 170, 255)
    end

    _G.ODXFn_PressBlock = function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.wait(0.04)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end

    _G.ODXFn_GetPlayersList = function()
        local list = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                table.insert(list, plr.Name)
            end
        end
        if #list == 0 then
            table.insert(list, "None")
        end
        return list
    end

    _G.ODXFn_UpdatePlayersDropdown = function()
        pcall(function()
            if targetDropdown then
                targetDropdown:SetValues(_G.ODXFn_GetPlayersList())
            end
        end)
    end

    _G.ODXFn_IsValidPlayer = function(char)
        if not char or not char.Parent then
            return false
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        return hum ~= nil and hrp ~= nil and hum.Health > 0
    end

    _G.ODXFn_FindTargetPlayerChar = function()
        if Config.TargetPlayerName == "" then
            return nil
        end
        local targetPlayer = Players:FindFirstChild(Config.TargetPlayerName)
        if targetPlayer and targetPlayer.Character and _G.ODXFn_IsValidPlayer(targetPlayer.Character) then
            return targetPlayer.Character
        end
        return nil
    end

    _G.ODXFn_FindStandModel = function(character)
        if not character then
            return nil
        end
        for _, n in ipairs({"StandMorph", "Stand", "StandModel", "ActiveStand", "StandActive"}) do
            local s = character:FindFirstChild(n)
            if s and (s:IsA("Model") or s:IsA("BasePart")) then
                return s
            end
        end
        for _, child in ipairs(character:GetChildren()) do
            local ln = child.Name:lower()
            if (ln:find("stand") or ln:find("morph")) and (child:IsA("Model") or child:IsA("BasePart")) then
                return child
            end
        end
        local myHRP = character:FindFirstChild("HumanoidRootPart")
        if myHRP then
            for _, obj in ipairs(Workspace:GetChildren()) do
                if obj:IsA("Model") and obj ~= character and obj.Name:lower():find("stand") then
                    local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildWhichIsA("BasePart", true)
                    if hrp and (hrp.Position - myHRP.Position).Magnitude < 30 then
                        return obj
                    end
                end
            end
        end
        return nil
    end

    _G.ODXFn_GetStandHRP = function(stand)
        if not stand then
            return nil
        end
        if stand:IsA("BasePart") then
            return stand
        end
        return stand:FindFirstChild("HumanoidRootPart") or stand:FindFirstChildWhichIsA("BasePart", true)
    end

    _G.ODXStandRoom = nil
    _G.ODXStandReturnCF = nil

    _G.ODXFn_DestroyStandRoom = function()
        if _G.ODXStandRoom then
            pcall(function() _G.ODXStandRoom:Destroy() end)
            _G.ODXStandRoom = nil
        end
    end

    _G.ODXFn_CreateStandRoom = function(center)
        _G.ODXFn_DestroyStandRoom()
        local folder = Instance.new("Folder")
        folder.Name = "OVERDRIVE_StandRoom"
        folder.Parent = Workspace
        local function wall(size, offset)
            local p = Instance.new("Part")
            p.Name = "Wall"
            p.Anchored = true
            p.CanCollide = true
            p.Size = size
            p.CFrame = CFrame.new(center + offset)
            p.Color = Color3.fromRGB(25, 25, 28)
            p.Material = Enum.Material.SmoothPlastic
            p.Parent = folder
        end
        wall(Vector3.new(14, 1, 14), Vector3.new(0, -0.5, 0))
        wall(Vector3.new(14, 1, 14), Vector3.new(0, 8.5, 0))
        wall(Vector3.new(14, 8, 1), Vector3.new(0, 4, -7))
        wall(Vector3.new(14, 8, 1), Vector3.new(0, 4, 7))
        wall(Vector3.new(1, 8, 14), Vector3.new(-7, 4, 0))
        wall(Vector3.new(1, 8, 14), Vector3.new(7, 4, 0))
        _G.ODXStandRoom = folder
        return center + Vector3.new(0, 3, 0)
    end

    _G.ODXFn_AttachStandToBack = function(standHRP, targetHRP)
        if not standHRP or not targetHRP then
            return
        end
        pcall(function()
            local look = targetHRP.CFrame.LookVector
            local flatLook = Vector3.new(look.X, 0, look.Z)
            if flatLook.Magnitude < 0.05 then
                flatLook = Vector3.new(0, 0, -1)
            else
                flatLook = flatLook.Unit
            end
            local vel = targetHRP.AssemblyLinearVelocity
            local flatVel = Vector3.new(vel.X, 0, vel.Z)
            local movingBack = Config.EnableTargetKill and flatVel.Magnitude > 2 and flatVel.Unit:Dot(flatLook) < -0.2
            local pos
            if movingBack then
                pos = targetHRP.Position - flatLook * Config.StandAttachDistance
            elseif Config.EnableTargetKill and flatVel.Magnitude > 2 then
                pos = targetHRP.Position + flatLook * Config.StandAttachDistance
            else
                pos = targetHRP.Position - flatLook * Config.StandAttachDistance
            end
            standHRP.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0), targetHRP.Position)
            standHRP.AssemblyLinearVelocity = Vector3.zero
            standHRP.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    _G.ODXFn_GetTargetAttachHRP = function()
        if Config.EnableTargetKill then
            if not _G.ODXFn_IsValidPlayer(activePlayerTarget) then
                activePlayerTarget = _G.ODXFn_FindTargetPlayerChar()
            end
            if activePlayerTarget and activePlayerTarget:FindFirstChild("HumanoidRootPart") then
                return activePlayerTarget.HumanoidRootPart
            end
        end
        if Config.AutoFarmMob and not isDoingQuest and not needsQuestGrab then
            if activeMobTarget and activeMobTarget:FindFirstChild("HumanoidRootPart") then
                local mHum = activeMobTarget:FindFirstChildOfClass("Humanoid")
                if mHum and mHum.Health > 0 then
                    return activeMobTarget.HumanoidRootPart
                end
            end
        end
        if lockedTargetPart and lockedTargetPart.Parent then
            return lockedTargetPart
        end
        return nil
    end

    table.insert(Connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed or UserInputService:GetFocusedTextBox() then
            return
        end
        if input.KeyCode == Enum.KeyCode.F1 then
            Config.AutoAttack = not Config.AutoAttack
            if autoAttackToggleObj then
                pcall(function()
                    autoAttackToggleObj:SetValue(Config.AutoAttack)
                end)
            end
            Library:Notify("Auto Attack Status: " .. tostring(Config.AutoAttack))
        elseif input.KeyCode == Enum.KeyCode.F2 then
            Config.FlyEnabled = not Config.FlyEnabled
            if flyToggleObj then
                pcall(function()
                    flyToggleObj:SetValue(Config.FlyEnabled)
                end)
            end
            Library:Notify("Fly Mode Status: " .. tostring(Config.FlyEnabled))
        end
    end))

    table.insert(Connections, UserInputService.JumpRequest:Connect(function()
        if Config.InfJump and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
            LocalPlayer.Character:FindFirstChildOfClass("Humanoid"):ChangeState("Jumping")
        end
    end))

    LeftMainGroup:AddDropdown("MobDropdown", {
        Values = MobsList,
        Default = 2,
        Text = "Select Mob (Quest & Farm)",
        Callback = function(Value)
            Config.SelectedMob = Value
            activeMobTarget = nil
            needsQuestGrab = true
        end,
    })

    LeftMainGroup:AddToggle("AutoFarmToggle", {
        Text = "Enable Auto Farm & Auto Quest",
        Default = false,
        Callback = function(Value)
            Config.AutoFarmMob = Value
        end,
    })

    LeftMainGroup:AddSlider("FlightSpeedSlider", {
        Text = "Flight Speed",
        Default = 50, Min = 20, Max = 150, Rounding = 0,
        Callback = function(Value)
            Config.TweenSpeed = Value
        end,
    })

    LeftMainGroup:AddSlider("BehindDistSlider", {
        Text = "Distance Behind Target",
        Default = 3.0, Min = 2, Max = 10, Rounding = 1,
        Callback = function(Value)
            Config.BehindDistance = Value
        end,
    })

    LeftMainGroup:AddToggle("StandAttachToggle", {
        Text = "Stand Attach (mob / target player)",
        Default = false,
        Callback = function(Value)
            Config.StandAttach = Value
            Library:Notify("Stand Attach: " .. tostring(Value))
        end,
    })

    LeftMainGroup:AddLabel("STAND ATTACH OFFSET: 1")
    LeftMainGroup:AddLabel("Works on Auto Farm AND Target Kill")

    RightMainGroup:AddLabel("Combat Settings")

    autoAttackToggleObj = RightMainGroup:AddToggle("AutoAttackToggle", {
        Text = "Auto Attack (Super Fast Spam LMB + Heavy + E/R)",
        Default = true,
        Callback = function(Value)
            Config.AutoAttack = Value
        end,
    })

    RightMainGroup:AddLabel("Auto Attack Keybind: F1 Button")
    RightMainGroup:AddLabel("Glue Methods (farm + target kill)")

    methodBehindToggleObj = RightMainGroup:AddToggle("MethodBehindToggle", {
        Text = "behinde",
        Default = Config.MethodBehind,
        Callback = function(Value)
            Config.MethodBehind = Value
            if Value then
                Config.MethodAbove = false
                if methodAboveToggleObj then pcall(function() methodAboveToggleObj:SetValue(false) end) end
            elseif not Config.MethodAbove then
                Config.MethodBehind = true
                if methodBehindToggleObj then pcall(function() methodBehindToggleObj:SetValue(true) end) end
            end
        end,
    })

    methodAboveToggleObj = RightMainGroup:AddToggle("MethodAboveToggle", {
        Text = "above",
        Default = Config.MethodAbove,
        Callback = function(Value)
            Config.MethodAbove = Value
            if Value then
                Config.MethodBehind = false
                if methodBehindToggleObj then pcall(function() methodBehindToggleObj:SetValue(false) end) end
            elseif not Config.MethodBehind then
                Config.MethodAbove = true
                if methodAboveToggleObj then pcall(function() methodAboveToggleObj:SetValue(true) end) end
            end
        end,
    })

    RightMainGroup:AddToggle("StandFarmToggle", {
        Text = "Stand Farm",
        Default = false,
        Callback = function(Value)
            Config.StandFarm = Value
            Library:Notify(Value and "Stand Farm: rokaka -> worthiness -> arrow" or "Stand Farm off")
        end,
    })
    RightMainGroup:AddDropdown("StandFarmTarget", {
        Values = {
            "Pity",
            "Whitesnake", "Stone Free", "Star Platinum", "The World",
            "Anubis", "Red Hot Chili Pepper", "Crazy Diamond", "Killer Queen",
            "Gold Experience", "King Crimson", "Silver Chariot", "Hermit Purple",
            "The Hand", "Purple Haze", "Cream", "Hierophant Green",
            "Magician's Red", "White Album", "Aerosmith", "Six Pistols",
            "Sticky Fingers", "Beach Boy", "Mr. President",
        },
        Default = 1,
        Text = "Target Stand",
        Callback = function(Value)
            Config.StandFarmTarget = Value
        end,
    })
    RightMainGroup:AddLabel("Arrows only. Pity rolls any stand. Stops on a skin.")

    RightMainGroup:AddToggle("AutoPrestigeToggle", {
        Text = "Auto Prestige (quest pipeline)",
        Default = false,
        Callback = function(Value)
            Config.AutoPrestige = Value
            Library:Notify(Value and "Auto Prestige: ON" or "Auto Prestige: OFF")
        end,
    })
    RightMainGroup:AddLabel("ON = auto mob by level -> prestige at cap")
    RightMainGroup:AddLabel("OFF anytime = stops pipeline")

    local LeftItemGroup = Tabs.Items:AddGroupbox({ Side = "Left", Name = "Item Farmer" })
    itemFarmToggleObj = LeftItemGroup:AddToggle("ItemFarmToggle", {
        Text = "Enable Item Farmer",
        Default = false,
        Callback = function(Value)
            ItemConfig.Enabled = Value
            if not Value and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.Velocity = Vector3.zero
            end
            if Value then
                -- Force re-scan of item spawns when enabling
                task.spawn(function()
                    local folder = Workspace:FindFirstChild("Item_Spawns")
                    if folder then
                        for _, d in ipairs(folder:GetDescendants()) do
                            pcall(_G.ODXFn_evalItem, d)
                        end
                    else
                        for _, d in ipairs(Workspace:GetDescendants()) do
                            pcall(_G.ODXFn_evalItem, d)
                        end
                    end
                    local n = 0
                    for _ in pairs(ItemConfig.Trackers) do n = n + 1 end
                    Library:Notify("Item scan: " .. tostring(n) .. " tracked", 4)
                end)
            end
        end,
    })

    LeftItemGroup:AddLabel("Item Farmer movement: TWEEN (speed 300)")
    LeftItemGroup:AddLabel("Flies spawn route and grabs selected items")
    LeftItemGroup:AddToggle("HopWhenEmptyToggle", {
        Text = "Server Hop When No Items",
        Default = false,
        Callback = function(Value)
            ItemConfig.HopWhenEmpty = Value
        end,
    })
    LeftItemGroup:AddToggle("AutoBuyLuckyToggle", {
        Text = "Auto Buy Lucky Arrow",
        Default = false,
        Callback = function(Value)
            ItemConfig.AutoBuyLucky = Value
        end,
    })
    LeftItemGroup:AddLabel("Lucky Arrow shop buy at 75,000")
    LeftItemGroup:AddLabel("Pickup only while holding E")
    LeftItemGroup:AddLabel("Stack Skip enabled")
    LeftItemGroup:AddLabel("Select Items to Farm:")

    for itemName, _ in pairs(ITEMS) do
        LeftItemGroup:AddToggle("ItemFilter_" .. tostring(itemName), {
            Text = itemName,
            Default = ItemConfig.SelectedItems[itemName] or false,
            Callback = function(Value)
                ItemConfig.SelectedItems[itemName] = Value
            end,
        })
    end

    local RightItemGroup = Tabs.Items:AddGroupbox({ Side = "Right", Name = "Auto Seller" })

    RightItemGroup:AddToggle("AutoSellToggle", {
        Text = "Enable Auto Sell Items",
        Default = false,
        Callback = function(Value)
            ItemConfig.AutoSellEnabled = Value
        end,
    })

    RightItemGroup:AddLabel("Seller: remote, no fly")
    RightItemGroup:AddLabel("Sells from any distance")
    RightItemGroup:AddLabel("Threshold: 1 of the SAME item")
    RightItemGroup:AddLabel("Seller is independent from Item Farmer")
    RightItemGroup:AddLabel("Sell Whitelist (1+):")

    for itemName, _ in pairs(ITEMS) do
        if itemName ~= "Lucky Arrow" then
            RightItemGroup:AddToggle("SellWhitelist_" .. tostring(itemName), {
                Text = "Sell: " .. itemName,
                Default = ItemConfig.SellWhitelist[itemName] or false,
                Callback = function(Value)
                    ItemConfig.SellWhitelist[itemName] = Value
                end,
            })
        end
    end

    RightItemGroup:AddLabel("")
    RightItemGroup:AddToggle("AutoCandyExchangeToggle", {
        Text = "Auto Candy Exchange",
        Default = false,
        Callback = function(Value)
            ItemConfig.AutoCandyExchange = Value
        end,
    })
    RightItemGroup:AddLabel("Talks to Jack, The Cauldron Specter")
    RightItemGroup:AddLabel("Clicks 'I want to turn in my candy.'")
    RightItemGroup:AddLabel("Then clicks on -click to continue-")

    local LeftCharGroup = Tabs.Character:AddGroupbox({ Side = "Left", Name = "Character Modifiers" })
    local RightCharGroup = Tabs.Character:AddGroupbox({ Side = "Right", Name = "Vision" })

    flyToggleObj = LeftCharGroup:AddToggle("FlyToggle", {
        Text = "Enable Fly",
        Default = false,
        Callback = function(V)
            Config.FlyEnabled = V
            Library:Notify("Fly Mode Status: " .. tostring(V))
        end,
    })

    
    LeftCharGroup:AddToggle("StandPilotToggle", {
        Text = "Stand Pilot",
        Default = false,
        Callback = function(V)
            Config.StandPilot = V
            if V then
                Library:Notify("Stand Pilot ON — WASD to move stand")
            else
                Library:Notify("Stand Pilot OFF")
            end
        end,
    })
    LeftCharGroup:AddSlider("StandPilotSpeed", {
        Text = "Pilot Speed",
        Default = 50,
        Min = 16,
        Max = 150,
        Rounding = 0,
        Callback = function(V)
            Config.StandPilotSpeed = V
        end,
    })
    LeftCharGroup:AddLabel("Controls stand with WASD")
    LeftCharGroup:AddLabel("Camera follows stand")

LeftCharGroup:AddLabel("Fly Keybind: F2 Button (WASD + Space/Ctrl)")

    LeftCharGroup:AddSlider("FlySpeedSlider", {
        Text = "Fly Speed",
        Default = 50, Min = 16, Max = 200, Rounding = 0,
        Callback = function(Value)
            Config.FlySpeed = Value
        end,
    })

    LeftCharGroup:AddToggle("InfJumpToggle", {
        Text = "Infinite Jump",
        Default = false,
        Callback = function(V)
            Config.InfJump = V
        end,
    })

    LeftCharGroup:AddToggle("NoclipToggle", {
        Text = "Noclip",
        Default = false,
        Callback = function(V)
            Config.GlobalNoclip = V
        end,
    })

    LeftCharGroup:AddToggle("SpeedToggle", {
        Text = "Enable Custom WalkSpeed",
        Default = false,
        Callback = function(V)
            Config.SpeedEnabled = V
            if not V and LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
                LocalPlayer.Character:FindFirstChildOfClass("Humanoid").WalkSpeed = 16
            end
        end,
    })

    LeftCharGroup:AddSlider("WalkSpeedSlider", {
        Text = "WalkSpeed Value (Warning: >30 can trigger AC)",
        Default = 22, Min = 16, Max = 100, Rounding = 0,
        Callback = function(Value)
            Config.CustomWalkSpeed = Value
        end,
    })

    LeftCharGroup:AddToggle("WatermarkToggle", {
        Text = "Watermark (corner HUD)",
        Default = true,
        Callback = function(Value)
            Config.WatermarkEnabled = Value
            pcall(function()
                if _G.ODXWatermarkGui then
                    _G.ODXWatermarkGui.Enabled = Value == true
                end
            end)
        end,
    })

    LeftCharGroup:AddToggle("AutoMenuFlowToggle", {
        Text = "Auto Menu (Skip -> Play -> MAIN PLAY)",
        Default = true,
        Callback = function(Value)
            Config.AutoMenuFlow = Value
            Library:Notify(Value and "Auto Menu: ON" or "Auto Menu: OFF")
        end,
    })
    LeftCharGroup:AddLabel("Skip → left Play → MAIN GAME PLAY")

    RightCharGroup:AddToggle("FOVToggle", {
        Text = "Enable Custom FOV",
        Default = false,
        Callback = function(V)
            Config.FOVEnabled = V
            if not V and Workspace.CurrentCamera then
                Workspace.CurrentCamera.FieldOfView = 70
            end
        end,
    })

    RightCharGroup:AddSlider("FOVSlider", {
        Text = "FOV Value",
        Default = 70, Min = 40, Max = 120, Rounding = 0,
        Callback = function(Value)
            Config.FOVValue = Value
        end,
    })

    RightCharGroup:AddLabel("FOV applies while enabled")

    RightCharGroup:AddToggle("AutoRunToggle", {
        Text = "Auto Run (Left Ctrl after skill)",
        Default = false,
        Callback = function(Value)
            Config.AutoRun = Value
        end,
    })
    RightCharGroup:AddToggle("AntiAFKToggle", {
        Text = "Anti AFK",
        Default = false,
        Callback = function(Value)
            Config.AntiAFK = Value
        end,
    })

    local LeftPlayersGroup = Tabs.Players:AddGroupbox({ Side = "Left", Name = "Target System" })
    local RightPlayersGroup = Tabs.Players:AddGroupbox({ Side = "Right", Name = "Player ESP" })

    targetDropdown = LeftPlayersGroup:AddDropdown("TargetPlayerDropdown", {
        Values = _G.ODXFn_GetPlayersList(),
        Default = 1,
        Text = "Select Target Player",
        Callback = function(Value)
            Config.TargetPlayerName = (Value ~= "None" and Value) or ""
            activePlayerTarget = nil
        end,
    })

    LeftPlayersGroup:AddButton({
        Text = "Refresh Players List",
        Func = function()
            _G.ODXFn_UpdatePlayersDropdown()
        end,
    })

    LeftPlayersGroup:AddToggle("TargetKillToggle", {
        Text = "Enable Target Kill",
        Default = false,
        Callback = function(Value)
            Config.EnableTargetKill = Value
            if Value then
                activePlayerTarget = _G.ODXFn_FindTargetPlayerChar()
            else
                activePlayerTarget = nil
            end
        end,
    })

    RightPlayersGroup:AddLabel("Status: Player ESP not working", true, "EspStatusLabelOpt")
    RightPlayersGroup:AddToggle("EspToggle", {
        Text = "Enable Player ESP",
        Default = false,
        Callback = function(V)
            Config.ESP_Players = V
        end,
    })
    RightPlayersGroup:AddToggle("EspDistToggle", {
        Text = "Show Distance",
        Default = false,
        Callback = function(V)
            Config.ESP_PlayerDist = V
        end,
    })
    RightPlayersGroup:AddToggle("EspRgbToggle", {
        Text = "RGB color",
        Default = false,
        Callback = function(V)
            Config.ESP_RGB = V
        end,
    })
    local LoadoutGroup = Tabs.Players:AddGroupbox({ Side = "Left", Name = "Server Loadouts" })
    local loadoutLabel = LoadoutGroup:AddLabel("Scanning players...", true, "ServerLoadoutLabel")
    _G.ODXFn_ReadStat = function(player, names)
        local stats = player:FindFirstChild("PlayerStats")
        if not stats then
            return "?"
        end
        for _, name in ipairs(names) do
            local value = stats:FindFirstChild(name)
            if value and value.Value ~= nil and tostring(value.Value) ~= "" then
                return tostring(value.Value)
            end
        end
        return "?"
    end
    task.spawn(function()
        while ScriptActive do
            local lines = {}
            for _, plr in ipairs(Players:GetPlayers()) do
                local stand = _G.ODXFn_ReadStat(plr, {"Stand"})
                local spec = _G.ODXFn_ReadStat(plr, {"Spec", "Specialty", "FightingStyle", "Style"})
                table.insert(lines, plr.Name .. " | " .. stand .. " | " .. spec)
            end
            local text = #lines > 0 and table.concat(lines, "\n") or "No players"
            pcall(function()
                if loadoutLabel and loadoutLabel.SetText then
                    loadoutLabel:SetText(text)
                elseif Options and Options.ServerLoadoutLabel then
                    Options.ServerLoadoutLabel:SetText(text)
                end
            end)
            task.wait(2)
        end
    end)

    table.insert(Connections, Players.PlayerAdded:Connect(_G.ODXFn_UpdatePlayersDropdown))
    table.insert(Connections, Players.PlayerRemoving:Connect(function(plr)
        _G.ODXFn_UpdatePlayersDropdown()
    end))

    --// SBR DYNAMIC AUTO ROUTE
    --// No saved coordinates. The current server exposes the active SBR route
    --// through SBR_Map attributes on Workspace.Map and Start/Finish objects.
    local SBRConfig = {
        Enabled = false,
        TweenSpeed = 90,
        TargetOffset = Vector3.new(0, -7, 0),
        ArrivalDistance = 10,
        RebuildInterval = 0.75,
        Route = {},
    }

    local sbrStatus = "idle"
    local sbrRunId = 0
    local sbrMoving = false

    _G.ODXSBRRecovery.ConfigRef = SBRConfig
    _G.ODXScriptActive = ScriptActive
    _G.ODXStartSBRRecoveryMonitor()
    -- Observed Stage 4 end-message state. The message is informational only;
    -- the physical barrier remains the authoritative gate for Stage 4.
    -- This survives the message disappearing before the final gate opens.
    local sbrStage4EndMessageSeen = false

    _G.ODXFn_SBRMarkStage4EndMessage = function(text)
        local t = tostring(text or ""):lower():gsub("%s+", " ")
        if t:find("reached the end of stage #4", 1, true)
            or (t:find("reached the end of stage", 1, true) and t:find("the next stage will open", 1, true)) then
            sbrStage4EndMessageSeen = true
            return true
        end
        return false
    end

    _G.ODXFn_SBRHasStage4EndMessage = function()
        local roots = {}
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if playerGui then
            table.insert(roots, playerGui)
        end
        table.insert(roots, CoreGui)

        for _, root in ipairs(roots) do
            for _, gui in ipairs(root:GetDescendants()) do
                if (gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox")) and gui.Visible and gui.Text ~= "" then
                    if _G.ODXFn_SBRMarkStage4EndMessage(gui.Text) then
                        return true
                    end
                end
            end
        end

        return sbrStage4EndMessageSeen
    end

    -- Capture both modern TextChatService messages and the legacy filtered-chat
    -- event. The Stage 4 banner can disappear too quickly for a periodic GUI scan.
    pcall(function()
        if TextChatService and TextChatService.MessageReceived then
            table.insert(Connections, TextChatService.MessageReceived:Connect(function(message)
                _G.ODXFn_SBRMarkStage4EndMessage(message and message.Text or "")
            end))
        end
    end)

    pcall(function()
        local events = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
        local onMessage = events and events:FindFirstChild("OnMessageDoneFiltering")
        if onMessage and onMessage:IsA("RemoteEvent") then
            table.insert(Connections, onMessage.OnClientEvent:Connect(function(data)
                if type(data) == "table" then
                    _G.ODXFn_SBRMarkStage4EndMessage(data.Message or data.message or data.Text or "")
                else
                    _G.ODXFn_SBRMarkStage4EndMessage(data)
                end
            end))
        end
    end)

    --// SBR SAFETY PLATFORM
    --// A solid anchored platform follows the player while Auto SBR is enabled.
    --// This prevents falling when the route crosses/stands on a physical barrier.
    local SBRPlatform = nil
    local SBRPlatformConnection = nil
    local SBRBarrierCheckRadius = 250
    local SBRNoClipConnection = nil

    _G.ODXFn_SBRSetNoClip = function(enabled)
        if not enabled then
            if SBRNoClipConnection then
                pcall(function() SBRNoClipConnection:Disconnect() end)
                SBRNoClipConnection = nil
            end
            return
        end

        if SBRNoClipConnection then
            return
        end

        SBRNoClipConnection = RunService.Stepped:Connect(function()
            if not ScriptActive or not SBRConfig.Enabled then
                return
            end

            local char = LocalPlayer.Character
            if not char then
                return
            end

            for _, obj in ipairs(char:GetDescendants()) do
                if obj:IsA("BasePart") then
                    obj.CanCollide = false
                end
            end
        end)
    end

    _G.ODXFn_SBRDestroySafetyPlatform = function()
        if SBRPlatformConnection then
            pcall(function() SBRPlatformConnection:Disconnect() end)
            SBRPlatformConnection = nil
        end

        if SBRPlatform then
            pcall(function() SBRPlatform:Destroy() end)
            SBRPlatform = nil
        end

        _G.ODXFn_SBRSetNoClip(false)
    end

    _G.ODXFn_SBRCreateSafetyPlatform = function()
        _G.ODXFn_SBRDestroySafetyPlatform()

        local platform = Instance.new("Part")
        platform.Name = "OVERDRIVE_SBR_SafetyPlatform"
        platform.Size = Vector3.new(14, 1, 14)
        platform.Anchored = true
        platform.CanCollide = true
        platform.CanTouch = false
        platform.CanQuery = false
        platform.Transparency = 0.35
        platform.Material = Enum.Material.SmoothPlastic
        platform.CastShadow = false
        platform.Locked = true
        platform.Parent = Workspace
        SBRPlatform = platform
        _G.ODXFn_SBRSetNoClip(true)

        SBRPlatformConnection = RunService.Stepped:Connect(function()
            if not ScriptActive or not SBRConfig.Enabled or not SBRPlatform or not SBRPlatform.Parent then
                return
            end

            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                return
            end

            -- Keep the platform directly under the player's feet.
            -- Stepped updates before physics, so the character does not get a
            -- physics frame to fall through while the SBR tween is moving.
            local recovery = _G.ODXSBRRecovery
            if recovery and recovery.Active and recovery.SafeCFrame then
                local safePos = recovery.SafeCFrame.Position
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                local footOffset = humanoid and math.max(2.5, humanoid.HipHeight + 1.5) or 3.25
                SBRPlatform.CFrame = CFrame.new(safePos.X, safePos.Y - footOffset, safePos.Z)
                return
            end

            local humanoid = char:FindFirstChildOfClass("Humanoid")
            local footOffset = humanoid and math.max(2.5, humanoid.HipHeight + 1.5) or 3.25
            local y = hrp.Position.Y - footOffset
            SBRPlatform.CFrame = CFrame.new(hrp.Position.X, y, hrp.Position.Z)
        end)
    end

    _G.ODXFn_SBRGetWorldPosition = function(obj)
        if not obj then
            return nil
        end
        if obj:IsA("BasePart") then
            return obj.Position
        elseif obj:IsA("Attachment") then
            return obj.WorldPosition
        elseif obj:IsA("Model") then
            local pp = obj.PrimaryPart
            if pp then
                return pp.Position
            end
            local ok, cf = pcall(function()
                return obj:GetBoundingBox()
            end)
            if ok and cf then
                return cf.Position
            end
        end
        return nil
    end

    _G.ODXFn_SBRFormatVector = function(v)
        if not v then
            return "?"
        end
        return string.format("%.1f, %.1f, %.1f", v.X, v.Y, v.Z)
    end

    _G.ODXFn_SBRFindStart = function(mapModel)
        if not mapModel then
            return nil
        end
        local direct = mapModel:FindFirstChild("Start")
        if direct and direct:IsA("BasePart") then
            return direct
        end
        for _, obj in ipairs(mapModel:GetDescendants()) do
            if obj.Name:lower() == "start" and obj:IsA("BasePart") then
                return obj
            end
        end
        return nil
    end

    _G.ODXFn_SBRReadMapStage = function(mapModel)
        if not mapModel or not mapModel:IsA("Instance") then
            return nil
        end
        local value = mapModel:GetAttribute("SBR_Map")
        if value == nil then
            return nil
        end
        if typeof(value) == "number" then
            return value
        end
        local n = tonumber(value)
        return n
    end

    _G.ODXFn_SBRBuildRoute = function()
        local route = {}
        local mapFolder = Workspace:FindFirstChild("Map")
        if not mapFolder then
            return route
        end

        -- Starting line is discovered dynamically as well.
        for _, mapModel in ipairs(mapFolder:GetChildren()) do
            local stage = _G.ODXFn_SBRReadMapStage(mapModel)
            if stage == nil and tostring(mapModel:GetAttribute("SBR_Map")) == "Starting_Line" then
                local startPart = _G.ODXFn_SBRFindStart(mapModel)
                if startPart then
                    route[0] = {
                        Stage = 0,
                        Object = startPart,
                        Position = startPart.Position,
                        Name = mapModel.Name,
                        StartingLine = true,
                    }
                end
            elseif stage ~= nil then
                local startPart = _G.ODXFn_SBRFindStart(mapModel)
                if startPart then
                    route[stage] = {
                        Stage = stage,
                        Object = startPart,
                        Position = startPart.Position,
                        Name = mapModel.Name,
                    }
                end
            end
        end

        local finish = Workspace:FindFirstChild("Finish")
        if finish and finish:IsA("BasePart") then
            route[5] = {
                Stage = 5,
                Object = finish,
                Position = finish.Position,
                Name = "Finish",
                Final = true,
            }
        end

        local ordered = {}
        if route[0] then
            table.insert(ordered, route[0])
        end
        for stage = 1, 4 do
            if route[stage] then
                table.insert(ordered, route[stage])
            end
        end
        if route[5] then
            table.insert(ordered, route[5])
        end

        SBRConfig.Route = ordered
        return ordered
    end

    _G.ODXFn_SBRGetRouteSignature = function(route)
        local parts = {}
        for _, node in ipairs(route or {}) do
            table.insert(parts, tostring(node.Stage) .. ":" .. tostring(node.Name) .. ":" .. tostring(node.Object))
        end
        return table.concat(parts, "|")
    end

    _G.ODXFn_SBRPrintRoute = function(route)
        print("============================================================")
        print("[OVERDRIVE X | SBR] DYNAMIC ROUTE")
        print("============================================================")
        print("PlaceId:", game.PlaceId)
        print("JobId:", game.JobId)
        for i, node in ipairs(route or {}) do
            print(string.format(
                "[%d] stage=%s | map=%s | object=%s | pos=%s",
                i,
                tostring(node.Stage),
                tostring(node.Name),
                node.Object and node.Object:GetFullName() or "?",
                _G.ODXFn_SBRFormatVector(node.Position)
            ))
        end
        print("Route nodes:", #(route or {}))
        print("============================================================")
    end

    _G.ODXFn_SBRRebuildRoute = function(forcePrint)
        local oldSignature = _G.ODXFn_SBRGetRouteSignature(SBRConfig.Route)
        local route = _G.ODXFn_SBRBuildRoute()
        local newSignature = _G.ODXFn_SBRGetRouteSignature(route)
        if forcePrint or oldSignature ~= newSignature then
            _G.ODXFn_SBRPrintRoute(route)
        end
        return route
    end

    _G.ODXFn_SBRStopMovement = function()
        sbrRunId = sbrRunId + 1
        sbrMoving = false
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end

    _G.ODXFn_SBRIsBarrierInstance = function(instance)
        if not instance then
            return false
        end

        local current = instance
        while current and current ~= Workspace do
            local name = string.lower(current.Name or "")
            if name == "barrier" or name == "barriers" or string.find(name, "barrier", 1, true) then
                return true
            end
            current = current.Parent
        end

        return false
    end

    _G.ODXFn_SBRGetActiveBarriers = function()
        local result = {}
        local roots = {}

        -- IMPORTANT: At the beginning of an SBR round the physical barrier may
        -- not exist yet. In that state there is nothing to wait for, so return
        -- an empty list instead of guessing that the gate is closed.
        local directBarrier = Workspace:FindFirstChild("Barrier")
        local directBarriers = Workspace:FindFirstChild("Barriers")

        if directBarrier then
            table.insert(roots, directBarrier)
        end
        if directBarriers and directBarriers ~= directBarrier then
            table.insert(roots, directBarriers)
        end

        -- The actual SBR start gate discovered by the scanner is
        -- Workspace.Barrier.StartBarrier. Keep it in the same physical barrier
        -- system so Auto SBR cannot pass through it while it is still closed.
        -- Do not scan every unrelated object whose name merely contains "barrier".
        local seen = {}
        for _, root in ipairs(roots) do
            if root:IsA("BasePart") then
                if root.CanCollide and root.Transparency < 1 then
                    seen[root] = true
                    table.insert(result, root)
                end
            else
                for _, obj in ipairs(root:GetDescendants()) do
                    if obj:IsA("BasePart") and obj.CanCollide and obj.Transparency < 1 and not seen[obj] then
                        seen[obj] = true
                        table.insert(result, obj)
                    end
                end
            end
        end

        return result
    end

    _G.ODXFn_SBRSegmentHitsPart = function(origin, target, part, padding)
        if not origin or not target or not part or not part.Parent then
            return false
        end

        local cf = part.CFrame
        local size = part.Size + Vector3.new(padding or 2, padding or 2, padding or 2)
        local a = cf:PointToObjectSpace(origin)
        local b = cf:PointToObjectSpace(target)
        local d = b - a

        local tMin, tMax = 0, 1
        local axes = {"X", "Y", "Z"}
        for _, axis in ipairs(axes) do
            local av = a[axis]
            local dv = d[axis]
            local half = size[axis] * 0.5

            if math.abs(dv) < 1e-6 then
                if av < -half or av > half then
                    return false
                end
            else
                local t1 = (-half - av) / dv
                local t2 = (half - av) / dv
                if t1 > t2 then
                    t1, t2 = t2, t1
                end
                if t1 > tMin then tMin = t1 end
                if t2 < tMax then tMax = t2 end
                if tMin > tMax then
                    return false
                end
            end
        end

        return tMax >= 0 and tMin <= 1
    end

    _G.ODXFn_SBRPointToPartDistance = function(point, part)
        if not point or not part or not part.Parent then
            return math.huge
        end

        local localPoint = part.CFrame:PointToObjectSpace(point)
        local half = part.Size * 0.5
        local dx = math.max(math.abs(localPoint.X) - half.X, 0)
        local dy = math.max(math.abs(localPoint.Y) - half.Y, 0)
        local dz = math.max(math.abs(localPoint.Z) - half.Z, 0)
        return Vector3.new(dx, dy, dz).Magnitude
    end

    _G.ODXFn_SBRBarrierBlocksPath = function(origin, target)
        if not origin or not target then
            return nil
        end

        local barriers = _G.ODXFn_SBRGetActiveBarriers()
        local nearestBarrier = nil
        local nearestDistance = math.huge

        for _, barrier in ipairs(barriers) do
            if barrier.Parent and barrier.CanCollide and barrier.Transparency < 1 then
                -- Only consider a barrier when the player is actually near it.
                -- This prevents a barrier from a later/previous stage from
                -- blocking the current stage while it is still far away.
                local distance = _G.ODXFn_SBRPointToPartDistance(origin, barrier)
                if distance <= SBRBarrierCheckRadius and distance < nearestDistance then
                    if _G.ODXFn_SBRSegmentHitsPart(origin, target, barrier, 4) then
                        nearestDistance = distance
                        nearestBarrier = barrier
                    end
                end
            end
        end

        return nearestBarrier
    end

    _G.ODXFn_SBRWaitForBarrier = function(runId, target)
        local waiting = false

        while ScriptActive and SBRConfig.Enabled and runId == sbrRunId do
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                task.wait(0.2)
                continue
            end

            local barrier = _G.ODXFn_SBRBarrierBlocksPath(hrp.Position, target)
            if not barrier then
                if waiting then
                    sbrStatus = "barrier opened"
                    task.wait(0.15)
                end
                return true
            end

            waiting = true
            sbrStatus = "waiting for barrier: " .. tostring(barrier.Name)
            task.wait(0.25)
        end

        return false
    end

    _G.ODXFn_SBRFinishGateClosed = function(fromPos, finishPos)
        if not fromPos or not finishPos then
            return false
        end
        local flatFrom = Vector3.new(fromPos.X, finishPos.Y, fromPos.Z)
        for _, barrier in ipairs(_G.ODXFn_SBRGetActiveBarriers()) do
            if barrier and barrier.Parent and barrier:IsA("BasePart") and barrier.CanCollide and barrier.Transparency < 1 then
                if _G.ODXFn_SBRSegmentHitsPart(flatFrom, finishPos, barrier, 6) then
                    return true
                end
            end
        end
        return false
    end

    -- Stage 4 is intentionally held immediately before the barrier that
    -- separates biome 4 from the bridge/finish straight. The barrier is
    -- resolved at runtime; no server-specific coordinates are stored.
    _G.ODXFn_SBRGetStage4BarrierTarget = function(stageTarget, currentPosition)
        if not stageTarget or not currentPosition then
            return nil
        end

        local bestPoint = nil
        local bestT = math.huge
        local direction = Vector3.new(stageTarget.X - currentPosition.X, 0, stageTarget.Z - currentPosition.Z)
        local directionMag = direction.Magnitude
        if directionMag < 0.05 then
            return nil
        end
        direction = direction.Unit

        for _, barrier in ipairs(_G.ODXFn_SBRGetActiveBarriers()) do
            if barrier and barrier.Parent and barrier:IsA("BasePart") then
                -- Test the actual path to Stage 4. This prevents selecting an
                -- unrelated barrier elsewhere on the map.
                local pathTarget = Vector3.new(stageTarget.X, stageTarget.Y, stageTarget.Z)
                if _G.ODXFn_SBRSegmentHitsPart(currentPosition, pathTarget, barrier, 0) then
                    local cf = barrier.CFrame
                    local half = barrier.Size * 0.5
                    local a = cf:PointToObjectSpace(currentPosition)
                    local b = cf:PointToObjectSpace(pathTarget)
                    local d = b - a

                    local tMin, tMax = 0, 1
                    local valid = true
                    for _, axis in ipairs({"X", "Y", "Z"}) do
                        local av = a[axis]
                        local dv = d[axis]
                        local h = half[axis]
                        if math.abs(dv) < 1e-6 then
                            if av < -h or av > h then
                                valid = false
                                break
                            end
                        else
                            local t1 = (-h - av) / dv
                            local t2 = (h - av) / dv
                            if t1 > t2 then t1, t2 = t2, t1 end
                            if t1 > tMin then tMin = t1 end
                            if t2 < tMax then tMax = t2 end
                            if tMin > tMax then
                                valid = false
                                break
                            end
                        end
                    end

                    if valid and tMax >= 0 and tMin <= 1 then
                        -- tMin is the first point where the route reaches the
                        -- barrier. Stop almost flush with its near surface.
                        local hitT = math.clamp(tMin, 0, 1)
                        local hitPoint = currentPosition:Lerp(pathTarget, hitT)
                        local stopPoint = hitPoint - direction * 0.35
                        stopPoint = Vector3.new(stopPoint.X, stageTarget.Y, stopPoint.Z)

                        if hitT < bestT then
                            bestT = hitT
                            bestPoint = stopPoint
                        end
                    end
                end
            end
        end

        -- Fallback: if the exact segment test misses the gate because the
        -- runtime Start/Finish marker is slightly offset from the physical
        -- barrier, still resolve the closest forward-facing active barrier.
        -- This keeps Stage 4 from stopping far away from the actual gate.
        if not bestPoint then
            local bestForwardDistance = math.huge
            local routeEnd = Vector3.new(stageTarget.X, currentPosition.Y, stageTarget.Z)

            for _, barrier in ipairs(_G.ODXFn_SBRGetActiveBarriers()) do
                if barrier and barrier.Parent and barrier:IsA("BasePart") and barrier.CanCollide and barrier.Transparency < 1 then
                    local barrierPoint = barrier.CFrame.Position
                    local flatToBarrier = Vector3.new(barrierPoint.X - currentPosition.X, 0, barrierPoint.Z - currentPosition.Z)
                    local along = flatToBarrier:Dot(direction)
                    local lateral = (flatToBarrier - direction * along).Magnitude

                    -- Only consider barriers in front of us and reasonably
                    -- close to the current route corridor.
                    if along > 0 and along < 5000 and lateral < 180 then
                        local localCurrent = barrier.CFrame:PointToObjectSpace(currentPosition)
                        local localRoute = barrier.CFrame:PointToObjectSpace(routeEnd)
                        local localDir = localRoute - localCurrent
                        local half = barrier.Size * 0.5

                        local tMin, tMax = 0, 1
                        local valid = true
                        for _, axis in ipairs({"X", "Y", "Z"}) do
                            local av = localCurrent[axis]
                            local dv = localDir[axis]
                            local h = half[axis]
                            if math.abs(dv) < 1e-6 then
                                if av < -h or av > h then
                                    valid = false
                                    break
                                end
                            else
                                local t1 = (-h - av) / dv
                                local t2 = (h - av) / dv
                                if t1 > t2 then t1, t2 = t2, t1 end
                                if t1 > tMin then tMin = t1 end
                                if t2 < tMax then tMax = t2 end
                                if tMin > tMax then
                                    valid = false
                                    break
                                end
                            end
                        end

                        if valid and tMax >= 0 and tMin <= 1 then
                            local hitT = math.clamp(tMin, 0, 1)
                            local hitPoint = currentPosition:Lerp(routeEnd, hitT)
                            local stopPoint = hitPoint - direction * 0.35
                            stopPoint = Vector3.new(stopPoint.X, stageTarget.Y, stopPoint.Z)
                            if along < bestForwardDistance then
                                bestForwardDistance = along
                                bestPoint = stopPoint
                            end
                        end
                    end
                end
            end
        end

        return bestPoint
    end

    _G.ODXFn_SBRMoveToNode = function(node, runId)
        if not node or not node.Object or not node.Object.Parent then
            return false
        end
        if not SBRConfig.Enabled or runId ~= sbrRunId then
            return false
        end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return false
        end

        local target = _G.ODXFn_SBRGetWorldPosition(node.Object)
        if not target then
            return false
        end

        if node.Stage < 5 then
            target = target + SBRConfig.TargetOffset
        elseif node.Stage == 5 then
            local dir = target - hrp.Position
            if dir.Magnitude < 1 then
                dir = Vector3.new(0, 0, 1)
            end
            target = target + dir.Unit * 18
        end

        local stage4BarrierTarget = nil
        local stage4FinalTarget = nil
        local stage4HoldY = nil
        if node.Stage == 4 then
            -- Stay at the under-checkpoint height for the whole stage 4 wait.
            -- Rise only happens later, on stage 5.
            stage4FinalTarget = target
            stage4HoldY = stage4FinalTarget.Y
            stage4BarrierTarget = _G.ODXFn_SBRGetStage4BarrierTarget(target, hrp.Position)
            if stage4BarrierTarget then
                target = stage4BarrierTarget
            end
            target = Vector3.new(target.X, stage4HoldY, target.Z)
        end

        if node.Stage < 4 and target.Y > hrp.Position.Y + 8 then
            target = Vector3.new(target.X, hrp.Position.Y + 8, target.Z)
        end
        local distance = (hrp.Position - target).Magnitude
        if distance <= SBRConfig.ArrivalDistance and not stage4BarrierTarget then
            return true
        end

        -- Stage 4 is special: never wait for the barrier on a route that ends
        -- before the barrier. Reach the gate first, then wait there.
        if node.Stage == 4 and stage4BarrierTarget then
            if distance > SBRConfig.ArrivalDistance then
                local speed = math.max(10, tonumber(SBRConfig.TweenSpeed) or 90)
                local duration = math.clamp(distance / speed, 0.05, 30)
                local gateTween = TweenService:Create(
                    hrp,
                    TweenInfo.new(duration, Enum.EasingStyle.Linear),
                    {CFrame = CFrame.new(target)}
                )
                sbrMoving = true
                sbrStatus = "stage 4: waiting at barrier"
                _G.ODXSBRRecovery.CurrentTween = gateTween
                gateTween:Play()
                gateTween.Completed:Wait()
                _G.ODXSBRRecovery.CurrentTween = nil
                if _G.ODXSBRRecovery.Active then
                    sbrMoving = false
                    return "recovery"
                end
                if not ScriptActive or not SBRConfig.Enabled or runId ~= sbrRunId then
                    sbrMoving = false
                    return false
                end
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                sbrMoving = false
            end

            -- The barrier is now the only thing allowed to hold us here.
            -- Do not change Y while it is closed.
            while ScriptActive and SBRConfig.Enabled and runId == sbrRunId do
                if _G.ODXSBRRecovery.Active then
                    sbrStatus = "smart recovery: holding safe position"
                    return "recovery"
                end
                -- Remember the message even if it disappears before the gate opens.
                if _G.ODXFn_SBRHasStage4EndMessage() then
                    sbrStage4EndMessageSeen = true
                end

                local barrier = _G.ODXFn_SBRBarrierBlocksPath(hrp.Position, stage4FinalTarget)
                if not barrier then
                    break
                end
                sbrStatus = "stage 4: waiting for barrier"
                task.wait(0.2)
            end
            if not ScriptActive or not SBRConfig.Enabled or runId ~= sbrRunId then
                return false
            end

            -- Gate opened. Stay at the same low Y until stage 5.
            sbrStatus = "stage 4: barrier opened -> staying low"
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            target = Vector3.new(stage4FinalTarget.X, stage4HoldY, stage4FinalTarget.Z)
        end

        -- A closed barrier must be cleared before normal route movement starts.
        if not (node.Stage == 4 and stage4BarrierTarget) then
            if not _G.ODXFn_SBRWaitForBarrier(runId, target) then
                return false
            end
        end

        -- Stage 5 is the normal surface level. Rise only after the stage 4 gate is actually gone.
        if node.Stage == 5 then
            local stage4Pos = hrp.Position - Vector3.new(0, 0, 80)
            local route = SBRConfig.Route
            for _, prev in ipairs(route or {}) do
                if prev.Stage == 4 and prev.Object and prev.Object.Parent then
                    stage4Pos = _G.ODXFn_SBRGetWorldPosition(prev.Object) or stage4Pos
                    break
                end
            end
            while ScriptActive and SBRConfig.Enabled and runId == sbrRunId and _G.ODXFn_SBRFinishGateClosed(stage4Pos, target) do
                sbrStatus = "stage 4: gate still closed, holding low"
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                hrp.CFrame = CFrame.new(stage4Pos.X, stage4Pos.Y + SBRConfig.TargetOffset.Y, stage4Pos.Z)
                task.wait(0.25)
            end
            if not ScriptActive or not SBRConfig.Enabled or runId ~= sbrRunId then
                return false
            end
            distance = (hrp.Position - target).Magnitude
        end

        local speed = math.max(10, tonumber(SBRConfig.TweenSpeed) or 90)
        local duration = math.clamp(distance / speed, 0.05, 30)
        local tween = TweenService:Create(
            hrp,
            TweenInfo.new(duration, Enum.EasingStyle.Linear),
            {CFrame = CFrame.new(target)}
        )

        sbrMoving = true
        sbrStatus = "moving -> stage " .. tostring(node.Stage)
        _G.ODXSBRRecovery.CurrentTween = tween
        tween:Play()

        local deadline = tick() + duration + 3
        while ScriptActive and SBRConfig.Enabled and runId == sbrRunId and tick() < deadline do
            if _G.ODXSBRRecovery.Active then
                pcall(function() tween:Cancel() end)
                _G.ODXSBRRecovery.CurrentTween = nil
                sbrMoving = false
                sbrStatus = "smart recovery: holding safe position"
                return "recovery"
            end
            if not node.Object.Parent then
                pcall(function() tween:Cancel() end)
                sbrMoving = false
                return false
            end

            local liveTarget = _G.ODXFn_SBRGetWorldPosition(node.Object)
            if liveTarget then
                if node.Stage < 5 then
                    liveTarget = liveTarget + SBRConfig.TargetOffset

                    if node.Stage == 4 then
                        _G.ODXFn_SBRHasStage4EndMessage()
                        local barrierTarget = _G.ODXFn_SBRGetStage4BarrierTarget(liveTarget, hrp.Position)
                        if barrierTarget and not sbrStage4EndMessageSeen then
                            liveTarget = barrierTarget
                        end
                        liveTarget = Vector3.new(liveTarget.X, stage4HoldY or hrp.Position.Y, liveTarget.Z)
                    end

                    if node.Stage < 4 then
                        local maxUp = hrp.Position.Y + 8
                        if liveTarget.Y > maxUp then
                            liveTarget = Vector3.new(liveTarget.X, maxUp, liveTarget.Z)
                        end
                    end
                else
                    local dir = liveTarget - hrp.Position
                    if dir.Magnitude < 1 then
                        dir = Vector3.new(0, 0, 1)
                    end
                    liveTarget = liveTarget + dir.Unit * 18
                end

                -- Check the complete remaining path, not a single ray.
                local barrier = _G.ODXFn_SBRBarrierBlocksPath(hrp.Position, liveTarget)
                if barrier then
                    pcall(function() tween:Cancel() end)
                    sbrMoving = false
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero

                    -- Wait here until the physical barrier is actually gone/open.
                    if not _G.ODXFn_SBRWaitForBarrier(runId, liveTarget) then
                        return false
                    end
                    return _G.ODXFn_SBRMoveToNode(node, runId)
                end

                if (hrp.Position - liveTarget).Magnitude <= SBRConfig.ArrivalDistance then
                    pcall(function() tween:Cancel() end)
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                    sbrMoving = false
                    return true
                end
            end

            task.wait(0.08)
        end

        pcall(function() tween:Cancel() end)
        if _G.ODXSBRRecovery.CurrentTween == tween then
            _G.ODXSBRRecovery.CurrentTween = nil
        end
        sbrMoving = false
        if not SBRConfig.Enabled or runId ~= sbrRunId then
            return false
        end

        -- Never force a final CFrame through a possibly closed barrier.
        local finalTarget = _G.ODXFn_SBRGetWorldPosition(node.Object)
        if finalTarget then
            if node.Stage < 5 then
                finalTarget = finalTarget + SBRConfig.TargetOffset
            elseif node.Stage == 5 then
                local dir = finalTarget - hrp.Position
                if dir.Magnitude < 1 then
                    dir = Vector3.new(0, 0, 1)
                end
                finalTarget = finalTarget + dir.Unit * 18
            end
            if not _G.ODXFn_SBRBarrierBlocksPath(hrp.Position, finalTarget) then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            else
                return _G.ODXFn_SBRWaitForBarrier(runId, finalTarget)
            end
        end
        return true
    end

    _G.ODXFn_HasRevolver = function()
        local char = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        local function has(container)
            if not container then return false end
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") and item.Name:lower():find("revolver") then
                    return true
                end
            end
            return false
        end
        return has(char) or has(backpack)
    end

    _G.ODXFn_TryJoinSBR = function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if playerGui then
            for _, gui in ipairs(playerGui:GetDescendants()) do
                if (gui:IsA("TextButton") or gui:IsA("ImageButton")) and gui.Visible then
                    local text = ""
                    if gui:IsA("TextButton") then
                        text = gui.Text or ""
                    end
                    local label = gui:FindFirstChildWhichIsA("TextLabel", true)
                    if label then
                        text = text .. " " .. (label.Text or "")
                    end
                    local low = text:lower()
                    if low:find("steel ball") or low:find("sbr") or low:find("join race") then
                        pcall(function()
                            if firesignal then
                                firesignal(gui.MouseButton1Click)
                            end
                            gui.MouseButton1Click:Fire()
                        end)
                    end
                end
            end
        end
        local char = LocalPlayer.Character
        local remote = char and char:FindFirstChild("RemoteEvent")
        if remote then
            pcall(function() remote:FireServer("JoinSBR") end)
            pcall(function() remote:FireServer("SteelBallRun") end)
            pcall(function() remote:FireServer("QueueSBR") end)
        end
    end

    _G.ODXFn_SBRAutoLoop = function()
        sbrRunId = sbrRunId + 1
        local runId = sbrRunId

        task.spawn(function()
            sbrStatus = "waiting for revolver"
            while ScriptActive and SBRConfig.Enabled and runId == sbrRunId and not _G.ODXFn_HasRevolver() do
                Library:Notify("SBR: waiting for revolver (start barrier)")
                task.wait(2)
            end
            if not ScriptActive or not SBRConfig.Enabled or runId ~= sbrRunId then
                return
            end
            local route = _G.ODXFn_SBRRebuildRoute(false)
            if #route < 6 then
                sbrStatus = "route incomplete"
                Library:Notify("SBR: dynamic route not ready (found " .. tostring(#route) .. "/6 targets).")
                return
            end

            for index, node in ipairs(route) do
                if not ScriptActive or not SBRConfig.Enabled or runId ~= sbrRunId then
                    break
                end

                -- Refresh runtime references before every stage. Nothing is saved between servers.
                route = _G.ODXFn_SBRRebuildRoute(false)
                node = route[index]
                if not node then
                    sbrStatus = "route changed"
                    break
                end

                -- The starting gate is a physical barrier. Before every stage,
                -- especially the first one, make sure StartBarrier is no longer
                -- blocking the player's current route. This prevents the tween
                -- from silently passing through the closed start gate.
                local char = LocalPlayer.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp and node.Object then
                    local preTarget = _G.ODXFn_SBRGetWorldPosition(node.Object)
                    if preTarget then
                        if node.Stage < 5 then
                            preTarget = preTarget + SBRConfig.TargetOffset
                        end
                        if not _G.ODXFn_SBRWaitForBarrier(runId, preTarget) then
                            break
                        end
                    end
                end

                if node.Stage == 5 then
                    local finishPos = node.Object and _G.ODXFn_SBRGetWorldPosition(node.Object)
                    local stage4Pos = hrp and hrp.Position or Vector3.zero
                    for _, prev in ipairs(SBRConfig.Route or {}) do
                        if prev.Stage == 4 and prev.Object and prev.Object.Parent then
                            stage4Pos = _G.ODXFn_SBRGetWorldPosition(prev.Object) or stage4Pos
                            break
                        end
                    end
                    if hrp and finishPos and _G.ODXFn_SBRFinishGateClosed(stage4Pos, finishPos) then
                        sbrStatus = "stage 4: overshot closed gate, holding"
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                        hrp.CFrame = CFrame.new(stage4Pos.X, stage4Pos.Y + SBRConfig.TargetOffset.Y, stage4Pos.Z)
                        while ScriptActive and SBRConfig.Enabled and runId == sbrRunId and _G.ODXFn_SBRFinishGateClosed(stage4Pos, finishPos) do
                            hrp.CFrame = CFrame.new(stage4Pos.X, stage4Pos.Y + SBRConfig.TargetOffset.Y, stage4Pos.Z)
                            task.wait(0.25)
                        end
                    end
                end
                if node.Stage == 5 then
                    sbrStatus = "moving -> finish"
                else
                    sbrStatus = "moving -> stage " .. tostring(node.Stage)
                end

                local reached = _G.ODXFn_SBRMoveToNode(node, runId)
                if reached == "recovery" then
                    sbrStatus = "smart recovery: restored safe position"
                    local recoveryDeadline = os.clock() + 6
                    while _G.ODXSBRRecovery.Active
                        and ScriptActive and SBRConfig.Enabled
                        and runId == sbrRunId
                        and os.clock() < recoveryDeadline do
                        task.wait(0.1)
                    end
                    if not ScriptActive or not SBRConfig.Enabled or runId ~= sbrRunId then
                        break
                    end
                    reached = _G.ODXFn_SBRMoveToNode(node, runId)
                end
                if not reached then
                    break
                end
                task.wait(0.2)
            end

            if ScriptActive and SBRConfig.Enabled and runId == sbrRunId then
                sbrStatus = "route complete, hopping"
                Library:Notify("SBR finished, hopping to a new server")
                task.wait(2)
                pcall(function() _G.ODXFn_ServerHop(true) end)
            else
                sbrStatus = "off"
            end
            sbrMoving = false
        end)
    end

    _G.ODXFn_SBRScanCurrentMap = function()
        local route = _G.ODXFn_SBRRebuildRoute(true)
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local origin = hrp and hrp.Position or Vector3.zero

        print("---------------- SBR DYNAMIC DATA ----------------")
        print("Player position:", _G.ODXFn_SBRFormatVector(origin))
        print("SBR_Map route nodes:", #route)
        for _, node in ipairs(route) do
            print(string.format(
                "stage=%s | map=%s | object=%s | pos=%s",
                tostring(node.Stage),
                tostring(node.Name),
                node.Object and node.Object:GetFullName() or "?",
                _G.ODXFn_SBRFormatVector(node.Position)
            ))
        end
        print("Finish object:", Workspace:FindFirstChild("Finish") and Workspace.Finish:GetFullName() or "NOT FOUND")
        print("Current SBR status:", sbrStatus)
        print("---------------------------------------------------")

        sbrStatus = "scan complete: " .. tostring(#route) .. "/6 targets"
        Library:Notify("SBR dynamic scan: " .. tostring(#route) .. "/6 targets found. Check console.")
    end

    local LeftSBR = Tabs.SBR:AddGroupbox({ Side = "Left", Name = "Auto SBR" })
    local RightSBR = Tabs.SBR:AddGroupbox({ Side = "Right", Name = "Dynamic Route" })

    LeftSBR:AddToggle("SBRToggle", {
        Text = "Enable Auto SBR",
        Default = false,
        Callback = function(v)
            SBRConfig.Enabled = v
            if v then
                sbrStage4EndMessageSeen = false
                if _G.ODXFn_SBRHasStage4EndMessage() then
                    sbrStage4EndMessageSeen = true
                end
                _G.ODXFn_SBRCreateSafetyPlatform()
                local recovery = _G.ODXSBRRecovery
                recovery.Active = false
                recovery.SafeCFrame = nil
                recovery.StableSince = 0
                sbrStatus = "starting dynamic route"
                _G.ODXFn_SBRAutoLoop()
            else
                sbrStage4EndMessageSeen = false
                _G.ODXFn_SBRStopMovement()
                _G.ODXFn_SBRDestroySafetyPlatform()
                local recovery = _G.ODXSBRRecovery
                recovery.Active = false
                recovery.SafeCFrame = nil
                recovery.CurrentTween = nil
                sbrStatus = "off"
            end
        end,
    })

    LeftSBR:AddSlider("SBRTweenSpeed", {
        Text = "Dynamic SBR Speed",
        Default = 90, Min = 20, Max = 500, Rounding = 0,
        Callback = function(v)
            SBRConfig.TweenSpeed = v
        end,
    })

    LeftSBR:AddLabel("Underground Height: -5 (fixed)")
    LeftSBR:AddLabel("Stage 4: no player-count hold")
    LeftSBR:AddLabel("Stage 5: normal player height")

    LeftSBR:AddLabel("Route is built from Workspace.Map SBR_Map attributes")
    LeftSBR:AddLabel("No saved coordinates / no per-user setup")
    LeftSBR:AddLabel("No SBR AI Flight / no CFrame Flight mode")
    LeftSBR:AddLabel("Targets are resolved again every stage")
    LeftSBR:AddLabel("Closed barriers are detected and waited out")
    LeftSBR:AddLabel("Rise only while flying to finish")

    RightSBR:AddButton({
        Text = "Scan Current SBR Route",
        Func = function()
            pcall(_G.ODXFn_SBRScanCurrentMap)
        end,
    })

    RightSBR:AddButton({
        Text = "Rebuild Dynamic Route",
        Func = function()
            local route = _G.ODXFn_SBRRebuildRoute(true)
            Library:Notify("SBR route rebuilt: " .. tostring(#route) .. "/6 targets.")
        end,
    })

    RightSBR:AddLabel("0: Starting_Line -> Workspace.Map")
    RightSBR:AddLabel("Stage 1-4: Workspace.Map -> SBR_Map")
    RightSBR:AddLabel("Stage 5: Workspace.Finish")
    RightSBR:AddLabel("Starting line: SBR_Map = Starting_Line")
    RightSBR:AddLabel("Current server data only; nothing is saved")

    task.spawn(function()
        while ScriptActive do
            task.wait(5)
            if SBRConfig.Enabled and not _G.ODXFn_HasRevolver() and not sbrMoving then
                pcall(_G.ODXFn_TryJoinSBR)
            end
        end
    end)

    table.insert(Connections, RunService.Heartbeat:Connect(function()
        if not ScriptActive then
            return
        end
        if not SBRConfig.Enabled or sbrMoving then
            return
        end
        -- If the route ends because the map changed, rebuild it automatically.
        if #SBRConfig.Route < 6 then
            _G.ODXFn_SBRRebuildRoute(false)
        end
    end))

    -- OVERDRIVE X Music Player / local track library
    -- Tracks are downloaded from direct Catbox URLs, cached locally, and
    -- indexed in JSON so the library survives script restarts.
    local ODX_MUSIC_FOLDER = "OVERDRIVE_X"
    local ODX_MUSIC_INDEX = ODX_MUSIC_FOLDER .. "/music_library.json"
    local ODXMusicLibrary = {}
    local ODXMusicSelected = nil
    local ODXMusicSound = nil
    local ODXMusicEndedConnection = nil
    local ODXMusicPaused = false
    local ODXMusicInput = ""
    local ODXMusicRenameInput = ""
    local ODXMusicDropdown = nil
    local ODXMusicStatus = nil

    _G.ODXFn_ODXMusicNotify = function(text)
        pcall(function()
            if Library and Library.Notify then
                Library:Notify(text)
            end
        end)
    end

    _G.ODXFn_ODXMusicEnsureFolder = function()
        if type(writefile) ~= "function" then
            return false
        end
        if type(isfolder) == "function" and type(makefolder) == "function" then
            local ok, exists = pcall(isfolder, ODX_MUSIC_FOLDER)
            if not ok or not exists then
                pcall(makefolder, ODX_MUSIC_FOLDER)
            end
        elseif type(makefolder) == "function" then
            pcall(makefolder, ODX_MUSIC_FOLDER)
        end
        return true
    end

    _G.ODXFn_ODXMusicSave = function()
        if type(writefile) ~= "function" or type(HttpService.JSONEncode) ~= "function" then
            return false
        end
        _G.ODXFn_ODXMusicEnsureFolder()
        local ok, encoded = pcall(function()
            return HttpService:JSONEncode(ODXMusicLibrary)
        end)
        if not ok or type(encoded) ~= "string" then
            return false
        end
        return pcall(writefile, ODX_MUSIC_INDEX, encoded)
    end

    _G.ODXFn_ODXMusicLoad = function()
        ODXMusicLibrary = {}
        if type(isfile) ~= "function" or type(readfile) ~= "function" then
            return
        end
        local okExists, exists = pcall(isfile, ODX_MUSIC_INDEX)
        if not okExists or not exists then
            return
        end
        local okRead, body = pcall(readfile, ODX_MUSIC_INDEX)
        if not okRead or type(body) ~= "string" or body == "" then
            return
        end
        local okDecode, data = pcall(function()
            return HttpService:JSONDecode(body)
        end)
        if okDecode and type(data) == "table" then
            for _, track in ipairs(data) do
                if type(track) == "table" and type(track.Name) == "string"
                    and type(track.Url) == "string" and type(track.File) == "string" then
                    track.AutoReplay = track.AutoReplay == true
                    table.insert(ODXMusicLibrary, track)
                end
            end
        end
    end

    _G.ODXFn_ODXMusicShortName = function(url)
        local clean = tostring(url):gsub("[%?#].*$", "")
        local name = clean:match("/([^/]+)$") or "Track"
        name = name:gsub("%.[%w]+$", "")
        name = name:gsub("[_%-]+", " ")
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then name = "Track" end
        return name
    end

    _G.ODXFn_ODXMusicHash = function(text)
        local h = 7
        for i = 1, #text do
            h = (h * 131 + string.byte(text, i)) % 2147483647
        end
        return tostring(h)
    end

    _G.ODXFn_ODXMusicGetAsset = function(track)
        if not track or type(track.File) ~= "string" then
            return nil
        end
        if type(isfile) == "function" then
            local ok, exists = pcall(isfile, track.File)
            if not ok or not exists then
                return nil
            end
        end
        local getter = rawget(getgenv and getgenv() or _G, "getcustomasset")
            or rawget(getgenv and getgenv() or _G, "getsynasset")
        if type(getter) ~= "function" then
            getter = getcustomasset or getsynasset
        end
        if type(getter) ~= "function" then
            return nil
        end
        local ok, asset = pcall(getter, track.File)
        return ok and asset or nil
    end

    _G.ODXFn_ODXMusicRefreshDropdown = function()
        if not ODXMusicDropdown then return end
        local values = {}
        for _, track in ipairs(ODXMusicLibrary) do
            table.insert(values, track.Name)
        end
        if #values == 0 then
            values = {"No downloaded tracks"}
        end
        pcall(function()
            ODXMusicDropdown:SetValues(values)
        end)
    end

    _G.ODXFn_ODXMusicFind = function(name)
        for _, track in ipairs(ODXMusicLibrary) do
            if track.Name == name then
                return track
            end
        end
        return nil
    end

    _G.ODXFn_ODXMusicPauseToggle = function()
        if not ODXMusicSound or not ODXMusicSound.Parent then
            _G.ODXFn_ODXMusicNotify("Music Player: no track is currently loaded.")
            return false
        end

        local ok, isPlaying = pcall(function()
            return ODXMusicSound.IsPlaying
        end)
        if not ok then
            return false
        end

        if isPlaying then
            local pausedAt = 0
            pcall(function() pausedAt = ODXMusicSound.TimePosition end)
            local pauseOk = pcall(function() ODXMusicSound:Pause() end)
            if pauseOk then
                ODXMusicPaused = true
                if ODXMusicStatus and ODXMusicSelected then
                    pcall(function()
                        ODXMusicStatus:SetText(string.format("Paused: %s [%.1fs]", ODXMusicSelected.Name, pausedAt))
                    end)
                end
                return true
            end
        else
            if ODXMusicPaused then
                local resumeOk = pcall(function() ODXMusicSound:Resume() end)
                if resumeOk then
                    ODXMusicPaused = false
                    if ODXMusicStatus and ODXMusicSelected then
                        pcall(function() ODXMusicStatus:SetText("Playing: " .. ODXMusicSelected.Name) end)
                    end
                    return true
                end
            end
        end

        return false
    end

    _G.ODXFn_ODXMusicStop = function(keepIndependent)
        ODXMusicPaused = false
        if ODXMusicEndedConnection then
            pcall(function() ODXMusicEndedConnection:Disconnect() end)
            ODXMusicEndedConnection = nil
        end
        if ODXMusicSound then
            pcall(function()
                ODXMusicSound:Stop()
                ODXMusicSound:Destroy()
            end)
            ODXMusicSound = nil
        end
        if not keepIndependent then
            _G.ODXFn_ODXDisableIndependentAudio()
        end
    end

    _G.ODXFn_ODXMusicPlay = function(track)
        if not track then
            _G.ODXFn_ODXMusicNotify("Music Player: select a downloaded track first.")
            return false
        end
        local asset = _G.ODXFn_ODXMusicGetAsset(track)
        if not asset then
            _G.ODXFn_ODXMusicNotify("Music Player: local file is missing. Download the track again.")
            return false
        end

        _G.ODXFn_ODXMusicStop(true)
        ODXMusicPaused = false
        _G.ODXFn_ODXEnableIndependentAudio()
        local sound = Instance.new("Sound")
        sound.Name = "ODX_MusicPlayer"
        sound.SoundId = asset
        sound.Volume = 1
        sound.Looped = false
        sound.RollOffMode = Enum.RollOffMode.Linear
        sound.RollOffMaxDistance = 100000
        sound.SoundGroup = ODXPlayerSoundGroup
        pcall(function() ODXPlayerSoundGroup.Volume = ODXAudioSettings.PlayerVolume end)
        sound.Parent = SoundService
        ODXMusicSound = sound

        ODXMusicEndedConnection = sound.Ended:Connect(function()
            if ODXMusicSound ~= sound then return end
            if track.AutoReplay then
                task.wait(0.15)
                _G.ODXFn_ODXMusicPlay(track)
            else
                ODXMusicSound = nil
                ODXMusicPaused = false
                pcall(function() sound:Destroy() end)
                _G.ODXFn_ODXDisableIndependentAudio()
                if ODXMusicStatus then
                    pcall(function() ODXMusicStatus:SetText("Stopped: " .. track.Name) end)
                end
            end
        end)

        local ok = pcall(function() sound:Play() end)
        if ok and ODXMusicStatus then
            pcall(function()
                local suffix = track.AutoReplay and "  [AUTO REPLAY]" or ""
                ODXMusicStatus:SetText("Playing: " .. track.Name .. suffix)
            end)
        end
        if not ok then
            _G.ODXFn_ODXMusicStop()
            _G.ODXFn_ODXMusicNotify("Music Player: failed to start the local track.")
            return false
        end
        return true
    end

    -- Prefer the executor HTTP request API for binary Catbox files.
    -- game:HttpGet() is kept only as a fallback because some executors handle
    -- large/binary responses from Catbox poorly through the Roblox wrapper.
    _G.ODXFn_ODXMusicHttpGet = function(url)
        -- Try every common executor request path. Some executors expose request(),
        -- but return an empty Body for Catbox binary files; in that case we keep
        -- trying the other available transport instead of reporting a false error.
        local attempts = {}
        local env = {}
        pcall(function()
            if type(getgenv) == "function" then
                env = getgenv() or {}
            end
        end)

        local function addRequest(name, fn)
            if type(fn) == "function" then
                table.insert(attempts, {Name = name, Fn = fn})
            end
        end

        addRequest("request", rawget(env, "request"))
        addRequest("http_request", rawget(env, "http_request"))

        local envSyn = rawget(env, "syn")
        if type(envSyn) == "table" then
            addRequest("syn.request", envSyn.request)
        end

        addRequest("_G.request", rawget(_G, "request"))
        addRequest("_G.http_request", rawget(_G, "http_request"))

        local synTable = rawget(_G, "syn")
        if type(synTable) == "table" then
            addRequest("_G.syn.request", synTable.request)
        end

        local httpTable = rawget(_G, "http")
        if type(httpTable) == "table" then
            addRequest("http.request", httpTable.request)
        end

        local lastError = nil
        local lastStatus = nil

        for _, attempt in ipairs(attempts) do
            local ok, response = pcall(attempt.Fn, {
                Url = url,
                Method = "GET",
                Headers = {
                    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/154.0 Safari/537.36",
                    ["Accept"] = "audio/*,application/octet-stream,*/*;q=0.8",
                    ["Accept-Encoding"] = "identity",
                    ["Cache-Control"] = "no-cache",
                    ["Pragma"] = "no-cache",
                    ["Referer"] = "https://files.catbox.moe/",
                },
            })

            if ok and type(response) == "table" then
                local body = response.Body or response.body
                local status = tonumber(response.StatusCode or response.Status or response.status_code)
                lastStatus = status or lastStatus

                if status and (status < 200 or status >= 300) then
                    lastError = "HTTP " .. tostring(status) .. " via " .. attempt.Name
                elseif type(body) == "string" and #body > 0 then
                    return true, body, status or 200, attempt.Name
                else
                    lastError = "empty response via " .. attempt.Name
                end
            else
                lastError = "request failed via " .. attempt.Name .. ": " .. tostring(response)
            end
        end

        -- Roblox's wrapper is a useful fallback. It is intentionally tried even
        -- when an executor request function existed but returned an empty body.
        local ok, body = pcall(function()
            return game:HttpGet(url)
        end)
        if ok and type(body) == "string" and #body > 0 then
            return true, body, 200, "game:HttpGet fallback"
        end

        if ok and type(body) == "string" then
            lastError = "empty response via game:HttpGet"
        elseif not ok then
            lastError = "HttpGet error: " .. tostring(body)
        end

        return false, nil, lastStatus, lastError or "all HTTP methods returned an empty response"
    end

    _G.ODXFn_ODXMusicDownload = function(url)
        url = tostring(url or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if url == "" then
            _G.ODXFn_ODXMusicNotify("Music Player: paste a Catbox .mp3/.ogg/.wav link first.")
            return
        end
        if not url:match("^https?://files%.catbox%.moe/") then
            _G.ODXFn_ODXMusicNotify("Music Player: only direct Catbox links are supported.")
            return
        end

        local cleanUrl = url:gsub("[%?#].*$", "")
        local extension = cleanUrl:match("%.([%w]+)$")
        extension = extension and extension:lower() or "mp3"
        if extension ~= "mp3" and extension ~= "ogg" and extension ~= "wav" then
            _G.ODXFn_ODXMusicNotify("Music Player: supported formats are MP3 / OGG / WAV.")
            return
        end

        for _, existing in ipairs(ODXMusicLibrary) do
            if existing.Url == url then
                _G.ODXFn_ODXMusicNotify("Music Player: this track is already in the list.")
                ODXMusicSelected = existing
                return
            end
        end

        if not _G.ODXFn_ODXMusicEnsureFolder() or type(writefile) ~= "function" then
            _G.ODXFn_ODXMusicNotify("Music Player: executor does not provide local file storage.")
            return
        end

        _G.ODXFn_ODXMusicNotify("Music Player: downloading track...")
        if ODXMusicStatus then
            pcall(function() ODXMusicStatus:SetText("Downloading: " .. url) end)
        end
        local ok, body, statusCode, source = _G.ODXFn_ODXMusicHttpGet(url)

        if not ok or type(body) ~= "string" then
            local detail = tostring(source or "unknown HTTP error")
            if statusCode then
                detail = "HTTP " .. tostring(statusCode) .. " • " .. detail
            end
            _G.ODXFn_ODXMusicNotify("Music Player: " .. detail)
            if ODXMusicStatus then
                pcall(function() ODXMusicStatus:SetText("Download failed: " .. detail) end)
            end
            return
        end

        -- Do not reject a valid audio file just because it is small. Instead,
        -- reject obvious HTML/JSON error pages returned by a proxy or CDN.
        local head = body:sub(1, 64):lower()
        local looksLikeErrorPage = head:find("<html", 1, true) or head:find("<!doctype", 1, true) or head:find("{\"error", 1, true)
        if looksLikeErrorPage then
            local preview = body:gsub("[%c]", " "):sub(1, 140)
            local detail = "server returned non-audio data"
            if preview ~= "" then
                detail = detail .. " • " .. preview
            end
            _G.ODXFn_ODXMusicNotify("Music Player: " .. detail)
            if ODXMusicStatus then
                pcall(function() ODXMusicStatus:SetText("Download failed: " .. detail) end)
            end
            return
        end

        local sizeMB = #body / 1048576
        if ODXMusicStatus then
            pcall(function()
                ODXMusicStatus:SetText(string.format("Downloaded %.2f MB • saving...", sizeMB))
            end)
        end

        local file = ODX_MUSIC_FOLDER .. "/track_" .. _G.ODXFn_ODXMusicHash(url) .. "." .. extension
        local writeOk, writeErr = pcall(writefile, file, body)
        if not writeOk then
            _G.ODXFn_ODXMusicNotify("Music Player: could not save the local file • " .. tostring(writeErr))
            if ODXMusicStatus then
                pcall(function() ODXMusicStatus:SetText("Save failed: " .. tostring(writeErr)) end)
            end
            return
        end

        local track = {
            Name = _G.ODXFn_ODXMusicShortName(url),
            Url = url,
            File = file,
            AutoReplay = false,
        }
        table.insert(ODXMusicLibrary, track)
        ODXMusicSelected = track
        _G.ODXFn_ODXMusicSave()
        _G.ODXFn_ODXMusicRefreshDropdown()
        _G.ODXFn_ODXMusicNotify(string.format("Music Player: %s downloaded and saved locally (%.2f MB).", track.Name, sizeMB))
        if ODXMusicStatus then
            pcall(function() ODXMusicStatus:SetText("Ready: " .. track.Name) end)
        end
    end

    _G.ODXFn_ODXMusicLoad()


    --// v1.3 PERFORMANCE STATS + SYSTEM DIAGNOSTICS
    _G.ODXPerformanceStats = _G.ODXPerformanceStats or {
        FPS = 0,
        FrameMs = 0,
        MemoryMB = 0,
        Ping = "?",
        Updated = 0,
    }

    _G.ODXGetPerformanceSnapshot = function()
        local StatsService = game:GetService("Stats")
        local stats = _G.ODXPerformanceStats

        pcall(function()
            local pingItem = StatsService.Network.ServerStatsItem["Data Ping"]
            local value = pingItem and pingItem:GetValue()
            if tonumber(value) then
                stats.Ping = tostring(math.floor(value + 0.5)) .. " ms"
            end
        end)

        pcall(function()
            local memory = StatsService:GetTotalMemoryUsageMb()
            if tonumber(memory) then
                stats.MemoryMB = memory
            end
        end)

        stats.Updated = os.clock()
        return stats
    end

    local LeftSystemGroup = Tabs.System:AddGroupbox({ Side = "Left", Name = "Server Hop" })
    local RightSystemGroup = Tabs.System:AddGroupbox({ Side = "Right", Name = "Console & Management" })
    local ODXPerfGroup = Tabs.System:AddGroupbox({ Side = "Right", Name = "Performance Stats" })
    local ODXPerfLabel = ODXPerfGroup:AddLabel("FPS: --\nFrame: -- ms\nPing: --\nMemory: -- MB", true, "ODXPerformanceStatsLabel")
    local ODXDiagLabel = ODXPerfGroup:AddLabel("System: ready", true, "ODXSystemDiagnosticsLabel")

    _G.ODXFn_ODXRunSystemDiagnostics = function()
        local checks = {}
        local function add(name, ok, detail)
            table.insert(checks, string.format("%s: %s%s", name, ok and "OK" or "WARN", detail and (" • " .. tostring(detail)) or ""))
        end

        add("Workspace", Workspace ~= nil)
        add("Character", LocalPlayer.Character ~= nil)
        add("SBR route", #((SBRConfig and SBRConfig.Route) or {}) >= 6, tostring(#((SBRConfig and SBRConfig.Route) or {})) .. "/6")
        add("SBR recovery", _G.ODXSBRRecovery ~= nil)
        add("Music library", type(ODXMusicLibrary) == "table", tostring(#(ODXMusicLibrary or {})) .. " tracks")
        add("writefile", type(writefile) == "function")
        add("readfile", type(readfile) == "function")
        add("getcustomasset", type(getcustomasset) == "function" or type(getsynasset) == "function")
        add("request", type(request) == "function" or type(http_request) == "function" or type(syn and syn.request) == "function")

        local text = table.concat(checks, "\n")
        pcall(function()
            ODXDiagLabel:SetText(text)
        end)
        pcall(function()
            Library:Notify("System Diagnostics completed.")
        end)
        return text
    end

    RightSystemGroup:AddButton({
        Text = "System Diagnostics",
        Func = function()
            pcall(_G.ODXFn_ODXRunSystemDiagnostics)
        end,
    })

    RightSystemGroup:AddButton({
        Text = "SBR Smart Recovery Test",
        Func = function()
            local recovery = _G.ODXSBRRecovery
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if recovery and hrp then
                recovery.SafeCFrame = hrp.CFrame
                recovery.Recoveries = recovery.Recoveries + 1
                Library:Notify("SBR recovery checkpoint captured.")
            else
                Library:Notify("SBR recovery: character/root not available.")
            end
        end,
    })

    task.spawn(function()
        local lastClock = os.clock()
        while ScriptActive do
            local now = os.clock()
            local dt = now - lastClock
            lastClock = now
            if dt > 0 then
                local fps = math.clamp(1 / dt, 0, 240)
                local stats = _G.ODXPerformanceStats
                stats.FPS = stats.FPS * 0.85 + fps * 0.15
                stats.FrameMs = stats.FPS > 0 and (1000 / stats.FPS) or 0
                _G.ODXGetPerformanceSnapshot()

                pcall(function()
                    ODXPerfLabel:SetText(string.format(
                        "FPS: %d\nFrame: %.1f ms\nPing: %s\nMemory: %.0f MB\nSBR recoveries: %d",
                        math.floor(stats.FPS + 0.5),
                        stats.FrameMs,
                        tostring(stats.Ping),
                        tonumber(stats.MemoryMB) or 0,
                        tonumber(_G.ODXSBRRecovery.Recoveries) or 0
                    ))
                end)
            end
            task.wait(1)
        end
    end)


    local LeftMusicGroup = Tabs.System:AddGroupbox({ Side = "Left", Name = "Music Library" })
    local RightMusicGroup = Tabs.System:AddGroupbox({ Side = "Right", Name = "Music Player" })

    LeftMusicGroup:AddLabel("CATBOX TRACK DOWNLOADER")
    LeftMusicGroup:AddLabel("Paste a direct Catbox audio link.")

    local ODXMusicInputBox = LeftMusicGroup:AddInput("ODXMusicUrlInput", {
        Default = "",
        Numeric = false,
        Finished = false,
        ClearTextOnFocus = false,
        Text = "Catbox Track URL",
        Placeholder = "https://files.catbox.moe/track.mp3",
        Callback = function(Value)
            ODXMusicInput = tostring(Value or "")
        end,
    })

    LeftMusicGroup:AddButton({
        Text = "Download",
        Func = function()
            _G.ODXFn_ODXMusicDownload(ODXMusicInput)
        end,
    })

    LeftMusicGroup:AddLabel("Saved tracks survive script restarts.")
    LeftMusicGroup:AddLabel("Files: OVERDRIVE_X/track_<id>.<format>")

    LeftMusicGroup:AddSlider("ODXLoadingVolumeSlider", {
        Text = "Loading Music Volume",
        Default = math.floor(ODXAudioSettings.LoadingVolume * 100 + 0.5),
        Min = 0,
        Max = 100,
        Rounding = 0,
        Callback = function(Value)
            ODXAudioSettings.LoadingVolume = math.clamp((tonumber(Value) or 35) / 100, 0, 1)
            pcall(function() ODXLoadingSoundGroup.Volume = ODXAudioSettings.LoadingVolume end)
            _G.ODXFn_ODXSaveAudioSettings()
        end,
    })

    ODXMusicDropdown = RightMusicGroup:AddDropdown("ODXMusicTrackDropdown", {
        Values = {},
        Default = 1,
        Text = "Select Track",
        Callback = function(Value)
            if Value and Value ~= "No downloaded tracks" then
                ODXMusicSelected = _G.ODXFn_ODXMusicFind(Value)
                if ODXMusicStatus and ODXMusicSelected then
                    local suffix = ODXMusicSelected.AutoReplay and "  [AUTO REPLAY]" or ""
                    pcall(function()
                        ODXMusicStatus:SetText("Selected: " .. ODXMusicSelected.Name .. suffix)
                    end)
                end
            else
                ODXMusicSelected = nil
            end
        end,
    })

    ODXMusicStatus = RightMusicGroup:AddLabel("No track selected.", true, "ODXMusicStatusLabel")

    RightMusicGroup:AddSlider("ODXPlayerVolumeSlider", {
        Text = "Player Music Volume",
        Default = math.floor(ODXAudioSettings.PlayerVolume * 100 + 0.5),
        Min = 0,
        Max = 100,
        Rounding = 0,
        Callback = function(Value)
            ODXAudioSettings.PlayerVolume = math.clamp((tonumber(Value) or 35) / 100, 0, 1)
            pcall(function() ODXPlayerSoundGroup.Volume = ODXAudioSettings.PlayerVolume end)
            _G.ODXFn_ODXSaveAudioSettings()
        end,
    })

    RightMusicGroup:AddLabel("OVERDRIVE X audio has its own volume controls.")
    RightMusicGroup:AddLabel("Independent Audio: Roblox 0% bypass via executor MasterVolume override.")

    RightMusicGroup:AddButton({
        Text = "Play",
        Func = function()
            _G.ODXFn_ODXMusicPlay(ODXMusicSelected)
        end,
    })

    RightMusicGroup:AddButton({
        Text = "Pause / Resume",
        Func = function()
            if not _G.ODXFn_ODXMusicPauseToggle() and ODXMusicStatus and not ODXMusicSound then
                pcall(function() ODXMusicStatus:SetText("No track is playing.") end)
            end
        end,
    })

    RightMusicGroup:AddButton({
        Text = "Stop",
        Func = function()
            _G.ODXFn_ODXMusicStop()
            if ODXMusicStatus then
                pcall(function()
                    if ODXMusicSelected then
                        ODXMusicStatus:SetText("Stopped: " .. ODXMusicSelected.Name)
                    else
                        ODXMusicStatus:SetText("No track selected.")
                    end
                end)
            end
        end,
    })

    RightMusicGroup:AddButton({
        Text = "Set as Auto Replay",
        Func = function()
            if not ODXMusicSelected then
                _G.ODXFn_ODXMusicNotify("Music Player: select a track first.")
                return
            end
            ODXMusicSelected.AutoReplay = true
            _G.ODXFn_ODXMusicSave()
            if ODXMusicStatus then
                pcall(function() ODXMusicStatus:SetText("Selected: " .. ODXMusicSelected.Name .. "  [AUTO REPLAY]") end)
            end
            _G.ODXFn_ODXMusicNotify("Auto Replay enabled: " .. ODXMusicSelected.Name)
        end,
    })

    RightMusicGroup:AddButton({
        Text = "Remove as Auto Replay",
        Func = function()
            if not ODXMusicSelected then
                _G.ODXFn_ODXMusicNotify("Music Player: select a track first.")
                return
            end
            ODXMusicSelected.AutoReplay = false
            _G.ODXFn_ODXMusicSave()
            if ODXMusicStatus then
                pcall(function() ODXMusicStatus:SetText("Selected: " .. ODXMusicSelected.Name) end)
            end
            _G.ODXFn_ODXMusicNotify("Auto Replay disabled: " .. ODXMusicSelected.Name)
        end,
    })

    RightMusicGroup:AddButton({
        Text = "Remove from List",
        Func = function()
            if not ODXMusicSelected then
                _G.ODXFn_ODXMusicNotify("Music Player: select a track first.")
                return
            end
            local removed = ODXMusicSelected
            if ODXMusicSound then
                local current = ODXMusicSelected
                if current == removed then
                    _G.ODXFn_ODXMusicStop()
                end
            end
            for i = #ODXMusicLibrary, 1, -1 do
                if ODXMusicLibrary[i] == removed then
                    table.remove(ODXMusicLibrary, i)
                    break
                end
            end
            if type(delfile) == "function" and removed.File then
                pcall(delfile, removed.File)
            end
            ODXMusicSelected = nil
            _G.ODXFn_ODXMusicSave()
            _G.ODXFn_ODXMusicRefreshDropdown()
            if ODXMusicStatus then
                pcall(function() ODXMusicStatus:SetText("No track selected.") end)
            end
            _G.ODXFn_ODXMusicNotify("Removed: " .. removed.Name)
        end,
    })

    RightMusicGroup:AddInput("ODXMusicRenameInput", {
        Default = "",
        Numeric = false,
        Finished = false,
        ClearTextOnFocus = false,
        Text = "New Track Name",
        Placeholder = "Enter your track name",
        Callback = function(Value)
            ODXMusicRenameInput = tostring(Value or "")
        end,
    })

    RightMusicGroup:AddButton({
        Text = "Rename",
        Func = function()
            if not ODXMusicSelected then
                _G.ODXFn_ODXMusicNotify("Music Player: select a track first.")
                return
            end

            local newName = tostring(ODXMusicRenameInput or "")
                :gsub("^%s+", "")
                :gsub("%s+$", "")
                :gsub("[\r\n]", " ")

            if newName == "" then
                _G.ODXFn_ODXMusicNotify("Music Player: enter a new track name first.")
                return
            end

            if #newName > 40 then
                newName = newName:sub(1, 40)
            end

            for _, track in ipairs(ODXMusicLibrary) do
                if track ~= ODXMusicSelected and track.Name:lower() == newName:lower() then
                    _G.ODXFn_ODXMusicNotify("Music Player: this name is already in use.")
                    return
                end
            end

            ODXMusicSelected.Name = newName
            _G.ODXFn_ODXMusicSave()
            _G.ODXFn_ODXMusicRefreshDropdown()
            if ODXMusicStatus then
                pcall(function()
                    local suffix = ODXMusicSelected.AutoReplay and "  [AUTO REPLAY]" or ""
                    ODXMusicStatus:SetText("Selected: " .. newName .. suffix)
                end)
            end
            _G.ODXFn_ODXMusicNotify("Track renamed to: " .. newName)
        end,
    })

    _G.ODXFn_ODXMusicRefreshDropdown()

    _G.ODXFn_ServerHop = function(lowest)
        Library:Notify("Searching for server...")
        local servers, cursor = {}, ""
        repeat
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
            if cursor ~= "" then
                url = url .. "&cursor=" .. cursor
            end
            local success, res = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(url))
            end)
            if success and res and res.data then
                for _, s in ipairs(res.data) do
                    if type(s) == "table" and s.id and s.playing and s.maxPlayers and s.playing < s.maxPlayers and s.id ~= game.JobId then
                        table.insert(servers, s)
                    end
                end
                cursor = res.nextPageCursor
            else
                break
            end
        until cursor == nil or #servers > 50

        if #servers > 0 then
            if lowest then
                table.sort(servers, function(a, b)
                    return a.playing < b.playing
                end)
            else
                table.sort(servers, function(a, b)
                    return a.playing > b.playing
                end)
            end
            Library:Notify("Teleporting to server (" .. servers[1].playing .. " players)...")
            task.wait(0.5)
            TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1].id, LocalPlayer)
        else
            Library:Notify("No suitable servers found!")
        end
    end

    LeftSystemGroup:AddButton({
        Text = "Server Hop (To Lowest Players)",
        Func = function()
            pcall(function()
                _G.ODXFn_ServerHop(true)
            end)
        end,
    })
    LeftSystemGroup:AddButton({
        Text = "Server Hop (To Highest Players)",
        Func = function()
            pcall(function()
                _G.ODXFn_ServerHop(false)
            end)
        end,
    })

    RightSystemGroup:AddLabel("No errors detected.", true, "TerminalLabelOpt")
    RightSystemGroup:AddButton({
        Text = "Clear Logs",
        Func = function()
            TerminalLogs = {}
            pcall(function()
                if Options and Options.TerminalLabelOpt then
                    Options.TerminalLabelOpt:SetText("No errors detected.")
                end
            end)
        end,
    })

    task.spawn(function()
        while ScriptActive do
            task.wait(0.5)
            if #TerminalLogs > 0 then
                pcall(function()
                    if Options and Options.TerminalLabelOpt then
                        Options.TerminalLabelOpt:SetText(table.concat(TerminalLogs, "\n"))
                    end
                end)
            end
        end
    end)

    RightSystemGroup:AddButton({
        Text = "Unload Script",
        Func = function()
            ScriptActive = false
    _G.ODXScriptActive = false
            for _, conn in ipairs(Connections) do
                pcall(function()
                    if conn then
                        conn:Disconnect()
                    end
                end)
            end
            pcall(function()
                local char = LocalPlayer.Character
                if char then
                    for _, p in ipairs(char:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.CanCollide = true
                        end
                    end
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum.WalkSpeed = 16
                    end
                end
                if Workspace.CurrentCamera then
                    Workspace.CurrentCamera.FieldOfView = 70
                end
            end)
            local container = CoreGui:FindFirstChild("OVERDRIVE_ESP_Container")
            if container then
                container:Destroy()
            end
            for _, data in pairs(ItemConfig.Trackers) do
                if data.Bb then
                    data.Bb:Destroy()
                end
                if data.Hl then
                    data.Hl:Destroy()
                end
            end
            pcall(function() _G.ODXFn_ODXMusicStop() end)
            pcall(function() _G.ODXFn_ODXMusicSave() end)
            pcall(function()
                Library:Unload()
            end)
        end,
    })

    if SaveManager and Library then
        pcall(function()
            SaveManager:SetLibrary(Library)
            SaveManager:SetFolder("OverdriveX_YBA")
            SaveManager:IgnoreThemeSettings()
            SaveManager:SetIgnoreIndexes({"SaveManager_ConfigList", "SaveManager_ConfigName", "SaveManager_JSON"})
            SaveManager:BuildConfigSection(Tabs.Config)
            SaveManager:LoadAutoloadConfig()
        end)
    else
        local FallbackGroup = Tabs.Config:AddGroupbox({ Side = "Left", Name = "Config Error" })
        FallbackGroup:AddLabel("SaveManager failed to load!")
    end

    local LeftCreditsGroup = Tabs.Credits:AddGroupbox({ Side = "Left", Name = "Author Information" })
    local RightCreditsGroup = Tabs.Credits:AddGroupbox({ Side = "Right", Name = "Thanks To" })
    LeftCreditsGroup:AddLabel("Developer / Owner:")
    LeftCreditsGroup:AddLabel("stendexe")
    LeftCreditsGroup:AddLabel("Project:")
    LeftCreditsGroup:AddLabel("OVERDRIVE X | YBA Edition")
    RightCreditsGroup:AddLabel("Thanks To:")
    RightCreditsGroup:AddLabel("fg")
    RightCreditsGroup:AddLabel("For testing Overdrive X")
    RightCreditsGroup:AddLabel("on potassium")
    RightCreditsGroup:AddLabel("guts")
    RightCreditsGroup:AddLabel("For testing Overdrive X on mobile (Delta)")

    local SpecialThanksGroup = Tabs.Credits:AddGroupbox({ Side = "Right", Name = "Special Thanks" })
    SpecialThanksGroup:AddLabel("special thanks TO")
    SpecialThanksGroup:AddLabel("everyone for using")
    SpecialThanksGroup:AddLabel("Overdrive X, happy")
    SpecialThanksGroup:AddLabel("halloween🎃")

    math.randomseed(tick())

    _G.ODXFn_GetRandomFloat = function(min, max)
        return min + math.random() * (max - min)
    end

    _G.ODXFn_ClickButtonObj = function(btn, safeOnly)
        pcall(function()
            if not btn or not btn.Parent then
                return
            end
            if not safeOnly and getconnections then
                pcall(function()
                    for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do
                        if conn.Function then
                            conn:Fire()
                        end
                    end
                end)
            end
            local pos = btn.AbsolutePosition + (btn.AbsoluteSize / 2)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            task.wait(0.06)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
        end)
    end

    _G.ODXFn_FindButtonByKeywords = function(keywords)
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then
            return nil
        end
        for _, gui in ipairs(playerGui:GetDescendants()) do
            if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                local foundText = ""
                if gui:IsA("TextButton") and gui.Text ~= "" then
                    foundText = gui.Text:lower()
                end
                if foundText == "" and gui.Name ~= "" then
                    foundText = gui.Name:lower()
                end
                if foundText == "" then
                    for _, child in ipairs(gui:GetDescendants()) do
                        if child:IsA("TextLabel") and child.Text ~= "" then
                            foundText = child.Text:lower()
                            break
                        end
                    end
                end
                for _, kw in ipairs(keywords) do
                    if foundText:find(kw:lower(), 1, true) then
                        return gui
                    end
                end
            end
        end
        return nil
    end

    _G.ODXFn_ClickGuiByText = function(keywords, safeOnly)
        local btn = _G.ODXFn_FindButtonByKeywords(keywords)
        if btn then
            _G.ODXFn_ClickButtonObj(btn, safeOnly == true)
            return true
        end
        return false
    end

    _G.ODXFn_FindClickToContinue = function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then
            return nil
        end
        for _, gui in ipairs(playerGui:GetDescendants()) do
            if gui:IsA("TextLabel") or gui:IsA("TextButton") then
                local t = tostring(gui.Text or ""):upper()
                if t:find("CLICK TO CONTINUE", 1, true) or t:find("CLICK TO CONT", 1, true) then
                    return gui
                end
            end
        end
        return nil
    end

    _G.ODXFn_HasClickToContinue = function()
        return _G.ODXFn_FindClickToContinue() ~= nil
    end

    _G.ODXFn_ClickScreenOnce = function(delayBeforeClick)
        local label = _G.ODXFn_FindClickToContinue()
        local cam = Workspace.CurrentCamera
        if not cam then
            return
        end
        local inset = game:GetService("GuiService"):GetGuiInset()
        local x, y
        if label and label.AbsoluteSize.X > 0 then
            local pos = label.AbsolutePosition + (label.AbsoluteSize / 2) + inset
            x, y = pos.X, pos.Y
        else
            local vp = cam.ViewportSize
            x, y = vp.X * 0.5, vp.Y * 0.62 + inset.Y
        end
        if delayBeforeClick and delayBeforeClick > 0 then
            task.wait(delayBeforeClick)
        end
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.03)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end

    _G.ODXFn_ClearClickToContinue = function(delayBeforeClick)
        for _ = 1, 10 do
            if not _G.ODXFn_HasClickToContinue() then
                return
            end
            _G.ODXFn_ClickScreenOnce(delayBeforeClick)
            task.wait(0.2)
        end
    end

    -- Auto decline Cosmetic Roller NPC dialogue
    _G.ODXFn_IsCosmeticRollerDialog = function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then return false end
        for _, gui in ipairs(playerGui:GetDescendants()) do
            if (gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox")) and gui.Text and gui.Text ~= "" then
                local t = gui.Text:lower()
                if t:find("cosmetic roller", 1, true)
                    or t:find("cosmetic roll", 1, true)
                    or t:find("roll cosmetics", 1, true) then
                    return true
                end
            end
        end
        return false
    end

    _G.ODXFn_DeclineCosmeticRoller = function()
        if not _G.ODXFn_IsCosmeticRollerDialog() then
            return false
        end
        local keywords = {
            "no thanks", "no thank", "nothanks", "no, thanks",
            "decline", "reject", "leave", "nevermind", "never mind",
            "close", "cancel", "exit",
        }
        local btn = _G.ODXFn_FindButtonByKeywords(keywords)
        if btn then
            pcall(_G.ODXFn_ClickButtonObj, btn)
            return true
        end
        -- Fallback: scan all text buttons for "no thanks"
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then return false end
        for _, gui in ipairs(playerGui:GetDescendants()) do
            if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                local t = ""
                if gui:IsA("TextButton") then t = (gui.Text or ""):lower() end
                if t == "" then t = (gui.Name or ""):lower() end
                for _, child in ipairs(gui:GetDescendants()) do
                    if child:IsA("TextLabel") and child.Text ~= "" then
                        t = t .. " " .. child.Text:lower()
                    end
                end
                if t:find("no thanks", 1, true) or t:find("no thank", 1, true) then
                    pcall(_G.ODXFn_ClickButtonObj, gui)
                    return true
                end
            end
        end
        return false
    end

    task.spawn(function()
        while ScriptActive do
            task.wait(0.35)
            pcall(_G.ODXFn_DeclineCosmeticRoller)
        end
    end)

    _G.ODXFn_ClickAllQuestDialogs = function()
        for _ = 1, 6 do
            local btn = _G.ODXFn_FindButtonByKeywords(QuestRetakeKeywords)
            if btn then
                _G.ODXFn_ClickButtonObj(btn)
                task.wait(0.3)
            end
            btn = _G.ODXFn_FindButtonByKeywords(QuestOtherKeywords)
            if btn then
                _G.ODXFn_ClickButtonObj(btn)
                task.wait(0.25)
            end
            if _G.ODXFn_HasClickToContinue() then
                _G.ODXFn_ClickScreenOnce()
                task.wait(0.2)
            else
                task.wait(0.12)
            end
        end
    end

    _G.ODXFn_GetSpecificNPC = function(npcKey)
        if not npcKey or npcKey == "__COORDS__" then
            return nil
        end
        local candidates = {}
        for _, v in ipairs(Workspace:GetDescendants()) do
            if v:IsA("Model") and v:FindFirstChild("HumanoidRootPart") then
                local exact = (v.Name == npcKey)
                local soft = (not exact) and v.Name:lower():find(npcKey:lower(), 1, true)
                if exact or soft then
                    local livingFolder = Workspace:FindFirstChild("Living")
                    local inLiving = livingFolder and v:IsDescendantOf(livingFolder)
                    local hasPrompt = v:FindFirstChildOfClass("ProximityPrompt")
                        or v.HumanoidRootPart:FindFirstChildOfClass("ProximityPrompt")
                        or v:FindFirstChildWhichIsA("ProximityPrompt", true)
                    table.insert(candidates, {
                        Model = v,
                        Exact = exact,
                        HasPrompt = hasPrompt ~= nil,
                        InLiving = inLiving and true or false,
                    })
                end
            end
        end
        table.sort(candidates, function(a, b)
            local sa = (a.Exact and 8 or 0) + (a.HasPrompt and 4 or 0) + (not a.InLiving and 2 or 0)
            local sb = (b.Exact and 8 or 0) + (b.HasPrompt and 4 or 0) + (not b.InLiving and 2 or 0)
            return sa > sb
        end)
        if #candidates > 0 then
            return candidates[1].Model
        end
        return nil
    end

    _G.ODXFn_GetNPCNearCoords = function(pos, maxDist)
        maxDist = maxDist or 25
        local best, bestDist = nil, maxDist
        for _, v in ipairs(Workspace:GetDescendants()) do
            if v:IsA("Model") and v:FindFirstChild("HumanoidRootPart") then
                local d = (v.HumanoidRootPart.Position - pos).Magnitude
                if d < bestDist then
                    local hasPrompt = v:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if hasPrompt or d < 12 then
                        bestDist = d
                        best = v
                    end
                end
            end
        end
        return best
    end

    _G.ODXFn_GetBackpackItemCount = function(itemName)
        local count = 0
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        local char = LocalPlayer.Character
        if backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                if item.Name == itemName then
                    count = count + 1
                end
            end
        end
        if char then
            for _, item in ipairs(char:GetChildren()) do
                if item.Name == itemName then
                    count = count + 1
                end
            end
        end
        return count
    end

    _G.ODXFn_EquipItem = function(itemName)
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        local char = LocalPlayer.Character
        if not char then
            return false
        end
        for _, item in ipairs(char:GetChildren()) do
            if item.Name == itemName then
                return true
            end
        end
        if backpack then
            for _, item in ipairs(backpack:GetChildren()) do
                if item.Name == itemName then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum:EquipTool(item)
                        task.wait(0.3)
                        return true
                    end
                end
            end
        end
        return false
    end

    _G.ODXFn_UseEquippedTool = function()
        local char = LocalPlayer.Character
        local tool = char and char:FindFirstChildOfClass("Tool")
        if not tool then
            return false
        end
        pcall(function() tool:Activate() end)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        return true
    end

    _G.ODXFn_GetCurrentStand = function()
        local stats = LocalPlayer:FindFirstChild("PlayerStats")
        local stand = stats and stats:FindFirstChild("Stand")
        if stand and type(stand.Value) == "string" and stand.Value ~= "" then
            return stand.Value
        end
        return "None"
    end

    _G.ODXFn_GetStandSkin = function()
        local char = LocalPlayer.Character
        local remote = char and char:FindFirstChild("RemoteFunction")
        if not remote then
            return "None"
        end
        local ok, skin = pcall(function()
            return remote:InvokeServer("ReturnStandSkin", "Stand")
        end)
        if ok and type(skin) == "string" and skin ~= "" and skin ~= "None" and skin:lower() ~= "default" then
            return skin
        end
        return "None"
    end

    _G.ODXFn_LearnWorthiness = function()
        local char = LocalPlayer.Character
        if not char then
            return false
        end
        local skills = {"Worthiness", "Worthiness I"}
        local function fire(remote)
            if not remote then
                return
            end
            for _, skill in ipairs(skills) do
                local payload = {Skill = skill, SkillTreeType = "Character"}
                pcall(function() remote:FireServer("LearnSkill", payload) end)
                pcall(function() remote:FireServer("LearnSkill3point0", payload) end)
            end
        end
        fire(char:FindFirstChild("RemoteEvent"))
        local remoteFn = char:FindFirstChild("RemoteFunction")
        if remoteFn then
            task.spawn(function()
                for _, skill in ipairs(skills) do
                    pcall(function()
                        remoteFn:InvokeServer("LearnSkill", {Skill = skill, SkillTreeType = "Character"})
                    end)
                end
            end)
        end
        return true
    end

    _G.ODXFn_HasWorthiness = function()
        local stats = LocalPlayer:FindFirstChild("PlayerStats")
        if not stats then
            return false
        end
        for _, obj in ipairs(stats:GetDescendants()) do
            local name = obj.Name:lower()
            if name:find("worth") then
                if obj:IsA("BoolValue") and obj.Value then
                    return true
                end
                if (obj:IsA("NumberValue") or obj:IsA("IntValue")) and tonumber(obj.Value) and obj.Value >= 1 then
                    return true
                end
                if obj:IsA("StringValue") and obj.Value ~= "" and obj.Value ~= "None" and obj.Value ~= "0" then
                    return true
                end
            end
        end
        return false
    end

    _G.ODXFn_WaitForWorthiness = function()
        _G.ODXFn_LearnWorthiness()
        local learn = _G.ODXFn_FindButtonByKeywords({"learn"})
        if learn then
            _G.ODXFn_ClickButtonObj(learn)
            task.wait(0.2)
            _G.ODXFn_ClickButtonObj(learn)
        end
        task.wait(0.6)
        return true
    end

    _G.ODXFn_ConfirmItemDialogue = function(delayBeforeClick)
        local started = tick()
        while tick() - started < 8 do
            local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
            local yesBtn = nil
            if playerGui then
                for _, gui in ipairs(playerGui:GetDescendants()) do
                    local text = ""
                    if gui:IsA("TextButton") or gui:IsA("TextLabel") then
                        text = gui.Text or ""
                    end
                    if text == "" and (gui:IsA("ImageButton") or gui:IsA("TextButton") or gui:IsA("Frame")) then
                        local label = gui:FindFirstChildWhichIsA("TextLabel", true)
                        text = label and label.Text or ""
                    end
                    local flat = tostring(text):lower():gsub("%s+", "")
                    if flat == "yes" or flat:find("acceptandletitmerge", 1, true) or flat:find("mergewithyoursoul", 1, true) then
                        if gui:IsA("GuiButton") then
                            yesBtn = gui
                        else
                            yesBtn = gui:FindFirstAncestorWhichIsA("GuiButton") or gui.Parent
                        end
                        break
                    end
                end
            end
            if yesBtn and yesBtn.AbsoluteSize.X > 0 then
                local inset = game:GetService("GuiService"):GetGuiInset()
                local pos = yesBtn.AbsolutePosition + (yesBtn.AbsoluteSize / 2) + inset
                pcall(function()
                    if getconnections and yesBtn:IsA("GuiButton") then
                        for _, conn in ipairs(getconnections(yesBtn.MouseButton1Click)) do
                            if conn.Function then
                                conn:Fire()
                            end
                        end
                    end
                end)
                VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
                task.wait(0.06)
                VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
                task.wait(0.25)
                for _ = 1, 8 do
                    if _G.ODXFn_HasClickToContinue() then
                        _G.ODXFn_ClickScreenOnce(delayBeforeClick)
                        task.wait(0.25)
                    else
                        break
                    end
                end
                _G.ODXFn_ClearClickToContinue(delayBeforeClick)
                return true
            end
            task.wait(0.15)
        end
        return false
    end

    task.spawn(function()
        local stats = LocalPlayer:WaitForChild("PlayerStats", 20)
        local stand = stats and stats:WaitForChild("Stand", 10)
        if not stand then
            return
        end
        stand.Changed:Connect(function(value)
            if Config.StandFarm and type(value) == "string" and value ~= "" and value ~= "None" then
                Library:Notify("Rolled stand: " .. value, 6)
            end
        end)
    end)

    task.spawn(function()
        while ScriptActive do
            if Config.StandFarm and _G.ODXFn_HasClickToContinue() then
                _G.ODXFn_ClickScreenOnce(0.75)
                task.wait(0.12)
            else
                task.wait(0.08)
            end
        end
    end)

    task.spawn(function()
        -- Minecraft-cheat style pipeline: while ON, pick mob by level, farm, prestige at cap.
        -- Toggle OFF at any time stops the pipeline (does not force-disable forever except max P3).
        local caps = {[0] = 35, [1] = 40, [2] = 45, [3] = 50}
        local lastMobNotify = ""
        local lastPrestigeAttempt = 0
        while ScriptActive do
            task.wait(0.75)
            if not Config.AutoPrestige then
                continue
            end

            local stats = LocalPlayer:FindFirstChild("PlayerStats")
            local level = stats and stats:FindFirstChild("Level")
            local prestige = stats and (stats:FindFirstChild("Prestige") or stats:FindFirstChild("PrestigeLevel"))
            local levelN = level and tonumber(level.Value) or 0
            local prestigeN = prestige and tonumber(prestige.Value) or 0
            local cap = caps[prestigeN] or 50

            -- Max progression: stop only prestige automation (user can turn back on later)
            if prestigeN >= 3 and levelN >= 50 then
                Config.AutoPrestige = false
                Library:Notify("Auto Prestige done: P3 / Lv50")
                continue
            end

            -- At level cap -> go prestige master, interact, confirm
            if levelN >= cap then
                Config.AutoFarmMob = false
                needsQuestGrab = false
                if os.clock() - lastPrestigeAttempt < 3 then
                    continue
                end
                lastPrestigeAttempt = os.clock()

                local master = _G.ODXFn_GetSpecificNPC("Prestige Master")
                    or _G.ODXFn_GetSpecificNPC("PrestigeMaster")
                    or _G.ODXFn_GetSpecificNPC("Prestige")
                local char = LocalPlayer.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                local masterHRP = master and master:FindFirstChild("HumanoidRootPart")

                if hrp and masterHRP then
                    if (hrp.Position - masterHRP.Position).Magnitude > 6 then
                        local dist = (hrp.Position - masterHRP.Position).Magnitude
                        local tTime = math.clamp(dist / math.max(Config.TweenSpeed or 50, 20), 0.15, 6)
                        local tw = TweenService:Create(hrp, TweenInfo.new(tTime, Enum.EasingStyle.Linear), {
                            CFrame = masterHRP.CFrame * CFrame.new(0, 0, 3)
                        })
                        tw:Play()
                        task.wait(tTime)
                    end
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.CFrame = masterHRP.CFrame * CFrame.new(0, 0, 3)

                    local prompt = master:FindFirstChildOfClass("ProximityPrompt")
                        or master:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if prompt then
                        pcall(function()
                            prompt.RequiresLineOfSight = false
                            if fireproximityprompt then
                                fireproximityprompt(prompt)
                            else
                                prompt:InputHoldBegin()
                                task.wait(0.12)
                                prompt:InputHoldEnd()
                            end
                        end)
                    end
                    for _ = 1, 2 do
                        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                        task.wait(0.05)
                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                        task.wait(0.1)
                    end
                    task.wait(0.25)
                    local btn = _G.ODXFn_FindButtonByKeywords({"prestige", "yes", "confirm", "accept"})
                    if btn then
                        _G.ODXFn_ClickButtonObj(btn)
                    end
                    if _G.ODXFn_HasClickToContinue and _G.ODXFn_HasClickToContinue() then
                        _G.ODXFn_ClickScreenOnce()
                    end
                    Library:Notify(string.format("Auto Prestige: P%s Lv%s -> master", tostring(prestigeN), tostring(levelN)))
                else
                    Library:Notify("Auto Prestige: Prestige Master not found")
                end
                continue
            end

            -- Below cap: force correct mob + enable farm (minecraft-style always grinding)
            local mob = "Vampire"
            if levelN < 10 then
                mob = "Thug"
            elseif levelN < 15 then
                mob = "Corrupt Police"
            elseif levelN < 20 then
                mob = "Alpha Thug"
            elseif levelN < 25 then
                mob = "Zombie Henchmen"
            end

            if Config.SelectedMob ~= mob then
                Config.SelectedMob = mob
                needsQuestGrab = true
                local key = tostring(mob) .. ":" .. tostring(levelN)
                if key ~= lastMobNotify then
                    lastMobNotify = key
                    Library:Notify(string.format("Auto Prestige: %s (%s/%s)", mob, tostring(levelN), tostring(cap)))
                end
            end
            if not Config.AutoFarmMob then
                Config.AutoFarmMob = true
            end
        end
    end)

    -- Dedicated Auto Buy Lucky Arrow loop (shop remote, $75k)
    task.spawn(function()
        local lastTry = 0
        while ScriptActive do
            task.wait(1)
            if not ItemConfig.AutoBuyLucky then
                continue
            end
            if os.clock() - lastTry < 2.5 then
                continue
            end
            local money = _G.ODXFn_GetPlayerMoney()
            if money < 75000 then
                continue
            end
            lastTry = os.clock()
            local before = _G.ODXFn_GetBackpackItemCount("Lucky Arrow")
            if _G.ODXFn_BuyLuckyArrow() then
                task.wait(1)
                local after = _G.ODXFn_GetBackpackItemCount("Lucky Arrow")
                if after > before then
                    pcall(function()
                        Library:Notify("Lucky Arrow bought! (" .. tostring(after) .. ") money left ~" .. tostring(_G.ODXFn_GetPlayerMoney()))
                    end)
                end
            end
        end
    end)

    task.spawn(function()
        local emptySince = 0
        local VirtualUser = game:GetService("VirtualUser")
        LocalPlayer.Idled:Connect(function()
            if not Config.AntiAFK then
                return
            end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
        while ScriptActive do
            task.wait(2)
            if ItemConfig.HopWhenEmpty and ItemConfig.Enabled then
                local hasItem = false
                local folder = Workspace:FindFirstChild("Item_Spawns")
                local items = folder and folder:FindFirstChild("Items")
                if items then
                    for _, model in ipairs(items:GetChildren()) do
                        local part = model:FindFirstChildWhichIsA("BasePart", true)
                        if part and part.Transparency < 0.99 then
                            hasItem = true
                            break
                        end
                    end
                end
                if hasItem then
                    emptySince = 0
                else
                    emptySince = emptySince + 2
                    if emptySince >= 20 then
                        emptySince = 0
                        Library:Notify("No items, hopping to a small server")
                        _G.ODXFn_ServerHop(true)
                    end
                end
            else
                emptySince = 0
            end
            if ItemConfig.AutoBuyLucky then
                local money = _G.ODXFn_GetPlayerMoney()
                -- Shop price is $75,000 for 1x Lucky Arrow (wiki / open sources)
                if money >= 75000 then
                    local before = _G.ODXFn_GetBackpackItemCount("Lucky Arrow")
                    local bought = _G.ODXFn_BuyLuckyArrow()
                    if bought then
                        Library:Notify(string.format("Buying Lucky Arrow ($%s)", tostring(money)))
                        task.wait(1.2)
                        local after = _G.ODXFn_GetBackpackItemCount("Lucky Arrow")
                        if after > before then
                            Library:Notify("Lucky Arrow purchased (" .. tostring(after) .. " total)")
                        end
                    end
                end
            end
        end
    end)

    task.spawn(function()
        while ScriptActive do
            task.wait(0.35)
            if not Config.StandFarm then
                continue
            end
            _G.ODXFn_LearnWorthiness()
            task.wait(0.15)
            local current = _G.ODXFn_GetCurrentStand()
            local skin = _G.ODXFn_GetStandSkin()
            if skin ~= "None" then
                Config.StandFarm = false
                Library:Notify("Skin dropped: " .. skin .. " (" .. current .. ")")
                continue
            end
            local pity = Config.StandFarmTarget == "Pity"
            if not pity and current ~= "None" and current:lower():find(Config.StandFarmTarget:lower(), 1, true) then
                Config.StandFarm = false
                Library:Notify("Stand Farm got " .. current)
                continue
            end
            if current ~= "None" then
                if not _G.ODXFn_EquipItem("Rokakaka") then
                    Library:Notify("Stand Farm: no normal Rokakaka")
                    task.wait(2)
                    continue
                end
                _G.ODXFn_UseEquippedTool()
                _G.ODXFn_ConfirmItemDialogue(0.75)
                local reset = false
                local conn = LocalPlayer.CharacterAdded:Connect(function()
                    reset = true
                end)
                local started = tick()
                while not reset and tick() - started < 8 and Config.StandFarm do
                    task.wait(0.1)
                end
                conn:Disconnect()
                task.wait(1.2)
            end
            if _G.ODXFn_GetCurrentStand() == "None" then
                _G.ODXFn_WaitForWorthiness()
                local usedItem = _G.ODXFn_EquipItem("Mysterious Arrow") or _G.ODXFn_EquipItem("Stand Arrow")
                if usedItem then
                    local before = _G.ODXFn_GetCurrentStand()
                    _G.ODXFn_UseEquippedTool()
                    _G.ODXFn_ConfirmItemDialogue(0.75)
                    _G.ODXFn_ClearClickToContinue(0.75)
                    local rolled = before
                    local started = tick()
                    while tick() - started < 8 and Config.StandFarm do
                        if _G.ODXFn_HasClickToContinue() then
                            _G.ODXFn_ClickScreenOnce(0.75)
                        end
                        rolled = _G.ODXFn_GetCurrentStand()
                        if rolled ~= "None" and rolled ~= before then
                            break
                        end
                        task.wait(0.2)
                    end
                    rolled = _G.ODXFn_GetCurrentStand()
                    local skin = _G.ODXFn_GetStandSkin()
                    if skin ~= "None" then
                        Config.StandFarm = false
                        Library:Notify("Skin dropped: " .. skin .. " (" .. rolled .. ")", 8)
                    elseif rolled ~= "None" then
                        Library:Notify("Rolled stand: " .. rolled, 6)
                    else
                        Library:Notify("Arrow used, stand not read yet", 4)
                    end
                    task.wait(1.2)
                else
                    Library:Notify("Stand Farm: no arrow")
                    task.wait(2)
                end
            end
        end
    end)

    _G.ODXFn_GetPlayerMoney = function()
        local n = 0
        pcall(function()
            local function consider(obj)
                if not obj then return end
                local ok, val = pcall(function() return obj.Value end)
                if ok and val ~= nil then
                    local num = tonumber(val)
                    if num then
                        n = math.max(n, num)
                    end
                end
            end
            -- Direct common paths first (YBA PlayerStats.Money)
            for _, folderName in ipairs({"PlayerStats", "Stats", "Data", "PlayerData", "leaderstats"}) do
                local folder = LocalPlayer:FindFirstChild(folderName)
                if folder then
                    for _, moneyName in ipairs({"Money", "Cash", "Yen", "Dollars", "Balance", "money", "cash"}) do
                        consider(folder:FindFirstChild(moneyName))
                    end
                    -- Deep scan one level of children
                    for _, child in ipairs(folder:GetDescendants()) do
                        local lname = child.Name:lower()
                        if lname == "money" or lname == "cash" or lname == "yen" or lname == "balance" then
                            consider(child)
                        end
                    end
                end
            end
            -- leaderstats on player
            local ls = LocalPlayer:FindFirstChild("leaderstats")
            if ls then
                consider(ls:FindFirstChild("Money") or ls:FindFirstChild("Cash"))
            end
        end)
        return n
    end

    _G.ODXFn_BuyLuckyArrow = function()
        local char = LocalPlayer.Character
        if not char then return false end
        local remote = char:FindFirstChild("RemoteEvent")
        if not remote then
            remote = char:FindFirstChildWhichIsA("RemoteEvent", true)
        end
        if not remote then return false end

        -- Working open-source pattern (BloodenOP / NukeVsCity style):
        -- FireServer("PurchaseShopItem", { ItemName = "1x Lucky Arrow" })
        local ok = pcall(function()
            remote:FireServer("PurchaseShopItem", {
                ItemName = "1x Lucky Arrow",
            })
        end)
        if not ok then
            ok = pcall(function()
                remote:FireServer("PurchaseShopItem", {
                    ["ItemName"] = "1x Lucky Arrow",
                })
            end)
        end
        return ok == true
    end

    -- Fire ProximityPrompt without showing the "E Interact" billboard UI.
    _G.ODXFn_SilentFirePrompt = function(prompt)
        if not prompt then return false end
        local oldMax = 16
        pcall(function()
            oldMax = ProximityPromptService.MaxPromptsVisible
            ProximityPromptService.MaxPromptsVisible = 0
        end)
        pcall(function()
            prompt.RequiresLineOfSight = false
            prompt.HoldDuration = 0
            prompt.Enabled = true
            -- keep original MaxActivationDistance if already large; do not force 10000
            if prompt.MaxActivationDistance < 50 then
                prompt.MaxActivationDistance = 50
            end
        end)
        local ok = false
        if fireproximityprompt then
            ok = pcall(fireproximityprompt, prompt, 0) or pcall(fireproximityprompt, prompt)
        end
        -- Hide prompt GUIs if they still appear
        pcall(function()
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            if not pg then return end
            for _, g in ipairs(pg:GetDescendants()) do
                if g:IsA("ScreenGui") or g:IsA("BillboardGui") or g:IsA("LayerCollector") then
                    local n = g.Name:lower()
                    if n:find("proximity", 1, true) or n:find("prompt", 1, true) then
                        g.Enabled = false
                    end
                end
            end
        end)
        task.delay(0.35, function()
            pcall(function()
                ProximityPromptService.MaxPromptsVisible = oldMax
            end)
        end)
        return ok
    end

    _G.ODXFn_TrySellItems = function()
        if not ItemConfig.AutoSellEnabled or isSellingItems then return end

        local itemToSell
        for itemName, enabled in pairs(ItemConfig.SellWhitelist) do
            if enabled and itemName ~= "Lucky Arrow" and _G.ODXFn_GetBackpackItemCount(itemName) >= 1 then
                itemToSell = itemName
                break
            end
        end
        if not itemToSell then return end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local merchantNPC = _G.ODXFn_GetSpecificNPC("Shiftplox") or _G.ODXFn_GetSpecificNPC("Travelling Merchant") or _G.ODXFn_GetSpecificNPC("Merchant")
        local npcHRP = merchantNPC and merchantNPC:FindFirstChild("HumanoidRootPart")
        if not hrp or not npcHRP then return end

        isSellingItems = true
        _G.ODXFn_CancelSellerTween()

        pcall(function()
            if not _G.ODXFn_EquipItem(itemToSell) then return end

            local prompt = merchantNPC:FindFirstChildWhichIsA("ProximityPrompt", true)
                or npcHRP:FindFirstChildWhichIsA("ProximityPrompt", true)

            if prompt then
                _G.ODXFn_SilentFirePrompt(prompt)
            end
            -- Do NOT press E key — that forces the Interact UI on-screen
            task.wait(0.5)

            local btn

        -- 1) "I'd like to sell this"
        for _=1,40 do
            btn = _G.ODXFn_FindButtonByKeywords({
                "i'd like to sell this",
                "id like to sell this",
                "like to sell this",
                "sell this"
            })
            if btn then break end
            task.wait(0.1)
        end
        if btn then
            _G.ODXFn_ClickButtonObj(btn)
        end

        -- 2) "Deal"
        btn = nil
        for _=1,40 do
            btn = _G.ODXFn_FindButtonByKeywords({"deal"})
            if btn then break end
            task.wait(0.1)
        end
        if btn then
            _G.ODXFn_ClickButtonObj(btn)
        end

        -- 3) "I'll sell all of these"
        btn = nil
        for _=1,40 do
            btn = _G.ODXFn_FindButtonByKeywords({
                "i'll sell all of these",
                "ill sell all of these",
                "i will sell all of these",
                "sell all of these",
                "all of these"
            })
            if btn then break end
            task.wait(0.1)
        end
        if btn then
            _G.ODXFn_ClickButtonObj(btn)
        end

        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.ButtonB, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.ButtonB, false, game)
        end)

        task.wait(0.1)
        isSellingItems = false
    end

    _G.ODXFn_CountTrackersNear = function(pos, radius, excludePart)
        local uniqueParts = {}
        for _, data in pairs(ItemConfig.Trackers) do
            local part = data.Part
            if part and part.Parent and part ~= excludePart
                and not uniqueParts[part]
                and (part.Position - pos).Magnitude <= radius then
                uniqueParts[part] = true
            end
        end
        local count = 0
        for _ in pairs(uniqueParts) do
            count = count + 1
        end
        return count
    end

    _G.ODXFn_getItemPart = function(obj)
        if not obj or not obj.Parent then
            return nil
        end
        local parent = obj.Parent
        if parent:IsA("BasePart") then
            return parent
        elseif parent:IsA("Model") then
            local part = parent:FindFirstChildWhichIsA("BasePart", true)
            if part and part.Transparency < 1 and part.Size.Magnitude > 0.1 then
                return part
            end
        end
        local altPart = obj.Parent and obj.Parent.Parent and obj.Parent.Parent:FindFirstChildWhichIsA("BasePart", true)
        if altPart and altPart.Transparency < 1 then
            return altPart
        end
        return nil
    end

    _G.ODXFn_ResolveItemName = function(obj)
        if not obj then return nil end
        if obj:IsA("ProximityPrompt") then
            local ot = obj.ObjectText or ""
            if ITEMS[ot] then return ot end
            local act = obj.ActionText or ""
            if ITEMS[act] then return act end
            for itemName in pairs(ITEMS) do
                if ot:lower():find(itemName:lower(), 1, true) or act:lower():find(itemName:lower(), 1, true) then
                    return itemName
                end
            end
        end
        if obj:IsA("BasePart") or obj:IsA("Model") then
            if ITEMS[obj.Name] then return obj.Name end
            for itemName in pairs(ITEMS) do
                if obj.Name:lower():find(itemName:lower(), 1, true) then
                    return itemName
                end
            end
            local parent = obj.Parent
            if parent and ITEMS[parent.Name] then return parent.Name end
        end
        return nil
    end

    _G.ODXFn_evalItem = function(obj)
        if not obj or ItemConfig.Trackers[obj] then
            return
        end
        local name, part = nil, nil
        if obj:IsA("ProximityPrompt") then
            name = _G.ODXFn_ResolveItemName(obj)
            if name then
                part = _G.ODXFn_getItemPart(obj)
            end
        elseif obj:IsA("BasePart") then
            name = _G.ODXFn_ResolveItemName(obj)
            if name and obj.Transparency < 1 and obj.Size.Magnitude > 0.2 then
                part = obj
            end
        elseif obj:IsA("Model") then
            name = _G.ODXFn_ResolveItemName(obj)
            if name then
                part = obj:FindFirstChildWhichIsA("BasePart", true)
            end
        end
        if not name or not part then
            return
        end
        if (part.Position - ItemConfig.DeadZone).Magnitude <= 5 then
            return
        end
        local color = ITEMS[name] or Color3.fromRGB(255, 255, 255)
        local hl = Instance.new("Highlight")
        hl.Parent = part
        hl.FillColor, hl.FillTransparency, hl.DepthMode = color, 0.5, Enum.HighlightDepthMode.AlwaysOnTop
        local bb = Instance.new("BillboardGui")
        bb.Parent = part
        bb.Size, bb.AlwaysOnTop, bb.MaxDistance, bb.ExtentsOffset = UDim2.new(0, 150, 0, 40), true, 4000, Vector3.new(0, 2, 0)
        local lbl = Instance.new("TextLabel")
        lbl.Parent = bb
        lbl.Size, lbl.BackgroundTransparency, lbl.TextColor3, lbl.TextSize, lbl.Font, lbl.Text =
            UDim2.new(1, 0, 1, 0), 1, color, 12, Enum.Font.SourceSansBold, name
        ItemConfig.Trackers[obj] = {
            Part = part,
            Bb = bb,
            Hl = hl,
            Lbl = lbl,
            Name = name,
            Prompt = obj:IsA("ProximityPrompt") and obj or part:FindFirstChildWhichIsA("ProximityPrompt", true),
        }
    end

    local ItemSpawnPoints = {
        Vector3.new(-413.53112792969, 827.54278564453, 42.011169433594),
        Vector3.new(-191.24629211426, 827.0869140625, -10.055070877075),
        Vector3.new(-282.28414916992, 826.04718017578, -26.729415893555),
        Vector3.new(-205.62605285645, 829.04846191406, -67.532608032227),
        Vector3.new(-154.98663330078, 829.00830078125, -52.219764709473),
        Vector3.new(-89.047630310059, 830.90832519531, -66.026138305664),
        Vector3.new(826.30889892578, 803.84655761719, -226.66427612305),
        Vector3.new(699.22119140625, 803.84655761719, -208.68244934082),
        Vector3.new(776.76434326172, 807.17486572266, -355.8134765625),
        Vector3.new(1050.7122802734, 803.84729003906, -296.76510620117),
        Vector3.new(809.83520507812, 803.84655761719, -81.491226196289),
        Vector3.new(796.341796875, 810.68719482422, -40.994129180908),
        Vector3.new(836.11309814453, 810.33142089844, -41.200565338135),
        Vector3.new(1051.7955322266, 815.47772216797, -25.381820678710001),
        Vector3.new(1915.4926757812, 822.24658203125, -39.561851501465),
        Vector3.new(1985.0435791016, 819.84655761719, -189.87425231934),
        Vector3.new(2341.68359375, 819.84655761719, -228.87698364258),
        Vector3.new(305.22045898438, 803.84655761719, -185.82682800293),
        Vector3.new(339.23501586914, 826.84722900391, -110.79901123047),
        Vector3.new(409.59423828125, 826.64733886719, -89.112976074219),
        Vector3.new(453.85363769531, 826.64733886719, 115.3904876709),
        Vector3.new(428.88458251953, 861.05114746094, -175.99559020996),
        Vector3.new(124.43515014648, 826.84722900391, -153.63478088379),
        Vector3.new(222.72418212891, 827.80584716797, -85.74934387207),
        Vector3.new(130.63851928711, 826.84704589844, -49.86185836792),
        Vector3.new(46.80810546875, 826.84698486328, -98.422576904297),
        Vector3.new(27.974872589111, 861.29296875, -10.053286552429),
        Vector3.new(375.23657226562, 826.84704589844, -162.12173461914),
        Vector3.new(341.62973022461, 826.84704589844, -131.64344787598),
        Vector3.new(479.29449462891, 826.84716796875, 254.90055847168),
        Vector3.new(452.22775268555, 826.84716796875, 302.7751159668),
        Vector3.new(315.51916503906, 826.84716796875, 261.26873779297),
        Vector3.new(518.22473144531, 826.24731445312, 360.57772827148),
        Vector3.new(429.50021362305, 875.04724121094, 387.19262695312),
        Vector3.new(129.19146728516, 826.84704589844, 379.81701660156),
        Vector3.new(32.098743438721, 828.24719238281, 302.8957824707),
        Vector3.new(171.77783203125, 826.84710693359, 255.28721618652),
        Vector3.new(199.16697692871, 857.84704589844, 258.2873840332),
        Vector3.new(21.905725479126, 870.04718017578, 280.63858032227),
        Vector3.new(-74.956695556641, 828.34704589844, 386.41787719727),
        Vector3.new(-152.78285217285, 830.97821044922, 413.20315551758),
        Vector3.new(-99.575782775879, 827.62579345703, 429.30065917969),
        Vector3.new(-118.483543396, 835.71136474609, 402.61944580078),
        Vector3.new(-196.11956787109, 826.84704589844, 408.80563354492),
        Vector3.new(-192.16874694824, 803.84710693359, 458.53912353516),
        Vector3.new(-228.64126586914, 826.84704589844, 309.07147216797),
        Vector3.new(-334.5627746582, 827.84716796875, 382.34112548828),
        Vector3.new(-295.66107177734, 827.7548828125, 260.44488525390001),
        Vector3.new(-243.06549072266, 826.84704589844, 97.641380310059),
        Vector3.new(145.40446472168, 827.79797363281, 106.12605285645),
        Vector3.new(84.441474914551, 826.84704589844, 104.43872070312),
        Vector3.new(43.941471099854, 826.84704589844, 268.90521240234),
        Vector3.new(172.65376281738, 826.84704589844, 278.38635253906),
        Vector3.new(236.93182373047, 826.84704589844, 430.49688720703),
        Vector3.new(210.55850219727, 803.84710693359, 460.701171875),
        Vector3.new(448.04244995117, 803.87713623047, 438.78884887695),
        Vector3.new(126.77220153809, 803.84710693359, 560.0048828125),
        
        Vector3.new(-470.92459106445, 803.84710693359, 381.17669677734),
        Vector3.new(-434.47100830078, 803.84710693359, 235.62271118164),
        Vector3.new(-442.24462890625, 803.84710693359, -198.76741027832),
        Vector3.new(-101.06670379639, 743.8486328125, 8.9106760025024),
        Vector3.new(-355.35842895508, 743.84289550781, 204.35467529297),
        Vector3.new(-178.44441223145, 720.17205810547, 264.23211669922),
        Vector3.new(196.2378692627, 671.93670654297, 83.881690979004),
        Vector3.new(107.51532745361, 749.04711914062, 359.88635253906),
        Vector3.new(11.99014377594, 744.07873535156, 530.36346435547),
        Vector3.new(138.86274719238, 743.84521484375, 493.1076965332),
        Vector3.new(-38.685668945312, 729.07989501953, 365.58688354492),
        Vector3.new(13.609048843384, 733.42077636719, 267.63186645508),
        Vector3.new(-228.36434936523, 751.04052734375, 528.87542724609),
        Vector3.new(-426.47561645508, 743.84716796875, 460.21655273438),
        Vector3.new(-311.52005004883, 722.84790039062, 438.1628112793),
        Vector3.new(-475.11709594727, 738.84729003906, 212.75103759766),
    }

    local ItemRoute = {}
    local ItemRouteIndex = 1
    local lastRouteScan = 0

    _G.ODXFn_RefreshItemRoute = function()
        ItemRoute = {}
        for _, pos in ipairs(ItemSpawnPoints) do
            table.insert(ItemRoute, pos)
        end
        ItemRouteIndex = 1
    end

    _G.ODXFn_IsItemStillThere = function(part)
        if not part or not part.Parent then
            return false
        end
        if part:IsA("BasePart") and part.Transparency >= 0.99 then
            return false
        end
        return true
    end

        local function FireItemPickup(part)
        if not part then
            return
        end
        local root = part.Parent and part.Parent:IsA("Model") and part.Parent or part
        local click = root:FindFirstChildWhichIsA("ClickDetector", true)
            or part:FindFirstChildWhichIsA("ClickDetector", true)
        local prompt = root:FindFirstChildWhichIsA("ProximityPrompt", true)
            or part:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            pcall(function()
                prompt.Enabled = true
                prompt.RequiresLineOfSight = false
                prompt.MaxActivationDistance = 40
                prompt.HoldDuration = 0
            end)
        end
        if click and fireclickdetector then
            pcall(fireclickdetector, click)
            pcall(fireclickdetector, click, 0)
            pcall(fireclickdetector, click, 1)
        end
        if prompt then
            pcall(function()
                if fireproximityprompt then
                    fireproximityprompt(prompt)
                end
            end)
            pcall(function()
                prompt:InputHoldBegin()
                task.wait(0.12)
                prompt:InputHoldEnd()
            end)
        end
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.12)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end

    _G.ODXFn_GrabNearbyItem = function(preferredPart, preferredPrompt)
        if not ItemConfig.Enabled then
            return false
        end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return false
        end

        local bestPart = preferredPart
        if not bestPart or not bestPart.Parent then
            local bestDist = 12
            local folder = Workspace:FindFirstChild("Item_Spawns")
            local items = folder and folder:FindFirstChild("Items")
            if items then
                for _, model in ipairs(items:GetChildren()) do
                    local part = model:FindFirstChildWhichIsA("BasePart", true)
                    if part and part.Transparency < 0.99 then
                        local dist = (part.Position - hrp.Position).Magnitude
                        if dist < bestDist then
                            bestDist = dist
                            bestPart = part
                        end
                    end
                end
            end
        end
        if not bestPart or not bestPart.Parent then
            return false
        end

        -- Item Farmer movement is controlled by ItemTP/Tween.
        -- Do not teleport here; only perform the pickup interaction.
        local distanceToItem = (bestPart.Position - hrp.Position).Magnitude
        if distanceToItem > 14 then
            return false
        end
        task.wait(0.12)

        for i = 1, 10 do
            if not _G.ODXFn_IsItemStillThere(bestPart) then
                return true
            end
            FireItemPickup(bestPart)
            task.wait(0.12)
        end
        return not _G.ODXFn_IsItemStillThere(bestPart)
    end

    _G.ODXFn_GetGroundedCFrame = function(position)
        if typeof(position) ~= "Vector3" then
            return nil
        end

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true

        local exclude = {}
        local character = LocalPlayer.Character
        if character then
            table.insert(exclude, character)
        end

        local itemSpawns = Workspace:FindFirstChild("Item_Spawns")
        if itemSpawns then
            table.insert(exclude, itemSpawns)
        end

        params.FilterDescendantsInstances = exclude

        local origin = position + Vector3.new(0, 1200, 0)
        local direction = Vector3.new(0, -2500, 0)
        local result = Workspace:Raycast(origin, direction, params)

        if not result then
            return nil
        end

        return CFrame.new(result.Position + Vector3.new(0, 3, 0))
    end

local function GetSpawnedItemTarget()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local myPos = hrp and hrp.Position
        local bestPart, bestName, bestPrompt, bestDist = nil, nil, nil, math.huge

        for _, data in pairs(ItemConfig.Trackers) do
            local part = data.Part
            -- Only consider items that already have ESP distance (tracker is fully ready)
            if part and part.Parent and part.Transparency < 0.99
                and data.Name and ItemConfig.SelectedItems[data.Name]
                and data.Lbl and data.Lbl.Parent  -- ESP label exists = ready
                and not ((part.Position - ItemConfig.DeadZone).Magnitude <= 5) then

                local prompt = data.Prompt
                local click = part:FindFirstChildWhichIsA("ClickDetector", true)
                    or (part.Parent and part.Parent:FindFirstChildWhichIsA("ClickDetector", true))
                if not prompt or not prompt.Parent then
                    prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
                        or (part.Parent and part.Parent:FindFirstChildWhichIsA("ProximityPrompt", true))
                end
                if prompt or click then
                    local dist = myPos and (part.Position - myPos).Magnitude or 0
                    if dist < bestDist then
                        bestDist = dist
                        bestPart = part
                        bestName = data.Name
                        bestPrompt = prompt
                    end
                end
            end
        end

        return bestPart, bestName, bestPrompt
    end

    _G.ODXFn_FlyItemRoute = function(root)
        if not ItemConfig.Enabled or not root then return end

        local itemPart, itemName, itemPrompt = GetSpawnedItemTarget()
        if itemPart and itemPart.Parent then
            local tween = _G.ODXFn_ItemTP(CFrame.new(itemPart.Position + Vector3.new(0, 0.8, 0)))
            if tween then tween.Completed:Wait() end
            if not ScriptActive or not ItemConfig.Enabled then _G.ODXFn_CancelItemTween(); return end
            task.wait(0.08)
            pcall(_G.ODXFn_GrabNearbyItem, itemPart, itemPrompt)
            return
        end

        if #ItemSpawnPoints == 0 then task.wait(0.1); return end
        if ItemRouteIndex > #ItemSpawnPoints then ItemRouteIndex = 1 end

        local checked = 0
        while checked < #ItemSpawnPoints and ScriptActive and ItemConfig.Enabled do
            local spot = ItemSpawnPoints[ItemRouteIndex]
            ItemRouteIndex = ItemRouteIndex + 1
            if ItemRouteIndex > #ItemSpawnPoints then ItemRouteIndex = 1 end
            checked = checked + 1

            if typeof(spot) == "Vector3" then
                local groundedCFrame = _G.ODXFn_GetGroundedCFrame(spot)
                if groundedCFrame then
                    local tween = _G.ODXFn_ItemTP(groundedCFrame)
                    while ScriptActive and ItemConfig.Enabled and tween and tween.PlaybackState == Enum.PlaybackState.Playing do
                        local spawnedPart, spawnedName, spawnedPrompt = GetSpawnedItemTarget()
                        if spawnedPart and spawnedPart.Parent then
                            _G.ODXFn_CancelItemTween()
                            local itemTween = _G.ODXFn_ItemTP(CFrame.new(spawnedPart.Position + Vector3.new(0, 0.8, 0)))
                            if itemTween then itemTween.Completed:Wait() end
                            if ScriptActive and ItemConfig.Enabled and spawnedPart.Parent then
                                pcall(_G.ODXFn_GrabNearbyItem, spawnedPart, spawnedPrompt)
                            end
                            return
                        end
                        task.wait(0.02)
                    end
                end
            end
        end
    end

    task.spawn(function()
        while ScriptActive do
            task.wait(0.25)
            if not isGuiOpen and not UserInputService:GetFocusedTextBox() then
                pcall(_G.ODXFn_TrySellItems)
            end
        end
    end)

    task.spawn(function()
        while ScriptActive do
            task.wait(_G.ODXFn_GetRandomFloat(0.04, 0.08))
            if isGuiOpen or UserInputService:GetFocusedTextBox() then
                task.wait(0.5)
            else
                if ItemConfig.Enabled then
                    local char = LocalPlayer.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    local myPos = root and root.Position
                    local bestPart, bestData, bestObj, minDist = nil, nil, nil, math.huge
                    for obj, data in pairs(ItemConfig.Trackers) do
                        if not obj or not obj:IsDescendantOf(game) or not data.Part or not data.Part:IsDescendantOf(game)
                            or (data.Part.Position - ItemConfig.DeadZone).Magnitude <= 5 then
                            if data.Bb then
                                data.Bb:Destroy()
                            end
                            if data.Hl then
                                data.Hl:Destroy()
                            end
                            ItemConfig.Trackers[obj] = nil
                        elseif myPos then
                            local d = (data.Part.Position - myPos).Magnitude
                            local stacked = _G.ODXFn_CountTrackersNear(data.Part.Position, STACK_RADIUS, data.Part) >= 1
                            if stacked then
                                data.Lbl.Text = string.format("%s\n[STACK SKIP]", data.Name)
                            else
                                data.Lbl.Text = string.format("%s\n[%d Studs]", data.Name, math.floor(d))
                            end
                            if ItemConfig.SelectedItems[data.Name] and not stacked and d < minDist then
                                minDist, bestPart, bestData, bestObj = d, data.Part, data, obj
                            end
                        end
                    end
                    if ItemConfig.Enabled and root then
                        pcall(_G.ODXFn_FlyItemRoute, root)
                    end
                end
            end
        end
    end)

    for _, d in ipairs(Workspace:GetDescendants()) do
        _G.ODXFn_evalItem(d)
    end
    table.insert(Connections, Workspace.DescendantAdded:Connect(function(d)
        task.wait(0.01)
        _G.ODXFn_evalItem(d)
    end))
    table.insert(Connections, ProximityPromptService.PromptShown:Connect(_G.ODXFn_evalItem))

    _G.ODXFn_GetTargetCFrame = function(targetHRP)
        local targetCFrame = targetHRP.CFrame
        if Config.MethodBehind then
            local behindPos = targetCFrame.Position - (targetCFrame.LookVector * Config.BehindDistance)
            return CFrame.new(behindPos, targetCFrame.Position + targetCFrame.LookVector)
        end
        return CFrame.new(targetHRP.Position + Vector3.new(0, 6.5, 0), targetHRP.Position)
    end

    table.insert(Connections, RunService.Stepped:Connect(function()
        if not ScriptActive then
            return
        end
        if Config.GlobalNoclip or ItemConfig.Enabled or Config.AutoFarmMob or Config.EnableTargetKill then
            local char = LocalPlayer.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        end
    end))

    _G.ODXFn_CheckAndSummonStand = function(character)
        if not character then
            return
        end
        local hasStandAttr = character:GetAttribute("StandActive")
        if hasStandAttr == false or (not character:FindFirstChild("StandMorph") and not character:FindFirstChild("StandActive")) then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
            task.wait(0.3)
        end
    end

    _G.ODXFn_HasCompletedQuestOnScreen = function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then
            return false
        end
        for _, gui in ipairs(playerGui:GetDescendants()) do
            if (gui:IsA("TextLabel") or gui:IsA("TextButton")) and gui.Visible and gui.Text ~= "" then
                local tUpper = gui.Text:upper()
                if tUpper:find("COMPLETED") or tUpper:find("QUEST COMPLETE") or tUpper:find("FINISHED")
                    or tUpper:find("GREAT JOB") or tUpper:find("WELL DONE") then
                    return true
                end
            end
        end
        return false
    end

    -- YBA blocks retaking a quest while still in combat with this message.
    _G.ODXFn_HasFightAttentionMessage = function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then
            return false
        end
        for _, gui in ipairs(playerGui:GetDescendants()) do
            if (gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox")) and gui.Text ~= "" then
                local t = gui.Text:lower()
                if t:find("pay attention", 1, true)
                    or t:find("fight first", 1, true)
                    or t:find("attention to your fight", 1, true) then
                    return true
                end
            end
        end
        return false
    end

    -- Re-fire NPC prompt + dialog clicks while standing still.
    _G.ODXFn_RetryQuestPickup = function(targetNPC, npcHRP)
        local prompt = nil
        if targetNPC then
            prompt = targetNPC:FindFirstChildOfClass("ProximityPrompt")
                or (npcHRP and npcHRP:FindFirstChildOfClass("ProximityPrompt"))
                or targetNPC:FindFirstChildWhichIsA("ProximityPrompt", true)
        end
        if prompt then
            pcall(function()
                prompt.RequiresLineOfSight = false
                if fireproximityprompt then
                    fireproximityprompt(prompt)
                else
                    prompt:InputHoldBegin()
                    task.wait(0.12)
                    prompt:InputHoldEnd()
                end
            end)
        end
        for _ = 1, 2 do
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            task.wait(0.12)
        end
        task.wait(0.25)
        _G.ODXFn_ClickAllQuestDialogs()
        if _G.ODXFn_HasClickToContinue() then
            _G.ODXFn_ClickScreenOnce()
            task.wait(0.15)
        end
    end

    _G.ODXHandleNPCQuestInteractionStandFarm = function(mobName)
        local npcKey = _G.ODXQuestNPCsRef[mobName]
        if not npcKey then return false end
        isDoingQuest = true
        local targetNPC
        if npcKey == "__COORDS__" then
            targetNPC = _G.ODXFn_GetNPCNearCoords(JotaroQuestCoords, 30)
        else
            targetNPC = _G.ODXFn_GetSpecificNPC(npcKey)
        end
        local prompt = targetNPC and (targetNPC:FindFirstChildOfClass("ProximityPrompt") or targetNPC:FindFirstChildWhichIsA("ProximityPrompt", true))
        if prompt then
            pcall(function()
                prompt.RequiresLineOfSight = false
                if fireproximityprompt then
                    fireproximityprompt(prompt)
                else
                    prompt:InputHoldBegin()
                    task.wait(0.12)
                    prompt:InputHoldEnd()
                end
            end)
        end
        for _ = 1, 2 do
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            task.wait(0.15)
        end
        task.wait(0.35)
        _G.ODXFn_ClickAllQuestDialogs()
        if _G.ODXFn_HasClickToContinue() then
            _G.ODXFn_ClickScreenOnce()
            task.wait(0.2)
        end

        local retry = 0
        while ScriptActive and _G.ODXConfigRef and _G.ODXConfigRef.AutoFarmMob
            and _G.ODXFn_HasFightAttentionMessage() and retry < 90 do
            task.wait(0.8)
            _G.ODXFn_RetryQuestPickup(targetNPC, targetNPC and targetNPC:FindFirstChild("HumanoidRootPart"))
            retry = retry + 1
        end

        isDoingQuest = false
        return true
    end

    _G.ODXHandleNPCQuestInteraction = function(mobName)
        local npcKey = _G.ODXQuestNPCsRef[mobName]
        if not npcKey then
            return
        end
        isDoingQuest = true
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            isDoingQuest = false
            return
        end
        local targetNPC, npcHRP, targetPos
        if npcKey == "__COORDS__" then
            targetPos = JotaroQuestCoords + Vector3.new(0, 3, 0)
            pcall(function()
                settings().Physics.AllowSleep = false
            end)
            while (hrp.Position - targetPos).Magnitude > 5 and ScriptActive and _G.ODXConfigRef.AutoFarmMob do
                hrp.Velocity = Vector3.zero
                local dist = (hrp.Position - targetPos).Magnitude
                local tTime = math.clamp(dist / _G.ODXConfigRef.TweenSpeed, 0.05, 3.0)
                TweenService:Create(hrp, TweenInfo.new(tTime, Enum.EasingStyle.Linear), {
                    CFrame = CFrame.new(targetPos, targetPos + hrp.CFrame.LookVector)
                }):Play()
                task.wait(tTime)
            end
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.CFrame = CFrame.new(targetPos)
            targetNPC = _G.ODXFn_GetNPCNearCoords(JotaroQuestCoords, 30)
            if targetNPC and targetNPC:FindFirstChild("HumanoidRootPart") then
                npcHRP = targetNPC.HumanoidRootPart
                hrp.CFrame = npcHRP.CFrame * CFrame.new(0, 0, 3)
            end
        else
            targetNPC = _G.ODXFn_GetSpecificNPC(npcKey)
            if not targetNPC or not targetNPC:FindFirstChild("HumanoidRootPart") then
                isDoingQuest = false
                return
            end
            npcHRP = targetNPC.HumanoidRootPart
            targetPos = npcHRP.Position + Vector3.new(0, 3, 0)
            pcall(function()
                settings().Physics.AllowSleep = false
            end)
            while (hrp.Position - targetPos).Magnitude > 5 and ScriptActive and _G.ODXConfigRef.AutoFarmMob do
                hrp.Velocity = Vector3.zero
                local dist = (hrp.Position - targetPos).Magnitude
                local tTime = math.clamp(dist / _G.ODXConfigRef.TweenSpeed, 0.05, 3.0)
                TweenService:Create(hrp, TweenInfo.new(tTime, Enum.EasingStyle.Linear), {
                    CFrame = CFrame.new(targetPos, targetPos + hrp.CFrame.LookVector)
                }):Play()
                task.wait(tTime)
            end
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.CFrame = npcHRP.CFrame * CFrame.new(0, 0, 3)
        end
        task.wait(0.3)
        local prompt = nil
        if targetNPC then
            prompt = targetNPC:FindFirstChildOfClass("ProximityPrompt")
                or (npcHRP and npcHRP:FindFirstChildOfClass("ProximityPrompt"))
            if not prompt then
                for _, p in ipairs(targetNPC:GetDescendants()) do
                    if p:IsA("ProximityPrompt") then
                        prompt = p
                        break
                    end
                end
            end
        end
        if prompt then
            pcall(function()
                prompt.RequiresLineOfSight = false
                if fireproximityprompt then
                    fireproximityprompt(prompt)
                else
                    prompt:InputHoldBegin()
                    task.wait(0.12)
                    prompt:InputHoldEnd()
                end
            end)
        end
        for _ = 1, 2 do
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            task.wait(0.15)
        end
        task.wait(0.35)
        _G.ODXFn_ClickAllQuestDialogs()
        if _G.ODXFn_HasClickToContinue() then
            _G.ODXFn_ClickScreenOnce()
            task.wait(0.2)
        end
        task.wait(0.15)
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.ButtonB, false, game)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.ButtonB, false, game)
        end)
        task.wait(0.2)

        -- If YBA says "pay attention to your fight first", stay put and keep
        -- retrying quest pickup until the message is gone (quest accepted) or stop.
        local retry = 0
        while ScriptActive and _G.ODXConfigRef and _G.ODXConfigRef.AutoFarmMob
            and _G.ODXFn_HasFightAttentionMessage() and retry < 90 do
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if root then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
            task.wait(0.8)
            _G.ODXFn_RetryQuestPickup(targetNPC, npcHRP)
            retry = retry + 1
        end

        isDoingQuest = false
    end

    _G.ODXIsValidMob = function(mob)
        if not mob or not mob.Parent then
            return false
        end
        local hum = mob:FindFirstChildOfClass("Humanoid")
        local hrp = mob:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp or hum.Health <= 0 or hrp.Position.Y < -150 then
            return false
        end
        local rawName = mob.Name
        local mobName = rawName:lower()
        local selected = _G.ODXConfigRef.SelectedMob:lower()
        if rawName == "Doppio" or mobName == "doppio" then
            return false
        end
        if mobName:find("officer") or mobName:find("deputy") or mobName:find("partner") then
            return false
        end
        if mobName:find("dracula") or mobName:find("zeppeli") or mobName:find("quest") then
            return false
        end
        for _, npcName in pairs(_G.ODXQuestNPCsRef) do
            if type(npcName) == "string" and npcName ~= "__COORDS__" and rawName == npcName then
                return false
            end
        end
        if selected == "yoshikage kira" then
            if not (mobName:find("yoshikage") or mobName:find("kira")) then
                return false
            end
            if mobName:find("quest") then
                return false
            end
        elseif selected == "thug" then
            if mobName:find("alpha") or mobName:find("corrupt") then
                return false
            end
            if not mobName:find("thug") then
                return false
            end
        elseif selected == "corrupt police" then
            if not (mobName:find("corrupt") or mobName:find("police")) then
                return false
            end
        elseif selected == "alpha thug" then
            if not mobName:find("alpha") then
                return false
            end
        elseif selected == "zombie henchmen" then
            if not (mobName:find("zombie") or mobName:find("henchmen")) then
                return false
            end
        elseif selected == "vampire" then
            if not mobName:find("vampire") then
                return false
            end
        elseif selected == "heaven ascension dio" then
            if mobName:find("doppio") or mobName:find("jotaro") then
                return false
            end
            if not (mobName:find("heaven") and (mobName:find("dio") or mobName:find("deo"))) then
                return false
            end
            return true
        elseif selected == "dio" then
            if mobName:find("doppio") or mobName:find("jotaro") then
                return false
            end
            if not mobName:find("dio") then
                return false
            end
            return true
        elseif selected == "jotaro" then
            if mobName:find("doppio") or mobName:find("kujo") then
                return false
            end
            if not mobName:find("jotaro") then
                return false
            end
        elseif selected == "jotaro kujo" then
            if mobName:find("doppio") then
                return false
            end
            if not mobName:find("kujo") then
                return false
            end
        else
            if not mobName:find(selected, 1, true) then
                return false
            end
        end
        return true
    end

    _G.ODXGetClosestMob = function()
        local living = Workspace:FindFirstChild("Living") or Workspace
        local character = LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return nil
        end
        local closest, minDist = nil, math.huge
        for _, npc in ipairs(living:GetChildren()) do
            if npc ~= character and npc:IsA("Model") and _G.ODXIsValidMob(npc) then
                local dist = (npc.HumanoidRootPart.Position - hrp.Position).Magnitude
                if dist < minDist then
                    minDist, closest = dist, npc
                end
            end
        end
        return closest
    end

    _G.ODXGetClosestMobFromPosition = function(origin)
        local living = Workspace:FindFirstChild("Living") or Workspace
        local closest, minDist = nil, math.huge
        if not origin then return nil end
        for _, npc in ipairs(living:GetChildren()) do
            if npc:IsA("Model") and _G.ODXIsValidMob(npc) then
                local mobHRP = npc:FindFirstChild("HumanoidRootPart")
                if mobHRP then
                    local dist = (mobHRP.Position - origin).Magnitude
                    if dist < minDist then
                        minDist, closest = dist, npc
                    end
                end
            end
        end
        return closest
    end

    _G.ODXGetStandFarmCFrame = function(standHRP, mobHRP)
        if _G.ODXConfigRef.MethodAbove then
            local p = mobHRP.Position + Vector3.new(0, 6.5, 0)
            return CFrame.new(p, mobHRP.Position)
        else
            local p = mobHRP.Position - mobHRP.CFrame.LookVector * _G.ODXConfigRef.BehindDistance
            return CFrame.new(p + Vector3.new(0, 1, 0), mobHRP.Position)
        end
    end

    _G.ODXMoveStandForFarm = function(stand, standHRP, targetCF)
        if not standHRP or not targetCF then return false end
        local ok = pcall(function()
            if stand:IsA("Model") then
                stand:PivotTo(targetCF)
            elseif stand:IsA("BasePart") then
                stand.CFrame = targetCF
            end
        end)
        return ok
    end

    _G.ODXPerformAdvancedAttack = function()
        if not Config.AutoAttack then
            return
        end
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(0.005)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        task.wait(0.005)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(0.005)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        task.wait(0.01)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 1, true, game, 1)
        task.wait(0.01)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 1, false, game, 1)
        task.wait(0.01)
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
        task.wait(0.01)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
        if not isBarraging then
            isBarraging = true
            task.spawn(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.wait(_G.ODXFn_GetRandomFloat(1.5, 1.8))
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                task.wait(0.1)
                isBarraging = false
            end)
        end
    end

    table.insert(Connections, RunService.RenderStepped:Connect(function()
        if not ScriptActive then
            return
        end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local cam = Workspace.CurrentCamera
        if cam and Config.FOVEnabled and math.abs(cam.FieldOfView - Config.FOVValue) > 0.1 then
            cam.FieldOfView = Config.FOVValue
        end
        if hum then
            if Config.SpeedEnabled then
                if hum.WalkSpeed ~= Config.CustomWalkSpeed then
                    hum.WalkSpeed = Config.CustomWalkSpeed
                end
            elseif hum.WalkSpeed > 16 and hum.WalkSpeed == Config.CustomWalkSpeed then
                hum.WalkSpeed = 16
            end
        end
        if Config.FlyEnabled and hrp and cam and not ItemConfig.Enabled then
            hrp.AssemblyLinearVelocity = Vector3.zero
            local moveDir = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                moveDir = moveDir + cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                moveDir = moveDir - cam.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                moveDir = moveDir - cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                moveDir = moveDir + cam.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                moveDir = moveDir + Vector3.new(0, 1, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                moveDir = moveDir - Vector3.new(0, 1, 0)
            end
            if moveDir.Magnitude > 0 then
                moveDir = moveDir.Unit
            end
            hrp.CFrame = hrp.CFrame + (moveDir * (Config.FlySpeed * 0.05))
        end

        if Config.StandAttach and char and not isDoingQuest then
            local standHRP = _G.ODXFn_GetStandHRP(_G.ODXFn_FindStandModel(char))
            local attachHRP = _G.ODXFn_GetTargetAttachHRP()
            if standHRP and attachHRP then
                _G.ODXFn_AttachStandToBack(standHRP, attachHRP)
            end
        end
        if Config.AutoRun and hum and not UserInputService:GetFocusedTextBox() then
            local skillDown = UserInputService:IsKeyDown(Enum.KeyCode.E)
                or UserInputService:IsKeyDown(Enum.KeyCode.R)
                or UserInputService:IsKeyDown(Enum.KeyCode.F)
                or UserInputService:IsKeyDown(Enum.KeyCode.C)
                or UserInputService:IsKeyDown(Enum.KeyCode.V)
                or UserInputService:IsKeyDown(Enum.KeyCode.X)
                or UserInputService:IsKeyDown(Enum.KeyCode.Z)
            if skillDown then
                _G.ODXAutoRunPending = true
            elseif _G.ODXAutoRunPending and tick() - lastAutoRun > 0.35 then
                _G.ODXAutoRunPending = false
                lastAutoRun = tick()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
                task.delay(0.05, function()
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
                end)
            elseif hum.MoveDirection.Magnitude > 0.1 and hum.WalkSpeed <= 16 and tick() - lastAutoRun > 0.6 then
                lastAutoRun = tick()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftControl, false, game)
                task.delay(0.05, function()
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
                end)
            end
        end
        if false and Config.StandAttach and char and not isDoingQuest then
            local standHRP = _G.ODXFn_GetStandHRP(_G.ODXFn_FindStandModel(char))
            local attachHRP = _G.ODXFn_GetTargetAttachHRP()
            if standHRP and attachHRP then
                _G.ODXFn_AttachStandToBack(standHRP, attachHRP)
            end
        end
        if isArrivedAtTarget and (Config.AutoFarmMob or Config.EnableTargetKill) and lockedTargetPart and lockedTargetPart.Parent and not Config.FlyEnabled and not ItemConfig.Enabled then
            if hrp then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                hrp.CFrame = _G.ODXFn_GetTargetCFrame(lockedTargetPart)
            end
        end
    end))

    task.spawn(function()
        while ScriptActive do
            task.wait(0.01)
            pcall(function()
                local character = LocalPlayer.Character
                if not character or not character:FindFirstChild("HumanoidRootPart") then
                    return
                end
                local hrp = character.HumanoidRootPart
                local hum = character:FindFirstChildOfClass("Humanoid")
                if not hum or hum.Health <= 0 then
                    lockedTargetPart, activeMobTarget, isArrivedAtTarget, isBarraging = nil, nil, false, false
                    return
                end
                if lastSelectedMob ~= Config.SelectedMob then
                    lastSelectedMob = Config.SelectedMob
                    needsQuestGrab = true
                    activeMobTarget = nil
                end
                if Config.EnableTargetKill then
                    _G.ODXFn_CheckAndSummonStand(character)
                    if not _G.ODXFn_IsValidPlayer(activePlayerTarget) then
                        activePlayerTarget = _G.ODXFn_FindTargetPlayerChar()
                    end
                    local targetChar = activePlayerTarget
                    if targetChar and targetChar:FindFirstChild("HumanoidRootPart") then
                        local targetHRP = targetChar.HumanoidRootPart
                        lockedTargetPart = targetHRP
                        local lockedCFrame = _G.ODXFn_GetTargetCFrame(targetHRP)
                        local dist = (hrp.Position - lockedCFrame.Position).Magnitude
                        if dist > 3.8 then
                            isArrivedAtTarget = false
                            pcall(function()
                                settings().Physics.AllowSleep = false
                            end)
                            hrp.Velocity = Vector3.zero
                            local timeToTravel = math.clamp(dist / Config.TweenSpeed, 0.05, 5.0)
                            local tw = TweenService:Create(hrp, TweenInfo.new(timeToTravel, Enum.EasingStyle.Linear), {CFrame = lockedCFrame})
                            tw:Play()
                            while tw.PlaybackState == Enum.PlaybackState.Playing and ScriptActive do
                                if not targetHRP or not targetHRP.Parent then
                                    break
                                end
                                if (hrp.Position - _G.ODXFn_GetTargetCFrame(targetHRP).Position).Magnitude <= 3.8 then
                                    break
                                end
                                task.wait(0.01)
                            end
                            pcall(function()
                                tw:Cancel()
                            end)
                        end
                        if (hrp.Position - lockedCFrame.Position).Magnitude <= 3.8 then
                            isArrivedAtTarget = true
                            hrp.AssemblyLinearVelocity = Vector3.zero
                            hrp.AssemblyAngularVelocity = Vector3.zero
                            _G.ODXPerformAdvancedAttack()
                        end
                        return
                    else
                        lockedTargetPart, isArrivedAtTarget = nil, false
                    end
                end
                if Config.StandMobFarm then
                    local stand = _G.ODXFn_FindStandModel(character)
                    local standHRP = _G.ODXFn_GetStandHRP(stand)
                    if not standHRP then
                        return
                    end
                    if Workspace.CurrentCamera and Workspace.CurrentCamera.CameraSubject ~= standHRP then
                        Workspace.CurrentCamera.CameraSubject = standHRP
                    end

                    -- Never move the real character in Stand Farm.
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero

                    if _G.ODXFn_HasCompletedQuestOnScreen() then
                        needsQuestGrab = true
                    end

                    -- Quest acquisition is attempted from the player's current AFK spot.
                    -- No character tween/teleport to the NPC is performed here.
                    if needsQuestGrab and QuestNPCs[Config.SelectedMob] ~= nil then
                        activeMobTarget = nil
                        lockedTargetPart = nil
                        isArrivedAtTarget = false
                        isBarraging = false
                        _G.ODXHandleNPCQuestInteractionStandFarm(Config.SelectedMob)
                        needsQuestGrab = false
                        task.wait(0.25)
                        return
                    end

                    if activeMobTarget and not _G.ODXIsValidMob(activeMobTarget) then
                        activeMobTarget = nil
                        lockedTargetPart = nil
                        isArrivedAtTarget = false
                        isBarraging = false
                    end
                    if not activeMobTarget then
                        activeMobTarget = _G.ODXGetClosestMobFromPosition(standHRP.Position)
                        if not activeMobTarget then
                            return
                        end
                    end

                    local mobHRP = activeMobTarget:FindFirstChild("HumanoidRootPart")
                    local mobHum = activeMobTarget:FindFirstChildOfClass("Humanoid")
                    if not mobHRP or not mobHum or mobHum.Health <= 0 then
                        activeMobTarget = nil
                        return
                    end

                    lockedTargetPart = mobHRP
                    local standTargetCF = _G.ODXGetStandFarmCFrame(standHRP, mobHRP)
                    _G.ODXMoveStandForFarm(stand, standHRP, standTargetCF)
                    _G.ODXPerformAdvancedAttack()
                    return
                end

                if not Config.AutoFarmMob then
                    if not Config.EnableTargetKill then
                        lockedTargetPart, activeMobTarget, isArrivedAtTarget, isBarraging = nil, nil, false, false
                    end
                    return
                end
                _G.ODXFn_CheckAndSummonStand(character)
                if _G.ODXFn_HasCompletedQuestOnScreen() then
                    needsQuestGrab = true
                end
                if needsQuestGrab and QuestNPCs[Config.SelectedMob] ~= nil then
                    activeMobTarget, isBarraging, lockedTargetPart, isArrivedAtTarget = nil, false, nil, false
                    _G.ODXHandleNPCQuestInteraction(Config.SelectedMob)
                    needsQuestGrab = false
                    task.wait(0.25)
                    return
                end
                if activeMobTarget and not _G.ODXIsValidMob(activeMobTarget) then
                    activeMobTarget, lockedTargetPart, isArrivedAtTarget, isBarraging = nil, nil, false, false
                end
                if not activeMobTarget then
                    activeMobTarget = _G.ODXGetClosestMob()
                    isBarraging = false
                    if not activeMobTarget then
                        return
                    end
                end
                local targetMob = activeMobTarget
                if targetMob and targetMob:FindFirstChild("HumanoidRootPart") then
                    local mobHRP = targetMob.HumanoidRootPart
                    local mobHum = targetMob:FindFirstChildOfClass("Humanoid")
                    lockedTargetPart = mobHRP
                    local targetCFrame = _G.ODXFn_GetTargetCFrame(mobHRP)
                    local dist = (hrp.Position - targetCFrame.Position).Magnitude
                    if mobHum and mobHum.Health > 0 then
                        if dist > 3.8 then
                            isArrivedAtTarget = false
                            pcall(function()
                                settings().Physics.AllowSleep = false
                            end)
                            hrp.Velocity = Vector3.zero
                            local timeToTravel = math.clamp(dist / Config.TweenSpeed, 0.05, 5.0)
                            local tw = TweenService:Create(hrp, TweenInfo.new(timeToTravel, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
                            tw:Play()
                            while tw.PlaybackState == Enum.PlaybackState.Playing and ScriptActive do
                                if not mobHRP or not mobHRP.Parent then
                                    break
                                end
                                local curMobHum = targetMob:FindFirstChildOfClass("Humanoid")
                                if not curMobHum or curMobHum.Health <= 0 then
                                    break
                                end
                                if _G.ODXFn_HasCompletedQuestOnScreen() then
                                    needsQuestGrab = true
                                    tw:Cancel()
                                    break
                                end
                                if (hrp.Position - _G.ODXFn_GetTargetCFrame(mobHRP).Position).Magnitude <= 3.8 then
                                    break
                                end
                                task.wait(0.01)
                            end
                            pcall(function()
                                tw:Cancel()
                            end)
                        end
                        if (hrp.Position - targetCFrame.Position).Magnitude <= 3.8 then
                            isArrivedAtTarget = true
                            hrp.AssemblyLinearVelocity = Vector3.zero
                            hrp.AssemblyAngularVelocity = Vector3.zero
                            _G.ODXPerformAdvancedAttack()
                        end
                    else
                        activeMobTarget, lockedTargetPart, isArrivedAtTarget, isBarraging = nil, nil, false, false
                    end
                else
                    lockedTargetPart, activeMobTarget, isArrivedAtTarget, isBarraging = nil, nil, false, false
                end
            end)
        end
    end)

    --// AUTO CANDY EXCHANGE (remote, like ShiftPlox)
    task.spawn(function()
        local exchanging = false
        while ScriptActive do
            task.wait(2)
            if not ItemConfig.AutoCandyExchange or exchanging then continue end

            -- Only exchange if player has candy in inventory
            local hasCandy = false
            local candyNames = { "Red Candy", "Blue Candy", "Green Candy", "Yellow Candy", "Candy" }
            local backpack = LocalPlayer:FindFirstChild("Backpack")
            local char = LocalPlayer.Character
            for _, name in ipairs(candyNames) do
                if (backpack and backpack:FindFirstChild(name)) or (char and char:FindFirstChild(name)) then
                    hasCandy = true
                    break
                end
            end
            if not hasCandy then continue end

            local jack = nil
            for _, v in ipairs(Workspace:GetDescendants()) do
                if v:IsA("Model") then
                    local n = v.Name:lower()
                    if n:find("jack") and (n:find("cauldron") or n:find("specter") or n:find("spectre")) then
                        jack = v
                        break
                    end
                end
            end
            if not jack then continue end

            exchanging = true
            pcall(function()
                local prompt = jack:FindFirstChildWhichIsA("ProximityPrompt", true)
                if not prompt then return end

                -- Silent remote activation (no E Interact UI)
                _G.ODXFn_SilentFirePrompt(prompt)
                task.wait(0.8)

                -- Click "I want to turn in my candy."
                local btn
                for _ = 1, 30 do
                    btn = _G.ODXFn_FindButtonByKeywords and _G.ODXFn_FindButtonByKeywords({
                        "i want to turn in my candy",
                        "turn in my candy",
                        "turn in candy"
                    })
                    if btn then break end
                    task.wait(0.1)
                end
                if btn and _G.ODXFn_ClickButtonObj then
                    _G.ODXFn_ClickButtonObj(btn)
                    task.wait(0.5)
                end

                -- Click "-click to continue" / "click to continue"
                for _ = 1, 10 do
                    local cont = nil
                    if _G.ODXFn_FindButtonByKeywords then
                        cont = _G.ODXFn_FindButtonByKeywords({
                            "click to continue",
                            "-click to continue",
                            "click to cont"
                        })
                    end
                    if cont and _G.ODXFn_ClickButtonObj then
                        _G.ODXFn_ClickButtonObj(cont)
                        task.wait(0.4)
                    else
                        -- fallback: click center if text is on screen
                        local pg = LocalPlayer:FindFirstChild("PlayerGui")
                        local found = false
                        if pg then
                            for _, gui in ipairs(pg:GetDescendants()) do
                                if (gui:IsA("TextLabel") or gui:IsA("TextButton")) then
                                    local t = (gui.Text or ""):lower()
                                    if t:find("click to continue") then
                                        found = true
                                        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
                                        task.wait(0.05)
                                        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
                                        task.wait(0.3)
                                        break
                                    end
                                end
                            end
                        end
                        if not found then break end
                    end
                end
            end)
            exchanging = false
            task.wait(3)
        end
    end)

    --// STAND PILOT
    task.spawn(function()
        local pilotCam = nil
        while ScriptActive do
            task.wait(0.03)
            if not Config.StandPilot then
                if pilotCam then
                    pcall(function()
                        workspace.CurrentCamera.CameraSubject = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                    end)
                    pilotCam = nil
                end
                continue
            end

            local char = LocalPlayer.Character
            if not char then continue end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum then continue end

            -- Summon stand if needed
            local stand = char:FindFirstChild("StandMorph") or workspace:FindFirstChild(LocalPlayer.Name .. "Stand")
            if not stand then
                local remote = char:FindFirstChild("RemoteFunction") or char:FindFirstChildOfClass("RemoteFunction")
                if remote then
                    pcall(function() remote:InvokeServer("ToggleStand", "Toggle") end)
                    task.wait(0.5)
                end
                continue
            end

            local standHRP = stand:FindFirstChild("HumanoidRootPart") or stand:FindFirstChildWhichIsA("BasePart")
            if not standHRP then continue end

            -- Move stand with WASD
            local cam = workspace.CurrentCamera
            local move = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end

            local spd = Config.StandPilotSpeed or 50
            if move.Magnitude > 0 then
                standHRP.CFrame = standHRP.CFrame + move.Unit * spd * 0.03
            end

            -- Camera follow stand
            pcall(function()
                cam.CameraSubject = standHRP
                pilotCam = true
            end)

            -- Keep player from moving while piloting
            pcall(function()
                hum.WalkSpeed = 0
            end)
        end
    end)

    --// WATERMARK (Minecraft-cheat style corner HUD)
    do
        local gui = Instance.new("ScreenGui")
        gui.Name = "ODX_Watermark"
        gui.IgnoreGuiInset = true
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 1000
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.Parent = CoreGui
        _G.ODXWatermarkGui = gui

        local label = Instance.new("TextLabel")
        label.Name = "Text"
        label.BackgroundTransparency = 1
        label.Position = UDim2.new(0, 12, 0, 10)
        label.Size = UDim2.new(0, 520, 0, 22)
        label.Font = Enum.Font.Code
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.TextColor3 = Color3.fromRGB(180, 220, 255)
        label.TextStrokeTransparency = 0.4
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.Text = "OVERDRIVE X | YBA"
        label.Parent = gui

        local frames = 0
        local lastFpsUpdate = os.clock()
        local fps = 0
        table.insert(Connections, RunService.RenderStepped:Connect(function()
            frames = frames + 1
            local now = os.clock()
            if now - lastFpsUpdate >= 0.5 then
                fps = math.floor(frames / (now - lastFpsUpdate) + 0.5)
                frames = 0
                lastFpsUpdate = now
            end
            if not Config.WatermarkEnabled then
                gui.Enabled = false
                return
            end
            gui.Enabled = true
            local name = LocalPlayer.Name or "?"
            label.Text = string.format("OVERDRIVE X | YBA  |  %s  |  %d FPS", name, fps)
        end))
    end

    _G.ODXESPContainer = CoreGui:FindFirstChild("OVERDRIVE_ESP_Container")
    if not _G.ODXESPContainer then
        _G.ODXESPContainer = Instance.new("Folder")
        _G.ODXESPContainer.Name = "OVERDRIVE_ESP_Container"
        _G.ODXESPContainer.Parent = CoreGui
    end

    _G.ODXActiveESP = {}

    _G.ODXRemoveESPForPlayer = function(player)
        if _G.ODXActiveESP[player] then
            if _G.ODXActiveESP[player].Highlight then
                _G.ODXActiveESP[player].Highlight:Destroy()
            end
            if _G.ODXActiveESP[player].Billboard then
                _G.ODXActiveESP[player].Billboard:Destroy()
            end
            _G.ODXActiveESP[player] = nil
        end
    end

    table.insert(Connections, RunService.RenderStepped:Connect(function()
        if not ScriptActive then
            return
        end
        pcall(function()
            if not Config.ESP_Players then
                if Options and Options.EspStatusLabelOpt then
                    Options.EspStatusLabelOpt:SetText("Status: Player ESP not working")
                end
                for plr, _ in pairs(_G.ODXActiveESP) do
                    _G.ODXRemoveESPForPlayer(plr)
                end
                return
            end
            if Options and Options.EspStatusLabelOpt then
                Options.EspStatusLabelOpt:SetText("Status: Player ESP working")
            end
            local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local pChar = player.Character
                    local pHRP = pChar and pChar:FindFirstChild("HumanoidRootPart")
                    local pHum = pChar and pChar:FindFirstChildOfClass("Humanoid")
                    if pChar and pHRP and pHum and pHum.Health > 0 then
                        local rgb = _G.ODXFn_GetESPColor()
                        if not _G.ODXActiveESP[player] then
                            local hl = Instance.new("Highlight")
                            hl.FillColor = rgb
                            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                            hl.FillTransparency = 0.5
                            hl.Adornee = pChar
                            hl.Parent = _G.ODXESPContainer
                            local bb = Instance.new("BillboardGui")
                            bb.Size = UDim2.new(0, 200, 0, 30)
                            bb.AlwaysOnTop = true
                            bb.Adornee = pHRP
                            bb.ExtentsOffset = Vector3.new(0, 2.5, 0)
                            local resultLabel = Instance.new("TextLabel")
                            resultLabel.Name = "Label"
                            resultLabel.Size = UDim2.new(1, 0, 1, 0)
                            resultLabel.BackgroundTransparency = 1
                            resultLabel.TextColor3 = rgb
                            resultLabel.Font = Enum.Font.SourceSansBold
                            resultLabel.TextSize = 14
                            resultLabel.TextStrokeTransparency = 0
                            resultLabel.Parent = bb
                            bb.Parent = _G.ODXESPContainer
                            _G.ODXActiveESP[player] = {Highlight = hl, Billboard = bb, Label = resultLabel}
                        else
                            _G.ODXActiveESP[player].Highlight.Adornee = pChar
                            _G.ODXActiveESP[player].Billboard.Adornee = pHRP
                            _G.ODXActiveESP[player].Highlight.FillColor = rgb
                            _G.ODXActiveESP[player].Label.TextColor3 = rgb
                            local distText = ""
                            if Config.ESP_PlayerDist and myHRP then
                                distText = " [" .. tostring(math.floor((myHRP.Position - pHRP.Position).Magnitude)) .. "m]"
                            end
                            _G.ODXActiveESP[player].Label.Text = player.Name .. distText
                        end
                    else
                        _G.ODXRemoveESPForPlayer(player)
                    end
                end
            end
            for plr, _ in pairs(_G.ODXActiveESP) do
                if not plr:IsDescendantOf(Players) then
                    _G.ODXRemoveESPForPlayer(plr)
                end
            end
        end)
    end))

    table.insert(Connections, Players.PlayerRemoving:Connect(function(plr)
        _G.ODXRemoveESPForPlayer(plr)
    end))


    
    -- Suppress proximity prompt UI while auto-sell / candy exchange is active
    table.insert(Connections, RunService.RenderStepped:Connect(function()
        if not ScriptActive then return end
        if ItemConfig.AutoSellEnabled or ItemConfig.AutoCandyExchange or isSellingItems then
            pcall(function()
                ProximityPromptService.MaxPromptsVisible = 0
            end)
        end
    end))

    
    --// AUTO MENU FLOW: Press to Skip → menu Play (above Help) → MAIN GAME PLAY
    task.spawn(function()
        local GuiService = game:GetService("GuiService")
        local step = 1 -- 1=skip, 2=left menu Play, 3=MAIN GAME PLAY
        local lastClick = 0
        local stepDeadline = 0
        local clickedMenuPlay = nil -- avoid re-clicking same button

        local function isReallyVisible(obj)
            local cur = obj
            while cur do
                if cur:IsA("GuiObject") then
                    if cur.Visible == false then return false end
                    if cur.AbsoluteSize.X <= 1 or cur.AbsoluteSize.Y <= 1 then return false end
                end
                if cur:IsA("ScreenGui") or cur:IsA("LayerCollector") then
                    if cur.Enabled == false then return false end
                end
                cur = cur.Parent
            end
            return true
        end

        local function collectText(obj)
            local parts = {}
            if obj:IsA("TextButton") or obj:IsA("TextLabel") or obj:IsA("TextBox") then
                local t = obj.Text
                if t and t ~= "" then table.insert(parts, t) end
            end
            if obj.Name and obj.Name ~= "" then
                table.insert(parts, obj.Name)
            end
            for _, child in ipairs(obj:GetDescendants()) do
                if child:IsA("TextLabel") or child:IsA("TextButton") then
                    local t = child.Text
                    if t and t ~= "" then table.insert(parts, t) end
                end
            end
            return table.concat(parts, " ")
        end

        local function forceClick(btn)
            if not btn or not btn.Parent then return false end
            pcall(function()
                if getconnections then
                    for _, signalName in ipairs({ "MouseButton1Click", "Activated", "MouseButton1Down", "MouseButton1Up" }) do
                        local ok, signal = pcall(function() return btn[signalName] end)
                        if ok and signal then
                            for _, conn in ipairs(getconnections(signal)) do
                                pcall(function()
                                    if conn.Function then conn:Fire() end
                                    if conn.Fire then conn:Fire() end
                                end)
                            end
                        end
                    end
                end
            end)
            pcall(function()
                if firesignal and btn.MouseButton1Click then firesignal(btn.MouseButton1Click) end
            end)
            pcall(function()
                if firesignal and btn.Activated then firesignal(btn.Activated) end
            end)
            pcall(function()
                local inset = GuiService:GetGuiInset()
                local pos = btn.AbsolutePosition + (btn.AbsoluteSize / 2) + inset
                VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
                task.wait(0.05)
                VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
            end)
            return true
        end

        local function getRoots()
            local roots = {}
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            if pg then table.insert(roots, pg) end
            pcall(function() table.insert(roots, CoreGui) end)
            return roots
        end

        local function ancestorHasText(obj, needle)
            local cur = obj
            local n = 0
            while cur and n < 12 do
                local t = collectText(cur):lower()
                if t:find(needle, 1, true) then return true end
                cur = cur.Parent
                n = n + 1
            end
            return false
        end

        -- mode: "skip" | "menu_play" | "main_play"
        local function findMenuButton(mode)
            local candidates = {}
            for _, root in ipairs(getRoots()) do
                for _, obj in ipairs(root:GetDescendants()) do
                    if not (obj:IsA("TextButton") or obj:IsA("ImageButton") or obj:IsA("TextLabel")) then
                        continue
                    end
                    if not isReallyVisible(obj) then continue end

                    local raw = collectText(obj)
                    local text = raw:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                    if text == "" then continue end

                    local clickTarget = obj
                    if not (obj:IsA("TextButton") or obj:IsA("ImageButton")) then
                        clickTarget = obj:FindFirstAncestorWhichIsA("TextButton")
                            or obj:FindFirstAncestorWhichIsA("ImageButton")
                            or obj
                    end
                    if not clickTarget or not isReallyVisible(clickTarget) then continue end
                    if clickedMenuPlay and clickTarget == clickedMenuPlay then continue end

                    local pos = clickTarget.AbsolutePosition
                    local size = clickTarget.AbsoluteSize

                    if mode == "skip" then
                        if text:find("press to skip", 1, true) or (text:find("skip", 1, true) and text:find("press", 1, true)) then
                            table.insert(candidates, { target = clickTarget, score = 100 })
                        end
                    elseif mode == "menu_play" then
                        -- Left sidebar Play (above Help). Prefer leftmost, pure "play" text, NOT near MAIN GAME.
                        local isPlay = (text == "play") or (raw:match("^%s*Play%s*$") ~= nil)
                        if isPlay and not text:find("skip", 1, true) and not text:find("player", 1, true) then
                            if ancestorHasText(clickTarget, "main game") then
                                continue -- this is the MAIN GAME panel button
                            end
                            -- Prefer left side of screen
                            local score = 100 - (pos.X / 10)
                            if pos.X < 250 then score = score + 40 end
                            if size.X < 220 then score = score + 15 end -- sidebar buttons are smaller width-ish
                            table.insert(candidates, { target = clickTarget, score = score })
                        end
                    elseif mode == "main_play" then
                        -- PLAY under MAIN GAME card
                        local isPlay = (text == "play") or (raw:match("^%s*PLAY%s*$") ~= nil) or (raw:match("^%s*Play%s*$") ~= nil)
                        if not isPlay then continue end
                        if text:find("skip", 1, true) or text:find("player", 1, true) then continue end

                        local score = 0
                        if ancestorHasText(clickTarget, "main game") then
                            score = score + 120
                        end
                        if ancestorHasText(clickTarget, "stands") or ancestorHasText(clickTarget, "spiritual") then
                            score = score + 40
                        end
                        -- Prefer more centered / not far-left menu
                        if pos.X > 200 then score = score + 30 end
                        if pos.X > 350 then score = score + 20 end
                        -- Prefer ALL-CAPS PLAY label slightly
                        if raw:find("PLAY") and not raw:find("Play") then
                            score = score + 10
                        end
                        if score > 0 then
                            table.insert(candidates, { target = clickTarget, score = score })
                        end
                    end
                end
            end

            table.sort(candidates, function(a, b) return a.score > b.score end)
            if #candidates > 0 then
                return candidates[1].target
            end
            return nil
        end

        while ScriptActive do
            task.wait(0.3)
            if not Config.AutoMenuFlow then
                step = 1
                clickedMenuPlay = nil
                continue
            end
            if os.clock() - lastClick < 0.5 then
                continue
            end

            if step == 1 then
                local btn = findMenuButton("skip")
                if btn then
                    forceClick(btn)
                    lastClick = os.clock()
                    step = 2
                    stepDeadline = os.clock() + 25
                    task.wait(1.0)
                end
            elseif step == 2 then
                if os.clock() > stepDeadline then
                    step = 1
                    clickedMenuPlay = nil
                    continue
                end
                local btn = findMenuButton("menu_play")
                if btn then
                    forceClick(btn)
                    clickedMenuPlay = btn
                    lastClick = os.clock()
                    step = 3
                    stepDeadline = os.clock() + 25
                    task.wait(1.2)
                end
            elseif step == 3 then
                if os.clock() > stepDeadline then
                    step = 1
                    clickedMenuPlay = nil
                    continue
                end
                local btn = findMenuButton("main_play")
                if btn then
                    forceClick(btn)
                    lastClick = os.clock()
                    step = 1
                    clickedMenuPlay = nil
                    task.wait(1.5)
                end
            end
        end
    end)

    --// ONLINE TRACKING (Cloudflare Worker)
    task.spawn(function()
        local workerUrl = "https://overdrive-online.dianalox287.workers.dev/heartbeat"
        while ScriptActive do
            pcall(function()
                local executor = "Unknown"
                pcall(function()
                    if identifyexecutor then executor = identifyexecutor() end
                    if getexecutorname then executor = getexecutorname() end
                end)
                local payload = {
                    nick = LocalPlayer.Name,
                    executor = tostring(executor or "Unknown"),
                    time = os.time(),
                }
                local body = HttpService:JSONEncode(payload)
                if type(request) == "function" then
                    request({
                        Url = workerUrl,
                        Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" },
                        Body = body,
                    })
                elseif type(http_request) == "function" then
                    http_request({
                        Url = workerUrl,
                        Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" },
                        Body = body,
                    })
                end
            end)
            task.wait(20)
        end
    end)


    Library:Notify("OVERDRIVE X loaded | V1.3 SBR upd")
