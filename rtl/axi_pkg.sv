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
