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
