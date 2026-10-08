// -----------------------------------------------------------------------
// fifo_tb_top.sv
// Top-level testbench module: clock/reset generation, DUT + interface
// instantiation, virtual interface registration, run_test().
// -----------------------------------------------------------------------
`include "uvm_macros.svh"

module fifo_tb_top;
  import uvm_pkg::*;
  import fifo_pkg::*;

  localparam DATA_WIDTH = 8;
  localparam DEPTH      = 16;

  logic clk;
  initial clk = 0;
  always #5 clk = ~clk;

  fifo_if #(.DATA_WIDTH(DATA_WIDTH)) vif (.clk(clk));

  sync_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(DEPTH)
  ) dut (
    .clk     (clk),
    .rst_n   (vif.rst_n),
    .wr_en   (vif.wr_en),
    .rd_en   (vif.rd_en),
    .wr_data (vif.wr_data),
    .rd_data (vif.rd_data),
    .full    (vif.full),
    .empty   (vif.empty)
  );

  initial begin
    vif.rst_n = 0;
    repeat (4) @(posedge clk);
    vif.rst_n = 1;
  end

  initial begin
    uvm_config_db#(virtual fifo_if)::set(null, "*", "vif", vif);
    run_test();
  end

  // safety net so a stuck sequence/objection doesn't hang the regression
  initial begin
    #1ms;
    `uvm_fatal("TB_TOP", "Simulation timeout - check for a hung sequence or missing objection drop")
  end
endmodule
