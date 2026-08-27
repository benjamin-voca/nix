--!strict
-- OtelClientBridge.client.luau
-- Forwards client-side console messages (prints/warnings/errors) to the
-- server through the OtelLogSink RemoteEvent. The server tags them with
-- the player and ships them to ClickStack together with server logs.
--
-- Clients cannot call HttpService; this relay is the supported path.

local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("OtelLogSink") :: RemoteEvent

local SEVERITY_MAP = {
	[Enum.MessageType.Message] = "INFO",
	[Enum.MessageType.Warning] = "WARN",
	[Enum.MessageType.Error] = "ERROR",
	[Enum.MessageType.Info] = "INFO",
	[Enum.MessageType.Trace] = "DEBUG",
}

-- Local throttle: max forwarded messages per flush window
local MAX_PER_WINDOW = 20
local WINDOW_SECONDS = 5
local sentThisWindow = 0
local windowStart = os.clock()

local function forward(severity: string, body: string, attributes: { [string]: any }?)
	local now = os.clock()
	if now - windowStart > WINDOW_SECONDS then
		windowStart = now
		sentThisWindow = 0
	end
	if sentThisWindow >= MAX_PER_WINDOW then
		return
	end
	sentThisWindow += 1

	local ok, err = pcall(function()
		remote:FireServer({
			severity = severity,
			body = body,
			attributes = attributes,
		})
	end)
	if not ok then
		-- Never let telemetry break gameplay
		warn("[OtelClientBridge] forward failed:", tostring(err))
	end
end

LogService.MessageOut:Connect(function(message, messageType)
	forward(SEVERITY_MAP[messageType] or "INFO", message)
end)

-- Uncaught errors include a stack trace; surface them with one attribute
ScriptContext.ErrorDetailed:Connect(function(message, stackTrace)
	forward("ERROR", message, { ["roblox.stack"] = stackTrace })
end)
