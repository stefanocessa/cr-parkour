local Vec = require 'client.core.vec'
local State = require 'client.core.state'
local Context = require 'client.core.context'
local Scanner = require 'client.core.scanner'
local Lifecycle = require 'client.core.lifecycle'
local Recovery = require 'client.core.recovery'
local Cooldown = require 'client.core.cooldowns'
local Animation = require 'client.systems.animation'
local Momentum = require 'client.systems.momentum'
local Camera = require 'client.systems.camera'
local LedgeAbility = require 'client.abilities.ledge'
local Shimmy = require 'client.abilities.shimmy'
local Wallrun = require 'client.abilities.wallrun'
local Rays = require 'client.debug.rays'
local DebugState = require 'client.debug.state'
local Tuning = require 'client.debug.tuning'

local Snapshot = {}

local vec = function(v)
    return v and Vec.Format(v) or '-'
end

local num = function(v)
    return v and ('%.3f'):format(v) or '-'
end

local currentWall = function(scan)
    local wall = Wallrun.Current()
    if wall then return wall, 'wallrun' end
    local walls = scan and scan.walls or {}
    for _, side in ipairs({ 'left', 'right', 'front' }) do
        if walls[side] and walls[side].valid then return walls[side], side end
    end
    return nil, nil
end

local currentLedge = function(scan)
    local ledge = Shimmy.Current() or LedgeAbility.Current()
    if ledge then return ledge, 'attivo' end
    if scan and scan.ledge and scan.ledge.valid then return scan.ledge, 'scansione' end
    return nil, nil
end

Snapshot.Build = function()
    local ctx = Context.Get()
    if not ctx.coords then return 'contesto non ancora inizializzato' end
    local scan = Scanner.Last()
    local run = Lifecycle.Run()
    local anim = Animation.State()
    local entry = Momentum.LastEntry()
    local wall, wallSource = currentWall(scan)
    local ledge, ledgeSource = currentLedge(scan)
    local canParkour, blockedReason = Context.CanParkour(ctx)
    local lines = {}
    local add = function(text) lines[#lines + 1] = text end

    add(('cr-parkour snapshot @ %d  preset %s'):format(ctx.now, Config.ActivePreset or 'balanced'))
    add(('STATE: %s  (prev %s, %d ms)'):format(State.Current(), State.Previous(), State.Elapsed()))
    add(('ABILITY: %s  phase %s'):format(run and run.ability or '-', run and run.phase or '-'))
    add(('can parkour: %s%s  armed %s'):format(tostring(canParkour), canParkour and '' or (' (' .. blockedReason .. ')'), tostring(ctx.armed)))
    add('')
    add(('coords: %s'):format(vec(ctx.coords)))
    add(('heading: %.2f'):format(ctx.heading))
    add(('speed: %.3f  2d %.3f'):format(ctx.speed, ctx.speed2d))
    add(('velocity: %s'):format(vec(ctx.velocity)))
    add(('grounded %s  airborne %s  coyote %s  ground clearance %s  fall %s'):format(tostring(ctx.grounded), tostring(ctx.airborne), tostring(ctx.coyote), num(ctx.groundClearance), num(ctx.fallDistance)))
    add('')
    add(('wall (%s): normal %s  distance %s  angle %s'):format(wallSource or '-', vec(wall and wall.normal), num(wall and wall.distance), num(wall and wall.angle)))
    add(('ledge (%s): edge %s  distance %s  height %s'):format(ledgeSource or '-', vec(ledge and ledge.edge), num(ledge and ledge.distance), num(ledge and ledge.height)))
    if ledge then
        add(('  normal %s  hang %s  heading %s  climbable %s  headClear %s'):format(vec(ledge.normal), vec(ledge.hang), num(ledge.heading), tostring(ledge.climbable), tostring(ledge.headClear)))
    end
    local obstacle = scan and scan.obstacle
    if obstacle and obstacle.hit then
        add(('obstacle: h %s  depth %s  dist %s  angle %s  reason %s  surface %s'):format(num(obstacle.height), num(obstacle.depth), num(obstacle.distance), num(obstacle.approachAngle), tostring(obstacle.reason), tostring(obstacle.surface)))
        add(('  groundZ %s  baseZ %s  edgeZ %s  topZ %s  landingZ %s  variance %s  top %s'):format(num(obstacle.groundZ), num(obstacle.baseZ), num(obstacle.edgeZ), num(obstacle.topZ), num(obstacle.landingZ), num(obstacle.topVariance), tostring(obstacle.topReason or 'ok')))
    end
    add('')
    if anim then
        add(('animation: %s  [%s]%s'):format(anim.name, anim.label, anim.fallbackBug and ' BUG: custom presente ma non usata' or ''))
        add(('dict: %s'):format(anim.dict or '-'))
        add(('clip: %s'):format(anim.clip or '-'))
        add(('normalized time: %s  reason %s  headingOffset %s'):format(num(anim.progress), tostring(anim.reason), num(anim.headingOffset)))
        local extra = anim.extraOffset or {}
        add(('tuning offset: f %s r %s u %s wall %s h %s'):format(num(extra.forward), num(extra.right), num(extra.up), num(extra.wallOffset), num(extra.heading)))
    else
        add('animation: -')
    end
    add('')
    add(('entry momentum: %s  (%s)'):format(vec(entry and entry.velocity), num(entry and entry.speed2d)))
    add(('current momentum: %s  (%s)'):format(vec(ctx.velocity), num(ctx.speed2d)))
    local camera = Camera.State()
    add(('camera: roll %.2f fov %+.2f overlay %s %s'):format(camera.roll, camera.fov, tostring(camera.overlay), table.concat(camera.effects, ',')))
    local cooldowns = Cooldown.Info(ctx.now)
    add(('cooldown: %s'):format(#cooldowns > 0 and table.concat(cooldowns, '  ') or '-'))
    local recovery = Recovery.Last()
    add(('last recovery: %s'):format(recovery and ('%s (%d ms fa)'):format(recovery.reason, ctx.now - recovery.at) or '-'))
    add('')

    if Rays.IsEnabled() then
        add('last reasons:')
        local reasons = DebugState.LastReasons()
        local keys = {}
        for key in pairs(reasons) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local reason = reasons[key]
            add(('  %s: %s%s  (%d ms fa)'):format(key, reason.code, reason.detail and (' (' .. tostring(reason.detail) .. ')') or '', ctx.now - reason.at))
        end
        local vault = DebugState.VaultInfo()
        if vault then
            local parts = {}
            for _, c in ipairs(vault.list) do
                parts[#parts + 1] = c.score and ('%s=%.2f'):format(c.name, c.score) or ('%s=x(%s)'):format(c.name, c.reason or '-')
            end
            add(('vault candidates: %s  selected = %s'):format(table.concat(parts, ' '), tostring(vault.selected)))
        end
    else
        add('last reasons: debug spento, attiva /parkourdebug per raccoglierli')
    end

    local changes = Tuning.Changes()
    if #changes > 0 then
        add('')
        add('tuning runtime:')
        for _, change in ipairs(changes) do add('  ' .. change) end
    end
    return table.concat(lines, '\n')
end

Snapshot.Copy = function()
    local text = Snapshot.Build()
    print(('[cr-parkour]\n%s'):format(text))
    lib.setClipboard(text)
    lib.notify({ title = 'Parkour', description = 'Snapshot copiato negli appunti e stampato in F8', type = 'success' })
    return text
end

return Snapshot
