import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_transaction extends uvm_sequence_item;

  typedef enum bit { AXI_READ, AXI_WRITE } direction_t;

  rand bit [AXI_ADDR_W-1:0] addr;
  rand bit [AXI_ID_W-1:0]   id;
  rand direction_t          dir;
  rand bit [7:0]            len;
  rand bit [2:0]            size;
  rand burst_t              burst;

  rand bit [AXI_DATA_W-1:0] data [];
  rand bit [AXI_STRB_W-1:0] strb [];

  bit [1:0]                 bresp;
  bit [1:0]                 rresp [];
  bit [AXI_DATA_W-1:0]      rdata [];

  rand int unsigned addr_delay;
  rand int unsigned data_delay [];

  `uvm_object_utils_begin(axi_transaction)
    `uvm_field_int (addr, UVM_ALL_ON)
    `uvm_field_int (id,   UVM_ALL_ON)
    `uvm_field_enum(direction_t, dir, UVM_ALL_ON)
    `uvm_field_int (len,  UVM_ALL_ON)
    `uvm_field_int (size, UVM_ALL_ON)
    `uvm_field_enum(burst_t, burst, UVM_ALL_ON)
    `uvm_field_array_int(data,  UVM_ALL_ON)
    `uvm_field_array_int(rdata, UVM_ALL_ON)
    `uvm_field_int (bresp, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "axi_transaction");
    super.new(name);
  endfunction

  constraint c_legal_size { size inside {[0:2]}; }

  constraint c_burst_type { burst inside {BURST_FIXED, BURST_INCR, BURST_WRAP}; }

  constraint c_len_range { len inside {[0:15]}; }

  constraint c_wrap_rules {
    (burst == BURST_WRAP) -> len inside {1, 3, 7, 15};
    (burst == BURST_WRAP && size == 1) -> addr[0]   == 1'b0;
    (burst == BURST_WRAP && size == 2) -> addr[1:0] == 2'b00;
  }

  constraint c_no_4k_cross {
    (burst == BURST_INCR) ->
      ((32'(addr[11:0]) - (32'(addr[11:0]) % (32'(1) << size)))
        + ((32'(len) + 1) << size)) <= 4096;
  }

  constraint c_payload_size {
    data.size()       == ((dir == AXI_WRITE) ? (len + 1) : 0);
    strb.size()       == data.size();
    data_delay.size() == len + 1;
  }

  constraint c_delays {
    addr_delay inside {[0:3]};
    foreach (data_delay[i]) data_delay[i] inside {[0:2]};
  }

  constraint c_default_region {
    soft addr inside {[SRAM_BASE : SRAM_BASE + SRAM_SIZE - 1]};
  }

  function void post_randomize();
    if (dir == AXI_WRITE)
      foreach (strb[i]) strb[i] = get_strobe(i);
  endfunction

  function int num_beats();      return int'(len) + 1; endfunction
  function int bytes_per_beat(); return 1 << size;     endfunction
  function bit is_aligned();     return (addr % bytes_per_beat()) == 0; endfunction

  function bit [AXI_ADDR_W-1:0] get_beat_addr(int beat);
    return beat_addr(addr, len, size, burst, beat);
  endfunction

  function bit [AXI_STRB_W-1:0] get_strobe(int beat);
    bit [AXI_STRB_W-1:0]   s  = '0;
    bit [AXI_ADDR_W-1:0]   ba = get_beat_addr(beat);
    int                    n  = bytes_per_beat();
    int                    lo, hi;
    if (beat == 0) begin
      lo = int'(ba % AXI_STRB_W);
      hi = ((lo / n) + 1) * n;
    end
    else begin
      lo = int'((ba - (ba % n)) % AXI_STRB_W);
      hi = lo + n;
    end
    for (int i = lo; i < hi && i < AXI_STRB_W; i++) s[i] = 1'b1;
    return s;
  endfunction

  function string convert2string();
    string burst_name = (burst == BURST_FIXED) ? "FIXED" :
                        (burst == BURST_INCR)  ? "INCR"  :
                        (burst == BURST_WRAP)  ? "WRAP"  : "RSVD";
    return $sformatf("%s addr=0x%08h id=%0d len=%0d(%0d beats) size=%0d(%0d B) burst=%s aligned=%0b",
                     dir.name(), addr, id, len, num_beats(), size,
                     bytes_per_beat(), burst_name, is_aligned());
  endfunction

endclass : axi_transaction
