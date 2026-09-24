import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_monitor extends uvm_monitor;

  virtual axi_if vif;
  uvm_analysis_port #(axi_transaction) ap;

  `uvm_component_utils(axi_monitor)

  function new(string name = "axi_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set")
  endfunction

  task run_phase(uvm_phase phase);
    wait (vif.aresetn === 1'b1);
    fork
      collect_writes();
      collect_reads();
    join
  endtask

  task collect_writes();
    forever begin
      axi_transaction tr;
      @(posedge vif.aclk);
      if (vif.awvalid === 1'b1 && vif.awready === 1'b1) begin
        tr = axi_transaction::type_id::create("wr_tr");
        tr.dir   = axi_transaction::AXI_WRITE;
        tr.id    = vif.awid;
        tr.addr  = vif.awaddr;
        tr.len   = vif.awlen;
        tr.size  = vif.awsize;
        tr.burst = burst_t'(vif.awburst);
        collect_w(tr);
        collect_b(tr);
        ap.write(tr);
      end
    end
  endtask

  task collect_w(axi_transaction tr);
    int beat = 0;
    tr.data = new[tr.num_beats()];
    tr.strb = new[tr.num_beats()];
    while (beat < tr.num_beats()) begin
      @(posedge vif.aclk);
      if (vif.wvalid === 1'b1 && vif.wready === 1'b1) begin
        tr.data[beat] = vif.wdata;
        tr.strb[beat] = vif.wstrb;
        if (vif.wlast === 1'b1 && beat != tr.num_beats() - 1)
          `uvm_error(get_type_name(),
            $sformatf("WLAST early: beat %0d of %0d", beat, tr.num_beats()))
        if (vif.wlast !== 1'b1 && beat == tr.num_beats() - 1)
          `uvm_error(get_type_name(),
            $sformatf("WLAST missing on final beat %0d", beat))
        beat++;
      end
    end
  endtask

  task collect_b(axi_transaction tr);
    forever begin
      @(posedge vif.aclk);
      if (vif.bvalid === 1'b1 && vif.bready === 1'b1) begin
        tr.bresp = vif.bresp;
        if (vif.bid !== tr.id)
          `uvm_error(get_type_name(),
            $sformatf("BID mismatch: expected %0d got %0d", tr.id, vif.bid))
        break;
      end
    end
  endtask

  task collect_reads();
    forever begin
      axi_transaction tr;
      @(posedge vif.aclk);
      if (vif.arvalid === 1'b1 && vif.arready === 1'b1) begin
        tr = axi_transaction::type_id::create("rd_tr");
        tr.dir   = axi_transaction::AXI_READ;
        tr.id    = vif.arid;
        tr.addr  = vif.araddr;
        tr.len   = vif.arlen;
        tr.size  = vif.arsize;
        tr.burst = burst_t'(vif.arburst);
        collect_r(tr);
        ap.write(tr);
      end
    end
  endtask

  task collect_r(axi_transaction tr);
    int beat = 0;
    tr.rdata = new[tr.num_beats()];
    tr.rresp = new[tr.num_beats()];
    while (beat < tr.num_beats()) begin
      @(posedge vif.aclk);
      if (vif.rvalid === 1'b1 && vif.rready === 1'b1) begin
        tr.rdata[beat] = vif.rdata;
        tr.rresp[beat] = vif.rresp;
        if (vif.rid !== tr.id)
          `uvm_error(get_type_name(),
            $sformatf("RID mismatch: expected %0d got %0d", tr.id, vif.rid))
        if (vif.rlast === 1'b1 && beat != tr.num_beats() - 1)
          `uvm_error(get_type_name(),
            $sformatf("RLAST early: beat %0d of %0d", beat, tr.num_beats()))
        if (vif.rlast !== 1'b1 && beat == tr.num_beats() - 1)
          `uvm_error(get_type_name(),
            $sformatf("RLAST missing on final beat %0d", beat))
        beat++;
      end
    end
  endtask

endclass : axi_monitor
