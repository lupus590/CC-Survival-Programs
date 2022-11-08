local expect = require("cc.expect")

-- TODO: scoping? Could be useful for libaries or when things want to say when they start and stop something. How to implement? An option to ignore a scope could be nice too, that way users can filter out library logs. Can also be context.
-- TODO: enrich/format
-- TODO: enrich with context
-- TODO: "cc.pretty" things?
-- TODO: meta methods?


local levels = {
	"verbose",
	"debug",
	"information",
	"warning",
	"error",
	"fatal",
}
for k,v in ipairs(levels) do
	levels[v] = k
	levels[v:sub(1,1)] = k
end

--- Gets the accepted logging levels, verbose, debug, information, etc.
---@return table All of the logging levels accepted by the logger.
local function getLevels()
	local returnLevels = {}
	for k,v in pairs(levels) do
		returnLevels[v] = k
	end
	return returnLevels
end

local sinks ={}

--- Adds a that any logger can then use.
---@param label string The unique identifier of the sink.
---@param sinkConstuctor function The function that is called to create this sink. This can take parameters. This contructor function should return a function that accepts a single table parameter.
local function registerSink(label, sinkConstuctor)
	expect.expect(1, label, "string")
	expect.expect(2, sinkConstuctor, "function")

	if label:find("%s") then -- TODO: Need to check if this covers all illegal characters.
		error("Label `"..label.."` contains illegal characters.", 2)
	end

	if sinks[label] then
		error("A sink with label `"..label.."` already exists", 2)
	end

	sinks[label] = sinkConstuctor
end

local function createLogger(loggerConfig)
	local logger = {}
	-- logger methods
	for levelNumber, levelString in ipairs(levels) do

		--- The actual log functions. The names of these logging functions are the string values of the levels.
		---@param message any The message to be logged.
		logger[levelString] = function(message)
			if loggerConfig._minimumLevel > levelNumber then
				return
			end

			local nowUtc = os.epoch("utc")
			local date = os.date("%Y-%m-%d %H:%M:%S", nowUtc * 1e-3)
			local milliseconds = ("%.2f"):format(nowUtc % 1000 * 1e-3):sub(2)
			local formatedDateTimeUtc = ("%s%s"):format(date, milliseconds)

			for _, sink in pairs(loggerConfig._sinks) do
				sink({levelString = levelString, levelNumber = levelNumber, formatedDateTimeUtc = formatedDateTimeUtc, message = message, nowUtc = nowUtc})
			end
		end
	end

	return logger
end


local function writeTo(loggerConfig)
	local w = {}

	for k, v in pairs(sinks) do
		w[k] = function(...)
			loggerConfig._sinks[k] = v(...)
			return loggerConfig
		end
	end

	return w
end

local function newLoggerConfig()
	local loggerConfig = {
		_sinks = {},
		_minimumLevel = 1,
	}

	loggerConfig.createLogger = function()
		return createLogger(loggerConfig)
	end

	--- Set the minimum level of logging, messages that are lower than this will be ignored.
	---@param newLevel number|string The level to set to.
	---@return table self Allows chaining.
	loggerConfig.minimumLevel = function(newLevel)
		expect.expect(1, newLevel, "number", "string")
		assert(levels[newLevel], "New minimum level is out of range.")
		if type(newLevel) == "string" then
			newLevel = levels[newLevel]
		end
		loggerConfig._minimumLevel = newLevel
        return loggerConfig
	end

	--- Add a registered sink to this logger, messages pushed to the logger will be given to each added sink.
	---@return {console : function, filePlainText : function, fileLuaTable : function} . A table of functions which are the sink constuctors, look up the docs of the sink you want to use to know how to constuct it.
	loggerConfig.writeTo = function()
		return writeTo(loggerConfig)
	end

	return loggerConfig
end

--- Registers a sink that writes the logs to the screen.
---@param terminal table|nil The terminal object to write to, defaults to term.current().
---@return function log Used internally, the logger calls this every time there is something to log.
registerSink("console", function(terminal)
    if terminal then
        local ok, errOldTerm = pcall(term.redirect, terminal) -- borrow redirect to validate the terminal
        if ok then
            term.redirect(errOldTerm)
        else
            error(errOldTerm, 3)
        end
    end
	terminal = terminal or term.current()
	terminal.setCursorPos(1, 1)
	terminal.setTextColour(colours.white)
	terminal.setBackgroundColour(colours.black)
	terminal.clear()
	terminal.setCursorPos(1, 1)
	local width, height = terminal.getSize()
	terminal.setCursorPos(1, height)

	local strings = require("cc.strings")

	local function log(data)
		local level, time, message = data.levelString, data.formatedDateTimeUtc, data.message
		local formatedMessage = ("[%s %s] %s"):format(level, time, message) -- TODO: smart colours

		for _, line in ipairs(strings.wrap(formatedMessage, width)) do
			terminal.write(line)
			terminal.scroll(1)
			terminal.setCursorPos(1, height)
		end
	end
	return log
end)

--- Registers a sink that writes simple text logs to the given filename.
---@param fileName string The file to write to.
---@return function log Used internally, the logger calls this every time there is something to log.
registerSink("filePlainText", function(fileName)
	expect.expect(1, fileName, "string")

	local file, err = fs.open(fileName, "a")
	if not file then
		error(err)
	end

	local function log(data)
		local level, time, message = data.levelString, data.formatedDateTimeUtc, data.message
		local formatedMessage = ("[%s %s] %s"):format(level, time, message)
		file.writeLine(formatedMessage)
		file.flush()
	end
	return log
end)

--- Registers a sink that writes a lua table representing the logs to the given filename.
---@param fileName string The file to write to.
---@return function log Used internally, the logger calls this every time there is something to log.
registerSink("fileLuaTable", function(fileName) -- We miss the outermost {}'s but the reader can add those
	expect.expect(1, fileName, "string")

	local file, err = fs.open(fileName, "a")
	if not file then
		error(err)
	end

	local function log(data)
		file.writeLine(textutils.serialise(data)..",")
		file.flush()
	end
	return log
end)

return {
	getLevels = getLevels,
	registerSink = registerSink,
	newLoggerConfig = newLoggerConfig,
}
