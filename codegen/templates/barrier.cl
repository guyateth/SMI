{% import 'utils.cl' as utils %}

{%- macro smi_barrier_kernel(program, op) -%}
__kernel void smi_kernel_barrier_{{ op.logical_port }}(char num_rank)
{
    bool external = true;
    char rcv;
    char root;
    char received_request = 0; // how many ranks are ready to receive
    const char num_requests = num_rank - 1;
    SMI_Network_message mess;

    while (true)
    {
        if (external) // read from the application
        {
            mess = read_channel_intel({{ op.get_channel("barrier_lock") }});
            printf("Got msg to kern (from root)\n");
            if (GET_HEADER_OP(mess.header) == SMI_BARRIER)   // beginning of a barrier, we have to wait for "ready to receive"
            {
                received_request = num_requests;
            }
            SET_HEADER_OP(mess.header, SMI_BARRIER);
            rcv = 0;
            external = false;
            root = GET_HEADER_SRC(mess.header);
        }
        else // handle the request
        {
            if (received_request != 0)
            {
                printf("Got msg to kern (from any: %d)\n", GET_HEADER_SRC(mess.header));
                SMI_Network_message req = read_channel_intel({{ op.get_channel("ckr_control") }});
                received_request--;
            }
            else
            {
                if (rcv != root) // it's not me
                {
                    printf("send to %d)\n", rcv);
                    SET_HEADER_DST(mess.header, rcv);
                    SET_HEADER_PORT(mess.header, {{ op.logical_port }});
                    write_channel_intel({{ op.get_channel("cks_data") }}, mess);
                } else { // it is me
                    SET_HEADER_DST(mess.header, rcv);
                    SET_HEADER_PORT(mess.header, {{ op.logical_port }});
                    write_channel_intel({{ op.get_channel("barrier_lift") }}, mess);
                }
                rcv++;
                external = rcv == num_rank; 
            }
        }
    }
}
{%- endmacro %}

{%- macro smi_barrier_impl(program, op) -%}
void {{ utils.impl_name_port_type("SMI_Barrier", op) }}(SMI_BarrierChannel* chan)
{
    // In a barrier we dont need packetization, as we only send control messages
    SET_HEADER_NUM_ELEMS(chan->net.header, 1);

    if (chan->my_rank == chan->root_rank) // root
    {
        SET_HEADER_OP(chan->net.header, SMI_BARRIER);          // after sending the first element of this reduce
        printf("Send msg to kern (from root)\n");
        write_channel_intel({{ op.get_channel("barrier_lock") }}, chan->net);
        
        mem_fence(CLK_CHANNEL_MEM_FENCE);
        chan->net_2 = read_channel_intel({{ op.get_channel("barrier_lift") }});
        // copy data from the network message to user variable
    }
    else
    {
        // send "awaiting at barrier"
        SET_HEADER_OP(chan->net.header,SMI_BARRIER);
        write_channel_intel({{ op.get_channel("cks_control") }}, chan->net);
        mem_fence(CLK_CHANNEL_MEM_FENCE);
        SMI_Network_message req = read_channel_intel({{ op.get_channel("ckr_data") }});        
    }
}
{%- endmacro %}

{%- macro smi_barrier_channel(program, op) -%}
SMI_BarrierChannel {{ utils.impl_name_port_type("SMI_Open_barrier_channel", op) }}(int count, int port, int root, SMI_Comm comm)
{
    SMI_BarrierChannel chan;
    // setup channel descriptor
    chan.port = (char) port;
    chan.my_rank = (char) SMI_Comm_rank(comm);
    chan.root_rank = (char) root;
    chan.num_rank = (char) SMI_Comm_size(comm);
    chan.message_size = (unsigned int) count;

    if (chan.my_rank != chan.root_rank)
    {
        // At the beginning, send a "ready to receive" to the root
        // This is needed to not inter-mix subsequent collectives
        SET_HEADER_OP(chan.net.header, SMI_SYNCH);
        SET_HEADER_DST(chan.net.header, chan.root_rank);
        SET_HEADER_SRC(chan.net.header, chan.my_rank);
        SET_HEADER_PORT(chan.net.header, chan.port);
    }
    else
    {
        SET_HEADER_OP(chan.net.header, SMI_SYNCH);           // used to signal to the support kernel that a new broadcast has begun
        SET_HEADER_SRC(chan.net.header, chan.root_rank);
        SET_HEADER_PORT(chan.net.header, chan.port);         // used by destination
        SET_HEADER_NUM_ELEMS(chan.net.header, 0);            // at the beginning no data
    }

    return chan;
}
{%- endmacro -%}
