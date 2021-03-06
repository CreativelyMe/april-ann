/*
 * This file is part of the Neural Network modules of the APRIL toolkit (A
 * Pattern Recognizer In Lua).
 *
 * Copyright 2012, Salvador España-Boquera, Adrian Palacios Corella, Francisco
 * Zamora-Martinez
 *
 * The APRIL-MLP toolkit is free software; you can redistribute it and/or modify it
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
#include <cmath>
#include "clamp.h"
#include "error_print.h"
#include "wrapper.h"

using april_utils::clamp;

#define clip(value, min, max) (((value) < (min)) ? (min) : (((value) > (max)) ? (max) : (value)))

///////////////////////////////////////////////////////////
/////////////////// Kernels ///////////////////////////////
///////////////////////////////////////////////////////////

#ifdef USE_CUDA
#include "cuda_utils.h"
__global__ void computeMSELossFunctionKernel(const float *output,
					     const float *target_output,
					     float *pattern_errors,
					     float zero_epsilon_distance,
					     unsigned int max_x,
					     unsigned int lda_x,
					     unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    float d = output[index] - target_output[index];
    if (fabsf(d) < zero_epsilon_distance) d = 0.0f;
    pattern_errors[index] = d*d;
  }
}

__global__ void computeMSEGradientKernel(const float *output,
					 const float *target_output,
					 float *error_output,
					 float zero_epsilon_distance,
					 unsigned int max_x,
					 unsigned int lda_x,
					 unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    float d = output[index] - target_output[index];
    if (fabsf(d) < zero_epsilon_distance) d = 0.0f;
    error_output[index] = d;
  }
}

__global__ void computeMAELossFunctionKernel(const float *output,
					     const float *target_output,
					     float *pattern_errors,
					     float zero_epsilon_distance,
					     unsigned int max_x,
					     unsigned int lda_x,
					     unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    float absd = fabsf(output[index] - target_output[index]);
    if (absd < zero_epsilon_distance) absd = 0.0f;
    pattern_errors[index] = absd / max_y;
  }
}

__global__ void computeMAEGradientKernel(const float *output,
					 const float *target_output,
					 float *error_output,
					 float zero_epsilon_distance,
					 unsigned int max_x,
					 unsigned int lda_x,
					 unsigned int max_y,
					 float invN) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    float d = output[index] - target_output[index];
    if (fabsf(d) < zero_epsilon_distance) error_output[index] = 0.0f;
    else {
      if (d < 0.0f) error_output_ptr[index] = -invN;
      else error_output_ptr[index] = invN;
    }
  }
}

__global__ void computeMultiClassCrossEntropyLossFunctionKernel(const float *output,
								const float *target_output,
								float *pattern_errors,
								float epsilon,
								unsigned int max_x,
								unsigned int lda_x,
								unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    // compute derivative
    // float o = clip(output[index], inf, epsilon, 1.0f - epsilon);
    float log_o = output[index];
    float t = clip(target_output[index], epsilon, 1.0f - epsilon);
    if (t > epsilon) pattern_errors[index] += t * log_o;
  }
}

__global__ void computeCrossEntropyLossFunctionKernel(const float *output,
						      const float *target_output,
						      float *pattern_errors,
						      float epsilon,
						      unsigned int max_x,
						      unsigned int lda_x,
						      unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    // compute derivative
    float  log_o     = output[index];
    double o         = exp(output[index]);
    float  log_inv_o = (o<1.0) ? log(1.0 - o) : log(epsilon);
    float  t         = clip(target_output[index], epsilon, 1.0f - epsilon);
    float  inv_t     = clip(1.0f - target_output[index], epsilon, 1.0f - epsilon);
    if (t > epsilon) pattern_errors[index] += t * log_o;
    if (inv_t > epsilon) pattern_errors[index] += inv_t * log_inv_o;
  }
}

__global__ void computeCrossEntropyGradientKernel(const float *output,
						  const float *target_output,
						  float *error_output,
						  float zero,
						  unsigned int max_x,
						  unsigned int lda_x,
						  unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    // compute derivative
    error_output[index] = expf(output[index]) - target_output[index];
  }
}

__global__ void applyTanhErrorFunctionKernel(const float *output,
					     const float *target_output,
					     float *output_error,
					     float *pattern_errors,
					     unsigned int max_x,
					     unsigned int lda_x,
					     unsigned int max_y) {
  unsigned int matrix_x_pos, matrix_y_pos;
  getColumnMajorBunchMatrixPositions(blockIdx,
				     blockDim,
				     threadIdx,
				     matrix_x_pos,
				     matrix_y_pos);
  if (matrix_x_pos < max_x && matrix_y_pos < max_y) {
    unsigned int index = getMatrixFlatIndex(matrix_x_pos, lda_x, matrix_y_pos);
    float d = output_error[index] = output[index] - target_output[index];
    if (d < -0.9999999f)
      output_error[index] = -DERIVATIVE_SATURATION;
    else if (d > 0.9999999f)
      output_error[index] =  DERIVATIVE_SATURATION;
    else output_error[index] = log((1.0f+output_error[index])/(1.0f-output_error[index]));
    pattern_errors[index] += d*d;
  }
}

#endif


///////////////////////////////////////////////////////////
///////////////// Error functions wrappers ////////////////
///////////////////////////////////////////////////////////

float doMSELossFunction(FloatGPUMirroredMemoryBlock *input,
			FloatGPUMirroredMemoryBlock *target,
			float zero_epsilon_distance,
			unsigned int size,
			unsigned int bunch_size,
			bool use_gpu) {
#ifdef USE_CUDA
  if (use_gpu) {    
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    FloatGPUMirroredMemoryBlock *pattern_errors = 
      new FloatGPUMirroredMemoryBlock(target->getSize());
    float *pattern_errors_ptr = pattern_errors->getGPUForWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeMSELossFunctionKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       pattern_errors_ptr,
       zero_epsilon_distance,
       bunch_size,
       bunch_size,
       size);
    float sum = cublasSasum(pattern_errors->getSize(), pattern_errors_ptr, 1);
    delete pattern_errors;
    return sum;
  }
  else {
#endif
    float d = 0.0f, sum=0.0f;
    const float *input_ptr  = input->getPPALForRead();
    const float *target_ptr = target->getPPALForRead();
    for (unsigned int i = 0; i < size; i++) {
      for (unsigned int b=0; b<bunch_size; ++b) {
	d = input_ptr[b] - target_ptr[b];
	if (fabsf(d) < zero_epsilon_distance) d = 0.0f;
	sum += d*d;
      }
      input_ptr  += bunch_size;
      target_ptr += bunch_size;
    }
    return sum;
#ifdef USE_CUDA
  }
#endif
}


void doComputeMSEGradient(FloatGPUMirroredMemoryBlock *input,
			  FloatGPUMirroredMemoryBlock *target,
			  FloatGPUMirroredMemoryBlock *error_output,
			  float zero_epsilon_distance,
			  unsigned int size,
			  unsigned int bunch_size,
			  bool use_gpu) {
#ifdef USE_CUDA
  if (use_gpu) {    
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    float *error_output_ptr = error_output_ptr->getGPUForReadAndWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeMSEGradientKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       error_output_ptr,
       zero_epsilon_distance,
       bunch_size,
       bunch_size,
       size);
  }
  else {
#endif
    float d = 0.0f;
    const float *input_ptr  = input->getPPALForRead();
    const float *target_ptr = target->getPPALForRead();
    float *error_output_ptr = error_output->getPPALForReadAndWrite();
    for (unsigned int i = 0; i < size; i++) {
      for (unsigned int b=0; b<bunch_size; ++b) {
	d = input_ptr[b] - target_ptr[b];
	if (fabsf(d) < zero_epsilon_distance) d = 0.0f;
	error_output_ptr[b] = d;
      }
      input_ptr  += bunch_size;
      target_ptr += bunch_size;
      error_output_ptr += bunch_size;
    }
#ifdef USE_CUDA
  }
#endif
}

float doMAELossFunction(FloatGPUMirroredMemoryBlock *input,
			FloatGPUMirroredMemoryBlock *target,
			float zero_epsilon_distance,
			unsigned int size,
			unsigned int bunch_size,
			bool use_gpu) {
#ifdef USE_CUDA
  if (use_gpu) {    
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    FloatGPUMirroredMemoryBlock *pattern_errors = 
      new FloatGPUMirroredMemoryBlock(target->getSize());
    float *pattern_errors_ptr = pattern_errors->getGPUForWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeMAELossFunctionKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       pattern_errors_ptr,
       zero_epsilon_distance,
       bunch_size,
       bunch_size,
       size);
    float sum = cublasSasum(pattern_errors->getSize(), pattern_errors_ptr, 1);
    delete pattern_errors;
    return sum;
  }
  else {
#endif
    float absd = 0.0f, sum=0.0f;
    const float *input_ptr  = input->getPPALForRead();
    const float *target_ptr = target->getPPALForRead();
    for (unsigned int i = 0; i < size; i++) {
      float mae = 0.0f;
      for (unsigned int b=0; b<bunch_size; ++b) {
	absd = fabsf(input_ptr[b] - target_ptr[b]);
	if (absd < zero_epsilon_distance) absd = 0.0f;
	mae += absd;
      }
      sum += mae/size;
      input_ptr  += bunch_size;
      target_ptr += bunch_size;
    }
    return sum;
#ifdef USE_CUDA
  }
#endif
}


void doComputeMAEGradient(FloatGPUMirroredMemoryBlock *input,
			  FloatGPUMirroredMemoryBlock *target,
			  FloatGPUMirroredMemoryBlock *error_output,
			  float zero_epsilon_distance,
			  unsigned int size,
			  unsigned int bunch_size,
			  bool use_gpu) {
#ifdef USE_CUDA
  if (use_gpu) {    
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    float *error_output_ptr = error_output_ptr->getGPUForReadAndWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeMAEGradientKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       error_output_ptr,
       zero_epsilon_distance,
       bunch_size,
       bunch_size,
       size,
       1.0f/size);
  }
  else {
#endif
    float d = 0.0f, absd = 0.0f;
    const float *input_ptr  = input->getPPALForRead();
    const float *target_ptr = target->getPPALForRead();
    float *error_output_ptr = error_output->getPPALForReadAndWrite();
    float invN = 1.0f/size;
    for (unsigned int i = 0; i < size; i++) {
      for (unsigned int b=0; b<bunch_size; ++b) {
	d = input_ptr[b] - target_ptr[b];
	if (fabsf(d) < zero_epsilon_distance) error_output_ptr[b] = 0.0f;
	else {
	  if (d < 0.0f) error_output_ptr[b] = -invN;
	  else error_output_ptr[b] = invN;
	}
      }
      input_ptr  += bunch_size;
      target_ptr += bunch_size;
      error_output_ptr += bunch_size;
    }
#ifdef USE_CUDA
  }
#endif
}

float doCrossEntropyLossFunction(FloatGPUMirroredMemoryBlock *input,
				 FloatGPUMirroredMemoryBlock *target,
				 float EPSILON,
				 unsigned int size,
				 unsigned int bunch_size,
				 bool use_gpu) {
#ifdef USE_CUDA
  if (use_gpu) {    
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    FloatGPUMirroredMemoryBlock *pattern_errors = 
      new FloatGPUMirroredMemoryBlock(target->getSize());
    float *pattern_errors_ptr = pattern_errors->getGPUForWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeCrossEntropyLossFunctionKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       pattern_errors_ptr,
       EPSILON,
       bunch_size,
       bunch_size,
       size);
    float sum = cublasSasum(pattern_errors->getSize(), pattern_errors_ptr, 1);
    delete pattern_errors;
    return sum;
  }
  else {
#endif
    const float *input_ptr  = input->getPPALForRead();
    const float *target_ptr = target->getPPALForRead();
    float sum = 0.0f;
    for (unsigned int i = 0; i < size; i++) {
      for (unsigned int b=0; b<bunch_size; ++b) {
	assert(!(input_ptr[b] > 0.0f) &&
	       "Only log-based activation functions are allowed");
	assert(!(target_ptr[b] < 0.0f) && !(target_ptr[b] > 1.0f) &&
	       "Only [0,1] target patterns are allowed");
	// compute derivative
	float  log_o     = input_ptr[b];
	double o         = exp(input_ptr[b]);
	float  log_inv_o = (o<1.0) ? log(1.0 - o) : log(EPSILON);
	float  t         = clamp(target_ptr[b], EPSILON, 1.0f - EPSILON);
	float  inv_t     = clamp(1.0f - target_ptr[b], EPSILON, 1.0f - EPSILON);
	if (t > EPSILON)     sum += t * log_o;
	if (inv_t > EPSILON) sum += inv_t * log_inv_o;
      }
      input_ptr += bunch_size;
      target_ptr += bunch_size;
    }
    return sum;
#ifdef USE_CUDA
  }
#endif
}

float doMultiClassCrossEntropyLossFunction(FloatGPUMirroredMemoryBlock *input,
					   FloatGPUMirroredMemoryBlock *target,
					   float EPSILON,
					   unsigned int size,
					   unsigned int bunch_size,
					   bool use_gpu) {
#ifdef USE_CUDA
  if (use_gpu) {    
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    FloatGPUMirroredMemoryBlock *pattern_errors = 
      new FloatGPUMirroredMemoryBlock(target->getSize());
    float *pattern_errors_ptr = pattern_errors->getGPUForWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeMultiClassCrossEntropyLossFunctionKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       pattern_errors_ptr,
       EPSILON,
       bunch_size,
       bunch_size,
       size);
    float sum = cublasSasum(pattern_errors->getSize(), pattern_errors_ptr, 1);
    delete pattern_errors;
    return sum;
  }
  else {
#endif
    const float *input_ptr  = input->getPPALForRead();
    const float *target_ptr = target->getPPALForRead();
    float sum = 0.0f;
    for (unsigned int i = 0; i < size; i++) {
      for (unsigned int b=0; b<bunch_size; ++b) {
	assert(!(input_ptr[b] > 0.0f) &&
	       "Only log-based activation functions are allowed");
	assert(!(target_ptr[b] < 0.0f) && !(target_ptr[b] > 1.0f) &&
	       "Only [0,1] target patterns are allowed");
	// compute derivative
	float log_o = input_ptr[b];
	float t = clamp(target_ptr[b], EPSILON, 1.0f - EPSILON);
	if (t > EPSILON) sum += t * log_o;
      }
      input_ptr  += bunch_size;
      target_ptr += bunch_size;
    }
    return sum;
#ifdef USE_CUDA
  }
#endif
}

void doComputeCrossEntropyGradient(FloatGPUMirroredMemoryBlock *input,
				   FloatGPUMirroredMemoryBlock *target,
				   FloatGPUMirroredMemoryBlock *error_output,
				   float EPSILON,
				   unsigned int size,
				   unsigned int bunch_size,
				   bool use_gpu) {
#ifdef USE_CUDA
  if (use_gpu) {    
    const float *input_ptr  = input->getGPUForRead();
    const float *target_ptr = target->getGPUForRead();
    float *error_output_ptr = error_output_ptr->getGPUForReadAndWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(bunch_size, size,
						 block, grid);
    computeCrossEntropyGradientKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (input_ptr,
       target_ptr,
       error_output_ptr,
       EPSILON,
       bunch_size,
       bunch_size,
       size);
  }
  else {
#endif
    float d = 0, sum=0;
    const float *input_ptr  = input->getPPALForRead();
    const float *target_ptr = target->getPPALForRead();
    float *error_output_ptr = error_output->getPPALForReadAndWrite();
    for (unsigned int i = 0; i < size; i++) {
      for (unsigned int b=0; b<bunch_size; ++b)
	error_output_ptr[b] = expf(input_ptr[b]) - target_ptr[b];
      input_ptr  += bunch_size;
      target_ptr += bunch_size;
      error_output_ptr += bunch_size;
    }
#ifdef USE_CUDA
  }
#endif
}

/*
void doCalculateTanhErrorFunction(FloatGPUMirroredMemoryBlock *output,
				  FloatGPUMirroredMemoryBlock *target_output,
				  FloatGPUMirroredMemoryBlock *output_error,
				  FloatGPUMirroredMemoryBlock *pattern_errors,
				  unsigned int output_size,
				  const ANNConfiguration &conf,
				  bool use_gpu) {
#ifdef USE_CUDA
  if (use_gpu) {
    const float *output_ptr        = output->getGPUForRead();
    const float *target_output_ptr = target_output->getGPUForRead();
    float *output_error_ptr        = output_error->getGPUForWrite();
    float *pattern_errors_ptr      = pattern_errors->getGPUForReadAndWrite();
    dim3 block, grid;
    computeBlockAndGridSizesForAColumnMajorBunch(conf, output_size,
						 block, grid);
  
    applyTanhErrorFunctionKernel<<<grid, block, 0, GPUHelper::getCurrentStream()>>>
      (output_ptr,
       target_output_ptr,
       output_error_ptr,
       pattern_errors_ptr,
       conf.cur_bunch_size,
       conf.max_bunch_size,
       output_size);
  }
  else {
#endif
    float d = 0;
    const float *output_ptr        = output->getPPALForRead();
    const float *target_output_ptr = target_output->getPPALForRead();
    float *output_error_ptr        = output_error->getPPALForWrite();
    float *pattern_errors_ptr      = pattern_errors->getPPALForReadAndWrite();
    
    for (unsigned int i = 0; i < output_size; i++) {
      for (unsigned int b=0; b<conf.cur_bunch_size; ++b) {
        d = output_error_ptr[b] = output_ptr[b] - target_output_ptr[b];
        if (d < -0.9999999f)
          output_error_ptr[b] = -DERIVATIVE_SATURATION;
        else if (d > 0.9999999f)
          output_error_ptr[b] =  DERIVATIVE_SATURATION;
        else output_error_ptr[b] = log((1.0f+output_error_ptr[b])/(1.0f-output_error_ptr[b]));
	pattern_errors_ptr[b] += d*d;
      }
      output_ptr         += conf.max_bunch_size;
      target_output_ptr  += conf.max_bunch_size;
      output_error_ptr   += conf.max_bunch_size;
      pattern_errors_ptr += conf.max_bunch_size;
    }
#ifdef USE_CUDA
  }
#endif
}
*/

/*
  void doCalculateMixtureCrossEntropy(FloatGPUMirroredMemoryBlock *output,
  FloatGPUMirroredMemoryBlock *target_output,
  FloatGPUMirroredMemoryBlock *output_error,
  FloatGPUMirroredMemoryBlock *pattern_errors,
  float EPSILON,
  float INF,
  unsigned int output_size,
  const ANNConfiguration &conf,
  bool use_gpu) {
  const float *output_ptr        = output->getPPALForRead();
  const float *target_output_ptr = target_output->getPPALForRead();
  float *output_error_ptr        = output_error->getPPALForWrite();
  float *pattern_errors_ptr      = pattern_errors->getGPUForReadAndWrite();

  for (unsigned int b=0; b<conf.cur_bunch_size; ++b) {
  float Z = 0.0f;
  unsigned int ipos = b;
  for (unsigned int i=0; i<output_size; ++i)
  {
  Z += target_output_ptr[ipos] * output_ptr[ipos];
  ipos += conf.max_bunch_size;
  }
  Z = 1.0f/Z;
  float prob = 0.0f;
  ipos = b;
  for (unsigned int i = 0; i < output_size; i++) {
  float component_prob = target_output_ptr[ipos] * output_ptr[ipos];
  output_error_ptr[ipos] = output_ptr[ipos] - component_prob*Z;
  prob += component_prob;
  ipos += conf.max_bunch_size;
  }
  s += ((fabs(prob) > EPSILON) ? logf(prob) : INF);
  }
  return s;
  }
*/

// F(o,t) = (1 + beta^2) * sum o_i * t_i / sum( o_i + beta^2 * t_i )
// Gab = (1 + beta^2) sum o_i * t_i
// Hab = sum( o_i + beta^2 * t_i )
float doLocalFMeasureLossFunction(FloatGPUMirroredMemoryBlock *input,
				  FloatGPUMirroredMemoryBlock *target,
				  unsigned int size,
				  unsigned int bunch_size,
				  float beta,
				  float &Gab, float &Hab,
				  bool complement_output,
				  bool use_gpu) {
  if (use_gpu)   ERROR_EXIT(128, "GPU VERSION NOT IMPLEMENTED YET!!!\n");
  if (size != 1) ERROR_EXIT(128, "Multi-class version is not implemented\n");
  const float *input_ptr  = input->getPPALForRead();
  const float *target_ptr = target->getPPALForRead();
  FloatGPUMirroredMemoryBlock *pattern_errors = 
    new FloatGPUMirroredMemoryBlock(target->getSize());
  float *pattern_errors_ptr = pattern_errors->getPPALForReadAndWrite();
  Gab = 0.0f;
  Hab = 0.0f;
  float beta2 = beta*beta;
  for (unsigned int b=0; b<bunch_size; ++b) {
    unsigned int ipos = b;
    for (unsigned int i = 0; i < size; i++) {
      // float out = clamp(output_ptr[ipos], 0.0f, 1.0f);
      float in = input_ptr[ipos];
      assert(!(in < 0.0f) && !(in > 1.0f) &&
	     "Only [0,1] activation functions are allowed");
      if (!complement_output) {
	Gab += in * target_ptr[ipos];
	Hab += in + beta2 * target_ptr[ipos];
      }
      else {
	Gab += 1.0f + in * target_ptr[ipos] - in - target_ptr[ipos];
	Hab += 1.0f + beta2 - in - beta2 * target_ptr[ipos];
      }
      ipos += bunch_size;
    }
  }
  Gab = (1.0f + beta2)*Gab;
  // cambiamos de signo para convertir la minimizacion en una maximizacion
  float error;
  if (Hab > 0.0f)
    error = -Gab/Hab;
  else error = -1.0f;
  return error;
}

// F'(o,t) = (1 + beta^2)*t_i / Hab - Gab/Hab
void doComputeLocalFMeasureGradient(FloatGPUMirroredMemoryBlock *target,
				    FloatGPUMirroredMemoryBlock *output_error,
				    unsigned int size,
				    unsigned int bunch_size,
				    float beta,
				    float Gab, float Hab,
				    bool complement_output,
				    bool use_gpu) {
  if (use_gpu)   ERROR_EXIT(128, "GPU VERSION NOT IMPLEMENTED!!!\n");
  if (size != 1) ERROR_EXIT(128, "Multi-class version is not implemented\n");
  const float *target_ptr = target->getPPALForRead();
  float *output_error_ptr = output_error->getPPALForReadAndWrite();
  float beta2_p1  = 1.0f + beta*beta;
  if (Hab > 0.0f) {
    float inv_Hab     = 1.0f/Hab;
    float Gab_DIV_Hab2 = Gab*inv_Hab*inv_Hab;
    for (unsigned int b=0; b<bunch_size; ++b) {
      unsigned int ipos = b;
      for (unsigned int i = 0; i < size; i++) {
	float t = target_ptr[ipos];
	if (complement_output) t = 1.0f - t;
	output_error_ptr[ipos] = beta2_p1*t*inv_Hab - Gab_DIV_Hab2;
	ipos += bunch_size;
      }
    }
  }
}

/*
  float doCalculateGA(FloatGPUMirroredMemoryBlock *output,
  FloatGPUMirroredMemoryBlock *target_output,
  FloatGPUMirroredMemoryBlock *output_error,
  FloatGPUMirroredMemoryBlock *pattern_errors,
  unsigned int output_size,
  const ANNConfiguration &conf,
  bool use_gpu) {
  const float *output_ptr        = output->getPPALForRead();
  const float *target_output_ptr = target_output->getPPALForRead();
  float *output_error_ptr        = output_error->getPPALForWrite();

  for (unsigned int b=0; b<conf.cur_bunch_size; ++b) {
  // Las 2 siguientes variables no se emplean?
  //float sum_a_b = 0.0f;
  //float sum_c_a_b;
  float Gab = 0.0f, Hab = 0.0f;
  unsigned int ipos = b;
  for (unsigned int i = 0; i < output_size; i++) {
  Gab += output_ptr[ipos] * target_output_ptr[ipos];
  Hab += output_ptr[ipos] + target_output_ptr[ipos];
  ipos += conf.max_bunch_size;
  }
  Gab *= 2.0f;
  s   += 1.0f - Gab/Hab; // hacemos 1 - FMeasure para cambiar la minimizacion
  // por una maximizacion
  float HabP2 = Hab*Hab;
  ipos = b;
  for (unsigned int i = 0; i < output_size; i++) {
  // Aqui cambiamos de signo para convertir una minimizacion en una
  // maximizacion
  output_error_ptr[ipos] = -(2 * target_output_ptr[ipos] * Hab - Gab) / HabP2;
  ipos += conf.max_bunch_size;
  }
  }
  return s;
  }

*/

#undef sigmoid
#undef clip
