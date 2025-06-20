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

`include "common_base_test.svh"

module cl_top_base_test();
   import tb_type_defines_pkg::*;

   // Simple Add-One register addresses
   `define INPUT_BASE    64'h00    // Input registers 0x00-0x1C (8 regs)
   `define OUTPUT_BASE   64'h20    // Output registers 0x20-0x3C (8 regs)
   `define CONTROL_REG   64'h40    // Control register
   `define STATUS_REG    64'h44    // Status register
   `define START_BIT     32'h00000001
   `define DONE_BIT      32'h00000001

   // Test data
   logic [31:0] test_input_data [0:7];
   logic [31:0] read_output_data [0:7];
   logic [31:0] expected_output_data [0:7];
   logic [31:0] status_data;
   logic [31:0] read_data;
   int poll_count;
   int error_count;

   initial begin
      error_count = 0;
      
      tb.power_up();
      
      $display("[%t] Starting Simple Add-One Test", $realtime);

      // Wait for system to stabilize
      tb.nsec_delay(1000);
      
      // Test sequence
      test_add_one();
      
      // Final delay
      tb.nsec_delay(500);
      tb.power_down();
      
      // Report results
      if (error_count == 0) begin
         $display("🎉 TEST PASSED: Simple Add-One test completed successfully");
      end else begin
         $display("💥 TEST FAILED: %0d errors detected", error_count);
      end
      
      report_pass_fail_status();
      $finish;
   end

   // Main test task
   task test_add_one();
      begin
         $display("[%t] === SIMPLE ADD-ONE TEST ===", $realtime);
         
         // Step 1: Initialize test data
         $display("[%t] Step 1: Initializing test data", $realtime);
         for (int i = 0; i < 8; i++) begin
            test_input_data[i] = 32'h10000000 + i;  // Simple pattern
            expected_output_data[i] = test_input_data[i] + 1;  // Expected result
         end
         
         // Step 2: Clear control register
         $display("[%t] Step 2: Clearing control register", $realtime);
         tb.poke_ocl(.addr(`CONTROL_REG), .data(32'h00000000));
         tb.nsec_delay(100);
         
         // Step 3: Write input data
         $display("[%t] Step 3: Writing input data", $realtime);
         for (int i = 0; i < 8; i++) begin
            tb.poke_ocl(.addr(`INPUT_BASE + (i * 4)), .data(test_input_data[i]));
            $display("[%t]   Input[%0d] = 0x%08x", $realtime, i, test_input_data[i]);
         end
         
         // Step 4: Verify input data readback
         $display("[%t] Step 4: Verifying input data readback", $realtime);
         for (int i = 0; i < 8; i++) begin
            tb.peek_ocl(.addr(`INPUT_BASE + (i * 4)), .data(read_data));
            if (read_data !== test_input_data[i]) begin
               $error("[%t] NO Input verification failed at reg %0d: expected 0x%08x, got 0x%08x", 
                      $realtime, i, test_input_data[i], read_data);
               error_count++;
            end else begin
               $display("[%t]   OK Input[%0d] readback: 0x%08x", $realtime, i, read_data);
            end
         end
         
         // Step 5: Check initial status
         tb.peek_ocl(.addr(`STATUS_REG), .data(status_data));
         $display("[%t] Step 5: Initial status: 0x%08x", $realtime, status_data);
         
         // Step 6: Start computation
         $display("[%t] Step 6: Starting Add-One computation", $realtime);
         tb.poke_ocl(.addr(`CONTROL_REG), .data(`START_BIT));
         tb.nsec_delay(100);
         
         // Step 7: Wait for completion
         $display("[%t] Step 7: Waiting for computation to complete", $realtime);
         poll_count = 0;
         status_data = 32'h0;
         
         while ((status_data & `DONE_BIT) == 0 && poll_count < 100) begin
            tb.nsec_delay(100); // 100ns delay between polls
            tb.peek_ocl(.addr(`STATUS_REG), .data(status_data));
            poll_count++;
            
            if (poll_count % 10 == 0) begin
               $display("[%t]   Polling... count=%0d, status=0x%08x", 
                        $realtime, poll_count, status_data);
            end
         end
         
         if (poll_count >= 100) begin
            $error("[%t] NO Timeout waiting for Add-One completion after %0d polls", $realtime, poll_count);
            error_count++;
            return;
         end
         
         $display("[%t] OK Add-One computation completed after %0d polls", $realtime, poll_count);
         
         // Step 8: Clear start bit
         $display("[%t] Step 8: Clearing start bit", $realtime);
         tb.poke_ocl(.addr(`CONTROL_REG), .data(32'h00000000));
         tb.nsec_delay(100);
         
         // Step 9: Read output data
         $display("[%t] Step 9: Reading output data", $realtime);
         for (int i = 0; i < 8; i++) begin
            tb.peek_ocl(.addr(`OUTPUT_BASE + (i * 4)), .data(read_output_data[i]));
            $display("[%t]   Output[%0d] = 0x%08x", $realtime, i, read_output_data[i]);
         end
         
         // Step 10: Verify results
         verify_results();
         
         // Step 11: Test multiple operations
         test_multiple_operations();
      end
   endtask

   // Verify the add-one results
   task verify_results();
      int correct_count;
      logic is_correct;
      begin
         $display("[%t] === VERIFYING RESULTS ===", $realtime);
         
         correct_count = 0;
         
         $display("INPUT -> OUTPUT COMPARISON:");
         $display("Reg# | Input      | Output     | Expected   | Status");
         $display("-----|------------|------------|------------|-------");
         
         for (int i = 0; i < 8; i++) begin
            is_correct = (read_output_data[i] == expected_output_data[i]);
            if (is_correct) correct_count++;
            
            $display("%2d   | 0x%08x | 0x%08x | 0x%08x | %s", 
                     i, test_input_data[i], read_output_data[i], 
                     expected_output_data[i], is_correct ? "OK PASS" : "NO FAIL");
            
            if (!is_correct) begin
               $error("[%t] NO Output mismatch at reg %0d", $realtime, i);
               error_count++;
            end
         end
         
         $display("\nSUMMARY:");
         $display("  Correct results: %0d/8", correct_count);
         $display("  Accuracy: %0d%%", (correct_count * 100) / 8);
         
         if (correct_count == 8) begin
            $display("[%t] 🎉 ALL OUTPUTS CORRECT! Add-One operation working perfectly!", $realtime);
         end else begin
            $display("[%t] 💥 SOME OUTPUTS INCORRECT! Add-One operation has issues.", $realtime);
         end
      end
   endtask

   // Test multiple operations to ensure proper reset behavior
   task test_multiple_operations();
      logic [31:0] test_data2 [0:7];
      logic [31:0] output_data2 [0:7];
      logic [31:0] temp_status;
      logic is_correct;
      begin
         $display("[%t] === TESTING MULTIPLE OPERATIONS ===", $realtime);
         
         // Prepare second test data
         for (int i = 0; i < 8; i++) begin
            test_data2[i] = 32'h20000000 + (i * 16);  // Different pattern
         end
         
         // Write new input data
         $display("[%t] Writing second test data", $realtime);
         for (int i = 0; i < 8; i++) begin
            tb.poke_ocl(.addr(`INPUT_BASE + (i * 4)), .data(test_data2[i]));
         end
         
         // Start second computation
         $display("[%t] Starting second computation", $realtime);
         tb.poke_ocl(.addr(`CONTROL_REG), .data(`START_BIT));
         tb.nsec_delay(100);
         
         // Wait for completion
         poll_count = 0;
         temp_status = 32'h0;
         while ((temp_status & `DONE_BIT) == 0 && poll_count < 100) begin
            tb.nsec_delay(100);
            tb.peek_ocl(.addr(`STATUS_REG), .data(temp_status));
            poll_count++;
         end
         
         if (poll_count >= 100) begin
            $display("[%t] ⚠️  Second computation timed out", $realtime);
         end else begin
            $display("[%t] OK Second computation completed after %0d polls", $realtime, poll_count);
            
            // Clear start bit
            tb.poke_ocl(.addr(`CONTROL_REG), .data(32'h00000000));
            tb.nsec_delay(100);
            
            // Read second results
            for (int i = 0; i < 8; i++) begin
               tb.peek_ocl(.addr(`OUTPUT_BASE + (i * 4)), .data(output_data2[i]));
               is_correct = (output_data2[i] == (test_data2[i] + 1));
               $display("[%t]   Second test[%0d]: 0x%08x + 1 = 0x%08x %s", 
                        $realtime, i, test_data2[i], output_data2[i], 
                        is_correct ? "OK" : "NO");
               if (!is_correct) error_count++;
            end
         end
         
         $display("[%t] Multiple operations test completed", $realtime);
      end
   endtask

endmodule // cl_top_base_test
