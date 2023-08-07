
module core (                       //Don't modify interface
	input         i_clk,
	input         i_rst_n,
	input         i_op_valid,
	input  [ 3:0] i_op_mode,
    output        o_op_ready,
	input         i_in_valid,
	input  [ 7:0] i_in_data,
	output        o_in_ready,
	output        o_out_valid,
	output [ 7:0] o_out_data
);
//==== STATE Declaration =======
    parameter IDLE   = 4'b0000;
    parameter LOAD_DATA   = 4'B0001;
    parameter SHIFT  = 4'b0010; //left,right,up,down,shift
    parameter KERNAL_SIZE  = 4'B0011; //kernal size up/sown
    parameter KERNAL_RETURN   = 4'b0100; //max,min,median,blur of kernal
    parameter RECORD_POSITION = 4'b0101;
	parameter DISPLAY_TRIANGLE = 4'b0110;
	parameter DISPLAY_1 = 4'b0111; //display 1 value
	parameter DISPLAY_2 = 4'b1000; //display many point
	parameter LOAD_OP = 4'b1001;
// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------

	reg  [7:0] matrix[15:0][15:0],next_matrix[15:0][15:0]; //store the 16*16 image data
	reg  [3:0] opmode,next_opmode,new_opmode;
	reg  [7:0] index,next_index; //count index for load operation
	reg  [7:0] new_data; //new in input image data
	reg  [3:0] state,next_state;
	integer k,j;
	reg  [3:0] origin_x,next_origin_x; //store the point of origin , initially (0,0)
	reg  [3:0] origin_y,next_origin_y;
	reg  [7:0] max1, mid1, min1, max2, mid2, min2, max3, mid3, min3, min_max, mid_mid, max_min; //used for median
	reg        kernal,next_kernal; //0:dense kernal 1:sparse kernal ,default=0
	reg  [7:0] temp,next_temp; //store the result of max,min,med,blur
	reg  [3:0] left,right,up,down; // handle index of kernal

	//reg  [7:0] kernal_v[8:0];// store 9 value of kernal

// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------

	assign o_op_ready = (state == IDLE)? 1:0;
	assign o_in_ready = (state == LOAD_DATA)? 1:0;
	assign o_out_valid = (state == DISPLAY_1)? 1:0;
	assign o_out_data = (state == DISPLAY_1)? temp:0;

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------

	always @(*) begin
		next_opmode = opmode;
		next_index = index;
		next_origin_x = origin_x;
		next_origin_y = origin_y;
		next_kernal = kernal;
		next_temp = temp;
		for(k=0;k<16;k=k+1) begin
			for(j=0;j<16;j=j+1)
			next_matrix[k][j] = matrix[k][j];
		end
		case(state)
		IDLE: begin //IDLE:set o_op_ready to high (wait 1 cycle to read next operation)
			next_index = 0;
			next_temp = 0;
			next_state = (i_op_valid)? LOAD_OP:IDLE;
		end
		LOAD_OP: begin
			next_opmode = new_opmode;
			case(next_opmode)
				4'b0000: next_state = LOAD_DATA;
				4'b0001: next_state = SHIFT;
				4'b0010: next_state = SHIFT;
				4'b0011: next_state = SHIFT;
				4'b0100: next_state = SHIFT;
				4'b0101: next_state = KERNAL_SIZE;
				4'b0110: next_state = KERNAL_SIZE;
				4'b0111: next_state = KERNAL_RETURN;
				4'b1000: next_state = KERNAL_RETURN;
				4'b1001: next_state = KERNAL_RETURN;
				4'b1010: next_state = KERNAL_RETURN;
				default: next_state = IDLE;

			endcase
		end
		LOAD_DATA: begin
			if(index < 255) begin
				next_matrix[index >> 4][index[3:0]] = new_data;
				next_state = LOAD_DATA;
			end
			else begin //LAST ONE DATA
				next_matrix[15][15] = new_data;
				next_state = IDLE;
			end
			next_index = index + 1;
		end
		SHIFT: begin
			next_state = IDLE;
			case(opmode)
				//right shift
				4'b0001: begin
					if(origin_y == 15) next_origin_y = origin_y; //out of scale
					else next_origin_y = origin_y+1;
				end
				//left shift
				4'b0010: begin
					if(origin_y == 0) next_origin_y = origin_y; //out of scale
					else next_origin_y = origin_y-1;
				end
				//up shift
				4'b0011: begin
					if(origin_x == 0) next_origin_x = origin_x; //out of scale
					else next_origin_x = origin_x-1;
				end
				//down shift
				4'b0100: begin
					if(origin_x == 15) next_origin_x = origin_x; //out of scale
					else next_origin_x = origin_x+1;
				end
			endcase
		end
		KERNAL_SIZE: begin
			next_state = IDLE;
			next_kernal = (opmode == 4'b0101)? 1:0;
			// 4'b0101: kernal size up
			// 4'b0110: kernal size down
		end
		KERNAL_RETURN: begin
			left = (origin_y < (1 + kernal))? 0 : origin_y-1-kernal; //check if left side out of scale
			right = (origin_y > (14-kernal))? 15 : origin_y + 1 + kernal; //right side out of scale
			up = (origin_x < (1 + kernal))? 0 : origin_x-1-kernal; //up side out of scale
			down = (origin_x  > (14-kernal))? 15 : origin_x + 1 + kernal; //down side out of scale
			/*index of kernal
			 (up,left)         ||  (up,origin_y)        ||   (up,right)
			 ==================================================================
			 (origin_x,left)   ||  (origin_x,origin_y)  ||   (origin_x,right)
			 ==================================================================
			 (down,left)       ||  (down,origin_y)      ||   (down,right)
			 */
			 /*
			kernal_v[0]=matrix[up][left];
			kernal_v[1]=matrix[up][origin_y];
			kernal_v[2]=matrix[up][right];
			kernal_v[3]=matrix[origin_x][left];
			kernal_v[4]=matrix[origin_x][origin_y];
			kernal_v[5]=matrix[origin_x][right];
			kernal_v[6]=matrix[down][left];
			kernal_v[7]=matrix[down][origin_y];
			kernal_v[8]=matrix[down][right];
			*/
			case(opmode)
				//max in kernal
				4'b0111: begin
					next_temp = matrix[origin_x][origin_y];
					next_temp = (matrix[up][left]>next_temp)? matrix[up][left] : next_temp;
					next_temp = (matrix[up][origin_y]>next_temp)? matrix[up][origin_y]: next_temp;
					next_temp = (matrix[up][right]>next_temp)? matrix[up][right]: next_temp;
					next_temp = (matrix[origin_x][left]>next_temp)? matrix[origin_x][left] : next_temp;
					next_temp = (matrix[origin_x][right]>next_temp)? matrix[origin_x][right]: next_temp;
					next_temp = (matrix[down][left]>next_temp)? matrix[down][left] : next_temp;
					next_temp = (matrix[down][origin_y]>next_temp)? matrix[down][origin_y] : next_temp;
					next_temp = (matrix[down][right]>next_temp)? matrix[down][right] : next_temp;
				end
				//min in kernal
				4'b1000: begin
					next_temp = matrix[origin_x][origin_y];
					next_temp = (matrix[up][left]<next_temp)? matrix[up][left] : next_temp;
					next_temp = (matrix[up][origin_y]<next_temp)? matrix[up][origin_y]: next_temp;
					next_temp = (matrix[up][right]<next_temp)? matrix[up][right]: next_temp;
					next_temp = (matrix[origin_x][left]<next_temp)? matrix[origin_x][left] : next_temp;
					next_temp = (matrix[origin_x][right]<next_temp)? matrix[origin_x][right]: next_temp;
					next_temp = (matrix[down][left]<next_temp)? matrix[down][left] : next_temp;
					next_temp = (matrix[down][origin_y]<next_temp)? matrix[down][origin_y] : next_temp;
					next_temp = (matrix[down][right]<next_temp)? matrix[down][right] : next_temp;
				end
				//median in kernal
				4'b1001: begin
					//upper row
					if(matrix[up][left]>=matrix[up][origin_y]) begin
						if(matrix[up][left]>=matrix[up][right]) begin
							max1 = matrix[up][left];
							if(matrix[up][origin_y]>=matrix[up][right]) begin
								mid1 = matrix[up][origin_y];
								min1 = matrix[up][right];
							end
							else begin
								mid1 = matrix[up][right];
								min1 = matrix[up][origin_y];
							end
						end
						else begin
							max1 = matrix[up][right];
							mid1 = matrix[up][left];
							min1 = matrix[up][origin_y];
						end
					end
					else begin
						if(matrix[up][left]>=matrix[up][right]) begin
							max1 = matrix[up][origin_y];
							mid1 = matrix[up][left];
							min1 = matrix[up][right];
						end
						else begin
							min1 = matrix[up][left];
							if(matrix[up][origin_y]>=matrix[up][right]) begin
								max1 = matrix[up][origin_y];
								mid1 = matrix[up][right];
							end
							else begin
								max1 = matrix[up][right];
								mid1 = matrix[up][origin_y];
							end
						end
					end
					//middle row
					if(matrix[origin_x][left]>=matrix[origin_x][origin_y]) begin
						if(matrix[origin_x][left]>=matrix[origin_x][right]) begin
							max2 = matrix[origin_x][left];
							if(matrix[origin_x][origin_y]>=matrix[origin_x][right]) begin
								mid2 = matrix[origin_x][origin_y];
								min2 = matrix[origin_x][right];
							end
							else begin
								mid2 = matrix[origin_x][right];
								min2 = matrix[origin_x][origin_y];
							end
						end
						else begin
							max2 = matrix[origin_x][right];
							mid2 = matrix[origin_x][left];
							min2 = matrix[origin_x][origin_y];
						end
					end
					else begin
						if(matrix[origin_x][left]>=matrix[origin_x][right]) begin
							max2 = matrix[origin_x][origin_y];
							mid2 = matrix[origin_x][left];
							min2 = matrix[origin_x][right];
						end
						else begin
							min2 = matrix[origin_x][left];
							if(matrix[origin_x][origin_y]>=matrix[origin_x][right]) begin
								max2 = matrix[origin_x][origin_y];
								mid2 = matrix[origin_x][right];
							end
							else begin
								max2 = matrix[origin_x][right];
								mid2 = matrix[origin_x][origin_y];
							end
						end
					end
					//bottom row
					if(matrix[down][left]>=matrix[down][origin_y]) begin
						if(matrix[down][left]>=matrix[down][right]) begin
							max3 = matrix[down][left];
							if(matrix[down][origin_y]>=matrix[down][right]) begin
								mid3 = matrix[down][origin_y];
								min3 = matrix[down][right];
							end
							else begin
								mid3 = matrix[down][right];
								min3 = matrix[down][origin_y];
							end
						end
						else begin
							max3 = matrix[down][right];
							mid3 = matrix[down][left];
							min3 = matrix[down][origin_y];
						end
					end
					else begin
						if(matrix[down][left]>=matrix[down][right]) begin
							max3 = matrix[down][origin_y];
							mid3 = matrix[down][left];
							min3 = matrix[down][right];
						end
						else begin
							min3 = matrix[down][left];
							if(matrix[down][origin_y]>=matrix[down][right]) begin
								max3 = matrix[down][origin_y];
								mid3 = matrix[down][right];
							end
							else begin
								max3 = matrix[down][right];
								mid3 = matrix[down][origin_y];
							end
						end
					end
					// find max_min, mid_mid, min_max
					min_max = max1;
					min_max = (min_max<max2) ? min_max : max2;
					min_max = (min_max<max3) ? min_max : max3;

					if((mid1 >= mid2 && mid1 <= mid3) || (mid1 >= mid3 && mid1 <= mid2))	mid_mid = mid1;
					else if((mid2 >= mid1 && mid2 <= mid3) || (mid2 >= mid3 && mid2 <= mid1))	mid_mid = mid2;
					else mid_mid = mid3;

					max_min = min1;
					max_min = (max_min>min2) ? max_min : min2;
					max_min = (max_min>min3) ? max_min : min3;

					if((min_max >= mid_mid && min_max <= max_min) || (min_max >= max_min && min_max <= mid_mid))	next_temp = min_max;
					else if((mid_mid >= min_max && mid_mid <= max_min) || (mid_mid >= max_min && mid_mid <= min_max))	next_temp = mid_mid;
					else next_temp = max_min;
				end
				//blur in kernal
				4'b1010: begin
					//max1只是借個變數存，計算被捨去的數
					max1 = (matrix[up][left][3:0]+matrix[up][right][3:0]+matrix[down][left][3:0]+matrix[down][right][3:0]+{matrix[up][origin_y][2:0],1'b0}+{matrix[origin_x][left][2:0],1'b0}+{matrix[origin_x][right][2:0],1'b0}+{matrix[down][origin_y][2:0],1'b0}+{matrix[origin_x][origin_y][1:0],2'b0});
					next_temp = (matrix[up][left]>>4)+(matrix[up][origin_y]>>3)+(matrix[up][right]>>4)+(matrix[origin_x][left]>>3)+(matrix[origin_x][origin_y]>>2)+(matrix[origin_x][right]>>3)+(matrix[down][left]>>4)+(matrix[down][origin_y]>>3)+(matrix[down][right]>>4)+(max1>>4);				
					next_temp = (max1[3]==1'b1)? next_temp+1:next_temp; //五入
				end			
				endcase
			next_state = DISPLAY_1;
		end
		DISPLAY_1: begin
			next_state = IDLE;
		end
		default:next_state=IDLE;

		endcase
	end

// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
			for(k=0;k<16;k=k+1) begin
				for(j=0;j<16;j=j+1)
				matrix[k][j] <= 8'b0;
			end
			state <= IDLE;
			origin_x <= 0;
			origin_y <= 0;
			kernal <= 0;
			temp <= 0;
        end
        else begin
			//state
			state <= next_state;
			//load  data
			index <= next_index;
			new_data <= i_in_data;   //input buffer
			for(k=0;k<16;k=k+1) begin
				for(j=0;j<16;j=j+1)
				matrix[k][j] <= next_matrix[k][j];
			end
			//opmode
			new_opmode <= i_op_mode; //input buffer
			opmode <= next_opmode;
			//origin
			origin_x <= next_origin_x;
			origin_y <= next_origin_y;
			//kernal type
			kernal <= next_kernal;
			//kernal return
			temp <= next_temp;

        end
    end

endmodule
