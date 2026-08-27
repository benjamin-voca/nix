--!strict
-- ExampleUsage.server.luau
-- Minimal wiring example. Delete after adopting OtelServer in your code.

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Otel = require(ServerScriptService.OtelServer)

-- One-time config (attributes win over constants in OtelServer.luau).
-- Set these per-place in Studio, or via Rojo/arg mapping in CI.
ServerScriptService:SetAttribute("OtelEndpoint", "https://otlp.voltrum.co/v1/logs")
ServerScriptService:SetAttribute("OtelToken", "SET-ME-TO-clickstack-otlp-token")
ServerScriptService:SetAttribute("OtelEnv", RunService:IsStudio() and "studio" or "prod")

local RunService = game:GetService("RunService")

Otel.info("Server booted", {
	fps = workspace:GetRealPhysicsFPS(),
	version = "0.1.0",
})

Players.PlayerAdded:Connect(function(player)
	Otel.event("player.join", {
		["roblox.player"] = player.Name,
		["roblox.user_id"] = player.UserId,
	})
end)

Players.PlayerRemoving:Connect(function(player)
	Otel.event("player.leave", {
		["roblox.player"] = player.Name,
		["roblox.user_id"] = player.UserId,
	})
end)

-- Example: correlate an operation with a trace id for future trace support
local function handleMatchStart(matchId: string)
	local traceId = Otel.newTraceId()
	local spanId = Otel.newSpanId()
	Otel.event("match.start", {
		matchId = matchId,
		traceId = traceId,
		spanId = spanId,
	})
end

task.delay(3, function()
	handleMatchStart("demo-" .. tostring(os.time()))
end)
