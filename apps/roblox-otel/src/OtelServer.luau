--!strict
-- OtelServer.luau
-- Server-side OTLP log shipper for ClickStack (HyperDX).
--
-- Batches logs and completed spans from the Roblox server (plus client logs
-- forwarded through the OtelLogSink RemoteEvent) and POSTs OTLP/HTTP JSON to:
--     POST https://otlp.voltrum.co/v1/logs
--     POST https://otlp.voltrum.co/v1/traces
--     Authorization: <ingestion token>  (RAW token — the ClickStack
--     standalone collector's bearertokenauth uses scheme="", no Bearer)
--
-- Configuration via ServerScriptService attributes (set once at startup):
--   ServerScriptService:SetAttribute("OtelEndpoint", "https://otlp.voltrum.co/v1/logs")
--   ServerScriptService:SetAttribute("OtelTracesEndpoint", "https://otlp.voltrum.co/v1/traces") -- optional
--   ServerScriptService:SetAttribute("OtelToken", "<clickstack-otlp-token>")
--   ServerScriptService:SetAttribute("OtelEnv", "prod")  -- or "dev", "studio"
-- Attributes fall back to the CONFIG constants below when not set.
--
-- Usage:
--   local Otel = require(game.ServerScriptService.OtelServer)
--   Otel.info("Match started", {mode = "ranked", players = 8})
--   Otel.error("Payment failed", {orderId = id, traceId = traceId})
--
-- Client logs: require OtelClientBridge from LocalScripts (see that file).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ServerScriptService = game:GetService("ServerScriptService")
local Trace = require(ServerScriptService.OtelTrace)

--------------------------------------------------------------------
-- Config
--------------------------------------------------------------------
local CONFIG = {
	Endpoint = "https://otlp.voltrum.co/v1/logs",
	TracesEndpoint = "https://otlp.voltrum.co/v1/traces",
	Token = "", -- REQUIRED in live servers unless set via attribute
	Environment = RunService:IsStudio() and "studio" or "prod",
	ServiceName = "roblox",
	FlushIntervalSeconds = 5,
	MaxQueueSize = 500,
	MaxTraceQueueSize = 500,
	MaxBatchSize = 120,
	RetryBackoffSeconds = 10,
}

local attrEndpoint = ServerScriptService:GetAttribute("OtelEndpoint")
if typeof(attrEndpoint) == "string" then
	CONFIG.Endpoint = attrEndpoint
	CONFIG.TracesEndpoint = Trace.deriveTracesEndpoint(attrEndpoint, CONFIG.TracesEndpoint)
end
local attrTracesEndpoint = ServerScriptService:GetAttribute("OtelTracesEndpoint")
if typeof(attrTracesEndpoint) == "string" then
	CONFIG.TracesEndpoint = attrTracesEndpoint
end
local attrToken = ServerScriptService:GetAttribute("OtelToken")
if typeof(attrToken) == "string" and #attrToken > 0 then
	CONFIG.Token = attrToken
end
local attrEnv = ServerScriptService:GetAttribute("OtelEnv")
if typeof(attrEnv) == "string" then
	CONFIG.Environment = attrEnv
end

--------------------------------------------------------------------
-- OTLP severity mapping (OTLP SeverityNumber)
--------------------------------------------------------------------
local SEVERITY = {
	TRACE = { text = "TRACE", number = 1 },
	DEBUG = { text = "DEBUG", number = 5 },
	INFO = { text = "INFO", number = 9 },
	WARN = { text = "WARN", number = 13 },
	ERROR = { text = "ERROR", number = 17 },
	FATAL = { text = "FATAL", number = 21 },
}

--------------------------------------------------------------------
-- State
--------------------------------------------------------------------
local queue: { any } = {}
local traceQueue: { any } = {}
local flushing = false
local tracesFlushing = false
local lastFailureAt = 0
local lastTraceFailureAt = 0
local remote: RemoteEvent? = nil

local function nanoNow(): string
	-- ms fits a double exactly; append zeros for nanosecond precision
	return tostring(DateTime.now().UnixTimestampMillis) .. "000000"
end

local function encodeValue(v: any): (boolean, any)
	local t = typeof(v)
	if t == "string" then
		return true, { stringValue = v }
	elseif t == "number" then
		if v % 1 == 0 then
			return true, { intValue = math.floor(v) }
		end
		return true, { doubleValue = v }
	elseif t == "boolean" then
		return true, { boolValue = v }
	end
	return false, { stringValue = tostring(v) }
end

local function encodeAttributes(attrs: { [string]: any }?): { any }
	local out = {}
	if not attrs then
		return out
	end
	for k, v in attrs do
		local ok, encoded = encodeValue(v)
		if ok then
			table.insert(out, { key = k, value = encoded })
		end
	end
	return out
end

local function makeRecord(sev, body: string, attrs: { [string]: any }?)
	local record = {
		timeUnixNano = nanoNow(),
		observedTimeUnixNano = nanoNow(),
		severityText = sev.text,
		severityNumber = sev.number,
		body = { stringValue = body },
		attributes = encodeAttributes(attrs),
	}
	Trace.applyLogContext(record, attrs)
	return record
end

--------------------------------------------------------------------
-- Queueing
--------------------------------------------------------------------
local function enqueue(record, priority: number)
	if #queue >= CONFIG.MaxQueueSize then
		-- Drop the lowest-priority (least severe) buffered record
		local dropIdx = nil
		for i, item in queue do
			if dropIdx == nil or item.priority < priority then
				if dropIdx == nil or queue[i].priority <= queue[dropIdx].priority then
					dropIdx = i
				end
			end
		end
		if dropIdx == nil or priority <= queue[dropIdx].priority then
			return -- incoming record is least important; drop it
		end
		table.remove(queue, dropIdx)
	end
	table.insert(queue, { record = record, priority = priority })
end

local function resourceAttributes(): { [string]: any }
	return {
		["service.name"] = CONFIG.ServiceName,
		["deployment.environment"] = CONFIG.Environment,
		["roblox.place_id"] = game.PlaceId,
		["roblox.universe_id"] = game.GameId,
		["roblox.job_id"] = game.JobId ~= "" and game.JobId or "studio",
		["roblox.server_type"] = RunService:IsStudio() and "studio" or "live",
	}
end

local function resourceLogsPayload(records: { any }): { any }
	return {
		resourceLogs = {
			{
				resource = {
					attributes = encodeAttributes(resourceAttributes()),
				},
				scopeLogs = {
					{
						scope = { name = "roblox-otel", version = "0.2.0" },
						logRecords = records,
					},
				},
			},
		},
	}
end

--------------------------------------------------------------------
-- Flush
--------------------------------------------------------------------
local function flush(): boolean
	if flushing or #queue == 0 then
		return false
	end
	flushing = true

	local batch = {}
	local n = math.min(#queue, CONFIG.MaxBatchSize)
	for _ = 1, n do
		table.insert(batch, table.remove(queue, 1).record)
	end

	local ok, err = pcall(function()
		local response = HttpService:RequestAsync({
			Url = CONFIG.Endpoint,
			Method = "POST",
			Headers = {
				["content-type"] = "application/json",
				-- RAW token, no "Bearer " prefix (collector scheme="")
				["authorization"] = CONFIG.Token,
			},
			Body = HttpService:JSONEncode(resourceLogsPayload(batch)),
		})
		if not response.Success then
			error(("OTLP ingest failed: %d %s"):format(response.StatusCode, response.StatusMessage))
		end
	end)

	if ok then
		flushing = false
		return true
	end

	lastFailureAt = os.clock()
	warn(("[OtelServer] flush failed: %s (requeueing %d records)"):format(tostring(err), #batch))
	-- Requeue (may drop overflow on a full queue)
	for _, rec in batch do
		enqueue(rec, SEVERITY.INFO.number)
	end
	flushing = false
	return false
end

local function enqueueTrace(record: any)
	if #traceQueue >= CONFIG.MaxTraceQueueSize then
		table.remove(traceQueue, 1)
	end
	table.insert(traceQueue, record)
end

local function flushTraces(): boolean
	if tracesFlushing or #traceQueue == 0 or #CONFIG.Token == 0 then
		return false
	end
	tracesFlushing = true

	local batch = {}
	local n = math.min(#traceQueue, CONFIG.MaxBatchSize)
	for _ = 1, n do
		table.insert(batch, table.remove(traceQueue, 1))
	end

	local ok, err = pcall(function()
		local response = HttpService:RequestAsync({
			Url = CONFIG.TracesEndpoint,
			Method = "POST",
			Headers = {
				["content-type"] = "application/json",
				["authorization"] = CONFIG.Token,
			},
			Body = HttpService:JSONEncode(Trace.resourceSpansPayload(resourceAttributes(), batch)),
		})
		if not response.Success then
			error(("OTLP trace ingest failed: %d %s"):format(response.StatusCode, response.StatusMessage))
		end
	end)

	if ok then
		tracesFlushing = false
		return true
	end

	lastTraceFailureAt = os.clock()
	warn(("[OtelServer] trace flush failed: %s (requeueing %d spans)"):format(tostring(err), #batch))
	for i = #batch, 1, -1 do
		table.insert(traceQueue, 1, batch[i])
	end
	while #traceQueue > CONFIG.MaxTraceQueueSize do
		table.remove(traceQueue)
	end
	tracesFlushing = false
	return false
end

local function flushLoop()
	while true do
		task.wait(CONFIG.FlushIntervalSeconds)
		if os.clock() - lastFailureAt > CONFIG.RetryBackoffSeconds then
			pcall(flush)
		end
		if os.clock() - lastTraceFailureAt > CONFIG.RetryBackoffSeconds then
			pcall(flushTraces)
		end
	end
end

--------------------------------------------------------------------
-- Client bridge
--------------------------------------------------------------------
local function setupRemoteBridge()
	local existing = ReplicatedStorage:FindFirstChild("OtelLogSink")
	if existing and existing:IsA("RemoteEvent") then
		remote = existing
		return
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = "OtelLogSink"
	remote.Parent = ReplicatedStorage

	remote.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local sev = SEVERITY[payload.severity] or SEVERITY.INFO
		local attrs = { ["roblox.player"] = player.Name, ["roblox.user_id"] = player.UserId }
		if typeof(payload.attributes) == "table" then
			for k, v in payload.attributes do
				-- Clients may not forge native correlation onto arbitrary traces.
				if k ~= "traceId" and k ~= "spanId" then
					attrs[k] = v
				end
			end
		end
		enqueue(makeRecord(sev, tostring(payload.body), attrs), sev.number)
	end)
end

--------------------------------------------------------------------
-- Init
--------------------------------------------------------------------
if RunService:IsServer() then
	setupRemoteBridge()
	task.spawn(flushLoop)

	game:BindToClose(function()
		-- Best-effort final flush (Roblox allows up to 30s).
		local deadline = os.clock() + 5
		while (#queue > 0 or #traceQueue > 0) and os.clock() < deadline do
			local progressed = false
			if #queue > 0 then
				progressed = flush() or progressed
			end
			if #traceQueue > 0 then
				progressed = flushTraces() or progressed
			end
			if not progressed then
				break
			end
		end
	end)
end

--------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------
local Otel = {}

function Otel.log(severity: string, body: string, attrs: { [string]: any }?)
	local sev = SEVERITY[string.upper(severity)] or SEVERITY.INFO
	enqueue(makeRecord(sev, body, attrs), sev.number)
end

function Otel.debug(body: string, attrs: { [string]: any }?)
	Otel.log("DEBUG", body, attrs)
end
function Otel.info(body: string, attrs: { [string]: any }?)
	Otel.log("INFO", body, attrs)
end
function Otel.warn(body: string, attrs: { [string]: any }?)
	Otel.log("WARN", body, attrs)
end
function Otel.error(body: string, attrs: { [string]: any }?)
	Otel.log("ERROR", body, attrs)
end

-- Named event with trace/span correlation ids (hex, 32/16 chars).
-- Pass traceId/spanId from a span when the event belongs to an in-progress
-- operation so HyperDX links the log to the exported trace.
function Otel.event(name: string, attrs: { [string]: any }?)
	local merged = attrs or {}
	merged["event.name"] = name
	Otel.log("INFO", name, merged)
end

function Otel.newTraceId(): string
	return HttpService:GenerateGUID(false):gsub("-", "") :: string
end
function Otel.newSpanId(): string
	return string.sub(HttpService:GenerateGUID(false):gsub("-", ""), 1, 16)
end

-- Start an OTLP span. Pass parentSpan:context() as parentContext for children.
-- Finish with span:finish("OK") or span:fail(errorMessage).
function Otel.startSpan(
	name: string,
	attrs: { [string]: any }?,
	parentContext: Trace.TraceContext?,
	kind: string?
): Trace.Span
	local traceId = if parentContext and Trace.isTraceId(parentContext.traceId)
		then parentContext.traceId
		else Otel.newTraceId()
	local parentSpanId = if parentContext and Trace.isSpanId(parentContext.spanId) then parentContext.spanId else nil
	return Trace.newSpan({
		name = name,
		traceId = traceId,
		spanId = Otel.newSpanId(),
		parentSpanId = parentSpanId,
		kind = kind,
		startTimeUnixNano = nanoNow(),
		attributes = attrs,
		nowNano = nanoNow,
		onFinish = enqueueTrace,
	})
end

function Otel.flushNow()
	flush()
	flushTraces()
end

return Otel
