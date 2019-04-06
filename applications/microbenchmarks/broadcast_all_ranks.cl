#pragma OPENCL EXTENSION cl_intel_channels : enable

#include "smi_broadcast.h"



__kernel void app_0(const int N, char root,char my_rank, char num_ranks)
{
    SMI_BChannel chan= SMI_Open_bcast_channel(N, SMI_FLOAT, root,my_rank,num_ranks);
    for(int i=0;i<N;i++)
    {
        SMI_Bcast(&chan,&i);
    }
}