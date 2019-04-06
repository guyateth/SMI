#include "smi/channel_helpers.h"

{% import 'kernel.cl' as kernel %}

#define RANK_COUNT {{ fpgas|length }}

// QSFP channels
#ifndef SMI_EMULATION_RANK
{% for channel in channels %}
channel SMI_Network_message io_out_{{ channel.index }} __attribute__((depth(16))) __attribute__((io("kernel_output_ch{{ channel.index }}")));
channel SMI_Network_message io_in_{{ channel.index }} __attribute__((depth(16))) __attribute__((io("kernel_input_ch{{ channel.index }}")));
{% endfor %}
#else
{% for fpga in fpgas %}
#if SMI_EMULATION_RANK == {{ fpga.rank }}
    {% for channel in range(channels_per_fpga) %}
channel SMI_Network_message io_out_{{ channel }} __attribute__((depth(16))) __attribute__((io("emulated_channel_{{ channel_name(fpga.channels[channel], true) }}")));
channel SMI_Network_message io_in_{{ channel }} __attribute__((depth(16))) __attribute__((io("emulated_channel_{{ channel_name(fpga.channels[channel], false) }}")));
    {% endfor %}
#endif
{% endfor %}
#endif

// internal routing tables
__constant char internal_sender_rt[{{ tag_count }}] = { {{ range(tag_count)|join(", ") }} };
__constant char internal_receiver_rt[{{ tag_count }}] = { {{ range(tag_count)|join(", ") }} };

channel SMI_Network_message channels_to_ck_s[{{ tag_count }}] __attribute__((depth(16)));
channel SMI_Network_message channels_from_ck_r[{{ tag_count }}] __attribute__((depth(16)));

__constant char QSFP_COUNT = {{ channels_per_fpga }};

// connect all CK_S together
channel SMI_Network_message channels_interconnect_ck_s[QSFP_COUNT*(QSFP_COUNT-1)] __attribute__((depth(16)));

// connect all CK_R together
channel SMI_Network_message channels_interconnect_ck_r[QSFP_COUNT*(QSFP_COUNT-1)] __attribute__((depth(16)));

// connect corresponding CK_S/CK_R pairs
channel SMI_Network_message channels_interconnect_ck_s_to_ck_r[QSFP_COUNT] __attribute__((depth(16)));

// connect corresponding CK_R/CK_S pairs
channel SMI_Network_message channels_interconnect_ck_r_to_ck_s[QSFP_COUNT] __attribute__((depth(16)));

#include "smi/pop.h"
#include "smi/push.h"

{% for channel in channels %}
{{ kernel.cks(channel, channels|length, target_index) }}
{{ kernel.ckr(channel, channels|length, target_index, tag_count) }}
{% endfor %}