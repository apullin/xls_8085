# Intel 8085 CPU Core - Build System
#
# Configurations:
#   i8085_test      - Validation target (unconstrained, max Fmax)
#   i8085_40dip     - True 40-DIP drop-in replacement (HX8K)
#   i8085_40dip_plus - Enhanced drop-in with internal resources (UP5K)
#
# Targets:
#   make setup       - Install XLS tools (auto-detects platform)
#   make test        - Run DSLX tests
#   make verilog     - Generate Verilog from DSLX
#
#   make test-synth  - Synthesize i8085_test (unconstrained)
#   make 40dip-synth - Synthesize i8085_40dip for HX8K
#   make 40dip-plus-synth - Synthesize i8085_40dip_plus for UP5K
#
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

# Generated Verilog from DSLX
CORE_IR := i8085_core.ir
CORE_OPT_IR := i8085_core.opt.ir
CORE_V := i8085_core.v
CORE_SIG := i8085_core.sig.textproto

CACHE_IR := cache_logic.ir
CACHE_OPT_IR := cache_logic.opt.ir
CACHE_V := cache_logic.v

# Common Verilog sources
COMMON_V := $(CORE_V) i8085_wrapper.v

# Configuration-specific sources
TEST_V := $(COMMON_V) $(CACHE_V) spi_engine.v spi_flash_cache.v i8085_test.v
DIP40_V := $(COMMON_V) i8085_40dip.v
DIP40_PLUS_V := $(COMMON_V) $(CACHE_V) spi_engine.v spi_flash_cache.v i8085_40dip_plus.v

.PHONY: all setup test verilog clean cleanall help
.PHONY: test-synth 40dip-synth 40dip-plus-synth
.PHONY: docker_xls install_xls

# Default target
all: verilog test-synth

help:
	@echo "Intel 8085 CPU Core - Build System"
	@echo ""
	@echo "Setup (run first):"
	@echo "  make setup       - Install XLS tools (auto-detects platform)"
	@echo ""
	@echo "Build targets:"
	@echo "  make test        - Run DSLX tests"
	@echo "  make verilog     - Generate Verilog from DSLX"
	@echo ""
	@echo "Synthesis targets:"
	@echo "  make test-synth       - i8085_test (UP5K, unconstrained, max Fmax)"
	@echo "  make 40dip-synth      - i8085_40dip (HX8K, true drop-in)"
	@echo "  make 40dip-plus-synth - i8085_40dip_plus (UP5K, enhanced drop-in)"
	@echo ""
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
# Synthesis: i8085_test (validation target, unconstrained)
#------------------------------------------------------------------------------

test-synth: i8085_test.json
	@echo ""
	@echo "=== i8085_test synthesis complete ==="
	@echo "Unconstrained synthesis for maximum Fmax measurement."
	@echo "Run 'make test-pnr' for place-and-route timing analysis."

i8085_test.json: $(TEST_V)
	@echo "Synthesizing i8085_test (unconstrained)..."
	@if ! command -v $(YOSYS) >/dev/null 2>&1; then \
		echo "Error: yosys not found. Install with:"; \
		echo "  macOS: brew install yosys"; \
		echo "  Linux: apt install yosys"; \
		exit 1; \
	fi
	$(YOSYS) -p "read_verilog -sv $(CORE_V) $(CACHE_V); \
		read_verilog i8085_wrapper.v spi_engine.v spi_flash_cache.v i8085_test.v; \
		synth_ice40 -top i8085_test -json $@"

test-pnr: i8085_test.json
	@echo "Running place-and-route for i8085_test (no PCF, unconstrained)..."
	@if ! command -v $(NEXTPNR) >/dev/null 2>&1; then \
		echo "Error: nextpnr-ice40 not found. Install with:"; \
		echo "  macOS: brew install nextpnr"; \
		echo "  Linux: apt install nextpnr"; \
		exit 1; \
	fi
	$(NEXTPNR) --up5k --package sg48 --json $< --asc i8085_test.asc --ignore-loops
	@echo ""
	@echo "=== i8085_test place-and-route complete ==="

#------------------------------------------------------------------------------
# Synthesis: i8085_40dip (true drop-in replacement)
#------------------------------------------------------------------------------

40dip-synth: i8085_40dip.json
	@echo ""
	@echo "=== i8085_40dip synthesis complete ==="
	@echo "True 40-DIP drop-in replacement for HX8K."

i8085_40dip.json: $(DIP40_V)
	@echo "Synthesizing i8085_40dip..."
	@if ! command -v $(YOSYS) >/dev/null 2>&1; then \
		echo "Error: yosys not found."; \
		exit 1; \
	fi
	$(YOSYS) -p "read_verilog -sv $(CORE_V); \
		read_verilog i8085_wrapper.v i8085_40dip.v; \
		synth_ice40 -top i8085_40dip -json $@"

40dip-pnr: i8085_40dip.json ice40hx8k_40dip.pcf
	@echo "Running place-and-route for i8085_40dip (HX8K)..."
	@if ! command -v $(NEXTPNR) >/dev/null 2>&1; then \
		echo "Error: nextpnr-ice40 not found."; \
		exit 1; \
	fi
	$(NEXTPNR) --hx8k --package ct256 --json $< --pcf ice40hx8k_40dip.pcf --asc i8085_40dip.asc --ignore-loops
	@echo ""
	@echo "=== i8085_40dip place-and-route complete ==="

#------------------------------------------------------------------------------
# Synthesis: i8085_40dip_plus (enhanced drop-in)
#------------------------------------------------------------------------------

40dip-plus-synth: i8085_40dip_plus.json
	@echo ""
	@echo "=== i8085_40dip_plus synthesis complete ==="
	@echo "Enhanced drop-in with internal resources for UP5K."

i8085_40dip_plus.json: $(DIP40_PLUS_V)
	@echo "Synthesizing i8085_40dip_plus..."
	@if ! command -v $(YOSYS) >/dev/null 2>&1; then \
		echo "Error: yosys not found."; \
		exit 1; \
	fi
	$(YOSYS) -p "read_verilog -sv $(CORE_V) $(CACHE_V); \
		read_verilog i8085_wrapper.v spi_engine.v spi_flash_cache.v i8085_40dip_plus.v; \
		synth_ice40 -top i8085_40dip_plus -json $@"

40dip-plus-pnr: i8085_40dip_plus.json ice40up5k_40dip_plus.pcf
	@echo "Running place-and-route for i8085_40dip_plus (UP5K)..."
	@if ! command -v $(NEXTPNR) >/dev/null 2>&1; then \
		echo "Error: nextpnr-ice40 not found."; \
		exit 1; \
	fi
	$(NEXTPNR) --up5k --package sg48 --json $< --pcf ice40up5k_40dip_plus.pcf --asc i8085_40dip_plus.asc \
		--pcf-allow-unconstrained --ignore-loops
	@echo ""
	@echo "=== i8085_40dip_plus place-and-route complete ==="

#------------------------------------------------------------------------------
# Clean
#------------------------------------------------------------------------------

clean:
	rm -f $(CORE_IR) $(CORE_OPT_IR) $(CORE_SIG)
	rm -f $(CACHE_IR) $(CACHE_OPT_IR)
	rm -f i8085_test.json i8085_test.asc
	rm -f i8085_40dip.json i8085_40dip.asc
	rm -f i8085_40dip_plus.json i8085_40dip_plus.asc
	@echo "Cleaned generated files (kept .v files)"

cleanall: clean
	rm -f $(CORE_V) $(CACHE_V)
	rm -rf tools/xls-bin
	@echo "Cleaned all generated files"
