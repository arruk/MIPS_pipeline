module pipeline (clk, reset, addIM, dataIM, addDM, dataDM, wenDM, dataOUT);
    input clk, reset; input [31:0] dataIM, dataDM;
    output reg[31:0] addIM, addDM, dataOUT; output wenDM;

  /********************************************************************/

    function isRType;  input [31:0] I; isRType  = !(|I[31:26]);                                         endfunction
    function isJR;     input [31:0] I; isJR     = (isRType(I) && I[5:0] == 6'b001000);                  endfunction
    function isADDI;   input [31:0] I; isADDI   = I[31:26] == 6'b001000;                                endfunction
    function isORI;    input [31:0] I; isORI    = I[31:26] == 6'b001101;                                endfunction
    function isANDI;   input [31:0] I; isANDI   = I[31:26] == 6'b001101;                                endfunction
    function isXORI;   input [31:0] I; isXORI   = I[31:26] == 6'b001110;                                endfunction
    function isSLTI;   input [31:0] I; isSLTI   = I[31:26] == 6'b001010;                                endfunction
    function isJAL;    input [31:0] I; isJAL    = I[31:26] == 6'b000011;                                endfunction
    function isJ;      input [31:0] I; isJ      = I[31:26] == 6'b000010;                                endfunction
    function isBEQ;    input [31:0] I; isBEQ    = I[31:26] == 6'b000100;                                endfunction
    function isBNE;    input [31:0] I; isBNE    = I[31:26] == 6'b000101;                                endfunction
    function isEND;    input [31:0] I; isEND    = &(I[31:26]) & &(I[5:0]);                              endfunction
    function isALUimm; input [31:0] I; isALUimm = isADDI(I)||isORI(I)||isADDI(I)||isXORI(I)||isSLTI(I); endfunction
    function isLoad;   input [31:0] I; isLoad   = I[31:26] == 6'b100010;                                endfunction
    function isStore;  input [31:0] I; isStore  = I[31:26] == 6'b101011;                                endfunction

    function [4:0] rsID;  input [31:0] I; rsID = I[25:21]; endfunction
    function [4:0] rtID;  input [31:0] I; rtID = I[20:16]; endfunction
    function [4:0] rdID;  input [31:0] I; rdID = I[15:11]; endfunction

    function [5:0] op;    input [31:0] I; op    = I[31:26]; endfunction
    function [4:0] funct; input [31:0] I; funct = I[5:0];   endfunction

    function aluop;    
        input [31:0] I; 
        aluop = !isRType(I) ? 8'h00 :
                (I[5:0] == 6'b100000) ? 8'h01 : (I[5:0] == 6'b100010) ? 8'h02 : (I[5:0] == 6'b100100) ? 8'h04 :
                (I[5:0] == 6'b100101) ? 8'h08 : (I[5:0] == 6'b100110) ? 8'h10 : (I[5:0] == 6'b101010) ? 8'h20 :
                (I[5:0] == 6'b000000) ? 8'h40 : (I[5:0] == 6'b000010) ? 8'h80 : 8'h00                         ;    
    endfunction

    function [31:0]Iimm;
        input [31:0] I;
        Iimm = {{16{I[15]}}, I[15:0]};
    endfunction
    
    function [27:0]Jimm;
        input [31:0] I;
        Jimm = {I[25:0], 2'b00};
    endfunction

  /********************************************************************/
    localparam F_bit=0; localparam F_state = 1 << F_bit;
    localparam D_bit=1; localparam D_state = 1 << D_bit;
    localparam E_bit=2; localparam E_state = 1 << E_bit;
    localparam M_bit=3; localparam M_state = 1 << M_bit;
    localparam w_bit=4; localparam W_state = 1 << W_bit;
    
    reg [4:0] state;
    wire halt

    always@(posedge clk) begin
        if(reset) begin
            state <= F_state;
        end else if(!halt) begin
            state <= {state[3:0], state[4]};
        end
    end

  /********************************************************************/

    reg [31:0] F_PC;

    always@(posedge clk) begin
        if(reset)begin
            F_PC <=0;
        end else if(state[F_bit]) begin
            FD_instr <= dataIM;
            FD_PC    <= F_PC;
            F_PC     <= F_PC+4;
        end else if(state[M_bit] & jumpORbranch) begin
            F_PC <= jumpORbranchADDR;
        end
    end
    
  /********************************************************************/

    reg [31:0] FD_instr;
    reg [31:0] FD_PC;

  /********************************************************************/

    reg [31:0] registerfile [0:31];

    always@(posedge clk) begin
        if(state[D_bit]) begin
            DE_PC    <= FD_PC;
            DE_instr <= DE_instr;
            DE_rs    <= registerfile[rsID(FD_instr)];
            DE_rt    <= registerfile[rtID(FD_instr)]; 
        end
    end

    always@(posedge clk) begin
        if(wbEnable) begin
            registerfile[wbRdID] <== wbData;
        end
    end

  /********************************************************************/

    reg [31:0] DE_instr;
    reg [31:0] DE_PC;
    reg [31:0] DE_rs;
    reg [31:0] DE_rt;
    
  /********************************************************************/

    wire [31:0] E_aluIN1 = DE_rs;
    wire [31:0] E_aluIN2 = (isALUreg | isBranch) ? DE_rt : (aluop(DE_instr)[6] | aluop(DE_instr)[7]) ? {27'b0, DE_instr[10:6]} : Iimm(DE_instr);

    wire [31:0] E_aluPlus = E_aluIN1 + E_aluIN2;
    wire [32:0] E_aluMinus = {1'b0, E_aluIN1} + {1'b1, ~E_aluIN2} + 33'b1;
    wire E_LT = (E_aluIN1[31]  ^ E_aluIN2[31]) ? E_aluIN1[31] : E_aluMinus[32];
    wire E_EQ = (E_aluMinus == 0);

    function [31:0] flip32;
        input[31:0] I;
        flip32 = {I[ 0],I[ 1],I[ 2],I[ 3],I[ 4],I[ 5],I[ 6],I[ 7],
                  I[ 8],I[ 9],I[10],I[11],I[12],I[13],I[14],I[15],
                  I[16],I[17],I[18],I[19],I[20],I[21],I[22],I[23],
                  I[24],I[25],I[26],I[27],I[28],I[29],I[30],I[31]};
    endfunction

    wire [31:0] E_rightshift =  E_aluIN2 >> E_aluIN1 ;
    wire [31:0] E_leftshift = flip32(E_shifter);

    reg [31:0] E_aluout;
    always@(*)
        case(aluop(DE_instr))
            8'h01: E_aluout = E_aluPlus;
            8'h02: E_aluout = E_aluMinus;
            8'h04: E_aluout = E_aluIN1 & E_aluIN2;
            8'h08: E_aluout = E_aluIN1 | E_aluIN2;
            8'h10: E_aluout = E_aluIN1 ^ E_aluIN2;
            8'h20: E_aluout = {31'b0, E_LT};
            8'h40: E_aluout = E_leftshift;
            8'h80: E_aluout = E_rightshift;
        endcase

    
    wire E_takebranch = (isBEQ(DE_instr) &&  E_EQ) | 
                        (isBNE(DE_instr) && ~E_EQ) ;

    wire E_jumpORbranch = (isJ(DE_instr) | isJAL(DE_instr) | isJR(DE_instr) | E_takebranch);

    wire [31:0] jumpORbranchADDR = 
                        (isJ(DE_instr) | isJAL(DE_instr)) ? {DE_PC[31:28], Jimm(DE_instr)} :
                        (isJAL(DE_instr))                 ? DE_rs : 
                                                            DE_PC + {14'b0, DE_instr[15:0], 2'b0};

    wire [31:0] E_result = (isJ(DE_instr) | isJAL(DE_instr) | isJR(DE_instr)) ? DE_PC+4 : E_aluout;

endmodule