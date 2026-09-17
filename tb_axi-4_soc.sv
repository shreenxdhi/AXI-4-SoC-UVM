// AXI4 UVM testbench
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
      bins slverr = {RESP_SLVERR};
      bins decerr = {RESP_DECERR};
      ignore_bins exokay = {RESP_EXOKAY};
    }

    burst_x_size      : cross cp_burst, cp_size;
    burst_x_length    : cross cp_burst, cp_length;
    direction_x_burst : cross cp_operation, cp_burst;
    direction_x_size  : cross cp_operation, cp_size;
    size_x_alignment  : cross cp_size, cp_alignment;
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


class axi_scoreboard extends uvm_scoreboard;

  axi_ref_model ref_model;
  uvm_analysis_imp #(axi_transaction, axi_scoreboard) ap_imp;

  int unsigned n_writes, n_reads;
  int unsigned n_write_beats, n_read_beats;
  int unsigned n_data_mismatch, n_resp_mismatch;

  `uvm_component_utils(axi_scoreboard)

  function new(string name = "axi_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    ap_imp = new("ap_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ref_model = axi_ref_model::type_id::create("ref_model", this);
  endfunction

  function void write(axi_transaction tr);
    if (tr.dir == axi_transaction::AXI_WRITE) check_write(tr);
    else                                      check_read(tr);
  endfunction

  function void check_write(axi_transaction tr);
    slave_t target = decode_addr(tr.addr);
    string resp_str;
    n_writes++;
    n_write_beats += tr.num_beats();
    if (target == SLV_SRAM) begin
      resp_str = (tr.bresp == RESP_OKAY)   ? "OKAY"   :
                 (tr.bresp == RESP_SLVERR) ? "SLVERR" :
                 (tr.bresp == RESP_DECERR) ? "DECERR" : "EXOKAY";
      if (tr.bresp !== RESP_OKAY) begin
        `uvm_error(get_type_name(),
          $sformatf({"RESPONSE_MISMATCH\n",
                     "id=%0d burst=%s start_addr=0x%08h\n",
                     "expected=OKAY actual=%s"},
                    tr.id, burst_to_string(tr.burst), tr.addr, resp_str))
        n_resp_mismatch++;
      end
      else begin
        ref_model.apply_write(tr);
        `uvm_info(get_type_name(),
          $sformatf("WRITE ok  %s", tr.convert2string()), UVM_MEDIUM)
      end
    end
    else begin
      resp_str = (tr.bresp == RESP_OKAY)   ? "OKAY"   :
                 (tr.bresp == RESP_SLVERR) ? "SLVERR" :
                 (tr.bresp == RESP_DECERR) ? "DECERR" : "EXOKAY";
      if (tr.bresp !== RESP_DECERR) begin
        `uvm_error(get_type_name(),
          $sformatf({"RESPONSE_MISMATCH\n",
                     "id=%0d burst=%s start_addr=0x%08h\n",
                     "expected=DECERR actual=%s"},
                    tr.id, burst_to_string(tr.burst), tr.addr, resp_str))
        n_resp_mismatch++;
      end
    end
  endfunction

  function void check_read(axi_transaction tr);
    slave_t target = decode_addr(tr.addr);
    string resp_str;
    n_reads++;
    n_read_beats += tr.num_beats();
    if (target != SLV_SRAM) begin
      foreach (tr.rresp[i]) begin
        resp_str = (tr.rresp[i] == RESP_OKAY)   ? "OKAY"   :
                   (tr.rresp[i] == RESP_SLVERR) ? "SLVERR" :
                   (tr.rresp[i] == RESP_DECERR) ? "DECERR" : "EXOKAY";
        if (tr.rresp[i] !== RESP_DECERR) begin
          `uvm_error(get_type_name(),
            $sformatf({"RESPONSE_MISMATCH\n",
                       "id=%0d burst=%s start_addr=0x%08h beat=%0d ",
                       "beat_addr=0x%08h\nexpected=DECERR actual=%s"},
                      tr.id, burst_to_string(tr.burst), tr.addr, i,
                      tr.get_beat_addr(i), resp_str))
          n_resp_mismatch++;
        end
      end
      return;
    end

    for (int beat = 0; beat < tr.num_beats(); beat++) begin
      bit [AXI_ADDR_W-1:0] ba  = tr.get_beat_addr(beat);
      bit [AXI_DATA_W-1:0] exp = ref_model.predict_read(ba);
      resp_str = (tr.rresp[beat] == RESP_OKAY)   ? "OKAY"   :
                 (tr.rresp[beat] == RESP_SLVERR) ? "SLVERR" :
                 (tr.rresp[beat] == RESP_DECERR) ? "DECERR" : "EXOKAY";
      if (tr.rresp[beat] !== RESP_OKAY) begin
        `uvm_error(get_type_name(),
          $sformatf({"RESPONSE_MISMATCH\n",
                     "id=%0d burst=%s start_addr=0x%08h beat=%0d ",
                     "beat_addr=0x%08h\nexpected=OKAY actual=%s"},
                    tr.id, burst_to_string(tr.burst), tr.addr, beat, ba,
                    resp_str))
        n_resp_mismatch++;
      end
      else if (tr.rdata[beat] !== exp) begin
        `uvm_error(get_type_name(),
          $sformatf({"DATA_MISMATCH\n",
                     "id=%0d burst=%s start_addr=0x%08h beat=%0d ",
                     "beat_addr=0x%08h\nexpected=0x%08h actual=0x%08h ",
                     "response=%s"},
                    tr.id, burst_to_string(tr.burst), tr.addr, beat, ba,
                    exp, tr.rdata[beat], resp_str))
        n_data_mismatch++;
      end
    end

    `uvm_info(get_type_name(),
      $sformatf("READ done %s", tr.convert2string()), UVM_MEDIUM)
  endfunction

  function string burst_to_string(burst_t burst);
    case (burst)
      BURST_FIXED: return "FIXED";
      BURST_INCR : return "INCR";
      BURST_WRAP : return "WRAP";
      default    : return "RSVD";
    endcase
  endfunction

  function int unsigned total_mismatches();
    return n_data_mismatch + n_resp_mismatch;
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf({
      "\n## AXI SCOREBOARD\n",
      "Writes checked      : %0d\n",
      "Reads checked       : %0d\n",
      "Write beats         : %0d\n",
      "Read beats          : %0d\n",
      "Data mismatches     : %0d\n",
      "Response mismatches : %0d\n",
      "-----------------------\n",
      "SCOREBOARD: writes=%0d reads=%0d mismatches=%0d"},
      n_writes, n_reads, n_write_beats, n_read_beats,
      n_data_mismatch, n_resp_mismatch,
      n_writes, n_reads, total_mismatches()), UVM_NONE)
  endfunction

endclass : axi_scoreboard


class axi_env extends uvm_env;

  axi_agent      agent;
  axi_scoreboard sb;
  axi_coverage   coverage;

  `uvm_component_utils(axi_env)

  function new(string name = "axi_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = axi_agent::type_id::create("agent", this);
    sb    = axi_scoreboard::type_id::create("sb", this);
    coverage = axi_coverage::type_id::create("coverage", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.monitor.ap.connect(sb.ap_imp);
    agent.monitor.ap.connect(coverage.analysis_export);
  endfunction

endclass : axi_env


class axi_base_seq extends uvm_sequence #(axi_transaction);
  `uvm_object_utils(axi_base_seq)
  function new(string name = "axi_base_seq"); super.new(name); endfunction
endclass

class axi_single_write_seq extends axi_base_seq;
  `uvm_object_utils(axi_single_write_seq)

  bit [AXI_ADDR_W-1:0] m_addr = SRAM_BASE;
  bit [AXI_DATA_W-1:0] m_data = 32'hDEAD_BEEF;
  bit [AXI_ID_W-1:0]   m_id   = '0;

  function new(string name = "axi_single_write_seq"); super.new(name); endfunction

  task body();
    axi_transaction tr = axi_transaction::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize() with {
          dir   == axi_transaction::AXI_WRITE;
          addr  == m_addr;
          id    == m_id;
          len   == 0;
          size  == 2;
          burst == BURST_INCR;
        })
      `uvm_fatal("RANDFAIL", "single write randomize failed")
    tr.data[0] = m_data;
    finish_item(tr);
  endtask
endclass

class axi_single_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_single_read_seq)

  bit [AXI_ADDR_W-1:0] m_addr = SRAM_BASE;
  bit [AXI_ID_W-1:0]   m_id   = '0;

  function new(string name = "axi_single_read_seq"); super.new(name); endfunction

  task body();
    axi_transaction tr = axi_transaction::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize() with {
          dir   == axi_transaction::AXI_READ;
          addr  == m_addr;
          id    == m_id;
          len   == 0;
          size  == 2;
          burst == BURST_INCR;
        })
      `uvm_fatal("RANDFAIL", "single read randomize failed")
    finish_item(tr);
  endtask
endclass

class axi_write_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_write_read_seq)

  int unsigned n_pairs = 4;

  function new(string name = "axi_write_read_seq"); super.new(name); endfunction

  task body();
    for (int i = 0; i < n_pairs; i++) begin
      bit [AXI_ADDR_W-1:0] a = SRAM_BASE + 32'h0100 + (i * 4);
      bit [AXI_DATA_W-1:0] d = 32'hA5A5_0000 + i;
      axi_transaction wr = axi_transaction::type_id::create("wr");
      axi_transaction rd = axi_transaction::type_id::create("rd");
      start_item(wr);
      if (!wr.randomize() with {
            dir == axi_transaction::AXI_WRITE; addr == a; id == i;
            len == 0; size == 2; burst == BURST_INCR;
          }) `uvm_fatal("RANDFAIL", "smoke write randomize failed")
      wr.data[0] = d;
      finish_item(wr);
      start_item(rd);
      if (!rd.randomize() with {
            dir == axi_transaction::AXI_READ; addr == a; id == i;
            len == 0; size == 2; burst == BURST_INCR;
          }) `uvm_fatal("RANDFAIL", "smoke read randomize failed")
      finish_item(rd);
    end
  endtask
endclass


class axi_incr_write_seq extends axi_base_seq;
  `uvm_object_utils(axi_incr_write_seq)

  bit [AXI_ADDR_W-1:0] start_addr    = SRAM_BASE + 32'h0100;
  int unsigned         burst_length = 4;
  bit [2:0]            transfer_size = 2;
  bit [AXI_ID_W-1:0]   axi_id        = '0;
  bit [AXI_DATA_W-1:0] payload[];

  function new(string name = "axi_incr_write_seq"); super.new(name); endfunction

  task body();
    axi_transaction tr = axi_transaction::type_id::create("tr");
    if (burst_length < 1 || burst_length > 16)
      `uvm_fatal("BAD_BURST_LENGTH",
        $sformatf("INCR burst_length must be 1..16, got %0d", burst_length))
    if (transfer_size > 2)
      `uvm_fatal("BAD_TRANSFER_SIZE",
        $sformatf("transfer_size must be 0..2, got %0d", transfer_size))
    if (payload.size() != 0 && payload.size() != burst_length)
      `uvm_fatal("BAD_PAYLOAD",
        $sformatf("payload has %0d elements; expected %0d",
                  payload.size(), burst_length))

    start_item(tr);
    if (!tr.randomize() with {
          dir   == axi_transaction::AXI_WRITE;
          addr  == local::start_addr;
          id    == local::axi_id;
          len   == local::burst_length - 1;
          size  == local::transfer_size;
          burst == BURST_INCR;
        })
      `uvm_fatal("RANDFAIL", "INCR write randomize failed")
    if (payload.size() == burst_length)
      foreach (tr.data[i]) tr.data[i] = payload[i];
    else
      foreach (tr.data[i]) tr.data[i] = 32'hA000_0000 |
                                             (axi_id << 16) | i;
    finish_item(tr);
  endtask
endclass : axi_incr_write_seq


class axi_incr_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_incr_read_seq)

  bit [AXI_ADDR_W-1:0] start_addr     = SRAM_BASE + 32'h0100;
  int unsigned         burst_length  = 4;
  bit [2:0]            transfer_size = 2;
  bit [AXI_ID_W-1:0]   axi_id        = '0;

  function new(string name = "axi_incr_read_seq"); super.new(name); endfunction

  task body();
    axi_transaction tr = axi_transaction::type_id::create("tr");
    if (burst_length < 1 || burst_length > 16)
      `uvm_fatal("BAD_BURST_LENGTH",
        $sformatf("INCR burst_length must be 1..16, got %0d", burst_length))
    if (transfer_size > 2)
      `uvm_fatal("BAD_TRANSFER_SIZE",
        $sformatf("transfer_size must be 0..2, got %0d", transfer_size))
    start_item(tr);
    if (!tr.randomize() with {
          dir   == axi_transaction::AXI_READ;
          addr  == local::start_addr;
          id    == local::axi_id;
          len   == local::burst_length - 1;
          size  == local::transfer_size;
          burst == BURST_INCR;
        })
      `uvm_fatal("RANDFAIL", "INCR read randomize failed")
    finish_item(tr);
  endtask
endclass : axi_incr_read_seq


class axi_incr_write_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_incr_write_read_seq)

  bit [AXI_ADDR_W-1:0] start_addr     = SRAM_BASE + 32'h0100;
  int unsigned         burst_length  = 4;
  bit [2:0]            transfer_size = 2;
  bit [AXI_ID_W-1:0]   axi_id        = '0;
  bit [AXI_DATA_W-1:0] payload[];

  function new(string name = "axi_incr_write_read_seq"); super.new(name); endfunction

  task body();
    axi_incr_write_seq wr_seq;
    axi_incr_read_seq  rd_seq;

    if (transfer_size <= 2 && (start_addr % (1 << transfer_size)) == 0) begin
      for (int beat = 0; beat < burst_length; beat++) begin
        bit [AXI_ADDR_W-1:0] expected = start_addr + (beat << transfer_size);
        bit [AXI_ADDR_W-1:0] actual = beat_addr(start_addr,
          burst_length - 1, transfer_size, BURST_INCR, beat);
        if (actual != expected)
          `uvm_fatal("BEAT_ADDR",
            $sformatf("beat_addr mismatch beat=%0d expected=0x%08h actual=0x%08h",
                      beat, expected, actual))
      end
    end

    wr_seq = axi_incr_write_seq::type_id::create("wr_seq");
    wr_seq.start_addr     = start_addr;
    wr_seq.burst_length  = burst_length;
    wr_seq.transfer_size = transfer_size;
    wr_seq.axi_id        = axi_id;
    wr_seq.payload       = payload;
    wr_seq.start(m_sequencer);

    rd_seq = axi_incr_read_seq::type_id::create("rd_seq");
    rd_seq.start_addr     = start_addr;
    rd_seq.burst_length  = burst_length;
    rd_seq.transfer_size = transfer_size;
    rd_seq.axi_id        = axi_id;
    rd_seq.start(m_sequencer);
  endtask
endclass : axi_incr_write_read_seq


class axi_random_incr_seq extends axi_base_seq;
  `uvm_object_utils(axi_random_incr_seq)

  int unsigned num_transactions = 50;

  function new(string name = "axi_random_incr_seq"); super.new(name); endfunction

  task body();
    for (int pair = 0; pair < num_transactions; pair++) begin
      axi_transaction wr = axi_transaction::type_id::create("wr");
      axi_transaction rd = axi_transaction::type_id::create("rd");
      int unsigned chosen_size = $urandom_range(2, 0);
      int unsigned chosen_len;
      case (pair % 4)
        0: chosen_len = 0;
        1: chosen_len = $urandom_range(3, 1);
        2: chosen_len = $urandom_range(7, 4);
        default: chosen_len = $urandom_range(15, 8);
      endcase

      start_item(wr);
      if (!wr.randomize() with {
            dir   == axi_transaction::AXI_WRITE;
            burst == BURST_INCR;
            size  == local::chosen_size;
            len   == local::chosen_len;
            addr inside {[SRAM_BASE : SRAM_BASE + SRAM_SIZE - 1]};
            (addr % (1 << size)) == 0;
            (addr + ((len + 1) << size)) <= (SRAM_BASE + SRAM_SIZE);
          })
        `uvm_fatal("RANDFAIL", "random INCR write randomize failed")
      finish_item(wr);

      start_item(rd);
      if (!rd.randomize() with {
            dir   == axi_transaction::AXI_READ;
            burst == BURST_INCR;
            addr  == wr.addr;
            id    == wr.id;
            len   == wr.len;
            size  == wr.size;
          })
        `uvm_fatal("RANDFAIL", "matching random INCR read randomize failed")
      finish_item(rd);
    end
  endtask
endclass : axi_random_incr_seq


class axi_base_test extends uvm_test;

  axi_env env;

  `uvm_component_utils(axi_base_test)

  function new(string name = "axi_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axi_env::type_id::create("env", this);
  endfunction

  function void report_phase(uvm_phase phase);
    uvm_report_server svr = uvm_report_server::get_server();
    int n_err = svr.get_severity_count(UVM_ERROR)
              + svr.get_severity_count(UVM_FATAL);
    super.report_phase(phase);
    if (n_err == 0)
      `uvm_info("RESULT", "*** TEST PASSED ***", UVM_NONE)
    else
      `uvm_info("RESULT", $sformatf("*** TEST FAILED (%0d errors) ***", n_err), UVM_NONE)
  endfunction

endclass

class smoke_test extends axi_base_test;
  `uvm_component_utils(smoke_test)

  function new(string name = "smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi_write_read_seq seq;
    phase.raise_objection(this);
    seq = axi_write_read_seq::type_id::create("seq");
    seq.start(env.agent.sequencer);
    phase.drop_objection(this);
  endtask
endclass


class axi_incr_directed_test extends axi_base_test;
  `uvm_component_utils(axi_incr_directed_test)

  function new(string name = "axi_incr_directed_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_incr(uvm_phase phase, int unsigned beats, bit [2:0] size,
                bit [AXI_ADDR_W-1:0] addr, bit [AXI_ID_W-1:0] id,
                bit directed_example = 0);
    axi_incr_write_read_seq seq;
    phase.raise_objection(this);
    seq = axi_incr_write_read_seq::type_id::create("seq");
    seq.start_addr     = addr;
    seq.burst_length  = beats;
    seq.transfer_size = size;
    seq.axi_id        = id;
    seq.payload       = new[beats];
    foreach (seq.payload[i])
      seq.payload[i] = 32'h1020_3040 + (i * 32'h0101_0101);
    if (directed_example && beats == 4) begin
      seq.payload[0] = 32'h1111_0000;
      seq.payload[1] = 32'h2222_0001;
      seq.payload[2] = 32'h3333_0002;
      seq.payload[3] = 32'h4444_0003;
    end
    seq.start(env.agent.sequencer);
    phase.drop_objection(this);
  endtask
endclass : axi_incr_directed_test


class incr_burst_4_test extends axi_incr_directed_test;
  `uvm_component_utils(incr_burst_4_test)
  function new(string name = "incr_burst_4_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_phase(uvm_phase phase);
    run_incr(phase, 4, 2, SRAM_BASE + 32'h0100, 4'h3, 1);
  endtask
endclass


class incr_burst_8_test extends axi_incr_directed_test;
  `uvm_component_utils(incr_burst_8_test)
  function new(string name = "incr_burst_8_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_phase(uvm_phase phase);
    run_incr(phase, 8, 2, SRAM_BASE + 32'h0140, 4'h5);
  endtask
endclass


class incr_burst_16_test extends axi_incr_directed_test;
  `uvm_component_utils(incr_burst_16_test)
  function new(string name = "incr_burst_16_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_phase(uvm_phase phase);
    run_incr(phase, 16, 2, SRAM_BASE + 32'h0180, 4'h7);
  endtask
endclass


class incr_byte_burst_test extends axi_incr_directed_test;
  `uvm_component_utils(incr_byte_burst_test)
  function new(string name = "incr_byte_burst_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_phase(uvm_phase phase);
    run_incr(phase, 8, 0, SRAM_BASE + 32'h0200, 4'h1);
  endtask
endclass


class incr_halfword_burst_test extends axi_incr_directed_test;
  `uvm_component_utils(incr_halfword_burst_test)
  function new(string name = "incr_halfword_burst_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_phase(uvm_phase phase);
    run_incr(phase, 8, 1, SRAM_BASE + 32'h0240, 4'h2);
  endtask
endclass


class incr_word_burst_test extends axi_incr_directed_test;
  `uvm_component_utils(incr_word_burst_test)
  function new(string name = "incr_word_burst_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  task run_phase(uvm_phase phase);
    run_incr(phase, 8, 2, SRAM_BASE + 32'h0280, 4'h4);
  endtask
endclass


class random_incr_test extends axi_base_test;
  `uvm_component_utils(random_incr_test)

  int unsigned num_transactions = 50;

  function new(string name = "random_incr_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(int unsigned)::get(
      this, "", "num_transactions", num_transactions));
    void'($value$plusargs("RANDOM_PAIRS=%d", num_transactions));
  endfunction

  task run_phase(uvm_phase phase);
    axi_random_incr_seq seq;
    phase.raise_objection(this);
    seq = axi_random_incr_seq::type_id::create("seq");
    seq.num_transactions = num_transactions;
    seq.start(env.agent.sequencer);
    phase.drop_objection(this);
  endtask
endclass : random_incr_test


module tb_top;

  logic aclk;
  logic aresetn;

  initial begin
    aclk = 1'b0;
    forever #5ns aclk = ~aclk;
  end

  initial begin
    aresetn = 1'b0;
    repeat (5) @(posedge aclk);
    aresetn = 1'b1;
  end

  axi_if axi_bus (.aclk(aclk), .aresetn(aresetn));

  soc_top dut (.aclk(aclk), .aresetn(aresetn), .m(axi_bus));

  initial begin
    string test_name;
    uvm_config_db#(virtual axi_if)::set(null, "*", "vif", axi_bus);
    if (!$value$plusargs("UVM_TESTNAME=%s", test_name))
      test_name = "smoke_test";
    run_test(test_name);
  end

  initial begin
    #200us;
    `uvm_fatal("TIMEOUT", "global watchdog expired")
  end

endmodule : tb_top
