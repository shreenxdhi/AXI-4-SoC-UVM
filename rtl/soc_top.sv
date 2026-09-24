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
