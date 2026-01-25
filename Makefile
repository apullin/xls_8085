# Intel 8085 CPU Core - Build System
#
# Configurations:
#   i8085_test       - Validation target (unconstrained, max Fmax)
#   i8085_dip40      - True DIP40 drop-in replacement
#   i8085_dip40_plus - Enhanced drop-in with internal resources (UP5K)
#   i8085_mcu        - MCU with Timer, GPIO, 2x UART (UP5K)
#
# Targets:
#   make test        - Run DSLX tests
#   make verilog     - Generate all Verilog from DSLX
#
#   make test-synth       - Synthesize i8085_test (unconstrained)
#   make dip40-synth      - Synthesize i8085_dip40
#   make dip40-plus-synth - Synthesize i8085_dip40_plus for UP5K
#   make mcu-synth        - Synthesize i8085_mcu with peripherals
#
#   make clean       - Remove generated files
#
# Prerequisites:
#   - XLS tools (native macOS or Linux x64)
#   - Yosys and nextpnr-ice40 for synthesis

# Platform detection
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# XLS tool paths - native builds preferred
ifeq ($(UNAME_S),Darwin)
    # macOS: use prebuilt native tools
    XLS_DIR := /Users/andrewpullin/personal/xls/xls-src/bin
else ifeq ($(UNAME_S),Linux)
    ifeq ($(UNAME_M),x86_64)
        # Linux x64: use native binaries
        XLS_DIR := ./tools/xls-bin
    else
        $(error Unsupported platform: $(UNAME_S) $(UNAME_M))
    endif
else
    $(error Unsupported platform: $(UNAME_S))
endif

# XLS tool commands
INTERPRETER := $(XLS_DIR)/dslx_interpreter_main
IR_CONVERTER := $(XLS_DIR)/ir_converter_main
OPT := $(XLS_DIR)/opt_main
CODEGEN := $(XLS_DIR)/codegen_main

# Codegen flags for Yosys compatibility (no SystemVerilog)
CODEGEN_FLAGS := --generator=combinational --delay_model=unit --use_system_verilog=false

# Synthesis tools
YOSYS := yosys
NEXTPNR := nextpnr-ice40

# Source files
DSLX_CORE := i8085_core.x
DSLX_CACHE := cache_logic.x
DSLX_TIMER := periph/timer16.x
DSLX_GPIO := periph/gpio8.x
DSLX_UART := periph/uart.x
DSLX_SPI := periph/spi.x

# Generated Verilog
CORE_V := i8085_core.v
CACHE_V := cache_logic.v
TIMER_V := periph/timer16.v
GPIO_V := periph/gpio8.v
UART_V := periph/uart.v
SPI_V := periph/spi.v

# All generated Verilog
ALL_DSLX_V := $(CORE_V) $(CACHE_V) $(TIMER_V) $(GPIO_V) $(UART_V) $(SPI_V)

# Common Verilog sources
COMMON_V := $(CORE_V) i8085_wrapper.v

# Configuration-specific sources
TEST_V := $(COMMON_V) $(CACHE_V) spi_engine.v spi_flash_cache.v i8085_test.v
DIP40_V := $(COMMON_V) i8085_dip40.v
DIP40_PLUS_V := $(COMMON_V) $(CACHE_V) spi_engine.v spi_flash_cache.v i8085_dip40_plus.v
MCU_V := $(COMMON_V) $(CACHE_V) spi_engine.v spi_flash_cache.v \
         $(TIMER_V) periph/timer16_wrapper.v \
         $(GPIO_V) periph/gpio8_wrapper.v \
         $(UART_V) periph/uart_wrapper.v \
         $(SPI_V) periph/spi_wrapper.v \
         periph/i2c_wrapper.v \
         periph/imath_wrapper.v \
         periph/vmath_wrapper.v \
         i8085_mcu.v

.PHONY: all test verilog clean cleanall help
.PHONY: test-synth dip40-synth dip40-plus-synth mcu-synth
.PHONY: test-core test-cache test-timer test-gpio test-uart test-spi

# Default target
all: verilog

help:
	@echo "Intel 8085 CPU Core - Build System"
	@echo ""
	@echo "Build targets:"
	@echo "  make test        - Run all DSLX tests"
	@echo "  make verilog     - Generate all Verilog from DSLX"
	@echo ""
	@echo "Synthesis targets:"
	@echo "  make test-synth       - i8085_test (UP5K, unconstrained)"
	@echo "  make dip40-synth      - i8085_dip40 (true drop-in)"
	@echo "  make dip40-plus-synth - i8085_dip40_plus (UP5K, enhanced)"
	@echo "  make mcu-synth        - i8085_mcu with peripherals (UP5K)"
	@echo ""
	@echo "  make clean       - Remove generated files"
	@echo ""
	@echo "Platform: $(UNAME_S) $(UNAME_M)"
	@echo "XLS tools: $(XLS_DIR)"

#------------------------------------------------------------------------------
# Test targets
#------------------------------------------------------------------------------

test: test-core test-cache test-timer test-gpio test-uart test-spi
	@echo ""
	@echo "=== All tests passed ==="

test-core:
	@echo "Testing i8085_core.x..."
	@$(INTERPRETER) $(DSLX_CORE)

test-cache:
	@echo "Testing cache_logic.x..."
	@$(INTERPRETER) $(DSLX_CACHE)

test-timer:
	@echo "Testing timer16.x..."
	@$(INTERPRETER) $(DSLX_TIMER)

test-gpio:
	@echo "Testing gpio8.x..."
	@$(INTERPRETER) $(DSLX_GPIO)

test-uart:
	@echo "Testing uart.x..."
	@$(INTERPRETER) $(DSLX_UART)

test-spi:
	@echo "Testing spi.x..."
	@$(INTERPRETER) $(DSLX_SPI)

#------------------------------------------------------------------------------
# Verilog generation
#------------------------------------------------------------------------------

verilog: $(ALL_DSLX_V)
	@echo ""
	@echo "=== All Verilog generated ==="

# Generic pattern: DSLX -> IR -> optimized IR -> Verilog
# CPU core
$(CORE_V): $(DSLX_CORE)
	@echo "Generating $@..."
	@$(IR_CONVERTER) $< --top=execute > /tmp/$(notdir $<).ir
	@$(OPT) /tmp/$(notdir $<).ir > /tmp/$(notdir $<).opt.ir
	@$(CODEGEN) /tmp/$(notdir $<).opt.ir --output_verilog_path=$@ $(CODEGEN_FLAGS)

# Cache logic
$(CACHE_V): $(DSLX_CACHE)
	@echo "Generating $@..."
	@$(IR_CONVERTER) $< --top=cache_lookup > /tmp/$(notdir $<).ir
	@$(OPT) /tmp/$(notdir $<).ir > /tmp/$(notdir $<).opt.ir
	@$(CODEGEN) /tmp/$(notdir $<).opt.ir --output_verilog_path=$@ $(CODEGEN_FLAGS)

# Timer
$(TIMER_V): $(DSLX_TIMER)
	@echo "Generating $@..."
	@$(IR_CONVERTER) $< --top=timer_tick > /tmp/$(notdir $<).ir
	@$(OPT) /tmp/$(notdir $<).ir > /tmp/$(notdir $<).opt.ir
	@$(CODEGEN) /tmp/$(notdir $<).opt.ir --output_verilog_path=$@ $(CODEGEN_FLAGS)

# GPIO
$(GPIO_V): $(DSLX_GPIO)
	@echo "Generating $@..."
	@$(IR_CONVERTER) $< --top=gpio_tick > /tmp/$(notdir $<).ir
	@$(OPT) /tmp/$(notdir $<).ir > /tmp/$(notdir $<).opt.ir
	@$(CODEGEN) /tmp/$(notdir $<).opt.ir --output_verilog_path=$@ $(CODEGEN_FLAGS)

# UART
$(UART_V): $(DSLX_UART)
	@echo "Generating $@..."
	@$(IR_CONVERTER) $< --top=uart_tick > /tmp/$(notdir $<).ir
	@$(OPT) /tmp/$(notdir $<).ir > /tmp/$(notdir $<).opt.ir
	@$(CODEGEN) /tmp/$(notdir $<).opt.ir --output_verilog_path=$@ $(CODEGEN_FLAGS)

# SPI
$(SPI_V): $(DSLX_SPI)
	@echo "Generating $@..."
	@$(IR_CONVERTER) $< --top=spi_tick_fn > /tmp/$(notdir $<).ir
	@$(OPT) /tmp/$(notdir $<).ir > /tmp/$(notdir $<).opt.ir
	@$(CODEGEN) /tmp/$(notdir $<).opt.ir --output_verilog_path=$@ $(CODEGEN_FLAGS)

#------------------------------------------------------------------------------
# Synthesis: i8085_test (validation target, unconstrained)
#------------------------------------------------------------------------------

test-synth: $(CORE_V) $(CACHE_V) i8085_test.json
	@echo ""
	@echo "=== i8085_test synthesis complete ==="

i8085_test.json: $(TEST_V)
	@echo "Synthesizing i8085_test..."
	@$(YOSYS) -q -p "read_verilog -sv $(TEST_V); synth_ice40 -top i8085_test -json $@"

#------------------------------------------------------------------------------
# Synthesis: i8085_dip40 (true drop-in replacement)
#------------------------------------------------------------------------------

dip40-synth: $(CORE_V) i8085_dip40.json
	@echo ""
	@echo "=== i8085_dip40 synthesis complete ==="

i8085_dip40.json: $(DIP40_V)
	@echo "Synthesizing i8085_dip40..."
	@$(YOSYS) -q -p "read_verilog -sv $(DIP40_V); synth_ice40 -top i8085_dip40 -json $@"

#------------------------------------------------------------------------------
# Synthesis: i8085_dip40_plus (enhanced drop-in)
#------------------------------------------------------------------------------

dip40-plus-synth: $(CORE_V) $(CACHE_V) i8085_dip40_plus.json
	@echo ""
	@echo "=== i8085_dip40_plus synthesis complete ==="

i8085_dip40_plus.json: $(DIP40_PLUS_V)
	@echo "Synthesizing i8085_dip40_plus..."
	@$(YOSYS) -q -p "read_verilog -sv $(DIP40_PLUS_V); synth_ice40 -top i8085_dip40_plus -json $@"

#------------------------------------------------------------------------------
# Synthesis: i8085_mcu (with Timer, GPIO, 2x UART)
#------------------------------------------------------------------------------

mcu-synth: $(ALL_DSLX_V) i8085_mcu.json
	@echo ""
	@echo "=== i8085_mcu synthesis complete ==="

i8085_mcu.json: $(MCU_V)
	@echo "Synthesizing i8085_mcu..."
	@$(YOSYS) -p "read_verilog -sv $(MCU_V); synth_ice40 -dsp -top i8085_mcu -json $@" 2>&1 | tail -30

#------------------------------------------------------------------------------
# Place and Route
#------------------------------------------------------------------------------

test-pnr: i8085_test.json
	@echo "Place-and-route i8085_test..."
	@$(NEXTPNR) --up5k --package sg48 --json $< --asc i8085_test.asc --ignore-loops

dip40-pnr: i8085_dip40.json ice40up5k_dip40.pcf
	@echo "Place-and-route i8085_dip40..."
	@$(NEXTPNR) --up5k --package sg48 --json $< --pcf ice40up5k_dip40.pcf --asc i8085_dip40.asc --ignore-loops

dip40-plus-pnr: i8085_dip40_plus.json ice40up5k_dip40_plus.pcf
	@echo "Place-and-route i8085_dip40_plus..."
	@$(NEXTPNR) --up5k --package sg48 --json $< --pcf ice40up5k_dip40_plus.pcf --asc i8085_dip40_plus.asc --ignore-loops

#------------------------------------------------------------------------------
# Clean
#------------------------------------------------------------------------------

clean:
	rm -f /tmp/*.ir /tmp/*.opt.ir
	rm -f i8085_test.json i8085_test.asc
	rm -f i8085_dip40.json i8085_dip40.asc
	rm -f i8085_dip40_plus.json i8085_dip40_plus.asc
	rm -f i8085_mcu.json i8085_mcu.asc
	@echo "Cleaned generated files (kept .v files)"

cleanall: clean
	rm -f $(ALL_DSLX_V)
	rm -rf tools/xls-bin
	@echo "Cleaned all generated files including Verilog"
