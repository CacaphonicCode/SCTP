// Testbench options
`define	TRACE	1	// enable simulation trace
`define RUNTIME 100	// How long simulator can run
`define CLKDEL  2	// CLocK transition delay

// Types
`define WORD	[31:0]	// size of a data word
`define ADDR	[31:0]	// size of a memory address
`define INST	[31:0]	// size of an instruction
`define REG	[4:0]	// size of a register number
`define	REGCNT	[31:0]	// register count
`define	MEMCNT	[511:0] // memory count implemented
`define	OPCODE	[5:0]	// 6-bit opcodes
`define	EXTOP	[6:0]	// {!RTYPE, OPCODE}

// Fields
`define OP	[31:26]	// opcode field
`define RS	[25:21]	// rs field
`define RT	[20:16]	// rt field
`define RD	[15:11]	// rd field
`define IMM	[15:0]	// immediate/offset field
`define SHAMT	[10:6]	// shift ammount
`define FUNCT	[5:0]	// function code (opcode extension)
`define JADDR	[25:0]	// jump address field
`define	JPACK(R,O,J)		begin R`OP=O; R`JADDR=((J)>>2); end
`define	IPACK(R,O,S,T,I)	begin R`OP=O; R`RS=S; R`RT=T; R`IMM=I; end
`define	RPACK(R,S,T,D,SH,FU)	begin R`OP=`RTYPE; R`RS=S; R`RT=T; R`RD=D; R`SHAMT=SH; R`FUNCT=FU; end

// Instruction encoding
`define	RTYPE	6'h00	// OP field for all RTYPE instructions
`define BEQ	6'h04	// OP field
`define BNE	6'h06	// OP field, PAUL G, BNE
`define	ADDIU	6'h09	// OP field
`define	SLTIU	6'h0b	// OP field
`define	ANDI	6'h0c	// OP field
`define	ORI	6'h0d	// OP field
`define	XORI	6'h0e	// OP field
`define	LUI	6'h0f	// OP field
`define	LW	6'h23	// OP field
`define	SW	6'h2b	// OP field 

`define	MUL	6'h01	// FUNCT field, PAUL G, MUL
`define	ADDU	6'h21	// FUNCT field
`define	SUBU	6'h23	// FUNCT field
`define	AND	6'h24	// FUNCT field
`define	OR	6'h25	// FUNCT field
`define	XOR	6'h26	// FUNCT field
`define	SLTU	6'h2b	// FUNCT field
`define	F(A)	{1'b1, A} // in FUNCT field
`define	TRAP	7'h7f	// illegal operation

// Decode OP, FUNCT into one 7-bit EXTOP
module decode(xop, ir);
output reg `EXTOP xop;	// decoded 7-bit op
input `INST ir;		// instruction

always @(ir) begin
  case (ir `OP)
    `RTYPE:	case (ir `FUNCT)
		  `MUL, // PAUL G, MUL
      `ADDU, `SUBU,
		  `AND, `OR, `XOR,
		  `SLTU:	xop = `F(ir `FUNCT);
		  default:	xop = `TRAP;
		endcase
    `BEQ,
    `BNE, // PAUL G, BNE
    `ADDIU, `SLTIU,
    `ANDI, `ORI, `XORI,
    `LUI, `LW, `SW:	xop = ir `OP;
    default:		xop = `TRAP;
  endcase
end
endmodule

// General-purpose ALU
module alu(zero, res, xop, top, bot);
output zero;		// res is 0?
output reg `WORD res;	// combinatorial result
input `EXTOP xop;	// extended operation
input `WORD top, bot;	// top & bottom inputs

assign zero = (res == 0);

// combinatorial always using sensitivity list
// output declared as reg, but never use <=
always @(xop or top or bot) begin
  case (xop)
    `F(`MUL): res = (top * bot); // PAUL G, MUL
    `LW, `SW,
    `ADDIU, `F(`ADDU):	res = (top + bot);
    `SLTIU, `F(`SLTU):	res = (top < bot);
    `ANDI, `F(`AND):	res = (top & bot);
    `ORI, `F(`OR):	res = (top | bot);
    `XORI, `F(`XOR):	res = (top ^ bot);
    `LUI:		res = (bot << 16);
    `BEQ, `F(`SUBU):	res = (top - bot);
    `BNE, `F(`SUBU): res = !(top - bot); // PAUL G, BNE
    // should always cover all possible values
    default:	res = top;
  endcase
end
endmodule

// Generic multi-cycle processor
module processor(halt, reset, clk);
output reg halt;
input reset, clk;
reg `ADDR pc;
reg `WORD m `MEMCNT;
reg `WORD r `REGCNT;
wire `INST ir;

// Initialize register file and memory
initial begin // PAUL G, Note : I believe this is just part of the test-bench and is not part of the actual implementations themselves
    r[1] = 22; r[2] = 1; r[3] = 42;
    r[4] = 601;	r[5] = 11811;
    `RPACK(m[0], 2, 3, 1, 0, `ADDU)
    `RPACK(m[1], 2, 3, 1, 0, `SLTU)
    `RPACK(m[2], 3, 5, 1, 0, `AND)
    `RPACK(m[3], 5, 3, 1, 0, `OR)
    `RPACK(m[4], 3, 5, 1, 0, `XOR)
    `RPACK(m[5], 4, 3, 1, 0, `SUBU)
    `IPACK(m[6], `ADDIU, 3, 1, -1)
    `IPACK(m[7], `SLTIU, 5, 1, 12345)
    `IPACK(m[8], `ANDI, 3, 1, 3)
    `IPACK(m[9], `ORI, 3, 1, 3)
    `IPACK(m[10], `XORI, 3, 1, 3)
    `IPACK(m[11], `LUI, 0, 1, 1)
    `IPACK(m[12], `LW, 2, 1, 1023)
    `IPACK(m[13], `SW, 0, 2, 1024)
    `IPACK(m[14], `BEQ, 4, 5, -1)
    m[15] = 0;
    m[256] = 22;
end

assign ir = m[pc >> 2];

// Control output signals
wire RegDst, Branch, MemRead, MemtoReg;
wire `OPCODE ALUop;
wire ALUSrc, MemWrite, RegWrite;

// Mux outputs
wire `REG RegDstMux;
wire `WORD ALUSrcMux, BranchZeroMux, MemtoRegMux;

// Function unit wiring
wire `WORD Shiftleft2, Signextend;
wire `ADDR PCAdd, BranchAdd;
wire `EXTOP ALUcontrol;
wire Zero;
wire `WORD ALUresult;

// Control logic
assign RegDst = (ir `OP == `RTYPE);
assign ALUSrc = ((ir `OP != `RTYPE) && (ir `OP != `BEQ));
assign ALUOp = (ir `OP);
assign MemRead = (ir `OP == `LW);
assign MemtoReg = (ir `OP == `LW);
assign MemWrite = (ir `OP == `SW);
assign RegWrite = ((ir `OP != `SW) && (ir `OP != `BEQ));
assign RegDstMux = (RegDst ? ir `RD : ir `RT);
assign ALUSrcMux = (ALUSrc ? Signextend : r[ir `RT]);
assign MemtoRegMux = (MemtoReg ? m[ALUresult >> 2] : ALUresult);
assign Branch = ((ir `OP == `BEQ) || (ir `OP == `BNE)); // PAUL G, BNE
assign BranchZeroMux = ((Branch & Zero) ? BranchAdd : PCAdd);

// Function units
assign Signextend = {{16{ir[15]}}, ir `IMM};
assign Shiftleft2 = {Signextend[29:0], 2'b00};
assign PCAdd = (pc + 4);
assign BranchAdd = (PCAdd + Shiftleft2);
decode DECODE(ALUcontrol, ir);
alu    ALU(Zero, ALUresult, ALUcontrol, r[ir `RS], ALUSrcMux);

always @(posedge clk) begin
  if (reset) begin
    // reset
    pc <= 0;
    halt <= 0;
    r[0] <= 0;
  end else begin
    // normal operation
    if (!halt) begin
      if (ALUcontrol != `TRAP) begin
`ifdef	TRACE
        if (ir `OP == 2) $display("%d: OP=%x JADDR=%d", pc, ir `OP, ir `JADDR);
        else if (ir `OP) $display("%d: OP=%x RS=%d RT=%d IMM=%x", pc, ir `OP, ir `RS, ir `RT, ir `IMM);
        else $display("%d: OP=%x RS=%d RT=%d RD=%d SHAMT=%d FUNCT=%x", pc, ir `OP, ir `RS, ir `RT, ir `RD, ir `SHAMT, ir `FUNCT);
        if (MemWrite) $display("%d: m[%d] <= r[%d] (%d)", pc, ALUresult, ir `RT, r[ir `RT]);
        if (RegWrite) $display("%d: r[%d] <= %d", pc, RegDstMux, MemtoRegMux);
        $display("%d: pc <= %d", pc, BranchZeroMux);
`endif
        if (MemWrite) m[ALUresult >> 2] <= r[ir `RT];
        if (RegWrite) r[RegDstMux] <= MemtoRegMux;
        pc <= BranchZeroMux;
      end else halt <= 1;
    end
  end
end
endmodule

// Testbench
module bench;
wire halt;
reg reset = 1;
reg clk = 0;

processor PE(halt, reset, clk);

initial begin
  #`CLKDEL clk = 1;
  #`CLKDEL clk = 0;
  reset = 0;
  while (($time < `RUNTIME) && !halt) begin
    #`CLKDEL clk = 1;
    #`CLKDEL clk = 0;
  end
end
endmodule


