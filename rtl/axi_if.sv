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
