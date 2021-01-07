{% import 'utils.cl' as utils %}

{%- macro smi_bcast_kernel(program, op) -%}
__kernel void smi_kernel_bcast_{{ op.logical_port }}(char num_rank)
{
    while (true)
    {
        ;
    }
}
{%- endmacro %}

{%- macro smi_bcast_impl(program, op) -%}
void {{ utils.impl_name_port_type("SMI_Bcast", op) }}(SMI_BChannel* chan, void* data)
{
    char* conv = (char*)data;
    // NEW AND SHINY


    if(chan->init)  //send ready-to-receive to the parent
    {
        write_channel_intel({{ op.get_channel("cks_control") }}, chan->net);
        chan->init=false;
    }

    // here we wait for the ready messages from our children
    if(chan->waiting)
    {
        if (chan->child_one != -1) 
        {
            // may do sanity checks
            read_channel_intel({{ op.get_channel("ckr_control") }});
        }
        if (chan->child_two != -1) 
        {
            // may do sanity checks
            read_channel_intel({{ op.get_channel("ckr_control") }});
        }
        
        chan->waiting=false;
    }

    if (chan->my_rank == chan->root_rank) // I'm the root
    {
        const unsigned int message_size = chan->message_size;
        chan->processed_elements++;

        //Copy data to network message. This is done explicitely to avoid internal compiler errors.
        char* data_snd = chan->net_2.data;
        #pragma unroll
        for (char jj = 0; jj < {{ op.data_size() }}; jj++)
        {
            data_snd[chan->packet_element_id * {{ op.data_size() }} + jj] = conv[jj];
        }

        chan->packet_element_id++;
        // send the network packet if it is full or we reached the message size
        if (chan->packet_element_id == chan->elements_per_packet || chan->processed_elements == message_size)
        {
            SET_HEADER_NUM_ELEMS(chan->net_2.header, chan->packet_element_id);
            SET_HEADER_PORT(chan->net_2.header, {{ op.logical_port }});
            chan->packet_element_id = 0;

            // send two messages to my children
            if (chan->child_one != -1){
                SET_HEADER_SRC(chan->net_2.header, chan->my_rank);
                SET_HEADER_DST(chan->net_2.header, chan->child_one);
                write_channel_intel({{ op.get_channel("cks_data") }}, chan->net_2);
            }
            if (chan->child_two != -1){
                SET_HEADER_DST(chan->net_2.header, chan->child_one);
                write_channel_intel({{ op.get_channel("cks_data") }}, chan->net_2);
            }
        }
    } 
    else // im not the root
    {
        if (chan->packet_element_id_rcv == 0)
        {
            chan->net_2 = read_channel_intel({{ op.get_channel("ckr_data") }});
            // send two messages to my children
            if (chan->child_one != -1){
                SET_HEADER_SRC(chan->net_2.header, chan->my_rank);
                SET_HEADER_DST(chan->net_2.header, chan->child_one);
                write_channel_intel({{ op.get_channel("cks_data") }}, chan->net_2);
            }
            if (chan->child_two != -1){
                SET_HEADER_DST(chan->net_2.header, chan->child_one);
                write_channel_intel({{ op.get_channel("cks_data") }}, chan->net_2);
            }
        }


        //Copy data from network message. This is done explicitely to avoid internal compiler errors.

        #pragma unroll
        for (int ee = 0; ee < {{ op.data_elements_per_packet() }}; ee++) { 
            if (ee == chan->packet_element_id_rcv) { 
                #pragma unroll
                for (int jj = 0; jj < {{ op.data_size() }}; jj++) { 
                        ((char *)conv)[jj] = chan->net_2.data[(ee * {{ op.data_size() }}) + jj]; 
                } 
            } 
        } 
        chan->packet_element_id_rcv++;
        if (chan->packet_element_id_rcv == chan->elements_per_packet)
        {
            chan->packet_element_id_rcv = 0;
        }        

    }


    
}
{%- endmacro %}

{%- macro smi_bcast_channel(program, op) -%}
SMI_BChannel {{ utils.impl_name_port_type("SMI_Open_bcast_channel", op) }}(int count, SMI_Datatype data_type, int port, int root, SMI_Comm comm)
{
    SMI_BChannel chan;
    // setup channel descriptor
    chan.message_size = count;
    chan.data_type = data_type;
    chan.port = (char) port;
    chan.my_rank = (char) SMI_Comm_rank(comm);
    chan.root_rank = (char) root;
    chan.num_rank = (char) SMI_Comm_size(comm);
    chan.init = true;
    chan.size_of_type = {{ op.data_size() }};
    chan.elements_per_packet = {{ op.data_elements_per_packet() }};



    SET_HEADER_OP(chan.net.header, SMI_SYNCH);           // used to signal to the support kernel that a new broadcast has begun
    SET_HEADER_SRC(chan.net.header, chan.root_rank);
    SET_HEADER_PORT(chan.net.header, chan.port);         // used by destination
    SET_HEADER_DST(chan.net.header, chan.my_rank);       // since we offload to support kernel
    

    // now we generate the next element, as well as the parent element
    // this builds the tree structure
    // we build a standard tree, and switch 0 and the root element (here, root = 1)
    //         0                 1
    //        / \               / \ 
    //       1   2             0   2
    //      / \ / \           / \ / \ 
    //     3  4 5  6         3  4 5  6 
    //
    if (chan.root_rank == chan.my_rank){
        // i am the root
        SET_HEADER_NUM_ELEMS(chan.net.header, 0);            // at the beginning no data

        chan.child_one = 1;
        // remove child if out of bounds
        if (chan.child_one >= chan.num_rank) chan.child_one = -1;
        chan.child_two = 2;
        // remove child if out of bounds
        if (chan.child_two >= chan.num_rank) chan.child_two = -1;
    } else if (chan.my_rank == 0 {
        // special case for ranks where rank is == 0, but they arent the root
        chan.my_parent = ((chan.root_rank + 1) / 2) - 1;

        chan.child_one = ((chan.root_rank * 2) + 1);
        // remove child if out of bounds
        if (chan.child_one >= chan.num_rank) chan.child_one = -1;
        chan.child_two = ((chan.root_rank * 2) + 2);
        // remove child if out of bounds
        if (chan.child_two >= chan.num_rank) chan.child_two = -1;
    } else {
        // i am not the root
        chan.my_parent = ((chan.my_rank + 1) / 2) - 1;

        chan.child_one = ((chan.my_rank * 2) + 1);
        // remove child if out of bounds
        if (chan.child_one >= chan.num_rank) chan.child_one = -1;
        // if the child would be the root, replace with 0
        if (chan.child_one == chan.root_rank) chan.child_one = 0;
        chan.child_two = ((chan.my_rank * 2) + 2);
        // remove child if out of bounds
        if (chan.child_two >= chan.num_rank) chan.child_two = -1;
        // if the child would be the root, replace with 0
        if (chan.child_two == chan.root_rank) chan.child_two = 0;
    }
    
    chan.processed_elements = 0;
    chan.packet_element_id = 0;
    chan.packet_element_id_rcv = 0;
    return chan;
}
{%- endmacro -%}
