#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define I2PI (1<<16)
#define MASK (I2PI-1)

__global__ void initarraygpu(float[], float[], int);

__global__ void computestrucf(float*, float*,
			      float*, float*,
			      int, int,
			      int, int, int);

extern "C"{
  void cudastrucf_(float *csf_r, float *csf_i, float *cex_r, float *cex_i, float *xat, int *nxat, int *num, float *xm, float *win, float *vin, float *uin, int *cr_natoms)
  {
    int nnum = num[0]*num[1]*num[2];
    
    int threadsPerBlock = 64;
    int threadsPerGrid = (nnum + threadsPerBlock - 1) / threadsPerBlock;
    
    float* d_rtcsf;
    cudaMalloc((void**) &d_rtcsf, nnum * sizeof(float));
    float* d_itcsf;
    cudaMalloc((void**) &d_itcsf, nnum * sizeof(float));
    
    float* d_rexp;
    cudaMalloc((void**) &d_rexp, I2PI * sizeof(float));
    float* d_iexp;
    cudaMalloc((void**) &d_iexp, I2PI * sizeof(float));
    
    cudaMemcpy(d_rexp, cex_r, I2PI * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_iexp, cex_i, I2PI * sizeof(float), cudaMemcpyHostToDevice);
    
    initarraygpu<<<threadsPerGrid, threadsPerBlock>>>(d_rtcsf, d_itcsf, nnum);
    
    printf("Starting CUDA!!\n");
    
    float xarg0, xincu, xincv;//, xincw;
    int iarg0, iincu, iincv;//, iincw;
    
    for(int l=0; l< nxat[0]; l++){
      xarg0 = xm[0] * xat[l] + xm[1] * xat[l+cr_natoms[0]+1] + xm[2] * xat[l+cr_natoms[0]+2];
      xincu = uin[0] * xat[l] + uin[1] * xat[l+cr_natoms[0]+1] + uin[2] * xat[l+cr_natoms[0]+2];
      xincv = vin[0] * xat[l] + vin[1] * xat[l+cr_natoms[0]+1] + vin[2] * xat[l+cr_natoms[0]+2];
      //xincw = win1 * xat1 + win2 * xat2 + win3 * xat3;
      iarg0 = (int)rintf(64 * I2PI * (xarg0 - (int)xarg0 + 1.));
      iincu = (int)rintf(64 * I2PI * (xincu - (int)xincu + 1.));
      iincv = (int)rintf(64 * I2PI * (xincv - (int)xincv + 1.));
      //iincw = (int)rintf(64 * I2PI * (xincw - (int)xincw + 1.));
      
      computestrucf<<<threadsPerGrid, threadsPerBlock>>>
	(d_rexp, d_iexp,
	 d_rtcsf, d_itcsf,
	 num[0],num[1],
	 iarg0,iincu,iincv);
    }
    
    cudaMemcpy(csf_r, d_rtcsf, nnum*sizeof(float), cudaMemcpyDeviceToHost);
    cudaMemcpy(csf_i, d_itcsf, nnum*sizeof(float), cudaMemcpyDeviceToHost);
    
    
    cudaFree(d_rtcsf);
    cudaFree(d_itcsf);
    cudaFree(d_rexp);
    cudaFree(d_iexp);
    
  }
}

__global__ void computestrucf(float* exp_r, float* exp_i,
			      float* tcsf_r, float* tcsf_i,
			      int num1, int num2,
			      int iarg0, int iincu, int iincv)
{
  int i, j, iadd, id, iarg;
  
  id = threadIdx.x + blockDim.x * blockIdx.x;
  if(id<num1*num2)
    {
      i = id / num1;
      j = id % num1;
      iarg = iarg0 + j * iincu + i * iincv;
      iadd = iarg >> 6;
      iadd = iadd & MASK;
      //tcsf_r[i*num1+j] += exp_r[iadd];
      //tcsf_i[i*num1+j] += exp_i[iadd];
      tcsf_r[id] += exp_r[iadd];
      tcsf_i[id] += exp_i[iadd];
    };
  __syncthreads();
}


__global__ void initarraygpu(float* array1, float* array2, int nelements)
{
  int id = threadIdx.x + blockDim.x * blockIdx.x;
  if(id<nelements)
    {
      array1[id] = 0.0;
      array2[id] = 0.0;
    };
  __syncthreads();
}

