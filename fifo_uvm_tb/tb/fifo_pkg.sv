// -----------------------------------------------------------------------
// fifo_pkg.sv
// UVM testbench for sync_fifo.sv.
//
// Requires a real UVM 1.2 class library (VCS / Questa / Xcelium / Aldec
// Riviera-PRO on EDA Playground). Icarus Verilog cannot run this -- it
// does not ship or support the UVM base classes. See ../README.md for
// how to run it.
//
// The driver/monitor use the interface's clocking blocks (drv_cb/
// mon_cb) specifically to avoid the clock-edge sampling race documented
// in ../sim/check_rtl.sv and ../tb/fifo_if.sv -- a plain `@(posedge clk)`
// read of full/empty/rd_data inside a testbench process is not
// guaranteed to be race-free against the DUT's own always_ff blocks.
// -----------------------------------------------------------------------
`ifndef FIFO_PKG_SV
`define FIFO_PKG_SV

package fifo_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  //-------------------------------------------------------------------
  // Transaction
  //-------------------------------------------------------------------
  class fifo_item extends uvm_sequence_item;
    rand bit       wr_en;
    rand bit       rd_en;
    rand bit [7:0] wr_data;

    // observed fields, filled in by the monitor on the way out
    bit [7:0] rd_data;
    bit       full;
    bit       empty;

    // weight toward normal single-op traffic but keep idle/simultaneous
    // cycles common enough to exercise those corners under random too
    constraint c_dist {
      wr_en dist { 1 := 45, 0 := 55 };
      rd_en dist { 1 := 45, 0 := 55 };
    }

    `uvm_object_utils_begin(fifo_item)
      `uvm_field_int(wr_en,   UVM_ALL_ON)
      `uvm_field_int(rd_en,   UVM_ALL_ON)
      `uvm_field_int(wr_data, UVM_ALL_ON)
      `uvm_field_int(rd_data, UVM_ALL_ON | UVM_NOCOMPARE)
      `uvm_field_int(full,    UVM_ALL_ON | UVM_NOCOMPARE)
      `uvm_field_int(empty,   UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_object_utils_end

    function new(string name = "fifo_item");
      super.new(name);
    endfunction
  endclass

  //-------------------------------------------------------------------
  // Sequences
  //-------------------------------------------------------------------
  class fifo_base_seq extends uvm_sequence #(fifo_item);
    `uvm_object_utils(fifo_base_seq)
    int unsigned num_items = 200;

    function new(string name = "fifo_base_seq");
      super.new(name);
    endfunction

    task body();
      fifo_item item;
      repeat (num_items) begin
        item = fifo_item::type_id::create("item");
        start_item(item);
        if (!item.randomize())
          `uvm_error("SEQ", "Randomization failed")
        finish_item(item);
      end
    endtask
  endclass

  // Directed: fill the FIFO completely, then keep writing a few more
  // cycles to exercise the write-while-full path.
  class fifo_full_seq extends uvm_sequence #(fifo_item);
    `uvm_object_utils(fifo_full_seq)
    int unsigned depth = 16;

    function new(string name = "fifo_full_seq");
      super.new(name);
    endfunction

    task body();
      fifo_item item;
      repeat (depth + 4) begin
        item = fifo_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with { wr_en == 1; rd_en == 0; })
          `uvm_error("SEQ", "Randomization failed")
        finish_item(item);
      end
    endtask
  endclass

  // Directed: drain an already-empty FIFO, then keep reading a few more
  // cycles to exercise the read-while-empty path.
  class fifo_empty_seq extends uvm_sequence #(fifo_item);
    `uvm_object_utils(fifo_empty_seq)

    function new(string name = "fifo_empty_seq");
      super.new(name);
    endfunction

    task body();
      fifo_item item;
      repeat (6) begin
        item = fifo_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with { wr_en == 0; rd_en == 1; })
          `uvm_error("SEQ", "Randomization failed")
        finish_item(item);
      end
    endtask
  endclass

  // Directed: simultaneous read+write every cycle.
  class fifo_simul_seq extends uvm_sequence #(fifo_item);
    `uvm_object_utils(fifo_simul_seq)
    int unsigned num_items = 40;

    function new(string name = "fifo_simul_seq");
      super.new(name);
    endfunction

    task body();
      fifo_item item;
      repeat (num_items) begin
        item = fifo_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with { wr_en == 1; rd_en == 1; })
          `uvm_error("SEQ", "Randomization failed")
        finish_item(item);
      end
    endtask
  endclass

  //-------------------------------------------------------------------
  // Driver
  //-------------------------------------------------------------------
  class fifo_driver extends uvm_driver #(fifo_item);
    `uvm_component_utils(fifo_driver)
    virtual fifo_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "virtual interface not set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      vif.drv_cb.wr_en   <= 0;
      vif.drv_cb.rd_en   <= 0;
      vif.drv_cb.wr_data <= '0;
      wait (vif.rst_n == 1);

      forever begin
        fifo_item item;
        seq_item_port.get_next_item(item);
        vif.drv_cb.wr_en   <= item.wr_en;
        vif.drv_cb.rd_en   <= item.rd_en;
        vif.drv_cb.wr_data <= item.wr_data;
        @(vif.drv_cb);
        seq_item_port.item_done();
      end
    endtask
  endclass

  //-------------------------------------------------------------------
  // Monitor
  //-------------------------------------------------------------------
  class fifo_monitor extends uvm_component;
    `uvm_component_utils(fifo_monitor)
    virtual fifo_if vif;
    uvm_analysis_port #(fifo_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
        `uvm_fatal("MON", "virtual interface not set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      wait (vif.rst_n == 1);
      forever begin
        fifo_item item = fifo_item::type_id::create("item");
        @(vif.mon_cb);
        item.wr_en   = vif.mon_cb.wr_en;
        item.rd_en   = vif.mon_cb.rd_en;
        item.wr_data = vif.mon_cb.wr_data;
        item.rd_data = vif.mon_cb.rd_data;
        item.full    = vif.mon_cb.full;
        item.empty   = vif.mon_cb.empty;
        ap.write(item);
      end
    endtask
  endclass

  //-------------------------------------------------------------------
  // Scoreboard
  //
  // Timing model: mon_cb's input skew samples each signal just before
  // its posedge, i.e. the same pre-edge values the DUT's own always_ff
  // blocks use to decide whether to accept a write/read that edge. Since
  // rd_data is itself a registered output, that same pre-edge sample is
  // the result of whatever read was issued on the PREVIOUS edge (if any)
  // -- it hasn't been overwritten yet for the current edge. So on every
  // item: first check expected_q against this item's rd_data (closing
  // out last cycle's read, if one was issued), THEN apply this item's
  // own write/read to the model. This ordering is the whole trick and
  // is exactly what sim/check_rtl.sv validates against the real RTL
  // before this scoreboard is ever run against it.
  //-------------------------------------------------------------------
  class fifo_scoreboard extends uvm_component;
    `uvm_component_utils(fifo_scoreboard)
    uvm_analysis_imp #(fifo_item, fifo_scoreboard) ap_imp;

    bit [7:0] model_q[$];
    bit [7:0] expected_q[$];

    int unsigned num_checked;
    int unsigned num_errors;
    int unsigned num_writes;
    int unsigned num_reads;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap_imp = new("ap_imp", this);
    endfunction

    function void write(fifo_item item);
      // 1) check any pending read expectation against this cycle's rd_data
      if (expected_q.size() > 0) begin
        bit [7:0] exp_val = expected_q.pop_front();
        num_checked++;
        if (exp_val !== item.rd_data) begin
          num_errors++;
          `uvm_error("SCB", $sformatf(
            "DATA MISMATCH: expected=0x%0h got=0x%0h", exp_val, item.rd_data))
        end
      end

      // 2) apply this cycle's write to the reference model
      if (item.wr_en && !item.full) begin
        model_q.push_back(item.wr_data);
        num_writes++;
      end

      // 3) apply this cycle's read: pop reference model, queue for
      //    comparison against the NEXT item's rd_data
      if (item.rd_en && !item.empty) begin
        if (model_q.size() == 0) begin
          num_errors++;
          `uvm_error("SCB", "DUT asserted a successful read but reference model is empty")
        end else begin
          expected_q.push_back(model_q.pop_front());
          num_reads++;
        end
      end
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("SCB", $sformatf(
        "writes=%0d reads=%0d checked=%0d errors=%0d",
        num_writes, num_reads, num_checked, num_errors), UVM_LOW)
      if (num_errors == 0)
        `uvm_info("SCB", "*** FIFO SCOREBOARD: ALL CHECKS PASSED ***", UVM_NONE)
      else
        `uvm_error("SCB", $sformatf("*** FIFO SCOREBOARD: %0d MISMATCHES ***", num_errors))
    endfunction
  endclass

  //-------------------------------------------------------------------
  // Functional coverage
  //-------------------------------------------------------------------
  class fifo_coverage extends uvm_component;
    `uvm_component_utils(fifo_coverage)
    uvm_analysis_imp #(fifo_item, fifo_coverage) ap_imp;
    fifo_item item;

    covergroup cg;
      option.per_instance = 1;

      cp_wr_en: coverpoint item.wr_en;
      cp_rd_en: coverpoint item.rd_en;
      cp_full:  coverpoint item.full;
      cp_empty: coverpoint item.empty;

      cp_wr_data: coverpoint item.wr_data {
        bins low   = {[0:63]};
        bins mid   = {[64:191]};
        bins high  = {[192:255]};
        bins all_0 = {8'h00};
        bins all_1 = {8'hFF};
      }

      cx_write_while_full: cross cp_wr_en, cp_full;
      cx_read_while_empty: cross cp_rd_en, cp_empty;
      cx_simultaneous_rw:  cross cp_wr_en, cp_rd_en;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap_imp = new("ap_imp", this);
      cg = new();
    endfunction

    function void write(fifo_item t);
      item = t;
      cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("Functional coverage = %0.2f%%", cg.get_coverage()), UVM_NONE)
    endfunction
  endclass

  //-------------------------------------------------------------------
  // Agent / Environment
  //-------------------------------------------------------------------
  class fifo_agent extends uvm_agent;
    `uvm_component_utils(fifo_agent)
    fifo_driver           drv;
    fifo_monitor          mon;
    uvm_sequencer #(fifo_item) sqr;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv = fifo_driver::type_id::create("drv", this);
      mon = fifo_monitor::type_id::create("mon", this);
      sqr = uvm_sequencer#(fifo_item)::type_id::create("sqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  class fifo_env extends uvm_env;
    `uvm_component_utils(fifo_env)
    fifo_agent      agent;
    fifo_scoreboard scb;
    fifo_coverage   cov;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = fifo_agent::type_id::create("agent", this);
      scb   = fifo_scoreboard::type_id::create("scb", this);
      cov   = fifo_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      agent.mon.ap.connect(scb.ap_imp);
      agent.mon.ap.connect(cov.ap_imp);
    endfunction
  endclass

  //-------------------------------------------------------------------
  // Tests
  //-------------------------------------------------------------------
  class fifo_base_test extends uvm_test;
    `uvm_component_utils(fifo_base_test)
    fifo_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = fifo_env::type_id::create("env", this);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
      uvm_top.print_topology();
    endfunction
  endclass

  class fifo_random_test extends fifo_base_test;
    `uvm_component_utils(fifo_random_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      fifo_base_seq seq = fifo_base_seq::type_id::create("seq");
      phase.raise_objection(this);
      seq.num_items = 300;
      seq.start(env.agent.sqr);
      phase.drop_objection(this);
    endtask
  endclass

  class fifo_full_test extends fifo_base_test;
    `uvm_component_utils(fifo_full_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      fifo_full_seq seq = fifo_full_seq::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sqr);
      phase.drop_objection(this);
    endtask
  endclass

  class fifo_empty_test extends fifo_base_test;
    `uvm_component_utils(fifo_empty_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      fifo_empty_seq seq = fifo_empty_seq::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sqr);
      phase.drop_objection(this);
    endtask
  endclass

  class fifo_simul_test extends fifo_base_test;
    `uvm_component_utils(fifo_simul_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      fifo_simul_seq seq = fifo_simul_seq::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sqr);
      phase.drop_objection(this);
    endtask
  endclass

  // Regression: all directed scenarios back-to-back, then a long random
  // tail, for closing coverage in one run.
  class fifo_regression_test extends fifo_base_test;
    `uvm_component_utils(fifo_regression_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      fifo_full_seq  full_seq;
      fifo_empty_seq empty_seq;
      fifo_simul_seq simul_seq;
      fifo_base_seq  rand_seq;

      phase.raise_objection(this);

      full_seq = fifo_full_seq::type_id::create("full_seq");
      full_seq.start(env.agent.sqr);

      empty_seq = fifo_empty_seq::type_id::create("empty_seq");
      empty_seq.start(env.agent.sqr);

      simul_seq = fifo_simul_seq::type_id::create("simul_seq");
      simul_seq.start(env.agent.sqr);

      rand_seq = fifo_base_seq::type_id::create("rand_seq");
      rand_seq.num_items = 500;
      rand_seq.start(env.agent.sqr);

      phase.drop_objection(this);
    endtask
  endclass

endpackage

`endif // FIFO_PKG_SV
