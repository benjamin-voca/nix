--!strict
-- OtelTrace.luau
-- Pure OTLP trace/span helpers shared by the Roblox exporter and its tests.

local OtelTrace = {}

type Attributes = { [string]: any }

export type TraceContext = {
	traceId: string,
	spanId: string,
}

export type Span = {
	traceId: string,
	spanId: string,
	parentSpanId: string?,
	setAttribute: (self: Span, key: string, value: any) -> (),
	context: (self: Span) -> TraceContext,
	finish: (self: Span, status: string?, attributes: Attributes?) -> boolean,
	fail: (self: Span, message: string, attributes: Attributes?) -> boolean,
}

export type SpanOptions = {
	name: string,
	traceId: string,
	spanId: string,
	parentSpanId: string?,
	kind: string?,
	startTimeUnixNano: string,
	attributes: Attributes?,
	nowNano: () -> string,
	onFinish: (record: any) -> (),
}

local KINDS = {
	INTERNAL = 1,
	SERVER = 2,
	CLIENT = 3,
	PRODUCER = 4,
	CONSUMER = 5,
}

local STATUS_CODES = {
	UNSET = 0,
	OK = 1,
	ERROR = 2,
}

local function isHexId(value: any, length: number): boolean
	if typeof(value) ~= "string" or #value ~= length then
		return false
	end
	if string.match(value, "^0+$") then
		return false
	end
	return string.match(value, "^[0-9a-fA-F]+$") ~= nil
end

function OtelTrace.isTraceId(value: any): boolean
	return isHexId(value, 32)
end

function OtelTrace.isSpanId(value: any): boolean
	return isHexId(value, 16)
end

function OtelTrace.deriveTracesEndpoint(logsEndpoint: string, fallback: string): string
	local derived, replacements = string.gsub(logsEndpoint, "/v1/logs$", "/v1/traces")
	if replacements == 1 then
		return derived
	end
	return fallback
end

local function copyAttributes(attributes: Attributes?): Attributes
	local copied = {}
	if attributes then
		for key, value in attributes do
			if typeof(key) == "string" then
				copied[key] = value
			end
		end
	end
	return copied
end

local function encodeValue(value: any): any?
	local valueType = typeof(value)
	if valueType == "string" then
		return { stringValue = value }
	elseif valueType == "number" then
		if value % 1 == 0 then
			return { intValue = math.floor(value) }
		end
		return { doubleValue = value }
	elseif valueType == "boolean" then
		return { boolValue = value }
	end
	return nil
end

function OtelTrace.encodeAttributes(attributes: Attributes?): { any }
	local encoded = {}
	if not attributes then
		return encoded
	end

	local keys = {}
	for key in attributes do
		if typeof(key) == "string" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)

	for _, key in keys do
		local value = encodeValue(attributes[key])
		if value then
			table.insert(encoded, { key = key, value = value })
		end
	end
	return encoded
end

function OtelTrace.applyLogContext(record: any, attributes: Attributes?)
	if not attributes then
		return
	end
	local traceId = attributes.traceId
	local spanId = attributes.spanId
	if OtelTrace.isTraceId(traceId) then
		record.traceId = string.lower(traceId)
	end
	if OtelTrace.isSpanId(spanId) then
		record.spanId = string.lower(spanId)
	end
end

function OtelTrace.resourceSpansPayload(resourceAttributes: Attributes, records: { any }): any
	return {
		resourceSpans = {
			{
				resource = { attributes = OtelTrace.encodeAttributes(resourceAttributes) },
				scopeSpans = {
					{
						scope = { name = "roblox-otel", version = "0.2.0" },
						spans = records,
					},
				},
			},
		},
	}
end

function OtelTrace.newSpan(options: SpanOptions): Span
	assert(OtelTrace.isTraceId(options.traceId), "traceId must be 32 non-zero hex characters")
	assert(OtelTrace.isSpanId(options.spanId), "spanId must be 16 non-zero hex characters")
	if options.parentSpanId ~= nil then
		assert(OtelTrace.isSpanId(options.parentSpanId), "parentSpanId must be 16 non-zero hex characters")
	end

	local attributes = copyAttributes(options.attributes)
	local ended = false
	local span = {
		traceId = string.lower(options.traceId),
		spanId = string.lower(options.spanId),
		parentSpanId = if options.parentSpanId then string.lower(options.parentSpanId) else nil,
	} :: any

	function span:setAttribute(key: string, value: any)
		if not ended and typeof(key) == "string" then
			attributes[key] = value
		end
	end

	function span:context(): TraceContext
		return { traceId = span.traceId, spanId = span.spanId }
	end

	function span:finish(status: string?, finalAttributes: Attributes?): boolean
		if ended then
			return false
		end
		ended = true
		if finalAttributes then
			for key, value in finalAttributes do
				if typeof(key) == "string" then
					attributes[key] = value
				end
			end
		end

		local normalizedStatus = string.upper(status or "UNSET")
		local record = {
			traceId = span.traceId,
			spanId = span.spanId,
			name = options.name,
			kind = KINDS[string.upper(options.kind or "INTERNAL")] or KINDS.INTERNAL,
			startTimeUnixNano = options.startTimeUnixNano,
			endTimeUnixNano = options.nowNano(),
			attributes = OtelTrace.encodeAttributes(attributes),
			status = { code = STATUS_CODES[normalizedStatus] or STATUS_CODES.UNSET },
		}
		if span.parentSpanId then
			record.parentSpanId = span.parentSpanId
		end
		options.onFinish(record)
		return true
	end

	function span:fail(message: string, finalAttributes: Attributes?): boolean
		local merged = copyAttributes(finalAttributes)
		merged["exception.message"] = message
		return span:finish("ERROR", merged)
	end

	return span :: Span
end

return OtelTrace
