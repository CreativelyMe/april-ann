ann.autoencoders = ann.autoencoders or {}

-- AUXILIAR LOCAL FUNCTIONS --

-- This function builds a codifier from the weights of the first layer of a
-- restricted autoencoder
local function build_two_layered_codifier_from_weights(bunch_size,
						       input_size,
						       input_actf,
						       cod_size,
						       cod_actf,
						       bias_mat,weights_mat)
  local codifier = ann.mlp{ bunch_size = bunch_size }
  local input_layer  = ann.units.real_cod{ ann  = codifier,
					   size = input_size,
					   type = "inputs" }
  local cod_layer = ann.units.real_cod{ ann  = codifier,
					size = cod_size,
					type = "outputs" }
  local cod_bias  = ann.connections.bias{ ann  = codifier,
					  size = cod_size }
  cod_bias:load{ w=bias_mat }
  local cod_weights = ann.connections.all_all{ ann         = codifier,
					       input_size  = input_size,
					       output_size = cod_size }
  cod_weights:load{ w=weights_mat }
  -- 
  codifier:push_back_all_all_layer{
    input   = input_layer,
    output  = cod_layer,
    bias    = cod_bias,
    weights = cod_weights,
    actfunc = cod_actf }
  return codifier
end

-- This function builds an autoencoder of two layers (input-hidden-output) where
-- the hidden-output uses the same weights as input-hidden, so it is
-- simetric.
local function build_two_layered_autoencoder_from_sizes_and_actf(bunch_size,
								 input_size,
								 input_actf,
								 cod_size,
								 cod_actf,
								 weights_random)
  local autoencoder  = ann.mlp{ bunch_size = bunch_size }
  local input_layer  = ann.units.real_cod{ ann  = autoencoder,
					   size = input_size,
					   type = "inputs" }
  local hidden_layer = ann.units.real_cod{ ann  = autoencoder,
					   size = cod_size,
					   type = "hidden" }
  local output_layer = ann.units.real_cod{ ann  = autoencoder,
					   size = input_size,
					   type = "outputs" }
  -- first layer
  autoencoder:push_back_all_all_layer{
    input   = input_layer,
    output  = hidden_layer,
    actfunc = cod_actf }
  -- the connections layer (1) is a bias object, (2) is the an all_all object
  local hidden_weights = autoencoder:get_layer_connections(2)
  -- second layer (weights transposed)
  autoencoder:push_back_all_all_layer{
    input     = hidden_layer,
    output    = output_layer,
    weights   = hidden_weights,
    transpose = true,
    actfunc   = input_actf }
  -- randomize weights
  autoencoder:randomize_weights{ random=weights_random,
				 inf=-1,
				 sup= 1,
				 use_fanin = true}
  return autoencoder
end

-- Generate the data table for training a two-layered auto-encoder
local function generate_training_table_configuration_from_params(current_dataset_params,
								 params,
								 noise)
  local data = {}
  if current_dataset_params.input_dataset then
    data.input_dataset  = current_dataset_params.input_dataset
    data.output_dataset = current_dataset_params.input_dataset
    if noise then
      -- The input is perturbed with gaussian noise
      if params.var > 0.0 then
	data.input_dataset = dataset.perturbation{
	  dataset  = data.input_dataset,
	  mean     = 0,
	  variance = params.var,
	  random   = params.perturbation_random }
      end
      if params.salt_noise_percentage > 0.0 then
	data.input_dataset = dataset.salt_noise{
	  dataset = data.input_dataset,
	  vd = params.salt_noise_percentage, -- 10%
	  zero = 0.0,
	  random = params.perturbation_random }
      end
    end
  end -- if params.input_dataset
  if current_dataset_params.distribution then
    data.distribution = {}
    for _,v in ipairs(current_dataset_params.distribution) do
      local ds = v.input_dataset
      if noise then
	-- The input is perturbed with gaussian noise
	if params.var > 0.0 then
	  data.input_dataset = dataset.perturbation{
	    dataset  = data.input_dataset,
	    mean     = 0,
	    variance = params.var,
	    random   = params.perturbation_random }
	end
	if params.salt_noise_percentage > 0.0 then
	  data.input_dataset = dataset.salt_noise{
	    dataset = data.input_dataset,
	    vd = params.salt_noise_percentage, -- 10%
	    zero = 0.0,
	    random = params.perturbation_random }
	end
      end
      table.insert(data.distribution, {
		     input_dataset = ds,
		     probability   = v.prob })
    end -- for _,v in ipairs(params.distribution)
  end -- if params.distribution
  data.shuffle     = params.shuffle_random
  data.replacement = params.replacement
  return data
end

-- PUBLIC FUNCTIONS --

-- This functions receives layer sizes and sdae_table with weights and bias
-- arrays. It returns a fully connected stacked denoising autoencoder ANN.
function ann.autoencoders.build_full_autoencoder(bunch_size,
						 layers,
						 sdae_table)
  local weights_mat = sdae_table.weights
  local bias_mat    = sdae_table.bias
  local sdae = ann.mlp{ bunch_size = bunch_size }
  local neuron_layers = {}
  local actfs         = {}
  local weights_sdae  = {}
  local bias_sdae     = {}
  table.insert(neuron_layers, ann.units.real_cod{
		 ann  = sdae,
		 size = layers[1].size,
		 type = "inputs" })
  for i=2,#layers do
    table.insert(neuron_layers, ann.units.real_cod{
		   ann  = sdae,
		   size = layers[i].size,
		   type = "hidden" })
    table.insert(actfs, ann.activations.from_string(layers[i].actf))
    table.insert(bias_sdae, ann.connections.bias{
		   ann  = sdae,
		   size = layers[i].size,
		   w    = bias_mat[i-1][1] })
    table.insert(weights_sdae, ann.connections.all_all{
		   ann = sdae,
		   input_size  = layers[i-1].size,
		   output_size = layers[i].size,
		   w           = weights_mat[i-1] })
    sdae:push_back_all_all_layer{ input   = neuron_layers[#neuron_layers-1],
				  output  = neuron_layers[#neuron_layers],
				  weights = weights_sdae[#weights_sdae],
				  bias    = bias_sdae[#bias_sdae],
				  actfunc = actfs[#actfs] }
  end
  for i=#layers-1,1,-1 do
    table.insert(neuron_layers, ann.units.real_cod{
		   ann  = sdae,
		   size = layers[i].size,
		   type = (i>1 and "hidden") or "outputs" })
    table.insert(actfs, ann.activations.from_string(layers[i].actf))
    table.insert(bias_sdae, ann.connections.bias{
		   ann  = sdae,
		   size = layers[i].size,
		   w    = bias_mat[i][2] })
    sdae:push_back_all_all_layer{ input     = neuron_layers[#neuron_layers-1],
				  output    = neuron_layers[#neuron_layers],
				  weights   = weights_sdae[i],
				  bias      = bias_sdae[#bias_sdae],
				  actfunc   = actfs[#actfs],
				  transpose = true }
  end
  return sdae
end

-- Params is a table which could contain:
--   * input_dataset => dataset with input (and output) for AE
--   * val_input_dataset => for validation
--   * distribution => a table which contains a list of {input_dataset=...., prob=....}
--   * replacement => replacement value for training
--   * shuffle_random => random number generator
--   * weights_random => random number generator
--   * perturbation_random => random number generator
--   * var => variance of gaussian noise
--   * layers => table which contains a list of { size=...., actf=....}, being
--               size a number and actf a string = "logistic"|"tanh"|"linear"
--   * bunch_size => size of mini-batch
--   * learning_rate
--   * momentum
--   * weight_decay
--   * max_epochs
--   * max_epochs_wo_improvement
--   * training_percentage_criteria
--
-- This function returns a Stacked Denoising Auto-Encoder parameters table,
-- pretrained following algorithm of:
--
-- [CITE]
--
-- If you train an auto-encoder for a topology of 256 128 64
-- the WHOLE auto-encoder will had this topology:
-- 256 - 128 - 64 - 128 - 256
-- So it has four layers: (1) 256-128, (2) 128-64, (3) 64-128, (4) 128-256
--
-- Two arrays store weights and bias, in this order:
-- bias[1] => 128      bias of layer (1)
-- bias[2] =>  64      bias of layer (2)
-- bias[3] => 128      bias of layer (3)
-- bias[4] => 256      bias of layer (4)
-- weights[1] => 256*128  weights of layer (1)
-- weights[2] => 128*64   weights of layer (2)
function ann.autoencoders.stacked_denoising_pretraining(params)
  local check_mandatory_param = function(params, name)
    if not params[name] then error ("Parameter " .. name .. " is mandatory") end
  end
  local valid_params = table.invert{ "shuffle_random", "distribution",
				     "perturbation_random", "replacement",
				     "var", "layers", "bunch_size",
				     "learning_rate",
				     "max_epochs", "max_epochs_wo_improvement",
				     "momentum", "weight_decay", "val_input_dataset",
				     "weights_random", "salt_noise_percentage",
				     "training_percentage_criteria" }
  for name,v in pairs(valid_params) do
    if not valid_params[name] then
      error("Incorrect param name '"..name.."'")
    end
  end
  -- Error checking in params table --
  if params.input_dataset and params.distribution then
    error("The input_dataset and distribution parameters are forbidden together")
  end
  if params.distribution and not params.replacement then
    error("The replacement parameter is mandatary if distribution")
  end
  for _,name in ipairs({ "shuffle_random", "perturbation_random",
			 "var", "layers", "bunch_size", "learning_rate",
			 "max_epochs",
			 "momentum", "weight_decay",
			 "weights_random", "salt_noise_percentage",
			 "training_percentage_criteria" }) do
    check_mandatory_param(params, name)
  end
  if params.val_input_dataset then
    if not params.max_epochs_wo_improvement then
      error ("max_epochs_wo_improvement is mandatory with val_input_dataset")
    end
  else
    if not params.training_percentage_criteria then
      error ("training_percentage_criteria is mandatory if not val_input_dataset")
    end
  end
  --------------------------------------

  -- copy dataset params to auxiliar table
  local current_dataset_params = {
    input_dataset = params.input_dataset,
    distribution  = params.distribution
  }
  local current_val_dataset_params
  if params.val_input_dataset then
    current_val_dataset_params = {
      input_dataset  = params.val_input_dataset,
      output_dataset = params.val_input_dataset
    }
  end
  -- output weights and bias matrices
  local weights = {}
  local bias    = {}
  -- loop for each pair of layers
  for i=2,#params.layers do
    local input_size = params.layers[i-1].size
    local cod_size   = params.layers[i].size
    printf("# Training of layer %d--%d--%d (number %d)\n",
	   input_size, cod_size, input_size, i-1)
    local input_actf = ann.activations.from_string(params.layers[i-1].actf)
    local cod_actf   = ann.activations.from_string(params.layers[i].actf)
    local val_data = current_val_dataset_params
    local data
    data = generate_training_table_configuration_from_params(current_dataset_params,
							     params,
							     i==2)
    local dae
    dae = build_two_layered_autoencoder_from_sizes_and_actf(params.bunch_size,
							    input_size,
							    input_actf,
							    cod_size,
							    cod_actf,
							    params.weights_random)
    dae:set_option("learning_rate", params.learning_rate)
    dae:set_option("momentum", params.momentum)
    dae:set_option("weight_decay", params.weight_decay)
    collectgarbage("collect")
    if (params.layers[i-1].actf == "logistic" or
	params.layer[i-1].actf == "softmax") then
      dae:set_error_function(ann.error_functions.full_logistic_cross_entropy())
    else
      dae:set_error_function(ann.error_functions.mse())
    end
    local best_val_error = 111111111
    local best_net       = dae:clone()
    local best_epoch     = 0
    local prev_train_err = 111111111
    for epoch=1,params.max_epochs do
      local train_error = dae:train_dataset(data)
      local val_error   = 0
      if val_data then
	dae:validate_dataset(val_data)
      end
      local train_improve = (prev_train_err - train_error)/prev_train_err
      if params.training_percentage_criteria then
	if train_improve < params.training_percentage_criteria then break end
      end
      prev_train_err = train_error
      if val_error < best_val_error then
	best_val_error = val_error
	best_epoch     = epoch
	best_net       = dae:clone()
      end
      printf("%4d %10.6f %10.6f  (best %10.6f at epoch %4d)  %.4f\n",
	     epoch, train_error, val_error, best_val_error, best_epoch,
	    train_improve)
      collectgarbage("collect")
      -- convergence criteria
      if params.val_input_dataset then
	if epoch - best_epoch > params.max_epochs_wo_improvement then break end
      else best_val_error = 111111111
      end
    end
    local b1mat = best_net:get_layer_connections(1):weights()
    local b2mat = best_net:get_layer_connections(3):weights()
    local wmat  = best_net:get_layer_connections(2):weights()
    table.insert(weights, wmat)
    table.insert(bias, { b1mat, b2mat })
    if i ~= #params.layers then
      -- generation of new input patterns using only the first part of
      -- autoencoder except at last loop iteration
      local codifier
      codifier = build_two_layered_codifier_from_weights(params.bunch_size,
							 input_size,
							 input_actf,
							 cod_size,
							 cod_actf,
							 b1mat, wmat)
      -- auxiliar function
      local generate_codification = function(codifier, ds)
	local output_mat = matrix(ds:numPatterns(), cod_size)
	local output_ds  = dataset.matrix(output_mat)
	codifier:use_dataset{ input_dataset = ds, output_dataset = output_ds }
	return output_ds
      end
      if current_dataset_params.distribution then
	-- compute code for each distribution dataset
	for _,v in ipairs(current_dataset_params.distribution) do
	  v.input_dataset = generate_codification(codifier, v.input_dataset)
	end
      else
	-- compute code for input dataset
	local ds = generate_codification(codifier,
					 current_dataset_params.input_dataset)
	current_dataset_params.input_dataset = ds
      end
      if current_val_dataset_params then
	-- compute code for validation input dataset
	local ds = generate_codification(codifier,
					 current_val_dataset_params.input_dataset)
	current_val_dataset_params.input_dataset  = ds
	current_val_dataset_params.output_dataset = ds
      end
    end -- if i ~= params.layers
  end -- for i=2,#params.layers
  return {weights=weights, bias=bias}
end



-- Receive an autoencoder table with bias and weights, pretrained with previous
-- function
function ann.autoencoders.stacked_denoising_finetunning(sdae_table, params)
  local check_mandatory_param = function(params, name)
    if not params[name] then error ("Parameter " .. name .. " is mandatory") end
  end
  local valid_params = table.invert{ "shuffle_random", "distribution",
				     "perturbation_random", "replacement",
				     "var", "layers", "bunch_size",
				     "learning_rate",
				     "max_epochs", "max_epochs_wo_improvement",
				     "momentum", "weight_decay",
				     "val_input_dataset",
				     "training_percentage_criteria",
				     "weights_random", "salt_noise_percentage"}
  for name,v in pairs(valid_params) do
    if not valid_params[name] then
      error("Incorrect param name '"..name.."'")
    end
  end
  -- Error checking in params table --
  if params.input_dataset and params.distribution then
    error("The input_dataset and distribution parameters are forbidden together")
  end
  if params.distribution and not params.replacement then
    error("The replacement parameter is mandatary if distribution")
  end
  for _,name in ipairs({ "shuffle_random", "perturbation_random",
			 "var", "layers", "bunch_size", "learning_rate",
			 "max_epochs", "max_epochs_wo_improvement",
			 "momentum", "weight_decay", "val_input_dataset",
			 "weights_random", "salt_noise_percentage"}) do
    check_mandatory_param(params, name)
  end
  --------------------------------------
  -- FINETUNING
  print("# Begining of fine-tuning")
  local sdae = ann.autoencoders.build_full_autoencoder(params.bunch_size,
						       params.layers,
						       sdae_table)
  sdae:set_option("learning_rate", params.learning_rate)
  sdae:set_option("momentum", params.momentum)
  sdae:set_option("weight_decay", params.weight_decay)
  if (params.layers[1].actf == "logistic" or
      params.layers[1].actf == "softmax") then
    sdae:set_error_function(ann.error_functions.full_logistic_cross_entropy())
  else
    sdae:set_error_function(ann.error_functions.mse())
  end
  collectgarbage("collect")
  local data
  data = generate_training_table_configuration_from_params(params,
							   params,
							   true)
  local val_data = { input_dataset  = params.val_input_dataset,
		     output_dataset = params.val_input_dataset }
  local best_val_error = 111111111
  local best_net       = sdae:clone()
  local best_epoch     = 0
  for epoch=1,params.max_epochs do
    local train_error = sdae:train_dataset(data)
    local val_error   = sdae:validate_dataset(val_data)
    if val_error < best_val_error then
      best_val_error = val_error
      best_epoch     = epoch
      best_net       = sdae:clone()
    end
    printf("%4d %10.6f %10.6f  (best %10.6f at epoch %4d)\n",
	   epoch, train_error, val_error, best_val_error, best_epoch)
    collectgarbage("collect")
    -- convergence criteria
    if epoch - best_epoch > params.max_epochs_wo_improvement then break end
  end
  return best_net
end

-- This function returns a MLP formed by the codification part of a full stacked
-- auto encoder
function ann.autoencoders.build_codifier_from_sdae_table(sdae_table,
							 bunch_size,
							 layers)
  local weights_mat   = sdae_table.weights
  local bias_mat      = sdae_table.bias
  local codifier_net  = ann.mlp{ bunch_size = bunch_size }
  local neuron_layers = {}
  local actfs         = {}
  local weights_codifier_net  = {}
  local bias_codifier_net     = {}
  table.insert(neuron_layers, ann.units.real_cod{
		 ann  = codifier_net,
		 size = layers[1].size,
		 type = "inputs" })
  for i=2,#layers do
    table.insert(neuron_layers, ann.units.real_cod{
		   ann  = codifier_net,
		   size = layers[i].size,
		   type = ((i < #layers and "hidden") or "outputs") })
    table.insert(actfs, ann.activations.from_string(layers[i].actf))
    table.insert(bias_codifier_net, ann.connections.bias{
		   ann  = codifier_net,
		   size = layers[i].size,
		   w    = bias_mat[i-1][1] })
    table.insert(weights_codifier_net, ann.connections.all_all{
		   ann = codifier_net,
		   input_size  = layers[i-1].size,
		   output_size = layers[i].size,
		   w           = weights_mat[i-1] })
    codifier_net:push_back_all_all_layer{
      input   = neuron_layers[#neuron_layers-1],
      output  = neuron_layers[#neuron_layers],
      bias    = bias_codifier_net[#bias_codifier_net],
      weights = weights_codifier_net[#weights_codifier_net],
      actfunc = actfs[#actfs] }
  end
  return codifier_net
end

-- This function returns a MLP formed by the codification part of a full stacked
-- auto encoder
function ann.autoencoders.build_codifier_from_sdae(sdae, bunch_size, layers)
  local sdae_connections = sdae:get_layer_connections_vector()
  local sdae_activations = sdae:get_layer_activations_vector()
  local codifier_net = ann.mlp{ bunch_size = bunch_size }
  local codifier_connections = {}
  local codifier_activations = {}
  for i=1,(#layers-1)*2 do
    table.insert(codifier_connections, sdae_connections[i]:clone(codifier_net))
  end
  local type = "inputs"
  for i=1,#layers-1 do
    table.insert(codifier_activations, sdae_activations[i]:clone(codifier_net,
								 type))
    type = "hidden"
  end
  table.insert(codifier_activations, sdae_activations[#layers]:clone(codifier_net,
								     "outputs"))
  local k=1
  for i=2,#layers do
    local actf    = ann.activations.from_string(layers[i].actf)
    local input   = codifier_activations[i-1]
    local output  = codifier_activations[i]
    local bias    = codifier_connections[k]
    local weights = codifier_connections[k+1]
    codifier_net:push_back_all_all_layer{
      input   = input,
      output  = output,
      bias    = bias,
      weights = weights,
      actfunc = actf }
    k = k + 2
  end
  return codifier_net
end

-- Returns a dataset with the codification of input dataset patterns  
function ann.autoencoders.compute_encoded_dataset_using_codifier(codifier_net,
								 input_dataset)
  local output_dataset = dataset.matrix(matrix(input_dataset:numPatterns(),
					       codifier_net:get_output_size()))
  codifier_net:use_dataset{ input_dataset  = input_dataset,
			    output_dataset = output_dataset }
  return output_dataset
end
