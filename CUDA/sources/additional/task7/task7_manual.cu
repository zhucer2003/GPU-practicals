#include <stdio.h>
#include <math.h>
// CUDA utils
#include "util.hpp"

// Simple define to index into a 1D array from 2D space
#define I2D(num, c, r) ((r)*(num)+(c))

__global__
void step_kernel_mod(int ni, int nj, float fact, float* temp_in, float* temp_out) 
{
  int i00, im10, ip10, i0m1, i0p1;
  float d2tdx2, d2tdy2;

  int j = blockDim.x * blockIdx.x + threadIdx.x;
  int i = blockDim.y * blockIdx.y + threadIdx.y;
  
  
  // loop over all points in domain (except boundary) 
  if ( (j>0 && i>0) && (j<nj-1 && i<ni-1) ) {
      // find indices into linear memory 
      // for central point and neighbours 
      i00 = I2D(ni, i, j); 
      im10 = I2D(ni, i-1, j); 
      ip10 = I2D(ni, i+1, j); 
      i0m1 = I2D(ni, i, j-1); 
      i0p1 = I2D(ni, i, j+1); 
            
      // evaluate derivatives 
      d2tdx2 = temp_in[im10]-2*temp_in[i00]+temp_in[ip10]; 
      d2tdy2 = temp_in[i0m1]-2*temp_in[i00]+temp_in[i0p1]; 
            
      // update temperatures 
      temp_out[i00] = temp_in[i00]+fact*(d2tdx2 + d2tdy2); 
    } 
}

void step_kernel_ref(int ni, int nj, float fact, float* temp_in, float* temp_out) 
{ 
  int i00, im10, ip10, i0m1, i0p1;
  float d2tdx2, d2tdy2;  
  
  
  // loop over all points in domain (except boundary) 
  for ( int j=1; j < nj-1; j++ ) { 
    for ( int i=1; i < ni-1; i++ ) { 
      // find indices into linear memory 
      // for central point and neighbours 
      i00 = I2D(ni, i, j); 
      im10 = I2D(ni, i-1, j); 
      ip10 = I2D(ni, i+1, j); 
      i0m1 = I2D(ni, i, j-1); 
      i0p1 = I2D(ni, i, j+1); 
            
      // evaluate derivatives 
      d2tdx2 = temp_in[im10]-2*temp_in[i00]+temp_in[ip10]; 
      d2tdy2 = temp_in[i0m1]-2*temp_in[i00]+temp_in[i0p1]; 
            
      // update temperatures 
      temp_out[i00] = temp_in[i00]+fact*(d2tdx2 + d2tdy2); 
    } 
  } 
} 

int main()
{
  int istep;
  int nstep = 200; // number of time steps
  
  // Specify our 2D dimensions
  const int ni = 200;
  const int nj = 100;
  float tfac = 8.418e-5; // thermal diffusivity of silver
  
  //const int size = ni * nj * sizeof(float);
  const size_t size = ni * nj;
  
  // Old alloc
  //temp1_ref = (float*)malloc(size);
  //temp2_ref = (float*)malloc(size);
  //temp1 = (float*)malloc(size);
  //temp2 = (float*)malloc(size);
  
  // Host
  float* temp_tmp;
  float* temp1_ref=malloc_host<float>(size);
  float* temp2_ref=malloc_host<float>(size);
  float* temp1=malloc_host<float>(size);
  float* temp2=malloc_host<float>(size);
  // Device
  float* d_temp1=malloc_device<float>(size);
  float* d_temp2=malloc_device<float>(size);
  float* d_temp_tmp=malloc_device<float>(size);

  // Initialize with random data
  for( int i = 0; i < ni*nj; ++i) {
    temp1_ref[i] = temp2_ref[i] = (float)rand()/(float)(RAND_MAX/100.0f);
  }

  //Here we manually copy initial data on the device
  copy_to_device<float>(temp1_ref, d_temp1, size);
  copy_to_device<float>(temp2_ref, d_temp2, size);

  // === CPU version (ref) ===
  for (istep=0; istep < nstep; istep++) {
    step_kernel_ref(ni, nj, tfac, temp1_ref, temp2_ref); 
       
    // swap the temperature pointers 
    temp_tmp = temp1_ref; 
    temp1_ref = temp2_ref;
    temp2_ref= temp_tmp; 
  }
  
  // ==== GPU kernel ====
  // Define grid size for kernel launch
  dim3 threads_per_block(32, 16, 1); // 32 x 16 threads per block
  dim3 number_of_blocks( (nj / threads_per_block.x)+1, (ni / threads_per_block.y)+1, 1);
  // Execute the GPU version with the same data
  for (istep=0; istep < nstep; istep++) { 
    step_kernel_mod<<< number_of_blocks, threads_per_block>>>(ni, nj, tfac, d_temp1, d_temp2); 

    // Check errors
    cuda_check_last_kernel("step_kernel_mod");
    cuda_check_status(cudaDeviceSynchronize());
       
    // swap the temperature pointers 
    d_temp_tmp = d_temp1; 
    d_temp1 = d_temp2; 
    d_temp2= d_temp_tmp; 
  }

  // We copy back data from device
  copy_to_host<float>(d_temp1, temp1, size);
  copy_to_host<float>(d_temp2, temp2, size);

  float maxError = 0;
  // Output should always be stored in the temp1 and temp1_ref at this point
  for( int i = 0; i < ni*nj; ++i ) {
    if (abs(temp1[i]-temp1_ref[i]) > maxError) { maxError = abs(temp1[i]-temp1_ref[i]); }
  }
  
  // Check and see if our maxError is greater than an error bound
  if (maxError > 0.0005f)
  	printf("Problem! The Max Error of %.5f is NOT within acceptable bounds.\n", maxError);
  else
  	printf("The Max Error of %.5f is within acceptable bounds.\n", maxError);
  
  free( temp1_ref );
  free( temp2_ref );
  free( temp1 );
  free( temp2 );
  cudaFree( d_temp1 );
  cudaFree( d_temp2 );
    
  return 0;
}