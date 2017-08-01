/*
 *   -- SIMPLE addon
 *      Author: Frederic Bonnet, Date: 25th of September 2015
 *      Monash University
 *      Spetember 2015
 *
 *      Routine which calculates the product (element wise) of 
 *      cuDoubleComplex matrix A and cuDoubleComplex matrix B. and takes the
 *      real part of the product and puts it into a matrix of type double
 *      C = cuCreal(x) * cuCreal(y) + cuCimag(x) * cuCimag(y)
 *      C = Re( A * conjg(B) ) element wise
 *
 *      Non Special case
 * @precisions normal z -> s d c
*/
#include "common_magma.h"
#include "commonblas_zz2d.h"
#include "simple_cuDoubleComplex.h"
#include "polarft_gpu.h"
#include "simple.h"

#define imin(a,b) (a<b?a:b)
//#define debug true
//#define debug_high false

#if defined (CUDA) /*preprossing for the OPENCL environment */

extern "C" __global__ void
rsum_1D( const cuFloatComplex *A, const cuFloatComplex *B, float *partial, int N) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  int sharedIndex = threadIdx.x;
  //allocating the shared memory array
  __shared__ float shared_AB[256];

  //summing over the 
  double temp = 0.0;
  while ( i < N ){
    temp += cuReCCstarmulf(A[i],B[i]);
    i += blockDim.x * gridDim.x;
  } 
  shared_AB[sharedIndex] = temp;
  //syncronizing the threads
  __syncthreads();

  //practising the 1/2 reducion sum at each step
  int j = blockDim.x / 2.0;
  while ( j != 0 ) {
    if ( sharedIndex < j ) shared_AB[sharedIndex] += shared_AB[sharedIndex + j];
    __syncthreads();
    j /= 2;
  }
  if ( sharedIndex == 0 ) partial[blockIdx.x] = shared_AB[0];
}

extern "C" __global__ void
absqsum_1D( const cuFloatComplex *A, float *partial, int N) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  int sharedIndex = threadIdx.x;
  //allocating the shared memory array
  __shared__ float shared_A[256];

  //summing over the 
  double temp = 0.0;
  while ( i < N ){
    temp += cuReCCstarf(A[i]);
    i += blockDim.x * gridDim.x;
  } 
  shared_A[sharedIndex] = temp;
  //syncronizing the threads
  __syncthreads();

  //practising the 1/2 reducion sum at each step
  int j = blockDim.x / 2.0;
  while ( j != 0 ) {
    if ( sharedIndex < j ) shared_A[sharedIndex] += shared_A[sharedIndex + j];
    __syncthreads();
    j /= 2;
  }
  if ( sharedIndex == 0 ) partial[blockIdx.x] = shared_A[0];
}

/* main kernel entry */
extern "C" int
polarft_corr_F_N(deviceDetails_t * s_devD,
                 polar_corr_calc_t *s_polar,
                 float *r,
                 const cuFloatComplex *A,
                 const cuFloatComplex *B,
                 int npart, int nrot, int nk,
                 float alpha,
                 bench_t *s_bench, debug_gpu_t *s_debug_gpu)
{
  int rc = 0;
  /*numbers of points to be considered */
  int npts = npart * nrot * nk;
  /* grid and threads block definition */
  int nx, ny, nz;          //Dimension of the threads
  int gridx, gridy, gridz; //Dimension of the 3D Grid
  /* setting the values into the object */
  pfts_Sizes *p_pfts_Sizes = new pfts_Sizes(npart,nrot,nk);
  mesh_3D *p_mesh_3D = new mesh_3D(s_polar);
  //TODO: fix the template argument when done
  //mesh_1D *p_mesh_1D = new mesh_1D(s_polar);
  /* the error handlers from the cuda library */
  cudaError_t err;
  /*device allocation */
  float *d_r;
  cuFloatComplex *d_A;
  cuFloatComplex *d_B;
  float *d_C;   //device pointer for the r product
  /* size of the element in consideration */
  int size_r;
  int size_m;
  int size_reC;
  /*start of the execution commands */
  cuFloatComplex *C = (cuFloatComplex*)malloc(npts);

  float *reC = (float*)malloc(npts);

  /* nx=16; ny=16; nz=4; dim3 threads(16,16,4); */
  nx=s_polar->nx; ny=s_polar->ny; nz=s_polar->nz;
  dim3 threads(nx,ny,nz);
  gridx = npart/(float)nx+(npart%nx!=0);
  gridy =  nrot/(float)ny+( nrot%ny!=0);
  gridz =    nk/(float)nz+(   nk%nz!=0);
  dim3 grid(gridx,gridy,gridz);
  //dim3 grid(npart/16.0+(npart%16!=0),
  //           nrot/16.0+( nrot%16!=0),
  //             nk/4.0+(     nk%4!=0) );
  
  if (s_debug_gpu->debug_i == true ) {
    rc = print_3D_mesh(0,p_mesh_3D,s_polar,p_pfts_Sizes,nx,ny,nz);
  }
 
  //allocating the memory on GPU
  size_r = 1 * sizeof(float);
  err = cudaMalloc((void**)&d_r, size_r); if ( (int)err != CUDA_SUCCESS ) {rc = err;}
  size_m = npts*sizeof(cuFloatComplex);
  err = cudaMalloc((void**)&d_A, size_m);
  err = cudaMalloc((void**)&d_B, size_m);
  size_reC = npts*sizeof(float);
  err = cudaMalloc((void**)&d_C, size_reC);
  //uploading the matrices A, B to GPU
  err = cudaMemcpy(d_A, A, npts*sizeof(cuFloatComplex), cudaMemcpyHostToDevice);
  err = cudaMemcpy(d_B, B, npts*sizeof(cuFloatComplex), cudaMemcpyHostToDevice);
  //computing the r product now summing the r 
  int N = npart *nrot * nk;
  int threadsPerBlock = 256; //threads/per block=16*16 for more //lism
  int blocksPerGrid = imin(32,(N+threadsPerBlock-1)/threadsPerBlock);
  if (s_debug_gpu->debug_i == true ) {
    rc = print_1D_mesh(0, NULL, N, threadsPerBlock, blocksPerGrid); }

  float c;
  int size_p_c = blocksPerGrid*sizeof(float);
  // summed value
  float *partial_c = (float*)malloc(size_p_c);
  float *d_partial_c = NULL;
  err = cudaMalloc((void**)&d_partial_c, size_p_c);

  //  sum_1D<<<blocksPerGrid,threadsPerBlock>>>(d_C,d_partial_c,N);
  rsum_1D<<<blocksPerGrid,threadsPerBlock>>>(d_A, d_B, d_partial_c,N);
  cuCtxSynchronize();
  err = cudaMemcpy(partial_c, d_partial_c, size_p_c, cudaMemcpyDeviceToHost);

  c = 0.0;
  for ( int igrid = 0 ; igrid < blocksPerGrid ; igrid++ ) {  
    c += partial_c[igrid];
  }
  s_polar->r_polar = c;
  free(partial_c);
  cudaFree(d_partial_c);
  err = cudaFree(d_C);

  //getting the PFT1 * conjg(PFT1)
  float *d_CaT;  //device pointer for for sumasq
  float *partial_ca = (float*)malloc(size_p_c);
  float *d_partial_ca = NULL;
  err = cudaMalloc((void**)&d_partial_ca, size_p_c);
  err = cudaMalloc((void**)&d_CaT, size_reC);
 
  absqsum_1D<<<blocksPerGrid,threadsPerBlock>>>(d_A,d_partial_ca,N);
  cuCtxSynchronize(); //synchronizing CPU with GPU
  err = cudaMemcpy(partial_ca, d_partial_ca, size_p_c, cudaMemcpyDeviceToHost);
  c = 0.0;
  for ( int igrid = 0 ; igrid < blocksPerGrid ; igrid++ ) {  
    c += partial_ca[igrid];
  }
  s_polar->sumasq_polar = c;

  free(partial_ca);
  cudaFree(d_partial_ca);
  err = cudaFree(d_CaT);

  //getting the PFT2 * conjg(PFT2)
  float *d_CbT;  //device pointer for for sumasq
  float *partial_cb = (float*)malloc(size_p_c);
  float *d_partial_cb = NULL;
  err = cudaMalloc((void**)&d_partial_cb, size_p_c);
  err = cudaMalloc((void**)&d_CbT, size_reC);

  absqsum_1D<<<blocksPerGrid,threadsPerBlock>>>(d_B,d_partial_cb,N);
  //synchronizing CPU with GPU
  cuCtxSynchronize();
  err = cudaMemcpy(partial_cb, d_partial_cb, size_p_c, cudaMemcpyDeviceToHost);
  c = 0.0;
  for ( int igrid = 0 ; igrid < blocksPerGrid ; igrid++ ) {  
    c += partial_cb[igrid];
  }
  s_polar->sumbsq_polar = c;

  free(partial_cb);
  cudaFree(d_partial_cb);
  err = cudaFree(d_CbT);

  if ( s_debug_gpu->debug_i == true ) { 
    rc = print_s_polar_struct(s_polar);
  }

  /*freeing memory on device */
  err = cudaFree(d_r);
  err = cudaFree(d_A);
  err = cudaFree(d_B);

  /* making sure that the GPU is synchronized with CPU before proceeding */
  cuCtxSynchronize();
  /* calling the destructor for the pfts_Sizes object */
  p_mesh_3D->~mesh_3D();
  //  p_mesh_1D->~mesh_1D();

  return rc;
 
} /* End of polarft_corr_F_N */

#endif /* CUDA */
