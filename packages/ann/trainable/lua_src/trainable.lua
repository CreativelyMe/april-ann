-------------------------------
-- LOCAL AUXILIARY FUNCTIONS --
-------------------------------

local MAX_ITERS_WO_COLLECT_GARBAGE=10000

local function check_dataset_sizes(ds1, ds2)
  assert(ds1:numPatterns() == ds2:numPatterns(),
	 string.format("Different input/output datasets "..
			 "numPatterns found: "..
			 "%d != %d",
		       ds1:numPatterns(),
		       ds2:numPatterns()))
end

-----------------------
-- TRAINABLE CLASSES --
-----------------------
april_set_doc("trainable.supervised_trainer", {
		class       = "class",
		summary     = "Supervised machine learning trainer",
		description ={"This class implements methods useful to",
			      "train, evalute and modify contents of",
			      "ANN components or similar supervised learning",
			      "models"}, })

class("trainable.supervised_trainer")

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.__call", {
		class = "method", summary = "Constructor",
		description ={"Constructor of the supervised_trainer class.",
			      "This class implements methods useful to",
			      "train, evalute and modify contents of",
			      "ANN components or similar supervised learning",
			      "models.",
			      "If the component is in build state, the",
			      "constructed trainer is in build state also.",
		},
		params = { "ANN component or similar supervised learning model",
			   "Loss function [optional]",
			   "Bunch size (mini batch) [optional]" },
		outputs = { "Instantiated object" }, })

function trainable.supervised_trainer:__call(ann_component,
					     loss_function,
					     bunch_size)
  local obj = {
    ann_component    = assert(ann_component,"Needs an ANN component object"),
    loss_function    = loss_function or false,
    weights_table    = {},
    components_table = {},
    weights_order    = {},
    components_order = {},
    bunch_size       = bunch_size or false,
  }
  obj = class_instance(obj, self, true)
  return obj
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.get_component", {
		class = "method",
		summary = "Returns an instance of ann.components",
		outputs = { "An instance of ann.components" }, })

function trainable.supervised_trainer:get_component()
  return self.ann_component
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.set_loss_function", {
		class = "method",
		summary = "Modifies the loss function property",
		params = { "Loss function" }, })

function trainable.supervised_trainer:set_loss_function(loss_function)
  self.loss_function = loss_function
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.get_input_size", {
		class = "method",
		summary = "Gets the input size of its component",
		outputs = { "The input size (a number)" }, })

function trainable.supervised_trainer:get_input_size()
  return self.ann_component:get_input_size()
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.get_output_size", {
		class = "method",
		summary = "Gets the output size of its component",
		outputs = { "The output size (a number)" }, })

function trainable.supervised_trainer:get_output_size()
  return self.ann_component:get_output_size()
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.size", {
		class = "method",
		summary = "Returns the model size (number of weights)",
		outputs = { "A number" }, })

function trainable.supervised_trainer:size()
  if #self.components_order == 0 then
    error("It is not build")
  end
  local sz = 0
  for wname,cnn in pairs(self.weights_table) do
    sz = sz + cnn:size()
  end
  return sz
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.save", {
		class = "method",
		summary = "Save the model at a disk file",
		description = {
		  "Save the model and connection weights at",
		  "a disk file.",
		  "Only works after build method is called.",
		},
		params = {
		  "A filename string",
		  { "A string indicating the matrix format: ascii or binary",
		    "[optional]. By default is binary." },
		}, })

function trainable.supervised_trainer:save(filename, binary)
  assert(#self.components_order > 0, "The component is not built")
  local binary = binary or "binary"
  local f = io.open(filename,"w") or error("Unable to open " .. filename)
  f:write("return { model=".. self.ann_component:to_lua_string() .. ",\n")
  f:write("connections={")
  for _,wname in ipairs(self.weights_order) do
    local cobj = self.weights_table[wname]
    local w,oldw = cobj:weights()
    f:write("\n[\"".. wname .. "\"] = {")
    f:write("\ninput = " .. cobj:get_input_size() .. ",")
    f:write("\noutput = " .. cobj:get_output_size() .. ",")
    f:write("\nw = matrix.fromString[[" .. w:toString(binary) .. "]],")
    f:write("\noldw = matrix.fromString[[" .. oldw:toString(binary) .. "]],")
    f:write("\n},")
  end
  f:write("\n},\n")
  if self.loss_function then
    local id = get_object_id(self.loss_function)
    local sz = self.ann_component:get_output_size()
    if id and sz then f:write("loss=" .. id .. "(".. sz .. "),\n") end
  end
  if self.bunch_size then f:write("bunch_size="..self.bunch_size..",\n") end
  f:write("}\n")
  f:close()
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.load", {
		class = "function",
		summary = "Load the model and weights from a disk file",
		description = {
		  "Load the model and connection weights stored at",
		  "a disk file. The trainer is loaded at build state.",
		},
		params = {
		  "A filename string",
		  "Loss function [optional]",
		  "Bunch size (mini batch) [optional]",
		}, })

function trainable.supervised_trainer.load(filename, loss, bunch_size)
  local f = loadfile(filename) or error("Unable to open " .. filename)
  local t = f() or error("Impossible to load chunk from file " .. filename)
  local model = t.model
  local connections = t.connections
  local bunch_size = bunch_size or t.bunch_size
  local loss = loss or t.loss
  local obj = trainable.supervised_trainer(model, loss, bunch_size)
  obj:build()
  for wname,cobj in obj:iterate_weights() do
    local w,oldw = connections[wname].w,connections[wname].oldw
    assert(w ~= nil, "Component " .. wname .. " not found at file")
    assert(connections[wname].input == cobj:get_input_size(),
	   string.format("Incorrect input size, expected %d, found %d\n",
			 cobj:get_input_size(), connections[wname].input))
    assert(connections[wname].output == cobj:get_output_size(),
	   string.format("Incorrect output size, expected %d, found %d\n",
			 cobj:get_output_size(), connections[wname].output))
    cobj:load{ w=w, oldw=oldw or w }
  end
  return obj
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.count_components", {
		class = "method",
		summary = "Count the number of components",
		params = {
		  { "A match string: filter and count only components",
		    "which match [optional], by default is '.*'" },
		}, })

function trainable.supervised_trainer:count_components(match_string)
  local match_string = match_string or ".*"
  if #self.components_order == 0 then
    error("It is not build")
  end
  local count = 0
  for i=1,#self.components_order do
    if self.components_order[i]:match(match_string) then count=count+1 end
  end
  return count
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.count_weights", {
		class = "method",
		summary = "Count the number of connection weight objects",
		params = {
		  { "A match string: filter and count only connections",
		    "which match [optional], by default is '.*'" },
		}, })

function trainable.supervised_trainer:count_weights(match_string)
  local match_string = match_string or ".*"
  if #self.components_order == 0 then
    error("It is not build")
  end
  local count = 0
  for i=1,#self.weights_order do
    if self.weights_order[i]:match(match_string) then count=count+1 end
  end
  return count
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.iterate_components", {
		class = "method",
		summary = "Iterates over components",
		description =
		  {
		    "This method is an iterator function to be used at for",
		    "loops: for name,component in trainer:iterate_components()",
		    "do print(name,component) end",
		  },
		params = {
		  { "A match string: filter and iterates only on components",
		    "which match [optional], by default is '.*'" },
		}, })

function trainable.supervised_trainer:iterate_components(match_string)
  local match_string = match_string or ".*"
  if #self.components_order == 0 then
    error("It is not build")
  end
  local pos = 0
  return function()
    repeat
      pos = pos + 1
      if pos > #self.components_order then
	return nil
      end
    until self.components_order[pos]:match(match_string)
    local name = self.components_order[pos]
    return name,self.components_table[name]
  end
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.iterate_weights", {
		class = "method",
		summary = "Iterates over weight connection objects",
		description = 
		  {
		    "This method is an iterator function to be used at for",
		    "loops: for name,connections in trainer:iterate_weights()",
		    "do print(name,component) end",
		  },
		params = {
		  { "A match string: filter and count only connections",
		    "which match [optional], by default is '.*'" },
		}, })

function trainable.supervised_trainer:iterate_weights(match_string)
  local match_string = match_string or ".*"
  if #self.components_order == 0 then
    error("It is not build")
  end
  local pos = 0
  return function()
    repeat
      pos = pos + 1
      if pos > #self.weights_order then
	return nil
      end
    until self.weights_order[pos]:match(match_string)
    local name = self.weights_order[pos]
    return name,self.weights_table[name]
  end
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.component", {
		class = "method",
		summary = "Returns a component given its name",
		description =
		  {
		    "This method returns a component object",
		    "which name is the given argument.",
		    "This method is forbidden before build method is called.",
		    "If an error is produced, it returns nil."
		  },
		params = { "A string with the component name" },
		outputs = { "A component object" } })

function trainable.supervised_trainer:component(str)
  if #self.components_order == 0 then
    error("Needs execution of build method")
  end
  return self.components_table[str]
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.weights", {
		class = "method",
		summary = "Returns a connections object given its name",
		description =
		  {
		    "This method returns a connections object",
		    "which name is the given argument.",
		    "This method is forbidden before build method is called.",
		    "If an error is produced, returns nil."
		  }, 
		params = { "A string with the connections name" },
		outputs = { "An ann.connections object" } })

function trainable.supervised_trainer:weights(str)
  if #self.components_order == 0 then
    error("Needs execution of build method")
  end
  return self.weights_table[str]
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.randomize_weights", {
		class = "method",
		summary = "Initializes randomly model weights and biases",
		description =
		  {
		    "This method initialies the weights, following an uniform",
		    "distribution, in the range [c*inf,c*sup].",
		    "Constant c depends on fan-in and/or fan-out fields.",
		    "If fan-in and fan-out are false, then c=1.",
		    "If fan-in=true and fan-out=false, then c=1/sqrt(fanin).",
		    "If fan-in=false and fan-out=true, then c=1/sqrt(fanout).",
		    "If fan-in and fan-out are true, then c=1/sqrt(fanin + fanout).",
		  },
		params = {
		  ["name_match"] = {
		    "A match string [optional], if given, only the connection",
		    "weights which match will be randomized",
		  },
		  ["random"] = "A random object",
		  ["inf"]    = "Range inf value",
		  ["sup"]    = "Range sup value",
		  ["use_fanin"] = "An optional boolean, by default false",
		  ["use_fanout"] = "An optional boolean, by default false",
		}, })

function trainable.supervised_trainer:randomize_weights(t)
  local params = get_table_fields(
    {
      name_match = { type_match="string", mandatory=false, default = nil },
      random  = { isa_match = random,  mandatory = true },
      inf     = { type_match="number", mandatory = true },
      sup     = { type_match="number", mandatory = true },
      use_fanin  = { type_match="boolean", mandatory = false, default = false },
      use_fanout = { type_match="boolean", mandatory = false, default = false },
    }, t)
  assert(#self.components_order > 0,
	 "Execute build method before randomize_weights")
  for i,wname in ipairs(self.weights_order) do
    if not params.name_match or wname:match(params.name_match) then
      local current_inf = params.inf
      local current_sup = params.sup
      local constant    = 0
      local connection  = self.weights_table[wname]
      if params.use_fanin then
	constant = constant + connection:get_input_size()
      end
      if params.use_fanout then
	constant = constant + connection:get_output_size()
      end
      if constant > 0 then
	current_inf = current_inf / math.sqrt(constant)
	current_sup = current_sup / math.sqrt(constant)
      end
      connection:randomize_weights{ random = params.random,
				    inf    = current_inf,
				    sup    = current_sup }
    end
  end
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.build", {
		class = "method",
		summary = "Executes build method of the component",
		description = 
		  {
		    "This method executes the build method of its",
		    "ann_component property, and weights_order, weights_table,",
		    "components_order and components_table properties are",
		    "also built. The method returns two tables with the",
		    "content of weights_table and components_table, in order",
		    "to provide easy acces to components and connections.",
		  }, 
		params = {
		  ["weights"] = "A dictionary weights_name => ann.connections object [optional]",
		  ["input"]   = "The input size of the component [optional]",
		  ["output"]  = "The output size of the component [optional]",
		},
		outputs = {
		  "Weights table, associates weights_name => ann.connections object",
		  "Components table, associates component_name => ann.components object",
		} })

function trainable.supervised_trainer:build(t)
  local params = get_table_fields(
    {
      weights = { type_match="table",  mandatory = false, default=nil },
      input   = { type_match="number", mandatory = false, default=nil },
      output  = { type_match="number", mandatory = false, default=nil },
    }, t or {})
  self.weights_table = params.weights or {}
  self.ann_component:reset_connections()
  self.weights_table,
  self.components_table = self.ann_component:build{
    input   = params.input,
    output  = params.output,
    weights = self.weights_table, }
  self.weights_order = {}
  for name,_ in pairs(self.weights_table) do
    table.insert(self.weights_order, name)
  end
  table.sort(self.weights_order)
  self.components_order = {}
  for name,_ in pairs(self.components_table) do
    table.insert(self.components_order, name)
  end
  table.sort(self.components_order)
  return self.weights_table,self.components_table
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.train_step", {
		class = "method",
		summary = "Executes one training step",
		description = 
		  {
		    "This method executes one training step of its component",
		    "with the given pair input/target output.",
		    "It returns the loss for the given pair of patterns and",
		    "the gradient computed at component inputs.",
		  }, 
		params = {
		  "A table with one input pattern or a token (with one or more patterns)",
		  "The corresponding target output pattern (table or token)",
		},
		outputs = {
		  "A number with the loss of the training step",
		  "A token with the gradient of loss function at component inputs",
		} })

function trainable.supervised_trainer:train_step(input, target)
  if type(input)  == "table" then input  = tokens.memblock(input)  end
  if type(target) == "table" then target = tokens.memblock(target) end
  self.ann_component:reset()
  local output   = self.ann_component:forward(input, true)
  local tr_loss  = self.loss_function:loss(output, target)
  local gradient = self.loss_function:gradient(output, target)
  self.ann_component:backprop(gradient)
  self.ann_component:update()
  return tr_loss,gradient
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.validate_step", {
		class = "method",
		summary = "Executes one validate step",
		description = 
		  {
		    "This method performs one forward step and computes",
		    "the loss for the given pair input/target output.",
		  }, 
		params = {
		  "A table with one input pattern or a token (with one or more patterns)",
		  "The corresponding target output pattern (table or token)",
		},
		outputs = {
		  "A number with the loss of the training step",
		} })

function trainable.supervised_trainer:validate_step(input, target)
  if type(input)  == "table" then input  = tokens.memblock(input)  end
  if type(target) == "table" then target = tokens.memblock(target) end
  self.ann_component:reset()
  local output   = self.ann_component:forward(input)
  local tr_loss  = self.loss_function:loss(output, target)
  return tr_loss
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.calculate", {
		class = "method",
		summary = "Executes one forward",
		description = 
		  {
		    "This method performs one forward step and returns",
		    "the computed output for the given input.",
		  }, 
		params = {
		  "A table with one input pattern or a token (with one or more patterns)",
		},
		outputs = {
		  "A table with the computed output",
		} })

function trainable.supervised_trainer:calculate(input)
  if type(input) == "table" then input = tokens.memblock(input) end
  return self.ann_component:forward(input):convert_to_memblock():to_table()
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.train_dataset", {
		class = "method",
		summary = "Executes one training epoch with a given dataset",
		description = 
		  {
		    "This method performs one training epoch with a given",
		    "dataset traversing patterns in order, and returns the",
		    "mean loss of each training step.",
		    "Each training step is performed with bunch_size patterns.",
		  }, 
		params = {
		  ["input_dataset"]  = "A dataset float or dataset token",
		  ["output_dataset"] = "A dataset float or dataset token (target output)",
		  ["bunch_size"]     = 
		    {
		      "Bunch size (mini-batch). It is optional if bunch_size",
		      "was set at constructor, otherwise it is mandatory.",
		    }, 
		},
		outputs = {
		  "A number with the mean loss of each training step",
		} })

april_set_doc("trainable.supervised_trainer.train_dataset", {
		class = "method",
		summary = "Executes one training epoch with shuffle",
		description = 
		  {
		    "This method performs one training epoch with a given",
		    "dataset traversing patterns in shuffle order, and returns the",
		    "mean loss of each training step.",
		    "Each training step is performed with bunch_size patterns.",
		  }, 
		params = {
		  ["input_dataset"]  = "A dataset float or dataset token",
		  ["output_dataset"] = "A dataset float or dataset token (target output)",
		  ["shuffle"]        = "A random object used to shuffle patterns before training",
		  ["bunch_size"]     = 
		    {
		      "Bunch size (mini-batch). It is optional if bunch_size",
		      "was set at constructor, otherwise it is mandatory.",
		    }, 
		},
		outputs = {
		  "A number with the mean loss of each training step",
		} })

april_set_doc("trainable.supervised_trainer.train_dataset", {
		class = "method",
		summary = "Executes one stochastic training epoch with replacement",
		description = 
		  {
		    "This method performs one stochastic training epoch with a given",
		    "dataset. Patterns are choosed randomly with replacement",
		    "until a given replacement size. The",
		    "mean loss of each training step is returned.",
		    "Each training step is performed with bunch_size patterns.",
		  }, 
		params = {
		  ["input_dataset"]  = "A dataset float or dataset token",
		  ["output_dataset"] = "A dataset float or dataset token (target output)",
		  ["shuffle"]        = "A random object used to shuffle patterns before training",
		  ["replacement"]    = "A number with the size of replacement training",
		  ["bunch_size"]     = 
		    {
		      "Bunch size (mini-batch). It is optional if bunch_size",
		      "was set at constructor, otherwise it is mandatory.",
		    }, 
		},
		outputs = {
		  "A number with the mean loss of each training step",
		} })

april_set_doc("trainable.supervised_trainer.train_dataset", {
		class = "method",
		summary = "Executes one stochastic training epoch with distribution",
		description = 
		  {
		    "This method performs one stochastic training epoch with a given",
		    "set of datasets with different a-priory probabilities.",
		    "Patterns are choosed randomly with replacement following",
		    "given a-priori distribution, until a given replacement",
		    "size. The mean loss of each training step is returned.",
		    "Each training step is performed with bunch_size patterns.",
		  }, 
		params = {
		  ["distibution"]    = "An array of tables with input_dataset,"..
		    " output_dataset and probability fields",
		  ["shuffle"]        = "A random object used to shuffle patterns before training",
		  ["replacement"]    = "A number with the size of replacement training",
		  ["bunch_size"]     = 
		    {
		      "Bunch size (mini-batch). It is optional if bunch_size",
		      "was set at constructor, otherwise it is mandatory.",
		    }, 
		},
		outputs = {
		  "A number with the mean loss of each training step",
		} })

function trainable.supervised_trainer:train_dataset(t)
  local params = get_table_fields(
    {
      input_dataset  = { mandatory = false, default=nil },
      output_dataset = { mandatory = false, default=nil },
      distribution   = { type_match="table", mandatory = false, default=nil,
			 getter = get_table_fields_ipairs{
			   input_dataset  = { mandatory=true },
			   output_dataset = { mandatory=true },
			   probability    = { type_match="number",
					      mandatory=true },
			 },
      },
      bunch_size     = { type_match = "number",
			 mandatory = (self.bunch_size == false),
			 default=self.bunch_size },
      shuffle        = { isa_match  = random,   mandatory = false, default=nil },
      replacement    = { type_match = "number", mandatory = false, default=nil },
    }, t)
  -- ERROR CHECKING
  assert(params.input_dataset ~= not params.output_dataset,
	 "input_dataset and output_dataset fields are mandatory together")
  assert(not params.input_dataset or not params.distribution,
	 "input_dataset/output_dataset fields are forbidden with distribution")
  --
  
  -- TRAINING TABLES
  
  -- for each pattern, index in dataset
  local ds_idx_table = {}
  -- set to ZERO the accumulated of loss
  self.loss_function:reset()
  if params.distribution then
    -- Training with distribution: given a table of datasets the patterns are
    -- sampled following the given apriory probability
    assert(params.shuffle,"shuffle is mandatory with distribution")
    assert(params.replacement,"replacement is mandatory with distribution")
    params.input_dataset  = dataset.token.union()
    params.output_dataset = dataset.token.union()
    local aprioris = {}
    local sizes    = {}
    local sums     = { 0 }
    for i,v in ipairs(params.distribution) do
      if isa(v.input_dataset, dataset) then
	v.input_dataset  = dataset.token.wrapper(v.input_dataset)
      end
      if isa(v.output_dataset, dataset) then
	v.output_dataset = dataset.token.wrapper(v.output_dataset)
      end
      check_dataset_sizes(v.input_dataset, v.output_dataset)
      table.insert(aprioris, v.probability)
      table.insert(sizes, v.input_dataset:numPatterns())
      table.insert(sums, sums[#sums] + sizes[#sizes])
      params.input_dataset:push_back(v.input_dataset)
      params.output_dataset:push_back(v.output_dataset)
    end
    -- generate training tables
    local dice = random.dice(aprioris)
    for i=1,params.replacement do
      local whichclass=dice:thrown(params.shuffle)
      local idx=params.shuffle:randInt(1,sizes[whichclass])
      table.insert(ds_idx_table, idx + sums[whichclass])
    end
  else
    if isa(params.input_dataset, dataset) then
      params.input_dataset  = dataset.token.wrapper(params.input_dataset)
    end
    if isa(params.output_dataset, dataset) then
      params.output_dataset = dataset.token.wrapper(params.output_dataset)
    end
    check_dataset_sizes(params.input_dataset, params.output_dataset)
    local num_patterns = params.input_dataset:numPatterns()
    -- generate training tables depending on training mode (replacement,
    -- shuffled, or sequential)
    if params.replacement then
      assert(params.shuffle,"shuffle is mandatory with replacement")
      for i=1,params.replacement do
	table.insert(ds_idx_table, params.shuffle:randInt(1,num_patterns))
      end
    elseif params.shuffle then
      ds_idx_table = params.shuffle:shuffle(num_patterns)
    else
      for i=1,num_patterns do table.insert(ds_idx_table, i) end
    end
  end
  -- TRAIN USING ds_idx_table
  local k=0
  for i=1,#ds_idx_table,params.bunch_size do
    local bunch_indexes = {}
    local last = math.min(i+params.bunch_size-1, #ds_idx_table)
    -- OJO j - 1
    for j=i,last do table.insert(bunch_indexes, ds_idx_table[j] - 1) end
    local input_bunch  = params.input_dataset:getPatternBunch(bunch_indexes)
    local output_bunch = params.output_dataset:getPatternBunch(bunch_indexes)
    self:train_step(input_bunch, output_bunch)
    k=k+1
    if k == MAX_ITERS_WO_COLLECT_GARBAGE then collectgarbage("collect") k=0 end
  end
  ds_idx_table = nil
  collectgarbage("collect")
  return self.loss_function:get_accum_loss()
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.validate_dataset", {
		class = "method",
		summary = "Executes one validation epoch with a given dataset",
		description = 
		  {
		    "This method performs one validation epoch with a given",
		    "dataset traversing patterns in order, and returns the",
		    "mean loss of each validate step.",
		    "Each validate step is performed with bunch_size patterns.",
		  }, 
		params = {
		  ["input_dataset"]  = "A dataset float or dataset token",
		  ["output_dataset"] = "A dataset float or dataset token (target output)",
		  ["bunch_size"]     = 
		    {
		      "Bunch size (mini-batch). It is optional if bunch_size",
		      "was set at constructor, otherwise it is mandatory.",
		    }, 
		},
		outputs = {
		  "A number with the mean loss of each validate step",
		} })

april_set_doc("trainable.supervised_trainer.validate_dataset", {
		class = "method",
		summary = "Executes one validation epoch with shuffle",
		description = 
		  {
		    "This method performs one validation epoch with a given",
		    "dataset traversing patterns in shuffle order, and returns the",
		    "mean loss of each validate step.",
		    "Each validate step is performed with bunch_size patterns.",
		  }, 
		params = {
		  ["input_dataset"]  = "A dataset float or dataset token",
		  ["output_dataset"] = "A dataset float or dataset token (target output)",
		  ["shuffle"]        = "A random object used to shuffle patterns before validate",
		  ["bunch_size"]     = 
		    {
		      "Bunch size (mini-batch). It is optional if bunch_size",
		      "was set at constructor, otherwise it is mandatory.",
		    }, 
		},
		outputs = {
		  "A number with the mean loss of each validate step",
		} })

april_set_doc("trainable.supervised_trainer.validate_dataset", {
		class = "method",
		summary = "Executes one stochastic validation epoch with replacement",
		description = 
		  {
		    "This method performs one stochastic validation epoch with a given",
		    "dataset. Patterns are choosed randomly with replacement",
		    "until a given replacement size. The",
		    "mean loss of each validate step is returned.",
		    "Each validate step is performed with bunch_size patterns.",
		  }, 
		params = {
		  ["input_dataset"]  = "A dataset float or dataset token",
		  ["output_dataset"] = "A dataset float or dataset token (target output)",
		  ["shuffle"]        = "A random object used to shuffle patterns before validate",
		  ["replacement"]    = "A number with the size of replacement validate",
		  ["bunch_size"]     = 
		    {
		      "Bunch size (mini-batch). It is optional if bunch_size",
		      "was set at constructor, otherwise it is mandatory.",
		    }, 
		},
		outputs = {
		  "A number with the mean loss of each validate step",
		} })

function trainable.supervised_trainer:validate_dataset(t)
  local params = get_table_fields(
    {
      input_dataset  = { mandatory = true },
      output_dataset = { mandatory = true },
      bunch_size     = { type_match = "number",
			 mandatory = (self.bunch_size == false),
			 default=self.bunch_size },
      shuffle        = { isa_match  = random, mandatory = false, default=nil },
      replacement    = { type_match = "number", mandatory = false, default=nil },
    }, t)
  -- ERROR CHECKING
  assert(params.input_dataset ~= not params.output_dataset,
	 "input_dataset and output_dataset fields are mandatory together")
  assert(not params.input_dataset or not params.distribution,
	 "input_dataset/output_dataset fields are forbidden with distribution")
  -- TRAINING TABLES
  
  -- for each pattern, index in corresponding datasets
  local ds_idx_table = {}
  self.loss_function:reset()
  if isa(params.input_dataset, dataset) then
    params.input_dataset  = dataset.token.wrapper(params.input_dataset)
  end
  if isa(params.output_dataset, dataset) then
    params.output_dataset = dataset.token.wrapper(params.output_dataset)
  end
  check_dataset_sizes(params.input_dataset, params.output_dataset)
  local num_patterns = params.input_dataset:numPatterns()
  -- generate training tables depending on training mode (replacement,
  -- shuffled, or sequential)
  if params.replacement then
    assert(params.shuffle,"shuffle is mandatory with replacement")
    for i=1,params.replacement do
      table.insert(ds_idx_table, params.shuffle:randInt(1,num_patterns))
    end
  elseif params.shuffle then
    ds_idx_table = params.shuffle:shuffle(num_patterns)
  else
    for i=1,num_patterns do table.insert(ds_idx_table, i) end
  end
  -- TRAIN USING ds_idx_table
  local k=0
  for i=1,#ds_idx_table,params.bunch_size do
    local bunch_indexes = {}
    local last = math.min(i+params.bunch_size-1, #ds_idx_table)
    -- OJO j - 1
    for j=i,last do table.insert(bunch_indexes, ds_idx_table[j] - 1) end
    local input_bunch  = params.input_dataset:getPatternBunch(bunch_indexes)
    local output_bunch = params.output_dataset:getPatternBunch(bunch_indexes)
    self:validate_step(input_bunch, output_bunch)
    k=k+1
    if k == MAX_ITERS_WO_COLLECT_GARBAGE then collectgarbage("collect") k=0 end
  end
  ds_idx_table = nil
  collectgarbage("collect")
  return self.loss_function:get_accum_loss()
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.for_each_pattern", {
		class = "method",
		summary = "Iterates over a dataset calling a given function",
		description = 
		  {
		    "This method performs forward with all patterns of the",
		    "given input_dataset. Each forward is done for bunch_size",
		    "patterns at the same time, and after each forward the",
		    "given function is called.",
		  }, 
		params = {
		  ["input_dataset"]  = "A dataset float or dataset token",
		  ["func"] = {"A function with this header: ",
			      "func(INDEXES,TRAINER). INDEXES is a table",
			      "with pattern indexes of the bunch, and",
			      "TRAINER is the instance of the trainer object.",},
		  ["bunch_size"]     = 
		    {
		      "Bunch size (mini-batch). It is [optional] if bunch_size",
		      "was set at constructor, otherwise it is mandatory.",
		    }, 
		}, })

function trainable.supervised_trainer:for_each_pattern(t)
  local params = get_table_fields(
    {
      input_dataset  = { mandatory = true },
      func           = { mandatory = true, type_match="function" },
      bunch_size     = { type_match = "number",
			 mandatory = (self.bunch_size == false),
			 default=self.bunch_size },
    }, t)
  if isa(params.input_dataset, dataset) then
    params.input_dataset = dataset.token.wrapper(params.input_dataset)
  end
  local nump = params.input_dataset:numPatterns()
  local k=0
  for i=1,nump,params.bunch_size do
    local bunch_indexes = {}
    local last = math.min(i+params.bunch_size-1, nump)
    -- OJO j - 1
    for j=i,last do table.insert(bunch_indexes, j - 1) end
    local input  = params.input_dataset:getPatternBunch(bunch_indexes)
    local output = self.ann_component:forward(input)
    params.func(bunch_indexes, self)
    k=k+1
    if k == MAX_ITERS_WO_COLLECT_GARBAGE then collectgarbage("collect") k=0 end
  end
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.use_dataset", {
		class = "method",
		summary = "Computes forward with a given dataset "..
		  "provinding output dataset",
		description = 
		  {
		    "This method performs forward with all patterns of the",
		    "given input_dataset, storing outputs at an",
		    "output_dataset with enough space.",
		    "If output_dataset field is given, it must be prepared to",
		    "store all input_dataset:numPatterns().",
		    "If output_dataset field is nil, a new dataset will be",
		    "constructed. The method returns the output_dataset in",
		    "both cases.",
		    "Each forward step is performed with bunch_size patterns.",
		  }, 
		params = {
		  ["input_dataset"]  = "A dataset float or dataset token",
		  ["output_dataset"] = "A dataset float or dataset token [optional].",
		  ["bunch_size"]     = 
		    {
		      "Bunch size (mini-batch). It is optional if bunch_size",
		      "was set at constructor, otherwise it is mandatory.",
		    }, 
		},
		outputs = {
		  "The output_dataset with input_dataset:numPatterns().",
		} })

function trainable.supervised_trainer:use_dataset(t)
  local params = get_table_fields(
    {
      input_dataset  = { mandatory = true },
      output_dataset = { mandatory = false, default=nil },
      bunch_size     = { type_match = "number",
			 mandatory = (self.bunch_size == false),
			 default=self.bunch_size },
    }, t)
  local nump    = params.input_dataset:numPatterns()
  local outsize = self.ann_component:get_output_size()
  if params.output_dataset then
    if isa(params.output_dataset, dataset) then
      params.output_dataset = dataset.token.wrapper(params.output_dataset)
    end
  elseif isa(params.input_dataset, dataset) then
    params.output_dataset = dataset.matrix(matrix(nump, outsize))
    t.output_dataset      = params.output_dataset
    params.output_dataset = dataset.token.wrapper(params.output_dataset)
  else
    params.output_dataset = dataset.token.vector(outsize)
    t.output_dataset      = params.output_dataset
  end
  if isa(params.input_dataset, dataset) then
    params.input_dataset = dataset.token.wrapper(params.input_dataset)
  end
  local k=0
  for i=1,nump,params.bunch_size do
    local bunch_indexes = {}
    local last = math.min(i+params.bunch_size-1, nump)
    -- OJO j - 1
    for j=i,last do table.insert(bunch_indexes, j - 1) end
    local input  = params.input_dataset:getPatternBunch(bunch_indexes)
    local output = self.ann_component:forward(input)
    params.output_dataset:putPatternBunch(bunch_indexes,output)
    k=k+1
    if k == MAX_ITERS_WO_COLLECT_GARBAGE then collectgarbage("collect") k=0 end
  end
  return t.output_dataset
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.show_weights", {
		class = "method",
		summary = "Print connection weights (for debug purposes).", })

function trainable.supervised_trainer:show_weights()
  for _,wname in pairs(self.weights_order) do
    local w = self.weights_table[wname]:weights():toTable()
    print(wname, table.concat(w, " "))
  end
end

------------------------------------------------------------------------

april_set_doc("trainable.supervised_trainer.clone", {
		class = "method",
		summary = "Returns a deep-copy of the object.", })

function trainable.supervised_trainer:clone()
  local obj = trainable.supervised_trainer(self.ann_component:clone(),
					   nil,
					   self.bunch_size)
  if self.loss_function then
    obj:set_loss_function(self.loss_function:clone())
  end
  if #self.weights_order > 0 then
    local aux_weights = {}
    for wname,cnn in pairs(self.weights_table) do
      aux_weights[wname] = cnn:clone()
    end
    obj:build{ weights=aux_weights }
  end
  return obj
end

------------------------------------------------------------------------
-- params is a table like this:
-- { training_table   = { input_dataset = ...., output_dataset = ....., .....},
--   validation_table = { input_dataset = ...., output_dataset = ....., .....},
--   validation_function = function( thenet, validation_table ) .... end
--   min_epochs = NUMBER,
--   max_epochs = NUMBER,
--   -- train_params is this table ;)
--   stopping_criterion = function{ current_epoch, best_epoch, best_val_error, train_error, validation_error, train_params } .... return true or false end
--   update_function = function{ current_epoch, best_epoch, best_val_error, 
--   first_epoch = 1
-- }
--
-- and returns this:
--  return { best             = best,
--	     best_epoch       = best_epoch,
--	     best_val_error   = best_val_error,
--	     num_epochs       = epoch,
--	     last_train_error = last_train_error,
--	     last_val_error   = last_val_error }
april_set_doc("trainable.supervised_trainer.train_holdout_validation", {
		class = "method",
		summary = "Trains until convergence with training and "..
		  "validation tables.",
		description = 
		  {
		    "This method trains the component object using",
		    "a training_table checking convergence using a",
		    "validation_table.",
		    "It performs a loop until convergence (stopping criterion)",
		    "running train_dataset(training_table) and",
		    "validate_dataset(validation_table) alternatively.",
		    "Execution of validate_dataset(...) is configurable by",
		    "validation_function parameter. After each epoch",
		    "update_function parameter could be used to do things",
		    "or to show information at screen. It outputs a table.",
		  }, 
		params = {
		  ["training_table"] = "A table for training_dataset method",
		  ["validation_table"] = "A table for validate_dataset method",
		  ["validation_function"] = "A function to customize "..
		    "validation procedure [optional]. By default it calls "..
		    "validate_dataset(validation_table) and uses same loss "..
		    "function to train and validate. The function is called "..
		    "as validation_function(self, validation_table)",
		  ["best_function"] = "A function to customize code execution "..
		    "when validation loss is improved [optional]. It is "..
		    "called as best_function(best_trainer_clone,best_error,best_epoch)",
		  ["epochs_wo_validation"] = {
		    "Number of epochs without taking into account validation",
		    "error [optional]. By default is 0",
		  },
		  ["min_epochs"] = "Minimum number of epochs",
		  ["max_epochs"] = "Maximum number of epochs",
		  ["stopping_criterion"] = "A predicate function which "..
		  "returns true if stopping criterion, false otherwise. "..
		    "Some basic criteria are implemented at "..
		    "trainable.stopping_criteria table."..
		    "The criterion function is called as "..
		    "stopping_criterion({ current_epoch=..., best_epoch=..., "..
		    "best_val_error=..., train_error=..., "..
		    "validation_error=..., train_params=THIS_PARAMS }).",
		  ["update_function"] = "Function executed after each "..
		  "epoch (after training and validation), for print "..
		    "purposes (and other stuff). It is called as "..
		    "update_function({ current_epoch=..., "..
		    "best_epoch=..., best_val_error=..., "..
		    "train_error=..., validation_error=..., "..
		    "cpu=CPU_TIME_LAST_EPCOCH, "..
		    "wall=CPU_WALL_TIME_LAST_EPOCH, "..
		    "train_params=THIS_PARAMS}) [optional].",
		  ["first_epoch"] = "Useful to rerun previous stopped "..
		    "experiments",
		},
		outputs = {
		  ["best"] = "The best validation loss trainer clone",
		  ["best_val_error"] = "The best validation loss",
		  ["best_epoch"] = "The best epoch",
		  ["last_epoch"] = "Number of epochs performed",
		  ["last_train_error"] = "The training loss achieved at last epoch",
		  ["last_val_error"] = "The validation loss achieved at last epoch",
		}, })

function trainable.supervised_trainer:train_holdout_validation(t)
  local params = get_table_fields(
    {
      training_table   = { mandatory=true, type_match="table" },
      validation_table = { mandatory=true, type_match="table" },
      validation_function = { mandatory=false, type_match="function",
			      default=function(thenet,t)
				return thenet:validate_dataset(t)
			      end },
      best_function = { mandatory=false, type_match="function",
			default=function(thenet,t) end },
      epochs_wo_validation = { mandatory=false, type_match="number", default=0 },
      min_epochs = { mandatory=true, type_match="number" },
      max_epochs = { mandatory=true, type_match="number" },
      stopping_criterion = { mandatory=true, type_match="function" },
      update_function    = { mandatory=false, type_match="function",
			     default=function(t) return end },
      first_epoch        = { mandatory=false, type_match="number", default=1 },
    }, t)
  local best_epoch       = params.first_epoch
  local best             = self:clone()
  local best_val_error   = params.validation_function(self,
						      params.validation_table)
  local last_val_error   = best_val_error
  local last_train_error = 0
  local last_epoch       = 0
  for epoch=params.first_epoch,params.max_epochs do
    collectgarbage("collect")
    local clock = util.stopwatch()
    clock:go()
    local tr_error  = self:train_dataset(params.training_table)
    local val_error = params.validation_function(self, params.validation_table)
    last_train_error,last_val_error,last_epoch = tr_error,val_error,epoch
    clock:stop()
    cpu,wall = clock:read()
    if val_error < best_val_error then
      best_epoch     = epoch
      best_val_error = val_error
      best           = self:clone()
      params.best_function(best, best_val_error, best_epoch)
    elseif epoch <= params.epochs_wo_validation then
      best_epoch     = epoch
      best_val_error = val_error
      best           = self:clone()
    end
    params.update_function({ current_epoch    = epoch,
			     best_epoch       = best_epoch,
			     best_val_error   = best_val_error,
			     train_error      = tr_error,
			     validation_error = val_error,
			     cpu              = cpu,
			     wall             = wall,
			     train_params     = params })
    if (epoch > params.min_epochs and
	  params.stopping_criterion({ current_epoch    = epoch,
				      best_epoch       = best_epoch,
				      best_val_error   = best_val_error,
				      train_error      = tr_error,
				      validation_error = val_error,
				      train_params     = params })) then
      break						  
    end
  end
  return { best             = best,
	   best_val_error   = best_val_error,
	   best_epoch       = best_epoch,
	   last_epoch       = last_epoch,
	   last_train_error = last_train_error,
	   last_val_error   = last_val_error }
end

---------------------------------------------------------------------------
-- This function trains without validation, it is trained until a maximum of
-- epochs or until the improvement in training error is less than given
-- percentage
--
-- params is a table like this:
-- { training_table   = { input_dataset = ...., output_dataset = ....., .....},
--   min_epochs = NUMBER,
--   max_epochs = NUMBER,
--   update_function = function{ current_epoch, best_epoch, best_val_error,
--   percentage_stopping_criterion = NUMBER (normally 0.01 or 0.001)
-- }
--
-- returns the trained object
april_set_doc("trainable.supervised_trainer.train_wo_validation", {
		class = "method",
		summary = "Trains until a given convergence of training loss, "..
		  "using a given training_table.",
		description = 
		  {
		    "This method trains the component object using",
		    "a training_table checking convergence based on training",
		    "loss.",
		    "It performs a loop until convergence (stopping criterion)",
		    "running train_dataset(training_table).",
		    "After each epoch",
		    "update_function parameter could be used to do things",
		    "or to show information at screen. It outputs a",
		    "trainable.supervised_trainer object.",
		  }, 
		params = {
		  ["training_table"] = "A table for training_dataset method",
		  ["min_epochs"] = "Minimum number of epochs",
		  ["max_epochs"] = "Maximum number of epochs",
		  ["percentage_stopping_criterion"] = "A percentage of "..
		    "training loss improvement under which convergence is "..
		    "achieved.",
		  ["update_function"] = "Function executed after each "..
		  "epoch (after training and validation), for print "..
		    "purposes (and other stuff). It is called as "..
		    "update_function({ train_error=..., "..
		    "train_improvement=..., "..
		    "train_params=THIS_PARAMS}) [optional].",
		},
		outputs = {
		  "A trainable.supervised_trainer object"
		}, })

april_set_doc("trainable.supervised_trainer.train_wo_validation", {
		class = "method",
		summary = "Trains until a given convergence of training loss, "..
		  "using a given training_table functor.",
		description = 
		  {
		    "This method trains the component object using",
		    "a training_table checking convergence based on training",
		    "loss. The training_table is a function which after",
		    "it is called, it returns a table for",
		    "training_dataset(...) method, so it is customizable.",
		    "It performs a loop until convergence (stopping criterion)",
		    "running train_dataset(training_table).",
		    "After each epoch",
		    "update_function parameter could be used to do things",
		    "or to show information at screen. It outputs a",
		    "trainable.supervised_trainer object.",
		  }, 
		params = {
		  ["training_table"] = "A function which returns a "..
		    "training_dataset compatible table",
		  ["min_epochs"] = "Minimum number of epochs",
		  ["max_epochs"] = "Maximum number of epochs",
		  ["percentage_stopping_criterion"] = "A percentage of "..
		    "training loss improvement under which convergence is "..
		    "achieved.",
		  ["update_function"] = "Function executed after each "..
		  "epoch (after training and validation), for print "..
		    "purposes (and other stuff). It is called as "..
		    "update_function({ current_epoch=..., "..
		    "train_error=..., "..
		    "train_improvement=..., "..
		    "train_params=THIS_PARAMS}) [optional].",
		},
		outputs = {
		  "A trainable.supervised_trainer object"
		}, })

function trainable.supervised_trainer:train_wo_validation(t)
  local params = get_table_fields(
    {
      training_table = { mandatory=true },
      min_epochs = { mandatory=true, type_match="number" },
      max_epochs = { mandatory=true, type_match="number" },
      update_function = { mandatory=false, type_match="function",
			  default=function(t) return end },
      percentage_stopping_criterion = { mandatory=false, type_match="number",
					default=0.01 },
    }, t)
  local prev_tr_err = 1111111111111
  local best        = self:clone()
  for epoch=1,params.max_epochs do
    local tr_table = params.training_table
    if type(tr_table) == "function" then tr_table = tr_table() end
    collectgarbage("collect")
    local tr_err         = self:train_dataset(tr_table)
    local tr_improvement = (prev_tr_err - tr_err)/prev_tr_err
    if (epoch > params.min_epochs and
	tr_improvement < params.percentage_stopping_criterion) then
      break
    end
    best = self:clone()
    params.update_function{ current_epoch     = epoch,
			    train_error       = tr_err,
			    train_improvement = tr_improvement,
			    train_params      = params }
    prev_tr_err = tr_err
  end
  return best
end

-------------------------
-- STOPPING CRITERIA --
-------------------------
april_set_doc("trainable.stopping_criteria", {
		class       = "namespace",
		summary     = "Table with built-in stopping criteria", })

trainable.stopping_criteria = trainable.stopping_criteria or {}

--------------------------------------------------------------------------

april_set_doc("trainable.stopping_criteria.make_max_epochs_wo_imp_absolute", {
		class       = "function",
		summary     = "Returns a stopping criterion based on absolute loss.",
		description = 
		  {
		    "This function returns a stopping criterion function",
		    "which returns is true if current_epoch - best_epoch >= abs_max."
		  }, 
		params = { "Absolute maximum difference (abs_max)" },
		outputs = { "A stopping criterion function" }, })

function trainable.stopping_criteria.make_max_epochs_wo_imp_absolute(abs_max)
  local f = function(params)
    return (params.current_epoch - params.best_epoch) >= abs_max
  end
  return f
end

--------------------------------------------------------------------------

april_set_doc("trainable.stopping_criteria.make_max_epochs_wo_imp_relative", {
		class       = "function",
		summary     = "Returns a stopping criterion based on relative loss.",
		description = 
		  {
		    "This function returns a stopping criterion function",
		    "which returns is true if not",
		    "current_epoch/best_epoch < rel_max."
		  }, 
		params = { "Relative maximum difference (rel_max)" },
		outputs = { "A stopping criterion function" }, })

function trainable.stopping_criteria.make_max_epochs_wo_imp_relative(rel_max)
  local f = function(params)
    return not (params.current_epoch/params.best_epoch < rel_max)
  end
  return f
end
