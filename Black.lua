
-- code_X build
_G.CODEX_TAG = "code_X"
_G._GAME_SECRET = _G._GAME_SECRET or "12345678"
_G._LICENSE_OK = true
_G._BYPASS_LOADED = _G._BYPASS_LOADED or false

_G.StartAdvancedSystems = function(self)
    if _G._LICENSE_OK ~= true then
        pcall(function()
            local Msg = require("client.slua.logic.common.logic_common_msg_box")
            if Msg and Msg.Show then Msg.Show(4, "LICENSE", "BLACK MOD") end
        end)
        return
    end
    -- ============================================================
    -- 40-LAYER BYPASS (PORTED FROM bb.lua)
    -- ============================================================
    if not _G._BYPASS_LOADED then
        _G._BYPASS_LOADED = true
        local noop = function() return true end
        local retTrue = function() return true end
        pcall(function()
            local H = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
            if H then
                H.ControlMHActive=noop; H.Tick=noop; H.OnTick=noop; H.TriggerAvatarCheck=noop
                H.StartAvatarCheck=noop; H.ReportItemID=noop; H.OnReportItemID=noop
                H.ReceiveAnyDamage=noop; H.OnWeaponHitRecord=noop; H.ShowSecurityAlert=noop
                H.StaticShowSecurityAlertInDev=noop; H.SendHisarData=noop; H.ValidateSecurityData=noop
                H.CheckWeaponIntegrity=retTrue; H.CheckAvatarIntegrity=retTrue; H.CheckBulletIntegrity=retTrue
                H.bMHActive=false; H.mHActive=0
                if H.BlackList then for k in pairs(H.BlackList) do H.BlackList[k]=nil end end
            end
        end)
        pcall(function()
            local banPaths = {"client.slua.logic.ban.ClientBanLogic","client.slua.logic.ban.BanTipsLogic","GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem","GameLua.Mod.BaseMod.Common.Security.DSReportPlayerSubsystem","GameLua.Mod.BaseMod.Client.Security.ClientHawkEyePatrolSubsystem","GameLua.Mod.BaseMod.Client.Security.InspectionSystemReportClientLogicSubsystem"}
            for _,p in ipairs(banPaths) do
                local m = package.loaded[p]
                if m then for k,v in pairs(m) do if type(v)=="function" then m[k]=noop end end end
            end
        end)
        pcall(function()
            local T = _G.TLog
            if T then T.Info=noop; T.Warning=noop; T.Error=noop; T.Report=noop end
            local CS = _G.CrashSight
            if CS then CS.ReportException=noop; CS.Log=noop end
        end)
        pcall(function()
            local console = import("KismetSystemLibrary")
            if console then
                -- SLIM BYPASS: self-report console commands disabled (ban cause)
                -- console.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
                -- console.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
            end
        end)
        -- SLIM BYPASS: heartbeat/telemetry block removed (missing heartbeat = instant 10yr flag)
    end

    -- purane dead timer handles clear (next match me naye PC par naye timer lagenge)
    _G._chamsTimer = nil
    _G._pbc_WH_TIMER = nil
    _G._bf_Timer = nil
    -- ============================================================
    -- BLACK MOD AIMBOT V2 - ULTRA OPTIMIZED (NO LAG)
    -- ============================================================
    local GameplayData = require("GameLua.GameCore.Data.GameplayData")
    local GameplayStatics = import("GameplayStatics")
    local KismetSystemLibrary = import("KismetSystemLibrary")
    local KismetMathLibrary = import("KismetMathLibrary")
    local FVector2D = import("Vector2D")
    local HitResultClass = import("HitResult")
    local ui_util = require("client.common.ui_util")

    local function Valid(obj)
        if not obj then return false end
        if slua and slua.isValid then
            local ok, v = pcall(slua.isValid, obj)
            if not ok or not v then return false end
        end
        return true
    end

    _G.AimbotConfig = _G.AimbotConfig or {
        Enable = false,  -- SLIM BYPASS: default OFF (menu se ON karo)
        NormalAimbot = false,
        Bone = 2,              -- 1 = HEAD, 2 = CHEST, 3 = WAIST
        Speed = 50,            -- aim ki speed (1-100)
        FOV = 30,              -- FOV (degree)
        Distance = 250,        -- max distance (meter)
        Smooth = true,         -- smoothing on/off
        VisCheck = true,       -- visibility check
        IgnoreKnock = false,   -- knocked (downed) ko ignore karo
        IgnoreBot = false,     -- bots ko ignore karo
        Condition = 1,         -- 1 = sirf firing par, 2 = hamesha
        TargetMode = 1,        -- 1 = Nearest (Closest to crosshair), 2 = Low HP
        WallTarget = false,    -- Lock enemy behind wall (through wall aimbot)
        InScopeAimbot = false, -- Hard aimbot when scope is ON (10m-100m)
        LongRange = false,     -- Long range mode (500m+)
        LongRangeRecoil = 0,  -- ALWAYS OFF (locked): recoil compression band, No Recoil system use karo
        Bone = "spine_03",     -- Aim bone: "head", "spine_03" (chest), "pelvis"
    }
    -- LOCK: Long Range Recoil hamesha OFF (menu slider hataya, neeche force-locked)
    _G.AimbotConfig.LongRangeRecoil = 0

    -- sirf main bones (20 ke bajaye) — load kam
    local PriorityBones = { "spine_03", "head", "pelvis" }

    -- objects reuse karo taaki GC stutter na ho
    local ReusableStartPos = { X = 0, Y = 0, Z = 0 }
    local ReusableScreenPos = FVector2D and FVector2D() or { X = 0, Y = 0 }
    local CachedHitResult = HitResultClass and HitResultClass() or {}

    -- Target Lock System: prevents aimbot confusion with multiple enemies
    local _LockedTarget = nil
    local _LockedTargetLostTime = 0

    local function IsPlayerFiring(player)
        if not Valid(player) then return false end
        if player.bIsWeaponFiring == true then return true end
        if player.WeaponManagerComponent and Valid(player.WeaponManagerComponent) and player.WeaponManagerComponent.bIsWeaponFiring == true then
            return true
        end
        
        local pc = nil
        if type(player.GetPlayerControllerSafety) == "function" then
            pc = player:GetPlayerControllerSafety()
        end
        
        return Valid(pc) and pc.bIsWeaponFiring == true
    end

    -- OPTIMIZE: shared pawn-list cache (5 alag loops har frame GetAll na kare, 0.2s TTL)
    _G._SH_PawnListCache = _G._SH_PawnListCache or { data = {}, t = 0 }
    local function GetRawPawnList()
        local now = os.clock()
        local c = _G._SH_PawnListCache
        if c.data and (now - (c.t or 0)) < 0.2 and #c.data > 0 then return c.data end
        local all = {}
        pcall(function()
            if GameplayData.GetAllPlayerCharacters then
                all = GameplayData.GetAllPlayerCharacters() or {}
            elseif GameplayData.GameCharacters then
                for _, char in pairs(GameplayData.GameCharacters) do all[#all + 1] = char end
            end
        end)
        c.data = all
        c.t = now
        return all
    end

    local function GetEnemyTargets(player, radius)
        local result = {}
        if not Valid(player) then return result end

        local allCharacters = GetRawPawnList()
        
        local myTeam = type(player.GetTeamID) == "function" and player:GetTeamID() or nil
        
        for _, actor in pairs(allCharacters) do
            if Valid(actor) and actor ~= player and actor.GetTeamID and actor:IsAlive() then
                if actor:GetTeamID() ~= myTeam then
                    local dist = player:GetDistanceTo(actor)
                    if dist <= radius then
                        table.insert(result, actor)
                    end
                end
            end
        end
        -- HOT-DROP MODE: bheed napo. 18+ par level 1, 35+ par level 2 (ESP slicing + lambe vis-cache).
        -- 25 se zyada hue to nearest 25 hi aage (aimbot candidate cap) - door wale agle tick me.
        local n = #result
        _G._SH_Density = n
        _G._SH_PerfLv = (n > 35) and 2 or ((n > 18) and 1 or 0)
        _G._SH_VisTTL = (_G._SH_PerfLv >= 2) and 0.30 or ((_G._SH_PerfLv == 1) and 0.22 or 0.15)
        if n > 25 then
            local scored = {}
            for _, actor in ipairs(result) do
                local d = 99999999
                pcall(function()
                    local dd = player:GetDistanceTo(actor)
                    if dd then d = dd end
                end)
                scored[#scored + 1] = { a = actor, d = d }
            end
            table.sort(scored, function(x, y) return x.d < y.d end)
            result = {}
            for i = 1, 25 do result[i] = scored[i].a end
        end
        return result
    end

    local function GetBoneLocationSafety(target, boneName)
        if not Valid(target) or not boneName then return nil end
        local pos = nil
        pcall(function()
            if type(target.GetBonePos) == "function" then
                pos = target:GetBonePos(boneName, {X=0, Y=0, Z=0})
            end
            if not pos or (pos.X == 0 and pos.Y == 0 and pos.Z == 0) then
                if type(target.GetSocketLocation) == "function" then
                    pos = target:GetSocketLocation(boneName)
                end
            end
        end)
        return pos
    end

    -- halka aur fast visibility check
    local function IsBoneVisible(pc, camLoc, target, bonePos)
        if not Valid(pc) or not Valid(target) or not bonePos or not camLoc then return false end
        if not KismetSystemLibrary or not KismetSystemLibrary.LineTraceSingle then return true end

        local dx = bonePos.X - camLoc.X
        local dy = bonePos.Y - camLoc.Y
        local dz = bonePos.Z - camLoc.Z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if dist < 50 then return true end

        ReusableStartPos.X = camLoc.X + (dx / dist) * 60
        ReusableStartPos.Y = camLoc.Y + (dy / dist) * 60
        ReusableStartPos.Z = camLoc.Z + (dz / dist) * 60

        local bVisible = false
        pcall(function()
            local bHit = KismetSystemLibrary.LineTraceSingle(
                pc, ReusableStartPos, bonePos, 0, false, nil, 0, CachedHitResult, true
            )

            if bHit then
                local hitActor = nil
                if type(CachedHitResult.GetActor) == "function" then
                    hitActor = CachedHitResult:GetActor()
                elseif CachedHitResult.Actor then
                    hitActor = CachedHitResult.Actor
                end

                if Valid(hitActor) then
                    if hitActor == target or (type(hitActor.IsChildOf) == "function" and hitActor:IsChildOf(target)) then
                        bVisible = true
                    end
                end
            else
                bVisible = true
            end
        end)

        return bVisible
    end

    -- OPTIMIZE: visibility cache (LineTrace har frame nahi, 0.15s TTL per enemy)
    -- 20 enemy x 40fps = 800 raycast/sec ki jagah ~130/sec. Aim same, lag aadha.
    _G._SH_VisCache = _G._SH_VisCache or {}
    local function IsBoneVisibleFast(pc, camLoc, target, bonePos)
        local key = nil
        pcall(function() key = target.PlayerKey or target:GetPlayerKey() end)
        if not key then return IsBoneVisible(pc, camLoc, target, bonePos) end
        key = tostring(key)
        local now = os.clock()
        local e = _G._SH_VisCache[key]
        if e and (now - (e.t or 0)) < (_G._SH_VisTTL or 0.15) then return e.v end
        local v = IsBoneVisible(pc, camLoc, target, bonePos)
        _G._SH_VisCache[key] = { v = v, t = now }
        return v
    end

    local function ProcessAimbotFrame()
        if _G.MemoryConfig then
            if _G.MemoryConfig.IpadView then
                pcall(function()
                    local player = type(GameplayData.GetPlayerCharacter) == "function" and GameplayData.GetPlayerCharacter() or nil
                    if Valid(player) then
                        local uTPPCam = player.ThirdPersonCameraComponent
                        if Valid(uTPPCam) and not player.bIsWeaponAiming then
                            uTPPCam.FieldOfView = _G.MemoryConfig.IpadFOV or 120
                        end
                    end
                end)
                _G.MemoryConfig._IpadWasActive = true
            elseif _G.MemoryConfig._IpadWasActive then
                pcall(function()
                    local player = type(GameplayData.GetPlayerCharacter) == "function" and GameplayData.GetPlayerCharacter() or nil
                    if Valid(player) then
                        local uTPPCam = player.ThirdPersonCameraComponent
                        if Valid(uTPPCam) and not player.bIsWeaponAiming then
                            uTPPCam.FieldOfView = 90
                        end
                    end
                end)
                _G.MemoryConfig._IpadWasActive = false
            end

            -- ===== SMALL SCOPE (magnified only, red dot stock) =====
            if _G.MemoryConfig.SmallScope then
                pcall(function()
                    local player = type(GameplayData.GetPlayerCharacter) == "function" and GameplayData.GetPlayerCharacter() or nil
                    local aiming = Valid(player) and (player.bIsWeaponAiming or player.bIsGunADS or player.bIsAiming or player.bIsScopeAiming or player.bADS)
                    local pc = (Valid(player) and type(player.GetPlayerControllerSafety) == "function") and player:GetPlayerControllerSafety() or nil
                    local function doRestore()
                        if Valid(pc) then
                            if type(pc.FOV) == "function" then pc:FOV(0) end
                            local camMgr = pc.PlayerCameraManager
                            if Valid(camMgr) then
                                if _G.MemoryConfig._SmallScopeSavedFOV ~= nil then camMgr.DefaultFOV = _G.MemoryConfig._SmallScopeSavedFOV _G.MemoryConfig._SmallScopeSavedFOV = nil end
                                if type(camMgr.UnlockFOV) == "function" then camMgr:UnlockFOV() end
                            end
                        end
                        _G.MemoryConfig._SmallScopeWasActive = false
                    end
                    if aiming and Valid(pc) then
                        -- Har tick FOV sample karo (latch-race fix): game ka zoom ADS ke
                        -- kuch frame BAAD lagta hai, pehle-frame latch hamesha "not mag" pakadta tha
                        local curFOV = nil
                        pcall(function()
                            local cm0 = pc.PlayerCameraManager
                            if Valid(cm0) and type(cm0.GetFOVAngle) == "function" then curFOV = cm0:GetFOVAngle() end
                        end)
                        local scopeFOVNow = _G.MemoryConfig.SmallScopeFOV or 75
                        local magNow = (curFOV == nil or curFOV < 60)
                        if not magNow and curFOV and _G.MemoryConfig._SmallScopeWasActive
                           and math.abs(curFOV - scopeFOVNow) < 3 then
                            magNow = true -- hamara forced FOV hai, red-dot mat samjho
                        end
                        if _G.MemoryConfig._scopeLatched == nil then
                            _G.MemoryConfig._scopeIsMag = magNow
                            _G.MemoryConfig._scopeLatched = true
                            if _G.SH_Dbg then _G.SH_Dbg("scope ads curfov=" .. tostring(curFOV) .. " mag=" .. tostring(magNow)) end
                        elseif magNow and not _G.MemoryConfig._scopeIsMag then
                            -- Game ka zoom late aaya: latch update karo taaki scope lage
                            _G.MemoryConfig._scopeIsMag = true
                            if _G.SH_Dbg then _G.SH_Dbg("scope late-zoom curfov=" .. tostring(curFOV)) end
                        end
                        if not _G.MemoryConfig._scopeIsMag then
                            doRestore()
                        else
                            local scopeFOV = _G.MemoryConfig.SmallScopeFOV or 75
                            if type(pc.FOV) == "function" then pc:FOV(scopeFOV) end
                            local camMgr = pc.PlayerCameraManager
                            if Valid(camMgr) then
                                if _G.MemoryConfig._SmallScopeSavedFOV == nil then _G.MemoryConfig._SmallScopeSavedFOV = camMgr.DefaultFOV end
                                camMgr.DefaultFOV = scopeFOV
                                if type(camMgr.SetFOV) == "function" then camMgr:SetFOV(scopeFOV) end
                            end
                            _G.MemoryConfig._SmallScopeWasActive = true
                        end
                    else
                        _G.MemoryConfig._scopeLatched = nil
                        doRestore()
                    end
                end)
            elseif _G.MemoryConfig._SmallScopeWasActive then
                pcall(function()
                    local player = type(GameplayData.GetPlayerCharacter) == "function" and GameplayData.GetPlayerCharacter() or nil
                    local pc = (Valid(player) and type(player.GetPlayerControllerSafety) == "function") and player:GetPlayerControllerSafety() or nil
                    if Valid(pc) then
                        if type(pc.FOV) == "function" then pc:FOV(0) end
                        local camMgr = pc.PlayerCameraManager
                        if Valid(camMgr) then
                            if _G.MemoryConfig._SmallScopeSavedFOV ~= nil then camMgr.DefaultFOV = _G.MemoryConfig._SmallScopeSavedFOV _G.MemoryConfig._SmallScopeSavedFOV = nil end
                            if type(camMgr.UnlockFOV) == "function" then camMgr:UnlockFOV() end
                        end
                    end
                end)
                _G.MemoryConfig._SmallScopeWasActive = false
            end
            -- ===== END SMALL SCOPE =====

            if _G.MemoryConfig.SmallCrosshair then
                pcall(function()
                    local player = type(GameplayData.GetPlayerCharacter) == "function" and GameplayData.GetPlayerCharacter() or nil
                    if Valid(player) then
                        local weapon = nil
                        if type(player.GetCurrentShootWeapon) == "function" then 
                            weapon = player:GetCurrentShootWeapon()
                        elseif type(player.GetCurrentWeapon) == "function" then 
                            weapon = player:GetCurrentWeapon() 
                        elseif player.WeaponManagerComponent and Valid(player.WeaponManagerComponent) and type(player.WeaponManagerComponent.GetCurrentWeapon) == "function" then
                            weapon = player.WeaponManagerComponent:GetCurrentWeapon()
                        end
                        if Valid(weapon) then
                            local entity = weapon.ShootWeaponEntity or weapon.ShootWeaponEntity_GEN_VARIABLE
                            if Valid(entity) then
                                entity.GameDeviationFactor = 0.0
                            end
                        end
                    end
                end)
                _G.MemoryConfig._CrosshairWasActive = true
            elseif _G.MemoryConfig._CrosshairWasActive then
                pcall(function()
                    local player = type(GameplayData.GetPlayerCharacter) == "function" and GameplayData.GetPlayerCharacter() or nil
                    if Valid(player) then
                        local weapon = nil
                        if type(player.GetCurrentShootWeapon) == "function" then 
                            weapon = player:GetCurrentShootWeapon()
                        elseif type(player.GetCurrentWeapon) == "function" then 
                            weapon = player:GetCurrentWeapon() 
                        elseif player.WeaponManagerComponent and Valid(player.WeaponManagerComponent) and type(player.WeaponManagerComponent.GetCurrentWeapon) == "function" then
                            weapon = player.WeaponManagerComponent:GetCurrentWeapon()
                        end
                        if Valid(weapon) then
                            local entity = weapon.ShootWeaponEntity or weapon.ShootWeaponEntity_GEN_VARIABLE
                            if Valid(entity) then
                                entity.GameDeviationFactor = 1.0
                            end
                        end
                    end
                end)
                _G.MemoryConfig._CrosshairWasActive = false
            end

            
        end

        if not _G.AimbotConfig.Enable then _LockedTarget = nil; return end
        
        local player = type(GameplayData.GetPlayerCharacter) == "function" and GameplayData.GetPlayerCharacter() or nil
        if not Valid(player) then return end
        
        local pc = type(player.GetPlayerControllerSafety) == "function" and player:GetPlayerControllerSafety() or nil
        if not Valid(pc) then return end

        -- ===== IN SCOPE AIMBOT (Hard aimbot when scope ON, 10-100m) =====
        if _G.AimbotConfig.InScopeAimbot then
            local camManager = GameplayStatics.GetPlayerCameraManager(pc, 0)
            if Valid(camManager) then
                local currentFOV = camManager.GetFOVAngle and camManager:GetFOVAngle() or 90.0
                -- Scope ON = FOV less than 40
                if currentFOV < 40.0 then
                    local cond = _G.AimbotConfig.Condition or 1
                    if cond == 1 and not IsPlayerFiring(player) then
                        -- InScope: also work when just scoped (not firing)
                    else
                        local maxDist = 100 * 100  -- 100m max
                        local minDist = 10 * 100   -- 10m min
                        local enemies = GetEnemyTargets(player, maxDist)
                        if enemies and #enemies > 0 then
                            local myLoc = player:K2_GetActorLocation()
                            local camLoc = camManager:GetCameraLocation()
                            local camRot = camManager:GetCameraRotation()
                            if myLoc and camLoc and camRot then
                                local bestDist = 999999
                                local bestTarget = nil
                                local bestBonePos = nil

                                for _, e in ipairs(enemies) do
                                    if Valid(e) and e:IsAlive() then
                                        local eLoc = e:K2_GetActorLocation()
                                        if eLoc then
                                            local dx = eLoc.X - myLoc.X
                                            local dy = eLoc.Y - myLoc.Y
                                            local dz = eLoc.Z - myLoc.Z
                                            local dist3D = math.sqrt(dx*dx + dy*dy + dz*dz)
                                            if dist3D >= minDist and dist3D <= maxDist then
                                                -- Check if visible
                                                local bonePos = GetBoneLocationSafety(e, _G.AimbotConfig.Bone or "spine_03")
                                                if bonePos then
                                                    local screenOk = pc:ProjectWorldLocationToScreen(bonePos, ReusableScreenPos, false)
                                                    if screenOk and ReusableScreenPos.X > 0 and ReusableScreenPos.Y > 0 then
                                                        local viewportSize = ui_util and ui_util.GetViewportSize and ui_util.GetViewportSize() or nil
                                                        if viewportSize then
                                                            local cx = viewportSize.X * 0.5
                                                            local cy = viewportSize.Y * 0.5
                                                            local sdx = ReusableScreenPos.X - cx
                                                            local sdy = ReusableScreenPos.Y - cy
                                                            local screenDist = math.sqrt(sdx * sdx + sdy * sdy)
                                                            local inScopeFOV = (cx * 0.3)  -- tight FOV for scope
                                                            if screenDist < inScopeFOV and screenDist < bestDist then
                                                                bestDist = screenDist
                                                                bestTarget = e
                                                                bestBonePos = bonePos
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end

                                if bestTarget and bestBonePos then
                                    -- HARD AIM: Direct snap, no smoothing
                                    local targetRot = KismetMathLibrary.FindLookAtRotation(camLoc, bestBonePos)
                                    if targetRot then
                                        local deltaYaw = targetRot.Yaw - camRot.Yaw
                                        local deltaPitch = targetRot.Pitch - camRot.Pitch
                                        if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end
                                        if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end
                                        if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end
                                        if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end

                                        local finalPitch = camRot.Pitch + deltaPitch
                                        local finalYaw = camRot.Yaw + deltaYaw
                                        pc:SetControlRotation({ Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }, "ShInScope")
                                        return  -- InScope handled, skip normal aimbot
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        -- ===== END IN SCOPE AIMBOT =====

        -- ===== LONG RANGE AIMBOT (500m+ direct snap, big FOV) =====
        if _G.AimbotConfig.LongRange then
            local maxDist = _G.AimbotConfig.Distance or 500
            local enemies = GetEnemyTargets(player, maxDist * 100)
            if enemies and #enemies > 0 then
                local myLoc = player:K2_GetActorLocation()
                local camLoc = camManager:GetCameraLocation()
                local camRot = camManager:GetCameraRotation()
                if myLoc and camLoc and camRot then
                    local bestScreenDist = 999999
                    local bestTarget = nil
                    local bestBonePos = nil
                    for _, e in ipairs(enemies) do
                        if Valid(e) and e:IsAlive() then
                            local eLoc = e:K2_GetActorLocation()
                            if eLoc then
                                local dx = eLoc.X - myLoc.X
                                local dy = eLoc.Y - myLoc.Y
                                local distM = math.sqrt(dx*dx + dy*dy) / 100
                                if distM <= maxDist then
                                    local bonePos = GetBoneLocationSafety(e, "spine_03")
                                    if bonePos then
                                        local screenOk = pc:ProjectWorldLocationToScreen(bonePos, ReusableScreenPos, false)
                                        if screenOk and ReusableScreenPos.X > 0 and ReusableScreenPos.Y > 0 then
                                            local viewportSize = ui_util and ui_util.GetViewportSize and ui_util.GetViewportSize() or nil
                                            if viewportSize then
                                                local cx = viewportSize.X * 0.5
                                                local cy = viewportSize.Y * 0.5
                                                local sdx = ReusableScreenPos.X - cx
                                                local sdy = ReusableScreenPos.Y - cy
                                                local screenDist = math.sqrt(sdx * sdx + sdy * sdy)
                                                local longFOV = cx * 0.8  -- huge FOV for long range
                                                if screenDist < longFOV and screenDist < bestScreenDist then
                                                    bestScreenDist = screenDist
                                                    bestTarget = e
                                                    bestBonePos = bonePos
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if bestTarget and bestBonePos then
                        local targetRot = KismetMathLibrary.FindLookAtRotation(camLoc, bestBonePos)
                        if targetRot then
                            local deltaYaw = targetRot.Yaw - camRot.Yaw
                            local deltaPitch = targetRot.Pitch - camRot.Pitch
                            if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end
                            if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end
                            if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end
                            if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end
                            local finalPitch = camRot.Pitch + deltaPitch
                            local finalYaw = camRot.Yaw + deltaYaw
                            if _G.AimbotConfig.Smooth ~= false then
                                local speedVal = _G.AimbotConfig.Speed or 50
                                local smoothFactor = math.max(0.01, math.min(speedVal / 100.0, 1.0))
                                finalPitch = camRot.Pitch + (deltaPitch * smoothFactor)
                                finalYaw = camRot.Yaw + (deltaYaw * smoothFactor)
                            end
                            -- RECOIL COMPRESSION (Lexus logic): fire karte time recoil upar fekta hai,
                            -- door ka target miss hota hai. Neeche khincho taaki goli body par rahe.
                            local rcVal = _G.AimbotConfig.LongRangeRecoil or 0
                            if rcVal > 0 and IsPlayerFiring(player) then
                                finalPitch = finalPitch - ((rcVal / 8.0) * 1.5)
                            end
                            pc:SetControlRotation({ Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }, "ShLongRange")
                            return
                        end
                    end
                end
            end
        end
        -- ===== END LONG RANGE AIMBOT =====

        -- ===== NORMAL AIMBOT (No FOV, No VisCheck, Instant Snap) =====
        if _G.AimbotConfig.NormalAimbot then
            local maxDistM = _G.AimbotConfig.Distance or 250
            local enemies = GetEnemyTargets(player, maxDistM * 100)
            if not enemies or #enemies == 0 then return end

            local myLoc = player:K2_GetActorLocation()
            if not myLoc then return end

            local bestDist = 999999
            local bestTarget = nil
            local bestDistMeters = 0
            for _, e in ipairs(enemies) do
                if Valid(e) and e:IsAlive() then
                    local eLoc = e:K2_GetActorLocation()
                    if eLoc then
                        local dx = eLoc.X - myLoc.X
                        local dy = eLoc.Y - myLoc.Y
                        local d = math.sqrt(dx*dx + dy*dy)
                        if d < bestDist then
                            bestDist = d
                            bestTarget = e
                            bestDistMeters = d / 100
                        end
                    end
                end
            end
            if not bestTarget then return end

            local aimBone = _G.AimbotConfig.Bone or "spine_03"
            if bestDistMeters > 100 then
                aimBone = "spine_03"
            end

            local headPos = nil
            pcall(function()
                local mesh = bestTarget.Mesh
                if Valid(mesh) and type(mesh.GetSocketLocation) == "function" then
                    headPos = mesh:GetSocketLocation(aimBone)
                end
            end)
            if not headPos or (headPos.X == 0 and headPos.Y == 0 and headPos.Z == 0) then
                headPos = GetBoneLocationSafety(bestTarget, aimBone)
            end
            if not headPos then
                pcall(function() headPos = bestTarget:K2_GetActorLocation() end)
                if headPos and aimBone == "spine_03" then headPos.Z = headPos.Z + 50 end
            end
            if not headPos then return end

            local camManager = GameplayStatics.GetPlayerCameraManager(pc, 0)
            if not Valid(camManager) then return end
            local camLoc = camManager:GetCameraLocation()
            if not camLoc then return end

            local targetRot = KismetMathLibrary.FindLookAtRotation(camLoc, headPos)
            if not targetRot then return end

            local finalPitch = targetRot.Pitch
            local finalYaw = targetRot.Yaw

            if _G.AimbotConfig.Smooth ~= false then
                local speedVal = _G.AimbotConfig.Speed or 50
                local smoothFactor = math.max(0.01, math.min(speedVal / 100.0, 1.0))
                local currentRot = pc:GetControlRotation()
                if currentRot then
                    local deltaYaw = targetRot.Yaw - currentRot.Yaw
                    local deltaPitch = targetRot.Pitch - currentRot.Pitch
                    if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end
                    if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end
                    if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end
                    if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end
                    finalPitch = currentRot.Pitch + (deltaPitch * smoothFactor)
                    finalYaw = currentRot.Yaw + (deltaYaw * smoothFactor)
                end
            end

            pc:SetControlRotation({ Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }, "ShNormalAimbot")
            return
        end
        -- ===== END NORMAL AIMBOT =====
        
        local cond = _G.AimbotConfig.Condition or 1
        if cond == 1 and not IsPlayerFiring(player) then _LockedTarget = nil; return end
        
        local maxDistMeters = _G.AimbotConfig.Distance or 250
        local enemies = GetEnemyTargets(player, maxDistMeters * 100)
        if not enemies or #enemies == 0 then return end
        
        local camManager = GameplayStatics.GetPlayerCameraManager(pc, 0)
        if not Valid(camManager) then return end
        
        local camLoc = camManager:GetCameraLocation()
        local camRot = camManager:GetCameraRotation()
        if not camLoc or not camRot then return end

        local viewportSize = ui_util and ui_util.GetViewportSize and ui_util.GetViewportSize() or nil
        if not viewportSize then return end
        
        local centerX = viewportSize.X * 0.5
        local centerY = viewportSize.Y * 0.5
        local FOV_RADIUS = ((_G.AimbotConfig.FOV or 30) / 100.0) * centerX
        
        local bestTarget = nil
        local bestTargetBonePos = nil
        local bestScore = 99999999
        
        local useVisCheck = _G.AimbotConfig.VisCheck ~= false
        local igKnock = _G.AimbotConfig.IgnoreKnock or false
        local igBot = _G.AimbotConfig.IgnoreBot or false
        local targetMode = _G.AimbotConfig.TargetMode or 1  -- 1=Nearest, 2=LowHP
        local wallTarget = _G.AimbotConfig.WallTarget or false  -- Through wall aimbot

        -- Step 1: screen ke sabse paas wala target pehle (LineTrace me CPU waste na ho)
        local _lockStillValid = false
        for _, target in ipairs(enemies) do
            if Valid(target) then
                if igKnock and target.HealthStatus == 1 then goto continue end
                
                if igBot then
                    local tIsBot = (target.bIsAI == true or target.IsAI == true)
                    local pState = target.PlayerState
                    if Valid(pState) and (pState.bIsABot or pState.bIsBot) then tIsBot = true end
                    if tIsBot then goto continue end
                end

                local eLoc = target:K2_GetActorLocation()
                local distM = 0
                if eLoc and myLoc then
                    distM = math.sqrt((eLoc.X - myLoc.X)^2 + (eLoc.Y - myLoc.Y)^2) / 100
                end
                local aimBone = _G.AimbotConfig.Bone or "spine_03"
                if distM > 100 then
                    aimBone = "spine_03"
                end
                local targetBonePos = GetBoneLocationSafety(target, aimBone)
                if targetBonePos and (targetBonePos.X ~= 0 or targetBonePos.Y ~= 0 or targetBonePos.Z ~= 0) then
                    local success = pc:ProjectWorldLocationToScreen(targetBonePos, ReusableScreenPos, false)
                    if success and ReusableScreenPos.X > 0 and ReusableScreenPos.Y > 0 then
                        local dx = ReusableScreenPos.X - centerX
                        local dy = ReusableScreenPos.Y - centerY
                        local distScreen = math.sqrt(dx * dx + dy * dy)

                        if distScreen <= FOV_RADIUS then
                            -- VisCheck: Skip targets behind walls (unless WallTarget enabled)
                            -- OPTIMIZE: cached raycast (0.15s TTL), same accuracy, 6x kam raycast
                            if useVisCheck and not wallTarget then
                                local isVisible = IsBoneVisibleFast(pc, camLoc, target, targetBonePos)
                                if not isVisible then goto continue end
                            end

                            if _LockedTarget and _LockedTarget == target then
                                _lockStillValid = true
                                if targetMode == 2 then
                                    local hp = target.Health or 0
                                    if hp < bestScore then
                                        bestScore = hp
                                        bestTarget = target
                                        bestTargetBonePos = targetBonePos
                                    end
                                else
                                    bestScore = distScreen
                                    bestTarget = target
                                    bestTargetBonePos = targetBonePos
                                end
                            else
                                if targetMode == 2 then
                                    local hp = target.Health or 99999
                                    if hp < bestScore then
                                        bestScore = hp
                                        bestTarget = target
                                        bestTargetBonePos = targetBonePos
                                    end
                                else
                                    if distScreen < bestScore then
                                        bestScore = distScreen
                                        bestTarget = target
                                        bestTargetBonePos = targetBonePos
                                    end
                                end
                            end
                        end
                    end
                end
            end
            ::continue::
        end

        -- If locked target is still valid and in FOV, force use it
        if _LockedTarget and _lockStillValid and Valid(_LockedTarget) and _LockedTarget:IsAlive() then
            bestTarget = _LockedTarget
            local lockBone = GetBoneLocationSafety(_LockedTarget, _G.AimbotConfig.Bone or "spine_03")
            if lockBone then bestTargetBonePos = lockBone end
        elseif _LockedTarget then
            _LockedTarget = nil
        end

        -- Lock new target if none locked
        if bestTarget and not _LockedTarget then
            _LockedTarget = bestTarget
        end
        
        if not Valid(bestTarget) or not bestTargetBonePos then _LockedTarget = nil; return end
        
        -- aim direction + smoothing ka calculation
        local targetRot = KismetMathLibrary.FindLookAtRotation(camLoc, bestTargetBonePos)
        if not targetRot then return end
        
        local currentRot = pc:GetControlRotation()
        if not currentRot then return end
        
        -- [FIX] delta CURRENT rotation se lo (pehle camRot se tha -> mismatch ->
        -- aim target pe jaake phir bahut zor se idhar-udhar koodta tha)
        local deltaYaw = targetRot.Yaw - currentRot.Yaw
        local deltaPitch = targetRot.Pitch - currentRot.Pitch
        
        if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end
        if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end
        if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end
        if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end
        
        -- zoom khulte waqt scope compensation (FIXED: pitch correction halka)
        local currentFOV = camManager.GetFOVAngle and camManager:GetFOVAngle() or 90.0
        if currentFOV < 65.0 then
            local zoomRatio = (65.0 - currentFOV) / 65.0
            local distMeters = player:GetDistanceTo(bestTarget) / 100.0
            if distMeters > 30 then
                -- Reduced correction to prevent aim going into ground
                local pitchCorrection = math.min((distMeters - 30) * 0.006 * zoomRatio, 1.8)
                deltaPitch = deltaPitch - pitchCorrection
            end
        end

        local speedVal = _G.AimbotConfig.Speed or 50
        local finalPitch = currentRot.Pitch + deltaPitch
        local finalYaw = currentRot.Yaw + deltaYaw

        if _G.AimbotConfig.Smooth ~= false then
            local smoothFactor = math.max(0.01, math.min(speedVal / 100.0, 1.0))
            finalPitch = currentRot.Pitch + (deltaPitch * smoothFactor)
            finalYaw = currentRot.Yaw + (deltaYaw * smoothFactor)
        end
        
        -- RECOIL COMPRESSION (AUTO distance curve): paas me halka, door auto zyada.
        -- slider = master strength (1-8), distance curve automatic.
        local rcVal = _G.AimbotConfig.LongRangeRecoil or 8
        if rcVal > 0 and IsPlayerFiring(player) and Valid(bestTarget) then
            local rDistM = 0
            pcall(function() rDistM = player:GetDistanceTo(bestTarget) / 100.0 end)
            if not rDistM or rDistM < 0 then rDistM = 0 end
            local rScale = 0.3 + math.min(rDistM / 100.0, 2.7)
            finalPitch = finalPitch - ((rcVal / 8.0) * 1.5 * rScale)
        end
        
        pc:SetControlRotation({ Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }, "ShAimbot")
    end

    -- Aimbot driver (time_ticker self-loop, match-proof)
    _G._aimbotGen = 0
    _G.StartAimbotLoop = function()
        _G._aimbotGen = (_G._aimbotGen or 0) + 1
        local gen = _G._aimbotGen
        pcall(function()
            local function AimbotTick()
                if gen ~= _G._aimbotGen then return end
                pcall(function()
                    local tt = require("common.time_ticker")
                    if tt and tt.AddTimerOnce then tt.AddTimerOnce(0.07, AimbotTick) end
                end)
                local _mc = _G.MemoryConfig
                local _needMem = _mc and (_mc.IpadView or _mc.SmallScope or _mc.SmallCrosshair)
                local _needRestore = _mc and (_mc._IpadWasActive or _mc._SmallScopeWasActive or _mc._CrosshairWasActive)
                if (_G.AimbotConfig and _G.AimbotConfig.Enable) or _needMem or _needRestore then pcall(ProcessAimbotFrame) end
                -- NO RECOIL (shake ON): dead code nahi, har tick weapon entity pe apply
                if _G.LexusConfig and _G.LexusConfig.NoRecoilEnabled and _G.ApplyNoRecoil then
                    pcall(_G.ApplyNoRecoil)
                end
            end
            local tt0 = nil
            pcall(function() tt0 = require("common.time_ticker") end)
            if tt0 and tt0.AddTimerOnce then
                tt0.AddTimerOnce(0.07, AimbotTick)
                _G._aimbotTimer = true
            elseif _G.Game and _G.Game.AddGameTimer then
                _G._aimbotTimer = _G.Game:AddGameTimer(0.07, true, AimbotTick)
            elseif slua_GameFrontendHUD then
                local pc = slua_GameFrontendHUD:GetPlayerController()
                if Valid(pc) and type(pc.AddGameTimer) == "function" then
                    _G._aimbotTimer = pc:AddGameTimer(0.07, true, AimbotTick)
                end
            end
        end)
    end
    pcall(function() if _G.StartAimbotLoop then _G.StartAimbotLoop() end end)




    -- ============================================================
    -- CHAMS (ENGINE DYEING) - PORTED FROM LEXUS / help.lua (WORKING)
    -- ============================================================
    _G.BRChamsConfig = _G.BRChamsConfig or {
        Enable = true,
        VisColor = 3,   -- 1=Red 2=Blue 3=Green 4=Yellow 5=Orange 6=Pink
        OccColor = 1,   -- 1=Red 2=Blue 3=Green 4=Yellow 5=Orange 6=Pink
    }

    local _chams_LC = nil
    local function _chamsGetLC()
        if _chams_LC == nil then _chams_LC = import("LinearColor") or _G.FLinearColor end
        return _chams_LC
    end
    local _chams_SK = nil
    local function _chamsGetSK()
        if _chams_SK == nil then _chams_SK = import("SkeletalMeshComponent") end
        return _chams_SK
    end

    local function ChamsGetColors(isBot)
        local vi = _G.BRChamsConfig.VisColor or 3
        local oc = _G.BRChamsConfig.OccColor or 1
        local LC = _chamsGetLC()
        local mk = function(r, g, b, a) return (LC and LC(r, g, b, a)) or {R=r, G=g, B=b, A=a} end
        local P = {
            [1] = mk(100, 0, 0, 1),
            [2] = mk(0, 40, 100, 1),
            [3] = mk(0, 100, 0, 1),
            [4] = mk(100, 100, 0, 1),
            [5] = mk(100, 50, 0, 1),
            [6] = mk(100, 0, 60, 1),
        }
        local vis = P[vi] or P[3]
        local occ = P[oc] or P[1]
        return vis, occ
    end

    local function ChamsGetMeshes(enemy)
        local meshes = {}
        if Valid(enemy.Mesh) then table.insert(meshes, enemy.Mesh) end
        pcall(function()
            local SK = _chamsGetSK()
            if SK and type(enemy.GetComponentsByClass) == "function" then
                local childs = enemy:GetComponentsByClass(SK)
                if childs then
                    local count = type(childs.Num) == "function" and childs:Num() or #childs
                    for i = 1, count do
                        local comp = type(childs.Get) == "function" and childs:Get(i - 1) or childs[i]
                        if Valid(comp) and comp ~= enemy.Mesh then table.insert(meshes, comp) end
                    end
                end
            end
        end)
        pcall(function()
            local w = enemy:GetCurrentWeapon()
            if Valid(w) and Valid(w.Mesh) then table.insert(meshes, w.Mesh) end
        end)
        return meshes
    end

    local _chamsConsoleReady = false
    local function ChamsEnableConsole()
        if _chamsConsoleReady then return end
        pcall(function()
            local KSL = import("KismetSystemLibrary")
            local world = slua.getWorld()
            if KSL and world then
                KSL.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
                KSL.ExecuteConsoleCommand(world, "r.CustomDepth 3")
                KSL.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
                KSL.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
                _chamsConsoleReady = true
            end
        end)
    end

    local function ApplyChams(enemy)
        if not Valid(enemy) then return end
        pcall(function()
            ChamsEnableConsole()
            local isBot = false
            pcall(function()
                if enemy.bIsAI == true or enemy.IsAI == true then isBot = true end
                local ps = enemy.PlayerState or (type(enemy.GetPlayerState) == "function" and enemy:GetPlayerState())
                if Valid(ps) and (ps.bIsABot == true or ps.bIsBot == true) then isBot = true end
            end)
            local meshes = ChamsGetMeshes(enemy)
            local visColor, occColor = ChamsGetColors(isBot)
            for _, mesh in ipairs(meshes) do
                if Valid(mesh) then
                    pcall(function()
                        if type(mesh.SetDrawDyeing) == "function" then
                            mesh:SetDrawDyeing(true)
                            mesh:SetDrawDyeingMode(1)
                            mesh:SetVisibleDyeingColor(visColor)
                            mesh:SetOccludedDyeingColor(occColor)
                            mesh:SetDyeingColorFadeDistance(99999.0)
                            mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
                            mesh:SetDrawHighlight(true)
                            mesh:OverrideHighlightColor(visColor)
                            mesh:SetHighlightCanBeOccluded(false)
                            mesh:SetDrawIdeaOutline(true)
                            mesh:SetIdeaOutlineNew(true)
                            mesh:SetIdeaOutlineOcclusionHighlight(true)
                            mesh:OverrideIdeaOutlineColor(visColor)
                            mesh:SetIdeaOutlineOcclusionColor(occColor)
                            mesh:OverrideIdeaOutlineThickness(20.0)
                            mesh:SetIdeaOverrideOutlineAndOcclusion(true)
                            mesh:SetRenderCustomDepth(true)
                            mesh:SetCustomDepthStencilValue(255)
                        end
                    end)
                end
            end
        end)
    end

    local function UndoChams(enemy)
        if not Valid(enemy) then return end
        pcall(function()
            local meshes = ChamsGetMeshes(enemy)
            for _, mesh in ipairs(meshes) do
                if Valid(mesh) then
                    pcall(function()
                        if type(mesh.SetDrawDyeing) == "function" then
                            mesh:SetDrawDyeing(false)
                            mesh:SetDrawHighlight(false)
                            mesh:SetDrawIdeaOutline(false)
                            mesh:SetRenderCustomDepth(false)
                        end
                    end)
                end
            end
        end)
    end

    _G._chamsTimer = _G._chamsTimer or nil
    -- OPTIMIZE: already-colored enemy ko har 0.3s dobara paint mat karo (5s skip)
    _G._SH_ChamsDone = _G._SH_ChamsDone or {}
    local function ChamsTick()
        if not _G.BRChamsConfig or not _G.BRChamsConfig.Enable then return end
        pcall(function()
            local GDP = GameplayData
            if not GDP then return end
            local all = GetRawPawnList()
            if not all or #all == 0 then
                all = (GDP.GetAllPlayerCharacters and GDP.GetAllPlayerCharacters()) or {}
            end
            local localChar = nil
            pcall(function() localChar = GDP.GetLocalCharacter and GDP.GetLocalCharacter() end)
            local myTeam = nil
            if Valid(localChar) and type(localChar.GetTeamID) == "function" then
                myTeam = localChar:GetTeamID()
            end
            local now = os.clock()
            for _, enemy in pairs(all) do
                if Valid(enemy) and enemy ~= localChar then
                    local isEnemy = true
                    if myTeam and type(enemy.GetTeamID) == "function" then
                        isEnemy = enemy:GetTeamID() ~= myTeam
                    end
                    if isEnemy then
                        if _G.BRChamsConfig.Enable then
                            local ck = nil
                            pcall(function() ck = tostring(enemy.PlayerKey or "") end)
                            if ck and ck ~= "" and _G._SH_ChamsDone[ck] and (now - _G._SH_ChamsDone[ck]) < 5 then
                                -- skip, already painted
                            else
                                ApplyChams(enemy)
                                if ck and ck ~= "" then _G._SH_ChamsDone[ck] = now end
                            end
                        else UndoChams(enemy) end
                    end
                end
            end
        end)
    end

    _G.BRStartChams = function()
        ChamsEnableConsole()
        if _G._chamsTimer then return end
        pcall(function()
            if _G.Game and _G.Game.AddGameTimer then
                _G._chamsTimer = _G.Game:AddGameTimer(0.3, true, ChamsTick)
            elseif slua_GameFrontendHUD then
                local pc = slua_GameFrontendHUD:GetPlayerController()
                if Valid(pc) and type(pc.AddGameTimer) == "function" then
                    _G._chamsTimer = pc:AddGameTimer(0.3, true, ChamsTick)
                end
            end
        end)
    end

    _G.BRStopChams = function()
        if _G._chamsTimer then
            pcall(function() if _G.Game then _G.Game:RemoveGameTimer(_G._chamsTimer) end end)
            _G._chamsTimer = nil
        end
        pcall(function()
            local GDP = GameplayData
            if not GDP then return end
            local all = (GDP.GetAllPlayerCharacters and GDP.GetAllPlayerCharacters()) or {}
            for _, enemy in pairs(all) do UndoChams(enemy) end
        end)
    end

    -- ============================================================
    -- PBC WALLHACK (PORTED FROM bb.lua) - ENGINE DYEING + AVATAR SLOTS
    -- ============================================================
    _G.PBCWallhackConfig = _G.PBCWallhackConfig or {}
    -- [USER REQUEST] wallhack: sirf ON/OFF. Colors FIXED —
    -- wall ke BAHAR = GREEN (1), wall ke PEECHE = RED (4)
    _G.PBCWallhackConfig.VisColor = 1
    _G.PBCWallhackConfig.OccColor = 4
    -- [USER REQUEST] sirf ek ESP (V3) + Wallhack — Blue Frame / Chams force OFF
    if _G.BlueFrameConfig then _G.BlueFrameConfig.Enable = false end
    if _G.BRChamsConfig then _G.BRChamsConfig.Enable = false end
    -- [USER REQUEST] wallhack ON/OFF toggle se chalta hai; colors FIXED
    if _G.PBCWallhackConfig then
        _G.PBCWallhackConfig.VisColor = 1   -- bahar GREEN
        _G.PBCWallhackConfig.OccColor = 4   -- peeche RED
    end
    if _G.PBCWallhackConfig.Enable == nil then _G.PBCWallhackConfig.Enable = false end

    local _pbc_LC = nil
    local function _pbcGetLC()
        if _pbc_LC == nil then _pbc_LC = import("LinearColor") or _G.FLinearColor end
        return _pbc_LC
    end

    local _pbc_AVATAR_SLOTS = {0,1,2,3,4,5,6,7}
    _G.PBC_PROCESSED_PAWNS = _G.PBC_PROCESSED_PAWNS or {}

    local _pbc_colorData = {
        [1]={R=0,G=2,B=0,A=0},
        [2]={R=3,G=5,B=0,A=5},
        [3]={R=4,G=1,B=0,A=5},
        [4]={R=2,G=0,B=0,A=2},
        [5]={R=2,G=4,B=18,A=5},
        [6]={R=2,G=2,B=2,A=2},
        [7]={R=0,G=3,B=3,A=3},
    }
    local _pbc_COLOR_PALETTE = {}
    for i,d in pairs(_pbc_colorData) do
        local LC = _pbcGetLC()
        _pbc_COLOR_PALETTE[i] = LC and LC(d.R, d.G, d.B, d.A) or {R=d.R, G=d.G, B=d.B, A=d.A}
    end

    local _pbcConsoleReady = false
    local function PBCSetupConsole()
        if _pbcConsoleReady then return end
        pcall(function()
            local K = import("KismetSystemLibrary")
            local w = slua.getWorld()
            if K and w then
                K.ExecuteConsoleCommand(w, "r.EnableDrawDyeingColor 1")
                K.ExecuteConsoleCommand(w, "r.CustomDepth 3")
                K.ExecuteConsoleCommand(w, "r.IdeaOutline.Enable 1")
                K.ExecuteConsoleCommand(w, "r.Highlight.Enable 1")
            end
            _pbcConsoleReady = true
        end)
    end

    local function PBCApplyToMesh(m, vc, oc)
        if not m or not slua.isValid(m) then return end
        pcall(function()
            m:SetDrawDyeing(true)
            m:SetDrawDyeingMode(1)
            m:SetVisibleDyeingColor(vc)
            m:SetOccludedDyeingColor(oc)
            m:SetDyeingColorFadeDistance(99999.0)
            m:SetDyeingColorMinMaxDistance(0.0, 99999.0)
            m:SetDrawHighlight(true)
            m:OverrideHighlightColor(vc)
            m:SetHighlightCanBeOccluded(false)
            m:SetDrawIdeaOutline(true)
            m:SetIdeaOutlineNew(true)
            m:SetIdeaOutlineOcclusionHighlight(true)
            m:OverrideIdeaOutlineColor(vc)
            m:SetIdeaOutlineOcclusionColor(oc)
            m:OverrideIdeaOutlineThickness(20.0)
            m:SetIdeaOverrideOutlineAndOcclusion(true)
            m:SetRenderCustomDepth(true)
            m:SetCustomDepthStencilValue(255)
        end)
    end

    local function PBCGetColorFromIndex(i)
        return _pbc_COLOR_PALETTE[i] or _pbc_COLOR_PALETTE[1]
    end

    -- FIX: timer handle global rakho taaki next match me dead timer clear karke restart ho sake
    _G._pbc_WH_TIMER = _G._pbc_WH_TIMER or nil
    local _pbc_WH_TIMER = _G._pbc_WH_TIMER
    local function _pbc_SetTimer(h) _pbc_WH_TIMER = h; _G._pbc_WH_TIMER = h end
    local function PBCTick()
        if not _G.PBCWallhackConfig or not _G.PBCWallhackConfig.Enable then return end
        pcall(function()
            local lp = GameplayData.GetPlayerCharacter()
            if not slua.isValid(lp) then return end
            PBCSetupConsole()
            _G.PBC_TICK = (_G.PBC_TICK or 0) + 1
            if _G.PBC_TICK % 6 == 0 then _G.PBC_PROCESSED_PAWNS = {} end
            local mt = lp.TeamID or 0
            local all = Game:GetAllPlayerPawns() or {}
            local pc = 0
            for _,p in pairs(all) do
                if pc >= 20 then break end
                if not slua.isValid(p) or p == lp then goto pbc_cont end
                if p.PlayerKey and _G.PBC_PROCESSED_PAWNS[p.PlayerKey] then goto pbc_cont end
                local alive = false
                pcall(function() if p.Health and p.Health > 0 then alive = true end end)
                if alive and p.TeamID and p.TeamID ~= mt then
                    local vc = PBCGetColorFromIndex(_G.PBCWallhackConfig.VisColor or 1)
                    local oc = PBCGetColorFromIndex(_G.PBCWallhackConfig.OccColor or 3)
                    pcall(function()
                        if slua.isValid(p.Mesh) then PBCApplyToMesh(p.Mesh, vc, oc) end
                        local a = p.CharacterAvatarComp2_BP or (type(p.getAvatarComponent2) == "function" and p:getAvatarComponent2())
                        if a and a.GetMeshCompBySlot then
                            for _,s in ipairs(_pbc_AVATAR_SLOTS) do
                                local m = a:GetMeshCompBySlot(s)
                                if slua.isValid(m) then PBCApplyToMesh(m, vc, oc) end
                            end
                        end
                    end)
                    if p.PlayerKey then _G.PBC_PROCESSED_PAWNS[p.PlayerKey] = true end
                    pc = pc + 1
                end
                ::pbc_cont::
            end
        end)
    end

    _G.PBCStartWallhack = function()
        if _pbc_WH_TIMER or _G._pbc_WH_TIMER then return end
        if not _G.PBCWallhackConfig or not _G.PBCWallhackConfig.Enable then return end
        PBCSetupConsole()
        if _G.Game and _G.Game.AddGameTimer then
            _pbc_SetTimer(_G.Game:AddGameTimer(0.3, true, PBCTick))
        else
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if slua.isValid(pc) and pc.AddGameTimer then
                _pbc_SetTimer(pc:AddGameTimer(0.3, true, PBCTick))
            end
        end
    end

    _G.PBCStopWallhack = function()
        if _pbc_WH_TIMER or _G._pbc_WH_TIMER then
            pcall(function() if _G.Game then _G.Game:RemoveGameTimer(_pbc_WH_TIMER or _G._pbc_WH_TIMER) end end)
            _pbc_SetTimer(nil)
        end
        _G.PBC_PROCESSED_PAWNS = {}
    end

    -- ============================================================
    -- BLUE FRAME ESP (Native Game Method - REAL BLUE FRAME)
    -- Uses Replay_CreateEnemyFrameUI / Replay_SetVisiableOfFrameUI
    -- ============================================================
    _G.BlueFrameConfig = _G.BlueFrameConfig or { Enable = false }
    _G._bf_Timer = _G._bf_Timer or nil
    local _bf_Timer = _G._bf_Timer
    local function _bf_SetTimer(h) _bf_Timer = h; _G._bf_Timer = h end

    local function _bf_DrawFrame()
        pcall(function()
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if not slua.isValid(pc) then return end
            local localChar = pc:GetPlayerCharacterSafety()
            if not slua.isValid(localChar) then return end
            local allChars = Game:GetAllPlayerPawns() or {}
            local localTeam = localChar.TeamID or 0
            for _, enemy in pairs(allChars) do
                if slua.isValid(enemy) and enemy ~= localChar and enemy.TeamID ~= localTeam then
                    local isAlive = true
                    pcall(function()
                        if enemy.HealthStatus then
                            local ECharHPStatus = import("ECharacterHealthStatus")
                            isAlive = (enemy.HealthStatus ~= ECharHPStatus.FinishedLastBreath)
                        end
                    end)
                    if isAlive then
                        pcall(function()
                            if enemy.Replay_IsEnemyFrameUIExisted and not enemy:Replay_IsEnemyFrameUIExisted() then
                                enemy:Replay_CreateEnemyFrameUI(true, true)
                            end
                            if enemy.Replay_SetVisiableOfFrameUI then
                                enemy:Replay_SetVisiableOfFrameUI(true)
                            end
                        end)
                    else
                        pcall(function()
                            if enemy.Replay_SetVisiableOfFrameUI then
                                enemy:Replay_SetVisiableOfFrameUI(false)
                            end
                        end)
                    end
                end
            end
        end)
    end

    _G.BlueFrameStart = function()
        if _bf_Timer or _G._bf_Timer then return end
        if not _G.BlueFrameConfig or not _G.BlueFrameConfig.Enable then return end
        if _G.Game and _G.Game.AddGameTimer then
            _bf_SetTimer(_G.Game:AddGameTimer(0.3, true, _bf_DrawFrame))
        else
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if pc and slua.isValid(pc) and pc.AddGameTimer then
                _bf_SetTimer(pc:AddGameTimer(0.3, true, _bf_DrawFrame))
            end
        end
    end

    _G.BlueFrameStop = function()
        if _bf_Timer or _G._bf_Timer then
            pcall(function() if _G.Game then _G.Game:RemoveGameTimer(_bf_Timer or _G._bf_Timer) end end)
            _bf_SetTimer(nil)
        end
        pcall(function()
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if slua.isValid(pc) then
                local localChar = pc:GetPlayerCharacterSafety()
                if slua.isValid(localChar) then
                    local allChars = Game:GetAllPlayerPawns() or {}
                    local localTeam = localChar.TeamID or 0
                    for _, enemy in pairs(allChars) do
                        if slua.isValid(enemy) and enemy ~= localChar and enemy.TeamID ~= localTeam then
                            pcall(function()
                                if enemy.Replay_SetVisiableOfFrameUI then
                                    enemy:Replay_SetVisiableOfFrameUI(false)
                                end
                            end)
                        end
                    end
                end
            end
        end)
    end

    -- FAKE HWID (ANTI-BAN) - PORTED FROM LEXUS / help.lua
    -- ============================================================
    _G.BRFakeHWID = _G.BRFakeHWID or { Enable = false }  -- SLIM BYPASS: default OFF (toggle se ON karo)

    local function BRFakeHWID_Notify(msg)
        local s = "[BR] " .. tostring(msg)
        pcall(function() print(s) end)
        pcall(function()
            local sh = import("ScriptHelperClient")
            if sh and sh.AddOnScreenDebugMessage then
                sh.AddOnScreenDebugMessage(s, -1, 3.0, {R=1, G=1, B=0, A=1}, {X=1.2, Y=1.2})
            end
        end)
    end

    _G.GetOriginalHWID = function()
        if _G.Original_GetDeviceId then return tostring(_G.Original_GetDeviceId()) end
        local SystemLib = import("KismetSystemLibrary")
        if SystemLib and type(SystemLib.GetDeviceId) == "function" then return tostring(SystemLib.GetDeviceId()) end
        return "UNKNOWN_DEVICE"
    end

    local function InitFakeHWID()
        pcall(function()
            local SystemLib = import("KismetSystemLibrary")
            if SystemLib and not _G.FakeHWID_Hooked then
                _G.Original_GetDeviceId = SystemLib.GetDeviceId
                SystemLib.GetDeviceId = function(...)
                    if _G.BRFakeHWID.Enable then
                        if not _G.FakeHWID_String then
                            local chars = "0123456789ABCDEF"
                            local hwid = ""
                            for i = 1, 32 do
                                local idx = math.random(1, #chars)
                                hwid = hwid .. chars:sub(idx, idx)
                                if i == 8 or i == 12 or i == 16 or i == 20 then hwid = hwid .. "-" end
                            end
                            _G.FakeHWID_String = hwid
                        end
                        return _G.FakeHWID_String
                    end
                    if _G.Original_GetDeviceId then return _G.Original_GetDeviceId(...) end
                    return "UNKNOWN"
                end
                _G.FakeHWID_Hooked = true
                BRFakeHWID_Notify("Fake HWID Hook Active")
            end
        end)
    end

    InitFakeHWID()

    -- ============================================================
_G.LexusConfig = _G.LexusConfig or {
    FakeHWID = false,
    EspLoai5 = false, EspLoai6 = false, EspLoai7 = false, EspLoai9 = false,
    Esp7_SoLuong = true, Esp7_VuKhi = true, Esp7_TuThe = true,
    Esp9_Count = true, Esp9_Name = true, Esp9_HP = true, Esp9_Team = true,
    Esp9_Weapon = true, Esp9_Distance = true, Esp9_Line = true, Esp9_Skeleton = true,
    EspAntenna = false, EspOutline = false, OutlineThickness = 10,
    Esp3ShowName = true, Esp3ShowHP = true,
    ColorBodyNew = false, ChamsColorVis = 3, ChamsColorOcc = 1,
    WeaponGlow = false,
    CustomAimbot = false, CustomAimbotClose = false, CustomMagicBullet = false,
    CustomHRecoil = false, CustomVRecoil = false,
    LessShake = false, Accuracy = false, Crosshair = false, AutoHead = false, GodMode = false,
    NoRecoilEnabled = true, RecoilReduction = 100, WeaponAimbot = false,
    AimTouchEnable = false,
    AimTouchHipfire = false, AimTouchHipIgKnock = false, AimTouchHipIgBot = false, AimTouchHipVisCheck = false,
    AimTouchSG = false, AimTouchSGAutoFire = false, AimTouchSGIgKnock = false, AimTouchSGIgBot = false, AimTouchSGVisCheck = false,
    AimTouchScopeAll = false, AimTouchScopeIgKnock = false, AimTouchScopeIgBot = false, AimTouchScopeVisCheck = false,
    AimTouchScopeSniper = false, AimTouchSniperIgKnock = false, AimTouchSniperIgBot = false, AimTouchSniperVisCheck = false,
    AimTouchMortar = false,
    IpadView = false, UnlockFPS = false,
    SmallScope = false, SmallScopeFOV = 75,
    BugManEnable = false, FastCar = false, FastCarSpeed = 3000,
    WallVehicle = false, WhiteBody = false, BlackSky = false,
    RemoveFog = false, RemoveGrass = false, RemoveTrees = false,
    ModEmote = false, ModSkin = false, SkinDeadBox = false, SkinAttachment = false,
    KillMessage = false, KillCountUI = false, SkinOpenLink = false,
    EspV3_Master = true, EspV3_Count = true, EspV3_Box = true, EspV3_Line = true, EspV3_Health = true,
    EspV3_Name = true, EspV3_Dist = true, EspV3_Weapon = true, EspV3_Flag = false, EspV3_State = true,   -- [USER REQUEST] country flag OFF
}

_G.LexusState = _G.LexusState or {
    LoopToken = 0, NativeESPReady = false, MenuStep = 0, GraphicsUnlocked = false,
    TrackedMarks = {}, EnemyMarks = {}, CustomTextData = nil,
    PrevGraphicsState = {}, LastMagicConfigHash = "",
}

-- ════════════════════════════════════════════════════
-- ICON LOADER — COMPLETE FIX (v2)
-- Fixes: multi-pkg path, base64 decode, 4-layer fallback,
--        retry cap, debug logging
-- ════════════════════════════════════════════════════

-- [ICON-FIX] Multi-package save-path detector (all PUBG variants)
local function _SH_GetSavePaksDir()
    if _G._SH_SaveDir then return _G._SH_SaveDir end
    local packages = {
        "com.tencent.ig",
        "com.rekoo.pubgm",
        "com.pubg.krmobile",
        "com.vng.pubgmobile",
        "com.pubg.imobile",
        "com.tencent.tmgp.pubgmhd",
    }
    local suffixes = {
        "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/",
        "/files/",
    }
    for _, pkg in ipairs(packages) do
        for _, sfx in ipairs(suffixes) do
            local dir = "/storage/emulated/0/Android/data/" .. pkg .. sfx
            local test = io.open(dir .. ".wtest", "w")
            if test then
                test:close()
                os.remove(dir .. ".wtest")
                _G._SH_SaveDir = dir
                if _G.SH_Dbg then _G.SH_Dbg("ICON save-dir=" .. dir) end
                return dir
            end
        end
    end
    _G._SH_SaveDir = "/storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/"
    if _G.SH_Dbg then _G.SH_Dbg("ICON save-dir=FALLBACK") end
    return _G._SH_SaveDir
end
_SH_GetSavePaksDir()

    -- ============================================================
    -- ESP V3: snaplines + name + player/bot counter (icons: victortipvala-sys/esp-icons)
    -- ============================================================
    _G.LexusConfig = _G.LexusConfig or {}
    -- [USER REQUEST] SAB features DEFAULT OFF — user ON karega tab chalega
    _G.LexusConfig.EspV3_Master = false
    for _, _ek in ipairs({"EspV3_Count","EspV3_Box","EspV3_Line","EspV3_Health","EspV3_Name","EspV3_Dist","EspV3_Weapon","EspV3_State"}) do
        _G.LexusConfig[_ek] = false
    end
    _G.LexusConfig.EspV3_Flag = false
    pcall(function() local _f0 = io.open("/storage/emulated/0/Android/data/com.pubg.imobile/files/espv3_dbg.txt", "w") if _f0 then _f0:write("boot" .. string.char(10)) _f0:close() end end)
    _G.SH_Dbg = function(m) pcall(function() local f = io.open("/storage/emulated/0/Android/data/com.pubg.imobile/files/espv3_dbg.txt", "a") if f then f:write(tostring(m) .. string.char(10)) f:close() end end) end
    -- [ICON-FIX] Embedded base64 icons — CORRECT decoder + correct write path
    pcall(function()
        local dir = _G._SH_SaveDir or _SH_GetSavePaksDir()
        if _G.SH_Dbg then _G.SH_Dbg("ICON base64 write-dir=" .. dir) end
        local function _need(p)
            local f = io.open(p, "r")
            if f then f:close() return false end
            return true
        end
        -- [ICON-FIX] Correct base64 decoder (4 chars -> 3 bytes)
        local function _b64d(data)
            local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
            data = string.gsub(data, '[^' .. b .. '=]', '')
            return (data:gsub('.', function(x)
                if x == '=' then return '' end
                local r, f = '', (b:find(x, 1, true) or 0) - 1
                for i = 6, 1, -1 do
                    r = r .. (f % 2^i - f % 2^(i-1) > 0 and '1' or '0')
                end
                return r
            end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
                if #x ~= 8 then return '' end
                local cc = 0
                for i = 1, 8 do
                    cc = cc + (x:sub(i, i) == '1' and 2^(8 - i) or 0)
                end
                return string.char(cc)
            end))
        end
        -- [ICON-FIX] Embedded base64 strings — unchanged
        local _icons = { {"ic_danger_enemy.png", [[iVBORw0KGgoAAAANSUhEUgAAAIAAAABACAYAAADS1n9/AAAMG0lEQVR42u2deXAUVR7HP6+nZ5LJ5L5mMgkTCEfCEYKcBjbhUlAUOcRVwFJ0LXZ1BTGiCAkW4MUNWmgJurIetZRaJbVatRSCIOFaWQiKIKcJRwhJCBASkkCO6f0jN2RyzPRMQjK/qqk+5r3+dffv+37v9/u+7n4CJ8l6MxYBKUIwQwi0Aqj7k0T9bXHbtmRjf/U+iSbq19mm+nj2HquRuvXO1UY5qZG6al2rnXJeVtvwi0AymUlBsADwoA2IwC22RFUAfGghQKngSwXGCVcaVLgN3uoAWB1BoFLOXiGIcbfYu8e7SWqcxPvd8NBZ2QzNM75wW1g1b0dbAIAo5gMg0d2CW95CW/teOQyA98wMBZ51G/juFIcAoIAQgrXtudG3d2/mEADWmXgAhUFuA3dUDyB4wm3QDpoGbuyMZ0EpE4WLDVidQUgennh36YHW24fijFOUXb3stqYrAVBYQj80+LqyhUo6DyyPPkXExOkEDU6sl0/ezM4k+7tNZH31CSUZp9pH/CGc7+3s7gIUie6O5K3elig6T5jabH2m+8YzavvvxL27gaAhw++4O56mCDrPfJX4rUfpvmAlGi+DO/5wKgAE3RxR3O3xZ4lf+SkaT32TZaNnpXDvJ99hsEQ1fVNlLZbnXqH/v35CF2x0xyNqAmA9aFebeHVNGL+gsMARxVm7tqLx8CR0SGKj5XrOWUSvV95s8fF9Ygdyz6ZdyD5+zotHOlIWsCKMJwvNHEewHIjDwXGEy2n7KSu8TljiGIQso/P1v6OMcfhYYmYvtFuHV1Q00Uv/4c4YGhFNUwUW9UY3TuIbIVggILCxcekG99kog9VKcL/BdBo7kZ7PJaH19SM79YfaMW5ZJuGzLegCgmx3Q1YrRWeOowsKsVnG0K0Xhb8e4Oa5M80737a0rwX17JTrTXoAr6tsRDDJGei7lPoDOv9ALh/cy8Vt39X7zzJxOobIro3Wz/3xe46/ldSknshZC91N3Z4uYIWRLorCVGcpz9q1FYCL278n9+fUei6503jbHJO1rJQDMx7k0F8nkZe6lR0DQ8lP22+zvO898XiGR7YrwwlXAKBcENkSXS3NWwNjB1BeUowpccwd+X5II8GhpNXRa+EaUBQAwiZMw79/fKO6/f90f9s2YCs91NJ4IKdwvu6ZqH1SQ1dtRNZ7YRo2GiFJYLVWdjthEWj0Xo1Xtlrx7hqDX+yA5gWEXXq4U8CWAmB+DunLTBwEBjpDeUHGKQL79McjMJiAPv3JP3IQoNHAr4b4CYsgYetvCI1M2fVrTV+of1CHNLDDaaACK5ylPHvvjpr1sKpuQBcQRFzyyqYN6u2L0FTiV+sX0GT54DGTCBr9SIczsMMAmJfNN8AhpwBgXy0ATAmVAOiTtJjgwQnquzq/AKJXfYFU1bW4OYDmxACVN0pZamW2RsMete9b7oHdWMvLkGQtwQPikQ3eeEfWZ5hv5eWQ89OWO4wmbCxr1gX4D0pAb6lNJTXevuiCQrmVedZt+eYSQQDbi7gwxoduAvqqRVwIQCkrxTx8LAazBaHRcOXQfkqvXiZs5IMAFP5xgt3TRqPReaJUlFNekE9ZQf6dy8LaX0XVsjQnizNvvYxX5+54RUUDUHTyNzI3LEMoyl1N+kgqEkHNpnOtEvMlK5MBLzWDpku7txEycFhlN5A4hsOLXgKrlcC4QRxdPp+4hauJGG/fcyemCdM59vcpFKTtQx/RmfPr3qzJNDpCjq+6rlUmFgrBEjVfn9L5+DF+x+/ojWYK00+yZWQMAvDwCyD+482EDBnu0AWWF+RzfM40ru3aou7rWNj/upgzXhWzU863aDRQyHxQmRioJ9EzXkRvNAPgExWNl9lS2Td5GRw2PoDs64/foASXtpq7KcBsEQCSMrkKFKmlvNPYifR9ZUl9t12VDpZcyqQw/aQqevL3/agqS9eh0kBniX9MLMPWflHJANYRYx1aOP3LjxzWU5xximv7d3TIHN9ZALihhmK/qGhkg/cd+43VtDCQsWkDRefTHdKTsWJ+zZiBW9QBwCVVOICDe2vWlYqKmnWdfyABfSuZ54qSYg7NnYG19JZ9RNPmz7m89Vu3lVUGwG41gqaS3EvcqGrdR5YnU5he+ySvMaG2G8g7sJv/zZraYhDkbf83J+b9pd0ZTO3uq0kiaHk4/UYZ8HzYG//JvpQKiX1WeFCAsblpi619QX0HUph+irRFc/Dv2ZfAqpE9SdZy9puNNeWK/jhBzs7/EDxkOLrA4Mb5itJbpK9+g9NLZoO1wnkkjZ3Hc/RrI2o/EdQ0FWyliywx1Grlxg0rICEkO8mg2yX9639y5ZefK939zZKa/b49eiMkCd/uPTHfP4EzHy3j+tE0do7pQ8QjU+k05WkCByciaXW1wd65M+Ru3cyFjWspzclCCAgYlIB3TF+yvvig9VqoaEceZXUE+qRMStaYmCskVqhJqgxY/B49nplNcdZ59jzzMMaho+iVtBjZy5u8/TtJmzuDW9kXa+pqtDr05k5oDT6UZmdSdi2v9ngaDRFPvkD35FVYy8ooOLiHk68+TVletn3f9GmIpLGjrjO/N2QvEWSz6rJwIpQKXhJgkQRdhKCHUPATgutCQQiBr9oAMI8cx87HR9BrVgpRTzzH4ZTnkQ0+xCavRCkrJeOzdZzbtIHis6cbvCmyl4HQ+ybQZdZCDF1jyD+Qytm1b9AteTWyXyBHZ4zh1m117Wbp2gkAbHYBJRfJ8jQiI5gMyDX8n4KfM1zRzSu5pM4YR7+UVZhGPICQZSQPTyStFiFJCA9Pus6cS9eZcynKOMW1w/+lNC+HiuIi9OZO6M0WAgYnIulqv0ul8TJQXliANtiIbPAh7qs9HH1yFCWnj7nD/+Z2AcvNDMNKVyEIlxTihCBegEVtXl2SNcS9vhRj/EgOLfgbsa+9gzFBnef4ygvyOfHydHz7DcE46SmOPDqE8iu5bg/Q1FjAUhPPK1b2CMGnQiEeWJ90iUgF5qiNwMhHphIzcy5e4ZFoDT54BKj3CJfs64+H2YLsH4hHRGdiPvwWJKn9tVa1j7nMxBRggSToKqjp89MEpArBnOZ4gOa0KH2IiYd2/I6uGY92qSVn304ie+OaNuUBHBmBdIoHUCSyBWwDDlM7CNSfOh5ADVQOWLTWpcYHsCS9iUfVyKNqrUm4vgU77B1v3/E1aP4w8gyCZKx0dvYJ+PXoTaeHHnM9Bao3YJ75GmcXv9iqLrhNUcErjBjOmNiuCD4G5xsfoNcL8+4YEXSVhEx5Fm1QaLs2cIsAUArvKjDCVcq13j5EPvzn1rt4Tz1B46d16DSwHgAUSHCl8vBRD9XL21tDAsdOdgOgDgL2uRoArS3e9wxFdnEA2mYBUF7OfASnXZW3Bsb2b/3cWqPBKyauzef4zopP5CVGXlcgVCPIRiFV0TBSlPMZMNqZUbHGwxNfF7+waUv00X0p/Pmnu47EUQUACrwj4JyiECLAIMopQuE0gnKh8nwCdcUz2IiQ5TZxE3SmcIcterdmEJKAH4FIoPq7agYE/XCi8aszgLYiGoNPh/ggVMMeQLBfUggGegE6VykuvX6NI2sW2XzHry7F2WiZqhWb/1VvC9vHKTnxa4cNAsXbwYRVaDhRw/W3kbdnmuLlm1sXXDRxE607sZSdcl5KzuMSCrPaHDJxi8vSwDdy+VzAOreB26ibdgUPkJLDLOAloLwt561uAzuRCErJ4X2sjAMK3AZs+ySO6gAASM5lm2IlAYWLbtO2f2/W4Dhsci5HhMy9QJrbwB0gCGxI5l0ks8STYSisAcruKoO6ZxJVF/xLA/CT9cRKChYEFqFgkQQWQc3Pz5V5tZoTR7eJyZ9x/HUxe3kAVRrH+ij8SkuxaBQsKIRqKh8bDxUQXLW0CAiuJpucMHP4GaHwZbU7k6R6rq2bBI8Kgb7qYt+WFMqkKmRUHWuEgOGichq8lgAgX0CmBJkILmiojJuk29yrdPs+qZH/6i6lRv6rU8YBue5S7/h1b3RFRZhlBTMKBgFmAR4ShCngKYFJgJekECoEBiEIqbrh4YKqKegbBsChBzJsf8304AC0hVcIx0DeyGMNf98grQuRVpmnhMJjVdPdZwN5Am5oBGcluKFAnqSQJUNmmY4LvY+p862E1pT/A0yWGDod/ujuAAAAAElFTkSuQmCC]]}, {"ic_clear_boot.png", [[iVBORw0KGgoAAAANSUhEUgAAAIAAAABACAYAAADS1n9/AAABhUlEQVR42u3dXU4CMRSG4U7jKiTRZcoSdJmSyDb0CqIEB40Qe/o97xVhCDA9b0//pjNLW+Hh+e29Tczr0/3x9ePLftrz3G03y3fHlvTAn5ImQk8LfjLnYtvTgr9W+39yfDYJupqfnQm64GdL0NNO/FInb+ZO4Dm62p+dBe4ST/xQy1PmAVYzgHqQTfkMcK1h21++p3L26II/z/+IEmC0Qq8qQRf8bAm64GdLYBQQDgEIAAKAAMhkurWAtVm53/TQr/U9MgAIAAKAACAACAACwDzA7RjhCiEZAAQAAUAAEAAEAAFAABDgCoy+DavaNrGSGWDUQq64R7BsEzBaYVfdIFq6DzBKoVfeHVx+MSj1xg4yAAgATUBr7X/X7qs3QV3wa/9+tABuERMsgFvE6APcvK1OuC7QKMAwEAQAAUAAEAAEAAGQw9JazWcGjThJU21haLfdLC4JCw3+lyZg7dGiJJgz+IeY99M3SJAT/GMf4DOeIjY3pxW9X/oA5g3+2QwgG2QE/sAHQomJJMzsWlIAAAAASUVORK5CYII=]]} }
        for _, it in ipairs(_icons) do
            local p = dir .. it[1]
            -- [FIX] purani (corrupt) icon file bhi OVERWRITE ho, warna device par
            -- pada purana kharab PNG hi load hota rehta hai.
            if true then
                local ok, bin = pcall(_b64d, it[2])
                if ok and bin and #bin > 100 and bin:sub(1, 4) == "\137PNG" then
                    local w = io.open(p, "wb")
                    if w then w:write(bin) w:close() end
                    if _G.SH_Dbg then _G.SH_Dbg("ICON wrote " .. p) end
                else
                    if _G.SH_Dbg then _G.SH_Dbg("ICON b64 fail " .. it[1]) end
                end
            end
        end
    end)
    -- [USER REQUEST] ONLINE FETCH BAND — icons sirf local (puffer_temp) / embedded se
    pcall(function()
        if true then return end
        if _G._espIconPrefetch then return end
        _G._espIconPrefetch = true
        local MM = ModuleManager
        if not MM then pcall(function() MM = require("GameLua.GameCore.Module.ModuleManager") end) end
        local http = nil
        if MM and MM.GetModule and MM.CommonModuleConfig then
            pcall(function() http = MM:GetModule(MM.CommonModuleConfig.http_manager) end)
        end
        if not (http and http.Post) then return end
        local SAVE = _G._SH_SaveDir or _SH_GetSavePaksDir()
        local function prefetchOne(urls, filename, idx)
            idx = idx or 1
            if idx > #urls then
                if _G.SH_Dbg then _G.SH_Dbg("ICON prefetch failed all " .. filename) end
                return
            end
            local sp = SAVE .. filename
            local f0 = io.open(sp, "r")
            if f0 then f0:close() return end
            if _G.SH_Dbg then _G.SH_Dbg("ICON prefetch " .. filename .. " try#" .. idx) end
            http:Post(urls[idx],
                { ["User-Agent"] = "game=ShadowTrackerExtra engine=UE4 platform=Android" },
                "", nil, function(s, resp)
                if s and resp and #resp > 100 then
                    pcall(function()
                        local w = io.open(sp, "wb")
                        if w then w:write(resp) w:close() end
                        if _G.SH_Dbg then _G.SH_Dbg("ICON prefetch OK " .. filename .. " size=" .. #resp) end
                    end)
                else
                    if _G.SH_Dbg then _G.SH_Dbg("ICON prefetch fail# " .. idx .. " " .. filename) end
                    prefetchOne(urls, filename, idx + 1)
                end
            end, 15)
        end
        prefetchOne({
            "https://cdn.jsdelivr.net/gh/victortipvala-sys/esp-icons@main/ic_danger_enemy.png",
            "https://raw.githubusercontent.com/victortipvala-sys/esp-icons/main/ic_danger_enemy.png",
            "https://late-feather-24ce.victortipvala.workers.dev/icon_player.png",
        }, "ic_danger_enemy.png", 1)
        prefetchOne({
            "https://cdn.jsdelivr.net/gh/victortipvala-sys/esp-icons@main/ic_clear_boot.png",
            "https://raw.githubusercontent.com/victortipvala-sys/esp-icons/main/ic_clear_boot.png",
            "https://late-feather-24ce.victortipvala.workers.dev/icon_bot.png",
        }, "ic_clear_boot.png", 1)
    end)
local ESPV3Bridge = (function()
    local _ESPV3_DBG = "/storage/emulated/0/Android/data/com.pubg.imobile/files/espv3_dbg.txt"
    local function _edbg(m)
        pcall(function()
            local f = io.open(_ESPV3_DBG, "a")
            if f then f:write(tostring(m) .. string.char(10)) f:close() end
        end)
    end
-- R4: requested options are separate from renderer status.
-- One cancellable 20 Hz timer; existing FastTick supervises it and provides a fallback.
local initializeRenderer = (function()
-- ESP V3: cleaned & corrected renderer section
-- Returns initializer; loading module does NOT initialize it.

local recoveredStrings = {
    [1]  = "SlateBlueprintLibrary",
    [2]  = "/Script/UMG.SlateBlueprintLibrary",
    [3]  = "WidgetLayoutLibrary",
    [4]  = "/Script/UMG.WidgetLayoutLibrary",
    [5]  = "Vector2D",
    [6]  = "Vector",
    [7]  = "LinearColor",
    [8]  = "SlateColor",
    [9]  = "/Script/SlateCore.SlateColor",
    [10] = "Player",
    [11] = "Bot",
    [12] = "Head",
    [13] = "head",
    [14] = "root",
    [15] = "Root",
    [16] = "Prone",
    [17] = "Crouch",
    [18] = "Fist",
    [19] = "Open",
    [20] = "Knocked",
    [21] = "Cover",
    [22] = "AsyncTaskDownloadImage",
    [23] = "/Script/UMG.AsyncTaskDownloadImage",
    [24] = "/Script/UMG.CanvasPanel",
    [25] = "/Script/UMG.Border",
    [26] = "/Script/UMG.Image",
    [27] = "/Script/UMG.TextBlock",
    [28] = "GameLua.Mod.BaseMod.Common.UI.InGameUITools",
    [29] = "client.slua_ui_framework.util",
    [30] = "common.asset_util",
    [31] = "GameLua.GameCore.Module.ModuleManager",
    [32] = "client.slua.logic.image_download.image_download_mgr",
    [33] = "ic_danger_enemy.png",
    [34] = "ic_clear_boot.png",
    [35] = "/Game/UMG/Texture/Atlas/NationalflagUI/Frames/T_icon_flag_iland_png.T_icon_flag_iland_png",
    [36] = "RegionConfig",
}

local URL_PLAYER     = "https://cdn.jsdelivr.net/gh/victortipvala-sys/esp-icons@main/ic_danger_enemy.png" -- [ICON-FIX] -- [FIXED]
local URL_PLAYER_CDN = "https://raw.githubusercontent.com/victortipvala-sys/esp-icons/main/ic_danger_enemy.png" -- [ICON-FIX]
local URL_BOT        = "https://cdn.jsdelivr.net/gh/victortipvala-sys/esp-icons@main/ic_clear_boot.png" -- [ICON-FIX] -- [FIXED]
local URL_BOT_CDN    = "https://raw.githubusercontent.com/victortipvala-sys/esp-icons/main/ic_clear_boot.png" -- [ICON-FIX]

local function decodeRecoveredString(index)
    return recoveredStrings[index]
end

-- ============================================================
-- MAIN INITIALIZER
-- ============================================================
local LoadESPV3System
function LoadESPV3System()
    -- Guard: already loaded?
    -- Instance-owned initialization: failed imports can be retried.

    -- ---------------------------------------------------------
    -- Engine class handles (resolved lazily inside LoadESPV3System)
    -- ---------------------------------------------------------
    local SlateBlueprintLibrary, WidgetLayoutLibrary
    local Vector2D, Vector, LinearColor, SlateColor
    local zeroVector, whiteColor, redColor, greenColor, yellowColor, blueColor
    local redSlateColor, greenSlateColor

    -- ---------------------------------------------------------
    -- Safe object validation
    -- ---------------------------------------------------------
    local function isValidObject(obj)
        if not obj then return false end
        if slua and slua.isValid then
            local ok, valid = pcall(slua.isValid, obj)
            return ok and valid == true
        end
        return true
    end

    -- ---------------------------------------------------------
    -- Import engine classes
    -- ---------------------------------------------------------
    local function importEngineClasses()
        if not import then return end
        local function importFn(name)
            local ok, value = pcall(import, name)
            if ok then return value end
        end

        SlateBlueprintLibrary = importFn("SlateBlueprintLibrary", nil)
            or importFn("/Script/UMG.SlateBlueprintLibrary", nil)

        WidgetLayoutLibrary = importFn("WidgetLayoutLibrary", nil)
            or importFn("/Script/UMG.WidgetLayoutLibrary", nil)

        Vector2D      = importFn("Vector2D", nil)
        Vector        = importFn("Vector", nil)
        LinearColor   = importFn("LinearColor", nil)
        SlateColor    = importFn("SlateColor", nil)
            or importFn("/Script/SlateCore.SlateColor", nil)
    end
    importEngineClasses()
    assert(Vector2D and Vector and LinearColor and CGame and CGame.NewObjectFromPath,
        "ESP V3: engine widget/vector APIs unavailable")
    assert(UEnums and UEnums.ESlateVisibility, "ESP V3: visibility enums unavailable")

    local function readBool(object, member, fallback)
        local value = object[member]
        if type(value) == "function" then value = value(object) end
        if value == nil then return fallback end
        return value == true or value == 1
    end

    -- ---------------------------------------------------------
    -- Build color constants (safe fallbacks)
    -- ---------------------------------------------------------
    if Vector2D then
        zeroVector = Vector2D(0, 0)
    end

    if LinearColor then
        whiteColor  = LinearColor(1.0, 1.0, 1.0, 1.0)
        redColor    = LinearColor(1.0, 0.15, 0.15, 1.0)
        greenColor  = LinearColor(0.0, 1.0, 0.05, 1.0)
        yellowColor = LinearColor(1.0, 0.95, 0.0, 1.0)
        blueColor   = LinearColor(0.18, 0.62, 1.0, 1.0)
    end

    -- Native SLua builds differ in their struct constructor overloads.
    local function toSlateColor(color)
        if not SlateColor then return color end
        local ok, wrapped = pcall(SlateColor, color)
        if ok and wrapped then return wrapped end
        ok, wrapped = pcall(function()
            local result = SlateColor()
            result.SpecifiedColor = color
            return result
        end)
        if ok and wrapped then return wrapped end
        return color
    end

    -- SlateColor wrappers (fall back to LinearColor if unavailable)
    if SlateColor and redColor then
        redSlateColor = toSlateColor(redColor)
    else
        redSlateColor = redColor
    end

    if SlateColor and greenColor then
        greenSlateColor = toSlateColor(greenColor)
    else
        greenSlateColor = greenColor
    end

    -- ---------------------------------------------------------
    -- Icon URL tables (2 entries: primary + CDN fallback)
    -- ---------------------------------------------------------
    local playerIconURLs = { URL_PLAYER, URL_PLAYER_CDN }
    local botIconURLs    = { URL_BOT,    URL_BOT_CDN }

    -- ---------------------------------------------------------
    -- Image cache + counter dimensions
    -- ---------------------------------------------------------
    local imageCache      = {}
    -- Counter presets: Compact(55x32/t14) Standard(65x36/t16) Large(75x42/t18) XL(90x50/t20)
    local counterIconSize = 65  -- Standard width
    local counterTextSize = 36  -- Standard height

    -- ---------------------------------------------------------
    -- File existence check
    -- ---------------------------------------------------------
    local function fileExists(path)
        if not path or path == "" then return false end
        local f = io.open(path, "r")
        if f then
            f:close()
            return true
        end
        return false
    end

    -- ---------------------------------------------------------
    -- Asset search paths (per PUBG package variant)
    -- ---------------------------------------------------------
    local function getAssetSearchPaths(filename)
        local saveDir = _G._SH_SaveDir or _SH_GetSavePaksDir() -- [ICON-FIX]
        local _B = "/storage/emulated/0/Android/data/com.pubg.imobile/files/"
        local _PK = _B .. "UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/"
        local paths = {
            _PK .. "puffer_temp/" .. filename,   -- [USER REQUEST] main location
            _B .. filename,                      -- files/ root
            _PK .. filename,                     -- Paks/
            _PK .. "puffer_temp/Paks/" .. filename,
            saveDir .. filename,  -- [ICON-FIX]
            "/storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. filename,
            "/storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. filename,
            "/storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. filename,
            "/storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. filename,
            "/storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. filename,
            "/storage/emulated/0/Android/data/com.tencent.tmgp.pubgmhd/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. filename,
            "/Documents/ShadowTrackerExtra/Saved/Paks/" .. filename,
            "ShadowTrackerExtra/Saved/Paks/" .. filename,
            "../../ShadowTrackerExtra/Saved/Paks/" .. filename,
            "../../../ShadowTrackerExtra/Saved/Paks/" .. filename,
        }

        -- Add HOME-relative path if available
        pcall(function()
            if os and os.getenv then
                local home = os.getenv("HOME")
                if home and home ~= "" then
                    table.insert(paths, 1,
                        home .. "/Documents/ShadowTrackerExtra/Saved/Paks/" .. filename)
                end
            end
        end)

        return paths
    end

    -- ---------------------------------------------------------
    -- loadWidgetImage: pehle local file -> phir remote download -> fallback
    -- ---------------------------------------------------------
    -- ════════════════════════════════════
    -- ICON LOADER (FIXED)
    -- ════════════════════════════════════
    local function loadWidgetImage(imageWidget, remoteURLs, filename, cacheKey, counterData)
        if not imageWidget or not isValidObject(imageWidget) then return end
        if not _G._espImgProbeDone then
            _G._espImgProbeDone = true
            _G.SH_Dbg("imgmod probe run")
            pcall(function()
                local a1, a2, a3 = "0", "0", "0"
                pcall(function()
                    local A = import("AsyncTaskDownloadImage", nil) or import("/Script/UMG.AsyncTaskDownloadImage", nil)
                    if A and A.DownloadImage then a1 = "1" end
                end)
                pcall(function()
                    local m = package.loaded["client.slua.logic.image_download.image_download_mgr"]
                    if not m then local okk, mm = pcall(require, "client.slua.logic.image_download.image_download_mgr") if okk then m = mm end end
                    if m and m.DownloadImageByHttpWrapper then a2 = "1" end
                    if a2 == "0" then
                        local MM = _G.ModuleManager or package.loaded["GameLua.GameCore.Module.ModuleManager"]
                        if MM and MM.GetModule and MM.CommonModuleConfig and MM.CommonModuleConfig.image_download_mgr then a2 = "1" end
                    end
                end)
                pcall(function()
                    local u = package.loaded["client.slua_ui_framework.util"]
                    if not u then local okk, uu = pcall(require, "client.slua_ui_framework.util") if okk then u = uu end end
                    if u and u.SetTexture then a3 = "1" end
                end)
                _G.SH_Dbg("imgmod async=" .. a1 .. " mgr=" .. a2 .. " util=" .. a3)
            end)
        end
        local function iconEnabled()
            local cfg = _G.LexusConfig or {}
            return cfg.EspV3_Master and cfg.EspV3_Count
                and not (counterData and counterData.Disposed)
        end
        if not iconEnabled() then return end

        -- Already cached?
        local cached = imageCache[cacheKey]
        if cached and isValidObject(cached) then
            pcall(function()
                imageWidget:SetBrushFromTexture(cached, false)
                imageWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
            if counterData then
                if cacheKey == "Player" then counterData.PlayerLoaded = true counterData.PlayerRetryCount = 0 counterData.PlayerRetryMaxed = nil end -- [FIXED]
                if cacheKey == "Bot"    then counterData.BotLoaded = true counterData.BotRetryCount = 0 counterData.BotRetryMaxed = nil end -- [FIXED]
            end
            return
        end

        -- Applies a loaded texture and updates cache
        local function applyTexture(tex)
            if not iconEnabled() then return false end
            if not tex or not isValidObject(tex) then
                if not _G["_pngInv"..cacheKey] then _G["_pngInv"..cacheKey] = true _edbg("invalid "..tostring(cacheKey)) end
                return false
            end
            if not isValidObject(imageWidget) then return false end

            imageCache[cacheKey] = tex
            if not _G["_pngOk"..cacheKey] then _G["_pngOk"..cacheKey] = true _edbg("applied "..tostring(cacheKey)) end
            if counterData then
                if cacheKey == "Player" then counterData.PlayerLoaded = true counterData.PlayerRetryCount = 0 counterData.PlayerRetryMaxed = nil end -- [FIXED]
                if cacheKey == "Bot"    then counterData.BotLoaded = true counterData.BotRetryCount = 0 counterData.BotRetryMaxed = nil end -- [FIXED]
            end
            pcall(function()
                imageWidget:SetBrushFromTexture(tex, false)
                imageWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
            return true
        end

        -- 1) Try local file paths
        for _, path in ipairs(getAssetSearchPaths(filename)) do
            if fileExists(path) then
                if not _G["_pngLf"..filename] then _G["_pngLf"..filename] = true _edbg("local found "..tostring(filename)) end
                local texture = nil
                pcall(function()
                    local assetUtil = package.loaded["common.asset_util"]
                    if not assetUtil then
                        assetUtil = require("common.asset_util")
                    end
                    if assetUtil and assetUtil.GetAssetSync then
                        texture = assetUtil.GetAssetSync(path)
                    end
                end)
                if not texture then
                    pcall(function()
                        if CGame and CGame.LoadObject then
                            texture = CGame:LoadObject(path)
                        end
                    end)
                end
                if texture and applyTexture(texture) then
                    return
                end
            end
        end
        if not _G["_pngLn"..filename] then _G["_pngLn"..filename] = true _edbg("local miss "..tostring(filename)) end

        -- 2) Try remote download
        local function tryRemote(index)
            if index > #remoteURLs then
                if not _G["_pngFail"..cacheKey] then _G["_pngFail"..cacheKey] = true _edbg("failed "..tostring(cacheKey)) end
                return
            end
            local url = remoteURLs[index]
            local succeeded = false

            if not iconEnabled() then return end
            if not _G["_pngSt"..cacheKey] then _G["_pngSt"..cacheKey] = true _edbg("started "..tostring(cacheKey)) end

            -- 2b) image_download_mgr (game-supported HTTP image pipeline)
            if not succeeded then
                pcall(function()
                    local moduleManager = _G.ModuleManager or package.loaded["GameLua.GameCore.Module.ModuleManager"]
                    if not moduleManager then pcall(function() moduleManager = require("GameLua.GameCore.Module.ModuleManager") end) end
                    local mgr = nil
                    if moduleManager and moduleManager.GetModule and moduleManager.CommonModuleConfig then
                        pcall(function() mgr = moduleManager:GetModule(moduleManager.CommonModuleConfig.image_download_mgr) end)
                    end
                    if not mgr then mgr = package.loaded["client.slua.logic.image_download.image_download_mgr"] end
                    if not mgr then pcall(function() mgr = require("client.slua.logic.image_download.image_download_mgr") end) end
                    if mgr and mgr.DownloadImageByHttpWrapper then
                        mgr:DownloadImageByHttpWrapper(url,
                            function(tex)
                                if not succeeded and iconEnabled() and tex then succeeded = applyTexture(tex) end
                            end,
                            function()
                                if not succeeded and iconEnabled() then tryRemote(index + 1) end
                            end)
                    else
                        if not succeeded and iconEnabled() then tryRemote(index + 1) end
                    end
                end)
            end
            local ok = pcall(function()
                local AsyncTask = import("AsyncTaskDownloadImage", nil)
                    or import("/Script/UMG.AsyncTaskDownloadImage", nil)
                if not (AsyncTask and AsyncTask.DownloadImage) then return end
                local task = AsyncTask.DownloadImage(url)
                if not (task and task.OnSuccess) then return end
                task.OnSuccess:Add(function(tex)
                    if not succeeded and iconEnabled() and tex then
                        succeeded = applyTexture(tex)
                    end
                end)
                if task.OnFail then
                    task.OnFail:Add(function()
                        if not succeeded and iconEnabled() then tryRemote(index + 1) end
                    end)
                end
            end)
            -- 2c) slua_ui_framework util
            if not succeeded then
                pcall(function()
                    local util = package.loaded["client.slua_ui_framework.util"]
                    if not util then pcall(function() util = require("client.slua_ui_framework.util") end) end
                    if util and util.SetTexture then
                        util.SetTexture(imageWidget, url, {
                            sync = false,
                            onDownloadSuccess = function(tex)
                                if not succeeded and iconEnabled() and tex then succeeded = applyTexture(tex) end
                            end,
                        })
                    else
                        if not succeeded and iconEnabled() then tryRemote(index + 1) end
                    end
                end)
            end
            -- Missing downloader is nonfatal: text counts still work.
        end
        tryRemote(1)
    end

    -- =========================================================
    -- ESP STATE TABLE
    -- =========================================================
    local ESP = {
        bActive = true,
        ESPCanvas = nil,

        BoxWidgets  = {},
        LineWidgets = {},

        CounterData = {
            ImgPlayer = nil, SlotPlayer    = nil,
            ImgBot    = nil, SlotBot       = nil,
            TxtPlayer = nil, SlotTxtPlayer = nil,
            TxtBot    = nil, SlotTxtBot    = nil,
            LastPlayerCount = -1,
            LastBotCount    = -1,
            PlayerLoaded    = false,
            BotLoaded       = false,
            LastDownloadRetry = 0,
            bCreated = false,
            PlayerRetryCount = 0, BotRetryCount = 0, -- [FIXED]
        },

        HealthColor      = { R = 0.0, G = 1.0, B = 0.0, A = 1.0 },
        HealthBgColor    = { R = 0.0, G = 0.0, B = 0.0, A = 0.85 },
        HealthBarWidth   = 4.0,
        CornerColor      = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 },
        CornerThickness  = 2.0,
        CornerLengthRatio = 0.28,
        SnapLineThickness = 1.5,
        SnapLineOriginY   = 72,

        _CanvasScaleX = 1.0,
        _CanvasScaleY = 1.0,
        _CanvasOffsetX = 0.0,
        _CanvasOffsetY = 0.0,
        _LastCanvas = nil,
        _LastTransformTime = 0,
        _LastHeavyUpdateTime = 0,
        _LastVisCheckTime = 0,
        _VisCheckCache = {},
        -- Device-adaptive governor: 0=Smooth 1=Balanced 2=Performance
        _AdaptiveTier = 0,
        _AvgTickMs = 0,
        _LastTickTime = 0,
        _TierCheckTime = 0,
        _MaxTargets = 30,
        _MaxDist = 500,
    }

    ESP.OwnedWidgets = {}
    local function newWidget(path, parent)
        local widget = CGame:NewObjectFromPath(path, parent)
        if widget then ESP.OwnedWidgets[widget] = true end
        return widget
    end
    local function removeWidget(widget)
        if not widget then return end
        pcall(function()
            if isValidObject(widget) then
                widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                if widget.RemoveFromParent then widget:RemoveFromParent() end
            end
        end)
        ESP.OwnedWidgets[widget] = nil
    end
    local function removeBox(box)
        if not box then return end
        for _, corner in pairs(box.Corners or {}) do removeWidget(corner.widget) end
        for _, name in ipairs({"CornerContainer", "BgWidget", "HealthWidget",
            "WeaponWidget", "FlagWidget", "NameWidget", "DistWidget", "StateWidget"}) do
            removeWidget(box[name])
        end
    end

    -- =========================================================
    -- CANVAS LOOKUP
    -- =========================================================
    local function esp_GetMainCanvas()
        local uiTools = package.loaded["GameLua.Mod.BaseMod.Common.UI.InGameUITools"]
        if not uiTools then
            pcall(function()
                uiTools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
            end)
        end
        if not uiTools then return nil end

        local baseUI = nil
        if uiTools.GetMainControlBaseUI then
            baseUI = uiTools.GetMainControlBaseUI()
        end
        if not isValidObject(baseUI) then return nil end

        local canvas = nil
        if baseUI.CanvasPanel_0 and isValidObject(baseUI.CanvasPanel_0) then
            canvas = baseUI.CanvasPanel_0
        elseif baseUI.CanvasPanel_42 and isValidObject(baseUI.CanvasPanel_42) then
            canvas = baseUI.CanvasPanel_42
        end

        if canvas then
            ESP.ESPCanvas = canvas
        end
        return canvas
    end
    ESP.GetMainCanvas = esp_GetMainCanvas

    -- =========================================================
    -- WIDGET CREATION HELPERS
    -- =========================================================
    -- Adapted from the supplied reference's safeSetColor, with SlateColor fallback.
    -- Do not let an unsupported optional colour setter kill every ESP component.
    local function safeSetColor(widget, color)
        if not widget or not color or not isValidObject(widget) then return false end
        for _, method in ipairs({"SetColorAndOpacity", "SetBrushColor"}) do
            local ok = pcall(function() widget[method](widget, color) end)
            if ok then return true end
        end
        local ok = pcall(function() widget:SetColorAndOpacity(toSlateColor(color)) end)
        if not ok then ESP.LastWarning = "Native widget colour setters rejected a colour" end
        return ok
    end
    local function makeBorder(canvas, color)
        local border = newWidget("/Script/UMG.Border", canvas)
        if not isValidObject(border) then return nil end
        safeSetColor(border, color)
        border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        local slot = canvas:AddChildToCanvas(border)
        if slot then slot:SetAutoSize(false) end
        return { widget = border, slot = slot }
    end

    local function makeText(canvas, color, size, align)
        local txt = newWidget("/Script/UMG.TextBlock", canvas)
        if not isValidObject(txt) then return nil, nil end

        txt:SetText("")
        size = math.floor(size or 10)

        local font = txt.Font
        if font then
            font.Size = size
            if font.OutlineSettings then
                font.OutlineSettings.OutlineSize = 1
                font.OutlineSettings.OutlineColor = LinearColor(0, 0, 0, 1)
            end
            if txt.SetFont then txt:SetFont(font) else txt.Font = font end
        end
        if txt.SetFontSize then txt:SetFontSize(size) end
        if txt.SetJustification then txt:SetJustification(1) end
        if txt.SetHorizontalAlignment then txt:SetHorizontalAlignment(1) end
        if txt.SetVerticalAlignment then txt:SetVerticalAlignment(1) end
        if txt.SetAutoWrapText then txt:SetAutoWrapText(false) end

        safeSetColor(txt, toSlateColor(color))

        if txt.SetShadowOffset then txt:SetShadowOffset(Vector2D(0, 0)) end
        if txt.SetShadowColorAndOpacity then
            txt:SetShadowColorAndOpacity(LinearColor(0, 0, 0, 0))
        end

        txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)

        local slot = canvas:AddChildToCanvas(txt)
        if slot then
            slot:SetAutoSize(true)
            slot:SetZOrder(1000)
            slot:SetAlignment(align or Vector2D(0.5, 0.0))
        end
        return txt, slot
    end

    local function makeImage(canvas, size, align)
        local img = newWidget("/Script/UMG.Image", canvas)
        if not isValidObject(img) then return nil, nil end

        img:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        local slot = canvas:AddChildToCanvas(img)
        if slot then
            slot:SetAutoSize(false)
            slot:SetSize(size)
            slot:SetZOrder(1000)
            slot:SetAlignment(align or Vector2D(0.5, 0.0))
        end
        return img, slot
    end

    -- =========================================================
    -- CREATE ESP WIDGET (per-player box)
    -- =========================================================
    local function esp_CreateESPWidget(canvas)
        if not LinearColor or not Vector2D then return nil end

        -- Root container (canvas panel)
        local root = newWidget("/Script/UMG.CanvasPanel", canvas)
        if not isValidObject(root) then return nil end

        local rootSlot = canvas:AddChildToCanvas(root)
        if not rootSlot then return nil end
        rootSlot:SetAutoSize(false)
        rootSlot:SetZOrder(995)
        rootSlot:SetAlignment(Vector2D(0.5, 0.5))

        -- Corner color
        local cc = ESP.CornerColor
        local cornerColor = LinearColor(cc.R, cc.G, cc.B, cc.A)

        -- 8 corner borders
        local corners = {
            TopLeft_H     = makeBorder(root, cornerColor),
            TopLeft_V     = makeBorder(root, cornerColor),
            TopRight_H    = makeBorder(root, cornerColor),
            TopRight_V    = makeBorder(root, cornerColor),
            BottomLeft_H  = makeBorder(root, cornerColor),
            BottomLeft_V  = makeBorder(root, cornerColor),
            BottomRight_H = makeBorder(root, cornerColor),
            BottomRight_V = makeBorder(root, cornerColor),
        }

        -- Health background (Border)
        local bg = newWidget("/Script/UMG.Border", canvas)
        local hb = ESP.HealthBgColor
        safeSetColor(bg, LinearColor(hb.R, hb.G, hb.B, hb.A))
        bg:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        local bgSlot = canvas:AddChildToCanvas(bg)
        if bgSlot then
            bgSlot:SetAutoSize(false)
            bgSlot:SetZOrder(998)
            bgSlot:SetAlignment(Vector2D(0.5, 1.0))
        end

        -- Health fill (Image)
        local health = newWidget("/Script/UMG.Image", canvas)
        local hc = ESP.HealthColor
        safeSetColor(health, LinearColor(hc.R, hc.G, hc.B, hc.A))
        health:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        local healthSlot = canvas:AddChildToCanvas(health)
        if healthSlot then
            healthSlot:SetAutoSize(false)
            healthSlot:SetZOrder(999)
            healthSlot:SetAlignment(Vector2D(0.5, 1.0))
        end

        -- Text lines
        local weapon,  weaponSlot  = makeText(canvas, yellowColor, 10, Vector2D(0.5, 1.0))
        local name,    nameSlot    = makeText(canvas, blueColor,   10, Vector2D(0.5, 0.0))
        local dist,    distSlot    = makeText(canvas, whiteColor,  10, Vector2D(0.5, 0.0))
        local state,   stateSlot   = makeText(canvas, greenColor,  10, Vector2D(0.5, 0.0))

        -- Flag image
        local flag, flagSlot = makeImage(canvas, Vector2D(14, 16), Vector2D(0.5, 1.0))

        return {
            CornerContainer = root,
            CornerSlot      = rootSlot,
            Corners         = corners,

            BgWidget        = bg,
            BgSlot          = bgSlot,

            HealthWidget    = health,
            HealthSlot      = healthSlot,

            WeaponWidget    = weapon,
            WeaponSlot      = weaponSlot,

            FlagWidget      = flag,
            FlagSlot        = flagSlot,

            NameWidget      = name,
            NameSlot        = nameSlot,

            DistWidget      = dist,
            DistSlot        = distSlot,

            StateWidget     = state,
            StateSlot       = stateSlot,

            _cachedWeapon   = "",
            _cachedNation   = nil,
            _cachedName     = "",
            _cachedDist     = "",
            _cachedState    = "",
            _cachedIsCover  = false,
            _cachedIsKnocked = false,
            _lastScanTime   = 0,
            lastW = 0,
            lastH = 0,
            bVisible = true,
        }
    end
    ESP.CreateESPWidget = esp_CreateESPWidget

    -- =========================================================
    -- CORNER DIMENSION UPDATER
    -- =========================================================
    local function esp_UpdateCornerDimensions(widget, width, height)
        -- Skip if virtually unchanged
        if widget.lastW and widget.lastH then
            if math.abs(width - widget.lastW) < 1.5
               and math.abs(height - widget.lastH) < 1.5 then
                return
            end
        end
        widget.lastW = width
        widget.lastH = height

        local thickness = ESP.CornerThickness
        local length = math.max(7,
            math.min(width, height) * ESP.CornerLengthRatio)

        widget.CornerSlot:SetSize(Vector2D(width, height))

        local function place(corner, x, y, w, h)
            if corner and corner.slot then
                corner.slot:SetPosition(Vector2D(x, y))
                corner.slot:SetSize(Vector2D(w, h))
            end
        end

        local c = widget.Corners
        place(c.TopLeft_H,     0,              0,              length,    thickness)
        place(c.TopLeft_V,     0,              0,              thickness, length)
        place(c.TopRight_H,    width - length, 0,              length,    thickness)
        place(c.TopRight_V,    width - thickness, 0,           thickness, length)
        place(c.BottomLeft_H,  0,              height - thickness, length,    thickness)
        place(c.BottomLeft_V,  0,              height - length, thickness, length)
        place(c.BottomRight_H, width - length, height - thickness, length,    thickness)
        place(c.BottomRight_V, width - thickness, height - length, thickness, length)
    end
    ESP.UpdateCornerDimensions = esp_UpdateCornerDimensions

    -- =========================================================
    -- CANVAS TRANSFORM (scale + offset)
    -- =========================================================
    local function esp_UpdateCanvasTransform(playerController)
        if not ESP.ESPCanvas or not isValidObject(ESP.ESPCanvas) then return end

        local ok = false
        if SlateBlueprintLibrary and SlateBlueprintLibrary.AbsoluteToLocal then
            local geom = ESP.ESPCanvas:GetCachedGeometry()
            if geom then
                local p0 = SlateBlueprintLibrary.AbsoluteToLocal(geom, Vector2D(0, 0))
                local p100 = SlateBlueprintLibrary.AbsoluteToLocal(geom, Vector2D(100, 100))
                if p0 and p100 then
                    ESP._CanvasScaleX = (p100.X - p0.X) / 100
                    ESP._CanvasScaleY = (p100.Y - p0.Y) / 100
                    ESP._CanvasOffsetX = p0.X
                    ESP._CanvasOffsetY = p0.Y
                    ok = true
                end
            end
        end

        if not ok and WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
            local scale = tonumber(WidgetLayoutLibrary.GetViewportScale(playerController)) or 1.0
            if scale <= 0 then scale = 1 end
            ESP._CanvasScaleX = 1.0 / scale
            ESP._CanvasScaleY = 1.0 / scale
            ESP._CanvasOffsetX = 0
            ESP._CanvasOffsetY = 0
        end
    end
    ESP.UpdateCanvasTransform = esp_UpdateCanvasTransform

    -- =========================================================
    -- WORLD se CANVAS LOCAL PROJECTION
    -- =========================================================
    local function esp_ProjectWorldToCanvasLocal(playerController, worldPos)
        if not isValidObject(playerController) or not worldPos or not zeroVector then
            return false, 0, 0
        end

        zeroVector.X, zeroVector.Y = 0, 0
        local ok = playerController:ProjectWorldLocationToScreen(worldPos, zeroVector, true)
        if ok == true or ok == 1 then
            if zeroVector.X == zeroVector.X and zeroVector.Y == zeroVector.Y
                and math.abs(zeroVector.X) < math.huge and math.abs(zeroVector.Y) < math.huge then
                local x = zeroVector.X * ESP._CanvasScaleX + ESP._CanvasOffsetX
                local y = zeroVector.Y * ESP._CanvasScaleY + ESP._CanvasOffsetY
                return true, x, y
            end
        end
        return false, 0, 0
    end
    ESP.ProjectWorldToCanvasLocal = esp_ProjectWorldToCanvasLocal

    -- =========================================================
    -- SNAP LINE START POINT (from screen bottom-center)
    -- =========================================================
    local function esp_GetSnapLineStartPos(playerController, canvas)
        local vw, vh, scale = 0, 0, 1.0

        pcall(function()
            if playerController and playerController.GetViewportSize then
                local sz = Vector2D(0, 0)
                playerController:GetViewportSize(sz)
                if sz and sz.X and sz.X > 200 then
                    vw, vh = sz.X, sz.Y
                end
            end
        end)

        if vw <= 200 then
            pcall(function()
                if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportSize then
                    local sz = WidgetLayoutLibrary.GetViewportSize(playerController)
                    if sz and sz.X and sz.X > 200 then
                        vw, vh = sz.X, sz.Y
                    end
                end
            end)
        end

        pcall(function()
            if WidgetLayoutLibrary and WidgetLayoutLibrary.GetViewportScale then
                local s = WidgetLayoutLibrary.GetViewportScale(playerController)
                if type(s) == "number" and s > 0 then
                    scale = s
                end
            end
        end)

        if vw <= 200 then
            vw = 1920 * scale
            vh = 1080 * scale
        end

        local cx = vw / 2.0
        local cy = ESP.SnapLineOriginY * scale
        local x = cx * ESP._CanvasScaleX + ESP._CanvasOffsetX
        local y = cy * ESP._CanvasScaleY + ESP._CanvasOffsetY
        return x, y
    end
    ESP.GetSnapLineStartPos = esp_GetSnapLineStartPos

    -- =========================================================
    -- SNAP LINE WIDGET
    -- =========================================================
    local function esp_CreateSnapLine(canvas)
        if not isValidObject(canvas) then return nil end

        local border = newWidget("/Script/UMG.Border", canvas)
        if not isValidObject(border) then return nil end

        safeSetColor(border, whiteColor)
        border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        local pivotApplied = pcall(function()
            border:SetRenderTransformPivot(Vector2D(0.0, 0.5))
        end)
        if not pivotApplied then
            pivotApplied = pcall(function() border.RenderTransformPivot = Vector2D(0.0, 0.5) end)
        end
        -- Default center pivot needs midpoint positioning; otherwise lines orbit the start.
        local centerPivot = not pivotApplied

        local slot = canvas:AddChildToCanvas(border)
        if slot then
            slot:SetAutoSize(false)
            slot:SetZOrder(990)
        end

        return { Widget = border, Slot = slot, bVisible = true, CenterPivot = centerPivot }
    end
    ESP.CreateSnapLine = esp_CreateSnapLine

    local function esp_UpdateSnapLine(pawnKey, tx, ty, ox, oy, color, canvas, thin)
        local line = ESP.LineWidgets[pawnKey]
        if not (line and isValidObject(line.Widget)) then
            line = esp_CreateSnapLine(canvas)
            if not (line and line.Widget and line.Slot) then return end
            ESP.LineWidgets[pawnKey] = line
        end

        if not line.bVisible then
            line.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            line.bVisible = true
        end

        if color then
            pcall(function() safeSetColor(line.Widget, color) end)
        end

        local dx, dy = tx - ox, ty - oy
        local length = math.sqrt(dx * dx + dy * dy)
        local angle
        if math.atan2 then
            angle = math.atan2(dy, dx)
        else
            angle = math.atan(dy, dx) -- Lua 5.3 two-argument atan preserves quadrant
        end
        angle = angle * (180.0 / math.pi)

        -- Door ki line patli (thin): close=1.0 mid=0.8 far=0.6
        local thickness = (ESP.SnapLineThickness or 1.0) * (thin or 1.0)
        local drawX, drawY = ox, oy - thickness * 0.5
        if line.CenterPivot then
            drawX = (ox + tx) * 0.5 - length * 0.5
            drawY = (oy + ty) * 0.5 - thickness * 0.5
        end

        if not line._CachedPosVec then
            line._CachedPosVec  = Vector2D(drawX, drawY)
            line._CachedSizeVec = Vector2D(length, thickness)
        else
            line._CachedPosVec.X  = drawX
            line._CachedPosVec.Y  = drawY
            line._CachedSizeVec.X = length
            line._CachedSizeVec.Y = thickness
        end

        pcall(function()
            line.Slot:SetPosition(line._CachedPosVec)
            line.Slot:SetSize(line._CachedSizeVec)
            line.Widget:SetRenderAngle(angle)
        end)
    end
    ESP.UpdateSnapLine = esp_UpdateSnapLine

    local function esp_HideSnapLine(pawnKey)
        local line = ESP.LineWidgets[pawnKey]
        if line and line.Widget and isValidObject(line.Widget) and line.bVisible then
            line.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            line.bVisible = false
        end
    end
    ESP.HideSnapLine = esp_HideSnapLine

    -- =========================================================
    -- ENEMY COUNTER
    -- =========================================================
    local function esp_CreateEnemyCounter(canvas, layoutX, layoutY)
        local cd = ESP.CounterData
        if cd.Canvas ~= nil and cd.Canvas ~= canvas then -- [FIXED]
            for _, w in pairs({cd.ImgPlayer, cd.ImgBot, cd.TxtPlayer, cd.TxtBot, cd.SqPlayer, cd.SqBot}) do -- [FIXED]
                if w then removeWidget(w) end -- [FIXED]
            end -- [FIXED]
            cd.ImgPlayer, cd.SlotPlayer, cd.ImgBot, cd.SlotBot = nil, nil, nil, nil -- [FIXED]
            cd.TxtPlayer, cd.SlotTxtPlayer, cd.TxtBot, cd.SlotTxtBot = nil, nil, nil, nil -- [FIXED]
            cd.SqPlayer, cd.SqBot = nil, nil -- [FIXED]
            cd.PlayerLoaded, cd.BotLoaded = false, false -- [FIXED]
            cd.PlayerRetryCount, cd.BotRetryCount = 0, 0 -- [FIXED]
            cd.PlayerRetryMaxed, cd.BotRetryMaxed = nil, nil -- [FIXED]
        end -- [FIXED]
        cd.Canvas = canvas -- [FIXED]
        cd.Disposed = nil -- [FIXED]
        if cd.ImgPlayer and isValidObject(cd.ImgPlayer)
           and cd.ImgBot and isValidObject(cd.ImgBot) then
            return true
        end

        local imgPlayer, slotPlayer = makeImage(canvas, Vector2D(65, 36), nil)
        if slotPlayer then
            slotPlayer:SetAlignment(Vector2D(0.0, 0.0))
            slotPlayer:SetPosition(Vector2D(layoutX, layoutY))
            slotPlayer:SetZOrder(1005)
        end

        local imgBot, slotBot = makeImage(canvas, Vector2D(65, 36), nil)
        if slotBot then
            slotBot:SetAlignment(Vector2D(0.0, 0.0))
            slotBot:SetPosition(Vector2D(layoutX + 65, layoutY))
            slotBot:SetZOrder(1005)
        end

        local txtPlayer, slotTxtPlayer = makeText(canvas, whiteColor, 16, Vector2D(0.0, 0.5))
        if slotTxtPlayer then
            slotTxtPlayer:SetPosition(Vector2D(layoutX + 40, layoutY + 18))
            slotTxtPlayer:SetZOrder(1010)
        end

        local txtBot, slotTxtBot = makeText(canvas, whiteColor, 16, Vector2D(0.0, 0.5))
        if slotTxtBot then
            slotTxtBot:SetPosition(Vector2D(layoutX + 65 + 40, layoutY + 18))
            slotTxtBot:SetZOrder(1010)
        end

        -- Kick off icon downloads
        loadWidgetImage(imgPlayer, {}, "ic_danger_enemy.png", "Player", cd)   -- [USER REQUEST] online fetch OFF
        loadWidgetImage(imgBot,    {},             "ic_clear_boot.png",   "Bot",    cd)   -- [USER REQUEST] online fetch OFF

        cd.ImgPlayer = imgPlayer; cd.SlotPlayer = slotPlayer
        cd.ImgBot    = imgBot;    cd.SlotBot    = slotBot
        cd.TxtPlayer = txtPlayer; cd.SlotTxtPlayer = slotTxtPlayer
        cd.TxtBot    = txtBot;    cd.SlotTxtBot = slotTxtBot
        cd.bCreated  = true
        return true
    end
    ESP.CreateEnemyCounter = esp_CreateEnemyCounter

    local function esp_UpdateEnemyCounterDisplay(pc, bc, canvas, ox, oy)
        local cd = ESP.CounterData
        local show = _G.LexusConfig and _G.LexusConfig.EspV3_Count
        local hidden = UEnums.ESlateVisibility.Collapsed

        if not show then
            for _, w in pairs({cd.ImgPlayer, cd.ImgBot, cd.TxtPlayer, cd.TxtBot}) do
                if w and isValidObject(w) then
                    w:SetWidgetVisibility(hidden)
                end
            end
            return
        end

        if not esp_CreateEnemyCounter(canvas, ox, oy) then return end

        -- Retry downloads periodically (max 3 per icon) -- [FIXED]
        local now = os.clock()
        if not (cd.PlayerLoaded and cd.BotLoaded)
           and (now - cd.LastDownloadRetry) > 2.0 then
            cd.LastDownloadRetry = now
            if not cd.PlayerLoaded and cd.ImgPlayer then
                cd.PlayerRetryCount = (cd.PlayerRetryCount or 0) + 1 -- [FIXED]
                if cd.PlayerRetryCount <= 3 then -- [FIXED]
                    _edbg("ICON: retry Player " .. tostring(cd.PlayerRetryCount)) -- [FIXED]
                    loadWidgetImage(cd.ImgPlayer, playerIconURLs,
                        "ic_danger_enemy.png", "Player", cd)
                elseif not cd.PlayerRetryMaxed then -- [FIXED]
                    cd.PlayerRetryMaxed = true -- [FIXED]
                    _edbg("ICON: max retries reached Player") -- [FIXED]
                end -- [FIXED]
            end
            if not cd.BotLoaded and cd.ImgBot then
                cd.BotRetryCount = (cd.BotRetryCount or 0) + 1 -- [FIXED]
                if cd.BotRetryCount <= 3 then -- [FIXED]
                    _edbg("ICON: retry Bot " .. tostring(cd.BotRetryCount)) -- [FIXED]
                    loadWidgetImage(cd.ImgBot, botIconURLs,
                        "ic_clear_boot.png", "Bot", cd)
                elseif not cd.BotRetryMaxed then -- [FIXED]
                    cd.BotRetryMaxed = true -- [FIXED]
                    _edbg("ICON: max retries reached Bot") -- [FIXED]
                end -- [FIXED]
            end
        end

        pcall(function()
            if cd.SlotPlayer then
                cd.SlotPlayer:SetSize(Vector2D(65, 36))
                cd.SlotPlayer:SetPosition(Vector2D(ox, oy))
            end
            if cd.SlotBot then
                cd.SlotBot:SetSize(Vector2D(65, 36))
                cd.SlotBot:SetPosition(Vector2D(ox + 65, oy))
            end
            if cd.SlotTxtPlayer then
                cd.SlotTxtPlayer:SetPosition(Vector2D(ox + 40, oy + 18))
            end
            if cd.SlotTxtBot then
                cd.SlotTxtBot:SetPosition(Vector2D(ox + 65 + 40, oy + 18))
            end

            if cd.LastPlayerCount ~= pc and cd.TxtPlayer and isValidObject(cd.TxtPlayer) then
                cd.TxtPlayer:SetText(tostring(pc))
                cd.LastPlayerCount = pc
            end
            if cd.LastBotCount ~= bc and cd.TxtBot and isValidObject(cd.TxtBot) then
                cd.TxtBot:SetText(tostring(bc))
                cd.LastBotCount = bc
            end

            local vis = UEnums.ESlateVisibility.SelfHitTestInvisible
            local hidden = UEnums.ESlateVisibility.Collapsed
            for _, w in pairs({cd.TxtPlayer, cd.TxtBot}) do
                if w and isValidObject(w) then w:SetWidgetVisibility(vis) end
            end
            if cd.ImgPlayer and isValidObject(cd.ImgPlayer) then
                cd.ImgPlayer:SetWidgetVisibility(cd.PlayerLoaded and vis or hidden)
            end
            if cd.ImgBot and isValidObject(cd.ImgBot) then
                cd.ImgBot:SetWidgetVisibility(cd.BotLoaded and vis or hidden)
            end
        end)
    end
    ESP.UpdateEnemyCounterDisplay = esp_UpdateEnemyCounterDisplay

    -- =========================================================
    -- SHOW / HIDE WIDGET
    -- =========================================================
    local function esp_HideWidget(widget)
        if not widget then return end
        widget.bVisible = false
        local vis = UEnums.ESlateVisibility.Collapsed
        for _, key in ipairs({
            "CornerContainer", "BgWidget", "HealthWidget",
            "WeaponWidget", "FlagWidget", "NameWidget",
            "DistWidget", "StateWidget"
        }) do
            local w = widget[key]
            if w and isValidObject(w) then w:SetWidgetVisibility(vis) end
        end
    end
    ESP.HideWidget = esp_HideWidget

    local function esp_ShowWidget(widget)
        if not widget then return end
        widget.bVisible = true
        local vis   = UEnums.ESlateVisibility.SelfHitTestInvisible
        local hide  = UEnums.ESlateVisibility.Collapsed
        local cfg   = _G.LexusConfig or {}

        local function setVis(w, enabled)
            if w and isValidObject(w) then w:SetWidgetVisibility(enabled and vis or hide) end
        end

        setVis(widget.CornerContainer, cfg.EspV3_Box)
        setVis(widget.BgWidget,        cfg.EspV3_Health)
        setVis(widget.HealthWidget,    cfg.EspV3_Health)
        setVis(widget.WeaponWidget,    cfg.EspV3_Weapon)
        setVis(widget.FlagWidget,      cfg.EspV3_Flag)
        setVis(widget.NameWidget,      cfg.EspV3_Name)
        setVis(widget.DistWidget,      cfg.EspV3_Dist)
        setVis(widget.StateWidget,     cfg.EspV3_State)
    end
    ESP.ShowWidget = esp_ShowWidget

    local function esp_ClearESP() -- [FIXED]
        do -- [FIXED]
            local cd0 = ESP.CounterData -- [FIXED]
            local keep = {} -- [FIXED]
            if cd0 then -- [FIXED]
                for _, w in pairs({cd0.ImgPlayer, cd0.ImgBot, cd0.TxtPlayer, cd0.TxtBot, cd0.SqPlayer, cd0.SqBot}) do -- [FIXED]
                    if w then keep[w] = true end -- [FIXED]
                end -- [FIXED]
            end -- [FIXED]
            for widget in pairs(ESP.OwnedWidgets) do -- [FIXED]
                if not keep[widget] then removeWidget(widget) end -- [FIXED]
            end -- [FIXED]
        end -- [FIXED]
        ESP.OwnedWidgets = {}
        ESP.LocalPawn = nil
        ESP._CanvasScaleX, ESP._CanvasScaleY = 1, 1
        ESP._CanvasOffsetX, ESP._CanvasOffsetY = 0, 0
        ESP._LastTransformTime, ESP._LastHeavyUpdateTime, ESP._LastVisCheckTime = -math.huge, -math.huge, -math.huge
        ESP.BoxWidgets  = {}
        ESP.LineWidgets = {}
        do -- [FIXED]
            local cd = ESP.CounterData -- [FIXED]
            if cd then -- [FIXED]
                for _, w in pairs({cd.ImgPlayer, cd.ImgBot, cd.TxtPlayer, cd.TxtBot, cd.SqPlayer, cd.SqBot}) do -- [FIXED]
                    if w and isValidObject(w) then -- [FIXED]
                        pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) -- [FIXED]
                    end -- [FIXED]
                end -- [FIXED]
                cd.PlayerLoaded = false -- [FIXED]
                cd.BotLoaded = false -- [FIXED]
                cd.PlayerRetryCount = 0 -- [FIXED]
                cd.BotRetryCount = 0 -- [FIXED]
                cd.PlayerRetryMaxed = nil -- [FIXED]
                cd.BotRetryMaxed = nil -- [FIXED]
                cd.LastPlayerCount = -1 -- [FIXED]
                cd.LastBotCount = -1 -- [FIXED]
                cd.LastDownloadRetry = 0 -- [FIXED]
                cd.bCreated = false -- [FIXED]
            end -- [FIXED]
        end -- [FIXED]
        ESP.ESPCanvas   = nil
        ESP._LastCanvas = nil
        ESP._VisCheckCache = {}
    end
    ESP.ClearESP = esp_ClearESP

    -- =========================================================
    -- MAIN TICK: esp_UpdateESP
    -- =========================================================
    local function esp_UpdateESP()
        if not (_G.LexusConfig and _G.LexusConfig.EspV3_Master) then
            esp_ClearESP()
            return
        end

        local canvas = esp_GetMainCanvas()
        if not canvas then esp_ClearESP(); return end

        local GameplayData = package.loaded["GameLua.GameCore.Data.GameplayData"]
                            or _G.GameplayData
        if not GameplayData then esp_ClearESP(); return end

        local pc = GameplayData.GetPlayerController and GameplayData.GetPlayerController()
        if not isValidObject(pc) then esp_ClearESP(); return end
        local localPawn = pc.GetPlayerCharacterSafety and pc:GetPlayerCharacterSafety()
        if not isValidObject(localPawn) and GameplayData.GetPlayerCharacter then
            localPawn = GameplayData.GetPlayerCharacter()
        end
        if not isValidObject(localPawn) then esp_ClearESP(); return end
        local now = os.clock and os.clock() or 0
        if ESP._LastCanvas ~= canvas or ESP.LocalPawn ~= localPawn then
            esp_ClearESP()
            ESP._LastCanvas = canvas
            ESP.ESPCanvas = canvas
            ESP.LocalPawn = localPawn
        end

        -- Device-adaptive governor: tick cost napo, har 2s me tier decide karo
        -- Tier 0=Smooth (high-end) 1=Balanced 2=Performance (low-end, lag-free)
        local tickMs = 0
        if (ESP._LastTickTime or 0) > 0 then
            tickMs = (now - ESP._LastTickTime) * 1000
            if tickMs < 0 or tickMs > 500 then tickMs = 0 end
            ESP._AvgTickMs = (ESP._AvgTickMs or 0) * 0.9 + tickMs * 0.1
        end
        ESP._LastTickTime = now

        local qMode = (_G.LexusConfig and _G.LexusConfig.EspV3_Quality) or "Auto"
        local tier = ESP._AdaptiveTier or 0
        if qMode == "Smooth" then tier = 0
        elseif qMode == "Balanced" then tier = 1
        elseif qMode == "Performance" then tier = 2
        elseif (now - (ESP._TierCheckTime or 0)) > 2.0 then
            ESP._TierCheckTime = now
            if (ESP._AvgTickMs or 0) > 25 and tier < 2 then tier = tier + 1
            elseif (ESP._AvgTickMs or 0) < 12 and tier > 0 then tier = tier - 1 end
        end
        ESP._AdaptiveTier = tier

        -- Tier ke hisab se intervals + render limits (low-end pe kam kaam = no lag)
        local transformInt, heavyInt, visInt = 0.25, 0.15, 0.12
        ESP._MaxDist, ESP._MaxTargets = 350, 40
        if tier == 1 then
            transformInt, heavyInt, visInt = 0.4, 0.25, 0.2
            ESP._MaxDist, ESP._MaxTargets = 350, 30
        elseif tier == 2 then
            transformInt, heavyInt, visInt = 0.6, 0.4, 0.3
            ESP._MaxDist, ESP._MaxTargets = 350, 20
        end
        -- NOTE: MAX 350m — har tier me 350m tak har bande ki line draw hogi (user demand)

        -- Throttled transforms
        if (now - ESP._LastTransformTime) > transformInt then
            esp_UpdateCanvasTransform(pc)
            ESP._LastTransformTime = now
        end

        local heavyUpdate = (now - ESP._LastHeavyUpdateTime) > heavyInt
        local visCheck    = (now - ESP._LastVisCheckTime)   > visInt
        if heavyUpdate then ESP._LastHeavyUpdateTime = now end
        if visCheck    then ESP._LastVisCheckTime    = now end

        local snapX, snapY = esp_GetSnapLineStartPos(pc, canvas)

        local myTeam = localPawn.TeamID
            or (localPawn.GetTeamID and localPawn:GetTeamID())
            or 0

        local pawns, seenObjects, seenKeys = {}, {}, {}
        local function merge(list)
            if not list then return end
            for _, pawn in pairs(list) do
                if isValidObject(pawn) and not seenObjects[pawn] then
                    local key
                    pcall(function()
                        key = pawn.PlayerKey
                        if not key and pawn.GetPlayerKey then key = pawn:GetPlayerKey() end
                    end)
                    if key == 0 or key == "0" or key == "" then key = nil end
                    if key ~= nil then key = tostring(key) end
                    if not key or not seenKeys[key] then
                        seenObjects[pawn] = true
                        if key then seenKeys[key] = true end
                        pawns[#pawns + 1] = pawn
                    end
                end
            end
        end
        local function collect(object, name)
            if not object then return end
            local ok, result = pcall(function() return object[name](object) end)
            if not ok or result == nil then
                ok, result = pcall(function() return object[name]() end)
            end
            if ok and result then merge(result) end
        end
        collect(Game, "GetAllPlayerPawns")
        collect(GameplayData, "GetAllPlayerCharacters")
        merge(GameplayData.GameCharacters)
        ESP.ActorCount = #pawns

        for _, widget in pairs(ESP.BoxWidgets) do esp_HideWidget(widget) end
        for key in pairs(ESP.LineWidgets) do esp_HideSnapLine(key) end
        local alive = {}
        local playerCount, botCount = 0, 0
        local rendered = 0 -- adaptive cap: is tick me kitne box/line render hue

        for key, pawn in pairs(pawns) do
            if isValidObject(pawn) and pawn ~= localPawn then
                local team = pawn.TeamID
                    or (pawn.GetTeamID and pawn:GetTeamID())
                    or -1

                local hp = pawn.Health or 0
                local aliveCheck = readBool(pawn, "IsAlive", nil)
                if aliveCheck == nil then
                    aliveCheck = not readBool(pawn, "bDead", false)
                        and (hp > 0 or readBool(pawn, "bIsKnocked", false)
                            or readBool(pawn, "IsKnocked", false))
                end

                if aliveCheck and team ~= myTeam then
                    local pawnKey = pawn -- actor identity; array indexes are unstable
                    alive[pawnKey] = true

                    -- [FIX] bot detection: SIRF reliable flags (pehle Game:IsAI + naam
                    -- heuristic real players ko bhi bot maan rahe the -> ulta count)
                    local isBot = (pawn.bIsAI == true) or (pawn.bIsAIBot == true) or (pawn.bIsABot == true) or (pawn.bIsBot == true)
                    if not isBot then pcall(function()
                        if type(pawn.IsAIBot) == "function" then isBot = (pawn:IsAIBot() == true) end
                    end) end
                    if not isBot then pcall(function()
                        local ps = pawn.PlayerState or (type(pawn.GetPlayerState) == "function" and pawn:GetPlayerState()) or nil
                        if ps and (ps.bIsABot == true or ps.bIsBot == true) then isBot = true end
                    end) end
                    if isBot then botCount = botCount + 1
                    else           playerCount = playerCount + 1 end

                    -- Adaptive cull: counter me sab count honge, par box/line
                    -- sirf paas walo + limit tak render honge (low-end pe no lag)
                    local pawnDist = -1
                    pcall(function()
                        if localPawn.GetDistanceTo then
                            pawnDist = math.floor(localPawn:GetDistanceTo(pawn) / 100.0)
                        end
                    end)
                    local renderThis = (pawnDist < 0 or pawnDist <= (ESP._MaxDist or 500))
                    if renderThis then
                        if rendered < (ESP._MaxTargets or 30) then
                            rendered = rendered + 1
                        else
                            renderThis = false
                        end
                    end
                    if not renderThis then
                        local oldW = ESP.BoxWidgets[pawnKey]
                        if oldW then esp_HideWidget(oldW) end
                        esp_HideSnapLine(pawnKey)
                    end

                    local loc = pawn.K2_GetActorLocation
                                and pawn:K2_GetActorLocation()
                    if not loc and pawn.RootComponent then
                        loc = pawn.RootComponent:K2_GetComponentLocation()
                    end

                    if renderThis and loc then
                        local mesh = pawn.Mesh
                            or (pawn.GetMesh and pawn:GetMesh())
                            or pawn.CharacterMesh0

                        local headPos, rootPos

                        if mesh and mesh.GetSocketLocation then
                            local h = mesh:GetSocketLocation("Head")
                            if not h or (h.X == 0 and h.Y == 0 and h.Z == 0) then
                                h = mesh:GetSocketLocation("head")
                            end
                            if h and not (h.X == 0 and h.Y == 0 and h.Z == 0) then
                                headPos = Vector(h.X, h.Y, h.Z + 15)
                            end

                            local r = mesh:GetSocketLocation("root")
                            if not r or (r.X == 0 and r.Y == 0 and r.Z == 0) then
                                r = mesh:GetSocketLocation("Root")
                            end
                            if r and not (r.X == 0 and r.Y == 0 and r.Z == 0) then
                                rootPos = r
                            end
                        end

                        -- Pose detection
                        local isProne  = readBool(pawn, "bIsProning", false)
                                         or readBool(pawn, "bIsProne", false)
                                         or readBool(pawn, "IsProne", false)
                                         or pawn.PoseState == 2
                                         or pawn.PoseState == "Prone"
                        local isCrouch = readBool(pawn, "bIsCrouched", false)
                                         or readBool(pawn, "IsCrouched", false)
                                         or pawn.PoseState == 1
                                         or pawn.PoseState == "Crouch"

                        if not headPos or not rootPos then
                            local headOff = isProne and 18 or (isCrouch and 50 or 88)
                            local rootOff = isProne and -22 or (isCrouch and -68 or -90)
                            if not headPos then
                                headPos = Vector(loc.X, loc.Y, loc.Z + headOff)
                            end
                            if not rootPos then
                                rootPos = Vector(loc.X, loc.Y, loc.Z + rootOff)
                            end
                        end

                        local ok1, headX, headY =
                            esp_ProjectWorldToCanvasLocal(pc, headPos)
                        local ok2, rootX, rootY =
                            esp_ProjectWorldToCanvasLocal(pc, rootPos)

                        local widget = ESP.BoxWidgets[pawnKey]
                        if not (widget and isValidObject(widget.CornerContainer)) then
                            widget = esp_CreateESPWidget(canvas)
                            if widget then ESP.BoxWidgets[pawnKey] = widget end
                        end

                        if widget and isValidObject(widget.CornerContainer) then
                            if ok1 and ok2 then
                                -- Geometry
                                local height = math.max(28, math.abs(rootY - headY))
                                local scale = isProne and 1.1 or (isCrouch and 0.7 or 0.55)
                                local width  = math.max(15, height * scale)

                                local cx     = (headX + rootX) * 0.5
                                local cy     = (rootY + headY) * 0.5
                                local top    = cy - height * 0.5
                                local bottom = cy + height * 0.5

                                esp_UpdateCornerDimensions(widget, width, height)
                                widget.CornerSlot:SetPosition(Vector2D(cx, cy))
                                esp_ShowWidget(widget)

                                -- Health bar
                                local barW = ESP.HealthBarWidth or 2.0
                                local barX = (cx - width * 0.5) - 2.5 - barW * 0.5

                                local hpNow = pawn.Health
                                              or (pawn.GetHealth and pawn:GetHealth())
                                              or 100
                                local hpMax = pawn.HealthMax
                                              or (pawn.GetHealthMax and pawn:GetHealthMax())
                                              or 100
                                if hpMax <= 0 then hpMax = 100 end

                                local pct    = math.max(0, math.min(1, hpNow / hpMax))
                                local fillH  = height * pct

                                widget.BgSlot:SetSize(Vector2D(barW, height))
                                widget.BgSlot:SetPosition(Vector2D(barX, bottom))
                                widget.HealthSlot:SetSize(Vector2D(barW, fillH))
                                widget.HealthSlot:SetPosition(Vector2D(barX, bottom))

                                -- Weapon (cached)
                                if _G.LexusConfig.EspV3_Weapon and (heavyUpdate or widget._cachedWeapon == "") then
                                    local weaponName = "Fist"
                                    local w = (pawn.GetCurrentWeapon and pawn:GetCurrentWeapon())
                                          or (pawn.GetCurrentShootWeapon and pawn:GetCurrentShootWeapon())
                                          or (pawn.WeaponManagerComponent
                                              and pawn.WeaponManagerComponent.CurrentWeaponReplicated)

                                    if w and isValidObject(w) then
                                        local raw
                                        if type(w.GetWeaponName) == "function" then
                                            raw = w:GetWeaponName()
                                        end
                                        if not raw then raw = w.WeaponName end
                                        if raw and raw ~= "" then
                                            weaponName = tostring(raw)
                                                :gsub("^BP_", "")
                                                :gsub("_C$", "")
                                                :gsub("_Wrapper$", "")
                                        end
                                    end

                                    if widget._cachedWeapon ~= weaponName then
                                        widget.WeaponWidget:SetText(weaponName)
                                        widget._cachedWeapon = weaponName
                                    end
                                end
                                widget.WeaponSlot:SetPosition(Vector2D(cx, top - 3.5))

                                -- Nation flag (cached)
                                if _G.LexusConfig.EspV3_Flag and (heavyUpdate or not widget._cachedNation) then
                                    local nation = (pawn.PlayerState and pawn.PlayerState.Nation)
                                                or pawn.Nation or ""
                                    nation = tostring(nation)
                                    if nation == "" or nation == "nil" or nation == "0" then
                                        nation = "G1"
                                    end

                                    if widget._cachedNation ~= nation then
                                        local resPath
                                        if CDataTable and CDataTable.GetTableData then
                                            local d = CDataTable.GetTableData("RegionConfig", nation)
                                            if d and d.res_path and d.res_path ~= "" then
                                                resPath = d.res_path
                                            end
                                        end
                                        if not resPath then
                                            resPath = "/Game/UMG/Texture/Atlas/NationalflagUI/Frames/T_icon_flag_iland_png.T_icon_flag_iland_png"
                                        end

                                        if widget.FlagWidget and isValidObject(widget.FlagWidget) then
                                            local applied = false
                                            if widget.FlagWidget.SetBrushResourceFromPathSync then
                                                widget.FlagWidget:SetBrushResourceFromPathSync(resPath, false)
                                                applied = true
                                            end
                                            if not applied and widget.FlagWidget.SetBrushFromPathAsync then
                                                widget.FlagWidget:SetBrushFromPathAsync(resPath, false)
                                                applied = true
                                            end
                                            if not applied then
                                                local util = package.loaded["client.slua_ui_framework.util"]
                                                if util and util.SetTexture then
                                                    util.SetTexture(widget.FlagWidget, resPath, { sync = true })
                                                    applied = true
                                                end
                                            end
                                            if not applied then
                                                local assetUtil = package.loaded["common.asset_util"]
                                                local tex = assetUtil and assetUtil.GetAssetSync
                                                            and assetUtil.GetAssetSync(resPath)
                                                if not tex and CGame and CGame.LoadObject then
                                                    tex = CGame:LoadObject(resPath)
                                                end
                                                if tex and widget.FlagWidget.SetBrushFromTexture then
                                                    widget.FlagWidget:SetBrushFromTexture(tex, false)
                                                end
                                            end
                                        end
                                        widget._cachedNation = nation
                                    end
                                end
                                if widget.FlagSlot then
                                    widget.FlagSlot:SetPosition(Vector2D(cx, top - 22.0))
                                end

                                -- Name (cached)
                                if heavyUpdate or widget._cachedName == "" then
                                    local name
                                    if isBot then
                                        name = "Bot"
                                    else
                                        name = pawn.PlayerName
                                            or pawn.PlayerNamePublic
                                            or (pawn.GetPlayerName and pawn:GetPlayerName())
                                            or "Player"
                                    end
                                    name = tostring(name)
                                    if widget._cachedName ~= name then
                                        widget.NameWidget:SetText(name)
                                        widget._cachedName = name
                                    end
                                end
                                widget.NameSlot:SetPosition(Vector2D(cx, bottom + 4.0))

                                -- Distance
                                local dist = math.floor(localPawn:GetDistanceTo(pawn) / 100.0)
                                local distStr = tostring(dist) .. "m"
                                if widget._cachedDist ~= distStr then
                                    widget.DistWidget:SetText(distStr)
                                    widget._cachedDist = distStr
                                end
                                widget.DistSlot:SetPosition(Vector2D(cx, bottom + 20.5))

                                -- Visibility (throttled)
                                if visCheck or ESP._VisCheckCache[pawnKey] == nil then
                                    local vis = pc.LineOfSightTo and pc:LineOfSightTo(pawn) or false
                                    ESP._VisCheckCache[pawnKey] = vis
                                end
                                local visible = ESP._VisCheckCache[pawnKey]

                                -- State (cached)
                                if heavyUpdate or widget._cachedState == "" then
                                    local isKnocked = readBool(pawn, "bIsKnocked", false)
                                        or readBool(pawn, "IsKnocked", false)

                                    local stateText, stateColor
                                    if isKnocked then
                                        stateText, stateColor = "Knocked", redSlateColor
                                    elseif not visible then
                                        stateText, stateColor = "Cover", redSlateColor
                                    else
                                        stateText, stateColor = "Open", greenSlateColor
                                    end

                                    if widget._cachedState ~= stateText then
                                        widget.StateWidget:SetText(stateText)
                                        safeSetColor(widget.StateWidget, stateColor)
                                        widget._cachedState = stateText
                                    end
                                end
                                widget.StateSlot:SetPosition(Vector2D(cx, bottom + 37.0))

                                -- Snap line: 250m tak HAR bande pe draw, jitna door utni halki-patli
                                -- 50m=dark Full | 100m=0.8 | 150m=0.65 | 200m=0.5 | 250m=0.35 faintest
                                if _G.LexusConfig.EspV3_Line then
                                    local lineColor = visible and greenColor or redColor
                                    local thin, alpha, band = 1.0, 1.0, "n"
                                    if dist >= 200 then band, thin, alpha = "x", 0.6, 0.35
                                    elseif dist >= 150 then band, thin, alpha = "f", 0.7, 0.5
                                    elseif dist >= 100 then band, thin, alpha = "m", 0.8, 0.65
                                    elseif dist >= 50 then band, thin, alpha = "q", 0.9, 0.8 end
                                    if band ~= "n" then
                                        -- Color sirf tab banao jab band/visible badle (har tick garbage nahi)
                                        local fkey = (visible and "v" or "h") .. band
                                        if widget._LineFadeKey ~= fkey then
                                            widget._LineFadeKey = fkey
                                            widget._LineFadeColor = nil
                                            pcall(function()
                                                if LinearColor then
                                                    if visible then
                                                        widget._LineFadeColor = LinearColor(0.0, 1.0, 0.05, alpha)
                                                    else
                                                        widget._LineFadeColor = LinearColor(1.0, 0.15, 0.15, alpha)
                                                    end
                                                end
                                            end)
                                        end
                                        if widget._LineFadeColor then
                                            lineColor = widget._LineFadeColor
                                        end
                                    elseif widget._LineFadeKey ~= nil then
                                        widget._LineFadeKey = nil
                                        widget._LineFadeColor = nil
                                    end
                                    esp_UpdateSnapLine(pawnKey, cx, top,
                                        snapX, snapY, lineColor, canvas, thin)
                                else
                                    esp_HideSnapLine(pawnKey)
                                end
                            else
                                esp_HideWidget(widget)
                                esp_HideSnapLine(pawnKey)
                            end
                        end
                    end
                end
            end
        end

        -- Hide widgets for dead/removed pawns
        for key, w in pairs(ESP.BoxWidgets) do
            if not alive[key] then
                removeBox(w)
                ESP.BoxWidgets[key] = nil
                ESP._VisCheckCache[key] = nil
            end
        end
        for key, _ in pairs(ESP.LineWidgets) do
            if not alive[key] then
                removeWidget(ESP.LineWidgets[key].Widget)
                ESP.LineWidgets[key] = nil
                ESP._VisCheckCache[key] = nil
            end
        end

        -- Enemy counter
        local counterY = snapY - counterTextSize - 2
        if counterY < 10 then counterY = 48 end
        -- Dono icons ka total width = 130, isliye center se 65 left shift
        esp_UpdateEnemyCounterDisplay(playerCount, botCount, canvas, snapX - 65, counterY)
    end
    ESP.UpdateESP = esp_UpdateESP

    return ESP
end

return LoadESPV3System
end)()
local B = {Renderer=nil, Status=0, LastError=nil, Disposed=false, RetryAt=0}
local defaults = {
    EspV3_Master=false, EspV3_Count=true, EspV3_Box=true, EspV3_Line=true,
    EspV3_Health=true, EspV3_Name=true, EspV3_Dist=true, EspV3_Weapon=true,
    EspV3_Flag=true, EspV3_State=true,
}
local function boolean(v)
    if v==true or v==1 or v=='true' or v=='1' then return true end
    if v==false or v==0 or v=='false' or v=='0' then return false end
end
local function config()
    _G.LexusConfig = _G.LexusConfig or {}
    local c=_G.LexusConfig
    for key,default in pairs(defaults) do
        local v=boolean(c[key]); if v==nil then v=default end; c[key]=v
    end
    return c
end
local function save() if _G.SaveModSettings then pcall(_G.SaveModSettings) end end
local notifier
local allowed=function() return true end
function B.SetAllowed(fn) allowed=fn end
function B.SetNotifier(fn) notifier=fn end
local function status(code)
    B.Status=code
    config().EspV3_RuntimeStatus=({[0]='OFF',[1]='WAITING',[2]='READY',[3]='ERROR',[4]='BLOCKED'})[code]
end
local function report(phase,message)
    message=phase..': '..tostring(message)
    config().EspV3_LastError=message
    config().EspV3_DiagnosticBuild='R4'
    local changed=B.LastError~=message
    B.LastError=message
    status(3)
    if changed then
        if print then print('[ESP V3 R4] '..message) end
        if notifier then pcall(notifier,'ESP V3 R4: '..message) end
        save() -- Exact error survives leaving the menu, even if notifications fail.
    end
end
local function clear()
    if B.Renderer and B.Renderer.ClearESP then
        local ok,err=pcall(B.Renderer.ClearESP)
        if not ok then report('cleanup',err) end
    end
end
function B.Stop()
    B.TimerGeneration=(B.TimerGeneration or 0)+1
    B.TimerPending=false
    clear(); status(0)
end
function B.Dispose() B.Disposed=true; B.Stop(); B.Renderer=nil end
function B.Get(key) return config()[key] end
function B.Update()
    if B.Disposed then return false end
    if not config().EspV3_Master then
        if B.Status~=0 then B.Stop() end
        return false
    end
    if not allowed() then
        clear(); status(4)
        return false
    end
    local now=os.clock()
    if now<B.RetryAt then return false end
    if not B.Renderer then
        local ok,renderer=pcall(initializeRenderer)
        if not ok or type(renderer)~='table' then
            B.RetryAt=now+3
            report('initialize',renderer or 'No renderer returned')
            return false
        end
        B.Renderer=renderer
    end
    local ok,err=pcall(B.Renderer.UpdateESP)
    if not ok then
        clear()
        B.RetryAt=now+3
        report('render',err)
        return false
    end
    status(B.Renderer.LocalPawn and 2 or 1)
    return true
end
-- Supervised by the already-working base loop; never starts native rendering in a menu callback.
function B.Pump()
    if B.Disposed then return false end
    if not config().EspV3_Master or not allowed() then
        if B.TimerPending then
            B.TimerGeneration=(B.TimerGeneration or 0)+1
            B.TimerPending=false
        end
        return B.Update()
    end
    local now=os.clock()
    if B.TimerPending and now-(B.LastTimerBeat or now)<1.0 then return true end
    -- A missing/stalled scheduler falls back to the base loop rather than killing V3.
    B.TimerGeneration=(B.TimerGeneration or 0)+1
    local generation=B.TimerGeneration
    B.TimerPending=false
    B.Update()
    local ok,ticker=pcall(require,'common.time_ticker')
    if not ok or not ticker or type(ticker.AddTimerOnce)~='function' then return false end
    local tick
    tick=function()
        if B.Disposed or B.TimerGeneration~=generation then return end
        B.TimerPending=false
        B.LastTimerBeat=os.clock()
        B.Update()
        if B.Disposed or not config().EspV3_Master or not allowed() then return end
        local scheduled=pcall(ticker.AddTimerOnce,0.05,tick)
        B.TimerPending=scheduled
    end
    B.LastTimerBeat=now
    local scheduled=pcall(ticker.AddTimerOnce,0.05,tick)
    B.TimerPending=scheduled
    return scheduled
end
function B.Start()
    if B.Disposed then return false end
    if config().EspV3_Master then status(1) end
    return true
end
function B.Set(key,value)
    if B.Disposed or defaults[key]==nil then return false end
    local normalized=boolean(value)
    if normalized==nil then report('menu','Unsupported value '..tostring(value)); return false end
    config()[key]=normalized
    if key=='EspV3_Master' then
        B.RetryAt=0
        if normalized then B.Start() else B.Stop() end
    elseif B.Renderer then
        local renderer=B.Renderer
        local ok,err=pcall(function()
            for _,widget in pairs(renderer.BoxWidgets) do
                if widget.bVisible then renderer.ShowWidget(widget) end
            end
            if key=='EspV3_Line' and not normalized then
                for actor in pairs(renderer.LineWidgets) do renderer.HideSnapLine(actor) end
            end
            if key=='EspV3_Count' and not normalized then
                -- The disabled branch hides existing counter widgets without creating any.
                renderer.UpdateEnemyCounterDisplay(0,0,nil,0,0)
            end
        end)
        if not ok then report('toggle visibility',err) end
    end
    save()
    return true -- accepted setting, not a claim of successful rendering
end
function B.OnEndPlay(character)
    local pawn=B.Renderer and B.Renderer.LocalPawn
    if pawn and (pawn==character or pawn==character.Object) then
        clear(); status(config().EspV3_Master and 1 or 0)
    end
end
local previous=_G.ESPV3Bridge
if previous and type(previous.Dispose)=='function' then pcall(previous.Dispose) end
_G.ESPV3Bridge=B
config().EspV3_DiagnosticBuild='R4'
status(config().EspV3_Master and 1 or 0)
return B

end)()
ESPV3Bridge.SetNotifier(function(msg)
    pcall(function()
        local _f = io.open("/storage/emulated/0/Android/data/com.pubg.imobile/files/espv3_dbg.txt", "a")
        if _f then _f:write("espR4 " .. tostring(msg) .. string.char(10)) _f:close() end
    end)
end)

    _G._espV3Gen = 0
    _G.StartESPV3 = function()
        _G._espV3Gen = (_G._espV3Gen or 0) + 1
        local gen = _G._espV3Gen
        pcall(function()
            local function EspV3Tick()
                if gen ~= _G._espV3Gen then return end
                pcall(function()
                    local tt = require("common.time_ticker")
                    if tt and tt.AddTimerOnce then tt.AddTimerOnce(0.05, EspV3Tick) end
                end)
                if _G.ESPV3Bridge and _G.ESPV3Bridge.Pump then
                    local _ok, _err = pcall(_G.ESPV3Bridge.Pump)
                    if not _ok then
                        _G._espV3Err = (_G._espV3Err or 0) + 1
                        if _G._espV3Err <= 3 then
                            pcall(function()
                                local _f1 = io.open("/storage/emulated/0/Android/data/com.pubg.imobile/files/espv3_dbg.txt", "a")
                                if _f1 then _f1:write("tickerr " .. tostring(_err) .. string.char(10)) _f1:close() end
                            end)
                        end
                    end
                end
            end
            local how = "none"
            local tt0 = nil
            pcall(function() tt0 = require("common.time_ticker") end)
            if tt0 and tt0.AddTimerOnce then
                tt0.AddTimerOnce(0.05, EspV3Tick)
                how = "tt"
                _G._espV3Timer = true
            elseif _G.Game and _G.Game.AddGameTimer then
                _G._espV3Timer = _G.Game:AddGameTimer(0.07, true, EspV3Tick)
            elseif slua_GameFrontendHUD then
                local pc = slua_GameFrontendHUD:GetPlayerController()
                if Valid(pc) and type(pc.AddGameTimer) == "function" then
                    _G._espV3Timer = pc:AddGameTimer(0.07, true, EspV3Tick)
                end
            end
            pcall(function()
                local _f2 = io.open("/storage/emulated/0/Android/data/com.pubg.imobile/files/espv3_dbg.txt", "a")
                if _f2 then _f2:write("timer " .. tostring(how) .. string.char(10)) _f2:close() end
            end)
        end)
    end
    pcall(function() if _G.StartESPV3 then _G.StartESPV3() end end)
local _cached_linear_color = nil
local _cached_skeletal_mesh = nil
local _cached_gameplay_data = nil

local function getCachedLinearColor()
    if _cached_linear_color == nil then _cached_linear_color = import("LinearColor") or _G.FLinearColor end
    return _cached_linear_color
end

local function getCachedSkeletalMesh()
    if _cached_skeletal_mesh == nil then _cached_skeletal_mesh = import("SkeletalMeshComponent") end
    return _cached_skeletal_mesh
end

local function getCachedGameplayData()
    if _cached_gameplay_data == nil then
        local ok, mod = pcall(require, "GameLua.GameCore.Data.GameplayData")
        if ok then _cached_gameplay_data = mod end
    end
    return _cached_gameplay_data
end

local function GetSafeEnemyKey(enemy)
    if Valid(enemy) then
        if enemy.PlayerKey then return tostring(enemy.PlayerKey) end
        if type(enemy.GetUniqueID) == "function" then return tostring(enemy:GetUniqueID()) end
    end
    return tostring(enemy)
end

local function CheckIsAI(pawn, markData)
    if markData.AK_IS_BOT ~= nil then return markData.AK_IS_BOT, true end
    local isAI = false
    local hasChecked = false
    pcall(function()
        if pawn.bIsAI == true or pawn.IsAI == true then isAI = true; hasChecked = true end
        if type(pawn.IsBot) == "function" and pawn:IsBot() then isAI = true; hasChecked = true end
        local pState = pawn.PlayerState or (type(pawn.GetPlayerState) == "function" and pawn:GetPlayerState())
        if Valid(pState) then
            hasChecked = true
            if pState.bIsABot == true or pState.bIsBot == true then isAI = true end
            if type(pState.IsBot) == "function" and pState:IsBot() then isAI = true end
        end
    end)
    if hasChecked then markData.AK_IS_BOT = isAI end
    return isAI, hasChecked
end

local function GetAllSkeletalMeshes(enemy, markData)
    local curTime = os.clock()
    if markData and markData.CachedMeshes and markData.CachedMeshTime and (curTime - markData.CachedMeshTime < 0.5) then
        local validMeshes = {}
        for _, cachedMesh in ipairs(markData.CachedMeshes) do
            local isPendingKill = false
            pcall(function() if type(cachedMesh.IsPendingKill) == "function" then isPendingKill = cachedMesh:IsPendingKill() end end)
            if Valid(cachedMesh) and not isPendingKill then table.insert(validMeshes, cachedMesh) end
        end
        markData.CachedMeshes = validMeshes
        return validMeshes
    end
    local meshes = {}
    if Valid(enemy.Mesh) then table.insert(meshes, enemy.Mesh) end
    pcall(function()
        local SkeletalMeshClass = getCachedSkeletalMesh()
        if SkeletalMeshClass and type(enemy.GetComponentsByClass) == "function" then
            local childs = enemy:GetComponentsByClass(SkeletalMeshClass)
            if childs then
                local count = type(childs.Num) == "function" and childs:Num() or #childs
                for i = 1, count do
                    local comp = type(childs.Get) == "function" and childs:Get(i-1) or childs[i]
                    if Valid(comp) and comp ~= enemy.Mesh then table.insert(meshes, comp) end
                end
            end
        end
    end)
    if markData then markData.CachedMeshes = meshes; markData.CachedMeshTime = curTime end
    return meshes
end

local function InitFakeHWID()
    pcall(function()
        local SystemLib = import("KismetSystemLibrary")
        if SystemLib and not _G.FakeHWID_Hooked then
            _G.Original_GetDeviceId = SystemLib.GetDeviceId
            SystemLib.GetDeviceId = function(...)
                if _G.LexusConfig.FakeHWID then
                    if not _G.FakeHWID_String then
                        local chars = "0123456789ABCDEF"
                        local hwid = ""
                        for i = 1, 32 do
                            local idx = math.random(1, #chars)
                            hwid = hwid .. chars:sub(idx, idx)
                            if i == 8 or i == 12 or i == 16 or i == 20 then hwid = hwid .. "-" end
                        end
                        _G.FakeHWID_String = hwid
                    end
                    return _G.FakeHWID_String
                end
                if _G.Original_GetDeviceId then return _G.Original_GetDeviceId(...) end
                return "UNKNOWN"
            end
            _G.FakeHWID_Hooked = true
            Notify("Fake HWID Hook Active")
        end
    end)
end




-- ====== AUTO REPORT SYSTEM (Reports all enemies, skips teammates) ======
_G.AutoReportConfig = _G.AutoReportConfig or {
    Enable = false,
    ReportReason = 1,
    ReportDelay = 3.0,
    BotsOnly = false,
    AutoScreenshot = true,
    _lastReportTime = 0,
    _reportedPlayers = {},
    _cachedReportModule = nil,
    _reportQueue = {},
}
-- BAN-SAFE LOCK: Auto Report + Auto Screenshot hamesha OFF (ban risk, menu se hataya)
_G.AutoReportConfig.Enable = false
_G.AutoReportConfig.AutoScreenshot = false

_G.AutoReportReasons = {
    [1] = "Cheating",
    [2] = "Hacking",
    [3] = "Abusing",
    [4] = "Griefing",
    [5] = "Team Killing",
}

_G.AutoReportPlayer = function(targetPlayer)
    if not _G.AutoReportConfig.Enable then return end
    if not targetPlayer or not slua.isValid(targetPlayer) then return end
    if not targetPlayer:IsAlive() then return end

    local localPlayer = nil
    pcall(function() localPlayer = GameplayData.GetLocalCharacter() end)
    if not Valid(localPlayer) then return end

    local myTeam = nil
    pcall(function() myTeam = localPlayer:GetTeamID() end)
    local targetTeam = nil
    pcall(function() targetTeam = targetPlayer:GetTeamID() end)

    if myTeam and targetTeam and myTeam == targetTeam then return end

    local targetKey = nil
    pcall(function() targetKey = targetPlayer:GetPlayerKey() end)
    if not targetKey then
        pcall(function() targetKey = targetPlayer.PlayerKey end)
    end
    if not targetKey then return end

    if _G.AutoReportConfig._reportedPlayers[targetKey] then return end

    local targetName = nil
    pcall(function() targetName = targetPlayer:GetPlayerNameSafety() end)
    if not targetName then
        pcall(function()
            local PS = targetPlayer:GetPlayerState()
            if Valid(PS) and PS.GetPlayerName then
                targetName = PS:GetPlayerName()
            end
        end)
    end
    if not targetName or targetName == "" or targetName == "Unknown" then return end

    local reason = _G.AutoReportReasons[_G.AutoReportConfig.ReportReason] or "Cheating"
    _G.AutoReportConfig._reportedPlayers[targetKey] = true
    _G.AutoReportConfig._reportQueue[#_G.AutoReportConfig._reportQueue + 1] = {key = targetKey, reason = reason, name = targetName}
end

_G._ProcessReportQueue = function()
    local queue = _G.AutoReportConfig._reportQueue
    if not queue or #queue == 0 then return end

    local curTime = os.clock()
    if (curTime - _G.AutoReportConfig._lastReportTime) < 0.5 then return end

    local entry = table.remove(queue, 1)
    if not entry then return end

    pcall(function()
        if not _G.AutoReportConfig._cachedReportModule then
            _G.AutoReportConfig._cachedReportModule = require("GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem")
        end
        local mod = _G.AutoReportConfig._cachedReportModule
        if mod and mod.ReportPlayer then
            mod:ReportPlayer(entry.key, entry.reason)
            _G.AutoReportConfig._lastReportTime = curTime
        end
    end)
end

_G.AutoReportTick = function()
    if not _G.AutoReportConfig.Enable then return end

    _G._ProcessReportQueue()

    local localPlayer = nil
    pcall(function() localPlayer = GameplayData.GetLocalCharacter() end)
    if not Valid(localPlayer) then return end

    local allCharacters = {}
    pcall(function()
        if GameplayData.GetAllPlayerCharacters then
            allCharacters = GameplayData.GetAllPlayerCharacters()
        end
    end)

    local aliveEnemies = 0
    for _, actor in pairs(allCharacters) do
        if Valid(actor) and actor ~= localPlayer and actor:IsAlive() then
            local isTeammate = false
            pcall(function()
                local myTeam = localPlayer:GetTeamID()
                local tTeam = actor:GetTeamID()
                if myTeam and tTeam and myTeam == tTeam then isTeammate = true end
            end)
            if not isTeammate then
                aliveEnemies = aliveEnemies + 1
                _G.AutoReportPlayer(actor)
                if (os.clock() - _G._AutoReportTickStart or 0) > 0.05 then break end
            end
        end
    end

    if aliveEnemies == 0 and _G.AutoReportConfig.AutoScreenshot then
        if not _G._AutoReportSSSent then
            _G._AutoReportSSSent = true
            pcall(function()
                local KSL = import("KismetSystemLibrary")
                local world = slua.getWorld()
                if KSL and world then
                    KSL.ExecuteConsoleCommand(world, "HighResShot 1920x1080")
                end
            end)
        end
    end

    if aliveEnemies > 0 then
        _G._AutoReportSSSent = false
    end
end

    -- Sh MENU MODULE - OPTIMIZED FOR NO LAG (ZERO REPETITION)
    -- ============================================================
    local MY_TAB_VER = 18

    if not _G.__MyTabInstalled then
    _G.__MyTabInstalled = true

    local LOC = {
        MY_TAB             = 9990001,
        TAB_AIMBOT         = 9990011,
        TAB_MEMORY         = 9990014,
        TAB_OUTFIT         = 9990018,
        TAB_GUNS           = 9990019,
        TAB_GEAR           = 9990020,
        TAB_VEH            = 9990021,

        BTN_ESP_ENABLE     = 9990100,
        TITLE_ESP          = 9990101,
        TITLE_CHAMS        = 9990130,
        BTN_CHAMS_ENABLE   = 9990102,
        BTN_ESP_LINES      = 9990103,
        BTN_ESP_FOV_CIRCLE = 9990110,
        BTN_ESP_ARROWS     = 9990111,
        BTN_ESP_BOX        = 9990112,
        BTN_CHAMS_VIS      = 9990104,
        BTN_CHAMS_OCC      = 9990105,
        BTN_NEW_WALLHACK   = 9990120,
        BTN_NEW_WH_VIS     = 9990121,
        BTN_NEW_WH_OCC     = 9990122,
        BTN_BLUE_FRAME     = 9990123,
        BTN_FAKE_HWID      = 9990106,
        
        TAB_BAN            = 9990017,
        BTN_CAR_FLY        = 9990107,
        BTN_CAR_FLY_SPEED  = 9990108,
        BTN_FAST_CAR       = 9990109,
        BTN_FORCE_TPP      = 9990114,
        BTN_MAGIC_BULLET   = 9990113,
        BTN_BAT_POWER      = 9990115,

        BTN_AIMBOT_ENABLE  = 9990030,
        BTN_AIMBOT_NORMAL = 9990036,
        BTN_AIMBOT_FOV     = 9990031,
        BTN_AIMBOT_DIST    = 9990032,
        BTN_AIMBOT_SPEED   = 9990033,
        BTN_AIMBOT_KNOCK   = 9990034,
        BTN_AIMBOT_BOT     = 9990035,
        BTN_AIMBOT_TARGET  = 9990037,
        BTN_AIMBOT_WALL    = 9990038,
        BTN_AIMBOT_INSCOPE = 9990039,
        BTN_AIMBOT_LONGRANGE = 9990042,
        BTN_AIMBOT_LONGRECOIL = 9990043,
        BTN_AIMBOT_BONE    = 9990041,
        
        BTN_MEM_GRASS      = 9990080,
        BTN_MEM_TREES      = 9990081,
        BTN_MEM_FOG        = 9990082,
        BTN_MEM_BLACKSKY   = 9990083,
        BTN_MEM_FPS        = 9990084,
        BTN_MEM_IPAD       = 9990085,
        BTN_MEM_IPAD_FOV   = 9990086,
        BTN_MEM_SMALLSCOPE     = 9990088,
        BTN_MEM_SMALLSCOPE_FOV = 9990089,
        
        BTN_MEM_CROSSHAIR  = 9990087,
        
        BTN_AUTO_REPORT       = 9990090,
        BTN_AUTO_REPORT_REASON = 9990091,
        BTN_AUTO_REPORT_DELAY  = 9990092,
        
        OPT_ON             = 9990060,
        OPT_OFF            = 9990061,
        
        TITLE_AIMING       = 9990062,
        TITLE_SETTINGS     = 9990063,
    }

    local LOC_STR = {
        [LOC.MY_TAB]            = "VIP MENU",
        [LOC.TAB_AIMBOT]        = "AIMBOT",
        [LOC.TAB_MEMORY]        = "MEMORY",
        [LOC.TAB_OUTFIT]        = "OUTFIT",
        [LOC.TAB_GUNS]          = "GUNS",
        [LOC.TAB_GEAR]          = "GEAR",
        [LOC.TAB_VEH]           = "VEHICLE",
        [LOC.TAB_BAN]           = "BAN FEATURES",
        [LOC.BTN_CAR_FLY]       = "Car Fly",
        [LOC.BTN_CAR_FLY_SPEED] = "Car Fly Speed",
        [LOC.BTN_FAST_CAR]      = "Fast Car",
        [LOC.BTN_FORCE_TPP]     = "Force TPP (FPP Match)",
        [LOC.BTN_MAGIC_BULLET]  = "Magic Bullet (Head Snap)",
        [LOC.BTN_BAT_POWER]     = "BAT New Power (Fly 10x)",

        [LOC.BTN_ESP_ENABLE]    = "ESP Enable",
        [LOC.TITLE_ESP]         = "ESP Control",
        [LOC.TITLE_CHAMS]       = "Chams & Wallhack",
        [LOC.BTN_CHAMS_ENABLE]  = "Chams (Color)",
        [LOC.BTN_ESP_LINES]     = "ESP Lines",
        [LOC.BTN_ESP_FOV_CIRCLE] = "FOV Circle",
        [LOC.BTN_ESP_ARROWS]     = "Offscreen Arrows",
        [LOC.BTN_ESP_BOX]        = "Box ESP",
        [LOC.BTN_CHAMS_VIS]     = "Chams Front Color (1R 2B 3G 4Y 5O 6P)",
        [LOC.BTN_CHAMS_OCC]     = "Chams Wall Color (1R 2B 3G 4Y 5O 6P)",
        [LOC.BTN_NEW_WALLHACK]  = "NEW WALLHACK (PBC)",
        [LOC.BTN_NEW_WH_VIS]    = "Wallhack Visible Color (1Green 2Lime 3Orange 4Red 5Blue 6Gray 7Teal)",
        [LOC.BTN_NEW_WH_OCC]    = "Wallhack Wall Color (1Green 2Lime 3Orange 4Red 5Blue 6Gray 7Teal)",
        [LOC.BTN_BLUE_FRAME]    = "BLUE FRAME ESP (OB Head)",
        [LOC.BTN_FAKE_HWID]     = "Fake HWID (Anti-Ban)",
        
        [LOC.BTN_AIMBOT_ENABLE] = "Aimbot Enable",
        [LOC.BTN_AIMBOT_NORMAL] = "Normal Aimbot",
        [LOC.BTN_AIMBOT_FOV]    = "Aimbot FOV",
        [LOC.BTN_AIMBOT_DIST]   = "Aimbot Max Dist",
        [LOC.BTN_AIMBOT_SPEED]  = "Aimbot Smooth Speed",
        [LOC.BTN_AIMBOT_KNOCK]  = "Ignore Knocked",
        [LOC.BTN_AIMBOT_BOT]    = "Ignore Bots",
        [LOC.BTN_AIMBOT_TARGET] = "Target Mode (1Near 2LowHP)",
        [LOC.BTN_AIMBOT_WALL]   = "Wall Target (Through Wall)",
        [LOC.BTN_AIMBOT_INSCOPE] = "In Scope Aimbot (10-100m)",
        [LOC.BTN_AIMBOT_LONGRANGE] = "Long Range Aimbot (300m+)",
        [LOC.BTN_AIMBOT_LONGRECOIL] = "Long Range Recoil (0 Off)",
        [LOC.BTN_AIMBOT_BONE]    = "Aim Bone",
        
        [LOC.BTN_MEM_GRASS]     = "Remove Grass",
        [LOC.BTN_MEM_TREES]     = "Remove Trees",
        [LOC.BTN_MEM_FOG]       = "Remove Fog",
        [LOC.BTN_MEM_BLACKSKY]  = "Black Sky",
        [LOC.BTN_MEM_FPS]       = "Unlock 165 FPS",
        [LOC.BTN_MEM_IPAD]      = "iPad View",
        [LOC.BTN_MEM_IPAD_FOV]  = "iPad FOV",
        [LOC.BTN_MEM_SMALLSCOPE]     = "Small Scope (iPad Style)",
        [LOC.BTN_MEM_SMALLSCOPE_FOV] = "Small Scope FOV",
        
        [LOC.BTN_MEM_CROSSHAIR]  = "Small Crosshair",
        
        [LOC.BTN_AUTO_REPORT]    = "Auto Report Enemies",
        [LOC.BTN_AUTO_REPORT_REASON] = "Report Reason",
        [LOC.BTN_AUTO_REPORT_DELAY]  = "Report Delay",
        
        [LOC.OPT_ON]            = "ON",
        [LOC.OPT_OFF]           = "OFF",
        
        [LOC.TITLE_AIMING]      = "Aimbot Configuration",
        [LOC.TITLE_SETTINGS]    = "Memory Hacks",
    }

    _G.MemoryConfig = _G.MemoryConfig or {
        RemoveGrass = false,
        RemoveTrees = false,
        RemoveFog   = false,
        BlackSky    = false,
        UnlockFPS   = false,
        IpadView    = false,
        IpadFOV     = 120,
        _IpadWasActive = false,
        SmallCrosshair = false,
        _CrosshairWasActive = false,
        SmallScope = false,
        SmallScopeFOV = 75,
    }

    local function ResolveLoc(id)
        return LOC_STR[id]
    end

    local function LOG(msg)
        pcall(print, "[Sh Menu] " .. tostring(msg))
    end

    LOG("Sh Menu v" .. MY_TAB_VER .. " loading...")

    local function ApplyMemoryFeature(feature, state)
        pcall(function()
        local lsg = require("client.slua.logic.setting.logic_setting_graphics")
        local gi = lsg.GetGameInstance()
        if not gi then
            gi = slua_GameFrontendHUD and slua_GameFrontendHUD:GetWorld()
        end
        if not gi then return end

        if feature == "Grass" then
            if state then
            gi:ExecuteCMD("grass.DensityScale", "0")
            gi:ExecuteCMD("grass.DiscardDataOnLoad", "1")
            else
            gi:ExecuteCMD("grass.DensityScale", "1")
            gi:ExecuteCMD("grass.DiscardDataOnLoad", "0")
            end
        elseif feature == "Trees" then
            if state then
            gi:ExecuteCMD("foliage.DensityScale", "0")
            gi:ExecuteCMD("r.Foliage.DensityScale", "0")
            gi:ExecuteCMD("foliage.MinimumScreenSize", "10000")
            gi:ExecuteCMD("r.DisableTreeRender", "1")
            else
            gi:ExecuteCMD("foliage.DensityScale", "1")
            gi:ExecuteCMD("r.Foliage.DensityScale", "1")
            gi:ExecuteCMD("foliage.MinimumScreenSize", "0")
            gi:ExecuteCMD("r.DisableTreeRender", "0")
            end
        elseif feature == "Fog" then
            if state then
            gi:ExecuteCMD("r.SkyAtmosphere", "1")
            gi:ExecuteCMD("r.Fog", "0")
            gi:ExecuteCMD("r.VolumetricFog", "0")
            else
            gi:ExecuteCMD("r.SkyAtmosphere", "1")
            gi:ExecuteCMD("r.Fog", "1")
            gi:ExecuteCMD("r.VolumetricFog", "1")
            end
        elseif feature == "BlackSky" then
            if state then
            gi:ExecuteCMD("r.CylinderMaxDrawHeight", "9999")
            else
            gi:ExecuteCMD("r.CylinderMaxDrawHeight", "0")
            end
        elseif feature == "FPS" then
            local SettingCfg = require("client.logic.setting.setting_config")
            local GraphicSettingDB = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
            
            if state then
            if SettingCfg then
                if SettingCfg.TpViewValue then SettingCfg.TpViewValue.max = 160 end
                if SettingCfg.FpViewValue then SettingCfg.FpViewValue.max = 160 end
            end
            if GraphicSettingDB then
                if GraphicSettingDB.TpViewValue then GraphicSettingDB.TpViewValue.max = 160 end
            end
            gi:ExecuteCMD("t.MaxFPS", "165")
            gi:ExecuteCMD("r.FrameRateLimit", "165")
            else
            if SettingCfg then
                if SettingCfg.TpViewValue then SettingCfg.TpViewValue.max = 90 end
                if SettingCfg.FpViewValue then SettingCfg.FpViewValue.max = 90 end
            end
            if GraphicSettingDB then
                if GraphicSettingDB.TpViewValue then GraphicSettingDB.TpViewValue.max = 90 end
            end
            gi:ExecuteCMD("t.MaxFPS", "90")
            gi:ExecuteCMD("r.FrameRateLimit", "90")
            end
        end
        end)
    end

    _G.ApplyMemoryFeature = ApplyMemoryFeature

    local function RefreshAllMemoryFeatures()
        if not _G.MemoryConfig then return end
        ApplyMemoryFeature("Grass", _G.MemoryConfig.RemoveGrass)
        ApplyMemoryFeature("Trees", _G.MemoryConfig.RemoveTrees)
        ApplyMemoryFeature("Fog", _G.MemoryConfig.RemoveFog)
        ApplyMemoryFeature("BlackSky", _G.MemoryConfig.BlackSky)
        ApplyMemoryFeature("FPS", _G.MemoryConfig.UnlockFPS)
    end
    _G.RefreshAllMemoryFeatures = RefreshAllMemoryFeatures

    RefreshAllMemoryFeatures()

    local function HookLoc(tbl, fname)
        if type(tbl) ~= "table" then return end
        if tbl["__mytab_hooked_" .. fname] then return end
        
        local orig = tbl[fname]
        if type(orig) ~= "function" then return end
        
        tbl["__mytab_hooked_" .. fname] = true
        tbl["__mytab_" .. fname] = orig
        
        tbl[fname] = function(...)
        local arg1 = select(1, ...)
        local id = arg1
        if type(arg1) == "table" and arg1 == tbl then
            id = select(2, ...)
        end
        
        local s = ResolveLoc(id)
        if s then return s end
        return orig(...)
        end
    end

    local function InstallLocHooks()
        local LocUtil = _G.LocUtil
        if not LocUtil then
        local ok, lu = pcall(require, "common.loc_util")
        if ok and lu then LocUtil = lu end
        end
        if type(LocUtil) == "table" then
        HookLoc(LocUtil, "GetLocalizeResStr")
        HookLoc(LocUtil, "GetLocalizeResStrV2")
        HookLoc(LocUtil, "TryGetLocalizeResStr")
        HookLoc(LocUtil, "ResolveText")
        end
        local DataMgr = _G.DataMgr
        if not DataMgr then
        local ok2, dm = pcall(require, "client.logic.data.data_mgr")
        if ok2 and dm then DataMgr = dm end
        end
        if type(DataMgr) == "table" then
        HookLoc(DataMgr, "GetMsgByID")
        HookLoc(DataMgr, "GetFormatMsgByID")
        end
    end

    InstallLocHooks()

    pcall(function()
        if type(slua) == "table" and type(slua.AddTickerDelegate) == "function" then
        local tries = 0
        slua.AddTickerDelegate(function()
            tries = tries + 1
            InstallLocHooks()
            return tries < 5
        end, 1.0)
        end
    end)

    local MY_TAB_DEFINE = {
        Key  = "MyTab",
        Text = LOC.MY_TAB,
    }


    local function HasMyTab(catalog)
        if type(catalog) ~= "table" then return false end
        local hasMy, hasSkin = false, false
        for _, item in ipairs(catalog) do
        if type(item) == "table" and item.Key == "MyTab" then hasMy = true end
        if type(item) == "table" and item.Key == "SkinTab" then hasSkin = true end
        end
        return hasMy and hasSkin
    end

    local function InjectMyTab(catalog)
        if type(catalog) ~= "table" then return end
        if HasMyTab(catalog) then return end
        GetMyTabDefine()
        table.insert(catalog, 1, MY_TAB_DEFINE)
        LOG("InjectMyTab: inserted VIP MENU at 1 + SKIN at 2")
    end

    if type(UIManager) == "table" and type(UIManager.ShowUI) == "function" then
        if UIManager.__mytab_ShowUI then
        UIManager.ShowUI = UIManager.__mytab_ShowUI
        UIManager.__mytab_ShowUI = nil
        end
        UIManager.__mytab_ShowUI = UIManager.ShowUI
        
        UIManager.ShowUI = function(...)
        local uiKey = select(1, ...)
        local arg1 = uiKey
        local args_start = 1
        if type(arg1) == "table" and arg1 == UIManager then
            uiKey = select(2, ...)
            args_start = 2
        end
        
        local cfg = UIManager.UI_Config
        if cfg and uiKey == cfg.setting_main then
            local catArg = select(args_start + 1, ...)
            if type(catArg) == "table" then InjectMyTab(catArg) end
        end
        return UIManager.__mytab_ShowUI(...)
        end
        LOG("UIManager.ShowUI hooked")
    end

    local SettingMainPath = "client.slua.umg.NewSetting.Main.setting_main_base"
    local okSM, SettingMain = pcall(require, SettingMainPath)
    if okSM and SettingMain then
        if SettingMain.__mytab_OnSelectTab_Page then
        SettingMain.OnSelectTab_Page = SettingMain.__mytab_OnSelectTab_Page
        SettingMain.__mytab_OnSelectTab_Page = nil
        end
        SettingMain.__mytab_OnSelectTab_Page = SettingMain.OnSelectTab_Page
        SettingMain.OnSelectTab_Page = function(self, ItemIndex)
        local pageData = self.AvailablePageList and self.AvailablePageList[ItemIndex]
        if pageData and (pageData.Key == "MyTab" or pageData.Key == "SkinTab") then
            if self._PageUI then
            pcall(function() self._PageUI:CloseSelf() end)
            self._PageUI = nil
            end
            if self._CategoryUI then
            pcall(function() self._CategoryUI:CloseSelf() end)
            self._CategoryUI = nil
            end

            local def = GetMyTabDefine()
            if pageData.Key == "SkinTab" then def = nil end
            if not def.Category then return end

            self._CurrentPage = pageData
            self._AvailableCategoryList = def.Category

            -- Try to ensure enough tab buttons exist
            pcall(function()
                local catCount = #def.Category
                self.UIRoot.HorizontalSelector_Category:SetNum(catCount)
            end)
            for i, catData in ipairs(def.Category) do
            pcall(function()
                local Child = self.UIRoot.HorizontalSelector_Category:GetChildAt(i - 1)
                if Child and slua.isValid(Child) and Child.TextBlock_Name then
                    Child.TextBlock_Name:SetText(ResolveLoc(catData.Text) or tostring(catData.Text))
                end
            end)
            end

            self:SetWidgetVisible(self.UIRoot.Border_Header, true)
            pcall(function()
            self:PlayUserWidgetAnimation(self.UIRoot.Fadein_Page, 0, 1, 0, 1)
            end)

            self.UIRoot.HorizontalSelector_Category:SetSelectedIndex(-1)
            self.UIRoot.HorizontalSelector_Category:SetSelectedIndex(1)
            return true
        end
        return SettingMain.__mytab_OnSelectTab_Page(self, ItemIndex)
        end
        LOG("OnSelectTab_Page hooked")

        if SettingMain.__mytab_OnSelectTab_Category then
        SettingMain.OnSelectTab_Category = SettingMain.__mytab_OnSelectTab_Category
        SettingMain.__mytab_OnSelectTab_Category = nil
        end
        SettingMain.__mytab_OnSelectTab_Category = SettingMain.OnSelectTab_Category
        SettingMain.OnSelectTab_Category = function(self, ItemIndex)
        local curPage = self._CurrentPage
        if curPage and (curPage.Key == "MyTab" or curPage.Key == "SkinTab") then
            local lastIndex = self.UIRoot.HorizontalSelector_Category:GetSelectedIndex()
            if lastIndex > 0 and self._CategoryUI then
            pcall(function() self._CategoryUI:CloseSelf() end)
            self._CategoryUI = nil
            end

            local catData = self._AvailableCategoryList and self._AvailableCategoryList[ItemIndex]
            if catData then
            if catData.UIKey and catData.Stack then
                self._CategoryUI = self:CreateChildWindow(
                self.UIRoot.StackRoot,
                UIManager.UI_Config[catData.UIKey],
                catData.Stack
                )
            elseif catData.Stack then
                self._CategoryUI = self:CreateChildWindow(
                self.UIRoot.StackRoot,
                UIManager.UI_Config.Setting_StackContainer,
                catData.Stack
                )
            end
            end

            pcall(function()
            self:PlayUserWidgetAnimation(self.UIRoot.Fadein_Category, 0, 1, 0, 1)
            end)
            return true
        end
        return SettingMain.__mytab_OnSelectTab_Category(self, ItemIndex)
        end
        LOG("OnSelectTab_Category hooked")
    end

    if type(UIManager) == "table" and type(UIManager.HideUI) == "function" then
        if UIManager.__mytab_HideUI then
        UIManager.HideUI = UIManager.__mytab_HideUI
        UIManager.__mytab_HideUI = nil
        end
        UIManager.__mytab_HideUI = UIManager.HideUI
        UIManager.HideUI = function(...)
        local uiKey = select(1, ...)
        local arg1 = uiKey
        local args_start = 1
        if type(arg1) == "table" and arg1 == UIManager then
            uiKey = select(2, ...)
            args_start = 2
        end
        
        local cfg = UIManager.UI_Config
        if cfg and uiKey == cfg.setting_main then
            local ui = UIManager.GetUI and UIManager.GetUI(cfg.setting_main)
            if ui then ui.__mytabInstalled = nil end
        end
        return UIManager.__mytab_HideUI(...)
        end
    end

    LOG("Sh Menu v" .. MY_TAB_VER .. " globally installed.")
    end

    -- ============================================================
    -- LIGHT REATTACH (har match me full re-exec KI JAGAH yahi chalega)
    -- Poora 9000-line chunk dobara compile/execute NAHI hota = no stuck.
    -- Sirf dead timers naye PC par lagte hain + canvas refresh. ~10x halka.
    -- NOTE: lua update ho to game restart chahiye (pehle se aisa hi tha).
    -- ============================================================
    _G.SH_Reattach = function()
        if _G._LICENSE_OK ~= true then return end
        -- ESP V3 + aimbot timers: naya match/character to dead handle hatao, phir start
        _G._espV3Timer = nil
        _G._aimbotTimer = nil
        pcall(function() if _G.StartESPV3 then _G.StartESPV3() end end)
        pcall(function() if _G.StartAimbotLoop then _G.StartAimbotLoop() end end)



        pcall(function()
            if _G.BRChamsConfig and _G.BRChamsConfig.Enable and _G.BRStartChams then
                if _G.BRStopChams then _G.BRStopChams() end
                _G._chamsTimer = nil
                _G.BRStartChams()
            end
        end)
        pcall(function()
            if _G.PBCWallhackConfig and _G.PBCWallhackConfig.Enable and _G.PBCStartWallhack then
                if _G.PBCStopWallhack then _G.PBCStopWallhack() end
                _G.PBCStartWallhack()
            end
        end)
        pcall(function()
            if _G.BlueFrameConfig and _G.BlueFrameConfig.Enable and _G.BlueFrameStart then
                if _G.BlueFrameStop then _G.BlueFrameStop() end
                _G.BlueFrameStart()
            end
        end)
        pcall(function()
            if _G.CarFlyConfig and _G.CarFlyConfig.Enable and _G.CarFlyConfig.Start then
                if _G.CarFlyConfig.Stop then _G.CarFlyConfig.Stop() end
                _G.CarFlyConfig.Start()
            end
        end)
        pcall(function()
            if _G.FastCarEnabled and _G.StartFastCar then
                if _G.StopFastCar then _G.StopFastCar() end
                _G.StartFastCar()
            end
        end)
        pcall(function()
            if _G.MagicBulletConfig and _G.MagicBulletConfig.Enable and _G.StartMagicBullet then
                if _G.StopMagicBullet then _G.StopMagicBullet() end
                _G.StartMagicBullet()
            end
        end)
        pcall(function()
            if _G.BatPowerConfig and _G.BatPowerConfig.Enable and _G.ReapplyBatPower then
                _G.ReapplyBatPower()
            end
        end)
        pcall(function()
            if _G.RefreshAllMemoryFeatures then _G.RefreshAllMemoryFeatures() end
        end)
    end

    -- Auto-restart features that were enabled in previous match
    -- (timers die when old PlayerController is destroyed between matches)
    -- Must be OUTSIDE __MyTabInstalled block so it runs every script load
    pcall(function()
        if _G.BRChamsConfig and _G.BRChamsConfig.Enable then
            _G._chamsTimer = nil  -- Force clear dead timer reference
            if _G.BRStopChams then _G.BRStopChams() end
            _G.BRStartChams()
        end
    end)
    pcall(function()
        if _G.PBCWallhackConfig and _G.PBCWallhackConfig.Enable then
            if _G.PBCStopWallhack then _G.PBCStopWallhack() end
            _G.PBCStartWallhack()
        end
    end)
    pcall(function()
        if _G.BlueFrameConfig and _G.BlueFrameConfig.Enable then
            if _G.BlueFrameStop then _G.BlueFrameStop() end
            _G.BlueFrameStart()
        end
    end)
    pcall(function()
        if _G.CarFlyConfig and _G.CarFlyConfig.Enable then
            if _G.CarFlyConfig.Stop then _G.CarFlyConfig.Stop() end
            _G.CarFlyConfig.Start()
        end
    end)
    pcall(function()
        if _G.FastCarEnabled then
            if _G.StopFastCar then _G.StopFastCar() end
            _G.StartFastCar()
        end
    end)
    pcall(function()
        if _G.MagicBulletConfig and _G.MagicBulletConfig.Enable then
            if _G.StopMagicBullet then _G.StopMagicBullet() end
            _G.MagicBulletConfig.Enable = true
            if _G.StartMagicBullet then _G.StartMagicBullet() end
        end
    end)
    pcall(function()
        if _G.BatPowerConfig and _G.BatPowerConfig.Enable then
            if _G.ReapplyBatPower then _G.ReapplyBatPower() end
        end
    end)
    pcall(function()
        if _G.RefreshAllMemoryFeatures then
            _G.RefreshAllMemoryFeatures()
        end
    end)

    -- ============================================================
    -- LIBANOGS BAN HOOK - Anti-Detection bypass
    -- ============================================================
    do
        local _libanogs_OrigBan = nil
        local function InitBanHook()
            pcall(function()
                local KSL = import("KismetSystemLibrary")
                if not KSL then return end
                local world = slua.getWorld()
                if not world then return end

                KSL.ExecuteConsoleCommand(world, "LoadLibrary libanogs.so")

                local libanogs = nil
                pcall(function() libanogs = slua.loadLibrary("libanogs.so") end)
                if not libanogs then
                    pcall(function() libanogs = import("libanogs.so") end)
                end

                if not libanogs then
                    LOG("[BanHook] libanogs.so not available, trying string scan")
                end

                _G._BanHookActive = true
                _G._OrigBanString = nil

                local function CheckBanString(s)
                    if type(s) ~= "string" then return s end
                    if string.find(s, "Anti%-Detection") or string.find(s, "10 Years") then
                        LOG("[BanHook] Ban string detected: " .. string.sub(s, 1, 50))
                        local safeStr = "Data/file/%%"
                        _G._OrigBanString = s
                        return safeStr
                    end
                    return s
                end
                _G.CheckBanString = CheckBanString

                if libanogs then
                    local banFuncNames = {"Ban", "BanPlayer", "BanUser", "ReportBan"}
                    for _, fname in ipairs(banFuncNames) do
                        if libanogs[fname] and type(libanogs[fname]) == "function" then
                            local orig = libanogs[fname]
                            libanogs[fname] = function(...)
                                local args = {...}
                                for i, arg in ipairs(args) do
                                    if type(arg) == "string" then
                                        args[i] = CheckBanString(arg)
                                    end
                                end
                                return orig(table.unpack(args))
                            end
                            LOG("[BanHook] Hooked " .. fname .. " in libanogs.so")
                        end
                    end
                end

                if KSL.GetDeviceId then
                    local origDeviceId = KSL.GetDeviceId
                    KSL.GetDeviceId = function(...)
                        local result = origDeviceId(...)
                        if _G.BRFakeHWID and _G.BRFakeHWID.Enable then
                            if not _G.FakeHWID_String then
                                local chars = "0123456789ABCDEF"
                                local hwid = ""
                                for i = 1, 32 do
                                    local idx = math.random(1, #chars)
                                    hwid = hwid .. chars:sub(idx, idx)
                                    if i == 8 or i == 12 or i == 16 or i == 20 then hwid = hwid .. "-" end
                                end
                                _G.FakeHWID_String = hwid
                            end
                            return _G.FakeHWID_String
                        end
                        return result
                    end
                    LOG("[BanHook] DeviceId hook active")
                end

                if KSL.GetDeviceIdOS then
                    local origDeviceIdOS = KSL.GetDeviceIdOS
                    KSL.GetDeviceIdOS = function(...)
                        local result = origDeviceIdOS(...)
                        if _G.BRFakeHWID and _G.BRFakeHWID.Enable then
                            if not _G.FakeHWID_String then
                                local chars = "0123456789ABCDEF"
                                local hwid = ""
                                for i = 1, 32 do
                                    local idx = math.random(1, #chars)
                                    hwid = hwid .. chars:sub(idx, idx)
                                    if i == 8 or i == 12 or i == 16 or i == 20 then hwid = hwid .. "-" end
                                end
                                _G.FakeHWID_String = hwid
                            end
                            return _G.FakeHWID_String
                        end
                        return result
                    end
                    LOG("[BanHook] DeviceIdOS hook active")
                end

                LOG("[BanHook] Anti-Detection bypass active")
            end)
        end

        -- SLIM BYPASS: libanogs hook disabled (ACE lib tampering = instant flag)
        _G._BanHookActive = false
    end

    -- ============================================================
    -- FLOATING MOD MENU (screen overlay: icon + ON/OFF + hide)
    -- Menu makers se auto-mirror hota hai (_G._FM_ITEMS).
    -- ============================================================
    _G._FM_OPEN = _G._FM_OPEN or false
    _G._FM_CAT = _G._FM_CAT or "AIM"

    local function _FM_BindClick(b, fn)
        if not (b and slua.isValid(b)) then return end
        pcall(function() if b.OnClicked and b.OnClicked.Add then b.OnClicked:Add(function() fn() end) end end)
        pcall(function() if b.OnClicked and b.OnClicked.Add then b.OnClicked:Add(b, function() fn() end) end end)
        pcall(function() if slua.addDelegate then slua.addDelegate(b.OnClicked, function() fn() end) end end)
    end

    local function _FM_Text(root, txt, size, color, x, y, z)
        local w = nil
        pcall(function() w = CGame:NewObjectFromPath("/Script/UMG.TextBlock", root) end)
        if not (w and slua.isValid(w)) then return nil end
        pcall(function()
            w:SetText(tostring(txt))
            local FLinearColor = import("LinearColor")
            local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
            if FSlateColor then w:SetColorAndOpacity(FSlateColor(color)) else w:SetColorAndOpacity(color) end
            if w.Font then local f = w.Font f.Size = size w.Font = f end
            w:SetWidgetVisibility(UEnums.ESlateVisibility.HitTestInvisible)
        end)
        pcall(function()
            local FVector2D = import("Vector2D")
            local s = root:AddChildToCanvas(w)
            if s then s:SetAutoSize(true) s:SetAlignment(FVector2D(0.5, 0.5)) s:SetPosition(FVector2D(x, y)) s:SetZOrder(z or 10002) end
        end)
        return w
    end

    local function _FM_Border(root, color, x, y, w, h, z)
        local b = nil
        pcall(function() b = CGame:NewObjectFromPath("/Script/UMG.Border", root) end)
        if not (b and slua.isValid(b)) then return nil end
        pcall(function()
            b:SetBrushColor(color)
            b:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
        pcall(function()
            local FVector2D = import("Vector2D")
            local s = root:AddChildToCanvas(b)
            if s then s:SetAlignment(FVector2D(0.5, 0.5)) s:SetPosition(FVector2D(x, y)) s:SetSize(FVector2D(w, h)) s:SetZOrder(z or 10001) end
        end)
        return b
    end

    local function _FM_Button(root, label, size, color, x, y, w, h, fn)
        local b = nil
        pcall(function() b = CGame:NewObjectFromPath("/Script/UMG.Button", root) end)
        if not (b and slua.isValid(b)) then return nil end
        pcall(function()
            local FVector2D = import("Vector2D")
            local bs = root:AddChildToCanvas(b)
            if bs then bs:SetAlignment(FVector2D(0.5, 0.5)) bs:SetPosition(FVector2D(x, y)) bs:SetSize(FVector2D(w, h)) bs:SetZOrder(10003) end
        end)
        pcall(function()
            local l = CGame:NewObjectFromPath("/Script/UMG.TextBlock", b)
            if l and slua.isValid(l) then
                l:SetText(tostring(label))
                local FLinearColor = import("LinearColor")
                local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
                local lc = FLinearColor(color[1], color[2], color[3], 1)
                if FSlateColor then l:SetColorAndOpacity(FSlateColor(lc)) else l:SetColorAndOpacity(lc) end
                if l.Font then local f2 = l.Font f2.Size = size l.Font = f2 end
                l:SetWidgetVisibility(UEnums.ESlateVisibility.HitTestInvisible)
                if b.AddChild then b:AddChild(l) end
            end
        end)
        _FM_BindClick(b, fn)
        return b
    end

    local function _FM_CatOf(key)
        key = tostring(key or "")
        if key:sub(1, 4) == "aim_" then return "AIM" end
        if key:sub(1, 4) == "mem_" then return "MEM" end
        if key:sub(1, 4) == "esp_" or key:sub(1, 6) == "chams_" or key:sub(1, 7) == "new_wh_" or key == "blue_frame" or key == "fake_hwid" then return "ESP" end
        if key:sub(1, 5) == "skin_" then return "SKIN" end
        return "BAN"
    end

    local function _FM_Label(it)
        local s = nil
        pcall(function()
            if type(it.textId) == "number" and LOC_STR then s = LOC_STR[it.textId] end
        end)
        if not s or s == "" then
            s = type(it.textId) == "string" and it.textId or tostring(it.key or "???")
        end
        return s
    end

    local function _FM_Destroy()
        pcall(function()
            if _G._FM_ROOT and slua.isValid(_G._FM_ROOT) then
                _G._FM_ROOT:RemoveFromParent()
                if _G._FM_ROOT.ConditionalBeginDestroy then _G._FM_ROOT:ConditionalBeginDestroy() end
            end
        end)
        _G._FM_ROOT = nil
    end

    function _G.FM_Show(character)
        pcall(function()
            -- purana match ka stale root hatao
            if _G._FM_ROOT and not slua.isValid(_G._FM_ROOT) then
                _G._FM_ROOT = nil
                _G._FM_PANEL = nil
                _G._FM_TIMER = nil
            end
            local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
            local MainUI = InGameUITools.GetMainControlBaseUI()
            if not (MainUI and slua.isValid(MainUI)) then
                if character and character.AddGameTimer then
                    _G._FM_RETRY = (_G._FM_RETRY or 0) + 1
                    if _G._FM_RETRY < 25 and not _G._FM_TIMER then
                        _G._FM_TIMER = character:AddGameTimer(1.0, true, function()
                            if _G._FM_ROOT and slua.isValid(_G._FM_ROOT) then
                                if character.RemoveGameTimer and _G._FM_TIMER then pcall(function() character:RemoveGameTimer(_G._FM_TIMER) end) end
                                _G._FM_TIMER = nil
                                return
                            end
                            local n = _G._FM_RETRY or 0
                            if n >= 25 then
                                if character.RemoveGameTimer and _G._FM_TIMER then pcall(function() character:RemoveGameTimer(_G._FM_TIMER) end) end
                                _G._FM_TIMER = nil
                                return
                            end
                            _G.FM_Show(character)
                        end)
                    end
                end
                return
            end
            _G._FM_RETRY = 0
            if _G._FM_ROOT and slua.isValid(_G._FM_ROOT) then return end
            local Parent = (MainUI.CanvasPanel_0 and slua.isValid(MainUI.CanvasPanel_0)) and MainUI.CanvasPanel_0 or nil
            if not (Parent and slua.isValid(Parent)) then return end
            local FVector2D = import("Vector2D")
            local FLinearColor = import("LinearColor")
            local vw, vh = 1920, 1080
            pcall(function()
                local ui_util = require("client.common.ui_util")
                local vs = ui_util and ui_util.GetViewportSize and ui_util.GetViewportSize()
                if vs and vs.X and vs.X > 0 then vw, vh = vs.X, vs.Y end
            end)
            local S = math.min(vw / 1920, vh / 1080)
            if not S or S <= 0 then S = 1 end
            local red = FLinearColor(1.0, 0.12, 0.12, 1.0)
            local white = FLinearColor(1.0, 1.0, 1.0, 1.0)
            local grey = FLinearColor(0.7, 0.72, 0.75, 1.0)
            local cardC = FLinearColor(0.05, 0.02, 0.02, 0.96)
            local root = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", Parent)
            if not (root and slua.isValid(root)) then return end
            _G._FM_ROOT = root
            _G._FM_S = S
            _G._FM_VW, _G._FM_VH = vw, vh
            local rs = Parent:AddChildToCanvas(root)
            if rs then pcall(function() rs:SetPosition(FVector2D(0, 0)) rs:SetSize(FVector2D(vw, vh)) rs:SetZOrder(10000) end) end
            -- floating icon (top-right)
            local ix, iy = vw - 70 * S, 110 * S
            _FM_Border(root, red, ix, iy, 60 * S + 6, 60 * S + 6, 10001)
            _FM_Button(root, "SH", math.floor(22 * S), {1, 1, 1}, ix, iy, 60 * S, 60 * S, function()
                _G._FM_OPEN = not _G._FM_OPEN
                pcall(function() if _G.FM_Build then _G.FM_Build() end end)
            end)
            pcall(function() if _G.FM_Build then _G.FM_Build() end end)
        end)
    end

    function _G.FM_Build()
        pcall(function()
            local root = _G._FM_ROOT
            if not (root and slua.isValid(root)) then return end
            local S = _G._FM_S or 1
            local vw, vh = _G._FM_VW or 1920, _G._FM_VH or 1080
            local FVector2D = import("Vector2D")
            local FLinearColor = import("LinearColor")
            local red = FLinearColor(1.0, 0.12, 0.12, 1.0)
            local white = FLinearColor(1.0, 1.0, 1.0, 1.0)
            local grey = FLinearColor(0.7, 0.72, 0.75, 1.0)
            local green = FLinearColor(0.15, 0.9, 0.4, 1.0)
            local cardC = FLinearColor(0.05, 0.02, 0.02, 0.96)
            -- purana panel hatao
            pcall(function()
                if _G._FM_PANEL and slua.isValid(_G._FM_PANEL) then
                    _G._FM_PANEL:RemoveFromParent()
                    if _G._FM_PANEL.ConditionalBeginDestroy then _G._FM_PANEL:ConditionalBeginDestroy() end
                end
            end)
            _G._FM_PANEL = nil
            if not _G._FM_OPEN then return end
            local panel = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", root)
            if not (panel and slua.isValid(panel)) then return end
            _G._FM_PANEL = panel
            local cx = vw * 0.5
            local topY = vh * 0.12
            -- rows filter
            local rows = {}
            for _, it in ipairs(_G._FM_ITEMS or {}) do
                if _FM_CatOf(it.key) == (_G._FM_CAT or "AIM") then rows[#rows + 1] = it end
            end
            local rowH = 42 * S
            local panelW = 620 * S
            local headH = 96 * S
            local panelH = headH + #rows * rowH + 20 * S
            local cy = topY + panelH * 0.5
            if cy + panelH * 0.5 > vh then cy = vh - panelH * 0.5 - 10 * S end
            _FM_Border(panel, cardC, cx, cy, panelW, panelH, 10001)
            -- red frame
            _FM_Border(panel, red, cx, cy - panelH * 0.5, panelW, math.max(3, math.floor(4 * S)), 10002)
            _FM_Border(panel, red, cx, cy + panelH * 0.5, panelW, math.max(3, math.floor(4 * S)), 10002)
            _FM_Text(panel, "SH MENU", math.floor(24 * S), red, cx, topY + 24 * S, 10004)
            -- category buttons + X
            local cats = {"AIM", "MEM", "ESP", "SKIN", "BAN"}
            local bw = (panelW - 90 * S) / 5
            for i, c in ipairs(cats) do
                local bx = cx - panelW * 0.5 + 45 * S + (i - 0.5) * bw
                local on = (_G._FM_CAT == c)
                _FM_Button(panel, c, math.floor(15 * S), on and {1, 0.15, 0.15} or {1, 1, 1}, bx, topY + 58 * S, bw - 6 * S, 30 * S, function()
                    _G._FM_CAT = c
                    pcall(function() if _G.FM_Build then _G.FM_Build() end end)
                end)
            end
            _FM_Button(panel, "X", math.floor(16 * S), {1, 0.3, 0.3}, cx + panelW * 0.5 - 28 * S, topY + 24 * S, 34 * S, 30 * S, function()
                _G._FM_OPEN = false
                pcall(function() if _G.FM_Build then _G.FM_Build() end end)
            end)
            -- rows
            local ry = topY + headH
            for _, it in ipairs(rows) do
                local label = _FM_Label(it)
                if #label > 34 then label = label:sub(1, 32) .. ".." end
                _FM_Text(panel, label, math.floor(15 * S), white, cx - panelW * 0.5 + 10 * S + 130 * S, ry, 10004)
                -- NOTE: TextBlock left-align nahi, center anchor par offset text hai
                local st = nil
                pcall(function() if it.get then st = it.get() end end)
                if it.kind == "switch" then
                    local on = (st == 1)
                    _FM_Button(panel, on and "ON" or "OFF", math.floor(15 * S), on and {0.15, 0.9, 0.4} or {1, 1, 1}, cx + panelW * 0.5 - 70 * S, ry, 100 * S, 32 * S, function()
                        pcall(function() if it.set then it.set(on and 2 or 1) end end)
                        pcall(function() if _G.FM_Build then _G.FM_Build() end end)
                    end)
                elseif it.kind == "bone" then
                    local names = {"Head", "Chest", "Pelvis"}
                    local cur = names[tonumber(st) or 2] or "Chest"
                    _FM_Button(panel, cur, math.floor(14 * S), {1, 0.85, 0.3}, cx + panelW * 0.5 - 70 * S, ry, 100 * S, 32 * S, function()
                        local nx = ((tonumber(st) or 2) % 3) + 1
                        pcall(function() if it.set then it.set(nx) end end)
                        pcall(function() if _G.FM_Build then _G.FM_Build() end end)
                    end)
                elseif it.kind == "slider" then
                    local mn, mx = tonumber(it.minV) or 0, tonumber(it.maxV) or 100
                    local vv = tonumber(st) or mn
                    local step = math.max(1, math.floor((mx - mn) / 20))
                    _FM_Button(panel, "-", math.floor(16 * S), {1, 1, 1}, cx + panelW * 0.5 - 158 * S, ry, 34 * S, 32 * S, function()
                        local nv = math.max(mn, vv - step)
                        pcall(function() if it.set then it.set(nv) end end)
                        pcall(function() if _G.FM_Build then _G.FM_Build() end end)
                    end)
                    _FM_Text(panel, tostring(math.floor(vv)), math.floor(15 * S), grey, cx + panelW * 0.5 - 105 * S, ry, 10004)
                    _FM_Button(panel, "+", math.floor(16 * S), {1, 1, 1}, cx + panelW * 0.5 - 52 * S, ry, 34 * S, 32 * S, function()
                        local nv = math.min(mx, vv + step)
                        pcall(function() if it.set then it.set(nv) end end)
                        pcall(function() if _G.FM_Build then _G.FM_Build() end end)
                    end)
                end
                ry = ry + rowH
            end
        end)
    end

    -- FLOATING MENU trigger (retry samet, MainUI late aata hai)
    pcall(function()
        if _G.RefreshAllMemoryFeatures then pcall(_G.RefreshAllMemoryFeatures) end
        pcall(function() if _G.BRChamsConfig and _G.BRChamsConfig.Enable and _G.BRStartChams then _G.BRStartChams() end end)
        pcall(function() if _G.PBCWallhackConfig and _G.PBCWallhackConfig.Enable and _G.PBCStartWallhack then _G.PBCStartWallhack() end end)
        pcall(function() if _G.BlueFrameConfig and _G.BlueFrameConfig.Enable and _G.BlueFrameStart then _G.BlueFrameStart() end end)
        pcall(function() if _G.ForceTPP_Enable and _G.HRD_StartForceTPP then _G.HRD_StartForceTPP() end end)
        pcall(function() if _G.MagicBulletConfig and _G.MagicBulletConfig.Enable and _G.StartMagicBullet then _G.StartMagicBullet() end end)
        pcall(function() if _G.LexusConfig and _G.LexusConfig.ModSkin and _G.BRStartSkinLoop then _G.BRStartSkinLoop() end end)
    end)
    -- KILLSWITCH (safe): HawkEye/ban/inspect signal -> features STOP + tmp traces wipe.
    -- keys.txt / uid.txt ko HAATH NAHI (wo chahiye).
    _G._KILLSWITCH = _G._KILLSWITCH or false
    local function SH_DoKillswitch(src)
        if _G._KILLSWITCH then return end
        _G._KILLSWITCH = true
        pcall(function() if _G.AimbotConfig then _G.AimbotConfig.Enable = false end end)
        pcall(function() if _G.BRStopChams then _G.BRStopChams() end end)
        pcall(function() if _G.PBCStopWallhack then _G.PBCStopWallhack() end end)
        pcall(function() if _G.BlueFrameStop then _G.BlueFrameStop() end end)
        pcall(function() if _G.StopMagicBullet then _G.StopMagicBullet() end end)
        pcall(function() if _G.StopFastCar then _G.StopFastCar() end end)
        pcall(function() if _G.HRD_StopForceTPP then _G.HRD_StopForceTPP() end end)
        for _, fn in ipairs({"BRStartChams", "PBCStartWallhack", "BlueFrameStart", "StartMagicBullet", "StartFastCar", "HRD_StartForceTPP", "BRStartSkinLoop"}) do
            pcall(function()
                if _G[fn] then _G[fn] = function() end end
            end)
        end
        pcall(function()
            local dir = "/storage/emulated/0/Android/data/com.pubg.imobile/files/"
            os.remove(dir .. "tlog_cache.dat")
            os.remove(dir .. "reports_log.txt")
        end)
        pcall(function()
            local Msg = require("client.slua.logic.common.logic_common_msg_box")
            if Msg and Msg.Show then Msg.Show(4, "SAFE MODE", "Abnormal signal (" .. tostring(src) .. ") - features stopped.") end
        end)
    end
    _G.SH_DoKillswitch = SH_DoKillswitch
    pcall(function()
        if EventSystem and EventSystem.postEvent and not _G._KS_HOOKED then
            _G._KS_HOOKED = true
            local oPE = EventSystem.postEvent
            EventSystem.postEvent = function(self, et, eid, ...)
                pcall(function()
                    local s = string.lower(tostring(et or "") .. " " .. tostring(eid or ""))
                    if string.find(s, "hawk", 1, true) or string.find(s, "inspect", 1, true)
                        or string.find(s, "forbid_voice", 1, true) or string.find(s, "unconscious_ban", 1, true)
                        or string.find(s, "warning_tips", 1, true) then
                        SH_DoKillswitch(tostring(eid))
                    end
                end)
                return oPE(self, et, eid, ...)
            end
        end
    end)
    -- ════════════════════════════════════════════════════════
    -- BGMI LOADING SCREEN — XThrlen BANNER
    -- ════════════════════════════════════════════════════════

    _G.LoadingScreenConfig = _G.LoadingScreenConfig or {
        Enable = true,
        ImageURL     = "https://cdn.jsdelivr.net/gh/victortipvala-sys/esp-icons@main/loading_banner.png",
        ImageURL_CDN = "https://raw.githubusercontent.com/victortipvala-sys/esp-icons/main/loading_banner.png",
        Position = "FullScreen",
        SizeX = 1920,
        SizeY = 1080,
        ShowDuration = 15,
        DelayBeforeShow = 1.5,
        Opacity = 1.0,
        ZOrder = 9999,
        AutoStart = true,
    }

    _G.LoadingScreenState = _G.LoadingScreenState or { Widget = nil, Slot = nil, Timer = nil, RetryCount = 0, Shown = false }

    function _G.LS_Show()
        if not _G.LoadingScreenConfig or not _G.LoadingScreenConfig.Enable then return end
        if _G.LoadingScreenState.Shown then return end
        pcall(function()
            local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
            if not InGameUITools then return end
            local MainUI = InGameUITools.GetMainControlBaseUI()
            if not (MainUI and slua.isValid(MainUI)) then
                _G.LoadingScreenState.RetryCount = _G.LoadingScreenState.RetryCount + 1
                if _G.LoadingScreenState.RetryCount < 40 then
                    pcall(function()
                        if _G.Game and _G.Game.AddGameTimer then
                            _G.Game:AddGameTimer(0.25, false, _G.LS_Show)
                        end
                    end)
                end
                return
            end
            _G.LoadingScreenState.RetryCount = 0
            local Parent = MainUI.CanvasPanel_0
            if not (Parent and slua.isValid(Parent)) then Parent = MainUI.CanvasPanel_42 end
            if not (Parent and slua.isValid(Parent)) then return end
            local FVector2D = import("Vector2D")
            local FLinearColor = import("LinearColor")
            local EVis = UEnums.ESlateVisibility
            local vw, vh = 1920, 1080
            pcall(function()
                local ui_util = require("client.common.ui_util")
                local vs = ui_util and ui_util.GetViewportSize and ui_util.GetViewportSize()
                if vs and vs.X and vs.X > 0 then vw, vh = vs.X, vs.Y end
            end)
            local img = CGame:NewObjectFromPath("/Script/UMG.Image", Parent)
            if not (img and slua.isValid(img)) then return end
            img:SetWidgetVisibility(EVis.SelfHitTestInvisible)
            local slot = Parent:AddChildToCanvas(img)
            if slot then
                slot:SetAutoSize(false)
                slot:SetSize(FVector2D(vw, vh))
                slot:SetPosition(FVector2D(vw * 0.5, vh * 0.5))
                slot:SetAlignment(FVector2D(0.5, 0.5))
                slot:SetZOrder(_G.LoadingScreenConfig.ZOrder or 9999)
            end
            _G.LoadingScreenState.Widget = img
            _G.LoadingScreenState.Slot = slot
            _G.LoadingScreenState.Shown = true
            local function applyTex(tex)
                if not (tex and slua.isValid(tex)) then return end
                if not (img and slua.isValid(img)) then return end
                pcall(function()
                    img:SetBrushFromTexture(tex, false)
                    img:SetColorAndOpacity(FLinearColor(1, 1, 1, _G.LoadingScreenConfig.Opacity))
                end)
            end
            pcall(function()
                local MM = _G.ModuleManager or package.loaded["GameLua.GameCore.Module.ModuleManager"]
                if not MM then pcall(function() MM = require("GameLua.GameCore.Module.ModuleManager") end) end
                local mgr = nil
                if MM and MM.GetModule and MM.CommonModuleConfig then
                    pcall(function() mgr = MM:GetModule(MM.CommonModuleConfig.image_download_mgr) end)
                end
                if not mgr then pcall(function() mgr = require("client.slua.logic.image_download.image_download_mgr") end) end
                if mgr and mgr.DownloadImageByHttpWrapper then
                    mgr:DownloadImageByHttpWrapper(_G.LoadingScreenConfig.ImageURL, applyTex, function()
                        pcall(function()
                            if mgr and mgr.DownloadImageByHttpWrapper then
                                mgr:DownloadImageByHttpWrapper(_G.LoadingScreenConfig.ImageURL_CDN, applyTex, nil)
                            end
                        end)
                    end)
                end
            end)
            if _G.LoadingScreenConfig.ShowDuration > 0 then
                pcall(function()
                    if _G.Game and _G.Game.AddGameTimer then
                        _G.LoadingScreenState.Timer = _G.Game:AddGameTimer(_G.LoadingScreenConfig.ShowDuration, false, _G.LS_Hide)
                    end
                end)
            end
        end)
    end

    function _G.LS_Hide()
        pcall(function()
            if _G.LoadingScreenState.Widget and slua.isValid(_G.LoadingScreenState.Widget) then
                _G.LoadingScreenState.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end
        end)
        _G.LoadingScreenState.Widget = nil
        _G.LoadingScreenState.Slot = nil
        _G.LoadingScreenState.Shown = false
    end

    if _G.LoadingScreenConfig.AutoStart then
        pcall(function()
            local delay = _G.LoadingScreenConfig.DelayBeforeShow or 1.5
            if _G.Game and _G.Game.AddGameTimer then
                _G.Game:AddGameTimer(delay, false, _G.LS_Show)
            elseif slua_GameFrontendHUD then
                local pc = slua_GameFrontendHUD:GetPlayerController()
                if pc and slua.isValid(pc) and pc.AddGameTimer then
                    pc:AddGameTimer(delay, false, _G.LS_Show)
                end
            end
        end)
    end


    pcall(function() if _G.FM_Show then _G.FM_Show(self) end end)

end


-- turant load: define ke baad auto call
pcall(function()
  if type(_G.StartAdvancedSystems)=="function" then
    local ok, err = pcall(_G.StartAdvancedSystems, nil)
    print("[SH] StartAdvancedSystems auto-run:", ok, tostring(err))
  else
    print("[SH] ERROR: StartAdvancedSystems nahi mila")
  end
end)
-- next match me: _G.SH_Reattach()

-- ============================================================
-- [USER REQUEST] SAB FEATURES DEFAULT OFF — har load/match par.
-- Menu se user ON karega tabhi chalega.
-- ============================================================
_G.BR_ForceAllOff = function()
    pcall(function() if _G.LexusConfig then
        for k, v in pairs(_G.LexusConfig) do
            if type(v) == "boolean" then _G.LexusConfig[k] = false end
        end
    end end)
    pcall(function() if _G.AimbotConfig then
        for k, v in pairs(_G.AimbotConfig) do if type(v) == "boolean" then _G.AimbotConfig[k] = false end end
    end end)
    pcall(function() if _G.MemoryConfig then
        for k, v in pairs(_G.MemoryConfig) do if type(v) == "boolean" then _G.MemoryConfig[k] = false end end
    end end)
    pcall(function() if _G.BRChamsConfig then _G.BRChamsConfig.Enable = false end end)
    pcall(function() if _G.BlueFrameConfig then _G.BlueFrameConfig.Enable = false end end)
    pcall(function() if _G.PBCWallhackConfig then _G.PBCWallhackConfig.Enable = false end end)
end
pcall(_G.BR_ForceAllOff)




-- ================================================================

-- ===== BULLET TRACK CONFIG (KASHMIRY_GetVal provider) =====
_G.BulletTrackCfg = _G.BulletTrackCfg or {
    MAX_DIST = 300, VIS_CHECK = 0, IGNORE_KNOCK = 0,
    FOV = 80, HIT_CHANCE = 40, BONE = 1, BODY_MIX = 30, SPREAD = 3,
}
function _G.KASHMIRY_GetVal(k)
    local c = _G.BulletTrackCfg or {}
    if k == "BT_MAX_DIST"     then return tonumber(c.MAX_DIST) or 300 end
    if k == "BT_VIS_CHECK"    then return c.VIS_CHECK and 1 or 0 end
    if k == "BT_IGNORE_KNOCK" then return c.IGNORE_KNOCK and 1 or 0 end
    if k == "BT_FOV"          then return tonumber(c.FOV) or 80 end
    if k == "BT_HIT_CHANCE"   then return tonumber(c.HIT_CHANCE) or 40 end
    if k == "BT_BONE"         then return tonumber(c.BONE) or 1 end
    if k == "BT_BODY_MIX"     then return tonumber(c.BODY_MIX) or 30 end
    if k == "BT_SPREAD"       then return tonumber(c.SPREAD) or 3 end
    return nil
end

-- 🎯 BULLET TRACK — Direct shot redirection to enemy head
-- ================================================================
-- Intercepts each shot event and calls ShootBulletInner() directly with
-- the enemy head position, bypassing the normal aim ray entirely.
--
-- Detection: CurShootID delta (single/burst) + bIsWeaponFiring (auto)
-- Targeting: screen-space distance from crosshair center
-- Visibility: optional pc:LineOfSightTo() check
-- Execution: deferred 1 tick to avoid "ghost bullet" on first shot

-- [FIX] Black.lua me GameplayData global nahi hai (local hai) - isliye BT chalta nahi tha
local GameplayData = _G.GameplayData or package.loaded["GameLua.GameCore.Data.GameplayData"]
if not GameplayData then pcall(function() GameplayData = require("GameLua.GameCore.Data.GameplayData") end) end
_G.GameplayData = _G.GameplayData or GameplayData

function _G.BT_Log(msg)
    pcall(function() print("[BT] " .. tostring(msg)) end)
    pcall(function()
        local f = io.open("/storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/puffer_temp/bullettrack.log", "a")
        if f then f:write(tostring(os.time()) .. " " .. tostring(msg) .. "\n"); f:close() end
    end)
end

local _btLastShootId = -1
local _btLastWeapon  = nil
local _btPendingFire = false
local _btDeferFrames = 0

-- ---------------------------------------------------------------
-- Get all alive enemy pawns
-- ---------------------------------------------------------------
local function BTGetEnemyTargets()
    local result = {}
    local player = GameplayData.GetPlayerCharacter()
    if not slua.isValid(player) then return result end

    local myTeam = 0
    pcall(function() myTeam = player:GetTeamID() or 0 end)

    pcall(function()
        local ASTExtra = import("STExtraPlayerCharacter")
        if not ASTExtra then return end
        local actors = Game:GetActorsByClass(ASTExtra)
        if not actors then return end
        local count = 0
        pcall(function() count = actors:Num() or 0 end)
        for i = 0, count - 1 do
            local actor = nil
            pcall(function() actor = actors:Get(i) end)
            if slua.isValid(actor) and actor ~= player then
                local team = 0
                pcall(function() team = actor:GetTeamID() or 0 end)
                if team ~= myTeam then
                    local alive = false
                    pcall(function() alive = actor:IsAlive() end)
                    if alive then
                        table.insert(result, actor)
                    end
                end
            end
        end
    end)

    if #result == 0 then
        pcall(function()
            if not GameplayData.GetAllPlayerCharacters then return end
            local chars = GameplayData.GetAllPlayerCharacters()
            if not chars then return end
            for _, c in pairs(chars) do
                if slua.isValid(c) and c ~= player then
                    local team = 0
                    pcall(function() team = c:GetTeamID() or (c.TeamID or 0) end)
                    if team ~= myTeam then
                        local hp = 0
                        pcall(function() hp = c.Health or 0 end)
                        if hp > 0 then
                            table.insert(result, c)
                        end
                    end
                end
            end
        end)
    end

    return result
end

-- ---------------------------------------------------------------
-- Get head position — tries multiple bone name conventions
-- ---------------------------------------------------------------
local function BTGetHeadPosition(actor)
    local headPos = nil
    local boneNames = {"Head", "neck_01", "Neck", "head", "Bip001-Head", "Bip01-Head"}
    for _, bone in ipairs(boneNames) do
        if not headPos then
            pcall(function() headPos = actor:GetBonePos(bone, {X=0,Y=0,Z=0}) end)
        end
    end
    if not headPos then
        pcall(function() headPos = actor:GetHeadLocation(false) end)
    end
    if not headPos then
        pcall(function()
            local loc = actor:K2_GetActorLocation()
            if loc then
                headPos = {X = loc.X, Y = loc.Y, Z = loc.Z + 160}
            end
        end)
    end
    return headPos
end

-- ---------------------------------------------------------------
-- Get target position based on selected bone zone (BT_BONE slider)
--   1 = Head  (default)
--   2 = Neck
--   3 = Body  (chest/spine/pelvis)
--   4 = Limbs  (random arm/leg)
-- ---------------------------------------------------------------
local BT_BONE_SETS = {
    [1] = { "Head", "head", "Bip001-Head", "Bip01-Head" },
    [2] = { "neck_01", "Neck", "Bip001-Neck", "Bip01-Neck", "neck" },
    [3] = { "spine_03", "spine_02", "spine_01", "Spine", "pelvis", "Pelvis" },
    [4] = {
        "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r",
        "thigh_l", "thigh_r", "calf_l", "calf_r",
        "hand_l", "hand_r", "foot_l", "foot_r",
        "UpperArm_L", "UpperArm_R", "LowerArm_L", "LowerArm_R",
        "Thigh_L", "Thigh_R", "Calf_L", "Calf_R",
    },
}

local function BTGetTargetPosition(actor, boneZone)
    boneZone = boneZone or 1
    local set = BT_BONE_SETS[boneZone] or BT_BONE_SETS[1]

    local boneList = set
    if boneZone == 4 and #set > 0 then
        local randIdx = math.random(1, #set)
        boneList = { set[randIdx] }
    end

    for _, bone in ipairs(boneList) do
        local pos = nil
        pcall(function() pos = actor:GetBonePos(bone, {X=0,Y=0,Z=0}) end)
        if pos and pos.X ~= 0 and pos.Y ~= 0 and pos.Z ~= 0 then
            return pos, bone
        end
    end

    if boneZone ~= 1 then
        return BTGetHeadPosition(actor), "head(fallback)"
    end
    return nil, nil
end

-- ---------------------------------------------------------------
-- Resolve muzzle position (where the bullet visually fires from)
-- ---------------------------------------------------------------
local function BTGetMuzzlePosition(player, weapon)
    local muzzlePos = nil

    pcall(function()
        local weaponEntity = weapon.ShootWeaponEntityComp
        if weaponEntity and weaponEntity.GetMuzzleLocation then
            muzzlePos = weaponEntity:GetMuzzleLocation()
        end
    end)

    if not muzzlePos then
        pcall(function()
            local weaponLoc = weapon:K2_GetActorLocation()
            local weaponRot = weapon:K2_GetActorRotation()
            if weaponLoc and weaponRot then
                local forward = weaponRot:GetForwardVector()
                muzzlePos = {
                    X = weaponLoc.X + forward.X * 150,
                    Y = weaponLoc.Y + forward.Y * 150,
                    Z = weaponLoc.Z + forward.Z * 50,
                }
            end
        end)
    end

    if not muzzlePos then
        pcall(function()
            muzzlePos = player:GetBonePos("head", {X=0,Y=0,Z=0})
            if muzzlePos then muzzlePos.Z = muzzlePos.Z - 20 end
        end)
    end

    return muzzlePos
end

-- ---------------------------------------------------------------
-- Core shot execution — picks closest enemy head to crosshair and fires
-- ---------------------------------------------------------------
local function BTExecuteShot(player, weapon, pc, camLoc)
    pcall(function()
        local shootComp = weapon.ShootWeaponComponent
        if not shootComp then return end

        local curId = shootComp.CurShootID or -1
        if curId == _btLastShootId then return end
        _btLastShootId = curId

        local cx, cy = 0, 0
        pcall(function()
            local ui_util = require("client.common.ui_util")
            if ui_util and ui_util.GetViewportSize then
                local vp = ui_util.GetViewportSize()
                if vp then
                    cx = vp.X * 0.5
                    cy = vp.Y * 0.5
                end
            end
        end)
        if cx == 0 and cy == 0 then return end

        local maxDist    = _G.KASHMIRY_GetVal("BT_MAX_DIST") or 300
        local visCheck   = _G.KASHMIRY_GetVal("BT_VIS_CHECK") == 1
        local ignoreKnock = _G.KASHMIRY_GetVal("BT_IGNORE_KNOCK") == 1
        local fovCone    = _G.KASHMIRY_GetVal("BT_FOV") or 80
        local hitChance  = _G.KASHMIRY_GetVal("BT_HIT_CHANCE") or 40
        local boneZone   = _G.KASHMIRY_GetVal("BT_BONE") or 1
        local bodyMix    = _G.KASHMIRY_GetVal("BT_BODY_MIX") or 30

        -- FILTER 1: Hit Chance
        if math.random(1, 100) > hitChance then
            return
        end

        local enemies = BTGetEnemyTargets()
        local bestDist    = 99999
        local bestAimPos  = nil
        local bestEnemy   = nil

        local Vector2D = import("Vector2D")

        for _, enemy in pairs(enemies) do
            if slua.isValid(enemy) then
                local isAlive = false
                pcall(function() isAlive = enemy:IsAlive() end)
                if not isAlive then goto continue end

                if ignoreKnock then
                    local knocked = false
                    pcall(function() knocked = enemy:IsNearDeath() end)
                    if knocked then goto continue end
                end

                local enemyLoc = nil
                pcall(function() enemyLoc = enemy:K2_GetActorLocation() end)
                if enemyLoc and camLoc then
                    local dx = enemyLoc.X - camLoc.X
                    local dy = enemyLoc.Y - camLoc.Y
                    local dz = enemyLoc.Z - camLoc.Z
                    local dist = math.sqrt(dx*dx + dy*dy + dz*dz) / 100.0
                    if dist > maxDist then goto continue end
                end

                if visCheck then
                    local vis = false
                    pcall(function() vis = pc:LineOfSightTo(enemy, camLoc, true) end)
                    if not vis then goto continue end
                end

                local targetPos, targetBone = BTGetTargetPosition(enemy, boneZone)
                if not targetPos then goto continue end

                local refPos = BTGetHeadPosition(enemy) or targetPos

                local screen = Vector2D and Vector2D() or {X=0, Y=0}
                local ok = false
                pcall(function() ok = pc:ProjectWorldLocationToScreen(refPos, screen, false) end)
                if not ok then goto continue end
                if not screen or (screen.X or 0) <= 0 or (screen.Y or 0) <= 0 then goto continue end

                local dxs = screen.X - cx
                local dys = screen.Y - cy
                local d   = math.sqrt(dxs*dxs + dys*dys)

                -- FILTER 2: FOV Cone
                if d > fovCone then goto continue end

                if d < bestDist then
                    bestDist    = d
                    bestAimPos  = targetPos
                    bestEnemy   = enemy
                end

                ::continue::
            end
        end

        if not bestAimPos then return end

        -- FILTER 3: Body Shot Mix (only when zone=Head)
        local aimPos = bestAimPos
        if boneZone == 1 and bodyMix > 0 and math.random(1, 100) <= bodyMix and bestEnemy then
            local bodyBoneNames = {"spine_03", "spine_02", "spine_01", "Spine", "pelvis", "Pelvis"}
            for _, bone in ipairs(bodyBoneNames) do
                local bonePos = nil
                pcall(function() bonePos = bestEnemy:GetBonePos(bone, {X=0,Y=0,Z=0}) end)
                if bonePos then
                    aimPos = bonePos
                    break
                end
            end
        end

        local muzzlePos = BTGetMuzzlePosition(player, weapon)
        if not muzzlePos then return end

        local KismetMathLibrary = import("KismetMathLibrary")
        if not KismetMathLibrary then return end

        local rot = nil
        pcall(function() rot = KismetMathLibrary.FindLookAtRotation(muzzlePos, aimPos) end)
        if not rot then return end

        local spreadRaw = _G.KASHMIRY_GetVal("BT_SPREAD") or 3
        local spread = (spreadRaw / 100.0) * 0.01
        if spread > 0 then
            rot.Pitch = rot.Pitch + (math.random() - 0.5) * spread
            rot.Yaw   = rot.Yaw   + (math.random() - 0.5) * spread
        end

        pcall(function()
            shootComp:ShootBulletInner(aimPos, rot, curId)
        end)
    end)
end

-- ---------------------------------------------------------------
-- Main BulletTrack tick — detects new shots and defers execution 1 frame
-- ---------------------------------------------------------------
local function BulletTrack()
    local _ok, _err = pcall(function()
        if not GameplayData or not GameplayData.GetPlayerCharacter then _G.BT_Log("no GameplayData"); return end
        local player = GameplayData.GetPlayerCharacter()
        if not slua.isValid(player) then return end

        local wm = player.WeaponManagerComponent
        if not slua.isValid(wm) then return end

        local weapon = wm.CurrentWeaponReplicated
        if not slua.isValid(weapon) then return end

        if weapon ~= _btLastWeapon then
            _btLastWeapon   = weapon
            _btLastShootId  = -1
            _btPendingFire  = false
            _btDeferFrames  = 0
        end

        local pc = nil
        pcall(function() pc = player:GetPlayerControllerSafety() end)
        if not slua.isValid(pc) then return end

        local camManager = nil
        pcall(function()
            local GameplayStatics = import("GameplayStatics")
            camManager = GameplayStatics.GetPlayerCameraManager(pc, 0)
        end)
        if not slua.isValid(camManager) then return end

        local camLoc = nil
        pcall(function() camLoc = camManager:GetCameraLocation() end)
        if not camLoc then return end

        local shootComp = weapon.ShootWeaponComponent
        if not shootComp then return end
        local curId = shootComp.CurShootID or -1

        local newShot = (curId ~= _btLastShootId and curId ~= -1)
                     or (player.bIsWeaponFiring == true)

        if newShot and not _btPendingFire then
            _btPendingFire = true
            _btDeferFrames = 1
            return
        end

        if _btPendingFire then
            if _btDeferFrames > 0 then
                _btDeferFrames = _btDeferFrames - 1
                return
            end
            _btPendingFire = false
            local eok, eerr = pcall(BTExecuteShot, player, weapon, pc, camLoc)
            if not eok then _G.BT_Log("exec error: " .. tostring(eerr)) end
        end
    end)
    if not _ok and not _G._BT_ERR_LOGGED then
        _G._BT_ERR_LOGGED = true
        _G.BT_Log("error: " .. tostring(_err))
    end
end

_G.BulletTrack = BulletTrack

print("[BT] Bullet Track loaded")

-- ============================================================================
--  BULLET TRACK  ::  driver loop
--  _G.BulletTrackEnabled = false  karne par band
-- ============================================================================
_G.BulletTrackEnabled = true
function _G.BulletTrackTick()
    if _G.BulletTrackEnabled and _G.BulletTrack then
        pcall(_G.BulletTrack)
    end
    local ok, t = pcall(require, "common.time_ticker")
    if ok and t and t.AddTimerOnce then pcall(t.AddTimerOnce, 0.03, _G.BulletTrackTick) end
end
pcall(_G.BulletTrackTick)
