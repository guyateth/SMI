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
        SMI_Barrier(&chan);
    }

    *mem=check;
}

__kernel void test_barrier_timeout(__global char* mem, const int N,SMI_Comm comm)
{
    char check=1;
    
    SMI_BarrierChannel  __attribute__((register)) chan= SMI_Open_barrier_channel(N,2,comm);
    if (SMI_Comm_rank(comm) == 1){
        printf("Here we dont enter the barrier.\n");
        *mem=check;
    } else {
        SMI_Barrier(&chan);
        // set the value to 42. This line should not be reached, if it is reached, the barrier failed
        *mem=42;
    }    
}