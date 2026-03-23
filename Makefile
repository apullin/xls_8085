# Makefile - CPU core tests and benchmarks
#
# Usage:
#   make test          # Run all tests (j8085 + i8085 + benchmarks)
#   make test-j8085    # j8085 pipelined core unit tests (66 tests)
#   make test-i8085    # i8085 FSM core unit tests (60 tests)
#   make bench         # Software benchmarks on both cores
#   make bench-j8085   # Benchmarks on j8085 only
#   make bench-i8085   # Benchmarks on i8085 only
#   make clean         # Remove build artifacts

IVERILOG ?= iverilog
VVP ?= vvp
IVFLAGS := -g2012

BUILD := build/test

# Source files
J8085_CORE := j8085/j8085_cpu.v j8085/j8085_alu.v j8085/j8085_decode.v
I8085_CORE := i8085/i8085_cpu.v i8085/i8085_core_parity_opt.v i8085/i8085_decode.v
MEM_SIM    := j8085/j8085_mem_sim.v

.PHONY: test test-j8085 test-i8085 bench bench-j8085 bench-i8085 clean

$(BUILD):
	@mkdir -p $@

# ── Unit tests ─────────────────────────────────────────────

test: test-j8085 test-i8085

$(BUILD)/j8085_test: j8085/j8085_tb.v $(J8085_CORE) $(MEM_SIM) | $(BUILD)
	@$(IVERILOG) $(IVFLAGS) -o $@ $^

$(BUILD)/i8085_test: j8085/i8085_compare_tb.v $(I8085_CORE) $(MEM_SIM) | $(BUILD)
	@$(IVERILOG) $(IVFLAGS) -o $@ $^

test-j8085: $(BUILD)/j8085_test
	@echo "=== j8085 pipelined core ==="
	@$(VVP) $< | tail -5

test-i8085: $(BUILD)/i8085_test
	@echo "=== i8085 FSM core ==="
	@$(VVP) $< | tail -3

# ── Benchmarks ─────────────────────────────────────────────

bench: bench-j8085 bench-i8085

$(BUILD)/bench_j8085: test/benchmark_tb.v $(J8085_CORE) $(MEM_SIM) | $(BUILD)
	@$(IVERILOG) $(IVFLAGS) -o $@ $^

$(BUILD)/bench_i8085: test/benchmark_fsm_tb.v $(I8085_CORE) $(MEM_SIM) | $(BUILD)
	@$(IVERILOG) $(IVFLAGS) -o $@ $^

bench-j8085: $(BUILD)/bench_j8085
	@echo "=== j8085 benchmarks ==="
	@$(VVP) $<

bench-i8085: $(BUILD)/bench_i8085
	@echo "=== i8085 benchmarks ==="
	@$(VVP) $<

# ── Clean ──────────────────────────────────────────────────

clean:
	rm -rf $(BUILD)
