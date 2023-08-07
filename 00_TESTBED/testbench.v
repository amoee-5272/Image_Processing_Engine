`timescale 1ns/100ps
`define CYCLE       40.0     // CLK period.
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   10000000
`define RST_DELAY   2


`ifdef tb1
    `define INFILE "../00_TESTBED/PATTERN/indata.dat"
    `define OPFILE "../00_TESTBED/PATTERN/opmode1.dat"
    `define GOLDEN "../00_TESTBED/PATTERN/golden1.dat"
    `define TEST_OP_NUM 39
    `define GOLDEN_NUM 2
`elsif tb2
    `define INFILE "../00_TESTBED/PATTERN/indata.dat"
    `define OPFILE "../00_TESTBED/PATTERN/opmode2.dat"
    `define GOLDEN "../00_TESTBED/PATTERN/golden2.dat"
    `define TEST_OP_NUM 25
    `define GOLDEN_NUM 16
`elsif tb3
    `define INFILE "../00_TESTBED/PATTERN/indata.dat"
    `define OPFILE "../00_TESTBED/PATTERN/opmode3.dat"
    `define GOLDEN "../00_TESTBED/PATTERN/golden3.dat"
    `define TEST_OP_NUM 242
    `define GOLDEN_NUM 120
`else
    `define INFILE "../00_TESTBED/PATTERN/indata.dat"
    `define OPFILE "../00_TESTBED/PATTERN/opmode0.dat"
    `define GOLDEN "../00_TESTBED/PATTERN/golden0.dat"
    `define TEST_OP_NUM 13
    `define GOLDEN_NUM 4
`endif

`ifdef SYN
    `define SDFFILE "./core_syn.sdf"
`elsif APR
    `define SDFFILE "./layout/core_apr.sdf"
`endif


module testbed;

    parameter INST_BW     = 4;
    parameter INPUT_BW    = 8;
    parameter IMG_W       = 16;
    parameter IMG_MAX_CH  = 1;
    parameter IMG_SIZE    = IMG_W * IMG_W * IMG_MAX_CH;
    parameter OUTPUT_BW   = 8;
     
    reg                  clk, rst_n;
    reg                  op_valid;
    reg  [  INST_BW-1:0] op_mode;
    wire                 op_ready;
    reg                  in_valid;
    reg  [ INPUT_BW-1:0] in_data;
    wire                 in_ready;
    wire                 out_valid;
    wire [OUTPUT_BW-1:0] out_data;

    integer              i;
    integer              cnt_pixel;
    integer              cnt_out_valid;
    integer              addr; //output address
    integer              t0, t1;
    integer              error;

    reg  [ INPUT_BW-1:0] indata_mem [0:IMG_SIZE-1];
    reg  [  INST_BW-1:0] opmode_mem [      0:1023];
    reg  [OUTPUT_BW-1:0] golden_mem [      0:4095];

    // Write out wavgform file
    initial begin
        `ifdef FSDB
            `ifdef SYN
                $fsdbDumpfile("core_syn.fsdb");
            `elsif APR
                $fsdbDumpfile("core_apr.fsdb");
            `else
                $fsdbDumpfile("core.fsdb");
            `endif
            $fsdbDumpvars(0, "+mda");
            $fsdbDumpvars;
        `endif
    end

    `ifdef SYN
        initial $sdf_annotate(`SDFFILE, u_core);
        initial #1 $display("SDF File %s were used for this simulation.", `SDFFILE);
    `elsif APR
        initial $sdf_annotate(`SDFFILE, u_core);
        initial #1 $display("SDF File %s were used for this simulation.", `SDFFILE);
    `endif


    core u_core (
    	.i_clk(clk),
    	.i_rst_n(rst_n),
    	.i_op_valid(op_valid),
    	.i_op_mode(op_mode),
        .o_op_ready(op_ready),
    	.i_in_valid(in_valid),
    	.i_in_data(in_data),
    	.o_in_ready(in_ready),
    	.o_out_valid(out_valid),
    	.o_out_data(out_data)
    );

    // Read in test pattern and golden pattern
    initial $readmemb(`INFILE, indata_mem);
    initial $readmemb(`OPFILE, opmode_mem);
    initial $readmemb(`GOLDEN, golden_mem);

    // Clock generation
    initial clk = 1'b0;
    always begin #(`CYCLE/2) clk = ~clk; end

    // Reset generation
    initial begin
        rst_n = 1; # (               0.25 * `CYCLE);
        rst_n = 0; # ((`RST_DELAY - 0.25) * `CYCLE);
        rst_n = 1; # (         `MAX_CYCLE * `CYCLE);
        $display("Error! Runtime exceeded!");
        $finish;
    end

    initial begin

        i             = 1;
        cnt_pixel     = 0;
        cnt_out_valid = 0;
        op_valid      = 0;
        op_mode       = 0;
        in_valid      = 0;
        in_data       = 0;
        rst_n         = 1;
        t0            = 0;
        t1            = 0;
        error         = 0;

        reset;

        @(negedge clk);
        // load image
        while (op_ready == 1'b0) begin
            @(negedge clk);
        end
        @(negedge clk);
        op_valid  =  1'b1;
        op_mode   =  4'b0;

        @(negedge clk);
        if (op_ready) begin
            $display("Error: o_op_ready & i_op_valid overlapped!!");
            $finish;
        end
        op_valid  = 1'b0;
        in_valid  = 1'b1;
        in_data   = indata_mem[cnt_pixel];

        t0 = $realtime;
        while (cnt_pixel < IMG_SIZE-1) begin
            @(negedge clk);
            if (in_ready == 1'b1) begin
                cnt_pixel = cnt_pixel + 1;
                in_data   = indata_mem[cnt_pixel];
            end
            if (op_ready) begin
                $display("Error: o_op_ready & i_in_valid overlapped!!");
                $finish;
            end
        end

        while (in_ready == 1'b0) begin
            @(negedge clk);
            if (op_ready) begin
                $display("Error: o_op_ready & i_in_valid overlapped!!");
                $finish;
            end
        end
        @(negedge clk);
        in_valid  = 1'b0;
        in_data   = 0;

        t1 = $realtime;
        $display("Data loading took %d", t1-t0);
        if (t1 - t0 > 300 * `CYCLE) begin
            $display("Error: data loading exceeded 3000 cycles!!");
            $finish;
        end

        while (i<`TEST_OP_NUM) begin
            cnt_out_valid = 0;
            while (op_ready == 1'b0) begin
                @(negedge clk);
            end
            if (out_valid && op_ready) begin
                $display("Error: o_out_valid & o_op_ready overlapped!!");
                $finish;
            end
            t1 = $realtime;

            @(negedge clk);
            op_valid  =  1'b1;
            op_mode   =  opmode_mem[i];
            $display("Mode = %d ",op_mode);
            if (out_valid) begin
                $display("Error: o_out_valid & i_op_valid overlapped!!");
                $finish;
            end

            @(negedge clk);
            if (op_ready) begin
                $display("Error: o_op_ready & i_op_valid overlapped!!");
                $finish;
            end
            op_valid  = 1'b0;
            op_mode   = 0;
            t0        = $realtime;
            if (out_valid == 1'b1) begin
                $display("Error: o_out_valid & i_in_valid overlapped!!");
                $finish;
            end

            i = i + 1;
        end
    end

    initial begin
        addr = 0;
        error = 0;
        while (addr < `GOLDEN_NUM) begin
            @(negedge clk);
            if (out_valid) begin
                if (out_data !== golden_mem[addr]) begin
                        $display (
                            "Test[%d]: Error! GOLDEN=(%d), yours=(%d)", addr, golden_mem[addr], out_data);
                        error = error+1;
                end     
                else begin
                    $display("Test[%d]: Correct!", addr);
                end 
                addr = addr + 1;
            end
        end
        if(error == 0) begin
            $display("\n");
          	$display("================================= The test result is ..... PASS =================================");
          	$display("\n");
          	$display("                     *************************************************            ");
          	$display("                     **                                             **      /|____|\\");
          	$display("                     **             Congratulations !!              **    ((´-___- `))");
          	$display("                     **                                             **   ///        \\\\\\");
          	$display("                     **  All data have been generated successfully! **  /||          ||\\");
          	$display("                     **                                             **  w|\\ m      m /|w");
          	$display("                     *************************************************    \\(o)____(o)/");
          	$display("\n");
          	$display("=================================================================================================");
        end else begin
            $display("\n");
            $display("---------------------------------The test result is ..... FAIL---------------------------------\n");
          	$display("------------------------------------ Simulation stop here. ------------------------------------\n");
			$display("Total error: %d", error);
        end
        # ( 2 * `CYCLE);
        $finish;
    end

    task reset; begin
        # ( 0.25 * `CYCLE);
        rst_n = 0;    
        # ((`RST_DELAY - 0.25) * `CYCLE);
        rst_n = 1;    
    end endtask

endmodule
