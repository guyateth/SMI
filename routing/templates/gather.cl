{% import 'utils.cl' as utils %}

{% macro smi_gather(program, op) -%}
__kernel void smi_kernel_gather_{{ op.logical_port }}(char num_rank)
{
    //receives the data from the application and
    //forwards it to the root only when the SYNCH message arrives
    SMI_Network_message mess;
    {% set ckr_control = program.create_group("ckr_control") %}
    {% set cks_data = program.create_group("cks_data") %}
    {% set scatter = program.create_group("gather") %}
    
    while(true)
    {

        mess=read_channel_intel({{ utils.channel_array("gather") }}[{{ scatter.get_hw_port(op.logical_port) }}]);
        if(GET_HEADER_OP(mess.header)==SMI_SYNCH)
        {
            
            SMI_Network_message req=read_channel_intel({{ utils.channel_array("ckr_control") }}[{{ ckr_control.get_hw_port(op.logical_port) }}]);
        }
        SET_HEADER_OP(mess.header,SMI_GATHER);
        //TODO: understand how to enable this without incurring in II penalties
        //mem_fence(CLK_CHANNEL_MEM_FENCE);
        write_channel_intel({{ utils.channel_array("cks_data") }}[{{ cks_data.get_hw_port(op.logical_port) }}], mess);
    }
}
{%- endmacro %}
