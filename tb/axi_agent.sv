import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_agent extends uvm_agent;

  axi_driver                       driver;
  axi_monitor                      monitor;
  uvm_sequencer #(axi_transaction) sequencer;

  `uvm_component_utils(axi_agent)

  function new(string name = "axi_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = axi_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      driver    = axi_driver::type_id::create("driver", this);
      sequencer = uvm_sequencer#(axi_transaction)::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass : axi_agent
