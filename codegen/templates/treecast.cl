{% import 'utils.cl' as utils %}

{%- macro smi_treecast_kernel(program, op) -%}
__kernel void smi_kernel_bcast_{{ op.logical_port }}(char num_rank)
{
    char stage = 0;
    char rcv;
    char root;
    char my_rank;
    char my_parent;
    char child_one;
    char child_two;
    bool sent_one = false;
    bool sent_two = false;
    char received_request = 0; // how many ranks are ready to receive
    char num_requests = 0;
    SMI_Network_message mess;
    SMI_Network_message mess_data;
    char init;
    int total_elems = 0;
    int remaining_elems = 0;

    while (true)
    {
        if (stage == 0) // read from the application (STAGE = INIT)
        {
            mess = read_channel_intel({{ op.get_channel("treecast_send") }});

            
            my_rank = GET_HEADER_SRC(mess.header);
            child_one = mess.data[0];
            child_two = mess.data[1];
            my_parent = mess.data[2];

            total_elems = * (((int*) mess.data) + 1);
            remaining_elems = total_elems;

            if (GET_HEADER_OP(mess.header) == SMI_SYNCH)   // beginning of a treecast
            {
                if (child_one != -1) num_requests ++;
                if (child_two != -1) num_requests ++;
                received_request = num_requests;
            }
            
            if (my_parent == -1) // i am the root
            {
                //
                stage = 2;
                printf("END OF STAGE 0 ROOT; %d %d %d %d %d %d\n", my_rank, my_parent, child_one, child_two, num_requests, total_elems);
            }
            else // i am not the root
            {
                stage = 2;
                printf("END OF STAGE 0 NONROOT; %d %d %d %d %d %d\n", my_rank, my_parent, child_one, child_two, num_requests, total_elems);
            }
        }
        else if (stage == 2) // wait for readies from all children (STAGE = WAIT_CHILDREN)
        {
            if (received_request != 0) // we wait for pending requests
            {
                //printf("WAITING RR; %d %d %d %d %d\n", my_rank, my_parent, child_one, child_two, received_request);
                SMI_Network_message req = read_channel_intel({{ op.get_channel("ckr_control") }});
                //printf("GOT RR; %d %d %d %d %d\n", my_rank, my_parent, child_one, child_two, received_request);
                received_request--;
            }
            else 
            {
                printf("ALL CHILDREN READY ON RANK %d \n", my_rank);
                if (my_parent == -1) // i am the root
                {
                    stage = 5;
                }
                else // i am not the root
                {
                    stage = 3;
                }
            }
        }
        else if (stage == 3) // send ready to recv to parent (STAGE = SEND_READY)
        {   
            SET_HEADER_DST(mess.header, my_parent);
            SET_HEADER_PORT(mess.header, {{ op.logical_port }});
            SET_HEADER_OP(mess_data.header, SMI_SYNCH);
            write_channel_intel({{ op.get_channel("cks_control") }}, mess);
            //printf("SENT RR; %d %d %d %d\n", my_rank, my_parent, child_one, child_two);
            stage = 6;
        }
        else if (stage == 4) // send data to children (STAGE = ROOT_SEND)
        {
            // we send to our children
            if (!sent_one && child_one != -1 || !sent_two && child_two != -1)
            {
                if (!sent_one && child_one != -1)
                {
                    SET_HEADER_DST(mess_data.header, child_one);
                    SET_HEADER_PORT(mess_data.header, {{ op.logical_port }});
                    sent_one = true;
                }
                else if (!sent_two && child_two != -1)
                {
                    SET_HEADER_DST(mess_data.header, child_two);
                    SET_HEADER_PORT(mess_data.header, {{ op.logical_port }});
                    sent_two = true;
                }

                write_channel_intel({{ op.get_channel("cks_data") }}, mess_data);
            }
            else
            {   
                sent_one = sent_two = false;
                if (my_parent == -1) {
                    stage = 5;
                }
                else
                {
                    SET_HEADER_DST(mess_data.header, my_rank);
                    SET_HEADER_PORT(mess_data.header, {{ op.logical_port }});
                    write_channel_intel({{ op.get_channel("treecast_recv") }}, mess_data);
                    stage = 6;
                }
            }
        }
        else if (stage == 5) // wait for new data (STAGE = ROOT_RECV)
        {
            if (remaining_elems <= 0) {
                printf("EOT IN ROOT \n");
                stage = 0;
            } else {
                mess_data = read_channel_intel({{ op.get_channel("treecast_data") }});
                remaining_elems -= GET_HEADER_NUM_ELEMS(mess_data.header);
                printf("GOT FROM APP; %d %d %d %d %d %d\n", my_rank, my_parent, child_one, child_two, GET_HEADER_NUM_ELEMS(mess_data.header), remaining_elems);
                SET_HEADER_OP(mess_data.header, SMI_BROADCAST);
                stage = 4;
            }

        }

        else if (stage == 6) // wait for new data (STAGE = CHILD_RECV)
        {
            if (remaining_elems <= 0) {
                printf("EOT IN CHILD %d \n", my_rank);
                stage = 0;
            } else {
                mess_data = read_channel_intel({{ op.get_channel("ckr_data") }});
                remaining_elems -= GET_HEADER_NUM_ELEMS(mess_data.header);
                //printf("GOT FROM PARENT; %d %d %d %d\n", my_rank, my_parent, child_one, child_two);
                SET_HEADER_OP(mess_data.header, SMI_BROADCAST);
                stage = 4;
            }
        }
    }
}
{%- endmacro %}

{%- macro smi_treecast_impl(program, op) -%}
void {{ utils.impl_name_port_type("SMI_Treecast", op) }}(SMI_TreecastChannel* chan, void* data)
{
    char* conv = (char*)data;

    if(chan->init)  // send setup to support kern
        {
            chan->net.data[0] = chan->child_one;
            chan->net.data[1] = chan->child_two;
            chan->net.data[2] = chan->my_parent;
            int* num_req_place = ((int*) chan->net.data) + 1;
            *num_req_place = chan->message_size;

            write_channel_intel({{ op.get_channel("treecast_send") }}, chan->net);
            chan->init=false;
        }
    if (chan->my_rank == chan->root_rank) // I'm the root
    {

        const unsigned int message_size = chan->message_size;
        chan->processed_elements++;

        //Copy data to network message. This is done explicitely to avoid internal compiler errors.
        char* data_snd = chan->net.data;
        #pragma unroll
        for (char jj = 0; jj < {{ op.data_size() }}; jj++)
        {
            data_snd[chan->packet_element_id * {{ op.data_size() }} + jj] = conv[jj];
        }

        chan->packet_element_id++;
        // send the network packet if it is full or we reached the message size
        if (chan->packet_element_id == chan->elements_per_packet || chan->processed_elements == message_size)
        {
            SET_HEADER_NUM_ELEMS(chan->net.header, chan->packet_element_id);
            SET_HEADER_PORT(chan->net.header, {{ op.logical_port }});
            chan->packet_element_id = 0;

            // offload to support kernel
            write_channel_intel({{ op.get_channel("treecast_data") }}, chan->net);
            SET_HEADER_OP(chan->net.header, SMI_BROADCAST);  // for the subsequent network packets
        }
    }
    else // I have to receive
    {
        if (chan->packet_element_id_rcv == 0)
        {
            chan->net_2 = read_channel_intel({{ op.get_channel("treecast_recv") }});
            //printf("Got message at %d\n", chan->my_rank);
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

{%- macro smi_treecast_channel(program, op) -%}
SMI_TreecastChannel {{ utils.impl_name_port_type("SMI_Open_treecast_channel", op) }}(int count, SMI_Datatype data_type, int port, int root, SMI_Comm comm)
{
    SMI_TreecastChannel chan;
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
    SET_HEADER_SRC(chan.net.header, chan.my_rank);
    SET_HEADER_PORT(chan.net.header, chan.port);         // used by destination
           // since we offload to support kernel
    

    // now we generate the next element, as well as the parent element
    // this builds the tree structure
    // we build a standard tree, and switch 0 and the root element (here, root = 1)
    //         0                 1       |
    //        / \               / \      |
    //       1   2             0   2     |
    //      / \ / \           / \ / \    |
    //     3  4 5  6         3  4 5  6   |
    //
    if (chan.root_rank == chan.my_rank){
        // i am the root
        SET_HEADER_NUM_ELEMS(chan.net.header, 0);            // at the beginning no data
        chan.my_parent = -1;
        chan.child_one = 1;
        // remove child if out of bounds
        if (chan.child_one >= chan.num_rank) chan.child_one = -1;
        chan.child_two = 2;
        // remove child if out of bounds
        if (chan.child_two >= chan.num_rank) chan.child_two = -1;
    } else if (chan.my_rank == 0) {
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

    SET_HEADER_DST(chan.net.header, chan.my_rank);
    
    chan.processed_elements = 0;
    chan.packet_element_id = 0;
    chan.packet_element_id_rcv = 0;
    return chan;
}
{%- endmacro -%}
