module axi_fabric
  import axi_pkg::*;
(
  input logic aclk,
  input logic aresetn,
  axi_if.slave  m,
  axi_if.master s0,
  axi_if.master s1,
  axi_if.master s2
);

  slave_t aw_sel;
  assign aw_sel = decode_addr(m.awaddr);

  always_comb begin
    s0.awvalid = 1'b0;
    s1.awvalid = 1'b0;
    s2.awvalid = 1'b0;
    case (aw_sel)
      SLV_SRAM  : s0.awvalid = m.awvalid;
      SLV_PERIPH: s1.awvalid = m.awvalid;
      default   : s2.awvalid = m.awvalid;
    endcase
  end

  always_comb begin
    case (aw_sel)
      SLV_SRAM  : m.awready = s0.awready;
      SLV_PERIPH: m.awready = s1.awready;
      default   : m.awready = s2.awready;
    endcase
  end

  assign s0.awid = m.awid; assign s0.awaddr = m.awaddr; assign s0.awlen = m.awlen;
  assign s0.awsize = m.awsize; assign s0.awburst = m.awburst; assign s0.awlock = m.awlock;
  assign s0.awcache = m.awcache; assign s0.awprot = m.awprot; assign s0.awqos = m.awqos;

  assign s1.awid = m.awid; assign s1.awaddr = m.awaddr; assign s1.awlen = m.awlen;
  assign s1.awsize = m.awsize; assign s1.awburst = m.awburst; assign s1.awlock = m.awlock;
  assign s1.awcache = m.awcache; assign s1.awprot = m.awprot; assign s1.awqos = m.awqos;

  assign s2.awid = m.awid; assign s2.awaddr = m.awaddr; assign s2.awlen = m.awlen;
  assign s2.awsize = m.awsize; assign s2.awburst = m.awburst; assign s2.awlock = m.awlock;
  assign s2.awcache = m.awcache; assign s2.awprot = m.awprot; assign s2.awqos = m.awqos;

  slave_t w_sel;
  always_ff @(posedge aclk) begin
    if (!aresetn)                        w_sel <= SLV_ERR;
    else if (m.awvalid && m.awready)     w_sel <= aw_sel;
  end

  always_comb begin
    s0.wvalid = 1'b0;
    s1.wvalid = 1'b0;
    s2.wvalid = 1'b0;
    case (w_sel)
      SLV_SRAM  : s0.wvalid = m.wvalid;
      SLV_PERIPH: s1.wvalid = m.wvalid;
      default   : s2.wvalid = m.wvalid;
    endcase
  end

  always_comb begin
    case (w_sel)
      SLV_SRAM  : m.wready = s0.wready;
      SLV_PERIPH: m.wready = s1.wready;
      default   : m.wready = s2.wready;
    endcase
  end

  assign s0.wdata = m.wdata; assign s0.wstrb = m.wstrb; assign s0.wlast = m.wlast;
  assign s1.wdata = m.wdata; assign s1.wstrb = m.wstrb; assign s1.wlast = m.wlast;
  assign s2.wdata = m.wdata; assign s2.wstrb = m.wstrb; assign s2.wlast = m.wlast;

  slave_t b_sel;
  always_ff @(posedge aclk) begin
    if (!aresetn)                                  b_sel <= SLV_ERR;
    else if (m.wvalid && m.wready && m.wlast)      b_sel <= w_sel;
  end

  always_comb begin
    s0.bready = 1'b0;
    s1.bready = 1'b0;
    s2.bready = 1'b0;
    case (b_sel)
      SLV_SRAM  : s0.bready = m.bready;
      SLV_PERIPH: s1.bready = m.bready;
      default   : s2.bready = m.bready;
    endcase
  end

  always_comb begin
    case (b_sel)
      SLV_SRAM  : begin m.bvalid = s0.bvalid; m.bid = s0.bid; m.bresp = s0.bresp; end
      SLV_PERIPH: begin m.bvalid = s1.bvalid; m.bid = s1.bid; m.bresp = s1.bresp; end
      default   : begin m.bvalid = s2.bvalid; m.bid = s2.bid; m.bresp = s2.bresp; end
    endcase
  end

  slave_t ar_sel;
  assign ar_sel = decode_addr(m.araddr);

  always_comb begin
    s0.arvalid = 1'b0;
    s1.arvalid = 1'b0;
    s2.arvalid = 1'b0;
    case (ar_sel)
      SLV_SRAM  : s0.arvalid = m.arvalid;
      SLV_PERIPH: s1.arvalid = m.arvalid;
      default   : s2.arvalid = m.arvalid;
    endcase
  end

  always_comb begin
    case (ar_sel)
      SLV_SRAM  : m.arready = s0.arready;
      SLV_PERIPH: m.arready = s1.arready;
      default   : m.arready = s2.arready;
    endcase
  end

  assign s0.arid = m.arid; assign s0.araddr = m.araddr; assign s0.arlen = m.arlen;
  assign s0.arsize = m.arsize; assign s0.arburst = m.arburst; assign s0.arlock = m.arlock;
  assign s0.arcache = m.arcache; assign s0.arprot = m.arprot; assign s0.arqos = m.arqos;

  assign s1.arid = m.arid; assign s1.araddr = m.araddr; assign s1.arlen = m.arlen;
  assign s1.arsize = m.arsize; assign s1.arburst = m.arburst; assign s1.arlock = m.arlock;
  assign s1.arcache = m.arcache; assign s1.arprot = m.arprot; assign s1.arqos = m.arqos;

  assign s2.arid = m.arid; assign s2.araddr = m.araddr; assign s2.arlen = m.arlen;
  assign s2.arsize = m.arsize; assign s2.arburst = m.arburst; assign s2.arlock = m.arlock;
  assign s2.arcache = m.arcache; assign s2.arprot = m.arprot; assign s2.arqos = m.arqos;

  slave_t r_sel;
  always_ff @(posedge aclk) begin
    if (!aresetn)                      r_sel <= SLV_ERR;
    else if (m.arvalid && m.arready)   r_sel <= ar_sel;
  end

  always_comb begin
    s0.rready = 1'b0;
    s1.rready = 1'b0;
    s2.rready = 1'b0;
    case (r_sel)
      SLV_SRAM  : s0.rready = m.rready;
      SLV_PERIPH: s1.rready = m.rready;
      default   : s2.rready = m.rready;
    endcase
  end

  always_comb begin
    case (r_sel)
      SLV_SRAM: begin
        m.rvalid = s0.rvalid; m.rid = s0.rid; m.rdata = s0.rdata;
        m.rresp  = s0.rresp;  m.rlast = s0.rlast;
      end
      SLV_PERIPH: begin
        m.rvalid = s1.rvalid; m.rid = s1.rid; m.rdata = s1.rdata;
        m.rresp  = s1.rresp;  m.rlast = s1.rlast;
      end
      default: begin
        m.rvalid = s2.rvalid; m.rid = s2.rid; m.rdata = s2.rdata;
        m.rresp  = s2.rresp;  m.rlast = s2.rlast;
      end
    endcase
  end

endmodule : axi_fabric
