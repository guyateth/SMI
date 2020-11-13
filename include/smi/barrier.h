#ifndef BARRIER_H
#define BARRIER_H
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

/**
 * @brief SMI_Open_bcast_channel opens a broadcast channel
 * @param count number of data elements to broadcast
 * @param data_type type of the channel
 * @param port port number
 * @param root rank of the root
 * @param comm communicator
 * @return the channel descriptor
 */
SMI_BChannel SMI_Open_bcast_channel(int count, SMI_Datatype data_type, int port, int root, SMI_Comm comm);

/**
 * @brief SMI_Open_bcast_channel_ad opens a broadcast channel with a given asynchronicity degree
 * @param count number of data elements to broadcast
 * @param data_type type of the channel
 * @param port port number
 * @param root rank of the root
 * @param comm communicator
 * @param asynch_degree the asynchronicity degree in number of data elements
 * @return the channel descriptor
 */
SMI_BChannel SMI_Open_bcast_channel_ad(int count, SMI_Datatype data_type, int port, int root, SMI_Comm comm, int asynch_degree);

/**
 * @brief SMI_Bcast
 * @param chan pointer to the broadcast channel descriptor
 * @param data pointer to the data element: on the root rank is the element that will be transmitted,
    on the non-root rank will be the received element
 */
void SMI_Bcast(SMI_BChannel *chan, void* data);
#endif // BCAST_H
