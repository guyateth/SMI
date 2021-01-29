{% import 'utils.cl' as utils %}

{%- macro smi_treereduce_kernel(program, op) -%}
#include "smi/reduce_operations.h"

__kernel void smi_kernel_treereduce_{{ op.logical_port }}(char num_rank)
{
    __constant int SHIFT_REG = {{ op.shift_reg() }};

    char my_rank;
    char my_parent;
    char child_one;
    char child_two;

    char received_request = 0; // how many ranks are ready to receive
    char num_children = 1; // we have at elast one, the app
    SMI_Network_message mess;
    SMI_Network_message reduce;
    SMI_Network_message reduce_result_downtree;

    int remaining_elems;

    const char credits_flow_control = 16; // choose it in order to have II=1
    {{ op.data_type }} __attribute__((register)) reduce_result[credits_flow_control][SHIFT_REG + 1];
    char data_recvd[credits_flow_control];

    char sender_id = 0;
    char add_to[MAX_RANKS];   // for each rank tells to what element in the buffer we should add the received item

    char current_buffer_element = 0;
    char add_to_root = 0;
    char contiguos_reads = 0;
    int stage = 0;

    bool init = false;
    bool reduce_mess_ready = false;
    bool sent_one = false;
    bool sent_two = false;

    for (int i = 0;i < credits_flow_control; i++)
    {
        data_recvd[i] = 0;
        #pragma unroll
        for(int j = 0; j < SHIFT_REG + 1; j++)
        {
            reduce_result[i][j] = {{ op.shift_reg_init() }};
        }
    }

    int cntr = 0;
    while (true)
    {
        if (!init)
        {
            // here we do the initialization of all the variables
            mess = read_channel_intel({{ op.get_channel("treereduce_init") }});

            
            my_rank = GET_HEADER_SRC(mess.header);
            child_one = mess.data[0];
            child_two = mess.data[1];
            my_parent = mess.data[2];

            remaining_elems = * (((int*) mess.data) + 1);
            num_children = 1;

            if (GET_HEADER_OP(mess.header) == SMI_SYNCH)   // beginning of a treecast
            {
                if (child_one != -1) num_children ++;
                if (child_two != -1) num_children ++;
                received_request = num_children;
            }
            printf("END OF INIT; %d %d %d %d %d %d\n", my_rank, my_parent, child_one, child_two, received_request, remaining_elems);
            init = true;
            #pragma unroll
            for (int i = 0; i < MAX_RANKS; i++)
            {
                add_to[i] = 0;
            }
            current_buffer_element = 0;
        }
        bool valid = false;

        if (stage == 0)
        {
        
            switch (sender_id)
            {   // for the root, I have to receive from both sides
                case 0:
                    mess = read_channel_nb_intel({{ op.get_channel("treereduce_send") }}, &valid);
                    break;
                case 1: // read from CK_R, can be done by the root and by the non-root
                    mess = read_channel_nb_intel({{ op.get_channel("ckr_data") }}, &valid);
                    break;
                case 2:
                    reduce_result_downtree = read_channel_nb_intel({{ op.get_channel("ckr_control") }}, &valid);
                    break;
            }

            if (valid)
            {
                char a;
                if (sender_id == 0)
                {
                    // received root contribution to the reduced result
                    // apply reduce
                    char* ptr = mess.data;
                    {{ op.data_type }} data= *({{ op.data_type }}*) (ptr);
                    reduce_result[add_to_root][SHIFT_REG] = {{ op.reduce_op() }}(data, reduce_result[add_to_root][0]); // apply reduce
                    #pragma unroll
                    for (int j = 0; j < SHIFT_REG; j++)
                    {
                        reduce_result[add_to_root][j] = reduce_result[add_to_root][j + 1];
                    }

                    data_recvd[add_to_root]++;
                    a = add_to_root;

                    printf("MESSAGE FROM APP; %d FROM: %d; TOTAL: %d SHIFT REG: %d\n", my_rank, my_rank, data_recvd[add_to_root], add_to_root);

                    add_to_root++;
                    if (add_to_root == credits_flow_control)
                    {
                        add_to_root = 0;
                    }
                }
                else if (sender_id == 1)
                {
                    // received contribution from a non-root rank, apply reduce operation
                    char* ptr = mess.data;
                    char rank = GET_HEADER_SRC(mess.header);
                    {{ op.data_type }} data = *({{ op.data_type }}*)(ptr);
                    char addto = add_to[rank];
                    data_recvd[addto]++;
                    a = addto;
                    reduce_result[addto][SHIFT_REG] = {{ op.reduce_op() }}(data, reduce_result[addto][0]);        // apply reduce
                    #pragma unroll
                    for (int j = 0; j < SHIFT_REG; j++)
                    {
                        reduce_result[addto][j] = reduce_result[addto][j + 1];
                    }

                    printf("MESSAGE FROM CHILD; %d FROM: %d; TOTAL: %d SHIFT REG: %d VAL: %d\n", my_rank, rank, data_recvd[addto], addto, *data);

                    addto++;
                    if (addto == credits_flow_control)
                    {
                        addto = 0;
                    }
                    add_to[rank] = addto;
                }
                else if (sender_id == 2)
                {
                    printf("MESSAGE FROM PARENT - FORWARDING; %d %d \n", my_rank, my_parent);
                    // recieved a credit from parent, forward to my children and app
                    stage = 2;
                }

                if (data_recvd[current_buffer_element] == num_children) 
                {
                    // we need to send the current buffer element to our children
                    printf("ALL CONTRIBUTIONS RECIEVED; %d \n", my_rank);
                    stage = 1;
                }
            }

            if (sender_id == 0) sender_id = 1;
            else if (sender_id == 1) sender_id = 2;
            else if (sender_id == 2) sender_id = 0;
            valid = false;
        }

        else if (stage == 1)
        {
            // We received all the contributions, we can send result to application
            char* data_snd;
            if (my_parent != -1) data_snd = reduce.data;
            else data_snd = reduce_result_downtree.data;
            // Build reduced result
            {{ op.data_type }} res = {{ op.shift_reg_init() }};
            #pragma unroll
            for (int i = 0; i < SHIFT_REG; i++)
            {
                res = {{ op.reduce_op() }}(res,reduce_result[current_buffer_element][i]);
            }
            char* conv = (char*)(&res);
            #pragma unroll
            for (int jj = 0; jj < {{ op.data_size() }}; jj++) // copy the data
            {
                data_snd[jj] = conv[jj];
            }
            reduce_mess_ready = true;
            data_recvd[current_buffer_element] = 0;

            //reset shift register
            #pragma unroll
            for (int j = 0; j < SHIFT_REG + 1; j++)
            {
                reduce_result[current_buffer_element][j] =  {{ op.shift_reg_init() }};
            }
            current_buffer_element++;
            if (current_buffer_element == credits_flow_control)
            {
                current_buffer_element = 0;
            }
            

            // we send to our parent
            if (my_parent != -1) // im not the root, send to parent
            {
                SET_HEADER_DST(reduce.header, my_parent);
                SET_HEADER_PORT(reduce.header, {{ op.logical_port }});
                SET_HEADER_SRC(reduce.header, my_rank);
                SET_HEADER_OP(reduce.header, SMI_REDUCE);
                SET_HEADER_NUM_ELEMS(reduce.header,1);
                printf("MESSAGE TO PARENT; %d -> %d CBE: %d\n", my_rank, my_parent, current_buffer_element);
                write_channel_intel({{ op.get_channel("cks_data") }}, reduce);
                stage = 0;
            } 
            else 
            {
                stage = 2; // if we're root we prepare to send to the children
            }
        } 
        else if (stage == 2) // this is the send to children and app rank
        {
            if ((!sent_one && child_one != -1) || (!sent_two && child_two != -1))
            {
                if (!sent_one && child_one != -1)
                {
                    SET_HEADER_DST(reduce_result_downtree.header, child_one);
                    sent_one = true;
                }
                else if (!sent_two && child_two != -1)
                {
                    SET_HEADER_DST(reduce_result_downtree.header, child_two);
                    sent_two = true;
                }
                SET_HEADER_NUM_ELEMS(reduce_result_downtree.header,1);
                SET_HEADER_SRC(reduce_result_downtree.header,my_rank);
                SET_HEADER_PORT(reduce_result_downtree.header, {{ op.logical_port }});
                SET_HEADER_OP(reduce_result_downtree.header, SMI_SYNCH);
                write_channel_intel({{ op.get_channel("cks_control") }}, reduce_result_downtree);
                printf("MESSAGE TO CHILD; %d -> %d CBE: %d\n", my_rank, GET_HEADER_DST(reduce_result_downtree.header), current_buffer_element);
            }
            else
            {   
                sent_one = sent_two = false;
                stage = 0;

                SET_HEADER_NUM_ELEMS(reduce_result_downtree.header,1);
                SET_HEADER_SRC(reduce_result_downtree.header,my_rank);
                SET_HEADER_DST(reduce_result_downtree.header, my_rank);
                SET_HEADER_PORT(reduce_result_downtree.header, {{ op.logical_port }});
                SET_HEADER_OP(reduce_result_downtree.header, SMI_SYNCH);
                printf("MESSAGE TO APP; %d -> %d CBE: %d\n", my_rank, GET_HEADER_DST(reduce_result_downtree.header), current_buffer_element);
                write_channel_intel({{ op.get_channel("treereduce_recv") }}, reduce_result_downtree);
                remaining_elems --;
                if (remaining_elems == 0) init = false;
                
            }
        }      
    }

        
}
{%- endmacro %}

{%- macro smi_treereduce_impl(program, op) -%}
void {{ utils.impl_name_port_type("SMI_Treereduce", op) }}(SMI_TreereduceChannel* chan,  void* data_snd, void* data_rcv)
{
    if(chan->init)  // send setup to support kern
    {
        chan->net.data[0] = chan->child_one;
        chan->net.data[1] = chan->child_two;
        chan->net.data[2] = chan->my_parent;

        int num_mes = (chan->message_size);

        int* num_req_place = ((int*) chan->net.data) + 1;
        *num_req_place = num_mes;

        write_channel_intel({{ op.get_channel("treereduce_init") }}, chan->net);
        chan->init=false;
    }

    char* conv = (char*) data_snd;
    // copy data to the network message
    COPY_DATA_TO_NET_MESSAGE(chan, chan->net,conv);

    // In this case we disabled network packetization: so we can just send the data as soon as we have it
    SET_HEADER_NUM_ELEMS(chan->net.header, 1);

    // spinlock, where we wait for the support kernel to be ready for new meassges
    while (chan->creds <= 0) {
        ;
    }

    chan->creds --;
    SET_HEADER_OP(chan->net.header, SMI_REDUCE);          // set the operation
    write_channel_intel({{ op.get_channel("treereduce_send") }}, chan->net);
    mem_fence(CLK_CHANNEL_MEM_FENCE);
    chan->net_2 = read_channel_intel({{ op.get_channel("treereduce_recv") }});
    // copy data from the network message to user variable

    if (chan->my_rank == chan->root_rank) // I'm the root
    {
        COPY_DATA_FROM_NET_MESSAGE(chan, chan->net_2, data_rcv);
        int *conv_int = (int *) data_rcv;
        printf("We recieved a total on root: %d\n", *conv_int);
    }
    

    chan->creds ++;
}
{%- endmacro %}

{%- macro smi_treereduce_channel(program, op) -%}
SMI_TreereduceChannel {{ utils.impl_name_port_type("SMI_Open_treereduce_channel", op) }}(int count, SMI_Datatype data_type, SMI_Op op, int port, int root, SMI_Comm comm)
{
    SMI_TreereduceChannel chan;
    // setup channel descriptor
    chan.message_size = (unsigned int) count;
    chan.data_type = data_type;
    chan.port = (char) port;
    chan.my_rank = (char) SMI_Comm_rank(comm);
    chan.root_rank = (char) root;
    chan.num_rank = (char) SMI_Comm_size(comm);
    chan.reduce_op = (char) op;
    chan.init = true;
    chan.size_of_type = {{ op.data_size() }};
    chan.elements_per_packet = 1;
    chan.creds = 16;



    SET_HEADER_OP(chan.net.header, SMI_SYNCH);           // used to signal to the support kernel that a new broadcast has begun
    SET_HEADER_SRC(chan.net.header, chan.my_rank);
    SET_HEADER_PORT(chan.net.header, chan.port);         // used by destination
    SET_HEADER_NUM_ELEMS(chan.net.header, 0);            // at the beginning no data
           // since we offload to support kernel
    

    // now we generate the next element, as well as the parent element
    // this builds the tree structure
    // we build a standard tree, and switch 0 and the root element (here, root = 5)
    //         0                 5       |
    //        / \               / \      |
    //       1   2             1   2     |
    //      / \ / \           / \ / \    |
    //     3  4 5  6         3  4 0  6   |
    //
    if (chan.root_rank == chan.my_rank){
        // i am the root
        chan.my_parent = -1;
        chan.child_one = 1;
        // remove child if out of bounds
        if (chan.child_one >= chan.num_rank) chan.child_one = -1;
        chan.child_two = 2;
        // remove child if out of bounds
        if (chan.child_two >= chan.num_rank) chan.child_two = -1;
        // these two special cases are hardcoded
        if (chan.root_rank == 1) chan.child_one = 0;
        if (chan.root_rank == 2) chan.child_two = 0;
    } else if (chan.my_rank == 0) {
        // special case for ranks where rank is == 0, but they arent the root
        chan.my_parent = ((chan.root_rank + 1) / 2) - 1;
        if (chan.my_parent == 0) chan.my_parent = chan.root_rank;

        chan.child_one = ((chan.root_rank * 2) + 1);
        // remove child if out of bounds
        if (chan.child_one >= chan.num_rank) chan.child_one = -1;
        chan.child_two = ((chan.root_rank * 2) + 2);
        // remove child if out of bounds
        if (chan.child_two >= chan.num_rank) chan.child_two = -1;
    } else {
        // i am not the root
        chan.my_parent = ((chan.my_rank + 1) / 2) - 1;
        if (chan.my_parent == 0 && chan.root_rank != 0) chan.my_parent = chan.root_rank;
        else if (chan.my_parent == chan.root_rank && chan.root_rank != 0) chan.my_parent = 0;

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
