module tx_logic #(
  localparam MTU = ..;
  localparam ADDRESS_SPACE = ..;
  localparam AXI_FRAME_SIZE = ..;
  localparam MAX_META_SIZE = ..;
  )
  (
  //! INPUTS
  input logic iClk, iRst;

  input logic [$clog2(AXI_FRAME_SIZE)-1:0] iSQ_DATA;
  input logic iSQ_TLAST;

  input logic [$clog2(AXI_FRAME_SIZE)-1:0] iDMA_DATA;
  input logic iDMA_TLAST;

  //! OUTPUTS
  output logic oSQ_TREADY;

  output logic [$clog2(ADDRESS_SPACE)-1:0] oDMA_ADDRESS_RANGE;
  output logic oDMA_TREADY;

  output logic [$clog2(MAX_META_SIZE)-1:0] oUDP_METADATA;
  output logic [$clog2(MTU)-1:0] oTX_DATA;
  output logic oTVALID;
  output logic oTREADY;
  output logic oTLAST;
  );

  // PROCESSES
  // 1. Send Queue reader
  // 2. Packet segmenter
  // 3. Header & Metadata resolver
  // 4. Header appender
  // **Need to synchonize the metadata and data outputs**
  //
endmodule

