# Intel 8085 CPU Core - Build System
#
# Targets:
#   make setup       - Install XLS tools (auto-detects platform)
#   make all         - Generate all Verilog from DSLX and run synthesis
#   make test        - Run DSLX tests
#   make verilog     - Generate Verilog from DSLX
#   make synth       - Synthesize for iCE40 UP5K
#   make clean       - Remove generated files
#
# Prerequisites:
#   - Docker (macOS) or Linux x64
#   - Yosys and nextpnr-ice40 for synthesis

# Platform detection
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Tool paths
ifeq ($(UNAME_S),Darwin)
    # macOS: use Docker wrapper
    XLS := ./tools/xls
    XLS_SETUP := docker_xls
else ifeq ($(UNAME_S),Linux)
    ifeq ($(UNAME_M),x86_64)
        # Linux x64: use native binaries
        XLS_DIR := ./tools/xls-bin
        XLS := $(XLS_DIR)/interpreter_main
        XLS_SETUP := install_xls
    else
        $(error Unsupported platform: $(UNAME_S) $(UNAME_M). XLS only supports Linux x86_64 or macOS via Docker.)
    endif
else
    $(error Unsupported platform: $(UNAME_S). XLS only supports Linux x86_64 or macOS via Docker.)
endif

# XLS tool commands (work for both Docker wrapper and native)
ifeq ($(UNAME_S),Darwin)
    INTERPRETER := $(XLS) interpreter_main
    IR_CONVERTER := $(XLS) ir_converter_main
    OPT := $(XLS) opt_main
    CODEGEN := $(XLS) codegen_main
else
    INTERPRETER := $(XLS_DIR)/interpreter_main
    IR_CONVERTER := $(XLS_DIR)/ir_converter_main
    OPT := $(XLS_DIR)/opt_main
    CODEGEN := $(XLS_DIR)/codegen_main
endif

# Synthesis tools (user must have these installed)
YOSYS := yosys
NEXTPNR := nextpnr-ice40

# Source files
DSLX_CORE := i8085_core.x
DSLX_CACHE := cache_logic.x

# Generated files
CORE_IR := i8085_core.ir
CORE_OPT_IR := i8085_core.opt.ir
CORE_V := i8085_core.v
CORE_SIG := i8085_core.sig.textproto

CACHE_IR := cache_logic.ir
CACHE_OPT_IR := cache_logic.opt.ir
CACHE_V := cache_logic.v

# Synthesis outputs
SOC_JSON := i8085_soc.json
SOC_ASC := i8085_soc.asc
SOC_BIN := i8085_soc.bin

# Verilog sources for synthesis
VERILOG_SRCS := $(CORE_V) $(CACHE_V) i8085_wrapper.v spi_engine.v spi_flash_cache.v i8085_soc.v

.PHONY: all setup test verilog synth synth-check clean docker_xls install_xls help

# Default target (synth-check skips place/route which needs board-specific PCF)
all: verilog synth-check

help:
	@echo "Intel 8085 CPU Core - Build System"
	@echo ""
	@echo "Setup (run first):"
	@echo "  make setup       - Install XLS tools (auto-detects platform)"
	@echo ""
	@echo "Build targets:"
	@echo "  make all         - Generate Verilog and synthesize"
	@echo "  make test        - Run DSLX tests"
	@echo "  make verilog     - Generate Verilog from DSLX"
	@echo "  make synth       - Synthesize for iCE40 UP5K"
	@echo "  make clean       - Remove generated files"
	@echo ""
	@echo "Platform: $(UNAME_S) $(UNAME_M)"
ifeq ($(UNAME_S),Darwin)
	@echo "XLS method: Docker (run 'make setup' to build image)"
else
	@echo "XLS method: Native Linux binaries"
endif

#------------------------------------------------------------------------------
# Setup targets
#------------------------------------------------------------------------------

setup: $(XLS_SETUP)
	@echo "XLS tools ready!"

docker_xls:
	@echo "Building XLS Docker image..."
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "Error: Docker not found. Install Docker or OrbStack first."; \
		echo "  brew install orbstack"; \
		exit 1; \
	fi
	cd tools && docker build -t xls -f Dockerfile.xls .
	@echo "Docker image 'xls' built successfully."

install_xls:
	@echo "Downloading XLS tools for Linux x64..."
	@mkdir -p tools/xls-bin
	@LATEST_URL=$$(curl -s -L \
		-H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		https://api.github.com/repos/google/xls/releases | \
		grep -m 1 -o 'https://.*/releases/download/.*\.tar\.gz') && \
	echo "Downloading: $$LATEST_URL" && \
	curl -L "$$LATEST_URL" | tar -xzf - -C tools/xls-bin --strip-components=1
	@echo "XLS tools installed to tools/xls-bin/"

#------------------------------------------------------------------------------
# Test targets
#------------------------------------------------------------------------------

test: test-core test-cache

test-core:
	@echo "Running i8085_core.x tests..."
	$(INTERPRETER) $(DSLX_CORE)

test-cache:
	@echo "Running cache_logic.x tests..."
	$(INTERPRETER) $(DSLX_CACHE)

#------------------------------------------------------------------------------
# Verilog generation
#------------------------------------------------------------------------------

verilog: $(CORE_V) $(CACHE_V)

# CPU core: DSLX -> IR -> optimized IR -> Verilog
$(CORE_IR): $(DSLX_CORE)
	@echo "Converting $(DSLX_CORE) to IR..."
	$(IR_CONVERTER) $< --top=execute > $@

$(CORE_OPT_IR): $(CORE_IR)
	@echo "Optimizing $(CORE_IR)..."
	$(OPT) $< > $@

$(CORE_V): $(CORE_OPT_IR)
	@echo "Generating $(CORE_V)..."
	$(CODEGEN) $< \
		--generator=combinational \
		--output_verilog_path=$@ \
		--output_signature_path=$(CORE_SIG)

# Cache logic: DSLX -> IR -> optimized IR -> Verilog
$(CACHE_IR): $(DSLX_CACHE)
	@echo "Converting $(DSLX_CACHE) to IR..."
	$(IR_CONVERTER) $< --top=cache_lookup > $@

$(CACHE_OPT_IR): $(CACHE_IR)
	@echo "Optimizing $(CACHE_IR)..."
	$(OPT) $< > $@

$(CACHE_V): $(CACHE_OPT_IR)
	@echo "Generating $(CACHE_V)..."
	$(CODEGEN) $< \
		--generator=combinational \
		--output_verilog_path=$@

#------------------------------------------------------------------------------
# Synthesis
#------------------------------------------------------------------------------

synth: $(SOC_ASC)
	@echo "Synthesis complete: $(SOC_ASC)"

# Synthesis check (yosys only, no place-and-route)
# Use this to verify the design synthesizes without needing the PCF to be complete
synth-check: $(SOC_JSON)
	@echo ""
	@echo "Synthesis check passed! Design synthesizes for iCE40 UP5K."
	@echo "Note: Full place-and-route (make synth) requires updating the PCF"
	@echo "for your specific board, or removing debug outputs from i8085_soc.v"

$(SOC_JSON): $(VERILOG_SRCS)
	@echo "Running Yosys synthesis..."
	@if ! command -v $(YOSYS) >/dev/null 2>&1; then \
		echo "Error: yosys not found. Install with:"; \
		echo "  macOS: brew install yosys"; \
		echo "  Linux: apt install yosys"; \
		exit 1; \
	fi
	$(YOSYS) -p "read_verilog -sv $(CORE_V) $(CACHE_V); \
		read_verilog i8085_wrapper.v spi_engine.v spi_flash_cache.v i8085_soc.v; \
		synth_ice40 -top i8085_soc -json $@"

$(SOC_ASC): $(SOC_JSON) ice40up5k.pcf
	@echo "Running nextpnr place and route..."
	@if ! command -v $(NEXTPNR) >/dev/null 2>&1; then \
		echo "Error: nextpnr-ice40 not found. Install with:"; \
		echo "  macOS: brew install nextpnr"; \
		echo "  Linux: apt install nextpnr"; \
		exit 1; \
	fi
	$(NEXTPNR) --up5k --package sg48 --json $< --pcf ice40up5k.pcf --asc $@ \
		--pcf-allow-unconstrained --ignore-loops || \
		(echo "Note: Place/route failed. The design may be too large for the target."; \
		 echo "Try removing debug outputs (dbg_*) from i8085_soc.v to free up IOs."; \
		 exit 1)

$(SOC_BIN): $(SOC_ASC)
	@echo "Generating bitstream..."
	icepack $< $@

#------------------------------------------------------------------------------
# Clean
#------------------------------------------------------------------------------

clean:
	rm -f $(CORE_IR) $(CORE_OPT_IR) $(CORE_SIG)
	rm -f $(CACHE_IR) $(CACHE_OPT_IR)
	rm -f $(SOC_JSON) $(SOC_ASC) $(SOC_BIN)
	@echo "Cleaned generated files (kept .v files)"

cleanall: clean
	rm -f $(CORE_V) $(CACHE_V)
	rm -rf tools/xls-bin
	@echo "Cleaned all generated files"
