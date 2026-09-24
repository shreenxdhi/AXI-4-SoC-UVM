import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_driver extends uvm_driver #(axi_transaction);

  virtual axi_if vif;

  `uvm_component_utils(axi_driver)

  function new(string name = "axi_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set")
  endfunction

  task run_phase(uvm_phase phase);
    init_signals();
    wait (vif.aresetn === 1'b1);
    @(posedge vif.aclk);
    forever begin
      seq_item_port.get_next_item(req);
      drive(req);
      seq_item_port.item_done();
    end
  endtask

  task init_signals();
    vif.awvalid <= 1'b0;
    vif.wvalid  <= 1'b0;
    vif.bready  <= 1'b0;
    vif.arvalid <= 1'b0;
    vif.rready  <= 1'b0;
    vif.wlast   <= 1'b0;
  endtask

  task drive(axi_transaction tr);
    if (tr.dir == axi_transaction::AXI_WRITE) begin
      fork
        drive_aw(tr);
        drive_w(tr);
        drive_b(tr);
      join
    end
    else begin
      fork
        drive_ar(tr);
        drive_r(tr);
      join
    end
  endtask

  task drive_aw(axi_transaction tr);
    repeat (tr.addr_delay) @(posedge vif.aclk);
    vif.awid    <= tr.id;
    vif.awaddr  <= tr.addr;
    vif.awlen   <= tr.len;
    vif.awsize  <= tr.size;
    vif.awburst <= tr.burst;
    vif.awlock  <= 1'b0;
    vif.awcache <= 4'h0;
    vif.awprot  <= 3'h0;
    vif.awqos   <= 4'h0;
    vif.awvalid <= 1'b1;
    do @(posedge vif.aclk); while (vif.awready !== 1'b1);
    vif.awvalid <= 1'b0;
  endtask

  task drive_w(axi_transaction tr);
    for (int i = 0; i < tr.num_beats(); i++) begin
      repeat (tr.data_delay[i]) begin
        vif.wvalid <= 1'b0;
        @(posedge vif.aclk);
      end
      vif.wdata  <= tr.data[i];
      vif.wstrb  <= tr.strb[i];
      vif.wlast  <= (i == int'(tr.len));
      vif.wvalid <= 1'b1;
      do @(posedge vif.aclk); while (vif.wready !== 1'b1);
      vif.wvalid <= 1'b0;
      vif.wlast  <= 1'b0;
    end
  endtask

  task drive_b(axi_transaction tr);
    vif.bready <= 1'b1;
    do @(posedge vif.aclk); while (vif.bvalid !== 1'b1);
    tr.bresp   = vif.bresp;
    vif.bready <= 1'b0;
  endtask

  task drive_ar(axi_transaction tr);
    repeat (tr.addr_delay) @(posedge vif.aclk);
    vif.arid    <= tr.id;
    vif.araddr  <= tr.addr;
    vif.arlen   <= tr.len;
    vif.arsize  <= tr.size;
    vif.arburst <= tr.burst;
    vif.arlock  <= 1'b0;
    vif.arcache <= 4'h0;
    vif.arprot  <= 3'h0;
    vif.arqos   <= 4'h0;
    vif.arvalid <= 1'b1;
    do @(posedge vif.aclk); while (vif.arready !== 1'b1);
    vif.arvalid <= 1'b0;
  endtask

  task drive_r(axi_transaction tr);
    tr.rdata = new[tr.num_beats()];
    tr.rresp = new[tr.num_beats()];
    vif.rready <= 1'b1;
    for (int i = 0; i < tr.num_beats(); i++) begin
      do @(posedge vif.aclk); while (vif.rvalid !== 1'b1);
      tr.rdata[i] = vif.rdata;
      tr.rresp[i] = vif.rresp;
      if (vif.rid !== tr.id)
        `uvm_error(get_type_name(),
          $sformatf("RID mismatch: expected %0d got %0d", tr.id, vif.rid))
      if (vif.rlast === 1'b1 && i != int'(tr.len))
        `uvm_error(get_type_name(),
          $sformatf("RLAST asserted early on beat %0d of %0d", i,
                    tr.num_beats()))
      if (i == int'(tr.len) && vif.rlast !== 1'b1)
        `uvm_error(get_type_name(), "RLAST not asserted on final read beat")
    end
    vif.rready <= 1'b0;
  endtask

endclass : axi_driver
