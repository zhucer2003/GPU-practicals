#include <stdio.h>

#define N 2048 * 2048 // Number of elements in each vector

__global__ void saxpy(float scalar, float * x, float * y)
{
    // Determine our unique global thread ID, so we know which element to process
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    
    if ( tid < N ) // Make sure we don't do more work than we have data!
        y[tid] = scalar * x[tid] + y[tid];
}

int main()
{
    float *x, *y;
    
    // CUDA types for error statuses
    cudaError_t ierrSync, ierrAsync;

    int size = N * sizeof (float); // The total number of bytes per vector

    // Allocate memory
    cudaMallocManaged(&x, size);
    cudaMallocManaged(&y, size);

    // Initialize memory
    for( int i = 0; i < N; ++i )
    {
        x[i] = 1.0f;
        y[i] = 2.0f;
    }

    int threads_per_block = 256;
    int number_of_blocks = (N / threads_per_block) + 1;

    saxpy <<< number_of_blocks, threads_per_block >>> ( 2.0f, x, y );
    
    /* TODO: get last error to see if kernel launch failed
     *       check is == cudaSuccess
     */

    /* TODO: get error AFTER kernel finished (first sync CPU and device)
     *       check is == cudaSuccess
     */

    // Print out our Max Error
    float maxError = 0;
    for( int i = 0; i < N; ++i )
        if (abs(4-y[i]) > maxError) { maxError = abs(4-y[i]); }
    printf("Max Error: %.5f", maxError);

    // Free all our allocated memory
    cudaFree( x ); cudaFree( y );
}
