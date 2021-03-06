/*
 * This file is part of APRIL-ANN toolkit (A
 * Pattern Recognizer In Lua with Artificial Neural Networks).
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
#include "mae_loss_function.h"
#include "wrapper.h"

namespace ANN {

  MAELossFunction::MAELossFunction(unsigned int size) :
    LossFunction(size), accumulated_loss(0.0f), N(0) {
  }
  
  MAELossFunction::~MAELossFunction() {
  }
  
  float MAELossFunction::addLoss(Token *input, Token *target) {
    if (input->getTokenCode() != table_of_token_codes::token_mem_block)
      ERROR_EXIT(128, "Incorrect input token type, expected memory block\n");
    if (target->getTokenCode() != table_of_token_codes::token_mem_block)
      ERROR_EXIT(128, "Incorrect target token type, expected memory block\n");
    //
    TokenMemoryBlock *input_mem_token = input->convertTo<TokenMemoryBlock*>();
    TokenMemoryBlock *target_mem_block = target->convertTo<TokenMemoryBlock*>();
    if (input_mem_token->getUsedSize() != target_mem_block->getUsedSize())
      ERROR_EXIT(128, "Different token sizes found\n");
    //
    unsigned int bunch_size = input_mem_token->getUsedSize() / size;
    float loss = doMAELossFunction(input_mem_token->getMemBlock(),
				   target_mem_block->getMemBlock(),
				   0.0f, size, bunch_size,
				   input_mem_token->getCudaFlag());
    loss = loss/bunch_size;
    accumulated_loss += loss;
    ++N;
    return loss;
  }

  Token *MAELossFunction::computeGradient(Token *input, Token *target) {
    if (input->getTokenCode() != table_of_token_codes::token_mem_block)
      ERROR_EXIT(128, "Incorrect token type, expected memory block\n");
    if (target->getTokenCode() != table_of_token_codes::token_mem_block)
      ERROR_EXIT(128, "Incorrect target token type, expected memory block\n");
    //
    TokenMemoryBlock *input_mem_token  = input->convertTo<TokenMemoryBlock*>();
    TokenMemoryBlock *target_mem_block = target->convertTo<TokenMemoryBlock*>();
    if (input_mem_token->getUsedSize() != target_mem_block->getUsedSize())
      ERROR_EXIT2(128, "Different token sizes found, input=%d  target=%d\n",
		  input_mem_token->getUsedSize(),
		  target_mem_block->getUsedSize());
    //
    unsigned int bunch_size = input_mem_token->getUsedSize() / size;
    TokenMemoryBlock *error_mem_block;
    error_mem_block = new TokenMemoryBlock(input_mem_token->getUsedSize());
    AssignRef(error_output, error_mem_block);
    doComputeMAEGradient(input_mem_token->getMemBlock(),
			 target_mem_block->getMemBlock(),
			 error_mem_block->getMemBlock(),
			 NEAR_ZERO, size, bunch_size,
			 input_mem_token->getCudaFlag());
    return error_output;
  }
  
  float MAELossFunction::getAccumLoss() {
    return accumulated_loss/N;
  }
   
  void MAELossFunction::reset() {
    LossFunction::reset();
    accumulated_loss = 0.0f;
    N = 0;
  }
}
