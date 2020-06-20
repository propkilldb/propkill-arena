local arenameta = {}
arenameta.__index = arenameta

PK.arenameta = arenameta

include("net.lua")
include("gamemodes.lua")
/*
	Class: Arena
	The base arena class
*/


// ==== Arena Player Management ==== \\

/*
	Function: Arena:AddPlayer()
	Adds a player to the arena

	Parameters:
		player: Player - The player to add to the arena

	Returns:
		success: bool - Did we succeed adding the player to the arena
		reason: string - The reason if we didn't succeed
*/
function arenameta:AddPlayer(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end

	if ply.arena == self then
		return false, "already in arena"
	end

	local canjoin, reason = self:CallGMHook("PlayerJoinArena", ply)
	if not canjoin then
		return false, reason or "arena not initialised"
	end

	if IsValid(ply.arena) then
		ply.arena:RemovePlayer(ply)
	end

	ply.arena = self
	ply:SetTeam(TEAM_DEATHMATCH)

	self.players[ply:EntIndex()] = ply
	self:NWPlayer(ply)
	self:CallGMHook("PlayerJoinedArena", ply)
	ply:SetNWString("arena", tostring(self))

	ply:Spawn()

	return true
end

/*
	Function: Arena:RemovePlayer()

	Parameters:
		player: Player - The player to remove from the arena
		silent: bool - Don't call the PlayerLeaveArena hook
*/
function arenameta:RemovePlayer(ply, silent)
	if ply.arena == nil then return end

	if IsValid(ply.team) then
		ply.team:RemovePlayer(self, ply)
	end

	ply.arena = nil
	self.players[ply:EntIndex()] = nil

	if not silent then
		self:CallGMHook("PlayerLeaveArena", ply)
	end

	self:NWPlayer(ply, true)
	ply:SetNWString("arena", nil)

	ply:Spawn()
end


// ==== Arena Hooks ==== \\

/*
	Function: Arena:CallGMHook()
	Calls the specified hook in the arena

	Parameters:
		event: string - The name of the event to call e.g. PlayerJoinedArena
		vararg - The arguments to be passed to the hooked functions

	Returns:
		nil unless a hooked function returns a value
*/
function arenameta:CallGMHook(event, ...)
	local gm = self.gamemode
	if not IsValid(gm) then return false end

	if gm.hooks.customHooks[event] == nil then
		error("Attempt to call non-existent gamemode hook", 2)
		return
	end

	return gm.hooks.customHooks[event](self, ...)
end


// ==== Arena Gamemode ==== \\

/*
	Function: Arena:SetGamemode()
	Sets the gamemode of the arena

	Parameters:
		gamemode: <Gamemode> - The gamemode table the arena will use
		keepPlayers: bool - Should we keep players in the arena
*/
function arenameta:SetGamemode(gm, keepPlayers)
	if not IsValid(gm) then return end

	// cleanup anything left from the previous gamemode
	self:GamemodeCleanup()
	self.gamemode = gm

	// initialize all the users hooks from the gamemode
	for k,v in pairs(gm.userHooks) do
		// check that it isnt an arena hook
		if gm.hooks.customHooks[k] == nil then
			self.hooks[k] = tostring(self)

			hook.Add(k, tostring(self), function(ply, ...)
				if not IsValid(self) then return end
				if ply.arena != self then return end

				for kk, vv in pairs(v) do
					local ret = vv(self, ply, ...)
					
					if type(ret) != "nil" then
						return ret
					end
				end
			end)
		end
	end

	// setup rounds
	for k,v in pairs(gm.round) do
		self.round[k] = v
	end

	// setup teams
	for k,v in pairs(gm.teams) do
		self.teams[k] = setmetatable(table.Copy(v), PK.teammeta)
	end

	self.initialized = true

	// tell the gamemode to initialize
	self:CallGMHook("InitializeGame")

	// network changes
	self:SetNWVar("gamemode", self:GetInfo().gamemode)
	self:SetNWVar("teams", self.teams)
	self:SetNWVar("initialized", self.initialized)

	if keepPlayers then
		for k,v in pairs(self.players) do
			local canjoin, reason = self:CallGMHook("PlayerJoinArena", v)
			if canjoin then
				self:CallGMHook("PlayerJoinedArena", v)
				v:Spawn()
			end
		end
	else
		for k,v in pairs(self.players) do
			self:RemovePlayer(v)
		end
	end

end

/*
	Function: Arena:GamemodeCleanup()
	De-initializes the arena and cleans up all data in the arena including gamemode, rounds, teams and props
*/
function arenameta:GamemodeCleanup()
	if IsValid(self.gamemode) then
		self:CallGMHook("TerminateGame", self)
	end

	self:Cleanup()

	for k,v in pairs(self.hooks) do
		hook.Remove(k, v)
	end

	self.gamemode = {}
	self.gmvars = {}
	self.round = {}
	self.teams = {}
	self.initialized = false

	self:SetNWVar("gamemode", self:GetInfo().gamemode)
	self:SetNWVar("teams", self.teams)
	self:SetNWVar("initialized", self.initialized)

	self:NWArena()
end

// ==== Arena Utility ==== \\

/*
	Function: Arena:GetInfo()
	Returns a table of arena info. Used internally for networking.

	Returns:
		data: table

		* name: string
		* icon: string path
		* maxplayers: number
		* players: table
		* props: table
		* teams: <Teams>
		* initialized: bool
		* round
			* currentRound: string
			* subRound: string
		* gamemode
			* name: string
*/
function arenameta:GetInfo()
	local data = {
		name = self.name,
		icon = self.icon,
		maxplayers = self.maxplayers,
		players = self.players,
		props = self.props,
		teams = self.teams,
		initialized = self.initialized,
		round = {
			currentRound = self.round.currentRound or "",
			subRound = self.round.currentSubRound or "",
		},
		gamemode = {
			name = self.gamemode.name or "",
		},
	}
	return data
end

/*
	Function: Arena:GetData()
	Returns a table of arena data. Used internally for saving an arena to file.

	Returns:
		data: table

		* name: string
		* icon: string path
		* positions: number
		* gamemode: string - gamemode abbreviation
*/
function arenameta:GetData()
	local data = {
		name = self.name,
		icon = self.icon,
		positions = self.positions,
		gamemode = self.gamemode.abbr or "",
	}
	return data
end

/*
	Function: Arena:Cleanup()
	Cleans up all the props in an arena
*/
function arenameta:Cleanup()
	for k,v in pairs(self.props) do
		v:Remove()
	end
	self:SetNWVar("props", self.props)
end

/*
	Function: Arena:GetTeam()
	Gets a team from the arena

	Returns:
		team: <Team> - Team from arena
*/
function arenameta:GetTeam(name)
	return self.teams[name]
end

/*
	Function: Arena:IsValid()
	Check if the arena is valid

	Returns:
		valid: bool - True if valid
*/
function arenameta:IsValid()
	return true
end

// ==== Arena Default Hooks ==== \\

hook.Add("PlayerDisconnected", "PK_Arena_PlayerDisconnect", function(ply)
	if IsValid(ply.arena) then
		ply.arena:RemovePlayer(ply)
	end
end)

hook.Add("SetupPlayerVisibility", "PK_Arena_SetupPlayerVisibility", function(ply)
	local arena = ply.arena

	if IsValid(arena) then
		for k,v in pairs(arena.players) do
			if IsValid(v) then
				AddOriginToPVS(v:GetPos())
			end
		end
		for k,v in pairs(arena.props) do
			if IsValid(v) then
				AddOriginToPVS(v:GetPos())
			end
		end
	end
end)

hook.Add("PlayerSpawnedProp", "PK_Arena_PlayerSpawnedProp", function(ply, model, ent)
	local arena = ply.arena

	if IsValid(arena) then
		ent.arena = arena
		table.insert(arena.props, ent:EntIndex(), ent)
		arena:NWProp(ent)
	end
end)

hook.Add("EntityRemoved", "PK_Arena_EntityRemoved", function(ent)
	local arena = ent.arena

	if IsValid(arena) then
		arena.props[ent:EntIndex()] = nil
		arena:NWProp(ent, true)
	end
end)
