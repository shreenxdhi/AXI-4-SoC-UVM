import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

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


class fixed_burst_test extends axi_base_test;
  `uvm_component_utils(fixed_burst_test)

  function new(string name = "fixed_burst_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi_burst_write_read_seq seq;
    phase.raise_objection(this);
    seq = axi_burst_write_read_seq::type_id::create("seq");
    seq.m_burst       = BURST_FIXED;
    seq.start_addr    = SRAM_BASE + 32'h0300;
    seq.burst_length  = 4;
    seq.transfer_size = 2;
    seq.axi_id        = 4'h6;
    seq.start(env.agent.sequencer);
    phase.drop_objection(this);
  endtask
endclass : fixed_burst_test


class wrap_burst_test extends axi_base_test;
  `uvm_component_utils(wrap_burst_test)

  function new(string name = "wrap_burst_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi_burst_write_read_seq seq;
    phase.raise_objection(this);
    seq = axi_burst_write_read_seq::type_id::create("seq");
    seq.m_burst       = BURST_WRAP;
    seq.start_addr    = SRAM_BASE + 32'h003C;
    seq.burst_length  = 4;
    seq.transfer_size = 2;
    seq.axi_id        = 4'h9;
    seq.start(env.agent.sequencer);
    phase.drop_objection(this);
  endtask
endclass : wrap_burst_test


class unaligned_burst_test extends axi_base_test;
  `uvm_component_utils(unaligned_burst_test)

  function new(string name = "unaligned_burst_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi_unaligned_write_read_seq seq;
    phase.raise_objection(this);
    seq = axi_unaligned_write_read_seq::type_id::create("seq");
    seq.start_addr    = SRAM_BASE + 32'h0302;
    seq.burst_length  = 4;
    seq.transfer_size = 1;
    seq.axi_id        = 4'hA;
    seq.start(env.agent.sequencer);
    phase.drop_objection(this);
  endtask
endclass : unaligned_burst_test


class err_response_test extends axi_base_test;
  `uvm_component_utils(err_response_test)

  function new(string name = "err_response_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi_err_write_seq wr;
    axi_err_read_seq  rd;
    phase.raise_objection(this);
    wr = axi_err_write_seq::type_id::create("wr");
    rd = axi_err_read_seq::type_id::create("rd");
    wr.start(env.agent.sequencer);
    rd.start(env.agent.sequencer);
    phase.drop_objection(this);
  endtask
endclass : err_response_test


class coverage_max_test extends axi_base_test;
  `uvm_component_utils(coverage_max_test)

  function new(string name = "coverage_max_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    axi_write_read_seq           smoke;
    axi_burst_write_read_seq     fixed_seq, wrap_seq;
    axi_unaligned_write_read_seq unal_seq;
    axi_err_write_seq            err_wr;
    axi_err_read_seq             err_rd;
    axi_random_incr_seq          rnd;

    phase.raise_objection(this);

    smoke = axi_write_read_seq::type_id::create("smoke");
    smoke.start(env.agent.sequencer);

    fixed_seq = axi_burst_write_read_seq::type_id::create("fixed_seq");
    fixed_seq.m_burst       = BURST_FIXED;
    fixed_seq.start_addr    = SRAM_BASE + 32'h0300;
    fixed_seq.burst_length  = 4;
    fixed_seq.transfer_size = 2;
    fixed_seq.axi_id        = 4'h6;
    fixed_seq.start(env.agent.sequencer);

    wrap_seq = axi_burst_write_read_seq::type_id::create("wrap_seq");
    wrap_seq.m_burst       = BURST_WRAP;
    wrap_seq.start_addr    = SRAM_BASE + 32'h003C;
    wrap_seq.burst_length  = 4;
    wrap_seq.transfer_size = 2;
    wrap_seq.axi_id        = 4'h9;
    wrap_seq.start(env.agent.sequencer);

    unal_seq = axi_unaligned_write_read_seq::type_id::create("unal_seq");
    unal_seq.start_addr    = SRAM_BASE + 32'h0302;
    unal_seq.burst_length  = 4;
    unal_seq.transfer_size = 1;
    unal_seq.axi_id        = 4'hA;
    unal_seq.start(env.agent.sequencer);

    err_wr = axi_err_write_seq::type_id::create("err_wr");
    err_wr.start(env.agent.sequencer);
    err_rd = axi_err_read_seq::type_id::create("err_rd");
    err_rd.start(env.agent.sequencer);

    rnd = axi_random_incr_seq::type_id::create("rnd");
    rnd.num_transactions = 100;
    rnd.start(env.agent.sequencer);

    phase.drop_objection(this);
  endtask
endclass : coverage_max_test


class axi_stress_test extends axi_base_test;
  `uvm_component_utils(axi_stress_test)

  int unsigned num_pairs = 1000;

  function new(string name = "axi_stress_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db#(int unsigned)::get(
      this, "", "num_pairs", num_pairs));
    void'($value$plusargs("STRESS_PAIRS=%d", num_pairs));
  endfunction

  task run_phase(uvm_phase phase);
    axi_random_incr_seq          rnd;
    axi_burst_write_read_seq     fixed_seq, wrap_seq;
    axi_unaligned_write_read_seq unal_seq;
    axi_err_write_seq            err_wr;
    axi_err_read_seq             err_rd;

    phase.raise_objection(this);

    rnd = axi_random_incr_seq::type_id::create("rnd");
    rnd.num_transactions = num_pairs;
    rnd.start(env.agent.sequencer);

    for (int grp = 0; grp < 5; grp++) begin
      fixed_seq = axi_burst_write_read_seq::type_id::create("fixed_seq");
      fixed_seq.m_burst       = BURST_FIXED;
      fixed_seq.start_addr    = SRAM_BASE + 32'h0300 + (grp * 32'h0010);
      fixed_seq.burst_length  = 4;
      fixed_seq.transfer_size = 2;
      fixed_seq.axi_id        = 4'h6;
      fixed_seq.start(env.agent.sequencer);

      wrap_seq = axi_burst_write_read_seq::type_id::create("wrap_seq");
      wrap_seq.m_burst       = BURST_WRAP;
      wrap_seq.start_addr    = SRAM_BASE + 32'h003C + (grp * 32'h0010);
      wrap_seq.burst_length  = 4;
      wrap_seq.transfer_size = 2;
      wrap_seq.axi_id        = 4'h9;
      wrap_seq.start(env.agent.sequencer);

      unal_seq = axi_unaligned_write_read_seq::type_id::create("unal_seq");
      unal_seq.start_addr    = SRAM_BASE + 32'h0302 + (grp * 32'h0010);
      unal_seq.burst_length  = 4;
      unal_seq.transfer_size = 1;
      unal_seq.axi_id        = 4'hA;
      unal_seq.start(env.agent.sequencer);

      err_wr = axi_err_write_seq::type_id::create("err_wr");
      err_wr.m_addr = PERIPH_BASE + (grp * 32'h0010);
      err_wr.start(env.agent.sequencer);
      err_rd = axi_err_read_seq::type_id::create("err_rd");
      err_rd.m_addr = PERIPH_BASE + (grp * 32'h0010);
      err_rd.start(env.agent.sequencer);
    end

    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("STRESS",
      $sformatf("Stress run completed %0d random write/read pairs at time %0t",
                num_pairs, $time), UVM_NONE)
  endfunction
endclass : axi_stress_test
