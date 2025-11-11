module packet_segmenter #(
  parameter MTU = 64,
  parameter AXI_FRAME_SIZE = 128
  )
  (
  //! INPUTS
  input logic clk, rst,
  input logic [AXI_FRAME_SIZE-1:0] s_axis_tdata,
  input logic s_axis_tvalid,
  input logic s_axis_tready,

  //! OUTPUTS
  output logic [MTU-1:0] m_axis_tdata,
  output logic m_axis_tvalid,
  output logic m_axis_tready
  );

  // HELPER FUNCTIONS

  //Greatest Common Divisor
  function automatic int gcd(input int a, input int b);
    while (b != 0) begin
      int temp = b;
      b = a % b;
      a = temp;
    end
    return a;
  endfunction

  //Lowest Common Multiple
  function automatic int lcm(input int a, input int b);
    if (a == 0 || b == 0)
      return 0;
    else 
      return (a / gcd(a, b)) * b;
  endfunction

    generate 
    if (MTU == AXI_FRAME_SIZE) begin : BUFFER_BYPASS
      assign m_axis_tdata = s_axis_tdata;
      assign m_axis_tvalid = s_axis_tvalid;
      assign m_axis_tready = s_axis_tready;
    end else begin : BUFFER_PATH
      // INTERNAL VARIABLES
      localparam int LCM = lcm(AXI_FRAME_SIZE, MTU);
      logic [LCM-1:0]                        buffer;
      logic [$clog2(LCM/AXI_FRAME_SIZE)-1:0] write_ptr;  
      logic [$clog2(LCM/MTU)-1:0]            read_ptr;
      logic [$clog2(LCM):0]                  bits_stored;
            
      // PROCESSES
      always_ff @(posedge clk) begin
        if (rst) begin
          write_ptr <= '0;
          read_ptr <= LCM/MTU - 1;
          bits_stored <= '0;
        end

        case ({(m_axis_tvalid), (s_axis_tready && s_axis_tvalid && m_axis_tready)})
        //[0]: write, [1]: read
          2'b01: begin 
            bits_stored <= bits_stored + AXI_FRAME_SIZE; // write only 
            write_ptr <= (write_ptr >= LCM/AXI_FRAME_SIZE - 1) ? 0 : write_ptr + 1;
          end
          2'b10: begin 
            bits_stored <= bits_stored - MTU; // read only 
            read_ptr <= (read_ptr <= 0) ? (LCM/MTU - 1) : read_ptr - 1; //bigendian
          end
          2'b11: begin 
            bits_stored <= bits_stored + AXI_FRAME_SIZE - MTU; // read & write
            write_ptr <= (write_ptr >= LCM/AXI_FRAME_SIZE - 1) ? 0 : write_ptr + 1;
            read_ptr <= (read_ptr <= 0) ? (LCM/MTU - 1) : read_ptr - 1; 
          end
        endcase

        if (s_axis_tready && s_axis_tvalid && m_axis_tready) begin
         // write to buffer 
          buffer[write_ptr * AXI_FRAME_SIZE +: AXI_FRAME_SIZE] <= s_axis_tdata;
        end

      end

      assign m_axis_tready = (bits_stored + AXI_FRAME_SIZE) <= LCM;
      assign m_axis_tdata = buffer[read_ptr * MTU +: MTU] & {MTU{m_axis_tvalid}}; //zero if no new data to output
      assign m_axis_tvalid = (bits_stored>=MTU);

    end
  endgenerate 
endmodule
