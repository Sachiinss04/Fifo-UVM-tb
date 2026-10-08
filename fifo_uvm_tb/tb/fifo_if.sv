// -----------------------------------------------------------------------
// fifo_if.sv
// DUT interface with driver/monitor clocking blocks.
//
// The clocking blocks aren't cosmetic: the standalone (non-UVM) checker
// in sim/check_rtl.sv hit a real race condition when it read wr_en/
// rd_en/full/empty/rd_data directly inside a posedge-triggered process,
// without any skew -- some reads landed before the DUT's NBAs committed
// for that edge, some landed after. A driver clocking block applies an
// output skew when it drives signals, and a monitor clocking block
// applies an input skew when it samples them, so both are guaranteed
// race-free relative to the DUT's own posedge-triggered always_ff
// blocks. This is exactly what drv_cb/mon_cb are for below.
// -----------------------------------------------------------------------
interface fifo_if #(parameter DATA_WIDTH = 8) (input logic clk);
  logic                  rst_n;
  logic                  wr_en;
  logic                  rd_en;
  logic [DATA_WIDTH-1:0] wr_data;
  logic [DATA_WIDTH-1:0] rd_data;
  logic                  full;
  logic                  empty;

  clocking drv_cb @(posedge clk);
    output wr_en, rd_en, wr_data;
  endclocking

  clocking mon_cb @(posedge clk);
    input wr_en, rd_en, wr_data, rd_data, full, empty;
  endclocking

endinterface
