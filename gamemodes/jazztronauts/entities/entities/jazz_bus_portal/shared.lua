-- Board that displays currently selected maps
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.RenderGroup = RENDERGROUP_OPAQUE
ENT.Model = "models/sunabouzu/bus_breakableWall.mdl"

ENT.GibModels = {}
for i=1, 37 do 
    local path = "models/sunabouzu/gib_bus_breakablewall_gib" .. i .. ".mdl"
    util.PrecacheModel(path)
    table.insert(ENT.GibModels, path)
end

ENT.VoidModels = {
    "models/sunabouzu/oleg_is_cool.mdl",
    "models/Gibs/HGIBS.mdl",
    "models/props_junk/ravenholmsign.mdl",
    "models/props_interiors/BathTub01a.mdl",
    "models/player/skeleton.mdl"
}

ENT.VoidSphereModel = "models/hunter/misc/sphere375x375.mdl"
ENT.VoidBorderModel = "models/props_debris/plaster_ceiling002a.mdl"
ENT.VoidRoadModel = "models/props_phx/huge/road_long.mdl"

ENT.RTSize = 1024
ENT.Size = 184

if SERVER then
lastBusEnts = lastBusEnts or {}
concommand.Add("jazz_call_bus", function(ply, cmd, args, argstr)
    local eyeTr = ply:GetEyeTrace()
    local pos = eyeTr.HitPos
    local ang = eyeTr.HitNormal:Angle()
    ang:RotateAroundAxis(ang:Up(), 90)  
    pos = pos - ang:Up() * 184/2
   
    -- Do a trace forward to where the bus will exit
    local tr = util.TraceLine( {
        start = eyeTr.HitPos,
        endpos = eyeTr.HitPos + eyeTr.HitNormal * 100000,
        mask = MASK_SOLID_BRUSHONLY
    } )

    local pos2 = tr.HitPos
    local ang2 = tr.HitNormal:Angle()
    ang2:RotateAroundAxis(ang2:Up(), 90)  
    pos2 = pos2 - ang2:Up() * 184/2

    local bus = ents.Create("jazz_bus_explore")
    bus:SetPos(pos)
	bus:SetAngles(ang)
    bus:Spawn()
    bus:Activate()

    local ent = ents.Create("jazz_bus_portal")
	ent:SetPos(pos)
	ent:SetAngles(ang)
    ent:SetBus(bus)
	ent:Spawn()
	ent:Activate()

    local exit = ents.Create("jazz_bus_portal")
	exit:SetPos(pos2)
	exit:SetAngles(ang2)
    exit:SetBus(bus)
    exit:SetIsExit(true)
	exit:Spawn()
	exit:Activate()

    bus.ExitPortal = exit -- So bus knows when to stop

    -- Remove last ones
    for _, v in pairs(lastBusEnts) do SafeRemoveEntityDelayed(v, 5) end
    
    table.insert(lastBusEnts, bus)
    table.insert(lastBusEnts, ent)
    table.insert(lastBusEnts, exit)
end )
end
function ENT:Initialize()

    if SERVER then 
        self:SetModel(self.Model)
        self:PrecacheGibs() -- Probably isn't necessary
        self:SetMoveType(MOVETYPE_NONE)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)

    end

    if CLIENT then
        ParticleEffect( "shard_glow", self:GetPos(), self:GetAngles(), self )

        -- Take a snapshot of the surface that's about to be destroyed
        self:StoreSurfaceMaterial()

        -- Create all the gibs beforehand, get them ready to go (but hide them for now)
        self.Gibs = {}
        for _, v in pairs(self.GibModels) do
            local gib = ents.CreateClientProp(v)
            gib:SetModel(v)
            gib:SetPos(self:GetPos())
            gib:SetAngles(self:GetAngles())
            gib:Spawn()
            gib:PhysicsInit(SOLID_VPHYSICS)
            gib:SetSolid(SOLID_VPHYSICS)
            gib:SetCollisionGroup(self:GetIsExit() and COLLISION_GROUP_WEAPON or COLLISION_GROUP_WORLD)
            gib:SetNoDraw(true)
            gib:GetPhysicsObject():SetMass(500)

            gib:SetMaterial("!bus_wall_material")
            table.insert(self.Gibs, gib)
        end

        -- Also get the void props ready too
        self.VoidProps = {}
        for _, v in pairs(self.VoidModels) do
            local mdl = ents.CreateClientProp(v)
            mdl:SetModel(v)
            mdl:SetNoDraw(true)
            table.insert(self.VoidProps, mdl)
        end

        self.VoidSphere = ents.CreateClientProp(self.VoidSphereModel)
        self.VoidSphere:SetModel(self.VoidSphereModel)
        self.VoidSphere:SetNoDraw(true)

        self.VoidBorder = ents.CreateClientProp(self.VoidBorderModel)
        self.VoidBorder:SetModel(self.VoidBorderModel)
        self.VoidBorder:SetNoDraw(true)

        self.VoidRoad = ents.CreateClientProp(self.VoidRoadModel)
        self.VoidRoad:SetModel(self.VoidRoadModel)
        self.VoidRoad:SetNoDraw(true)
    end
end

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "Bus")
    self:NetworkVar("Bool", 1, "IsExit") -- Are we the exit from the map into the void?
end

function ENT:OnRemove()
    if self.IdleSound then
        self.IdleSound:Stop()
        self.IdleSound = nil 
    end

    if self.Gibs then
        for _, v in pairs(self.Gibs) do
            if IsValid(v) then v:Remove() end
        end
    end
end

-- Test which side the given point is of the portal
function ENT:DistanceToVoid(pos, dontflip)
    local dir = pos - self:GetPos()
    local fwd = self:GetAngles():Right()
    local mult = (!dontflip and self:GetIsExit() and -1) or 1

    return fwd:Dot(dir) * mult
end

if SERVER then return end

TEXTUREFLAGS_ANISOTROPIC = 16
TEXTUREFLAGS_RENDERTARGET = 32768

-- Render the wall we're right next to so we can break it
function ENT:StoreSurfaceMaterial()

    -- Create (or retrieve) the render target
    local rtname = "bus_wall_rt"
    if self:GetIsExit() then rtname = rtname .. "_exit" end
    self.WallTexture = GetRenderTargetEx(rtname, self.RTSize, self.RTSize, 
        RT_SIZE_OFFSCREEN, MATERIAL_RT_DEPTH_SEPARATE, 
        bit.bor(TEXTUREFLAGS_RENDERTARGET,TEXTUREFLAGS_ANISOTROPIC), 
        0, IMAGE_FORMAT_DEFAULT)

    -- Note we just keep reusing "bus_wall_material". If we wanted multiple buses at the same time,
    -- then we'll need a unique name for each material. But not yet.
    self.WallMaterial = CreateMaterial("bus_wall_material", "UnlitGeneric", { ["$nocull"] = 1})
    self.WallMaterial:SetTexture("$basetexture", self.WallTexture)

    -- Bam, just like that, render the wall to the texture
    local pos = self.Size / 2
    local viewang = self:GetAngles()
    viewang:RotateAroundAxis(viewang:Up(), 90)
    render.PushRenderTarget(self.WallTexture)

        render.RenderView( {
            origin = self:GetPos() + viewang:Forward() * -5 + viewang:Up() * pos,
            angles = viewang,
            drawviewmodel = false,
            x = 0,
            y = 0,
            w = ScrW(),
            h = ScrH(),
            ortholeft = -pos,
            orthoright = pos,
            orthotop = -pos,
            orthobottom = pos,
            ortho = true,
        } )

    render.PopRenderTarget()
end

function ENT:Think()
    -- Break when the distance of the bus's front makes it past our portal plane
    if !self.Broken then 
        self.Broken = self:ShouldBreak()

        if self.Broken then 
            self:OnBroken()
        end

    end

    -- This logic is for the exit view only
    if self:GetIsExit() then
        -- Mark the exact time when the client's eyes went into the void
        if self.Broken and !self.VoidTime then
            if self:DistanceToVoid(LocalPlayer():EyePos(), true) < 0 then 
                self.VoidTime = CurTime()
                //self:GetBus().JazzSpeed = self:GetBus():GetVelocity():Length()
            end
        end

        -- Bus have not have networked, but we need a way to go from Bus -> Portal
        -- Just set a value on the bus entity that points to us
        if IsValid(self:GetBus()) then
            self:GetBus().ExitPortal = self
        end
    end
end

function ENT:UpdateCustomTexture()
    self.WallMaterial:SetTexture("$basetexture", self.WallTexture)
end

function ENT:SetupVoidLighting()
    render.SetModelLighting(BOX_FRONT, 100/255.0, 0, 244/255.0)
    render.SetModelLighting(BOX_BACK, 150/255.0, 0, 234/255.0)
    render.SetModelLighting(BOX_LEFT, 40/255.0, 0, 144/255.0)
    render.SetModelLighting(BOX_RIGHT, 100/255.0, 0, 244/255.0)
    render.SetModelLighting(BOX_TOP, 255/255.0, 1, 255/255.0)
    render.SetModelLighting(BOX_BOTTOM, 20/255.0, 0, 45/255.0)
end

function ENT:DrawInsidePortal()

    -- Define our own lighting environment for this
    render.SuppressEngineLighting(true)
    self:SetupVoidLighting()

    local center = self:GetPos() + self:GetAngles():Up() * self.Size/2
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Up(), -90)

    -- Draw a few random floating props in the void
    for i = 1, 10 do
        -- Lifehack: SharedRandom is a nice stateless random function
        local randX = util.SharedRandom("prop", -500, 500, i)
        local randY = util.SharedRandom("prop", -500, 500, -i)

        local offset = self:GetAngles():Right() * (-200 + i * -120)
        offset = offset + self:GetAngles():Up() * randY
        offset = offset + self:GetAngles():Forward() * randX

        -- Subtle twists and turns, totally arbitrary
        local angOffset = Angle(
            randX + CurTime()*randX/50, 
            randY + CurTime()*randY/50, 
            math.sin(randX + randY) * 360 + CurTime() * 10)

        -- Just go through the list of props, looping back
        local mdl = self.VoidProps[(i % #self.VoidProps) + 1]

        mdl:SetPos(center + offset)
        mdl:SetAngles(ang + angOffset)
        mdl:SetupBones() -- Since we're drawing in multiple locations
        mdl:DrawModel()
    end

    -- Draw the wiggly wobbly road into the distance
    local scalemat = Matrix()
    scalemat:Scale(Vector(1, 10, 1))
    self.VoidRoad:EnableMatrix("RenderMultiply", scalemat)
    self.VoidRoad:SetPos(self:GetPos() + self:GetAngles():Right() * -12000)
    self.VoidRoad:SetAngles(self:GetAngles())
    self.VoidRoad:DrawModel()

    -- If we're the exit portal, draw the gibs floating into space
    if self:GetIsExit() then 
        for _, gib in pairs(self.Gibs) do
            gib:DrawModel()
        end
    end

    -- Draw a fixed border to make it look like cracks in the wall
    -- TODO: Ask sun for a model that has proper UVs/sizes.
    -- All this code is just to line it up with the border
    self.VoidBorder:SetPos(center + self:GetAngles():Right() * -6)
    local borderAng = self:GetAngles()
    borderAng:RotateAroundAxis(borderAng:Forward(), 90)
    borderAng:RotateAroundAxis(borderAng:Up(), 90)
    self.VoidBorder:SetAngles(borderAng)
    local mat = Matrix()

    mat:SetScale(Vector(.9, 2, 1) * 0.8)
    self.VoidBorder:EnableMatrix("RenderMultiply", mat)
    self.VoidBorder:SetMaterial("!bus_wall_material")
    self.VoidBorder:SetupBones()
    self.VoidBorder:DrawModel()
    self.VoidBorder:DisableMatrix("RenderMultiply")

    render.SuppressEngineLighting(false)
end

-- Draws doubles of things that are in the normal world too
-- (eg. the Bus, seats, other players, etc.)
function ENT:DrawInteriorDoubles()
    -- Define our own lighting environment for this
    render.SuppressEngineLighting(true)
    self:SetupVoidLighting()

    -- Draw background
    self.VoidSphere:SetPos(EyePos())
    self.VoidSphere:SetModelScale(100)
    self.VoidSphere:SetMaterial("sunabouzu/jazzLake02")
    self.VoidSphere:DrawModel()

    self.VoidSphere:SetPos(EyePos())
    self.VoidSphere:SetMaterial("sunabouzu/jazzLake01")
    self.VoidSphere:DrawModel()

    -- Draw bus
    if IsValid(self:GetBus()) then 
        self:GetBus():DrawModel() 
        local childs = self:GetBus():GetChildren()
        for _, v in pairs(childs) do
            v:DrawModel()
        end
    end

    -- Draw players
    -- NOTE: Usually this is a bad idea, but legitimately every single player should be in the bus
    for _, ply in pairs(player.GetAll()) do
        local seat = ply:GetVehicle()
        if IsValid(seat) and seat:GetParent() == self:GetBus() then 
            ply:DrawModel()
        end
    end

    render.SuppressEngineLighting(false)
end

-- Break if the front of the bus has breached our plane of existence
function ENT:ShouldBreak()
    if !IsValid(self:GetBus()) then return false end
    
    local busFront = self:GetBus():GetFront()
    return self:DistanceToVoid(busFront) > 0
end

-- Right when we switch over to the jazz dimension, the bus will stop moving
-- So we immediately start 'virtually' moving through the jazz dimension instead
-- IDEALLY I'D LIKE TO RETURN A VIEW MATRIX, BUT GMOD DOESN'T HANDLE THAT VERY WELL
function ENT:GetJazzVoidView()
    if !self.VoidTime or !IsValid(self:GetBus()) then return Vector() end

    local t = CurTime() - self.VoidTime
    return self:GetAngles():Right() * self:GetBus().JazzSpeed * -t
end

function ENT:OnBroken()

    -- Draw and wake up every gib
    for _, gib in pairs(self.Gibs) do

        -- Gibs are manually drawn for exit portal (they're in the void)
        if !self:GetIsExit() then
            gib:SetNoDraw(false)
        else
            gib:GetPhysicsObject():EnableGravity(false)
        end

        gib:GetPhysicsObject():Wake()
        local mult = self:GetIsExit() and -1 or 1 -- Break INTO the void, not out of
        local force = math.random(200, 700) * mult
        gib:GetPhysicsObject():SetVelocity(self:GetAngles():Right() * force)
        gib:GetPhysicsObject():AddAngleVelocity(VectorRand() * 100)
    end

    -- Effects
    local center = self:GetPos() + self:GetAngles():Up() * self.Size/2
    local ang = self:GetAngles()
    ang:RotateAroundAxis(ang:Right(), 90)

    local ed = EffectData()
    ed:SetScale(10)
    ed:SetMagnitude(30)
	ed:SetEntity(self)
    ed:SetOrigin(center)
    ed:SetAngles(ang)

    util.Effect("HelicopterMegaBomb", ed)

    self:EmitSound("ambient/machines/wall_crash1.wav", 130)
    self:EmitSound("ambient/machines/thumper_hit.wav", 130)

    util.ScreenShake(self:GetPos(), 15, 3, 3, 1000)

    local ed2 = EffectData()
    ed2:SetStart(self:GetPos())
    ed2:SetOrigin(self:GetPos())
    ed2:SetScale(100)
    ed2:SetMagnitude(100)
    ed2:SetNormal(self:GetAngles():Right())

    -- TODO: Glue these to the bus's two front wheels
    util.Effect("ManhackSparks", ed2, true, true)

    -- Start rendering the portal view
    self.RenderView = true
end

function ENT:Draw()
    if !self.RenderView then return end

    -- Don't bother rendering if the eyes are behind the plane anyway
    if self:DistanceToVoid(EyePos(), true) < 0 then return end

    self:UpdateCustomTexture()

    render.SetStencilEnable(true)
        render.SetStencilWriteMask(255)
        render.SetStencilTestMask(255)
        render.ClearStencil()

        -- First, draw where we cut out the world
        render.SetStencilReferenceValue(1)
        render.SetStencilCompareFunction(STENCIL_ALWAYS)
        render.SetStencilPassOperation(STENCIL_REPLACE)

        self:DrawModel()

        -- Second, draw the interior
        render.SetStencilCompareFunction(STENCIL_EQUAL)
        render.ClearBuffersObeyStencil(55, 0, 55, 255, true)

        cam.IgnoreZ(true)
            cam.Start3D()
                self:DrawInsidePortal()
                self:DrawInteriorDoubles()
            cam.End3D()
        cam.IgnoreZ(false)

        -- Draw into the depth buffer for the interior to prevent
        -- Props from going through
        render.OverrideColorWriteEnable(true, false)
            self:DrawModel()
        render.OverrideColorWriteEnable(false, false)

    render.SetStencilEnable(false)

end

hook.Add("RenderScene", "JazzBusDrawVoid", function(origin, angles, fov)
    local bus = IsValid(LocalPlayer():GetVehicle()) and LocalPlayer():GetVehicle():GetParent() or nil
    if !IsValid(bus) or !bus:GetClass() == "jazz_bus_explore" then return end 
    if !IsValid(bus.ExitPortal) then return end 

    -- If the local player's view is past the portal 'plane', ONLY render the jazz dimension
    if bus.ExitPortal:DistanceToVoid(EyePos()) > 0 then

        local voffset = bus.ExitPortal:GetJazzVoidView()
        render.Clear(55, 0, 55, 255)
        cam.Start3D(origin + voffset, angles, fov)
            bus.ExitPortal:DrawInsidePortal()
        cam.End3D()

        cam.Start3D(origin, angles, fov)
            bus.ExitPortal:DrawInteriorDoubles()
        cam.End3D()
        return true -- Don't bother drawing the world
    end
end )