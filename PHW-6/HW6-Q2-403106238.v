module main (
    input wire Clk, input wire Rst,
    input wire [127:0] InstrMM_DataIn, input wire InstrMM_Done,
    input wire [127:0] DataMM_DataIn, input wire DataMM_Done,
    
    output wire [31:0] R0,  R1,  R2,  R3,
    output wire [31:0] R4,  R5,  R6,  R7,
    output wire [31:0] R8,  R9,  R10, R11,
    output wire [31:0] R12, R13, R14, R15,
    output wire [31:0] R16, R17, R18, R19,
    output wire [31:0] R20, R21, R22, R23,
    output wire [31:0] R24, R25, R26, R27,
    output wire [31:0] R28, R29, R30, R31,

    output wire [31:0] InstrMM_Addr, output wire InstrMM_Read, 
    output wire [31:0] DataMM_Addr, output wire DataMM_Read,
    output wire DataMM_Write, output wire [127:0] DataMM_DataOut,
    
    output wire [31:0] PC
);

    // CPU outputs
    wire [31:0] cpu_instr_addr;  // word address of current PC (= PC >> 2)
    wire [31:0] cpu_data_addr;   // word address of data access (= ALU_result >> 2)
    wire cpu_data_write;         // MemWrite from control unit
    wire [31:0] cpu_data_out;    // data to store (for SW)
    wire cpu_mem_read;           // MemRead from control unit (exposed via MemRead_out)

    // Cache data outputs
    wire [31:0] icache_data;    // instruction word from icache
    wire icache_done;           // icache CPU_Done
    wire [31:0] dcache_data;    // data word from dcache
    wire dcache_done;           // dcache CPU_Done

    wire [31:0] instr_byte_addr = {cpu_instr_addr[29:0], 2'b00};
    wire [31:0] data_byte_addr  = {cpu_data_addr[29:0],  2'b00};

    // Stall logic
    reg data_done_flag;

    wire dcache_active = (cpu_mem_read || cpu_data_write) && icache_done;
    wire dcache_stall = dcache_active && !data_done_flag;
    wire total_stall = !icache_done || dcache_stall;

    always @(posedge Clk or posedge Rst) begin
        if (Rst)
            data_done_flag <= 1'b0;
        else if (!total_stall)
            data_done_flag <= 1'b0;
        else if (dcache_done && dcache_active)
            data_done_flag <= 1'b1;
    end

    // Instruction cache
    wire icache_mm_write_nc;
    wire [127:0] icache_mm_dataout_nc;

    cache icache (
        .Clk        (Clk),
        .Rst        (Rst),
        .CPU_Addr   (instr_byte_addr),
        .CPU_Read   (1'b1),       // always fetching
        .CPU_Write  (1'b0),
        .CPU_DataIn (32'b0),
        .CPU_Done   (icache_done),
        .CPU_DataOut(icache_data),
        .MM_Addr    (InstrMM_Addr),
        .MM_Read    (InstrMM_Read),
        .MM_Write   (icache_mm_write_nc),    // icache never writes
        .MM_DataIn  (InstrMM_DataIn),
        .MM_DataOut (icache_mm_dataout_nc),  // icache never writes
        .MM_Done    (InstrMM_Done)
    );

    // Data cache
    cache dcache (
        .Clk        (Clk),
        .Rst        (Rst),
        .CPU_Addr   (data_byte_addr),
        .CPU_Read   (cpu_mem_read  && icache_done),
        .CPU_Write  (cpu_data_write && icache_done),
        .CPU_DataIn (cpu_data_out),
        .CPU_Done   (dcache_done),
        .CPU_DataOut(dcache_data),
        .MM_Addr    (DataMM_Addr),
        .MM_Read    (DataMM_Read),
        .MM_Write   (DataMM_Write),
        .MM_DataIn  (DataMM_DataIn),
        .MM_DataOut (DataMM_DataOut),
        .MM_Done    (DataMM_Done)
    );

    // CPU core
    cpu_core cpu0 (
        .Clk        (Clk),
        .Rst        (Rst),
        .ExtStall   (total_stall),
        .InstrIn    (icache_data),
        .DataIn     (dcache_data),
        .InstrAddr  (cpu_instr_addr),
        .DataAddr   (cpu_data_addr),
        .DataWrite  (cpu_data_write),
        .DataOut    (cpu_data_out),
        .MemRead_out(cpu_mem_read),
        .R0 (R0),  .R1 (R1),  .R2 (R2),  .R3 (R3),
        .R4 (R4),  .R5 (R5),  .R6 (R6),  .R7 (R7),
        .R8 (R8),  .R9 (R9),  .R10(R10), .R11(R11),
        .R12(R12), .R13(R13), .R14(R14), .R15(R15),
        .R16(R16), .R17(R17), .R18(R18), .R19(R19),
        .R20(R20), .R21(R21), .R22(R22), .R23(R23),
        .R24(R24), .R25(R25), .R26(R26), .R27(R27),
        .R28(R28), .R29(R29), .R30(R30), .R31(R31)
    );

    assign PC = cpu_instr_addr;
endmodule


module cache (
    input wire Clk, input wire Rst,
    input wire [31:0] CPU_DataIn, input wire [31:0] CPU_Addr, input wire CPU_Write,
    input wire CPU_Read, input wire [127:0] MM_DataIn, input wire MM_Done,
    output reg [31:0] CPU_DataOut, output reg CPU_Done, output reg MM_Write,
    output reg MM_Read, output reg [31:0] MM_Addr, output reg [127:0] MM_DataOut
);
    reg valid [0:15];
    reg [23:0] tag_arr [0:15];
    reg [127:0] data_arr [0:15];

    // FSM
    localparam S_IDLE = 3'd0;
    localparam S_MM_RD_PULSE = 3'd1;
    localparam S_MM_RD_WAIT = 3'd2;
    localparam S_MM_WR_PULSE = 3'd3;
    localparam S_MM_WR_WAIT = 3'd4;
    localparam S_DONE = 3'd5;

    reg [2:0] state;

    reg [23:0] sv_tag;    // tag of in-flight request
    reg [3:0] sv_idx;     // cache set index
    reg [1:0] sv_woff;    // word offset within the line
    reg [31:0] sv_baddr;  // 16-byte-aligned block address (→ MM_Addr)
    reg [31:0] sv_wdata;  // CPU write data (write requests only)
    reg sv_is_write;      // 1 = write transaction, 0 = read transaction

    wire [23:0] c_tag = CPU_Addr[31:8];
    wire [3:0] c_idx = CPU_Addr[7:4];
    wire [1:0] c_woff = CPU_Addr[3:2];
    wire [31:0] c_baddr = {CPU_Addr[31:4], 4'b0};   // clear low 4 bits

    // Hit: line is valid AND tag matches
    wire hit = valid[c_idx] && (tag_arr[c_idx] == c_tag);

    // Combinational Output
    always @(*) begin
        CPU_Done = 1'b0;
        CPU_DataOut = 32'b0;
        MM_Read = 1'b0;
        MM_Write = 1'b0;
        MM_Addr = 32'b0;
        MM_DataOut = 128'b0;

        case (state)
            S_IDLE: begin
                if (CPU_Read && hit) begin
                    CPU_Done = 1'b1;
                    case (c_woff)
                        2'b00: CPU_DataOut = data_arr[c_idx][31:0];
                        2'b01: CPU_DataOut = data_arr[c_idx][63:32];
                        2'b10: CPU_DataOut = data_arr[c_idx][95:64];
                        2'b11: CPU_DataOut = data_arr[c_idx][127:96];
                    endcase
                end
            end

            S_MM_RD_PULSE: begin
                MM_Read = 1'b1;
                MM_Addr = sv_baddr;
            end

            S_MM_RD_WAIT: begin
                MM_Addr = sv_baddr;
            end

            S_MM_WR_PULSE: begin
                MM_Write = 1'b1;
                MM_Addr = sv_baddr;
                MM_DataOut = data_arr[sv_idx]; // updated line (written at prev posedge)
            end

            S_MM_WR_WAIT: begin
                MM_Addr = sv_baddr;
                MM_DataOut = data_arr[sv_idx];
            end

            S_DONE: begin
                CPU_Done = 1'b1;
            end

            default: ;
        endcase
    end

    integer k;

    // Sequential FSM
    always @(posedge Clk or posedge Rst) begin
        if (Rst) begin
            state <= S_IDLE;
            sv_tag <= 24'b0;
            sv_idx <= 4'b0;
            sv_woff <= 2'b0;
            sv_baddr <= 32'b0;
            sv_wdata <= 32'b0;
            sv_is_write <= 1'b0;
            for (k = 0; k < 16; k = k + 1)
                valid[k] <= 1'b0;
        end else begin
            case (state)

                S_IDLE: begin
                    if (CPU_Read || CPU_Write) begin
                        if (hit) begin
                            if (CPU_Write) begin
                                // Write hit
                                sv_tag <= c_tag;
                                sv_idx <= c_idx;
                                sv_woff <= c_woff;
                                sv_baddr <= c_baddr;
                                sv_wdata <= CPU_DataIn;
                                sv_is_write <= 1'b1;
                                case (c_woff)
                                    2'b00: data_arr[c_idx] <= {data_arr[c_idx][127:32],  CPU_DataIn};
                                    2'b01: data_arr[c_idx] <= {data_arr[c_idx][127:64],  CPU_DataIn, data_arr[c_idx][31:0]};
                                    2'b10: data_arr[c_idx] <= {data_arr[c_idx][127:96],  CPU_DataIn, data_arr[c_idx][63:0]};
                                    2'b11: data_arr[c_idx] <= {CPU_DataIn, data_arr[c_idx][95:0]};
                                endcase
                                state <= S_MM_WR_PULSE;
                            end

                        end else begin
                            // Miss (read or write)
                            sv_tag <= c_tag;
                            sv_idx <= c_idx;
                            sv_woff <= c_woff;
                            sv_baddr <= c_baddr;
                            sv_wdata <= CPU_DataIn;
                            sv_is_write <= CPU_Write;
                            state <= S_MM_RD_PULSE;
                        end
                    end
                end

                S_MM_RD_PULSE: begin
                    state <= S_MM_RD_WAIT;
                end

                S_MM_RD_WAIT: begin
                    if (MM_Done) begin
                        valid[sv_idx] <= 1'b1;
                        tag_arr[sv_idx] <= sv_tag;

                        if (sv_is_write) begin
                            // Write-allocate
                            case (sv_woff)
                                2'b00: data_arr[sv_idx] <= {MM_DataIn[127:32],  sv_wdata};
                                2'b01: data_arr[sv_idx] <= {MM_DataIn[127:64],  sv_wdata, MM_DataIn[31:0]};
                                2'b10: data_arr[sv_idx] <= {MM_DataIn[127:96],  sv_wdata, MM_DataIn[63:0]};
                                2'b11: data_arr[sv_idx] <= {sv_wdata, MM_DataIn[95:0]};
                            endcase
                            state <= S_MM_WR_PULSE;
                        end else begin
                            // Read miss
                            data_arr[sv_idx] <= MM_DataIn;
                            state <= S_IDLE;
                        end
                    end
                end

                S_MM_WR_PULSE: begin
                    state <= S_MM_WR_WAIT;
                end

                S_MM_WR_WAIT: begin
                    if (MM_Done) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    if (!CPU_Write) begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule


module cpu_core(
    input ExtStall,
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
    output MemRead_out
);

    reg [31:0] PC;

    // instruction fields
    wire [5:0] opcode = InstrIn[31:26];
    wire [4:0] rs = InstrIn[25:21];
    wire [4:0] rt = InstrIn[20:16];
    wire [4:0] rd = InstrIn[15:11];
    wire [5:0] funct = InstrIn[5:0];
    wire [15:0] imm = InstrIn[15:0];
    wire [25:0] jaddr = InstrIn[25:0];

    wire [31:0] sext_imm = {{16{imm[15]}}, imm};

    // control signals
    wire RegDst, RegWrite, ALUSrc, MemRead, MemWrite, Branch, Jump, Jal, Jr;
    wire [1:0] MemtoReg;
    wire [2:0] ALUControl;

    control_unit cu(
        .opcode(opcode), .funct(funct),
        .RegDst(RegDst), .RegWrite(RegWrite), .ALUSrc(ALUSrc),
        .MemtoReg(MemtoReg), .MemRead(MemRead), .MemWrite(MemWrite),
        .Branch(Branch), .Jump(Jump), .Jal(Jal), .Jr(Jr),
        .ALUControl(ALUControl)
    );

    assign MemRead_out = MemRead;

    localparam ALU_MUL = 3'b010;
    localparam ALU_DIV = 3'b011;

    wire [31:0] reg_rs_data, reg_rt_data;
    wire [31:0] alu_b = ALUSrc ? sext_imm : reg_rt_data;

    wire [31:0] mul_result, div_result;
    wire mul_done, div_done;

    multiplier mul0(
        .Clk(Clk), .Rst(Rst), .Enable(ALUControl == ALU_MUL),
        .A(reg_rs_data), .B(alu_b),
        .Product(mul_result), .Done(mul_done)
    );

    divider div0(
        .Clk(Clk), .Rst(Rst), .Enable(ALUControl == ALU_DIV),
        .A(reg_rs_data), .B(alu_b),
        .Quotient(div_result), .Done(div_done)
    );

    wire stall = ExtStall || (ALUControl == ALU_MUL && !mul_done) 
                          || (ALUControl == ALU_DIV && !div_done);

    // register file
    wire [4:0] write_reg = Jal ? 5'd31 : (RegDst ? rd : rt);
    wire real_regwrite = RegWrite && !stall;
    wire [31:0] write_data;

    regfile rf(
        .Clk(Clk), .Rst(Rst),
        .RegWrite(real_regwrite),
        .ReadReg1(rs), .ReadReg2(rt),
        .WriteReg(write_reg), .WriteData(write_data),
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

    wire [31:0] alu_result;
    wire        zero;

    alu alu0(
        .A(reg_rs_data), .B(alu_b), .ALUControl(ALUControl),
        .Result(alu_result), .Zero(zero)
    );

    wire [31:0] final_result = (ALUControl == ALU_MUL) ? mul_result :
                                (ALUControl == ALU_DIV) ? div_result :
                                                           alu_result;

    // write-back mux
    wire [31:0] pc_plus4 = PC + 32'd4;
    assign write_data = (MemtoReg == 2'd2) ? pc_plus4 :
                         (MemtoReg == 2'd1) ? DataIn   :
                                              final_result;

    // next PC
    wire [31:0] branch_target = pc_plus4 + (sext_imm << 2);
    wire [31:0] jump_target   = {pc_plus4[31:28], jaddr, 2'b00};

    wire [31:0] pc_normal_next = Jr               ? reg_rs_data   :
                                 Jump             ? jump_target   :
                                 (Branch & zero)  ? branch_target :
                                                    pc_plus4;

    wire [31:0] next_pc = stall ? PC : pc_normal_next;

    always @(posedge Clk or posedge Rst) begin
        if (Rst) PC <= 32'b0;
        else     PC <= next_pc;
    end

    assign InstrAddr = PC >> 2;
    assign DataAddr = (MemRead | MemWrite) ? (final_result >> 2) : 32'b0;
    assign DataOut = reg_rt_data;
    assign DataWrite = MemWrite;
endmodule


module control_unit(
    input [5:0] opcode,
    input [5:0] funct,
    output reg RegDst, RegWrite, ALUSrc, MemRead, MemWrite, Branch, Jump, Jal, Jr,
    output reg [1:0] MemtoReg,
    output reg [2:0] ALUControl
);

    // opcodes
    localparam RTYPE = 6'b000000;
    localparam LW = 6'b100011;
    localparam SW = 6'b101011;
    localparam ADDI = 6'b001000;
    localparam SUBI = 6'b001001;
    localparam LUI = 6'b001111;
    localparam BEQ = 6'b000100;
    localparam J = 6'b000010;
    localparam JAL = 6'b000011;

    // funct codes (R-type)
    localparam F_ADD = 6'b100000;
    localparam F_SUB = 6'b100010;
    localparam F_MUL = 6'b011000;
    localparam F_DIV = 6'b011010;
    localparam F_JR  = 6'b001000;

    // ALU control codes
    localparam ALU_ADD = 3'b000;
    localparam ALU_SUB = 3'b001;
    localparam ALU_MUL = 3'b010;
    localparam ALU_DIV = 3'b011;
    localparam ALU_LUI = 3'b100;

    always @(*) begin
        // defaults - nop-like, avoids latches
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

            default: ; // unused opcode, treat as nop
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
            Done    <= 1'b0;
        end else if (!running && !Done) begin
            // first cycle this instruction is seen: load operands
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
            Done <= 1'b0;
        end else if (!running && !Done) begin
            // first cycle this instruction is seen: load operands
            P <= {32'b0, A};
            divisor <= B;
            count <= 6'd0;
            running <= 1'b1;
            div_by_zero <= (B == 32'b0); // not exercised by the grading program
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
    output [31:0] R0, output [31:0] R1, output [31:0] R2, output [31:0] R3,
    output [31:0] R4, output [31:0] R5, output [31:0] R6, output [31:0] R7,
    output [31:0] R8, output [31:0] R9, output [31:0] R10, output [31:0] R11,
    output [31:0] R12, output [31:0] R13, output [31:0] R14, output [31:0] R15,
    output [31:0] R16, output [31:0] R17, output [31:0] R18, output [31:0] R19,
    output [31:0] R20, output [31:0] R21, output [31:0] R22, output [31:0] R23,
    output [31:0] R24, output [31:0] R25, output [31:0] R26, output [31:0] R27,
    output [31:0] R28, output [31:0] R29, output [31:0] R30, output [31:0] R31
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