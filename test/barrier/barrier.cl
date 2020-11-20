/**
	Broadcast test. A sequeuence of number is broadcasted.
	Non-root ranks check whether the received number is correct
*/

#include <smi.h>


__kernel void test_barrier(__global char* mem, const int N, char root,SMI_Comm comm)
{
    char check=1;
    SMI_Channel  __attribute__((register)) chan= SMI_Open_barrier_channel(N,0, root,comm);
    for(int i=0;i<N;i++)
    {

        SMI_Barrier(&chan);

    }
    *mem=check;
}

__kernel void test_barrier_2(__global char* mem, const int N, char root,SMI_Comm comm)
{
    char check=1;
    SMI_Channel  __attribute__((register)) chan= SMI_Open_barrier_channel(N,0, root,comm);
    for(int i=0;i<N;i++)
    {

        SMI_Barrier(&chan);

    }
    *mem=check;
}