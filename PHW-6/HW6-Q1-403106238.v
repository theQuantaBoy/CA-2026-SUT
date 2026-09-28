module main (
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