Benchmark = {}
Benchmark.__index = Benchmark


--- Creates a new Benchmark object by reading in a config file.
function Benchmark.create(config)
  local self = setmetatable({}, Benchmark)
  self.testcases = {}
  self.features = {}
  self.featureCount = 0
  self.config = config

  self.testLines = {}
  self.includeLines = {}
  self:readConfig(config)
  return self
end

--- Reads in the benchmark configuration.
function Benchmark:readConfig(config)
  if (settings.config.testfeature) then return end
  local fh = io.open(config)
  if (not fh) then
    logger.debug("'" ..  config .. "' not found, searching in " .. global.benchmarkCfgs)
    fh = io.open(global.benchmarkCfgs .. "/" .. config)
    if (not fh) then return end
  end
  local config = string.sub(config, 1, #config - #global.cfgFiletype)
  config = string.replace(config, global.benchmarkCfgs.."/", "")
  self.testLines[config] = true
  while (true) do
    local line = fh:read()
    if (not line) then break end
    line = string.trim(line)
    if (not (string.sub(line, 1,1) == global.ch_comment) and #line > 0) then
      if string.startsWith(line, "Test ") then
        line = string.split(line, ":", 1)[2]
      end
      local import = false
      for _,incKey in pairs(global.include) do
        local key = string.sub(line, 1,#incKey)
        local include = string.trim(string.sub(line, #incKey+2,-1))
        if (key == incKey) then
          if (not self.testLines[include]) then
            logger.debug("importing benchmark " .. include)
            self:readConfig(include .. global.cfgFiletype)
            self.testLines[include] = false
          end
          import = true
        end
      end
      if (import == false) then
        local test = TestCase.create(line)
        local conf = test:toString()

        if test:isDisabled() then
          logger.debug("skipped disabled test-case " .. line)
        elseif self.testLines[conf] then
          logger.debug("skipped duplicate test-case " .. line)
        else
          self.testLines[conf] = true
          table.insert(self.testcases, test)
          logger.debug("added test-case " .. line)
        end
      end
    end
  end
  io.close(fh)
  if (self:checkExit()) then exit() end
end

--- Checks if there are no tests to perform.
function Benchmark:checkExit()
  if (#self.testcases == 0) then return true
  else return false end
end

--- Reads the feature list files, creates the feature objects.
function Benchmark:getFeatures(force)
  logger.log("retrieving features")
  local force = force or false
  if (not force and settings.isTestFeature()) then
    self.featureList = {}
    local feature = Feature.create(settings.getTestFeature())
    if feature:isDisabled() then return end
    self.features[settings.getTestFeature()] = feature
    self.featureCount = 1
    table.insert(self.featureList, 1, feature)
    return
  end
  local list = settings:getLocalPath() .. "/" .. global.featureFolder .. "/" .. global.featureList
  local fh = io.open(list)
  if (not fh) then logger.err("Could not open feature list '" .. list .. "'") return end
  self.featureList = {}
  self.featureCount = 0
  while true do
    local line = fh:read()
    if line == nil then break end
    if (not (string.sub(line, 1,1) == global.ch_comment) and string.len(line) > 0 ) then
      local feature = Feature.create(line)
      if (not feature:isDisabled()) then
        self.features[line] = feature
        self.featureCount = self.featureCount + 1
        table.insert(self.featureList, self.featureCount, feature)
        logger.debug("added feature " .. line)
      end
    end
  end
end

--- Exports features and their states to make it persistent.
function Benchmark:exportFeatures()
  logger.log("exporting features")
  if (settings.config.skipfeature or settings.config.simulate) then return end
  local file = io.open(global.featureFile, "w")
  file:write("#Feature status\n#Last update: " .. logger.getTimestamp() .. "\n\n")
  local t = {}
  for name, feature in pairs(self.features) do
    table.insert(t,name)
  end
  table.sort(t)
  for i,name in pairs(t) do
    file:write(string.format("%-22s = %s\n", name, tostring(self.features[name]:isSupported())))
    logger.debug("export feature " .. name .. " as " .. tostring(self.features[name]:isSupported()))
  end
  io.close(file)
end

--- Imports features and their states from a previous run.
function Benchmark:importFeatures()
  logger.log("importing features")
  self:getFeatures(true)
  if (not localfileExists(global.featureFile)) then return end
  local fh = io.open(global.featureFile)
  while true do
    local line = fh:read()
    if line == nil then break end
    if ( not (string.sub(line, 1,1) == global.ch_comment) and string.len(line) > 0 ) then
      local split = string.find(line, global.ch_equal)
      if (split) then
        local name = string.trim(string.sub(line, 1, split-1))
        local state = string.trim(string.sub(line, split+1, -1))
        local feature = self.features[name]
        if (feature and state == "true") then feature.supported = true end
        logger.debug("imported feature " .. name .. " as " .. state)
      end
    end
  end
  io.close(fh)
  if (not settings.config.testfeature and not settings.config.skipfeature) then printBar() end
end

--- Returns the state of the given feature.
function Benchmark:isFeatureSupported(name)
  if (not self.features[name]) then
    logger.warn("Feature '" .. name .. "' disabled or not found, check log")
    return false
  end
  return self.features[name]:isSupported()
end

--- Performs the feature tests for all available features.
function Benchmark:testFeatures()
  if settings.config.skipfeature then
    self:importFeatures()
    return
  end
  self:getFeatures()
  if (self.featureCount == 0) then
    logger.printlog("No features to test")
  end
  for i,feature in pairs(self.featureList) do
    logger.printlog("Testing feature ( " .. i .. " / " .. self.featureCount .. " ): " .. feature:getName(), nil, global.headline1)
    feature:runTest()
    if (not settings.config.simulate) then logger.print(feature:getStatus(), 1) end
  end
  logger.log("Step complete")
  if (settings.config.testfeature) then
    logger.printBar()
    self:sumFeatures()
    if (self.features[settings.config.testfeature] ~= nil) then
      local state = self.features[settings.config.testfeature]:isSupported()
      self:importFeatures()
      self.features[settings.config.testfeature].supported = state
    end
    self:exportFeatures()
    exit()
  end
  self:exportFeatures()
  logger.printBar()
end

--- Prepares all test-cases by coping necessary files. If disabled, the test
-- is skipped. Only after this step the test-cases have a valid id.
function Benchmark:prepare()
  if (settings.config.testfeature) then return end
  local testcases = {}
  local fileList = {}
  local fileCount = 0
  for id,test in pairs(self.testcases) do
    logger.printlog("Preparing test ( " .. id .. " / " .. #self.testcases .. " ): " .. test:getName(), nil, global.headline1)
    test:checkFeatures(settings.config[global.ofVersion], self)
    if (not test:isDisabled() or settings.config.simulate) then
      local files = test:getLoadGenFiles()
      for i,file in pairs(files) do
        if (not settings:evalOnly()) then
          logger.print("Selecting file " .. i .. "/" .. #files .. " (" .. file .. ")", 1, global.headline2)
        end
        fileList[file] = true
        fileCount = fileCount + 1
        Setup.createFolder(test:getOutputPath())
      end
      local id = #testcases + 1
      test:setId(id)
      table.insert(testcases, id, test)
    end
    logger.log("selecting files completed")
  end
  if (settings:evalOnly()) then logger.printBar() return end
  logger.printlog("Copying files", nil, global.headline1)
  local n = 1
  for file,_ in pairs(fileList) do
    logger.print("Copying file " .. n .. "/" .. fileCount .. " (" .. file .. ")", 1, global.headline2)
    local cmd = SCPCommand.create()
    cmd:switchCopyTo(settings:isLocal(), settings:getLocalPath() .. "/" .. global.testFolder .. "/" .. file, settings:get(global.loadgenWd) .. "/" .. global.scripts)
    cmd:execute(settings.config.verbose)
    n = n + 1
  end
  self.testcases = testcases
  self:exportTestCases()
  logger.log("Copying completed")
  logger.printBar()
end

--- Exports the configuration of all test-cases to a file.
function Benchmark:exportTestCases()
  local file = io.open(global.results .. "/all_tests.txt", "w")
  for id,test in pairs(self.testcases) do
    file:write(string.format("Test %3s: %s\n", id, test:toString()))
  end
  io.close(file)
end

local function applyContext (testcase, context, expression)
  if expression == nil then return true end

  if type(context) ~= "table" then
    Exception("ParameterException", "parameter 'context' is not a table"):throw()
  end
  if type(expression) ~= "string" then
    Exception("ParameterException", "parameter 'expression' is not a string"):throw()
  end

  expression = string.gsub(expression, "$self\.(%w+)", function (n)
      return testcase:getCurrentValueOfParameter(normalizeKey(n))
  end)

  expression = string.gsub(expression,'%$','x%.')
  local func, err = loadstring("local x = ...; return " .. expression)
  if func == nil then
    Exception('InvalidExpressionException', 'failed to compile expression', err):throw()
  end

  return TryCatchFinally(function ()
      return func(context)
  end, function (ex)
      Exception('InvalidExpressionException', 'failed to execute expression', ex):throw()
  end)
end

function Benchmark:runTest (test, context)

  if TryCatchFinally(function ()
    if not applyContext(test, context, test:getCondition()) then
      logger.printlog("Skipping test ( " .. test:getId() .. " / " .. #self.testcases .. " ): " .. test:getName(), nil, global.headline1)
      logger.printlog("Condition '" .. test:getCondition() .. "' failed", 1, global.headline2)
      test:disable()
      return true
    end
  end,{ InvalidExpressionException = function (ex)
    logger.printlog("Skipping test ( " .. test:getId() .. " / " .. #self.testcases .. " ): " .. test:getName(), nil, global.headline1)
    logger.printlog("Condition '" .. test:getCondition() .. "' invalid", 1, global.headline2)
    logger.debug(tostring(ex), 1, global.headline2)
    test:disable()
    return true
  end}) then return end

  -- apply context to parameters
  for name, value in pairs(test:getParameters()) do
    if TryCatchFinally(function ()
      local newValue = tostring(applyContext(test, context, value))
      test:updateParameter(name, newValue)
    end,{ InvalidExpressionException = function (ex)
      logger.printlog("Skipping test ( " .. test:getId() .. " / " .. #self.testcases .. " ): " .. test:getName(), nil, global.headline1)
      logger.printlog("Expression '" .. value .. "' of parameter '" .. name .. "' invalid" , 1, global.headline2)
      logger.debug(tostring(ex), 1, global.headline2)
      test:disable()
      return true
    end}) then return end
  end

  logger.printlog("Running test ( " .. test:getId() .. " / " .. #self.testcases .. " ): " .. test:getName(), nil, global.headline1)

  if (settings.config.verbose) then test:print() end

  -- configure open-flow device
  local dur = global.ofSetupTime + global.ofResetTimeOut
  logger.print("Configuring OpenFlow device (~" .. dur .. " sec)", 1, global.headline2)
  local template = test:getOutputPath() .. "/" .. test:getCompleteName()
  local ofDev = OpenFlowDevice.create()
  ofDev:reset()
  -- wait for reset process to finish
  sleep(global.ofResetTimeOut)
  local flowData = ofDev:getFlowData(test)
  ofDev:createAllFiles(flowData, template)
  ofDev:installAllFiles(template, "_ovs-output")
  ofDev:dumpAll(template .. "_flowdump-before")
  if (not settings.config.simulate) then sleep(global.ofSetupTime) end
  test:export(template .. "_parameter.csv")

  -- start loadgen
  local duration = test:getDuration() or "?"
  duration = " (measuring for " .. duration .. " sec)"
  logger.print("Starting measurement" .. duration, 1, global.headline2)
  local lgDump = io.open(template .. "_loadgen-output", "w")
  local cmd = CommandLine.getRunInstance(settings:isLocal()).create()
  cmd:addCommand("cd " .. settings:get(global.loadgenWd) .. "/MoonGen")
  cmd:addCommand("./" .. test:getLoadGen() .. " " .. test:getLgArgs())
  if (settings:isVerbose()) then cmd:print() end
  lgDump:write(cmd:execute(settings:isVerbose()))
  if (not Settings:doSimulate()) then
    ofDev:dumpAll(template .. "_flowdump-after")
  end
  io.close(lgDump)
  logger.print("Collecting results", 1, global.headline2)
  local cmd = SCPCommand.create()
  cmd:switchCopyFrom(settings:isLocal(), settings:get(global.loadgenWd) .. "/" .. global.results .."/test_" .. test:getId() .. "_*", test:getOutputPath())
  local out = cmd:execute(settings.config.verbose)
  if (not out) then
    self.reason = "Test-case failed, no files were created"
    test:disable()
  end

  if test.config.afterExecution then
    test.config.afterExecution(test, context)
  end

  logger.log("done")
end

--- Performs the measurement for every test-case
function Benchmark:run()
  if (settings.config.testfeature) then return end
  if (self:checkExit()) then logger.printlog("No test left") end

  if (settings:evalOnly()) then
    for id,test in pairs(self.testcases) do
      TryCatchFinally(function ()
        test:import(test:getOutputPath() .. "/" .. test:getCompleteName() .. "_parameter.csv")
      end,{
        LoadingFileException = function ()
          test:disable()
        end
      })
    end
    return
  end

  local testcontext = {}
  for id,test in pairs(self.testcases) do
    self:runTest(test, testcontext)
  end
  logger.log("Step complete")
  logger.printBar()
end

function Benchmark:sumFeatures()
  if (self.featureCount == 0) then
    logger.print("No features tested")
    logger.printBar()
    return
  elseif (settings:doSkipfeature()) then
    logger.print("Skipping feature report, using " ..global.featureFile)
    logger.printBar()
    return
  end
  local compliance = true;
  for i,feature in pairs(self.featureList) do
    logger.print(string.format("Feature:   ".. Logger.ColorCode.white .. "%-24s" .. Logger.ColorCode.normal .. "%-24s %s", feature:getName(), feature:getState()..",".. feature:getRequiredOFVersion(), feature:getStatus()))
    local optional = feature:getState() == global.featureState.optional or feature:getState() == global.featureState.recommended
    compliance = compliance and (optional or (feature:isSupported() and feature:getState() == global.featureState.required))
  end
  if (not settings.config.testfeature) then
    if (compliance) then logger.printlog("\nTestdevice has passed all required tests for " .. settings.config[global.ofVersion], nil, "lgreen")
    else logger.printlog("\nTestdevice is not compliant with " .. settings.config[global.ofVersion], nil, "lred") end
  end
  Reports.generateFeatureReport(self.featureList)
  logger.printBar()
end

-- creates a database with all test parameters and the according test ids
function Benchmark:generateTestDB()
  local db = {}
  for _,test in pairs(self.testcases) do
    local testName = test:getName()
    db[testName] = db[testName] or {}
    db[testName].ids = db[testName].ids or {}
    db[testName].paramaterList = db[testName].paramaterList or {}
    db[testName].testParameter = db[testName].testParameter or {}

    table.insert(db[testName].ids, test:getId())
    local parameters = test:getParameters()
    db[testName].testParameter[test:getId()] = parameters
    for name in pairs(parameters) do
      db[testName].paramaterList[name] = true
    end
  end
  return db
end

function Benchmark:listTestCases()
  if (#self.testcases > 0 ) then logger.printBar() logger.print("Benchmark config:") end
  for id,test in pairs(self.testcases) do
    test:print()
  end
end
