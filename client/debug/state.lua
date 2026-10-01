local Vec = require 'client.core.vec'
local Rays = require 'client.debug.rays'

local DebugState = {}

local panel = Config.DebugPanel
local reasons = {}
local ledgeInfo = nil
local candidates = {}
local candidateOrder = { 'tictac', 'wallflip', 'precision', 'longjump', 'balance', 'trick' }
local ledgeAnimation = nil
local inputInfo = nil
local vaultInfo = nil
local vaultContext = nil
local underInfo = nil
local lastDeny = nil
local reasonOrder = { 'recovery', 'watchdog', 'parkour', 'input', 'vault', 'slide', 'roll', 'wallrun', 'walljump', 'wallclimb', 'ledge', 'shimmy', 'climb', 'balance', 'landing', 'anim' }
local positiveCodes = { [Constants.Reasons.OK] = true, [Constants.Reasons.ROLL_ARMED] = true, [Constants.Reasons.VAULT_STYLE] = true }

DebugState.SetReason = function(ability, code, detail)
    if not Rays.IsEnabled() then return end
    local last = reasons[ability]
    if last and last.code == code and last.detail == detail then
        last.at = GetGameTimer()
        return
    end
    reasons[ability] = { code = code, detail = detail, at = GetGameTimer() }
    if not positiveCodes[code] and code ~= Constants.Reasons.VAULT_DENIED_NO_OBSTACLE then
        lastDeny = { key = ability, code = code, detail = detail, at = GetGameTimer() }
    end
end

DebugState.Reason = DebugState.SetReason

DebugState.Ledge = function(ledge, heading, position)
    if not ledge then
        ledgeInfo = nil
        return
    end
    if not Rays.IsEnabled() then return end
    ledgeInfo = { ledge = ledge, heading = heading, position = position, at = GetGameTimer() }
    local edge = ledge.edge
    Rays.Line(edge, edge + ledge.normal * panel.vectorLength, 'blocked')
    Rays.Line(edge, edge + ledge.wallDir * panel.vectorLength, 'valid')
    Rays.Point(edge, 'ledge')
    Rays.Point(position, 'landing')
end

DebugState.LedgeAnimation = function(state)
    if not Rays.IsEnabled() or not state then return end
    local changed = not ledgeAnimation or ledgeAnimation.name ~= state.name or ledgeAnimation.source ~= state.source
    ledgeAnimation = state
    if not changed then return end
    lib.print.info(('[cr-parkour] Ledge animation: %s dict = %s clip = %s %s reason = %s headingOffset = %.1f'):format(
        state.name, state.dict or '-', state.clip or '-', state.label or state.source, state.reason or '-', state.headingOffset or 0.0))
end

local handInfo = nil
local printedCorrections = {}

DebugState.LedgeHands = function(key, correction, hands)
    if not Rays.IsEnabled() then return end
    handInfo = { key = key, correction = correction, at = GetGameTimer() }
    Rays.Point(hands, 'top')
end

DebugState.LedgeCorrections = function(corrections)
    if not Rays.IsEnabled() then return end
    for key, correction in pairs(corrections) do
        local text = ('up = %.2f, forward = %.2f'):format(correction.up, -correction.out)
        if printedCorrections[key] ~= text then
            printedCorrections[key] = text
            lib.print.info(('[cr-parkour] allineamento mani %s -> positionOffset = { %s, right = 0.0 }'):format(key, text))
        end
    end
end

DebugState.Candidate = function(name, ok, reason, info)
    if not Rays.IsEnabled() then return end
    local entry = candidates[name] or {}
    entry.ok, entry.reason, entry.at = ok, reason, GetGameTimer()
    if info then entry.info = info end
    candidates[name] = entry
end

DebugState.Input = function(info)
    inputInfo = info
end

DebugState.VaultCandidates = function(list, selected, measure)
    if not Rays.IsEnabled() then return end
    vaultInfo = { list = list, selected = selected, measure = measure, at = GetGameTimer() }
end

DebugState.UnderVariants = function(list, selected)
    if not Rays.IsEnabled() then return end
    underInfo = { list = list, selected = selected, at = GetGameTimer() }
end

DebugState.UnderPlan = function(passage, plan)
    if not Rays.IsEnabled() then return end
    underInfo = underInfo or { list = {} }
    underInfo.selected, underInfo.plan, underInfo.at = plan.name, plan, GetGameTimer()
end

DebugState.VaultContext = function(context)
    if not Rays.IsEnabled() then return end
    vaultContext = { context = context, at = GetGameTimer() }
end

DebugState.LastReasons = function()
    return reasons
end

DebugState.VaultInfo = function()
    return vaultInfo
end

local drawText = function(text, x, y, color)
    SetTextFont(panel.font)
    SetTextScale(0.0, panel.scale)
    SetTextColour(color[1], color[2], color[3], color[4])
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local yesNo = function(value)
    return value and 'yes' or 'no'
end

local number = function(value)
    return value and ('%.2f'):format(value) or '-'
end

local animationLines = function(lines, extras)
    local anim = extras and extras.animation
    local entry = extras and extras.entry
    if anim then
        local color = anim.fallbackBug and Constants.Colors.blocked or Constants.Colors.top
        lines[#lines + 1] = { ('anim %s %s%s  t %s'):format(anim.name, anim.label, anim.fallbackBug and ' (BUG: custom presente)' or '', number(anim.progress)), color }
        lines[#lines + 1] = { ('dict %s  clip %s  root %s'):format(anim.dict or '-', anim.clip or '-', yesNo(anim.rootMotion)) }
        local extra = anim.extraOffset
        if extra and ((extra.forward or 0) ~= 0 or (extra.right or 0) ~= 0 or (extra.up or 0) ~= 0 or (extra.heading or 0) ~= 0 or (extra.wallOffset or 0) ~= 0) then
            lines[#lines + 1] = { ('tuning offset f %.2f r %.2f u %.2f wall %.2f h %.1f'):format(extra.forward or 0, extra.right or 0, extra.up or 0, extra.wallOffset or 0, extra.heading or 0) }
        end
    else
        lines[#lines + 1] = { 'anim -' }
    end
    lines[#lines + 1] = { ('entry vel %s  (%.2f)'):format(entry and Vec.Format(entry.velocity) or '-', entry and entry.speed2d or 0.0) }
end

local ledgeLines = function(lines, ctx)
    if not ledgeInfo or GetGameTimer() - ledgeInfo.at > panel.reasonTtl then return end
    local ledge = ledgeInfo.ledge
    local anim = ledgeAnimation
    lines[#lines + 1] = { 'LEDGE', Constants.Colors.ledge }
    lines[#lines + 1] = { ('wallNormal %s'):format(Vec.Format(ledge.normal)) }
    lines[#lines + 1] = { ('towardWall %s'):format(Vec.Format(ledge.wallDir)) }
    lines[#lines + 1] = { ('pedHeading %.1f  targetHeading %.1f  logical %.1f'):format(GetEntityHeading(ctx.ped), ledge.heading, ledgeInfo.heading) }
    lines[#lines + 1] = { ('headingOffset %.1f'):format(anim and anim.headingOffset or 0.0) }
    lines[#lines + 1] = { ('ledgePosition %s'):format(Vec.Format(ledge.edge)) }
    lines[#lines + 1] = { ('hangPosition %s'):format(Vec.Format(ledgeInfo.position)) }
    if handInfo and GetGameTimer() - handInfo.at <= panel.reasonTtl then
        local c = handInfo.correction
        lines[#lines + 1] = { ('mani err su %.2f fuori %.2f  corr su %.2f fuori %.2f'):format(c.errUp, c.errOut, c.up, c.out) }
    end
    if anim then
        lines[#lines + 1] = { ('anim %s  %s/%s  %s'):format(anim.name, anim.dict or '-', anim.clip or '-', anim.label or anim.source), anim.fallbackBug and Constants.Colors.blocked or nil }
        lines[#lines + 1] = { ('reason %s  rootMotion %s'):format(anim.reason or '-', yesNo(anim.rootMotion)) }
    end
end

local fmt = function(value)
    if type(value) == 'number' then return ('%.2f'):format(value) end
    if type(value) == 'boolean' then return yesNo(value) end
    return value ~= nil and tostring(value) or '-'
end

local candidateDetails = {
    precision = function(info)
        return ('  dist %s  dh %s  req %s  avail %s  landing %s  width %s'):format(
            fmt(info.distance), fmt(info.heightDelta), fmt(info.requiredSpeed), fmt(info.availableSpeed),
            fmt(info.landingValid), fmt(info.landingWidth))
    end,
    balance = function(info)
        return ('  width %s  left %s  right %s'):format(fmt(info.surfaceWidth), fmt(info.leftEdge), fmt(info.rightEdge))
    end,
    wallflip = function(info)
        return ('  back clearance %s  wall angle %s  wall dist %s'):format(fmt(info.backClearance), fmt(info.wallAngle), fmt(info.wallDistance))
    end,
    longjump = function(info)
        return ('  speed %s  air %s  landing %s'):format(fmt(info.speed), fmt(info.airTime), fmt(info.landing))
    end,
    trick = function(info)
        return ('  %s  ground %s  vz %s  air %s'):format(fmt(info.animation), fmt(info.groundDistance), fmt(info.verticalSpeed), fmt(info.airTime))
    end,
    tictac = function(info)
        return ('  %s  angle %s  wall %s'):format(fmt(info.side), fmt(info.angle), fmt(info.wallDistance))
    end,
}

local candidateLines = function(lines)
    local now = GetGameTimer()
    for i = 1, #candidateOrder do
        local name = candidateOrder[i]
        local entry = candidates[name]
        if entry and now - entry.at <= panel.reasonTtl then
            lines[#lines + 1] = { ('%sCandidate %s'):format(name, entry.ok and 'OK' or entry.reason), entry.ok and Constants.Colors.valid or Constants.Colors.blocked }
            if entry.info and candidateDetails[name] then lines[#lines + 1] = { candidateDetails[name](entry.info) } end
        end
    end
end

local shortName = function(name)
    return name and name:match('[^%.]+$') or '-'
end

local vaultLines = function(lines)
    if not vaultInfo or GetGameTimer() - vaultInfo.at > panel.reasonTtl then return end
    local m = vaultInfo.measure
    lines[#lines + 1] = { ('VAULT CLIPS  h %.2f d %.2f v %.2f a %.0f dist %.2f'):format(m.height or 0, m.depth or 0, m.speed or 0, m.angle or 0, m.distance or 0), Constants.Colors.top }
    for i = 1, #vaultInfo.list do
        local c = vaultInfo.list[i]
        local ok = c.score ~= nil
        local text = ok and ('  %s = %.2f'):format(shortName(c.name), c.score) or ('  %s = x %s'):format(shortName(c.name), c.reason or '-')
        lines[#lines + 1] = { text, c.name == vaultInfo.selected and Constants.Colors.valid or (ok and nil or Constants.Colors.blocked) }
    end
    if not vaultInfo.selected then
        lines[#lines + 1] = { '  CUSTOM ANIMATION NOT SELECTED', Constants.Colors.blocked }
    end
end

local comboLines = function(lines, extras)
    local combo = extras and extras.combo
    if not combo or not (combo.previous or combo.current) then return end
    lines[#lines + 1] = { ('combo prev %s  current %s  since %s ms'):format(combo.previous or '-', combo.current or '-', combo.since or '-') }
end

local parkourLines = function(lines, extras)
    local parkour = extras and extras.parkour
    if not parkour then return end
    lines[#lines + 1] = { ('PARKOUR HELD: %s'):format(tostring(parkour.held)), parkour.held and Constants.Colors.valid or Constants.Colors.blocked }
    lines[#lines + 1] = { ('candidate: %s   selected: %s'):format(parkour.candidate or 'NONE', parkour.selected or '-') }
    local stamina = parkour.stamina
    if stamina and stamina.enabled then
        lines[#lines + 1] = { ('stamina on  current %s / %s  required %s (%s)'):format(number(stamina.current), number(stamina.maximum), number(stamina.required), stamina.ability or '-') }
    else
        lines[#lines + 1] = { 'stamina off' }
    end
    if lastDeny and GetGameTimer() - lastDeny.at <= panel.reasonTtl then
        local text = lastDeny.detail and ('%s: %s (%s)'):format(lastDeny.key, lastDeny.code, lastDeny.detail) or ('%s: %s'):format(lastDeny.key, lastDeny.code)
        lines[#lines + 1] = { 'last deny ' .. text, Constants.Colors.blocked }
    end
end

local inputLines = function(lines)
    if not inputInfo then return end
    lines[#lines + 1] = { ('E -> %s   CTRL -> %s   SPACE -> %s'):format(inputInfo.primary or '-', inputInfo.secondary or 'GTA', inputInfo.jump), Constants.Colors.top }
    if inputInfo.buffered or inputInfo.coyote then
        lines[#lines + 1] = { ('buffer %s  coyote %s'):format(inputInfo.buffered or '-', yesNo(inputInfo.coyote)) }
    end
end

local lifecycleLines = function(lines, extras)
    local run = extras and extras.run
    if run then
        lines[#lines + 1] = { ('ability %s [%s] %s  %d ms'):format(run.ability, run.phase, run.state, GetGameTimer() - run.startedAt), Constants.Colors.ledge }
    end
    local camera = extras and extras.camera
    if camera and (camera.overlay or #camera.effects > 0) then
        lines[#lines + 1] = { ('camera roll %.2f  fov %+.2f  %s'):format(camera.roll, camera.fov, table.concat(camera.effects, ',')) }
    end
    local cooldowns = extras and extras.cooldowns
    if cooldowns and #cooldowns > 0 then
        lines[#lines + 1] = { ('cooldown %s'):format(table.concat(cooldowns, '  ')) }
    end
    if extras and extras.blocked then
        lines[#lines + 1] = { ('parkour bloccato: %s'):format(extras.blocked), Constants.Colors.blocked }
    end
    if extras and extras.preset then
        lines[#lines + 1] = { ('preset %s  armed %s'):format(extras.preset, yesNo(extras.armed)) }
    end
end

local buildLines = function(ctx, state, scan, extras)
    local walls = scan and scan.walls or {}
    local wall = walls.left and walls.left.valid and walls.left
        or walls.right and walls.right.valid and walls.right
        or walls.front and walls.front.valid and walls.front
    local ledge = scan and scan.ledge
    local obstacle = scan and scan.obstacle

    local lines = {
        { ('STATE  %s  (prev %s)'):format(state.Current(), state.Previous()), Constants.Colors.landing },
        { ('speed %.2f  2d %.2f'):format(ctx.speed, ctx.speed2d) },
        { ('velocity %s'):format(Vec.Format(ctx.velocity)) },
        { ('grounded %s  airborne %s  sprint %s'):format(yesNo(ctx.grounded), yesNo(ctx.airborne), yesNo(ctx.sprinting)) },
        { ('wall side %s  dist %s  angle %s'):format(wall and wall.side or '-', number(wall and wall.distance), number(wall and wall.angle)) },
        { ('ledge %s  dist %s  height %s'):format(yesNo(ledge and ledge.valid), number(ledge and ledge.distance), number(ledge and ledge.height)) },
        { ('obstacle h %s  d %s  dist %s'):format(number(obstacle and obstacle.hit and obstacle.height), number(obstacle and obstacle.hit and obstacle.depth), number(obstacle and obstacle.hit and obstacle.distance)) },
        { ('fall %.2f  start z %.2f  ground %.2f'):format(ctx.fallDistance or 0.0, ctx.fallStartZ or 0.0, ctx.groundClearance or 0.0) },
        { ('scan every %sms  surface %s'):format(scan and scan.interval or '-', obstacle and obstacle.surface or '-') },
    }
    parkourLines(lines, extras)
    lifecycleLines(lines, extras)
    animationLines(lines, extras)
    inputLines(lines)
    comboLines(lines, extras)
    candidateLines(lines)
    ledgeLines(lines, ctx)

    local now = GetGameTimer()
    for i = 1, #reasonOrder do
        local key = reasonOrder[i]
        local reason = reasons[key]
        if reason and now - reason.at <= panel.reasonTtl then
            local ok = positiveCodes[reason.code] == true
            local text
            if key == 'anim' then
                text = ('%s: %s'):format(reason.code, reason.detail or '-')
            else
                text = reason.detail and ('%s: %s (%s)'):format(key, reason.code, reason.detail) or ('%s: %s'):format(key, reason.code)
            end
            lines[#lines + 1] = { text, ok and Constants.Colors.valid or Constants.Colors.blocked }
        end
    end
    return lines
end

local flag = function(value)
    return value and 'true' or 'false'
end

local slope = function(normal)
    if not normal then return nil end
    return math.deg(math.acos(Vec.Clamp(normal.z, -1.0, 1.0)))
end

local frontLines = function(lines, scan)
    local obstacle = scan and scan.obstacle or {}
    local front = scan and scan.walls and scan.walls.front
    lines[#lines + 1] = { 'FRONT WALL', Constants.Colors.top }
    if front then
        lines[#lines + 1] = { ('  detected %s  distance %s  angle %s  hits %s'):format(flag(front.valid), number(front.distance), number(front.angle), front.hits or 0) }
        lines[#lines + 1] = { ('  normal %s'):format(front.normal and Vec.Format(front.normal) or '-') }
    else
        lines[#lines + 1] = { ('  detected %s  distance %s  angle %s  (fan ostacolo)'):format(flag(obstacle.hit), number(obstacle.distance), number(obstacle.approachAngle)) }
        lines[#lines + 1] = { ('  normal %s'):format(obstacle.normal and Vec.Format(obstacle.normal) or '-') }
    end
    lines[#lines + 1] = { 'OBSTACLE', Constants.Colors.top }
    local valid = obstacle.hit == true and obstacle.topZ ~= nil and obstacle.topReason == nil
    lines[#lines + 1] = { ('  valid %s  height %s  depth %s%s'):format(flag(valid), number(obstacle.height), number(obstacle.depth), obstacle.deep and ' (deep)' or '') }
    lines[#lines + 1] = { ('  groundZ %s  topZ %s  topNormal %s  topSlope %s'):format(number(obstacle.groundZ), number(obstacle.topZ), number(obstacle.topNormal and obstacle.topNormal.z), number(slope(obstacle.topNormal))) }
    lines[#lines + 1] = { ('  reason %s'):format(obstacle.topReason or obstacle.reason or '-'), valid and nil or Constants.Colors.blocked }
    local landing = obstacle.landing
    lines[#lines + 1] = { 'LANDING', Constants.Colors.top }
    lines[#lines + 1] = { ('  found %s  clear %s  coords %s'):format(flag(landing ~= nil), flag(landing and landing.clear), landing and Vec.Format(landing.point) or '-') }
end

local ledgeProbeLines = function(lines, scan, extras)
    local ledge = scan and scan.ledge or (extras and extras.ledgeProbe)
    lines[#lines + 1] = { 'LEDGE', Constants.Colors.top }
    if not ledge then
        lines[#lines + 1] = { '  found false' }
        return
    end
    local reachable = ledge.valid and ledge.reason == Constants.Reasons.OK
    lines[#lines + 1] = { ('  found %s  reachable %s  heightDifference %s  distance %s'):format(flag(ledge.topZ ~= nil), flag(reachable), number(ledge.height), number(ledge.distance)) }
    if not reachable then lines[#lines + 1] = { ('  reason %s'):format(ledge.reason or '-'), Constants.Colors.blocked } end
end

local playerLines = function(lines, ctx, state)
    local now = GetGameTimer()
    lines[#lines + 1] = { 'PLAYER', Constants.Colors.top }
    lines[#lines + 1] = { ('  speed %.2f  horizontal %.2f  vertical %.2f'):format(ctx.speed, ctx.speed2d, ctx.velocity.z) }
    lines[#lines + 1] = { ('  grounded %s  airborne %s  state %s'):format(flag(ctx.grounded), flag(ctx.airborne), state.Current()) }
    lines[#lines + 1] = { ('  state entered at %d  age %d ms'):format(state.EnteredAt(), now - state.EnteredAt()) }
end

local layerOrder = { 'feet', 'knees', 'waist', 'chest', 'head', 'overhead' }

local layerLines = function(lines, scan)
    local layers = scan and scan.layers
    if not layers then return end
    local parts = {}
    for i = 1, #layerOrder do
        local layer = layers[layerOrder[i]]
        parts[#parts + 1] = ('%s %s'):format(layerOrder[i], layer and layer.hit and ('%.2f'):format(layer.distance or 0.0) or '-')
    end
    lines[#lines + 1] = { 'BODY LAYERS  ' .. table.concat(parts, '  ') }
end

local point = function(value)
    return value and Vec.Format(value) or '-'
end

local resolverLines = function(lines, extras)
    local decision = extras and extras.decision
    lines[#lines + 1] = { 'TRAVERSAL PROFILE', Constants.Colors.top }
    if not decision or not decision.results or #decision.results == 0 then
        lines[#lines + 1] = { '  nessuna valutazione' }
        return
    end
    for i = 1, #decision.results do
        local entry = decision.results[i]
        local text
        if entry.ok then
            text = ('  %-8s %.2f  -> %s%s'):format(entry.type, entry.score or 0.0, shortName(entry.variant or entry.name), entry.startReason and (' (start: ' .. entry.startReason .. ')') or '')
        elseif entry.valid then
            text = ('  %-8s %s  ability x %s%s'):format(entry.type, entry.score and ('%.2f'):format(entry.score) or 'valid', entry.reason or '-', entry.detail and (' (' .. tostring(entry.detail) .. ')') or '')
        else
            text = ('  %-8s invalid  %s%s'):format(entry.type, entry.reason or '-', entry.detail and (' (' .. tostring(entry.detail) .. ')') or '')
        end
        lines[#lines + 1] = { text, entry.ok and Constants.Colors.valid or (entry.valid and Constants.Colors.landing or Constants.Colors.blocked) }
    end
end

local candidateBlocks = function(lines, scan)
    local profile = scan and scan.profile
    if not profile then return end
    local obstacle = scan.obstacle or {}
    local over = profile.byType.THROUGH and profile.byType.THROUGH.window and profile.byType.THROUGH or profile.byType.OVER
    if over and over.path then
        lines[#lines + 1] = { ('%s CANDIDATE'):format(over.type), Constants.Colors.top }
        lines[#lines + 1] = { ('  height %s  depth %s  top Z %s  clearance %s'):format(number(obstacle.height), number(obstacle.depth), number(obstacle.topZ), number(obstacle.topClearance)) }
        lines[#lines + 1] = { ('  entry %s'):format(point(over.path.entry)) }
        lines[#lines + 1] = { ('  cross %s'):format(point(over.path.cross)) }
        lines[#lines + 1] = { ('  exit  %s'):format(point(over.path.exit)) }
    end
    local passage = profile.byType.UNDER
    if passage and passage.passageHeight then
        lines[#lines + 1] = { 'UNDER CANDIDATE', Constants.Colors.top }
        lines[#lines + 1] = { ('  lowest obstruction Z %s  ground Z %s'):format(number(passage.lowestBlockingZ), number(passage.groundZ)) }
        lines[#lines + 1] = { ('  passage height %s  depth %s  start %s  end %s'):format(number(passage.passageHeight), number(passage.passageDepth), number(passage.passageStart), number(passage.passageEnd)) }
        lines[#lines + 1] = { ('  exit clear %s  exit length %s  samples %d'):format(flag(passage.exitClear), number(passage.exitLength), passage.samples and #passage.samples or 0) }
        if underInfo and GetGameTimer() - underInfo.at <= panel.reasonTtl then
            local parts = {}
            for i = 1, #underInfo.list do
                local v = underInfo.list[i]
                parts[#parts + 1] = v.score and ('%s=%.2f'):format(shortName(v.name), v.score) or ('%s=x %s'):format(shortName(v.name), v.reason or '-')
            end
            lines[#lines + 1] = { '  variants ' .. table.concat(parts, '  ') }
            lines[#lines + 1] = { ('  selected animation: %s'):format(underInfo.selected and shortName(underInfo.selected) or 'NONE'), underInfo.selected and Constants.Colors.valid or Constants.Colors.blocked }
        end
    end
    local opening = profile.byType.THROUGH
    if opening and opening.opening then
        lines[#lines + 1] = { ('THROUGH CANDIDATE%s'):format(opening.window and ' (window)' or ''), Constants.Colors.top }
        lines[#lines + 1] = { ('  opening width %s  height %s'):format(number(opening.opening.width), number(opening.opening.height)) }
        lines[#lines + 1] = { ('  capsule width %.2f  height %.2f'):format(Config.TraversalCapsule.width, opening.window and Config.TraversalCapsule.crouchedHeight or Config.TraversalCapsule.standingHeight) }
        if opening.path then
            lines[#lines + 1] = { ('  entry %s'):format(point(opening.path.entry)) }
            lines[#lines + 1] = { ('  cross %s'):format(point(opening.path.cross)) }
            lines[#lines + 1] = { ('  exit  %s'):format(point(opening.path.exit)) }
        end
    end
end

local selectionLines = function(lines, extras)
    local decision = extras and extras.decision
    local parkour = extras and extras.parkour
    lines[#lines + 1] = { ('SELECTED: %s%s'):format(decision and decision.selected or 'NONE', decision and decision.persisted and ' (persisted)' or ''), Constants.Colors.ledge }
    lines[#lines + 1] = { ('VARIANT: %s   ability: %s'):format(decision and decision.variant and shortName(decision.variant) or '-', parkour and parkour.selected or '-'), Constants.Colors.ledge }
    lines[#lines + 1] = { ('collision mode: %s'):format(extras and extras.collision or 'NORMAL') }
    local anim = extras and extras.animation
    if vaultContext and GetGameTimer() - vaultContext.at <= panel.reasonTtl then
        local c = vaultContext.context
        lines[#lines + 1] = { ('ANIMATION  %s / %s  [%s]'):format(c.dict or '-', c.clip or '-', shortName(c.animation)), Constants.Colors.ledge }
        lines[#lines + 1] = { ('  WHY height %s  depth %s  speed %s  score %s'):format(number(c.obstacleHeight), number(c.obstacleDepth), number(c.approachSpeed), number(c.score)) }
        lines[#lines + 1] = { ('  design %s  lift %s  entity lift %s  body peak %s (top +%s)'):format(number(c.design), number(c.lift), number(c.entityLift), number(c.bodyPeakZ), number(c.bodyPeakZ - c.topZ)) }
        lines[#lines + 1] = { ('  ground Z %s  top Z %s  target Z %s  phase %s->%s x%s'):format(number(c.groundZ), number(c.topZ), number(c.targetZ), number(c.startPhase), number(c.cross), number(c.rate)) }
    elseif anim then
        lines[#lines + 1] = { ('ANIMATION  %s / %s  [%s]'):format(anim.dict or '-', anim.clip or '-', anim.label), Constants.Colors.ledge }
    end
    if anim and anim.name and anim.name:match('^wallrun%.') then
        lines[#lines + 1] = { ('WALLRUN SIDE: %s'):format(anim.name:match('[^%.]+$'):upper()), Constants.Colors.ledge }
    end
    local final = decision and decision.final
    if final then
        local text = ('FINAL REASON: %s'):format(final.code or '-')
        if final.ability then text = text .. ' [' .. final.ability .. ']' end
        if final.detail then text = text .. ' (' .. tostring(final.detail) .. ')' end
        lines[#lines + 1] = { text, Constants.Colors.blocked }
        if final.chain then lines[#lines + 1] = { '  dopo ' .. final.chain, Constants.Colors.blocked } end
    end
end

DebugState.BuildPipeline = function(ctx, state, scan, extras)
    if not ctx.coords then return nil end
    local lines = {}
    local parkour = extras and extras.parkour
    lines[#lines + 1] = { ('PARKOUR HELD: %s'):format(parkour and parkour.held and 'YES' or 'NO'), parkour and parkour.held and Constants.Colors.valid or Constants.Colors.blocked }
    resolverLines(lines, extras)
    selectionLines(lines, extras)
    layerLines(lines, scan)
    candidateBlocks(lines, scan)
    vaultLines(lines)
    frontLines(lines, scan)
    ledgeProbeLines(lines, scan, extras)
    playerLines(lines, ctx, state)
    return lines
end

DebugState.DrawPipeline = function(ctx, state, scan, extras)
    local lines = DebugState.BuildPipeline(ctx, state, scan, extras)
    if lines then DebugState.DrawLines(lines, panel.pipelineX, panel.y, panel.pipelineWidth) end
end

DebugState.DrawLines = function(lines, x, y, width)
    local height = #lines * panel.lineHeight + panel.lineHeight
    DrawRect(x + width * 0.5, y + height * 0.5, width, height, 0, 0, 0, panel.backgroundAlpha)
    for i = 1, #lines do
        drawText(lines[i][1], x + panel.padding, y + (i - 1) * panel.lineHeight + panel.padding, lines[i][2] or Constants.Colors.text)
    end
end

DebugState.BuildPanel = function(ctx, state, scan, extras)
    if not ctx.coords then return nil end
    return buildLines(ctx, state, scan, extras)
end

DebugState.Draw = function(ctx, state, scan, extras)
    local lines = DebugState.BuildPanel(ctx, state, scan, extras)
    if lines then DebugState.DrawLines(lines, panel.x, panel.y, panel.width) end
end

return DebugState
