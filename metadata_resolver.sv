module metadata_resolver #(
  localparam AXI_FRAME_SIZE = ..;
  localparam RDMA_HEADER_SIZE = ..;
  localparam METADATA_FRAME_SIZE = ..;
  localparam SRC_ADDRESS_SIZE = ..;
  localparam DST_ADDRESS_SIZE = ..;
  localparam MEM_LENGTH = ..;
  )
  (
  //! INPUTS
  input logic clk, rst,
  input logic s_axis_tready, s_axis_tvalid,
  input logic [AXI_FRAME_SIZE-1:0] s_axis_tdata,

  //! OUTPUTS
  output logic m_axis_tready, m_axis_tvalid,
  output logic [METADATA_FRAME_SIZE-1:0] oMetadata
  );

  initial begin
  assert (DST_ADDRESS_SIZE <= AXI_FRAME_SIZE)
    else $error("SRC_ADDRESS_SIZE larger than maximum AXI transfer size");
  assert (SRC_ADDRESS_SIZE <= AXI_FRAME_SIZE)
    else $error("DST_ADDRESS_SIZE larger than maximum AXI transfer size");
  assert (MEM_LENGTH <= AXI_FRAME_SIZE)
    else $error("MEM_LENGTH larger than maxium AXI transfer size");
  end

  generate 
  if (SRC_ADDRESS_SIZE+DST_ADDRESS_SIZE+MEM_LENGTH <= AXI_FRAME_SIZE) begin : BUFFER_BYPASS
    always_ff @(posedge clk) begin 
      if (rst)
        oMetadata <= '0;
      else if (s_axis_tready && s_axis_tvalid) 
        oMetadata[8+DST_ADDRESS_SIZE+DST_ADDRESS_SIZE+MEM_LENGTH+8:0] <=
                    {'hFAFA,
                    s_axis_tdata[0 +: SRC_ADDRESS_SIZE],
                    s_axis_tdata[SRC_ADDRESS_SIZE +: DST_ADDRESS_SIZE],
                    s_axis_tdata[(SRC_ADDRESS_SIZE + DST_ADDRESS_SIZE) +: MEM_LENGTH],
                    'hFEFE};
    end
  end : BUFFER_BYPASS
  else begin : BUFFER 
    logic [SRC_ADDRESS_SIZE-1:0] src_address_buf;
    logic [DST_ADDRESS_SIZE-1:0] dst_address_buf;
    logic [MEM_LENGTH-1:0] memory_length_buf;

    logic [SRC_ADDRESS_SIZE-1:0] src_address_bits_received;
    logic [DST_ADDRESS_SIZE-1:0] dst_address_bits_received;
    logic [MEM_LENGTH-1:0] mem_length_bits_received;

    typedef enum logic [1:0] {
      RECEIVING_SRC = 2'b00,
      RECEIVING_DST = 2'b01,
      RECEIVING_MEM = 2'b10,
      COMPLETE = 2'b11
    } state_t;

    state_t current_state, next_state;
    
    logic [AXI_FRAME_SIZE-1:0] bits_to_take;
    logic [AXI_FRAME_SIZE-1:0] bits_remaining_in_field;

    always_ff (posedge clk) begin
      current_state <= next_state;
      if (rst) begin
        current_state <=RECEIVING_SRC;
        next_state <= RECEIVING_SRC;
        src_address_bits_received <= '0;
        dst_address_bits_received <= '0;
        mem_length_bits_received <= '0;
      end
      else if (s_axis_tready && s_axis_tvalid) begin
        case (current_state)
          RECEIVING_SRC: begin
            bits_remaining_in_field <= SRC_ADDRESS_SIZE - src_address_bits_received;

            bits_to_take <= (bits_remaining_in_field < AXI_FRAME_SIZE)? bits_remaining_in_field : AXI_FRAME_SIZE;

            src_address_buf <= (src_address_buf << bits_to_take) | s_axis_tdata[bits_to_take-1:0];

            src_address_bits_received <= src_address_bits_received + bits_to_take;

            if (src_address_bits_received + bits_to_take >= SRC_ADDRESS_SIZE)
              next_state <= RECEIVING_DST;
            else 
              next_state <= RECEIVING_SRC;
          end

          RECEIVING_DST: begin 
            bits_remaining_in_field <= DST_ADDRESS_SIZE - dst_address_bits_received;

            bits_to_take <= (bits_remaining_in_field < AXI_FRAME_SIZE)? bits_remaining_in_field : AXI_FRAME_SIZE;

            dst_address_buf <= (dst_address_buf << bits_to_take) | s_axis_tdata[bits_to_take-1:0];

            dst_address_bits_received <= dst_address_bits_received + bits_to_take;

            if(dst_address_bits_received + bits_to_take >= DST_ADDRESS_SIZE)
              next_state <= RECEIVING_MEM;
            else
              next_state <= RECEIVING_DST;
          end 

          RECEIVING_MEM: begin 
            bits_remaining_in_field <=MEM_LENGTH - mem_length_bits_received;

            bits_to_take <= (bits_remaining_in_field < AXI_FRAME_SIZE) ? bits_remaining_in_field : AXI_FRAME_SIZE;

            memory_length_buf <= (memory_length_buf << bits_to_take) | s_axis_tdata[bits_to_take-1:0];

            mem_length_bits_received <= mem_length_bits_received + bits_to_take;

            if(mem_length_bits_received + bits_to_take >= DST_ADDRESS_SIZE)
              next_state <=COMPLETE;
            else 
              next_state <= RECEIVING_MEM;
          end

          COMPLETE: begin
            oMetadata[8+DST_ADDRESS_SIZE+DST_ADDRESS_SIZE+MEM_LENGTH+8:0] <=
                  {'hFAFA,
                  src_address_buf,
                  dst_address_buf,
                  memory_length_buf,
                  'hFEFE};
            m_axis_tvalid <= '1;
            next_state <= RECEIVING_SRC;
          end
      end
    end 
  end : BUFFER
  endgenerate 
  endmodule;
