/*
 * This file is part of APRIL-ANN toolkit (A
 * Pattern Recognizer In Lua with Artificial Neural Networks).
 *
 * Copyright 2013, Francisco Zamora-Martinez
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
#ifndef LOSSFUNCTION_H
#define LOSSFUNCTION_H

#include "referenced.h"
#include "token_base.h"
#include "token_memory_block.h"
#include "error_print.h"

namespace ANN {
  /// An abstract class that defines the basic interface that
  /// the loss_functions must complain.
  class LossFunction : public Referenced {
  protected:
    Token *error_output;
    unsigned int size;
  public:
    LossFunction(unsigned int size) :
    Referenced(), error_output(0), size(size) {
      if (size == 0)
	ERROR_EXIT(128, "Impossible to build ZERO size LossFunction\n");
    }
    virtual ~LossFunction() {
      if (error_output) DecRef(error_output);
    }
    virtual float  addLoss(Token *input, Token *target) = 0;
    virtual Token *computeGradient(Token *input, Token *target) = 0;
    virtual float  getAccumLoss() = 0;
    virtual void   reset() {
      if (error_output) DecRef(error_output);
      error_output = 0;
    }
    virtual LossFunction *clone() = 0;
  };
}

#endif // LOSSFUNCTION_H
