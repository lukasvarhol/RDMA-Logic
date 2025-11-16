// ============================================================================
// Pure Verilog testbench - no SystemVerilog
// ============================================================================

`timescale 1ns / 1ps

module tb_tx_path_ddr_wrapper;

  // Parameters
  parameter MTU = 64;
  parameter AXI_FRAME_SIZE = 128;
  parameter CLK_PERIOD = 10;
  
  // Signals
  reg clk;
  reg rst;
  reg [31:0] cmd_src_addr;
  reg [31:0] cmd_dst_addr;
  reg [31:0] cmd_mem_length;
  reg        cmd_valid;
  wire       cmd_ready;
  wire       transfer_done;
  wire       busy;
  wire [71:0] m_axis_mm2s_cmd_tdata;
  wire        m_axis_mm2s_cmd_tvalid;
  reg         m_axis_mm2s_cmd_tready;
  reg [127:0] s_axis_mm2s_tdata;
  reg         s_axis_mm2s_tvalid;
  wire        s_axis_mm2s_tready;
  reg         s_axis_mm2s_tlast;
  wire [63:0] m_axis_tdata;
  wire        m_axis_tvalid;
  reg         m_axis_tready;
  wire        m_axis_tlast;
  reg         mm2s_rd_xfer_complete;
  
  integer cycle_count;
  
  // Clock generation
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end
  
  // DUT instantiation (without the packet_segmenter for now)
  // We'll just test the FSM and command generation
  
  // FSM states
  localparam IDLE = 2'd0;
  localparam SEND_CMD = 2'd1;
  localparam WAIT_TRANSFER = 2'd2;
  localparam DONE = 2'd3;
  
  reg [1:0] current_state, next_state;
  reg [31:0] src_addr_reg;
  reg [22:0] mem_length_reg;
  reg load_cmd;
  wire cmd_sent;
  
  // State register
  always @(posedge clk) begin
    if (rst)
      current_state <= IDLE;
    else
      current_state <= next_state;
  end
  
  // FSM logic
  always @(*) begin
    next_state = current_state;
    load_cmd = 1'b0;
    
    case (current_state)
      IDLE: begin
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
        next_state = IDLE;
      end
      
      default: next_state = IDLE;
    endcase
  end
  
  // Outputs based on state
  assign cmd_ready = (current_state == IDLE);
  assign transfer_done = (current_state == DONE);
  assign busy = (current_state != IDLE);
  
  // Load command
  always @(posedge clk) begin
    if (rst) begin
      src_addr_reg <= 32'h0;
      mem_length_reg <= 23'h0;
    end else if (load_cmd) begin
      src_addr_reg <= cmd_src_addr;
      mem_length_reg <= cmd_mem_length[22:0];
    end
  end
  
  // Command generation
  assign m_axis_mm2s_cmd_tdata = {
    8'h00,
    src_addr_reg,
    1'b0,
    1'b1,
    6'h00,
    1'b1,
    mem_length_reg
  };
  
  assign m_axis_mm2s_cmd_tvalid = (current_state == SEND_CMD);
  assign cmd_sent = m_axis_mm2s_cmd_tvalid && m_axis_mm2s_cmd_tready;
  
  // For now, just connect segmenter signals directly
  assign s_axis_mm2s_tready = m_axis_tready;
  assign m_axis_tdata = s_axis_mm2s_tdata[63:0];
  assign m_axis_tvalid = s_axis_mm2s_tvalid;
  assign m_axis_tlast = s_axis_mm2s_tlast;
  
  // Cycle counter
  always @(posedge clk) begin
    if (rst)
      cycle_count = 0;
    else
      cycle_count = cycle_count + 1;
      
    if (cycle_count < 50) begin
      $display("[Cycle %3d, Time %0t] State=%0d cmd_ready=%0b cmd_valid=%0b busy=%0b cmd_sent=%0b", 
               cycle_count, $time, current_state, cmd_ready, cmd_valid, busy, cmd_sent);
    end
  end
  
  // Test stimulus
  initial begin
    $display("\n=== Starting Pure Verilog Test ===\n");
    
    // Initialize
    rst = 1;
    cmd_valid = 0;
    cmd_src_addr = 0;
    cmd_dst_addr = 0;
    cmd_mem_length = 0;
    m_axis_mm2s_cmd_tready = 0;
    s_axis_mm2s_tdata = 0;
    s_axis_mm2s_tvalid = 0;
    s_axis_mm2s_tlast = 0;
    m_axis_tready = 1;
    mm2s_rd_xfer_complete = 0;
    cycle_count = 0;
    
    // Reset
    #100;
    $display("[%0t] Releasing reset", $time);
    rst = 0;
    
    #50;
    $display("[%0t] Sending command", $time);
    cmd_src_addr = 32'h1000_0000;
    cmd_dst_addr = 32'h2000_0000;
    cmd_mem_length = 64;
    cmd_valid = 1;
    
    #20;
    cmd_valid = 0;
    $display("[%0t] Command valid deasserted", $time);
    
    // Accept MM2S command
    #50;
    $display("[%0t] Accepting MM2S command", $time);
    m_axis_mm2s_cmd_tready = 1;
    #20;
    m_axis_mm2s_cmd_tready = 0;
    
    // Send data
    #50;
    $display("[%0t] Sending data", $time);
    s_axis_mm2s_tdata = 128'hDEADBEEFCAFEBABE;
    s_axis_mm2s_tvalid = 1;
    s_axis_mm2s_tlast = 1;
    #20;
    s_axis_mm2s_tvalid = 0;
    s_axis_mm2s_tlast = 0;
    
    // Complete transfer
    #50;
    $display("[%0t] Completing transfer", $time);
    mm2s_rd_xfer_complete = 1;
    #20;
    mm2s_rd_xfer_complete = 0;
    
    #100;
    
    $display("\n=== Test Complete ===\n");
    $display("Final state: %0d (0=IDLE, 1=SEND_CMD, 2=WAIT, 3=DONE)", current_state);
    $display("Transfer done: %0b", transfer_done);
    
    $finish;
  end
  
  // Timeout
  initial begin
    #5000;
    $display("\n=== TIMEOUT ===\n");
    $finish;
  end

endmodule