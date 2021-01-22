#ifndef TREEREDUCE_H
#define TREEREDUCE_H
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
    char root_rank;
    char my_rank;                       //These two are essentially the Communicator
    char num_rank;
    char port;                          //Port number
    unsigned int message_size;          //given in number of data elements
    unsigned int processed_elements;    //how many data elements we have sent/received
    char packet_element_id;             //given a packet, the id of the element that we are currently processing (from 0 to the data elements per packet)
    SMI_Datatype data_type;             //type of message
    SMI_Network_message net_2;          //buffered network message: used for the receiving side
    char size_of_type;                  //size of data type
    char elements_per_packet;           //number of data elements per packet
    char packet_element_id_rcv;         //used by the receivers
    bool init;                          //true at the beginning, used by the receivers for synchronization
    bool waiting;
    char child_one;
    char child_two;
    char my_parent;
}SMI_TreereduceChannel;

/**
 * @brief SMI_Open_bcast_channel opens a barrier channel
 * @param count number of data elements to barrier
 * @param data_type type of the channel
 * @param port port number
 * @param root rank of the root
 * @param comm communicator
 * @return the channel descriptor
 */
SMI_TreereduceChannel SMI_Open_treereduce_channel(int count, SMI_Datatype data_type, int port, int root, SMI_Comm comm);

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
SMI_TreereduceChannel SMI_Open_treereduce_channel_ad(int count, SMI_Datatype data_type, int port, int root, SMI_Comm comm, int asynch_degree);

/**
 * @brief SMI_Bcast
 * @param chan pointer to the barrier channel descriptor
 * @param data pointer to the data element: on the root rank is the element that will be transmitted,
    on the non-root rank will be the received element
 */
void SMI_Treereduce(SMI_TreereduceChannel *chan, void* data);
#endif // BARRIER_H
