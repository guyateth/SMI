/**
 	Example 5 is a MPMD program, characterized by three ranks:
    - rank 0: has two application kernels App_0 and App_1
    - rank 1: has one application kernel App_2
    - rank 3: has one application kernel App_3

    The logic is the following:
    - App_0 sends N integers to App_2 through a proper channel (TAG 0)
    - App_1 sends N floats to App_3 through a proper channel (TAG 1)

	The program will be execute on three FPGA nodes ( node 15 acl0, 15:1 and 16:1)
	using the following connections:
	- 15:0:chan1 - 15:1:chan1
	- 15:1:chan0 - 16:1:chan0
        To test this: try to change the used nodes


	So we don't use the crossbar. This is done to see if everything works with an intermediate hop

        Also, considering that for the moment being we actively use only 2 QSFPs:
	- APP 0 is connected to CK_S_0: in this way its sent data must go to CK_S_1 and then to QSFP
	- APP 1 is connected to CK_S_1: so data will go through QSFP1, will be received to CK_R_1 on rank 1
		which will route it to its paired CK_S_1, who will route it to CK_S_1 (in rank 1) who finally
		sends it to rank 2
        - APP_2 is connected to CK_R_0 (so in rank 1, the messages to APP_2 will be received by CK_R_1 which routes them to CK_R_0)
	- APP_3 is connected to CK_R_0 (so no additional hop)

	Therefore the routing table for CK_Ss will be: (remember 0-> QSFP, 1 CK_R, 2... connected CK_S. This maps ranks-> ids)
	- rank 0: 	CK_S_0: 1,2,2
				CK_S_1: 1,0,0
	- rank 1:	CK_S_0: 2,1,0
				CK_S_1: 0,1,2
	- rank 2: meaningless

	The routing tables for CK_Rs, instead, maps TAGs to internal port id (0,...Q-2 other CK_R, others: application endpoints):
        - rank 0:        meaningless
        - rank 1: 	CK_R_0: 4,xxx  send to APP_2
                        CK_R_1: 1,xxx data for TAG 0 must be routed to CK_R_0 to which the APP is attached. This one also receives data that is directed to rank2

         rank 2: 	CK_R_0: xxx, xxx Meanigless
                        CK_R_1: xxx, 4


 */



#pragma OPENCL EXTENSION cl_intel_channels : enable

#include "../../kernels/communications/channel_helpers.h"
#include "../../kernels/communications/push.h"
//#include "../../kernels/communications/pop.h"


//#define EMULATION
//#define ON_CHIP
//****This part should be code-generated****

#if defined(EMULATION)
channel SMI_Network_message io_out_0 __attribute__((depth(16)))
                    __attribute__((io("emulatedChannel_15_0_to_16_0_0")));
channel SMI_Network_message io_out_1 __attribute__((depth(16)))
                    __attribute__((io("emulatedChannel_15_0_to_15_1_1")));
channel SMI_Network_message io_out_2 __attribute__((depth(16)))
                    __attribute__((io("emulatedChannel_tmp")));
channel SMI_Network_message io_out_3 __attribute__((depth(16)))
                    __attribute__((io("emulatedChannel_tmp")));

channel SMI_Network_message io_in_0 __attribute__((depth(16)))
                    __attribute__((io("emulatedChannel_16_0_to_15_0_0")));
channel SMI_Network_message io_in_1 __attribute__((depth(16)))
                    __attribute__((io("emulatedChannel_15_1_to_15_0_1")));

channel SMI_Network_message io_in_2 __attribute__((depth(16)))
                    __attribute__((io("emulatedChannel_tmp")));
channel SMI_Network_message io_in_3 __attribute__((depth(16)))
                    __attribute__((io("emulatedChannel_tmp")));

#else

channel SMI_Network_message io_out_0 __attribute__((depth(16)))
                    __attribute__((io("kernel_output_ch0")));
channel SMI_Network_message io_out_1 __attribute__((depth(16)))
                    __attribute__((io("kernel_output_ch1")));
channel SMI_Network_message io_out_2 __attribute__((depth(16)))
                    __attribute__((io("kernel_output_ch2")));
channel SMI_Network_message io_out_3 __attribute__((depth(16)))
                    __attribute__((io("kernel_output_ch3")));
channel SMI_Network_message io_in_0 __attribute__((depth(16)))
                    __attribute__((io("kernel_input_ch0")));
channel SMI_Network_message io_in_1 __attribute__((depth(16)))
                    __attribute__((io("kernel_input_ch1")));
channel SMI_Network_message io_in_2 __attribute__((depth(16)))
                    __attribute__((io("kernel_input_ch2")));
channel SMI_Network_message io_in_3 __attribute__((depth(16)))
                    __attribute__((io("kernel_input_ch3")));
#endif

//internal routing tables: these two must be visible also to push and pop implementation
//the sender_rt will be used by push  and maps TAG->channel_id (used to index channel_to_ck_s)
//on rank 0, App_0 is connected to CK_S_0, App_1 to CK_S_1
__constant char internal_sender_rt[2]={0,1};
//on the receiver, the internal routing table is used by pop and is used to map TAG->channel_id (used to index_channel_from_ck_r)
//no receivers on this rank
__constant char internal_receiver_rt[2]={0,0};

//channels to CK_S 
channel SMI_Network_message channels_to_ck_s[2] __attribute__((depth(16)));

//channels from CK_R: we don't use them, so we remove otherwise the compiler complains
//indeed we dind'nt include the pop.h header
//channel SMI_Network_message channels_from_ck_r[1] __attribute__((depth(16)));


//inteconnection between CK_S and CK_R (some of these are not used in this example)
__constant char num_qsfp=4;
channel SMI_Network_message channels_interconnect_ck_s[num_qsfp*(num_qsfp-1)] __attribute__((depth(16)));
channel SMI_Network_message channels_interconnect_ck_r[num_qsfp*(num_qsfp-1)] __attribute__((depth(16)));
//also we have two channels between each CK_S/CK_R pair
channel SMI_Network_message channels_interconnect_ck_s_to_ck_r[num_qsfp] __attribute__((depth(16)));
channel SMI_Network_message channels_interconnect_ck_r_to_ck_s[num_qsfp] __attribute__((depth(16)));




__kernel void CK_S_0(__global volatile char *restrict rt, const char numRanks)
{
    const char ck_id=0;
    //Number of senders to this CK_S is given by the number of application connected to this CK_S
    //and the number of CK_Ss pair
    const char num_sender=(num_qsfp-1)+1+1; //num_qsfp-1 CK_S, 1 CK_R, 1 application
    char sender_id=0;
    bool valid=false;
    SMI_Network_message mess;

    char external_routing_table[256];
    for(int i=0;i<numRanks;i++)
        external_routing_table[i]=rt[i];

    /* CK_S accepts input data from other CK_Ss, the paired CK_R, and from Applications.
     * It will read from these input_channel in RR, unsing non blocking read.
     */
    //This particular CK_S has App_0 attached
    while(1)
    {
        switch(sender_id)
        {
            case 0: //CK_S_1
                mess=read_channel_nb_intel(channels_interconnect_ck_s[ck_id*(num_qsfp-1)], &valid);
            break;
            case 1: //CK_S_2
                mess=read_channel_nb_intel(channels_interconnect_ck_s[ck_id*(num_qsfp-1)+1], &valid);
            break;
            case 2: //CK_S_3
                mess=read_channel_nb_intel(channels_interconnect_ck_s[ck_id*(num_qsfp-1)+2], &valid);
            break;
            case 3: //CK_R
                mess=read_channel_nb_intel(channels_interconnect_ck_r_to_ck_s[ck_id],&valid);
            break;
            case 4: //appl
                mess=read_channel_nb_intel(channels_to_ck_s[0],&valid);
            break;

        }

        if(valid)
        {
            //check the routing table
            //as possibility we have:
            // - 0, forward to the network (QSFP)
            // - 1, send to the connected CK_R (local send)
            // - 2,... send to other CK_S
            //closed formula to get the rigt ch_id for communicating with other ck_s: (dest*(numQSFP-1))+((ck_id>dest)?ck_id-1:ck_id))
            char idx=external_routing_table[GET_HEADER_DST(mess.header)];
            switch(idx)
            {
                case 0:
                    write_channel_intel(io_out_0,mess);
                    break;
                case 1:
                    write_channel_intel(channels_interconnect_ck_s_to_ck_r[ck_id],mess);
                    break;
                case 2:
                    write_channel_intel(channels_interconnect_ck_s[3],mess);
                break;
                case 3:
                    write_channel_intel(channels_interconnect_ck_s[6],mess);
                break;
                case 4:
                    write_channel_intel(channels_interconnect_ck_s[9],mess);
                break;
            }
            valid=false;
        }
        sender_id++;
        if(sender_id==num_sender)
                sender_id=0;

    }
}



__kernel void CK_S_1(__global volatile char *restrict rt, const char numRanks)
{
    const char ck_id=1;
    //Number of sender is given by the number of application connected to this CK_S
    //and the number of CK_Ss pair
    const char num_sender=(num_qsfp-1)+1+1; //num_qsfp-1 CK_S, 1 CK_R, 1 application
    char sender_id=0;
    bool valid=false;
    SMI_Network_message mess;
    
    char external_routing_table[256];
    for(int i=0;i<numRanks;i++)
        external_routing_table[i]=rt[i];

    /* CK_S accepts input data from other CK_Ss, the paired CK_R, and from Applications.
     * It will read from these input_channel in RR, unsing non blocking read.
     */
    while(1)
    {
        switch(sender_id)
        {
            case 0: //CK_S_0
                mess=read_channel_nb_intel(channels_interconnect_ck_s[ck_id*(num_qsfp-1)], &valid);
            break;
            case 1: //CK_S_2
                mess=read_channel_nb_intel(channels_interconnect_ck_s[ck_id*(num_qsfp-1)+1], &valid);
            break;
            case 2: //CK_S_3
                mess=read_channel_nb_intel(channels_interconnect_ck_s[ck_id*(num_qsfp-1)+2], &valid);
            break;
            case 3: //CK_R
                mess=read_channel_nb_intel(channels_interconnect_ck_r_to_ck_s[ck_id],&valid);
            break;
            case 4: //appl
                mess=read_channel_nb_intel(channels_to_ck_s[1],&valid);
            break;

        }

        if(valid)
        {
            //check the routing table
            //as possibility we have:
            // - 0, forward to the network (QSFP)
            // - 1, send to the connected CK_R (local send)
            // - 2,... send to other CK_S
            char idx=external_routing_table[GET_HEADER_DST(mess.header)];
            switch(idx)
            {
                case 0:
                    write_channel_intel(io_out_1,mess);
                break;
                case 1:
                    write_channel_intel(channels_interconnect_ck_s_to_ck_r[ck_id],mess);
                    break;
                case 2: //CK_S_0
                    write_channel_intel(channels_interconnect_ck_s[0],mess);
                break;
                case 3: //CK_S_2
                    write_channel_intel(channels_interconnect_ck_s[7],mess);
                break;
                case 4: //CK_S_3
                    write_channel_intel(channels_interconnect_ck_s[10],mess);
                break;
            }
            valid=false;
        }
        sender_id++;
        if(sender_id==num_sender)
                sender_id=0;
    }
}


__kernel void CK_S_2(__global volatile char *restrict rt, const char numRanks)
{
    const char ck_id=2;
    const char num_sender=(num_qsfp-1)+1; //num_qsfp-1 CK_S, 1 CK_R
    char sender_id=0;
    bool valid=false;
    SMI_Network_message mess;

    char external_routing_table[256];
    for(int i=0;i<numRanks;i++)
        external_routing_table[i]=rt[i];
    while(1)
    {
        switch(sender_id)
        {
            case 0: //CK_S_0
                mess=read_channel_nb_intel(channels_interconnect_ck_s[ck_id*(num_qsfp-1)], &valid);
            break;
            case 1: //CK_S_1
                mess=read_channel_nb_intel(channels_interconnect_ck_s[ck_id*(num_qsfp-1)+1], &valid);
            break;
            case 2: //CK_S_3
                mess=read_channel_nb_intel(channels_interconnect_ck_s[ck_id*(num_qsfp-1)+2], &valid);
            break;
            case 3: //CK_R
                mess=read_channel_nb_intel(channels_interconnect_ck_r_to_ck_s[ck_id],&valid);
            break;
        }

        if(valid)
        {

            char idx=external_routing_table[GET_HEADER_DST(mess.header)];
            switch(idx)
            {
                case 0:
                    write_channel_intel(io_out_2,mess);
                break;
                case 1:
                    write_channel_intel(channels_interconnect_ck_s_to_ck_r[ck_id],mess);
                break;
                case 2: //CK_S_0
                    write_channel_intel(channels_interconnect_ck_s[1],mess);
                break;
                case 3: //CK_S_1
                    write_channel_intel(channels_interconnect_ck_s[4],mess);
                break;
                case 4: //CK_S_3
                    write_channel_intel(channels_interconnect_ck_s[11],mess);
                break;
            }
            valid=false;
        }
        sender_id++;
        if(sender_id==num_sender)
                sender_id=0;
    }
}


__kernel void CK_S_3(__global volatile char *restrict rt, const char numRanks)
{
    const char ck_id=3;
    const char num_sender=(num_qsfp-1)+1;
    char sender_id=0;
    bool valid=false;
    SMI_Network_message mess;

    char external_routing_table[256];
    for(int i=0;i<numRanks;i++)
        external_routing_table[i]=rt[i];

    while(1)
    {
        switch(sender_id)
        {
            case 0: //CK_S_0
                mess=read_channel_nb_intel(channels_interconnect_ck_s[ck_id*(num_qsfp-1)], &valid);
            break;
            case 1: //CK_S_1
                mess=read_channel_nb_intel(channels_interconnect_ck_s[ck_id*(num_qsfp-1)+1], &valid);
            break;
            case 2: //CK_S_2
                mess=read_channel_nb_intel(channels_interconnect_ck_s[ck_id*(num_qsfp-1)+2], &valid);
            break;
            case 3: //CK_R
                mess=read_channel_nb_intel(channels_interconnect_ck_r_to_ck_s[ck_id],&valid);
            break;

        }

        if(valid)
        {
            char idx=external_routing_table[GET_HEADER_DST(mess.header)];
            switch(idx)
            {
                case 0:
                    write_channel_intel(io_out_3,mess);
                    break;
                case 1:
                    write_channel_intel(channels_interconnect_ck_s_to_ck_r[ck_id],mess);
                    break;
                case 2: //CK_S_0
                    write_channel_intel(channels_interconnect_ck_s[2],mess);
                break;
                case 3: //CK_S_1
                    write_channel_intel(channels_interconnect_ck_s[5],mess);
                break;
                case 4: //CK_S_2
                    write_channel_intel(channels_interconnect_ck_s[8],mess);
                break;
            }
            valid=false;
        }
        sender_id++;
        if(sender_id==num_sender)
                sender_id=0;
    }
}


//This will not do anything
__kernel void CK_R_0(__global volatile char *rt,const char myRank, const char numRanks)
{
    const char ck_id=0;
    //The CK_R will receive from i/o, others CK_R and the paired CK_S (for local sends)
    const char num_senders=1+(num_qsfp-1)+1; //1 QSFP, num_qsfp-1 CK_Rs, 1 CK_S
    char sender_id=0;
    bool valid=false;
    SMI_Network_message mess;

    char external_routing_table[256];
    //load the routing table: in this case is useless
    for(int i=0;i<numRanks;i++)
        external_routing_table[i]=rt[i];

    /* The CK_R receives:
     *  - from the QSFP;
     *  -  from other CK_Rs;
     *  - from the paired CK_S;
     */
    while(1)
    {
        switch(sender_id)
        {
            case 0: //QSFP
                mess=read_channel_nb_intel(io_in_0,&valid);
            break;
            case 1: //CK_R_0
                mess=read_channel_nb_intel(channels_interconnect_ck_r[ck_id*(num_qsfp-1)],&valid);
            break;
            case 2: //CK_R_1
                mess=read_channel_nb_intel(channels_interconnect_ck_r[ck_id*(num_qsfp-1)+1],&valid);
            break;
            case 3: //CK_R_2
                mess=read_channel_nb_intel(channels_interconnect_ck_r[ck_id*(num_qsfp-1)+2],&valid);
            break;
            case 4: //paired CK_S
                mess=read_channel_nb_intel(channels_interconnect_ck_s_to_ck_r[ck_id],&valid);
            break;
        }
        if(valid)
        {
            //forward it to the right application endpoint or to another CK_R
            //0, send to the connected CK_S (remote send)
            //1, ...,NQ−1, send to other CK_R (the application endpoint is not connected to this CK_R)
            //other indexes: send to the application
            char dest;
            if(GET_HEADER_DST(mess.header)!=myRank)
                dest=0;
            else
                dest=external_routing_table[GET_HEADER_TAG(mess.header)];
            //notice: in this case we don't use the internal_receiver_routing_table
            //this is somehow included in the routing table and the code below
            //The internal_receiver_routing_table, will be instead used for generating the external routing_table
            switch(dest)
            {
                case 0:
                    write_channel_intel(channels_interconnect_ck_r_to_ck_s[ck_id],mess);
                break;
                case 1: //CK_R_1
                    write_channel_intel(channels_interconnect_ck_r[3],mess);
                break;
                case 2: //CK_R_2
                    write_channel_intel(channels_interconnect_ck_r[6],mess);
                break;
                case 3: //CK_R_3
                    write_channel_intel(channels_interconnect_ck_r[9],mess);
                break;
                    //there no other cases for this, since there is no application endpoints connected to it
            }
            valid=false;
        }
        sender_id++;
        if(sender_id==num_senders)
                sender_id=0;

    }

}

//This will not do anything
__kernel void CK_R_1(__global volatile char *rt,const char myRank, const char numRanks)
{
    const char ck_id=1;
    const char num_senders=1+(num_qsfp-1)+1; //1 QSFP, 1 CK_R, 1 CK_S
    char sender_id=0;
    bool valid=false;
    SMI_Network_message mess;

    char external_routing_table[256];
    //load the routing table: in this case is useless
    for(int i=0;i<numRanks;i++)
        external_routing_table[i]=rt[i];

    /* The CK_R receives:
     *  - from the QSFP;
     *  -  from other CK_Rs;
     *  - from the paired CK_S;
     */
    while(1)
    {
        switch(sender_id)
        {
            case 0: //QSFP
                mess=read_channel_nb_intel(io_in_1,&valid);
            break;
            case 1: //CK_R_0
                mess=read_channel_nb_intel(channels_interconnect_ck_r[ck_id*(num_qsfp-1)],&valid);
            break;
            case 2: //CK_R_1
                mess=read_channel_nb_intel(channels_interconnect_ck_r[ck_id*(num_qsfp-1)+1],&valid);
            break;
            case 3: //CK_R_2
                mess=read_channel_nb_intel(channels_interconnect_ck_r[ck_id*(num_qsfp-1)+2],&valid);
            break;
            case 4: //paired CK_S
                mess=read_channel_nb_intel(channels_interconnect_ck_s_to_ck_r[ck_id],&valid);
            break;
        }
        if(valid)
        {
            //forward it to the right application endpoint or to another CK_R
            //0, send to the connected CK_S (remote send)
            //1, ...,NQ−1, send to other CK_R (the application endpoint is not connected to this CK_R)
            //other indexes: send to the application
            char dest;
            if(GET_HEADER_DST(mess.header)!=myRank)
                dest=0;
            else
                dest=external_routing_table[GET_HEADER_TAG(mess.header)];
            //notice: in this case we don't use the internal_receiver_routing_table
            //this is somehow included in the routing table and the code below
            //in this case we know that if the routing table there is written 2 then we forward to the application
            switch(dest)
            {
                case 0:
                    write_channel_intel(channels_interconnect_ck_r_to_ck_s[ck_id],mess);
                break;
                case 1: //CK_R_0
                    write_channel_intel(channels_interconnect_ck_r[0],mess);
                break;
                case 2: //CK_R_2
                    write_channel_intel(channels_interconnect_ck_r[7],mess);
                break;
                case 3: //CK_R_3
                    write_channel_intel(channels_interconnect_ck_r[10],mess);
                break;
                //no APPs
            }
            valid=false;
        }
        sender_id++;
        if(sender_id==num_senders)
                sender_id=0;

    }

}

//This will not do anything
__kernel void CK_R_2(__global volatile char *rt,const char myRank, const char numRanks)
{
    const char ck_id=2;
    const char num_senders=1+(num_qsfp-1)+1; //1 QSFP, 1 CK_R, 1 CK_S
    char sender_id=0;
    bool valid=false;
    SMI_Network_message mess;

    char external_routing_table[256];
    //load the routing table: in this case is useless
    for(int i=0;i<numRanks;i++)
        external_routing_table[i]=rt[i];

    /* The CK_R receives:
     *  - from the QSFP;
     *  -  from other CK_Rs;
     *  - from the paired CK_S;
     */
    while(1)
    {
        switch(sender_id)
        {
            case 0: //QSFP
                mess=read_channel_nb_intel(io_in_2,&valid);
            break;
            case 1: //CK_R_0
                mess=read_channel_nb_intel(channels_interconnect_ck_r[ck_id*(num_qsfp-1)],&valid);
            break;
            case 2: //CK_R_1
                mess=read_channel_nb_intel(channels_interconnect_ck_r[ck_id*(num_qsfp-1)+1],&valid);
            break;
            case 3: //CK_R_2
                mess=read_channel_nb_intel(channels_interconnect_ck_r[ck_id*(num_qsfp-1)+2],&valid);
            break;
            case 4: //paired CK_S
                mess=read_channel_nb_intel(channels_interconnect_ck_s_to_ck_r[ck_id],&valid);
            break;
        }
        if(valid)
        {
            //forward it to the right application endpoint or to another CK_R
            //0, send to the connected CK_S (remote send)
            //1, ...,NQ−1N_Q-1N​Q​​−1, send to other CK_R (the application endpoint is not connected to this CK_R)
            //other indexes: send to the application
            char dest;
            if(GET_HEADER_DST(mess.header)!=myRank)
                dest=0;
            else
                dest=external_routing_table[GET_HEADER_TAG(mess.header)];
            //notice: in this case we don't use the internal_receiver_routing_table
            //this is somehow included in the routing table and the code below
            //in this case we know that if the routing table there is written 2 then we forward to the application
            switch(dest)
            {
                case 0:
                    write_channel_intel(channels_interconnect_ck_r_to_ck_s[ck_id],mess);
                break;
                case 1:
                    write_channel_intel(channels_interconnect_ck_r[1],mess);
                break;
                case 2:
                    write_channel_intel(channels_interconnect_ck_r[4],mess);
                break;
                case 3:
                    write_channel_intel(channels_interconnect_ck_r[11],mess);
                break;
                //no APPs
            }
            valid=false;
        }
        sender_id++;
        if(sender_id==num_senders)
                sender_id=0;

    }

}

//This will not do anything

__kernel void CK_R_3(__global volatile char *rt,const char myRank, const char numRanks)
{

    char sender_id=0;
    bool valid=false;
    const char ck_id=3;
    SMI_Network_message mess;
    const char num_senders=1+(num_qsfp-1)+1; //1 QSFP, 1 CK_R, 1 CK_S

    char external_routing_table[256];
    //load the routing table: in this case is useless
    for(int i=0;i<numRanks;i++)
        external_routing_table[i]=rt[i];
    /* The CK_R receives:
     *  - from the QSFP;
     *  -  from other CK_Rs;
     *  - from the paired CK_S;
     */
    while(1)
    {
        switch(sender_id)
        {
            case 0: //QSFP
                mess=read_channel_nb_intel(io_in_3,&valid);
            break;
            case 1: //CK_R_0
                mess=read_channel_nb_intel(channels_interconnect_ck_r[ck_id*(num_qsfp-1)],&valid);
            break;
            case 2: //CK_R_1
                mess=read_channel_nb_intel(channels_interconnect_ck_r[ck_id*(num_qsfp-1)+1],&valid);
            break;
            case 3: //CK_R_2
                mess=read_channel_nb_intel(channels_interconnect_ck_r[ck_id*(num_qsfp-1)+2],&valid);
            break;
            case 4: //paired CK_S
                mess=read_channel_nb_intel(channels_interconnect_ck_s_to_ck_r[ck_id],&valid);
            break;
        }
        if(valid)
        {
            //forward it to the right application endpoint or to another CK_R
            //0, send to the connected CK_S (remote send)
            //1, ...,NQ−1N_Q-1N​Q​​−1, send to other CK_R (the application endpoint is not connected to this CK_R)
            //other indexes: send to the application
            char dest;
            if(GET_HEADER_DST(mess.header)!=myRank)
                dest=0;
            else
                dest=external_routing_table[GET_HEADER_TAG(mess.header)];
            //notice: in this case we don't use the internal_receiver_routing_table
            //this is somehow included in the routing table and the code below
            //in this case we know that if the routing table there is written 2 then we forward to the application
            switch(dest)
            {
                case 0:
                    write_channel_intel(channels_interconnect_ck_r_to_ck_s[ck_id],mess);
                break;
                case 1:
                    write_channel_intel(channels_interconnect_ck_r[2],mess);
                break;
                case 2:
                    write_channel_intel(channels_interconnect_ck_r[5],mess);
                break;
                case 3:
                    write_channel_intel(channels_interconnect_ck_r[8],mess);
                break;
                //no APPs
            }
            valid=false;
        }
        sender_id++;
        if(sender_id==num_senders)
                sender_id=0;

    }

}


//****End code-generated part ****

__kernel void app_0(const int N)
{
    //Rank 1, TAG 0
    SMI_Channel chan=SMI_Open_send_channel(N,SMI_INT,1,0);
    for(int i=0;i<N;i++)
    {
        int data=i;
        SMI_Push(&chan,&data);
    }
}

__kernel void app_1(const int N)
{
    //Rank 2, TAG 1
    SMI_Channel chan=SMI_Open_send_channel(N,SMI_FLOAT,2,1);
    const float start=1.1f;
    for(int i=0;i<N;i++)
    {
        float data=i+start;
        SMI_Push(&chan,&data);
    }
}