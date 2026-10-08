# UVM Testbench for a Synchronous FIFO

SystemVerilog + UVM 1.2 verification environment for a parameterized synchronous FIFO
(8-bit data, 16 deep, extra-MSB pointer full/empty detection).

## What's in it

| File | Purpose |
|---|---|
| `rtl/sync_fifo.sv` | DUT |
| `tb/fifo_if.sv` | Interface with driver/monitor clocking blocks |
| `tb/fifo_pkg.sv` | Transaction, 4 sequences, driver, monitor, scoreboard, covergroup, agent, env, 5 tests |
| `tb/fifo_tb_top.sv` | Top: clock/reset, DUT, config_db, `run_test()` |
| `sim/check_rtl.sv` | Non-UVM sanity check of the RTL + scoreboard timing model (runs on Icarus) |
| `sim/Makefile` | Run targets for VCS / Questa / Xcelium |

## Verification features

- Constrained-random stimulus (weighted `dist` on wr_en/rd_en)
- Directed sequences: fill-to-full + overflow attempts, read-while-empty, simultaneous R/W
- Scoreboard with reference queue and one-cycle read-latency model
- Functional coverage: wr_en/rd_en/full/empty, data-range bins, crosses for write-while-full,
  read-while-empty, simultaneous R/W
- Regression test combining all directed sequences with a 500-item random tail

## Running

**EDA Playground (free):** pick SystemVerilog/Verilog, UVM 1.2, a simulator with UVM support
(Synopsys VCS or Aldec Riviera-PRO), paste `sync_fifo.sv`, `fifo_if.sv`, `fifo_pkg.sv` and
`fifo_tb_top.sv` into design/testbench panes (package must compile before top), run option
`+UVM_TESTNAME=fifo_regression_test`, enable coverage.

**Local commercial tools:** `cd sim && make vcs` / `make questa` / `make xcelium`.

## Verification status (be honest about this in interviews)

- **Verified in sandbox:** RTL and the scoreboard's timing algorithm, using `sim/check_rtl.sv`
  on Icarus: 995 writes / 995 reads / 995 data checks, 0 errors.
- **NOT yet compiled or run:** the UVM code (`fifo_pkg.sv`, `fifo_tb_top.sv`). Icarus cannot
  parse the UVM library, so this has never been through a real UVM simulator. Expect to fix
  small compile errors on the first VCS/Questa run. Do that before putting numbers on a resume.
- Coverage % is not yet measured. Run `fifo_regression_test`, read the number, and report
  that one.

## Bugs hit while building the checker (worth knowing, good interview material)

1. Blocking-assign driving right after `@(posedge clk)` raced with the DUT and let a write
   through one cycle early. Fix: nonblocking drive, which is what a clocking block does for you.
2. Variables declared with an initializer inside a procedural block ran their initializer once,
   freezing `exp_val` and the random `w`/`r` values. Fix: declare outside, assign inside.
3. Icarus queue support was unreliable, so the checker uses plain circular buffers.

## Resume bullets (use only after a real run, and fill in the measured numbers)

- Built a UVM 1.2 verification environment for a parameterized synchronous FIFO: constrained-random
  and directed sequences, reference-model scoreboard, and functional coverage with crosses
- Closed __% functional coverage on <VCS/Questa/Riviera-PRO> across 5 tests incl. full/empty
  corner cases and simultaneous read/write
