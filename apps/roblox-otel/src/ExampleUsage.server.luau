--!strict
-- ExampleUsage.server.luau
-- Minimal wiring example. Delete after adopting OtelServer in your code.

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Configure before requiring OtelServer; the module starts its exporters at
-- require time. OtelTracesEndpoint is derived by replacing /v1/logs unless
-- explicitly overridden.
ServerScriptService:SetAttribute("OtelEndpoint", "https://otlp.voltrum.co/v1/logs")
ServerScriptService:SetAttribute("OtelToken", "SET-ME-TO-clickstack-otlp-token")
ServerScriptService:SetAttribute("OtelEnv", RunService:IsStudio() and "studio" or "prod")

local Otel = require(ServerScriptService.OtelServer)

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

-- Trace an operation and correlate its logs. Child spans inherit the trace ID
-- by receiving the parent's context.
local function handleMatchStart(matchId: string)
	local span = Otel.startSpan("match.start", { matchId = matchId }, nil, "SERVER")
	Otel.event("match.start", {
		matchId = matchId,
		traceId = span.traceId,
		spanId = span.spanId,
	})

	local child = Otel.startSpan("match.allocate", { matchId = matchId }, span:context())
	child:finish("OK")
	span:finish("OK")
end

task.delay(3, function()
	handleMatchStart("demo-" .. tostring(os.time()))
end)
