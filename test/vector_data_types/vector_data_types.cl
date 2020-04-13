/**
	Test vectorized data types

	Tests with p2p channels are structured as a pipeline.
	We can have single or double channels between stages and different communication schemas (for double rail)

*/

#pragma OPENCL EXTENSION cl_intel_channels : enable
#include <smi.h>

__kernel void test_double_rail_float4(__global char* mem, const int N, SMI_Comm comm)
{
    //Interleaves between two channels
    char check=1;

    int my_rank=SMI_Comm_rank(comm);
    int num_ranks=SMI_Comm_size(comm);

    //each rank increments by one
    float4 expected1 = num_ranks-1;

    SMI_Channel chan_send1=SMI_Open_send_channel(N, SMI_FLOAT4, my_rank+1, 0, comm);
    SMI_Channel chan_send2=SMI_Open_send_channel(N, SMI_FLOAT4, my_rank+1, 1, comm);
    SMI_Channel chan_rcv1=SMI_Open_receive_channel(N, SMI_FLOAT4, my_rank-1, 0, comm);
    SMI_Channel chan_rcv2=SMI_Open_receive_channel(N, SMI_FLOAT4, my_rank-1, 1, comm);

    for(int i=0;i<N;i++)
    {
	    float4 data;
	    if(my_rank > 0){
	    	if((i&1)==0)
		    	SMI_Pop(&chan_rcv1, &data);
		    else
		    	SMI_Pop(&chan_rcv2, &data);
		    data=data+(float4)(1);
	    }
	    else{
		    data=i;
        }
        if(my_rank < num_ranks -1){
        	if((i&1)==0)
		    	SMI_Push(&chan_send1, &data);
		    else
		    	SMI_Push(&chan_send2, &data);
        }
	    else{
		    check &= (all(data==expected1+(float4)(i)));
	    }
    }
    *mem=check;
}
