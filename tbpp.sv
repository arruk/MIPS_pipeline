`timescale 1ns/1ps

`include "pipeline2.sv"
`include "pipeline.sv"

module tbpp;

    reg  clk, reset, stopf, stopf2;

    pipeline dut(clk, reset, stopf);

    pipeline2 dut2(clk, reset, stopf2);

    integer i;

    always begin
        clk=0; #5; clk=1; #5;
    end

    initial begin
        i=0;
        reset = 1'b1; #10; reset = 1'b0;
        $display("initializing testbench!");
        $dumpfile("dump.vcd"); $dumpvars;
    end

    always@(posedge clk) begin
        
        i++;
        
        if(stopf || i>500) begin
            $display("finishing testbench");
            $finish();
        end
    end
endmodule