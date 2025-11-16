module tx_path_ddr_wrapper #(
  parameter MTU = 64,
  parameter AXI_FRAME_SIZE = 128,
  parameter SRC_ADDRESS_SIZE = 32,
  parameter DST_ADDRESS_SIZE = 32,
  parameter MEM_LENGTH_SIZE = 32 
  )
  (
  //! INPUT/OUTPUT
  input logic clk, 
  input logic rst,
  
  input  logic [SRC_ADDRESS_SIZE-1:0]  cmd_src_addr,
  input  logic [DST_ADDRESS_SIZE-1:0]  cmd_dst_addr,
  input  logic [MEM_LENGTH_SIZE-1:0]   cmd_mem_length,
  input  logic                         cmd_valid,
  output logic                         cmd_ready,
  output logic                         transfer_done,
  output logic                         busy,
  
  output logic [71:0] m_axis_mm2s_cmd_tdata,
  output logic        m_axis_mm2s_cmd_tvalid,
  input  logic        m_axis_mm2s_cmd_tready,    
  
  input  logic [AXI_FRAME_SIZE-1:0] s_axis_mm2s_tdata, 
  input  logic                      s_axis_mm2s_tvalid, 
  output logic                      s_axis_mm2s_tready,  
  input  logic                      s_axis_mm2s_tlast,   
  
  // Segmented output (to next stage)
  output logic [MTU-1:0] m_axis_tdata,
  output logic           m_axis_tvalid,
  input  logic           m_axis_tready,
  output logic           m_axis_tlast,
  
  input logic mm2s_rd_xfer_complete
  );
  
  typedef enum logic [1:0] {
    IDLE,
    SEND_CMD,
    WAIT_TRANSFER,
    DONE
  } state_t;
  
  state_t current_state, next_state;
  
  logic [SRC_ADDRESS_SIZE-1:0] src_addr_reg;
  logic [22:0]                 mem_length_reg;  

  logic load_cmd;
  logic cmd_sent;
  
  always_ff @(posedge clk) begin
    if (rst) 
      current_state <= IDLE;
    else 
      current_state <= next_state;
  end
  
  // FSM logic
  always_comb begin 
    next_state = current_state;
    load_cmd = 1'b0;
    cmd_ready = 1'b0;
    transfer_done = 1'b0;
    busy = 1'b1;
    
    case (current_state)
      IDLE: begin
        busy = 1'b0;
        cmd_ready = 1'b1;
        if (cmd_valid) begin
          load_cmd = 1'b1;
          next_state = SEND_CMD;
        end
      end
      
      SEND_CMD: begin 
        if (cmd_sent) 
          next_state = WAIT_TRANSFER;
      end
      
      WAIT_TRANSFER: begin 
        if (mm2s_rd_xfer_complete)
          next_state = DONE;
      end
      
      DONE: begin 
        transfer_done = 1'b1;
        next_state = IDLE;
      end
      
      default: next_state = IDLE;
    endcase 
  end
  
  // Load command from submit queue 
  always_ff @(posedge clk) begin
    if (rst) begin 
      src_addr_reg <= '0;
      mem_length_reg <= '0;
    end else if (load_cmd) begin 
      src_addr_reg <= cmd_src_addr;
      // Ensure length fits in 23 bits (max 8MB-1)
      mem_length_reg <= cmd_mem_length[22:0];
    end 
  end 
  
  // AXI Data Mover MM2S Command Generation 
  // Command format:
  // [71:64] - Reserved (8 bits)
  // [63:32] - Start address (32 bits)
  // [31]    - DRR (0 = increment address)
  // [30]    - EOF (1 = end of frame)
  // [29:24] - Reserved (6 bits)
  // [23]    - Type (1 = fixed increment)
  // [22:0]  - BTT (bytes to transfer, max 8MB - 1)
  
  assign m_axis_mm2s_cmd_tdata = {
    8'h00,              // Reserved
    src_addr_reg,       // Source address in DDR
    1'b0,               // DRR - increment address
    1'b1,               // EOF - end of frame
    6'h00,              // Reserved
    1'b1,               // Type - fixed increment
    mem_length_reg      // Bytes to transfer
  };
  
  assign m_axis_mm2s_cmd_tvalid = (current_state == SEND_CMD);
  assign cmd_sent = m_axis_mm2s_cmd_tvalid && m_axis_mm2s_cmd_tready;
  
  packet_segmenter #(
    .MTU(MTU), 
    .AXI_FRAME_SIZE(AXI_FRAME_SIZE)
  ) packet_seg_inst (
    .clk(clk), 
    .rst(rst),
    // Input from Data Mover MM2S (DDR read data)
    .s_axis_tdata(s_axis_mm2s_tdata),
    .s_axis_tvalid(s_axis_mm2s_tvalid),
    .s_axis_tready(s_axis_mm2s_tready),
    .s_axis_tlast(s_axis_mm2s_tlast),
    // Segmented output
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast)
  );
  
endmodule
