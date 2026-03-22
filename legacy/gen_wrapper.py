#!/usr/bin/env python3
"""
Generate a clean Verilog wrapper from XLS module signature.

Reads the .sig.textproto file and generates a wrapper with named ports
instead of flattened bit vectors.
"""

import re
import sys
from dataclasses import dataclass
from typing import List, Optional

@dataclass
class Port:
    name: str
    direction: str  # 'input' or 'output'
    width: int
    fields: List[tuple]  # [(name, width, bit_lo, bit_hi), ...]

def parse_signature(sig_path: str) -> tuple:
    """Parse the XLS signature textproto file."""
    with open(sig_path) as f:
        content = f.read()

    # Extract module name
    m = re.search(r'module_name:\s*"([^"]+)"', content)
    module_name = m.group(1) if m else "unknown"

    # This is a simplified parser - real implementation would use protobuf
    ports = []

    # For the 8085, we know the structure:
    # state input: 95 bits = (7x8 regs + 2x16 sp/pc + 5x1 flags + 2x1 halted/inte)
    # out output: 120 bits = (95 state + 25 membus)

    return module_name, ports

def generate_wrapper():
    """Generate the wrapper based on known 8085 structure."""

    wrapper = '''// Auto-generated wrapper for i8085_core
// Provides clean named interface hiding XLS bit-packing

module i8085_wrapper (
    input  wire        clk,
    input  wire        reset_n,

    // Memory Bus
    output wire [15:0] mem_addr,
    input  wire [7:0]  mem_data_in,
    output wire [7:0]  mem_data_out,
    output wire        mem_rd,
    output wire        mem_wr,

    // Instruction input (directly accent fetch externally)
    input  wire [7:0]  opcode,
    input  wire [7:0]  imm1,
    input  wire [7:0]  imm2,

    // Memory read data (for instructions that read from HL)
    input  wire [7:0]  mem_read_data,

    // Stack read data (for RET/POP)
    input  wire [7:0]  stack_lo,
    input  wire [7:0]  stack_hi,

    // Control
    input  wire        execute,     // Pulse to execute instruction

    // Status outputs
    output wire [15:0] pc,
    output wire [15:0] sp,
    output wire [7:0]  reg_a,
    output wire        halted,
    output wire        flag_z,
    output wire        flag_c
);

    // =========================================================================
    // CPU State Registers
    // =========================================================================

    reg [7:0]  r_b, r_c, r_d, r_e, r_h, r_l, r_a;
    reg [15:0] r_sp, r_pc;
    reg        f_sign, f_zero, f_aux, f_parity, f_carry;
    reg        r_halted, r_inte;

    // =========================================================================
    // XLS Core - bit packing/unpacking
    // =========================================================================

    // Pack state for core input (LSB-first per XLS convention)
    wire [94:0] core_state = {
        r_inte,
        r_halted,
        f_carry, f_parity, f_aux, f_zero, f_sign,
        r_pc,
        r_sp,
        r_a, r_l, r_h, r_e, r_d, r_c, r_b
    };

    wire [119:0] core_out;

    __i8085_core__execute core (
        .state(core_state),
        .opcode(opcode),
        .byte2(imm1),
        .byte3(imm2),
        .mem_read_data(mem_read_data),
        .stack_read_lo(stack_lo),
        .stack_read_hi(stack_hi),
        .out(core_out)
    );

    // Unpack core output
    wire [7:0]  next_b      = core_out[7:0];
    wire [7:0]  next_c      = core_out[15:8];
    wire [7:0]  next_d      = core_out[23:16];
    wire [7:0]  next_e      = core_out[31:24];
    wire [7:0]  next_h      = core_out[39:32];
    wire [7:0]  next_l      = core_out[47:40];
    wire [7:0]  next_a      = core_out[55:48];
    wire [15:0] next_sp     = core_out[71:56];
    wire [15:0] next_pc     = core_out[87:72];
    wire        next_f_sign = core_out[88];
    wire        next_f_zero = core_out[89];
    wire        next_f_aux  = core_out[90];
    wire        next_f_par  = core_out[91];
    wire        next_f_cry  = core_out[92];
    wire        next_halted = core_out[93];
    wire        next_inte   = core_out[94];

    // Memory bus output
    wire [15:0] core_mem_addr = core_out[110:95];
    wire [7:0]  core_mem_data = core_out[118:111];
    wire        core_mem_wr   = core_out[119];

    // =========================================================================
    // State Update
    // =========================================================================

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            r_b <= 8'h00; r_c <= 8'h00;
            r_d <= 8'h00; r_e <= 8'h00;
            r_h <= 8'h00; r_l <= 8'h00;
            r_a <= 8'h00;
            r_sp <= 16'hFFFF;
            r_pc <= 16'h0000;
            f_sign <= 1'b0; f_zero <= 1'b0;
            f_aux <= 1'b0; f_parity <= 1'b0; f_carry <= 1'b0;
            r_halted <= 1'b0;
            r_inte <= 1'b0;
        end else if (execute && !r_halted) begin
            r_b <= next_b; r_c <= next_c;
            r_d <= next_d; r_e <= next_e;
            r_h <= next_h; r_l <= next_l;
            r_a <= next_a;
            r_sp <= next_sp;
            r_pc <= next_pc;
            f_sign <= next_f_sign;
            f_zero <= next_f_zero;
            f_aux <= next_f_aux;
            f_parity <= next_f_par;
            f_carry <= next_f_cry;
            r_halted <= next_halted;
            r_inte <= next_inte;
        end
    end

    // =========================================================================
    // Output assignments
    // =========================================================================

    assign mem_addr = core_mem_wr ? core_mem_addr : r_pc;
    assign mem_data_out = core_mem_data;
    assign mem_wr = core_mem_wr & execute;
    assign mem_rd = ~core_mem_wr & ~r_halted;

    assign pc = r_pc;
    assign sp = r_sp;
    assign reg_a = r_a;
    assign halted = r_halted;
    assign flag_z = f_zero;
    assign flag_c = f_carry;

endmodule
'''
    return wrapper

if __name__ == '__main__':
    wrapper = generate_wrapper()

    if len(sys.argv) > 1:
        with open(sys.argv[1], 'w') as f:
            f.write(wrapper)
        print(f"Wrote wrapper to {sys.argv[1]}")
    else:
        print(wrapper)
