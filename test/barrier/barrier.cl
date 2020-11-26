/**
	Broadcast test. A sequeuence of number is broadcasted.
	Non-root ranks check whether the received number is correct
*/

#include <smi.h>


__kernel void test_barrier(__global char* mem, const int N,SMI_Comm comm)
{
    char check=1;
    SMI_BarrierChannel  __attribute__((register)) chan= SMI_Open_barrier_channel(N,0,comm);
    
    SMI_Barrier(&chan);


    *mem=check;
}

__kernel void test_barrier_2(__global char* mem, const int N,SMI_Comm comm)
{
    char check=1;
    SMI_BarrierChannel  __attribute__((register)) chan= SMI_Open_barrier_channel(N,1,comm);

    for(int i=0;i<N;i++)
    {   
        printf("BRun %d \n", i);
        SMI_Barrier(&chan);
        printf("Run %d \n", i);
    }

    *mem=check;
}