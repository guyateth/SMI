{% macro bcast(program, op) -%}
__kernel void smi_kernel_bcast_{{ op.logical_port }}(char num_rank)
{
    bool external = true;
    char rcv;
    char root;
    char received_request = 0; // how many ranks are ready to receive
    const char num_requests = num_rank - 1;
    SMI_Network_message mess;
    {% set ckr_control = program.create_group(("ckr", "control")) %}
    {% set cks_data = program.create_group(("cks", "data")) %}
    {% set broadcast = program.create_group(("broadcast")) %}

    while (true)
    {
        if (external) // read from the application
        {
            mess = read_channel_intel(channels_bcast_send[{{ broadcast.get_hw_port(op.logical_port) }}]);
            if (GET_HEADER_OP(mess.header) == SMI_SYNCH)   // beginning of a broadcast, we have to wait for "ready to receive"
            {
                received_request = num_requests;
            }
            SET_HEADER_OP(mess.header, SMI_BROADCAST);
            rcv = 0;
            external = false;
            root = GET_HEADER_SRC(mess.header);
        }
        else // handle the request
        {
            if (received_request != 0)
            {
                SMI_Network_message req = read_channel_intel(channels_ckr_control[{{ ckr_control.get_hw_port(op.logical_port) }}]);
                received_request--;
            }
            else
            {
                if (rcv != root) // it's not me
                {
                    SET_HEADER_DST(mess.header, rcv);
                    SET_HEADER_PORT(mess.header, {{ op.logical_port }});
                    write_channel_intel(channels_cks_data[{{ cks_data.get_hw_port(op.logical_port) }}], mess);
                }
                rcv++;
                external = rcv == num_rank;
            }
        }
    }
}
{%- endmacro %}
