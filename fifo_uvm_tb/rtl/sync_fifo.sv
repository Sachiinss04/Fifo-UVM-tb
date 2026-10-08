// -----------------------------------------------------------------------
// sync_fifo.sv
// Parameterized synchronous FIFO, single clock domain.
// Full/empty detection uses the classic extra-MSB pointer-wrap technique.
// -----------------------------------------------------------------------
module sync_fifo #(
  parameter int DATA_WIDTH = 8,
  parameter int DEPTH      = 16
)(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  wr_en,
  input  logic                  rd_en,
  input  logic [DATA_WIDTH-1:0] wr_data,
  output logic [DATA_WIDTH-1:0] rd_data,
  output logic                  full,
  output logic                  empty
);

  localparam int PTR_WIDTH = $clog2(DEPTH);

  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  logic [PTR_WIDTH:0]    wr_ptr, rd_ptr;

  // full  : pointers equal in index bits but differ in the wrap (MSB) bit
  // empty : pointers fully equal
  assign full  = (wr_ptr[PTR_WIDTH] != rd_ptr[PTR_WIDTH]) &&
                 (wr_ptr[PTR_WIDTH-1:0] == rd_ptr[PTR_WIDTH-1:0]);
  assign empty = (wr_ptr == rd_ptr);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
    end else if (wr_en && !full) begin
      mem[wr_ptr[PTR_WIDTH-1:0]] <= wr_data;
      wr_ptr                    <= wr_ptr + 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr  <= '0;
      rd_data <= '0;
    end else if (rd_en && !empty) begin
      rd_data <= mem[rd_ptr[PTR_WIDTH-1:0]];
      rd_ptr  <= rd_ptr + 1'b1;
    end
  end

endmodule
