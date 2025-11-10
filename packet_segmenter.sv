module packet_segmenter #(
  parameter MTU = 64,
  parameter AXI_FRAME_SIZE = 128
  )
  (
  //! INPUTS
  input logic iClk, iRst,
  input logic [AXI_FRAME_SIZE-1:0] iDMA_DATA,
  input logic iVALID,
  input logic iREADY,

  //! OUTPUTS
  output logic [MTU-1:0] oDATA_PACKET,
  output logic oVALID,
  output logic oREADY
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
      assign oDATA_PACKET = iDMA_DATA;
      assign oVALID = iVALID;
      assign oREADY = iREADY;
    end else begin : BUFFER_PATH
      // INTERNAL VARIABLES
      localparam int LCM = lcm(AXI_FRAME_SIZE, MTU);
      logic [LCM-1:0] buffer;
      logic [$clog2(LCM/AXI_FRAME_SIZE)-1:0] write_ptr;  
      logic [$clog2(LCM/MTU)-1:0] read_ptr;
      logic [$clog2(LCM):0] bits_available;
      
      // PROCESSES
      always_ff @(posedge iClk) begin
        if (iRst) begin
          buffer <= '0;
          write_ptr <= '0;
          read_ptr <= '0;
          bits_available <= '0;
          oDATA_PACKET <= '0;
          oVALID <= '0;
        end

        else begin
          if (oREADY && iVALID) begin
            // write to buffer 
            buffer[write_ptr * AXI_FRAME_SIZE +: AXI_FRAME_SIZE] <= iDMA_DATA;
            write_ptr <= (write_ptr + 1 >= LCM/AXI_FRAME_SIZE) ? 0 : write_ptr + 1;
          end 

          if (bits_available >= MTU && iREADY) begin
            // read from buffer
            oDATA_PACKET <= buffer[read_ptr * MTU +: MTU];
            oVALID <= 1;
            read_ptr <= (read_ptr + 1 >= LCM/MTU) ? 0 : write_ptr + 1;
          end else begin
            oDATA_PACKET <= 0;
            oVALID <= 0;
          end
          
          if ((oREADY && iVALID) && (bits_available >= MTU && iREADY)) begin
          // Both write and read
            bits_available <= bits_available + AXI_FRAME_SIZE - MTU;
          end
          else if (oREADY && iVALID) begin
          // Only write
            bits_available <= bits_available + AXI_FRAME_SIZE;
          end
          else if (bits_available >= MTU && iREADY) begin
          // Only read
            bits_available <= bits_available - MTU;
          end
        end
      end
      assign oREADY = (bits_available + AXI_FRAME_SIZE) <= LCM;
    end
  endgenerate 
endmodule
