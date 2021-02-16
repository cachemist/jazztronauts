AddCSLuaFile()

if SERVER then

	util.AddNetworkString("io_net_event")

end

module( "ionet", package.seeall )

local strings = {}
local stringLookup = {}
local function addLookupString(k)
	if stringLookup[k] then return end
	local id = #strings + 1
	stringLookup[k] = id
	strings[id] = k
end

for _, class in pairs(iocommon.FGDClasses) do
	for input, param in pairs(class.inputs) do addLookupString(input) end
	for output, param in pairs(class.outputs) do addLookupString(output) end
end

local lookupStringBits = math.ceil(math.log(#strings) / LOG_2)

local function WriteIndexed(str)

	local n = stringLookup[str]
	if n then
		net.WriteBit(1)
		net.WriteUInt(n-1, lookupStringBits)
	else
		net.WriteBit(0)
		net.WriteString(str)
	end

end

local function ReadIndexed()

	if net.ReadBit() == 1 then
		return strings[net.ReadUInt(lookupStringBits)+1]
	else
		return net.ReadString()
	end

end

print("Lookup bits: " .. lookupStringBits)


if SERVER then

	function SendEventToClients( ent, event )

		net.Start("io_net_event")
		net.WriteUInt( ent:GetIndex()-1, 16 )
		WriteIndexed( event )
		net.Broadcast()

	end

	hook.Add("IOEventTriggered", "ionet", function(ent, event)

		--print( ent:GetName() .. " -> " .. event )
		SendEventToClients( ent, event )

	end)

else

	net.Receive("io_net_event", function(ply, len)

		local id = net.ReadUInt(16)
		local event = ReadIndexed()
		local data = bsp2.GetCurrent()

		if data == nil or data:IsLoading() then return end

		local ent = data.iograph:GetByIndex(id+1)

		hook.Call("IOEventTriggered", GAMEMODE, ent, event )


	end)

	hook.Add("IOEventTriggered", "ionet", function(ent, event)

		for _, out in ipairs(ent:GetOutputs()) do

			if out.event == event then

				timer.Simple( out.delay, function()

					print( out.from:GetName() .. "[" .. out.event .. "]" .. " -> " .. out.to:GetName() .. "[" .. out.func .. "]" )

				end )

			end

		end

	end)

end