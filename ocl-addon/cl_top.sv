// ============================================================================
// Amazon FPGA Hardware Development Kit
//
// Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Amazon Software License (the "License"). You may not use
// this file except in compliance with the License. A copy of the License is
// located at
//
//    http://aws.amazon.com/asl/
//
// or in the "license" file accompanying this file. This file is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
// implied. See the License for the specific language governing permissions and
// limitations under the License.
// ============================================================================

//====================================================================================
// Top level module file for cl_top - Simple Add-One Example
//====================================================================================

module cl_top
    #(
      parameter EN_DDR = 0,
      parameter EN_HBM = 0
    )
    (
      `include "cl_ports.vh"
    );

`include "cl_id_defines.vh" // CL ID defines required for all examples
`include "cl_top_defines.vh"

//=============================================================================
// GLOBALS
//=============================================================================

  logic rst_main_n_sync;  
  logic pre_sync_rst_n;

  always_comb begin
     cl_sh_flr_done    = 'b1;
     cl_sh_status0     = 'b0;
     cl_sh_status1     = 'b0;
     cl_sh_status2     = 'b0;
     cl_sh_id0         = `CL_SH_ID0;
     cl_sh_id1         = `CL_SH_ID1;
     cl_sh_status_vled = 'b0;
     cl_sh_dma_wr_full = 'b0;
     cl_sh_dma_rd_full = 'b0;
  end

always @(posedge clk_main_a0)
    if (!rst_main_n)
    begin
        pre_sync_rst_n  <= 0;
        rst_main_n_sync <= 0;
    end
    else
    begin
        pre_sync_rst_n  <= 1;
        rst_main_n_sync <= pre_sync_rst_n;
    end

//=============================================================================
// PCIM
//=============================================================================

  // Cause Protocol Violations
  always_comb begin
    cl_sh_pcim_awaddr  = 'b0;
    cl_sh_pcim_awsize  = 'b0;
    cl_sh_pcim_awburst = 'b0;
    cl_sh_pcim_awvalid = 'b0;

    cl_sh_pcim_wdata   = 'b0;
    cl_sh_pcim_wstrb   = 'b0;
    cl_sh_pcim_wlast   = 'b0;
    cl_sh_pcim_wvalid  = 'b0;

    cl_sh_pcim_araddr  = 'b0;
    cl_sh_pcim_arsize  = 'b0;
    cl_sh_pcim_arburst = 'b0;
    cl_sh_pcim_arvalid = 'b0;
  end

  // Remaining CL Output Ports
  always_comb begin
    cl_sh_pcim_awid    = 'b0;
    cl_sh_pcim_awlen   = 'b0;
    cl_sh_pcim_awcache = 'b0;
    cl_sh_pcim_awlock  = 'b0;
    cl_sh_pcim_awprot  = 'b0;
    cl_sh_pcim_awqos   = 'b0;
    cl_sh_pcim_awuser  = 'b0;

    cl_sh_pcim_wid     = 'b0;
    cl_sh_pcim_wuser   = 'b0;

    cl_sh_pcim_arid    = 'b0;
    cl_sh_pcim_arlen   = 'b0;
    cl_sh_pcim_arcache = 'b0;
    cl_sh_pcim_arlock  = 'b0;
    cl_sh_pcim_arprot  = 'b0;
    cl_sh_pcim_arqos   = 'b0;
    cl_sh_pcim_aruser  = 'b0;

    cl_sh_pcim_rready  = 'b0;
  end

//=============================================================================
// PCIS
//=============================================================================

  // Cause Protocol Violations
  always_comb begin
    cl_sh_dma_pcis_bresp   = 'b0;
    cl_sh_dma_pcis_rresp   = 'b0;
    cl_sh_dma_pcis_rvalid  = 'b0;
  end

  // Remaining CL Output Ports
  always_comb begin
    cl_sh_dma_pcis_awready = 'b0;

    cl_sh_dma_pcis_wready  = 'b0;

    cl_sh_dma_pcis_bid     = 'b0;
    cl_sh_dma_pcis_bvalid  = 'b0;

    cl_sh_dma_pcis_arready  = 'b0;

    cl_sh_dma_pcis_rid     = 'b0;
    cl_sh_dma_pcis_rdata   = 'b0;
    cl_sh_dma_pcis_rlast   = 'b0;
    cl_sh_dma_pcis_ruser   = 'b0;
  end

//=============================================================================
// OCL - Simple Add-One Implementation
//=============================================================================

  localparam ADDR_WIDTH = 8;
  localparam NUM_REGS = 8;  // Simple: 8 input + 8 output registers
  
  // Register map for Simple Add-One
  // 0x00-0x1C: Input data registers (8 × 32-bit)
  // 0x20-0x3C: Output data registers (8 × 32-bit)
  // 0x40: Control register (bit 0: start)
  // 0x44: Status register (bit 0: done)
  
  logic [31:0] input_regs [0:NUM_REGS-1];   // 8 × 32-bit input registers
  logic [31:0] output_regs [0:NUM_REGS-1];  // 8 × 32-bit output registers
  logic [31:0] control_reg;
  logic [31:0] status_reg;
  
  // Simple Add-One logic
  logic [3:0] add_counter;
  logic       add_computing;
  logic       add_done;
  logic       add_start;
  
  assign add_start = control_reg[0];
  
  // Add-One state machine
  always_ff @(posedge clk_main_a0) begin
    if (!rst_main_n_sync) begin
      add_counter <= 4'h0;
      add_computing <= 1'b0;
      add_done <= 1'b0;
      
      // Initialize output registers
      for (int i = 0; i < NUM_REGS; i++) begin
        output_regs[i] <= 32'h0;
      end
    end
    else begin
      if (add_start && !add_computing && !add_done) begin
        // Start computation
        add_computing <= 1'b1;
        add_done <= 1'b0;
        add_counter <= 4'h0;
        $display("[%t] ADD-ONE: Starting computation", $realtime);
      end
      else if (add_computing) begin
        add_counter <= add_counter + 1;
        if (add_counter == 4'h4) begin // 4 cycles delay
          // Finish computation - add 1 to each input
          add_computing <= 1'b0;
          add_done <= 1'b1;
          for (int i = 0; i < NUM_REGS; i++) begin
            output_regs[i] <= input_regs[i] + 1;
          end
          $display("[%t] ADD-ONE: Computation complete", $realtime);
        end
      end
      else if (add_done && !add_start) begin
        // Reset done when start goes low
        add_done <= 1'b0;
        $display("[%t] ADD-ONE: Reset done flag", $realtime);
      end
    end
  end
  
  // Connect to status register
  always_comb begin
    status_reg[0] = add_done;
    status_reg[31:1] = 31'b0;
  end
  
  // AXI4-Lite state machines
  typedef enum logic [1:0] {
    WRITE_IDLE,
    WRITE_DATA,
    WRITE_RESP
  } write_state_t;
  
  typedef enum logic [1:0] {
    READ_IDLE,
    READ_DATA
  } read_state_t;
  
  write_state_t wr_state;
  read_state_t rd_state;
  logic [ADDR_WIDTH-1:0] wr_addr;
  logic [ADDR_WIDTH-1:0] rd_addr;
  
  // Write Channel
  always_ff @(posedge clk_main_a0) begin
    if (!rst_main_n_sync) begin
      wr_state <= WRITE_IDLE;
      cl_ocl_awready <= 1'b0;
      cl_ocl_wready <= 1'b0;
      cl_ocl_bvalid <= 1'b0;
      cl_ocl_bresp <= 2'b00;
      wr_addr <= '0;
      
      // Initialize registers
      for (int i = 0; i < NUM_REGS; i++) begin
        input_regs[i] <= 32'h0;
      end
      control_reg <= 32'h0;
    end
    else begin
      case (wr_state)
        WRITE_IDLE: begin
          cl_ocl_awready <= 1'b1;
          cl_ocl_wready <= 1'b0;
          cl_ocl_bvalid <= 1'b0;
          
          if (ocl_cl_awvalid && cl_ocl_awready) begin
            wr_addr <= ocl_cl_awaddr[ADDR_WIDTH-1:0];
            cl_ocl_awready <= 1'b0;
            wr_state <= WRITE_DATA;
            $display("[%t] AXI WRITE: Address = 0x%02x", $realtime, ocl_cl_awaddr[ADDR_WIDTH-1:0]);
          end
        end
        
        WRITE_DATA: begin
          cl_ocl_wready <= 1'b1;
          
          if (ocl_cl_wvalid && cl_ocl_wready) begin
            $display("[%t] AXI WRITE: Data = 0x%08x to addr 0x%02x", $realtime, ocl_cl_wdata, wr_addr);
            
            // Decode address and write to appropriate register
            if (wr_addr >= 8'h00 && wr_addr <= 8'h1C) begin
              // Input registers (0x00-0x1C, 8 registers)
              input_regs[wr_addr[4:2]] <= ocl_cl_wdata;
              $display("[%t] WRITE: Input reg[%0d] = 0x%08x", $realtime, wr_addr[4:2], ocl_cl_wdata);
            end
            else if (wr_addr == 8'h40) begin
              // Control register
              control_reg <= ocl_cl_wdata;
              $display("[%t] WRITE: Control reg = 0x%08x", $realtime, ocl_cl_wdata);
            end
            
            cl_ocl_wready <= 1'b0;
            wr_state <= WRITE_RESP;
          end
        end
        
        WRITE_RESP: begin
          cl_ocl_bvalid <= 1'b1;
          cl_ocl_bresp <= 2'b00; // OKAY response
          
          if (ocl_cl_bready && cl_ocl_bvalid) begin
            cl_ocl_bvalid <= 1'b0;
            wr_state <= WRITE_IDLE;
          end
        end
      endcase
    end
  end
  
  // Read Channel
  always_ff @(posedge clk_main_a0) begin
    if (!rst_main_n_sync) begin
      rd_state <= READ_IDLE;
      cl_ocl_arready <= 1'b0;
      cl_ocl_rvalid <= 1'b0;
      cl_ocl_rdata <= 32'h0;
      cl_ocl_rresp <= 2'b00;
      rd_addr <= '0;
    end
    else begin
      case (rd_state)
        READ_IDLE: begin
          cl_ocl_arready <= 1'b1;
          cl_ocl_rvalid <= 1'b0;
          
          if (ocl_cl_arvalid && cl_ocl_arready) begin
            rd_addr <= ocl_cl_araddr[ADDR_WIDTH-1:0];
            cl_ocl_arready <= 1'b0;
            rd_state <= READ_DATA;
            $display("[%t] AXI READ: Address = 0x%02x", $realtime, ocl_cl_araddr[ADDR_WIDTH-1:0]);
          end
        end
        
        READ_DATA: begin
          cl_ocl_rvalid <= 1'b1;
          cl_ocl_rresp <= 2'b00; // OKAY response
          
          // Decode address and read from appropriate register
          if (rd_addr >= 8'h00 && rd_addr <= 8'h1C) begin
            // Input registers (read-back)
            cl_ocl_rdata <= input_regs[rd_addr[4:2]];
            $display("[%t] READ: Input reg[%0d] = 0x%08x", $realtime, rd_addr[4:2], input_regs[rd_addr[4:2]]);
          end
          else if (rd_addr >= 8'h20 && rd_addr <= 8'h3C) begin
            // Output registers
            cl_ocl_rdata <= output_regs[rd_addr[4:2] - 3'h0]; // Subtract offset for 0x20 base
            $display("[%t] READ: Output reg[%0d] = 0x%08x", $realtime, rd_addr[4:2], output_regs[rd_addr[4:2]]);
          end
          else if (rd_addr == 8'h40) begin
            // Control register
            cl_ocl_rdata <= control_reg;
            $display("[%t] READ: Control reg = 0x%08x", $realtime, control_reg);
          end
          else if (rd_addr == 8'h44) begin
            // Status register
            cl_ocl_rdata <= status_reg;
            $display("[%t] READ: Status reg = 0x%08x", $realtime, status_reg);
          end
          else begin
            cl_ocl_rdata <= 32'hDEADBEEF; // Default value
            $display("[%t] READ: Unknown address 0x%02x, returning 0xDEADBEEF", $realtime, rd_addr);
          end
          
          if (ocl_cl_rready && cl_ocl_rvalid) begin
            cl_ocl_rvalid <= 1'b0;
            rd_state <= READ_IDLE;
          end
        end
      endcase
    end
  end

//=============================================================================
// SDA
//=============================================================================

  // Cause Protocol Violations
  always_comb begin
    cl_sda_bresp   = 'b0;
    cl_sda_rresp   = 'b0;
    cl_sda_rvalid  = 'b0;
  end

  // Remaining CL Output Ports
  always_comb begin
    cl_sda_awready = 'b0;
    cl_sda_wready  = 'b0;

    cl_sda_bvalid = 'b0;

    cl_sda_arready = 'b0;

    cl_sda_rdata   = 'b0;
  end

//=============================================================================
// SH_DDR
//=============================================================================

   sh_ddr
     #(
       .DDR_PRESENT (EN_DDR)
       )
   SH_DDR
     (
      .clk                       (clk_main_a0 ),
      .rst_n                     (            ),
      .stat_clk                  (clk_main_a0 ),
      .stat_rst_n                (            ),
      .CLK_DIMM_DP               (CLK_DIMM_DP ),
      .CLK_DIMM_DN               (CLK_DIMM_DN ),
      .M_ACT_N                   (M_ACT_N     ),
      .M_MA                      (M_MA        ),
      .M_BA                      (M_BA        ),
      .M_BG                      (M_BG        ),
      .M_CKE                     (M_CKE       ),
      .M_ODT                     (M_ODT       ),
      .M_CS_N                    (M_CS_N      ),
      .M_CLK_DN                  (M_CLK_DN    ),
      .M_CLK_DP                  (M_CLK_DP    ),
      .M_PAR                     (M_PAR       ),
      .M_DQ                      (M_DQ        ),
      .M_ECC                     (M_ECC       ),
      .M_DQS_DP                  (M_DQS_DP    ),
      .M_DQS_DN                  (M_DQS_DN    ),
      .cl_RST_DIMM_N             (RST_DIMM_N  ),
      .cl_sh_ddr_axi_awid        (            ),
      .cl_sh_ddr_axi_awaddr      (            ),
      .cl_sh_ddr_axi_awlen       (            ),
      .cl_sh_ddr_axi_awsize      (            ),
      .cl_sh_ddr_axi_awvalid     (            ),
      .cl_sh_ddr_axi_awburst     (            ),
      .cl_sh_ddr_axi_awuser      (            ),
      .cl_sh_ddr_axi_awready     (            ),
      .cl_sh_ddr_axi_wdata       (            ),
      .cl_sh_ddr_axi_wstrb       (            ),
      .cl_sh_ddr_axi_wlast       (            ),
      .cl_sh_ddr_axi_wvalid      (            ),
      .cl_sh_ddr_axi_wready      (            ),
      .cl_sh_ddr_axi_bid         (            ),
      .cl_sh_ddr_axi_bresp       (            ),
      .cl_sh_ddr_axi_bvalid      (            ),
      .cl_sh_ddr_axi_bready      (            ),
      .cl_sh_ddr_axi_arid        (            ),
      .cl_sh_ddr_axi_araddr      (            ),
      .cl_sh_ddr_axi_arlen       (            ),
      .cl_sh_ddr_axi_arsize      (            ),
      .cl_sh_ddr_axi_arvalid     (            ),
      .cl_sh_ddr_axi_arburst     (            ),
      .cl_sh_ddr_axi_aruser      (            ),
      .cl_sh_ddr_axi_arready     (            ),
      .cl_sh_ddr_axi_rid         (            ),
      .cl_sh_ddr_axi_rdata       (            ),
      .cl_sh_ddr_axi_rresp       (            ),
      .cl_sh_ddr_axi_rlast       (            ),
      .cl_sh_ddr_axi_rvalid      (            ),
      .cl_sh_ddr_axi_rready      (            ),
      .sh_ddr_stat_bus_addr      (            ),
      .sh_ddr_stat_bus_wdata     (            ),
      .sh_ddr_stat_bus_wr        (            ),
      .sh_ddr_stat_bus_rd        (            ),
      .sh_ddr_stat_bus_ack       (            ),
      .sh_ddr_stat_bus_rdata     (            ),
      .ddr_sh_stat_int           (            ),
      .sh_cl_ddr_is_ready        (            )
      );

  always_comb begin
    cl_sh_ddr_stat_ack   = 'b0;
    cl_sh_ddr_stat_rdata = 'b0;
    cl_sh_ddr_stat_int   = 'b0;
  end

//=============================================================================
// USER-DEFINED INTERRUPTS
//=============================================================================

  always_comb begin
    cl_sh_apppf_irq_req = 'b0;
  end

//=============================================================================
// VIRTUAL JTAG
//=============================================================================

  always_comb begin
    tdo = 'b0;
  end

//=============================================================================
// HBM MONITOR IO
//=============================================================================

  always_comb begin
    hbm_apb_paddr_1   = 'b0;
    hbm_apb_pprot_1   = 'b0;
    hbm_apb_psel_1    = 'b0;
    hbm_apb_penable_1 = 'b0;
    hbm_apb_pwrite_1  = 'b0;
    hbm_apb_pwdata_1  = 'b0;
    hbm_apb_pstrb_1   = 'b0;
    hbm_apb_pready_1  = 'b0;
    hbm_apb_prdata_1  = 'b0;
    hbm_apb_pslverr_1 = 'b0;

    hbm_apb_paddr_0   = 'b0;
    hbm_apb_pprot_0   = 'b0;
    hbm_apb_psel_0    = 'b0;
    hbm_apb_penable_0 = 'b0;
    hbm_apb_pwrite_0  = 'b0;
    hbm_apb_pwdata_0  = 'b0;
    hbm_apb_pstrb_0   = 'b0;
    hbm_apb_pready_0  = 'b0;
    hbm_apb_prdata_0  = 'b0;
    hbm_apb_pslverr_0 = 'b0;
  end

//=============================================================================
// PCIE
//=============================================================================

  always_comb begin
    PCIE_EP_TXP    = 'b0;
    PCIE_EP_TXN    = 'b0;

    PCIE_RP_PERSTN = 'b0;
    PCIE_RP_TXP    = 'b0;
    PCIE_RP_TXN    = 'b0;
  end

endmodule // cl_top
