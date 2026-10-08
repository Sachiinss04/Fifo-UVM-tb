# Usage:
#   make check            # Icarus: RTL + reference-model sanity check (no UVM)
#   make vcs   TEST=fifo_regression_test
#   make questa TEST=fifo_regression_test
#   make xcelium TEST=fifo_regression_test
#
# Tests: fifo_random_test fifo_full_test fifo_empty_test fifo_simul_test
#        fifo_regression_test

TEST ?= fifo_regression_test
SRC   = ../rtl/sync_fifo.sv ../tb/fifo_if.sv ../tb/fifo_pkg.sv ../tb/fifo_tb_top.sv

check:
	iverilog -g2012 -o check_rtl.out ../rtl/sync_fifo.sv check_rtl.sv
	vvp check_rtl.out

vcs:
	vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps -cm line+cond+fsm+tgl+branch \
	    $(SRC) -o simv
	./simv +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=UVM_LOW -cm line+cond+fsm+tgl+branch

questa:
	vlib work
	vlog -sv +incdir+$(UVM_HOME)/src $(UVM_HOME)/src/uvm_pkg.sv $(SRC)
	vsim -c -coverage work.fifo_tb_top +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=UVM_LOW \
	     -do "run -all; coverage report -summary; quit"

xcelium:
	xrun -sv -uvm -uvmhome CDNS-1.2 -timescale 1ns/1ps -coverage all \
	     $(SRC) +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=UVM_LOW

clean:
	rm -rf *.out work simv* csrc xcelium.d INCA_libs *.log *.vcd
