{% import 'utils.cl' as utils %}

{%- macro smi_cks(program, channel, channel_count, target_index) -%}
__kernel void smi_kernel_cks_{{ channel.index }}(__global volatile char *restrict rt, const char num_ranks)
{
    {% set logical_ports = program.logical_port_count %}
    char external_routing_table[MAX_RANKS][{{ logical_ports }} /* logical port count */];
    
    #pragma loop_coalesce
    for (int i = 0; i < MAX_RANKS; i++)
    {
        for (int j = 0; j < {{ logical_ports }}; j++){
            if (i < num_ranks)
            {
                external_routing_table[i][j] = rt[i*{{ logical_ports }} + j];
            }
        }
    }

{% set allocations = program.get_channel_allocations_with_prefix(channel.index, "cks") %}
    // number of CK_S - 1 + CK_R + {{ allocations|length }} CKS hardware ports
    const char num_sender = {{ channel_count + allocations|length }};
    char sender_id = 0;
    SMI_Network_message message;

    char contiguous_reads = 0;

    while (1)
    {
        bool valid = false;
        switch (sender_id)
        {
            {% for ck_s in channel.neighbours() %}
            case {{ loop.index0 }}:
                // receive from CK_S_{{ ck_s }}
                message = read_channel_nb_intel(channels_interconnect_ck_s[{{ (channel_count - 1) * channel.index + loop.index0 }}], &valid);
                break;
            {% endfor %}
            case {{ channel_count - 1 }}:
                // receive from CK_R_{{ channel.index }}
                message = read_channel_nb_intel(channels_interconnect_ck_r_to_ck_s[{{ channel.index }}], &valid);
                break;
            {% for (op, key) in allocations %}
            case {{ channel_count + loop.index0 }}:
                // receive from {{ op }}
                message = read_channel_nb_intel({{ op.get_channel(key) }}, &valid);
                break;
            {% endfor %}
        }

        if (valid)
        {
            contiguous_reads++;
            char idx = external_routing_table[GET_HEADER_DST(message.header)][GET_HEADER_PORT(message.header)];
            switch (idx)
            {
                case 0:
                    // send to QSFP
                    write_channel_intel(io_out_{{ channel.index }}, message);
                    break;
                case 1:
                    // send to CK_R_{{ channel.index }}
                    write_channel_intel(channels_interconnect_ck_s_to_ck_r[{{ channel.index }}], message);
                    break;
                {% for ck_s in channel.neighbours() %}
                case {{ 2 + loop.index0 }}:
                    // send to CK_S_{{ ck_s }}
                    write_channel_intel(channels_interconnect_ck_s[{{ (channel_count - 1) * ck_s + target_index(ck_s, channel.index) }}], message);
                    break;
                {% endfor %}
            }
        }
        if (!valid || contiguous_reads == READS_LIMIT)
        {
            contiguous_reads = 0;
            sender_id++;
            if (sender_id == num_sender)
            {
                sender_id = 0;
            }
        }
    }
}
{%- endmacro %}
