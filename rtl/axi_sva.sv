`include "uvm_macros.svh"

module axi_sva
  import uvm_pkg::*;
  import axi_pkg::*;
(
  input logic                  aclk,
  input logic                  aresetn,

  input logic                  awvalid,
  input logic                  awready,
  input logic [AXI_ADDR_W-1:0] awaddr,
  input logic [AXI_ID_W-1:0]   awid,
  input logic [7:0]            awlen,
  input logic [2:0]            awsize,
  input logic [1:0]            awburst,

  input logic                  wvalid,
  input logic                  wready,
  input logic [AXI_STRB_W-1:0] wstrb,
  input logic                  wlast,

  input logic                  bvalid,
  input logic                  bready,
  input logic [AXI_ID_W-1:0]   bid,
  input logic [1:0]            bresp,

  input logic                  arvalid,
  input logic                  arready,
  input logic [AXI_ADDR_W-1:0] araddr,
  input logic [AXI_ID_W-1:0]   arid,
  input logic [7:0]            arlen,
  input logic [2:0]            arsize,
  input logic [1:0]            arburst,

  input logic                  rvalid,
  input logic                  rready,
  input logic [AXI_ID_W-1:0]   rid,
  input logic [1:0]            rresp,
  input logic                  rlast
);

  default clocking cb @(posedge aclk); endclocking
  default disable iff (!aresetn);

  int unsigned aw_inflight;
  int unsigned ar_inflight;
  int unsigned w_beats;
  int unsigned r_beats;

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      aw_inflight <= 0;
      ar_inflight <= 0;
      w_beats     <= 0;
      r_beats     <= 0;
    end
    else begin
      if (awvalid & awready) aw_inflight <= aw_inflight + 1;
      if (bvalid  & bready)  aw_inflight <= (aw_inflight != 0)
                                                ? aw_inflight - 1 : 0;
      if (arvalid & arready) ar_inflight <= ar_inflight + 1;
      if (rvalid  & rready & rlast)
        ar_inflight <= (ar_inflight != 0) ? ar_inflight - 1 : 0;

      if (awvalid & awready)              w_beats <= 0;
      else if (wvalid & wready)           w_beats <= w_beats + 1;

      if (arvalid & arready)              r_beats <= 0;
      else if (rvalid & rready)           r_beats <= r_beats + 1;
    end
  end

  function automatic bit [AXI_STRB_W-1:0] low_mask(int n);
    bit [AXI_STRB_W-1:0] m = '0;
    for (int i = 0; i < n && i < AXI_STRB_W; i++) m[i] = 1'b1;
    return m;
  endfunction

  property p_aw_stable;
    awvalid && !awready |=> $stable({awid, awaddr, awlen, awsize, awburst});
  endproperty
  a_aw_stable: assert property (p_aw_stable)
    else `uvm_error("AXI_SVA", "AW payload changed while AWVALID held high")

  a_aw_burst_legal: assert property (awvalid |-> awburst != BURST_RSVD)
    else `uvm_error("AXI_SVA", $sformatf("AWBURST reserved (2'b11) at 0x%08h",
                                         awaddr))

  a_aw_wrap_len: assert property (
    awvalid |-> (awburst != BURST_WRAP) ||
                (awlen inside {1, 3, 7, 15}))
    else `uvm_error("AXI_SVA", $sformatf("WRAP burst with illegal AWLEN=%0d",
                                         awlen))

  a_aw_wrap_align: assert property (
    awvalid |-> (awburst != BURST_WRAP) ||
                ((awsize == 1 && awaddr[0]   == 1'b0) ||
                 (awsize == 2 && awaddr[1:0] == 2'b00)))
    else `uvm_error("AXI_SVA", $sformatf("WRAP burst from unaligned addr 0x%08h",
                                         awaddr))

  property p_w_stable;
    wvalid && !wready |=> $stable({wstrb, wlast}) && wvalid;
  endproperty
  a_w_stable: assert property (p_w_stable)
    else `uvm_error("AXI_SVA", "WSTRB/WLAST changed or WVALID dropped while WREADY low")

  a_w_strb_nonzero: assert property (wvalid |-> wstrb != '0)
    else `uvm_error("AXI_SVA", "WVALID with all-zero WSTRB")

  a_w_beat_bound: assert property (
    (wvalid && aw_inflight != 0) |-> (w_beats <= awlen))
    else `uvm_error("AXI_SVA", $sformatf("write beat %0d exceeds AWLEN+1=%0d",
                                         w_beats + 1, awlen + 1))

  a_w_last_position: assert property (
    (wvalid && wready && aw_inflight != 0) |->
      (wlast == (w_beats == awlen)))
    else `uvm_error("AXI_SVA", $sformatf("WLAST=%0b on beat %0d of %0d",
                                         wlast, w_beats + 1, awlen + 1))

  a_b_needs_outstanding: assert property (
    bvalid |-> aw_inflight != 0)
    else `uvm_error("AXI_SVA", "BVALID with no outstanding AW transaction")

  property p_b_stable;
    bvalid && !bready |=> $stable({bid, bresp}) && bvalid;
  endproperty
  a_b_stable: assert property (p_b_stable)
    else `uvm_error("AXI_SVA", "BID/BRESP changed or BVALID dropped while BREADY low")

  a_bresp_legal: assert property (
    bvalid |-> (bresp inside {RESP_OKAY, RESP_DECERR}))
    else `uvm_error("AXI_SVA", $sformatf("illegal BRESP=%0b", bresp))

  property p_ar_stable;
    arvalid && !arready |=> $stable({arid, araddr, arlen, arsize, arburst});
  endproperty
  a_ar_stable: assert property (p_ar_stable)
    else `uvm_error("AXI_SVA", "AR payload changed while ARVALID held high")

  a_ar_burst_legal: assert property (arvalid |-> arburst != BURST_RSVD)
    else `uvm_error("AXI_SVA", "ARBURST reserved (2'b11)")

  a_ar_wrap_len: assert property (
    arvalid |-> (arburst != BURST_WRAP) ||
                (arlen inside {1, 3, 7, 15}))
    else `uvm_error("AXI_SVA", $sformatf("read WRAP burst with illegal ARLEN=%0d",
                                         arlen))

  property p_r_stable;
    rvalid && !rready |=> $stable({rid, rresp}) && rvalid;
  endproperty
  a_r_stable: assert property (p_r_stable)
    else `uvm_error("AXI_SVA", "RID/RRESP changed or RVALID dropped while RREADY low")

  a_r_needs_outstanding: assert property (
    rvalid |-> ar_inflight != 0)
    else `uvm_error("AXI_SVA", "RVALID with no outstanding AR transaction")

  a_r_beat_bound: assert property (
    (rvalid && ar_inflight != 0) |-> (r_beats <= arlen))
    else `uvm_error("AXI_SVA", $sformatf("read beat %0d exceeds ARLEN+1=%0d",
                                         r_beats + 1, arlen + 1))

  a_r_last_position: assert property (
    (rvalid && rready && ar_inflight != 0) |->
      (rlast == (r_beats == arlen)))
    else `uvm_error("AXI_SVA", $sformatf("RLAST=%0b on beat %0d of %0d",
                                         rlast, r_beats + 1, arlen + 1))

  a_rresp_legal: assert property (
    rvalid |-> (rresp inside {RESP_OKAY, RESP_DECERR}))
    else `uvm_error("AXI_SVA", $sformatf("illegal RRESP=%0b", rresp))

  a_first_beat_lanes: assert property (
    (wvalid && wready && w_beats == 0 && aw_inflight != 0) |->
      ((wstrb & low_mask(int'(awaddr[1:0]))) == '0) &&
      ((wstrb & ~low_mask(int'(awaddr[1:0]))) != '0))
    else `uvm_error("AXI_SVA", $sformatf(
      "first-beat WSTRB=%0b violates byte-offset rule for addr 0x%08h",
      wstrb, awaddr))

  a_aligned_first_beat_lanes: assert property (
    (wvalid && wready && w_beats == 0 && aw_inflight != 0 &&
     (awaddr % (1 << awsize)) == 0) |->
      (wstrb & ~low_mask(int'(((awaddr % 4) >> awsize) + 1) << int'(awsize)))
        == '0)
    else `uvm_error("AXI_SVA", $sformatf(
      "aligned first-beat WSTRB=%0b outside byte window for addr 0x%08h size=%0d",
      wstrb, awaddr, awsize))

endmodule : axi_sva
