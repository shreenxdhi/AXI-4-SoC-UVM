//==============================================================================
// Simplified AXI4 Memory Subsystem
//
// This file contains the shared AXI definitions, interface, SRAM model,
// error responder, address-routing fabric and design top level.
//==============================================================================

//==============================================================================
// AXI definitions and address-map helpers
//==============================================================================

package axi_pkg;

  parameter int AXI_ADDR_W = 32;
  parameter int AXI_DATA_W = 32;
  parameter int AXI_STRB_W = AXI_DATA_W / 8;
  parameter int AXI_ID_W   = 4;

  typedef enum logic [1:0] {
    BURST_FIXED = 2'b00,
    BURST_INCR  = 2'b01,
    BURST_WRAP  = 2'b10,
    BURST_RSVD  = 2'b11
  } burst_t;

  typedef enum logic [1:0] {
    RESP_OKAY   = 2'b00,
    RESP_EXOKAY = 2'b01,
    RESP_SLVERR = 2'b10,
    RESP_DECERR = 2'b11
  } resp_t;

  parameter logic [31:0] SRAM_BASE   = 32'h0000_0000;
  parameter logic [31:0] SRAM_SIZE   = 32'h0001_0000;
  parameter logic [31:0] PERIPH_BASE = 32'h1000_0000;
  parameter logic [31:0] PERIPH_SIZE = 32'h0000_1000;

  // Peripheral register offsets
  parameter logic [11:0] REG_STATUS    = 12'h000;
  parameter logic [11:0] REG_CONTROL   = 12'h004;
  parameter logic [11:0] REG_DELAY_CFG = 12'h008;
  parameter logic [11:0] REG_ERROR_CFG = 12'h00C;

  typedef enum int { SLV_SRAM = 0, SLV_PERIPH = 1, SLV_ERR = 2 } slave_t;

  function automatic slave_t decode_addr(logic [AXI_ADDR_W-1:0] addr);
    if (addr >= SRAM_BASE && addr < (SRAM_BASE + SRAM_SIZE))
      return SLV_SRAM;
    else if (addr >= PERIPH_BASE && addr < (PERIPH_BASE + PERIPH_SIZE))
      return SLV_PERIPH;
    else
      return SLV_ERR;
  endfunction

  function automatic logic [AXI_ADDR_W-1:0] lane_base(logic [AXI_ADDR_W-1:0] a);
    return a - (a % AXI_STRB_W);
  endfunction

  function automatic logic [AXI_ADDR_W-1:0] beat_addr(
    input logic [AXI_ADDR_W-1:0] start_addr,
    input logic [7:0]            len,
    input logic [2:0]            size,
    input burst_t                burst,
    input int                    beat
  );
    logic [AXI_ADDR_W-1:0] nbytes  = AXI_ADDR_W'(1) << size;
    logic [AXI_ADDR_W-1:0] aligned = start_addr - (start_addr % nbytes);
    logic [AXI_ADDR_W-1:0] total   = nbytes * (AXI_ADDR_W'(len) + 1);
    logic [AXI_ADDR_W-1:0] wrap_lo;

    case (burst)
      BURST_FIXED: return start_addr;
      BURST_INCR : return (beat == 0) ? start_addr : (aligned + beat * nbytes);
      BURST_WRAP : begin
        wrap_lo = start_addr - (start_addr % total);
        return wrap_lo + ((start_addr + beat * nbytes) % total);
      end
      default    : return start_addr;
    endcase
  endfunction

endpackage : axi_pkg


//==============================================================================
// AXI interface and master/slave signal directions
//==============================================================================
interface axi_if (input logic aclk, input logic aresetn);
  import axi_pkg::*;

  logic [AXI_ID_W-1:0]   awid;
  logic [AXI_ADDR_W-1:0] awaddr;
  logic [7:0]            awlen;
  logic [2:0]            awsize;
  logic [1:0]            awburst;
  logic                  awlock;
  logic [3:0]            awcache;
  logic [2:0]            awprot;
  logic [3:0]            awqos;
  logic                  awvalid, awready;

  logic [AXI_DATA_W-1:0] wdata;
  logic [AXI_STRB_W-1:0] wstrb;
  logic                  wlast, wvalid, wready;

  logic [AXI_ID_W-1:0]   bid;
  logic [1:0]            bresp;
  logic                  bvalid, bready;

  logic [AXI_ID_W-1:0]   arid;
  logic [AXI_ADDR_W-1:0] araddr;
  logic [7:0]            arlen;
  logic [2:0]            arsize;
  logic [1:0]            arburst;
  logic                  arlock;
  logic [3:0]            arcache;
  logic [2:0]            arprot;
  logic [3:0]            arqos;
  logic                  arvalid, arready;

  logic [AXI_ID_W-1:0]   rid;
  logic [AXI_DATA_W-1:0] rdata;
  logic [1:0]            rresp;
  logic                  rlast, rvalid, rready;

  modport slave (
    input  aclk, aresetn,
    input  awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid,
    output awready,
    input  wdata, wstrb, wlast, wvalid,
    output wready,
    output bid, bresp, bvalid,
    input  bready,
    input  arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid,
    output arready,
    output rid, rdata, rresp, rlast, rvalid,
    input  rready
  );

  modport master (
    input  aclk, aresetn,
    output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid,
    input  awready,
    output wdata, wstrb, wlast, wvalid,
    input  wready,
    input  bid, bresp, bvalid,
    output bready,
    output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid,
    input  arready,
    input  rid, rdata, rresp, rlast, rvalid,
    output rready
  );

endinterface : axi_if


//==============================================================================
// Byte-addressable SRAM slave
//==============================================================================
module axi_sram
  import axi_pkg::*;
#(
  parameter int SIZE_BYTES = 65536,
  parameter int MIN_DELAY  = 0,
  parameter int MAX_DELAY  = 3
) (
  input logic aclk,
  input logic aresetn,
  axi_if.slave s
);

  logic [7:0] mem [0:SIZE_BYTES-1];

  // Simulation SRAM model: initialize memory deterministically at time 0.
  // This avoids an X-valued initialization flag blocking all AXI writes.
  initial begin
    for (int i = 0; i < SIZE_BYTES; i++)
      mem[i] = 8'h00;
  end

  logic [15:0] lfsr;
  always_ff @(posedge aclk) begin
    if (!aresetn) lfsr <= 16'hACE1;
    else          lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  end

  function automatic int get_delay();
    if (MAX_DELAY <= MIN_DELAY) return MIN_DELAY;
    return MIN_DELAY + (int'(lfsr[2:0]) % (MAX_DELAY - MIN_DELAY + 1));
  endfunction

  typedef enum logic [1:0] { W_IDLE, W_DATA, W_RESP } wst_e;
  wst_e wst;

  logic [AXI_ID_W-1:0]   aw_id;
  logic [AXI_ADDR_W-1:0] aw_addr;
  logic [7:0]            aw_len;
  logic [2:0]            aw_size;
  burst_t                aw_burst;
  int                    w_beat;
  int                    w_dly, b_dly;

  assign s.awready = (wst == W_IDLE) && aresetn;
  assign s.wready  = (wst == W_DATA) && (w_dly == 0);
  assign s.bvalid  = (wst == W_RESP) && (b_dly == 0);
  assign s.bid     = aw_id;
  assign s.bresp   = RESP_OKAY;

  logic [AXI_ADDR_W-1:0] w_beat_addr;
  always_comb w_beat_addr = beat_addr(aw_addr, aw_len, aw_size, aw_burst, w_beat);

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      wst    <= W_IDLE;
      w_beat <= 0;
      w_dly  <= 0;
      b_dly  <= 0;
      aw_id  <= '0;
      aw_len <= '0;
    end
    else begin
      case (wst)
        W_IDLE: if (s.awvalid && s.awready) begin
          aw_id    <= s.awid;
          aw_addr  <= s.awaddr;
          aw_len   <= s.awlen;
          aw_size  <= s.awsize;
          aw_burst <= burst_t'(s.awburst);
          w_beat   <= 0;
          w_dly    <= get_delay();
          wst      <= W_DATA;
        end

        W_DATA: begin
          if (w_dly > 0) w_dly <= w_dly - 1;
          else if (s.wvalid && s.wready) begin
            w_dly <= get_delay();
            if (s.wlast) begin
              b_dly <= get_delay();
              wst   <= W_RESP;
            end
            else w_beat <= w_beat + 1;
          end
        end

        W_RESP: begin
          if (b_dly > 0) b_dly <= b_dly - 1;
          else if (s.bvalid && s.bready) wst <= W_IDLE;
        end

        default: wst <= W_IDLE;
      endcase
    end
  end

  always_ff @(posedge aclk) begin
    if (aresetn && s.wvalid && s.wready) begin
      for (int i = 0; i < AXI_STRB_W; i++)
        if (s.wstrb[i])
          mem[(lane_base(w_beat_addr) + i) % SIZE_BYTES] <= s.wdata[i*8 +: 8];
    end
  end

  typedef enum logic { R_IDLE, R_DATA } rst_e;
  rst_e rst_s;

  logic [AXI_ID_W-1:0]   ar_id;
  logic [AXI_ADDR_W-1:0] ar_addr;
  logic [7:0]            ar_len;
  logic [2:0]            ar_size;
  burst_t                ar_burst;
  int                    r_beat;
  int                    r_dly;

  assign s.arready = (rst_s == R_IDLE) && aresetn;
  assign s.rvalid  = (rst_s == R_DATA) && (r_dly == 0);
  assign s.rid     = ar_id;
  assign s.rresp   = RESP_OKAY;
  assign s.rlast   = (rst_s == R_DATA) && (r_beat == int'(ar_len));

  logic [AXI_ADDR_W-1:0] r_beat_addr;
  always_comb r_beat_addr = beat_addr(ar_addr, ar_len, ar_size, ar_burst, r_beat);

  always_comb begin
    s.rdata = '0;
    for (int i = 0; i < AXI_STRB_W; i++)
      s.rdata[i*8 +: 8] = mem[(lane_base(r_beat_addr) + i) % SIZE_BYTES];
  end

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      rst_s  <= R_IDLE;
      r_beat <= 0;
      r_dly  <= 0;
      ar_id  <= '0;
      ar_len <= '0;
    end
    else begin
      case (rst_s)
        R_IDLE: if (s.arvalid && s.arready) begin
          ar_id    <= s.arid;
          ar_addr  <= s.araddr;
          ar_len   <= s.arlen;
          ar_size  <= s.arsize;
          ar_burst <= burst_t'(s.arburst);
          r_beat   <= 0;
          r_dly    <= get_delay();
          rst_s    <= R_DATA;
        end

        R_DATA: begin
          if (r_dly > 0) r_dly <= r_dly - 1;
          else if (s.rvalid && s.rready) begin
            r_dly <= get_delay();
            if (s.rlast) rst_s  <= R_IDLE;
            else         r_beat <= r_beat + 1;
          end
        end

        default: rst_s <= R_IDLE;
      endcase
    end
  end

endmodule : axi_sram


//==============================================================================
// DECERR slave for reserved and unmapped address regions
//==============================================================================
module axi_err_slave
  import axi_pkg::*;
(
  input logic aclk,
  input logic aresetn,
  axi_if.slave s
);

  typedef enum logic [1:0] { WS_IDLE, WS_DATA, WS_RESP } ws_e;
  ws_e ws;
  logic [AXI_ID_W-1:0] w_id;

  assign s.awready = (ws == WS_IDLE) && aresetn;
  assign s.wready  = (ws == WS_DATA);
  assign s.bvalid  = (ws == WS_RESP);
  assign s.bid     = w_id;
  assign s.bresp   = RESP_DECERR;

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      ws   <= WS_IDLE;
      w_id <= '0;
    end
    else case (ws)
      WS_IDLE: if (s.awvalid && s.awready) begin w_id <= s.awid; ws <= WS_DATA; end
      WS_DATA: if (s.wvalid && s.wready && s.wlast) ws <= WS_RESP;
      WS_RESP: if (s.bvalid && s.bready) ws <= WS_IDLE;
      default: ws <= WS_IDLE;
    endcase
  end

  typedef enum logic { RS_IDLE, RS_DATA } rs_e;
  rs_e rs;
  logic [AXI_ID_W-1:0] r_id;
  logic [7:0]          r_len;
  int                  r_beat;

  assign s.arready = (rs == RS_IDLE) && aresetn;
  assign s.rvalid  = (rs == RS_DATA);
  assign s.rid     = r_id;
  assign s.rdata   = '0;
  assign s.rresp   = RESP_DECERR;
  assign s.rlast   = (rs == RS_DATA) && (r_beat == int'(r_len));

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      rs     <= RS_IDLE;
      r_beat <= 0;
      r_id   <= '0;
      r_len  <= '0;
    end
    else case (rs)
      RS_IDLE: if (s.arvalid && s.arready) begin
        r_id   <= s.arid;
        r_len  <= s.arlen;
        r_beat <= 0;
        rs     <= RS_DATA;
      end
      RS_DATA: if (s.rvalid && s.rready) begin
        if (s.rlast) begin r_beat <= 0; rs <= RS_IDLE; end
        else               r_beat <= r_beat + 1;
      end
      default: rs <= RS_IDLE;
    endcase
  end

endmodule : axi_err_slave


//==============================================================================
// Address decoder and AXI channel router
//==============================================================================
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


//==============================================================================
// Memory-subsystem top level
//==============================================================================
module soc_top
  import axi_pkg::*;
(
  input logic aclk,
  input logic aresetn,
  axi_if.slave m
);

  axi_if s0_if (.aclk(aclk), .aresetn(aresetn));
  axi_if s1_if (.aclk(aclk), .aresetn(aresetn));
  axi_if s2_if (.aclk(aclk), .aresetn(aresetn));

  axi_fabric u_fabric (
    .aclk(aclk), .aresetn(aresetn),
    .m(m), .s0(s0_if), .s1(s1_if), .s2(s2_if)
  );

  axi_sram u_sram (.aclk(aclk), .aresetn(aresetn), .s(s0_if));

  axi_err_slave u_periph (.aclk(aclk), .aresetn(aresetn), .s(s1_if));

  axi_err_slave u_err (.aclk(aclk), .aresetn(aresetn), .s(s2_if));

endmodule : soc_top
