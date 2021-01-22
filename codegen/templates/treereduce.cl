{% import 'utils.cl' as utils %}

{%- macro smi_treereduce_kernel(program, op) -%}
#include "smi/reduce_operations.h"

__kernel void smi_kernel_treereduce_{{ op.logical_port }}(char num_rank)
{
    ;
}
{%- endmacro %}

{%- macro smi_treereduce_impl(program, op) -%}
void {{ utils.impl_name_port_type("SMI_Treereduce", op) }}(SMI_RChannel* chan,  void* data_snd, void* data_rcv)
{
    char* conv = (char*) data_snd;
    // copy data to the network message
    COPY_DATA_TO_NET_MESSAGE(chan, chan->net,conv);

    // In this case we disabled network packetization: so we can just send the data as soon as we have it
    SET_HEADER_NUM_ELEMS(chan->net.header, 1);

    if (chan->my_rank == chan->root_rank) // root
    {
        write_channel_intel({{ op.get_channel("treereduce_send") }}, chan->net);
        SET_HEADER_OP(chan->net.header, SMI_REDUCE);          // after sending the first element of this reduce
        mem_fence(CLK_CHANNEL_MEM_FENCE);
        chan->net_2 = read_channel_intel({{ op.get_channel("treereduce_recv") }});
        // copy data from the network message to user variable
        COPY_DATA_FROM_NET_MESSAGE(chan, chan->net_2, data_rcv);
    }
    else
    {
        // wait for credits

        SMI_Network_message req = read_channel_intel({{ op.get_channel("ckr_control") }});
        mem_fence(CLK_CHANNEL_MEM_FENCE);
        SET_HEADER_OP(chan->net.header,SMI_REDUCE);
        // then send the data
        write_channel_intel({{ op.get_channel("cks_data") }}, chan->net);
    }
}
{%- endmacro %}

{%- macro smi_treereduce_channel(program, op) -%}
SMI_RChannel {{ utils.impl_name_port_type("SMI_Open_treereduce_channel", op) }}(int count, SMI_Datatype data_type, SMI_Op op, int port, int root, SMI_Comm comm)
{
    SMI_RChannel chan;
    // setup channel descriptor
    chan.message_size = (unsigned int) count;
    chan.data_type = data_type;
    chan.port = (char) port;
    chan.my_rank = (char) SMI_Comm_rank(comm);
    chan.root_rank = (char) root;
    chan.num_rank = (char) SMI_Comm_size(comm);
    chan.reduce_op = (char) op;
    chan.size_of_type = {{ op.data_size() }};
    chan.elements_per_packet = {{ op.data_elements_per_packet() }};

    // setup header for the message
    SET_HEADER_DST(chan.net.header, chan.root_rank);
    SET_HEADER_SRC(chan.net.header, chan.my_rank);
    SET_HEADER_PORT(chan.net.header, chan.port);         // used by destination
    SET_HEADER_NUM_ELEMS(chan.net.header, 0);            // at the beginning no data
    // workaround: the support kernel has to know the message size to limit the number of credits
    // exploiting the data buffer
    *(unsigned int *)(&(chan.net.data[24])) = chan.message_size;
    SET_HEADER_OP(chan.net.header, SMI_SYNCH);
    chan.processed_elements = 0;
    chan.packet_element_id = 0;
    chan.packet_element_id_rcv = 0;
    return chan;
}
{%- endmacro -%}
