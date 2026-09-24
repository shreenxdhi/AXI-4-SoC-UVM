module tb_top;
  import uvm_pkg::*;
  import tb_pkg::*;

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

  `include "axi_sva_bind.sv"

  soc_top dut (.aclk(aclk), .aresetn(aresetn), .m(axi_bus));

  initial begin
    string test_name;
    uvm_config_db#(virtual axi_if)::set(null, "*", "vif", axi_bus);
    if (!$value$plusargs("UVM_TESTNAME=%s", test_name))
      test_name = "smoke_test";
    run_test(test_name);
  end

  initial begin
    static time timeout_ns = 2_000_000; // 2 ms
    void'($value$plusargs("TIMEOUT_NS=%d", timeout_ns));
    #(timeout_ns * 1ns);
    `uvm_fatal("TIMEOUT", "global watchdog expired")
  end

endmodule : tb_top
