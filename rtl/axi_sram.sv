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
