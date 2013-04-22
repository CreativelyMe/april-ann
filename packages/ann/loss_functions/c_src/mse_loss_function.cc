/*
 * This file is part of the Neural Network modules of the APRIL toolkit (A
 * Pattern Recognizer In Lua).
 *
 * Copyright 2012, Salvador España-Boquera, Adrian Palacios, Francisco Zamora-Martinez
 *
 * The APRIL-ANN toolkit is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3 as
 * published by the Free Software Foundation
 *
 * This library is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
 * for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 *
 */
#include "token_memory_block.h"
#include "mse_loss_function.h"
#include "wrapper.h"

namespace ANN {

  MSELossFunction::MSELossFunction(unsigned int size) :
    LossFunction(size), accumulated_loss(0.0f) {
    error_mem_block = new TokenMemoryBlock(size);
    error_output    = error_mem_block;
    IncRef(error_output);
  }
  
  MSELossFunction::~MSELossFunction() {
    DecRef(error_output);
  }
  
  float MSELossFunction::addLoss(Token *_input, Token *target) {
    if (_input->getTokenCode() != table_of_token_codes::token_mem_block)
      ERROR_EXIT(128, "Incorrect input token type, expected memory block\n");
    if (target->getTokenCode() != table_of_token_codes::token_mem_block)
      ERROR_EXIT(128, "Incorrect target token type, expected memory block\n");
    //
    if (input != 0) DecRef(input);
    input = _input;
    IncRef(input);
    TokenMemoryBlock *input_mem_token = input->convertTo<TokenMemoryBlock*>();
    TokenMemoryBlock *target_mem_block = target->convertTo<TokenMemoryBlock*>();
    if (input_mem_token->getUsedSize() != target_mem_block->getUsedSize())
      ERROR_EXIT(128, "Different token sizes found\n");
    //
    unsigned int bunch_size = input_mem_token->getUsedSize() / size;
    float loss = doMSELossFunction(input_mem_token->getMemBlock(),
				   target_mem_block->getMemBlock(),
				   0.0f, size, bunch_size,
				   input_mem_token->getCudaFlag());
    loss *= 0.5f/bunch_size;
    accumulated_loss += loss;
    return loss;
  }

  Token *MSELossFunction::computeGrandient(Token *_input, Token *target) {
    if (_input->getTokenCode() != table_of_token_codes::token_mem_block)
      ERROR_EXIT(128, "Incorrect token type, expected memory block\n");
    if (target->getTokenCode() != table_of_token_codes::token_mem_block)
      ERROR_EXIT(128, "Incorrect target token type, expected memory block\n");
    //
    if (input != _input) {
      if (input != 0) DecRef(input);
      input = _input;
      IncRef(input);
    }
    TokenMemoryBlock *input_mem_token  = input->convertTo<TokenMemoryBlock*>();
    TokenMemoryBlock *target_mem_block = target->convertTo<TokenMemoryBlock*>();
    if (input_mem_token->getUsedSize() != target_mem_block->getUsedSize())
      ERROR_EXIT(128, "Different token sizes found\n");
    //
    unsigned int bunch_size = input_mem_token->getUsedSize() / size;
    error_mem_block->resize(bunch_size);
    doAccumulateMSEGradient(input_mem_token->getMemBlock(),
			    target_mem_block->getMemBlock(),
			    error_mem_block->getMemBlock(),
			    0.0f, size, bunch_size,
			    input_mem_token->getCudaFlag());
    return error_output;
  }
  
  float MSELossFunction::getAccumLoss() {
    return accumulated_loss;
  }
   
  void MSELossFunction::reset() {
    accumulated_loss = 0.0f;
    doVectorSetToZero(error_mem_block->getMemBlock(),
		      error_mem_block->getMaxSize(),
		      1, 0, error_mem_block->getCudaFlag());
  }
}
