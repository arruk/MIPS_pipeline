module pipeline (clk, reset, stopf);
    input  clk, reset; output stopf;

  /********************************************************************/

    logic [31:0] ROM [0:31]; 
    logic [31:0] RAM [0:31];     

  /********************************************************************/

    function isRType;  input [31:0] I; isRType  = !(|I[31:26]);                                     endfunction
    function isJR;     input [31:0] I; isJR     = (isRType(I) && I[5:0] == 6'b001000);              endfunction
    function isADDI;   input [31:0] I; isADDI   = I[31:26] == 6'b001000;                            endfunction
    function isORI;    input [31:0] I; isORI    = I[31:26] == 6'b001101;                            endfunction
    function isANDI;   input [31:0] I; isANDI   = I[31:26] == 6'b001101;                            endfunction
    function isXORI;   input [31:0] I; isXORI   = I[31:26] == 6'b001110;                            endfunction
    function isSLTI;   input [31:0] I; isSLTI   = I[31:26] == 6'b001010;                            endfunction
    function isJAL;    input [31:0] I; isJAL    = I[31:26] == 6'b000011;                            endfunction
    function isJ;      input [31:0] I; isJ      = I[31:26] == 6'b000010;                            endfunction
    function isBEQ;    input [31:0] I; isBEQ    = I[31:26] == 6'b000100;                            endfunction
    function isBNE;    input [31:0] I; isBNE    = I[31:26] == 6'b000101;                            endfunction
    function isEND;    input [31:0] I; isEND    = &(I[31:26]) & &(I[5:0]);                          endfunction
    function isALUimm; input [31:0] I; isALUimm = isADDI(I)|isORI(I)|isADDI(I)|isXORI(I)|isSLTI(I); endfunction
    function isLoad;   input [31:0] I; isLoad   = I[31:26] == 6'b100010;                            endfunction
    function isStore;  input [31:0] I; isStore  = I[31:26] == 6'b101011;                            endfunction
    function isALUreg; input [31:0] I; isALUreg = isRType(I) & !isJR(I);                            endfunction
    function isBranch; input [31:0] I; isBranch = isBEQ(I) | isBNE(I);                              endfunction

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
    localparam W_bit=4; localparam W_state = 1 << W_bit;
    
    reg [4:0] state;

    always@(posedge clk) begin
        if(reset) begin
            state <= F_state;
        end else begin
            state <= {state[3:0], state[4]};
            if(stopf) begin
                $writememh("regs.dat", registerfile);
                $writememb("RAMa.dat", RAM);
            end
        end
    end

  /********************************************************************/

    reg [31:0] F_PC;

    wire [31:0] jumpORbranchADDR;
    wire        jumpORbranch;

    initial begin
        $readmemb("ROM.dat", ROM);
    end

    always@(posedge clk) begin
        if(reset)begin
            F_PC <=0;
        end else if(state[F_bit]) begin
            FD_instr <= ROM[F_PC[31:2]];
            FD_PC    <= F_PC;
            F_PC     <= F_PC+4;
        end else if(state[M_bit] & jumpORbranch) begin
            F_PC     <= jumpORbranchADDR;
        end
    end
    
  /********************************************************************/

    reg [31:0] FD_instr;
    reg [31:0] FD_PC;

  /********************************************************************/

    wire        wbEnable;
    wire [31:0] wbData;
    wire  [4:0] wbRdID;

    reg [31:0] registerfile [0:31];

    always@(posedge clk) begin
        if(state[D_bit]) begin
            DE_PC    <= FD_PC;
            DE_instr <= FD_instr;
            DE_rs    <= registerfile[rsID(FD_instr)];
            DE_rt    <= registerfile[rtID(FD_instr)]; 
        end
    end

    always@(posedge clk) begin
        if(wbEnable) begin
            registerfile[wbRdID] <= wbData;
        end
    end

  /********************************************************************/

    reg [31:0] DE_instr;
    reg [31:0] DE_PC;
    reg [31:0] DE_rs;
    reg [31:0] DE_rt;
    
  /********************************************************************/
    wire [7:0] E_aluop = aluop(DE_instr);

    wire [31:0] E_aluIN1 = DE_rs;
    wire [31:0] E_aluIN2 = (isALUreg(DE_instr) | isBranch(DE_instr)) ? DE_rt   :
                           (E_aluop[6] | E_aluop[7]) ? {27'b0, DE_instr[10:6]} :
                           Iimm(DE_instr)                                      ;

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
    wire [31:0] E_leftshift = flip32(E_rightshift);

    reg [31:0] E_aluout;
    always@(*)
        if( isADDI(DE_instr) || E_aluop[0])
            E_aluout = E_aluPlus;
        else if( E_aluop[1])
            E_aluout = E_aluMinus;
        else if( isANDI(DE_instr) || E_aluop[2])
            E_aluout = E_aluIN1 & E_aluIN2;
        else if( isORI(DE_instr)  || E_aluop[3])
            E_aluout = E_aluIN1 | E_aluIN2;
        else if( isXORI(DE_instr) || E_aluop[4])
            E_aluout = E_aluIN1 ^ E_aluIN2;
        else if( isSLTI(DE_instr) || E_aluop[5])
            E_aluout = {31'b0, E_LT};
        else if( E_aluop[6])
            E_aluout = E_leftshift;
        else if( E_aluop[7])
            E_aluout = E_rightshift;      

    
    wire E_takebranch = (isBEQ(DE_instr) &&  E_EQ) | 
                        (isBNE(DE_instr) && ~E_EQ) ;

    wire E_jumpORbranch = (isJ(DE_instr) | isJAL(DE_instr) | isJR(DE_instr) | E_takebranch);

    wire [31:0] DE_PCP4 = DE_PC + 4;

    wire [31:0] E_jumpORbranchADDR = 
                        (isJ(DE_instr) | isJAL(DE_instr)) ? {DE_PCP4[31:28], Jimm(DE_instr)} :
                        (isJAL(DE_instr))                 ? DE_rs : 
                                                            DE_PCP4 + {14'b0, DE_instr[15:0], 2'b0};

    wire [31:0] E_result = (isJ(DE_instr) | isJAL(DE_instr) | isJR(DE_instr)) ? DE_PC+4 : E_aluout;

    always@(posedge clk) begin
        if(state[E_bit])begin
            EM_PC      <= DE_PC;
            EM_instr   <= DE_instr;
            EM_rt      <= DE_rt;
            EM_Eresult <= E_result;
            EM_addr    <= DE_rs + Iimm(DE_instr) ;
        end
    end

    assign jumpORbranchADDR = E_jumpORbranchADDR;
    assign jumpORbranch = E_jumpORbranch;

  /********************************************************************/

    reg [31:0] EM_instr;
    reg [31:0] EM_PC;
    reg [31:0] EM_rt;
    reg [31:0] EM_Eresult;
    reg [31:0] EM_addr;

  /********************************************************************/

    wire [31:0] M_store_data = EM_rt;

    wire [31:0] M_word_addr = EM_addr;

    wire wenDM = isStore(EM_instr);

    always@(posedge clk) begin
        MW_Mdata <= RAM[M_word_addr];
        if(wenDM) RAM[M_word_addr] <= M_store_data;
    end

    always@(posedge clk) begin
        if(state[M_bit]) begin
            MW_PC      <= EM_PC;
            MW_instr   <= EM_instr;
            MW_Eresult <= EM_Eresult;
            MW_add     <= EM_addr;
        end
    end

  /********************************************************************/

    reg [31:0] MW_instr;
    reg [31:0] MW_PC;
    reg [31:0] MW_Eresult;
    reg [31:0] MW_add;      
    reg [31:0] MW_Mdata;

  /********************************************************************/  

    wire [31:0] W_Mresult = MW_Mdata;
    
    assign wbData   = isLoad(MW_instr) ? W_Mresult : MW_Eresult ;

    assign wbEnable = !isBranch(MW_instr) & !isStore(MW_instr) & (isALUreg(MW_instr) ? rdID(MW_instr) != 0 : rtID(MW_instr) != 0 ) ;

    assign wbRdID   = isJAL(MW_instr)    ? 5'd31          : 
                      isALUreg(MW_instr) ? rdID(MW_instr) :
                      rtID(MW_instr)                      ;
                
    assign stopf = isEND(MW_instr) & state == 4'b0001;

    initial begin
        registerfile[0] = 0;
    end
        
endmodule