import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;
class axi_coverage extends uvm_subscriber #(axi_transaction);

  bit                  sample_dir;
  bit [1:0]            sample_burst;
  bit [2:0]            sample_size;
  int unsigned         sample_beats;
  bit                  sample_aligned;
  bit [1:0]            sample_resp;

  `uvm_component_utils(axi_coverage)

  covergroup axi_cg;
    option.per_instance = 1;

    cp_operation: coverpoint sample_dir {
      bins read  = {axi_transaction::AXI_READ};
      bins write = {axi_transaction::AXI_WRITE};
    }

    cp_burst: coverpoint sample_burst {
      bins fixed = {BURST_FIXED};
      bins incr  = {BURST_INCR};
      bins wrap  = {BURST_WRAP};
    }

    cp_size: coverpoint sample_size {
      bins byte_size     = {0};
      bins halfword_size = {1};
      bins word_size     = {2};
      illegal_bins unsupported = default;
    }

    cp_length: coverpoint sample_beats {
      bins one       = {1};
      bins two_four  = {[2:4]};
      bins five_eight = {[5:8]};
      bins nine_sixteen = {[9:16]};
    }

    cp_alignment: coverpoint sample_aligned {
      bins unaligned = {0};
      bins aligned   = {1};
    }

    cp_response: coverpoint sample_resp {
      bins okay   = {RESP_OKAY};
      bins decerr = {RESP_DECERR};
      ignore_bins exokay = {RESP_EXOKAY};
      // No block in the design returns SLVERR, so the bin is unreachable.
      ignore_bins slverr = {RESP_SLVERR};
    }

    burst_x_size      : cross cp_burst, cp_size;
    // WRAP requires 2/4/8/16 beats per AXI spec, so the wrap x one cell is
    // unreachable.
    burst_x_length : cross cp_burst, cp_length {
      ignore_bins wrap_x_one = binsof(cp_burst.wrap) && binsof(cp_length.one);
    }
    direction_x_burst : cross cp_operation, cp_burst;
    direction_x_size  : cross cp_operation, cp_size;
    // A byte-sized transfer covers every lane of the word, so an unaligned
    // byte beat addresses all bytes anyway; the byte x unaligned cell is
    // unreachable.
    size_x_alignment : cross cp_size, cp_alignment {
      ignore_bins byte_x_unaligned =
        binsof(cp_size.byte_size) && binsof(cp_alignment.unaligned);
    }
    direction_x_resp  : cross cp_operation, cp_response;
  endgroup

  function new(string name = "axi_coverage", uvm_component parent = null);
    super.new(name, parent);
    axi_cg = new();
    axi_cg.set_inst_name(name);
  endfunction

  function void write(axi_transaction t);
    sample_dir     = t.dir;
    sample_burst   = t.burst;
    sample_size    = t.size;
    sample_beats   = t.num_beats();
    sample_aligned = t.is_aligned();
    if (t.dir == axi_transaction::AXI_WRITE)
      sample_resp = t.bresp;
    else if (t.rresp.size() != 0)
      sample_resp = t.rresp[t.rresp.size()-1];
    else
      sample_resp = RESP_DECERR;
    axi_cg.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
      $sformatf("FUNCTIONAL COVERAGE: %0.2f%%", axi_cg.get_inst_coverage()),
      UVM_NONE)
  endfunction

endclass : axi_coverage
