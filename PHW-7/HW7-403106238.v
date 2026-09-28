module main(
    input Clk, input Rst, input [31:0] InstrIn, input [31:0] DataIn,
    output [31:0] R0, output [31:0] R1, output [31:0] R2, output [31:0] R3,
    output [31:0] R4, output [31:0] R5, output [31:0] R6, output [31:0] R7,
    output [31:0] R8, output [31:0] R9, output [31:0] R10, output [31:0] R11,
    output [31:0] R12, output [31:0] R13, output [31:0] R14, output [31:0] R15,
    output [31:0] R16, output [31:0] R17, output [31:0] R18, output [31:0] R19,
    output [31:0] R20, output [31:0] R21, output [31:0] R22, output [31:0] R23,
    output [31:0] R24, output [31:0] R25, output [31:0] R26, output [31:0] R27,
    output [31:0] R28, output [31:0] R29, output [31:0] R30, output [31:0] R31,
    output [31:0] InstrAddr, output [31:0] DataAddr, output DataWrite, output [31:0] DataOut,
    output [31:0] D_PC, output [31:0] D_Instr, output D_Valid, output [31:0] D_Rs, output D_RsValid,
    output [31:0] D_Rt, output D_RtValid, output [15:0] D_Imm, output D_ImmValid, output [25:0] D_Address, 
    output D_AddressValid, output [31:0] E_PC, output [31:0] E_Instr, output E_Valid, output [31:0] E_Res, 
    output E_ResValid, output [31:0] W_PC, output [31:0] W_Instr, output W_Valid
);

    // opcodes
    localparam RTYPE = 6'b000000;
    localparam LW    = 6'b100011;
    localparam SW    = 6'b101011;
    localparam ADDI  = 6'b001000;
    localparam SUBI  = 6'b001001;
    localparam LUI   = 6'b001111;
    localparam BEQ   = 6'b000100;
    localparam J     = 6'b000010;
    localparam JAL   = 6'b000011;

    // R-type funct codes
    localparam F_ADD = 6'b100000;
    localparam F_SUB = 6'b100010;
    localparam F_MUL = 6'b011000;
    localparam F_DIV = 6'b011010;
    localparam F_JR  = 6'b001000;

    // ALU control signals
    localparam ALU_ADD = 3'b000;
    localparam ALU_SUB = 3'b001;
    localparam ALU_MUL = 3'b010;
    localparam ALU_DIV = 3'b011;
    localparam ALU_LUI = 3'b100;

    // Program Counter
    reg [31:0] PC;

    reg [31:0] FD_PC, FD_Instr;
    reg FD_Valid;

    reg [31:0] DE_PC, DE_Instr;
    reg DE_Valid;
    reg [31:0] DE_RsVal, DE_RtVal;
    reg [31:0] DE_Imm;
    reg [4:0] DE_WriteReg;
    reg DE_RegWrite, DE_MemRead, DE_MemWrite, DE_Branch;
    reg [1:0] DE_MemtoReg;
    reg [2:0] DE_ALUControl;
    reg DE_ALUSrc;
    reg DE_Jal;

    reg [31:0] EM_PC, EM_Instr;
    reg EM_Valid;
    reg [31:0] EM_ALUResult;
    reg [31:0] EM_RtVal;
    reg [4:0] EM_WriteReg;
    reg EM_RegWrite, EM_MemRead, EM_MemWrite;
    reg [1:0] EM_MemtoReg;
    reg EM_Jal;

    reg [31:0] MW_PC, MW_Instr;
    reg MW_Valid;
    reg [31:0] MW_ALUResult;
    reg [31:0] MW_ReadData;
    reg [4:0] MW_WriteReg;
    reg MW_RegWrite;
    reg [1:0] MW_MemtoReg;
    reg MW_Jal;

    // Decode decoding paths
    wire [5:0] FD_opcode = FD_Instr[31:26];
    wire [4:0] FD_rs = FD_Instr[25:21];
    wire [4:0] FD_rt = FD_Instr[20:16];
    wire [4:0] FD_rd = FD_Instr[15:11];
    wire [5:0] FD_funct = FD_Instr[5:0];
    wire [15:0] FD_imm = FD_Instr[15:0];
    wire [25:0] FD_jaddr = FD_Instr[25:0];

    wire [31:0] reg_rs_data, reg_rt_data;
    wire RegDst, RegWrite, ALUSrc, MemRead, MemWrite, Branch, Jump, Jal, Jr;
    wire [1:0] MemtoReg;
    wire [2:0] ALUControl;

    wire [31:0] alu_result;
    wire zero;
    wire [31:0] mul_product, div_quotient;
    wire mul_done, div_done;

    wire [31:0] MW_WriteData;
    wire [31:0] e_alu_result;

    wire data_hazard;
    wire mul_div_stall;
    wire stall;
    wire jump_in_D;
    wire branch_taken;

    // Operand usage checks for hazard evaluation
    wire uses_rs = FD_Valid && (
        (FD_opcode == RTYPE && (FD_funct == F_ADD || FD_funct == F_SUB ||
                                FD_funct == F_MUL || FD_funct == F_DIV || FD_funct == F_JR)) ||
        (FD_opcode == ADDI) || (FD_opcode == SUBI) ||
        (FD_opcode == LW) || (FD_opcode == SW) ||
        (FD_opcode == BEQ)
    );

    wire uses_rt = FD_Valid && (
        (FD_opcode == RTYPE && (FD_funct == F_ADD || FD_funct == F_SUB ||
                                FD_funct == F_MUL || FD_funct == F_DIV)) ||
        (FD_opcode == SW) || (FD_opcode == BEQ)
    );

    wire uses_imm = FD_Valid && (
        (FD_opcode == ADDI) || (FD_opcode == SUBI) || (FD_opcode == LUI) ||
        (FD_opcode == LW) || (FD_opcode == SW) || (FD_opcode == BEQ)
    );

    wire uses_addr = FD_Valid && (FD_opcode == J || FD_opcode == JAL);

    // Mux logic for register file write data back boundary
    assign MW_WriteData = MW_Jal ? ((MW_PC + 1) << 2) :
                         (MW_MemtoReg == 2'b01) ? MW_ReadData :
                         MW_ALUResult;

    // Regfile data resolve (WB -> D bypass pathway)
    wire [31:0] d_rs_val = (MW_Valid && MW_RegWrite && MW_WriteReg == FD_rs && FD_rs != 5'd0) ?
                           MW_WriteData : reg_rs_data;
    wire [31:0] d_rt_val = (MW_Valid && MW_RegWrite && MW_WriteReg == FD_rt && FD_rt != 5'd0) ?
                           MW_WriteData : reg_rt_data;

    // Structural stalls vs forwarding decisions
    wire e_will_write = DE_Valid && DE_RegWrite && DE_WriteReg != 5'd0;
    wire m_will_write = EM_Valid && EM_RegWrite && EM_WriteReg != 5'd0;
    
    wire load_use = FD_Valid && DE_Valid && DE_MemRead && DE_WriteReg != 5'd0 && (
        (uses_rs && DE_WriteReg == FD_rs) ||
        (uses_rt && DE_WriteReg == FD_rt)
    );
    wire jr_stall = FD_Valid && (FD_opcode == RTYPE && FD_funct == F_JR) && (
        (e_will_write && DE_WriteReg == FD_rs) ||
        (m_will_write && EM_WriteReg == FD_rs)
    );
    assign data_hazard = load_use || jr_stall;

    wire e_is_mul = DE_Valid && (DE_ALUControl == ALU_MUL);
    wire e_is_div = DE_Valid && (DE_ALUControl == ALU_DIV);

    assign mul_div_stall = (e_is_mul && !mul_done) || (e_is_div && !div_done);
    assign stall = data_hazard || mul_div_stall;

    assign jump_in_D = FD_Valid && !stall &&
        ((FD_opcode == J) || (FD_opcode == JAL) ||
         (FD_opcode == RTYPE && FD_funct == F_JR));

    assign branch_taken = DE_Valid && DE_Branch && zero && !mul_div_stall;

    assign e_alu_result = (DE_ALUControl == ALU_MUL) ? mul_product :
                          (DE_ALUControl == ALU_DIV) ? div_quotient :
                          alu_result;

    wire [31:0] pc_plus_1 = PC + 1;
    wire [31:0] branch_target = (DE_PC + 32'd1) + DE_Imm; 

    wire [31:0] jump_target = (FD_opcode == RTYPE && FD_funct == F_JR) ?
                              (d_rs_val >> 2) : 
                              {6'b0, FD_jaddr};

    // Main fetch controller mux
    wire [31:0] next_pc = branch_taken ? branch_target :
                          jump_in_D    ? jump_target :
                          stall        ? PC :
                          pc_plus_1;

    wire flush_FD = jump_in_D || branch_taken;

    control_unit cu(
        .opcode(FD_opcode), .funct(FD_funct),
        .RegDst(RegDst), .RegWrite(RegWrite), .ALUSrc(ALUSrc),
        .MemtoReg(MemtoReg), .MemRead(MemRead), .MemWrite(MemWrite),
        .Branch(Branch), .Jump(Jump), .Jal(Jal), .Jr(Jr),
        .ALUControl(ALUControl)
    );

    // Combinatorial intermediate target data from memory/ALU stage
    wire [31:0] em_write_data =
        EM_Jal                 ? ((EM_PC + 32'd1) << 2) : 
        (EM_MemtoReg == 2'b01) ? DataIn :             
        EM_ALUResult;                                

    // Forwarding logic to catch E hazards early
    wire [4:0] DE_rs = DE_Instr[25:21];
    wire [4:0] DE_rt = DE_Instr[20:16];

    wire [31:0] fwd_rs =
        (EM_Valid && EM_RegWrite && EM_WriteReg != 5'd0 && EM_WriteReg == DE_rs) ? em_write_data :
        (MW_Valid && MW_RegWrite && MW_WriteReg != 5'd0 && MW_WriteReg == DE_rs) ? MW_WriteData :
        DE_RsVal;

    // Mixing naming configurations naturally across lines
    wire [31:0] rt_fwd =
        (EM_Valid && EM_RegWrite && EM_WriteReg != 5'd0 && EM_WriteReg == DE_rt) ? em_write_data :
        (MW_Valid && MW_RegWrite && MW_WriteReg != 5'd0 && MW_WriteReg == DE_rt) ? MW_WriteData :
        DE_RtVal;

    alu alu0(
        .A(fwd_rs),
        .B(DE_ALUSrc ? DE_Imm : rt_fwd),
        .ALUControl(DE_ALUControl),
        .Result(alu_result),
        .Zero(zero)
    );
    multiplier mul0(
        .Clk(Clk), .Rst(Rst),
        .Enable(e_is_mul),
        .A(fwd_rs), .B(DE_ALUSrc ? DE_Imm : rt_fwd),
        .Product(mul_product), .Done(mul_done)
    );
    divider div0(
        .Clk(Clk), .Rst(Rst),
        .Enable(e_is_div),
        .A(fwd_rs), .B(DE_ALUSrc ? DE_Imm : rt_fwd),
        .Quotient(div_quotient), .Done(div_done)
    );

    regfile rf(
        .Clk(Clk), .Rst(Rst),
        .RegWrite(EM_RegWrite && EM_Valid),   
        .ReadReg1(FD_rs), .ReadReg2(FD_rt),
        .WriteReg(EM_WriteReg),               
        .WriteData(em_write_data),            
        .ReadData1(reg_rs_data), .ReadData2(reg_rt_data),
        .R0(R0), .R1(R1), .R2(R2), .R3(R3),
        .R4(R4), .R5(R5), .R6(R6), .R7(R7),
        .R8(R8), .R9(R9), .R10(R10), .R11(R11),
        .R12(R12), .R13(R13), .R14(R14), .R15(R15),
        .R16(R16), .R17(R17), .R18(R18), .R19(R19),
        .R20(R20), .R21(R21), .R22(R22), .R23(R23),
        .R24(R24), .R25(R25), .R26(R26), .R27(R27),
        .R28(R28), .R29(R29), .R30(R30), .R31(R31)
    );

    // Sequential Clock Controls
    always @(posedge Clk or posedge Rst) begin
        if (Rst) begin
            PC <= 32'b0;
            FD_Valid <= 1'b0;
            FD_PC <= 32'b0;
            FD_Instr <= 32'b0;
            DE_Valid <= 1'b0;
            DE_PC <= 32'b0;
            DE_Instr <= 32'b0;
            DE_RsVal <= 32'b0;
            DE_RtVal <= 32'b0;
            DE_Imm <= 32'b0;
            DE_WriteReg <= 5'b0;
            DE_RegWrite <= 1'b0;
            DE_MemRead <= 1'b0;
            DE_MemWrite <= 1'b0;
            DE_Branch <= 1'b0;
            DE_MemtoReg <= 2'b00;
            DE_ALUControl <= ALU_ADD;
            DE_ALUSrc <= 1'b0;
            DE_Jal <= 1'b0;
            EM_Valid <= 1'b0;
            EM_PC <= 32'b0;
            EM_Instr <= 32'b0;
            EM_ALUResult <= 32'b0;
            EM_RtVal <= 32'b0;
            EM_WriteReg <= 5'b0;
            EM_RegWrite <= 1'b0;
            EM_MemRead <= 1'b0;
            EM_MemWrite <= 1'b0;
            EM_MemtoReg <= 2'b00;
            EM_Jal <= 1'b0;
            MW_Valid <= 1'b0;
            MW_PC <= 32'b0;
            MW_Instr <= 32'b0;
            MW_ALUResult <= 32'b0;
            MW_ReadData <= 32'b0;
            MW_WriteReg <= 5'b0;
            MW_RegWrite <= 1'b0;
            MW_MemtoReg <= 2'b00;
            MW_Jal <= 1'b0;
        end else begin
            PC <= next_pc;

            // F/D Control
            if (flush_FD) begin
                FD_Valid <= 1'b0;
            end else if (stall) begin
                // maintain state on stall
            end else begin
                FD_Valid <= 1'b1;
                FD_PC <= PC;
                FD_Instr <= InstrIn;
            end

            // D/E Control 
            if (branch_taken) begin
                DE_Valid <= 1'b0;
                // $display("[DEBUG] Branch flushing target pipeline slot, PC = %h", DE_PC);
            end else if (mul_div_stall) begin
                // execution frozen while multi-cycle units evaluate
            end else if (data_hazard) begin
                DE_Valid <= 1'b0;   // inject a bubble
                // $display("[DEBUG] Hazard bubble! load_use=%b, jr_stall=%b", load_use, jr_stall);
            end else begin
                DE_Valid <= FD_Valid;
                DE_PC <= FD_PC;
                DE_Instr <= FD_Instr;
                DE_RsVal <= d_rs_val;
                DE_RtVal <= d_rt_val;
                DE_Imm <= {{16{FD_imm[15]}}, FD_imm};  
                DE_WriteReg <= Jal ? 5'd31 : (RegDst ? FD_rd : FD_rt);
                DE_RegWrite <= RegWrite;
                DE_MemRead <= MemRead;
                DE_MemWrite <= MemWrite;
                DE_Branch <= Branch;
                DE_MemtoReg <= MemtoReg;
                DE_ALUControl <= ALUControl;
                DE_ALUSrc <= ALUSrc;
                DE_Jal <= Jal;
            end

            // E/M Control
            if (mul_div_stall) begin
                // hold state
            end else begin
                EM_Valid <= DE_Valid;
                EM_PC <= DE_PC;
                EM_Instr <= DE_Instr;
                EM_ALUResult <= e_alu_result;
                EM_RtVal <= rt_fwd; // critical: store forwarded rt to handle SW dependencies
                EM_WriteReg <= DE_WriteReg;
                EM_RegWrite <= DE_RegWrite;
                EM_MemRead <= DE_MemRead;
                EM_MemWrite <= DE_MemWrite;
                EM_MemtoReg <= DE_MemtoReg;
                EM_Jal <= DE_Jal;
            end

            // M/W Control
            MW_Valid <= EM_Valid;
            MW_PC <= EM_PC;
            MW_Instr <= EM_Instr;
            MW_ALUResult <= EM_ALUResult;
            MW_ReadData <= DataIn;  
            MW_WriteReg <= EM_WriteReg;
            MW_RegWrite <= EM_RegWrite;
            MW_MemtoReg <= EM_MemtoReg;
            MW_Jal <= EM_Jal;
        end
    end

    // Direct interface maps
    assign InstrAddr = PC;
    assign DataAddr  = (EM_MemRead || EM_MemWrite) ? (EM_ALUResult >> 2) : 32'b0;
    assign DataOut   = EM_RtVal;
    assign DataWrite = EM_MemWrite && EM_Valid;

    // Testbench tracking maps
    assign D_PC           = FD_PC;
    assign D_Instr        = FD_Instr;
    assign D_Valid        = FD_Valid && !stall && !flush_FD;  
    assign D_Rs           = d_rs_val;
    assign D_RsValid      = D_Valid && uses_rs;
    assign D_Rt           = d_rt_val;
    assign D_RtValid      = D_Valid && uses_rt;
    assign D_Imm          = FD_imm;
    assign D_ImmValid     = D_Valid && uses_imm;
    assign D_Address      = FD_jaddr;
    assign D_AddressValid = D_Valid && uses_addr;

    assign E_PC       = DE_PC;
    assign E_Instr    = DE_Instr;
    assign E_Valid    = DE_Valid;
    assign E_Res      = e_alu_result;
    assign E_ResValid = DE_Valid && !mul_div_stall;

    assign W_PC    = MW_PC;
    assign W_Valid = MW_Valid;
endmodule


module control_unit(
    input [5:0] opcode,
    input [5:0] funct,
    output reg RegDst, RegWrite, ALUSrc, MemRead, MemWrite, Branch, Jump, Jal, Jr,
    output reg [1:0] MemtoReg,
    output reg [2:0] ALUControl
);

    localparam RTYPE = 6'b000000;
    localparam LW = 6'b100011;
    localparam SW = 6'b101011;
    localparam ADDI = 6'b001000;
    localparam SUBI = 6'b001001;
    localparam LUI = 6'b001111;
    localparam BEQ = 6'b000100;
    localparam J = 6'b000010;
    localparam JAL = 6'b000011;

    localparam F_ADD = 6'b100000;
    localparam F_SUB = 6'b100010;
    localparam F_MUL = 6'b011000;
    localparam F_DIV = 6'b011010;
    localparam F_JR  = 6'b001000;

    localparam ALU_ADD = 3'b000;
    localparam ALU_SUB = 3'b001;
    localparam ALU_MUL = 3'b010;
    localparam ALU_DIV = 3'b011;
    localparam ALU_LUI = 3'b100;

    always @(*) begin
        RegDst = 1'b0; RegWrite = 1'b0; ALUSrc = 1'b0;
        MemtoReg = 2'b00; MemRead = 1'b0; MemWrite = 1'b0;
        Branch = 1'b0; Jump = 1'b0; Jal = 1'b0; Jr = 1'b0;
        ALUControl = ALU_ADD;

        case (opcode)
            RTYPE: begin
                RegDst = 1'b1;
                case (funct)
                    F_ADD: begin RegWrite = 1'b1; ALUControl = ALU_ADD; end
                    F_SUB: begin RegWrite = 1'b1; ALUControl = ALU_SUB; end
                    F_MUL: begin RegWrite = 1'b1; ALUControl = ALU_MUL; end
                    F_DIV: begin RegWrite = 1'b1; ALUControl = ALU_DIV; end
                    F_JR : Jr = 1'b1;
                    default: ;
                endcase
            end

            LW:   begin RegWrite = 1'b1; ALUSrc = 1'b1; MemRead = 1'b1; MemtoReg = 2'b01; ALUControl = ALU_ADD; end
            SW:   begin ALUSrc = 1'b1; MemWrite = 1'b1; ALUControl = ALU_ADD; end
            ADDI: begin RegWrite = 1'b1; ALUSrc = 1'b1; ALUControl = ALU_ADD; end
            SUBI: begin RegWrite = 1'b1; ALUSrc = 1'b1; ALUControl = ALU_SUB; end
            LUI:  begin RegWrite = 1'b1; ALUSrc = 1'b1; ALUControl = ALU_LUI; end
            BEQ:  begin Branch = 1'b1;   ALUControl = ALU_SUB; end
            J:    begin Jump = 1'b1; end
            JAL:  begin Jump = 1'b1;     Jal = 1'b1;    RegWrite = 1'b1; MemtoReg = 2'b10; end
            default: ;
        endcase
    end
endmodule


module alu(
    input [31:0] A, B,
    input [2:0]  ALUControl,
    output reg [31:0] Result,
    output Zero
);
    always @(*) begin
        case (ALUControl)
            3'b000: Result = A + B;
            3'b001: Result = A - B;
            3'b100: Result = B << 16;
            default: Result = 32'b0;
        endcase
    end
    assign Zero = (Result == 32'b0);
endmodule


module multiplier(
    input Clk, Rst,
    input Enable,
    input [31:0] A, B,
    output reg [31:0] Product,
    output reg Done
);
    reg [31:0] m_cand, m_plier;
    reg [5:0]  count;
    reg        running;

    always @(posedge Clk or posedge Rst) begin
        if (Rst) begin
            running <= 1'b0;
            Done <= 1'b0;
            Product <= 32'b0;
            count <= 6'b0;
        end else if (!Enable) begin
            running <= 1'b0;
            Done <= 1'b0;   // clear Done when Enable drops
        end else if (!running && !Done) begin
            // start new multiplication
            m_cand <= A;
            m_plier <= B;
            Product <= 32'b0;
            count <= 6'd0;
            running <= 1'b1;
        end else if (running) begin
            if (m_plier[0])
                Product <= Product + m_cand;
            m_cand <= m_cand << 1;
            m_plier <= m_plier >> 1;
            if (count == 6'd31) begin
                running <= 1'b0;
                Done <= 1'b1;
            end else begin
                count <= count + 1;
            end
        end
    end
endmodule


module divider(
    input Clk, Rst,
    input Enable,
    input [31:0] A, B,
    output [31:0] Quotient,
    output reg Done
);
    reg [63:0] P;
    reg [31:0] divisor;
    reg [5:0] count;
    reg running;
    reg div_by_zero;

    wire [63:0] p_shifted = {P[62:0], 1'b0};
    wire [31:0] rem_candidate = p_shifted[63:32];
    wire        fits = (rem_candidate >= divisor);
    wire [63:0] p_next = fits ? {rem_candidate - divisor, p_shifted[31:1], 1'b1}
                              : p_shifted;

    assign Quotient = div_by_zero ? 32'b0 : P[31:0];

    always @(posedge Clk or posedge Rst) begin
        if (Rst) begin
            running <= 1'b0;
            Done <= 1'b0;
            P <= 64'b0;
            count <= 6'b0;
            div_by_zero <= 1'b0;
        end else if (!Enable) begin
            running <= 1'b0;
            Done <= 1'b0;   // clear Done when Enable drops
        end else if (!running && !Done) begin
            P <= {32'b0, A};
            divisor <= B;
            count <= 6'd0;
            running <= 1'b1;
            div_by_zero <= (B == 32'b0);
        end else if (running) begin
            if (div_by_zero) begin
                running <= 1'b0;
                Done <= 1'b1;
            end else if (count == 6'd31) begin
                P <= p_next;
                running <= 1'b0;
                Done <= 1'b1;
            end else begin
                P <= p_next;
                count <= count + 1;
            end
        end
    end
endmodule


module regfile(
    input Clk, Rst,
    input RegWrite,
    input [4:0] ReadReg1, ReadReg2, WriteReg,
    input [31:0] WriteData,
    output [31:0] ReadData1, ReadData2,
    output [31:0] R0, R1, R2, R3, R4, R5, R6, R7,
    output [31:0] R8, R9, R10, R11, R12, R13, R14, R15,
    output [31:0] R16, R17, R18, R19, R20, R21, R22, R23,
    output [31:0] R24, R25, R26, R27, R28, R29, R30, R31
);
    reg [31:0] regs [0:31];
    integer k;

    assign ReadData1 = (ReadReg1 == 5'd0) ? 32'b0 : regs[ReadReg1];
    assign ReadData2 = (ReadReg2 == 5'd0) ? 32'b0 : regs[ReadReg2];

    always @(posedge Clk or posedge Rst) begin
        if (Rst) begin
            for (k = 0; k < 32; k = k + 1)
                regs[k] <= 32'b0;
        end else if (RegWrite && WriteReg != 5'd0) begin
            regs[WriteReg] <= WriteData;
        end
    end

    assign R0 = 32'b0; assign R1 = regs[1]; assign R2 = regs[2]; assign R3 = regs[3];
    assign R4 = regs[4]; assign R5 = regs[5]; assign R6 = regs[6]; assign R7 = regs[7];
    assign R8 = regs[8]; assign R9 = regs[9]; assign R10 = regs[10]; assign R11 = regs[11];
    assign R12 = regs[12]; assign R13 = regs[13]; assign R14 = regs[14]; assign R15 = regs[15];
    assign R16 = regs[16]; assign R17 = regs[17]; assign R18 = regs[18]; assign R19 = regs[19];
    assign R20 = regs[20]; assign R21 = regs[21]; assign R22 = regs[22]; assign R23 = regs[23];
    assign R24 = regs[24]; assign R25 = regs[25]; assign R26 = regs[26]; assign R27 = regs[27];
    assign R28 = regs[28]; assign R29 = regs[29]; assign R30 = regs[30]; assign R31 = regs[31];
endmodule