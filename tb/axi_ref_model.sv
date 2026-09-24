import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_ref_model extends uvm_component;

  bit [7:0] mem [bit [AXI_ADDR_W-1:0]];

  `uvm_component_utils(axi_ref_model)

  function new(string name = "axi_ref_model", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void apply_write(axi_transaction tr);
    for (int beat = 0; beat < tr.num_beats(); beat++) begin
      bit [AXI_ADDR_W-1:0] base = lane_base(tr.get_beat_addr(beat));
      for (int i = 0; i < AXI_STRB_W; i++)
        if (tr.strb[beat][i])
          mem[base + i] = tr.data[beat][i*8 +: 8];
    end
  endfunction

  function bit [AXI_DATA_W-1:0] predict_read(bit [AXI_ADDR_W-1:0] a);
    bit [AXI_ADDR_W-1:0]   base = lane_base(a);
    bit [AXI_DATA_W-1:0]   d    = '0;
    for (int i = 0; i < AXI_STRB_W; i++)
      d[i*8 +: 8] = mem.exists(base + i) ? mem[base + i] : 8'h00;
    return d;
  endfunction

endclass : axi_ref_model
