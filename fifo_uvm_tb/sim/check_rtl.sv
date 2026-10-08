// -----------------------------------------------------------------------
// check_rtl.sv
// Quick non-UVM sanity testbench. Plain SystemVerilog, runs on Icarus.
// Exercises random traffic + full/empty corner cases and checks DUT
// output against a software reference queue, using the SAME one-cycle-
// latency timing model that the UVM scoreboard (fifo_pkg.sv) uses.
//
// Timing note: wr_en/rd_en/wr_data are set with BLOCKING assignment well
// before each posedge, so they are already stable pre-edge values by the
// time the edge fires. full/empty are continuous (combinational) outputs
// of registered pointers, so at the posedge's active region (before NBA
// commits) they still reflect pre-edge pointer state. rd_data is itself
// a registered signal, so at that same point it still holds the result
// of the PREVIOUS edge's read. Reading all of these directly in a single
// always @(posedge clk) block therefore gives a consistent, race-free
// snapshot per cycle -- this exists to validate the RTL and the timing
// model independently, since Icarus Verilog cannot run the real UVM
// class library.
// -----------------------------------------------------------------------
`timescale 1ns/1ps

module check_rtl;
  localparam DATA_WIDTH = 8;
  localparam DEPTH      = 16;

  logic clk = 0;
  logic rst_n;
  logic wr_en, rd_en;
  logic [DATA_WIDTH-1:0] wr_data;
  logic [DATA_WIDTH-1:0] rd_data;
  logic full, empty;

  always #5 clk = ~clk;

  sync_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) dut (
    .clk(clk), .rst_n(rst_n),
    .wr_en(wr_en), .rd_en(rd_en), .wr_data(wr_data),
    .rd_data(rd_data), .full(full), .empty(empty)
  );

  // software reference model -- plain circular buffers, NOT SystemVerilog
  // queues. Icarus Verilog's queue (.pop_front/.size on $-sized arrays)
  // support is unreliable, so this checker avoids it entirely; the real
  // UVM scoreboard (fifo_pkg.sv) still uses queues, which VCS/Questa/
  // EDA Playground support correctly.
  localparam MODEL_DEPTH = 4096;
  bit [DATA_WIDTH-1:0] model_buf [0:MODEL_DEPTH-1];
  int model_wr, model_rd;

  bit [DATA_WIDTH-1:0] exp_buf [0:MODEL_DEPTH-1];
  int exp_wr, exp_rd;

  int num_checked = 0;
  int num_errors  = 0;
  int num_writes  = 0;
  int num_reads   = 0;

  // Declared at module scope and assigned (not inline-initialized) inside
  // the always block below: a variable declared WITH an initializer
  // inside a procedural block defaults to one-time/static init in this
  // context (Icarus warns about this) -- it would only pick up exp_buf's
  // value once, at time 0, and silently keep that stale value on every
  // later re-entry into the block, which is exactly the bug this
  // comment is here to stop someone from reintroducing.
  bit [DATA_WIDTH-1:0] exp_val;

  // Icarus does not cleanly separate active/NBA regions across module
  // boundaries for signals like full/empty/rd_data that are derived from
  // NBA-updated registers: reading them directly in a posedge-triggered
  // testbench process raced with the DUT's own posedge process (observed
  // empirically -- a write was dropped because the checker saw the
  // POST-update "full" instead of the pre-edge value the DUT itself used).
  // Fix: shadow-sample full/empty/rd_data at negedge, a clean half-cycle
  // after the DUT's NBAs have settled with nothing else active. This is
  // the same problem SystemVerilog clocking blocks solve for a real UVM
  // monitor (input skew sampling) -- here it's done by hand.
  logic s_full, s_empty;
  logic [DATA_WIDTH-1:0] s_rd_data;

  always @(negedge clk) begin
    if (rst_n) begin
      s_full    <= full;
      s_empty   <= empty;
      s_rd_data <= rd_data;
    end
  end

  always @(posedge clk) begin
    if (rst_n) begin
      // 1) check any pending read expectation against s_rd_data
      //    (captured at the preceding negedge = result of the previous
      //    cycle's read, race-free)
      if (exp_rd != exp_wr) begin
        exp_val = exp_buf[exp_rd];
        exp_rd  = (exp_rd + 1) % MODEL_DEPTH;
        num_checked++;
        if (exp_val !== s_rd_data) begin
          num_errors++;
          $display("[%0t] MISMATCH: expected=0x%0h got=0x%0h", $time, exp_val, s_rd_data);
        end
      end

      // 2) apply this cycle's write to the reference model
      //    (wr_en/wr_data are safely pre-edge -- driven with blocking
      //    assignment well before this edge. s_full is the negedge-
      //    shadowed value, matching what the DUT itself used to gate)
      if (wr_en && !s_full) begin
        model_buf[model_wr] = wr_data;
        model_wr = (model_wr + 1) % MODEL_DEPTH;
        num_writes++;
      end

      // 3) apply this cycle's read: pop reference model, queue for
      //    comparison against s_rd_data on the NEXT posedge
      if (rd_en && !s_empty) begin
        if (model_rd == model_wr) begin
          num_errors++;
          $display("[%0t] ERROR: DUT read succeeded but reference model empty", $time);
        end else begin
          exp_buf[exp_wr] = model_buf[model_rd];
          exp_wr  = (exp_wr + 1) % MODEL_DEPTH;
          model_rd = (model_rd + 1) % MODEL_DEPTH;
          num_reads++;
        end
      end
    end
  end

  // NONBLOCKING drive: setting wr_en/rd_en/wr_data right after
  // @(posedge clk) returns, with a BLOCKING assignment, races against
  // other processes (the DUT, the checker) also triggered by that same
  // edge -- whoever evaluates first wins, which caused an extra write to
  // sneak in a cycle early during debugging. Nonblocking assignment
  // defers the update to the NBA region, so it's guaranteed invisible to
  // anything still evaluating the edge that just fired, and only takes
  // effect for the next edge -- standard testbench practice.
  bit w, r;

  task automatic step(bit w, bit r, bit [DATA_WIDTH-1:0] d);
    wr_en <= w; rd_en <= r; wr_data <= d;
    @(posedge clk);
  endtask

  initial begin
    wr_en = 0; rd_en = 0; wr_data = '0;
    rst_n = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // 1) fill the FIFO completely, then attempt 4 extra writes (should be dropped)
    for (int i = 0; i < DEPTH + 4; i++)
      step(1, 0, i[7:0]);

    // 2) drain completely, then attempt 4 extra reads (should be no-ops)
    for (int i = 0; i < DEPTH + 4; i++)
      step(0, 1, '0);

    // 3) randomized mixed traffic incl. simultaneous read+write.
    //    w/r are declared OUTSIDE the loop and assigned with blocking
    //    "=" below, not declared-with-initializer inside the loop body
    //    -- that pattern hit the same one-time-static-init trap as
    //    exp_val above and silently froze w/r at their first values
    //    for every later iteration.
    for (int i = 0; i < 2000; i++) begin
      w = $urandom_range(0, 1);
      r = $urandom_range(0, 1);
      step(w, r, $urandom_range(0, 255));
    end

    // drain any remainder so final checks land
    repeat (DEPTH + 2) step(0, 1, '0);
    repeat (2) @(posedge clk);

    $display("--------------------------------------------------");
    $display("writes=%0d reads=%0d checked=%0d errors=%0d", num_writes, num_reads, num_checked, num_errors);
    if (num_errors == 0)
      $display("*** CHECK_RTL: ALL CHECKS PASSED ***");
    else
      $display("*** CHECK_RTL: %0d MISMATCHES ***", num_errors);
    $display("--------------------------------------------------");
    $finish;
  end
endmodule
