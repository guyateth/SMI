#ifndef TREECAST_H
#define TREECAST_H
#pragma OPENCL EXTENSION cl_khr_fp64 : enable

/**
   @file barrier.h
   This file contains the definition of channel descriptor,
   open channel and communication primitive for Barrier.
*/

#include "data_types.h"
#include "header_message.h"
#include "operation_type.h"
#include "network_message.h"
#include "communicator.h"


typedef struct __attribute__((packed)) __attribute__((aligned(64))){
    SMI_Network_message net;            //buffered network message
    SMI_Network_message net_2;          //buffered network message: used for the receiving side
    char root_rank;
    char my_rank;                       //These two are essentially the Communicator
    char num_rank;
    char port;                          //Port number
    char packet_element_id_rcv;         //used by the receivers
    unsigned int message_size;          //given in number of data elements
    bool init;                          //true at the beginning, used by the receivers for synchronization
    bool waiting;
}SMI_TreecastChannel;

/**
 * @brief SMI_Open_bcast_channel opens a barrier channel
 * @param count number of data elements to barrier
 * @param data_type type of the channel
 * @param port port number
 * @param root rank of the root
 * @param comm communicator
 * @return the channel descriptor
 */
SMI_TreecastChannel SMI_Open_treecast_channel(int count, SMI_Datatype data_type, int port, int root, SMI_Comm comm);

/**
 * @brief SMI_Open_bcast_channel_ad opens a barrier channel with a given asynchronicity degree
 * @param count number of data elements to barrier
 * @param data_type type of the channel
 * @param port port number
 * @param root rank of the root
 * @param comm communicator
 * @param asynch_degree the asynchronicity degree in number of data elements
 * @return the channel descriptor
 */
SMI_TreecastChannel SMI_Open_treecast_channel_ad(int count, SMI_Datatype data_type, int port, int root, SMI_Comm comm, int asynch_degree);

/**
 * @brief SMI_Bcast
 * @param chan pointer to the barrier channel descriptor
 * @param data pointer to the data element: on the root rank is the element that will be transmitted,
    on the non-root rank will be the received element
 */
void SMI_Treecast(SMI_TreecastChannel *chan);
#endif // BARRIER_H