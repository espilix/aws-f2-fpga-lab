/*
 * Copyright 2015-2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"). You may
 * not use this file except in compliance with the License. A copy of the
 * License is located at
 *
 *     http://aws.amazon.com/apache2.0/
 *
 * or in the "license" file accompanying this file. This file is distributed
 * on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 * express or implied. See the License for the specific language governing
 * permissions and limitations under the License.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>

// AWS FPGA SDK includes
#include <fpga_pci.h>
#include <fpga_mgmt.h>
#include <utils/lcd.h>

// Register addresses for Simple Add-One
#define INPUT_BASE_ADDR     0x00    // Input registers 0x00-0x1C (8 regs)
#define OUTPUT_BASE_ADDR    0x20    // Output registers 0x20-0x3C (8 regs)
#define CONTROL_REG_ADDR    0x40    // Control register
#define STATUS_REG_ADDR     0x44    // Status register

#define START_BIT           0x00000001
#define DONE_BIT            0x00000001

#define NUM_REGISTERS       8

// FPGA slot and PCI IDs
#define FPGA_SLOT_ID        0
#define PCI_VENDOR_ID       0x1D0F  // Amazon PCI Vendor ID
#define PCI_DEVICE_ID       0xF000  // PCI Device ID

// Function prototypes
static int check_afi_ready(int slot_id);
static int peek_poke_example(int slot_id, int pf_id, int bar_id);
static int test_add_one_operation(pci_bar_handle_t pci_bar_handle);

int main(int argc __attribute__((unused)), char **argv __attribute__((unused))) {
    int rc = 0;
    int slot_id = 0;
    int pf_id = FPGA_APP_PF;
    int bar_id = APP_PF_BAR0;

    printf("\n=== AWS FPGA Simple Add-One Test ===\n");

    // Initialize the FPGA management library
    rc = fpga_mgmt_init();
    if (rc != 0) {
        printf("ERROR: Unable to initialize the FPGA management library\n");
        return 1;
    }

    printf("FPGA management library initialized successfully\n");

    // Check if AFI is ready
    rc = check_afi_ready(slot_id);
    if (rc != 0) {
        printf("ERROR: AFI is not ready\n");
        goto cleanup;
    }

    printf("AFI is ready, proceeding with test\n");

    // Run the peek/poke example
    rc = peek_poke_example(slot_id, pf_id, bar_id);
    if (rc != 0) {
        printf("ERROR: Peek/poke example failed\n");
        goto cleanup;
    }

    printf("Test completed successfully!\n");

cleanup:
    printf("Cleaning up...\n");
    return rc;
}

static int check_afi_ready(int slot_id) {
    struct fpga_mgmt_image_info info = {0};
    int rc = 0;

    // Get the current state of the AFI
    rc = fpga_mgmt_describe_local_image(slot_id, &info, 0);
    if (rc != 0) {
        printf("ERROR: Unable to get AFI information from slot %d. Are you running as root?\n", slot_id);
        return rc;
    }

    // Check if the AFI is loaded and ready
    printf("AFI PCI  Vendor ID: 0x%x, Device ID 0x%x\n", info.spec.map[FPGA_APP_PF].vendor_id, info.spec.map[FPGA_APP_PF].device_id);

    if (info.status != FPGA_STATUS_LOADED) {
        printf("ERROR: AFI is not in LOADED state!\n");
        printf("       AFI status: %s\n", 
               info.status == FPGA_STATUS_NOT_PROGRAMMED ? "NOT_PROGRAMMED" :
               info.status == FPGA_STATUS_CLEARED ? "CLEARED" :
               info.status == FPGA_STATUS_LOADED ? "LOADED" :
               info.status == FPGA_STATUS_BUSY ? "BUSY" : "UNKNOWN");
        return 1;
    }

    printf("AFI is loaded and ready\n");
    return 0;
}

static int peek_poke_example(int slot_id, int pf_id, int bar_id) {
    int rc = 0;
    pci_bar_handle_t pci_bar_handle = PCI_BAR_HANDLE_INIT;

    printf("\n=== Initializing PCI BAR ===\n");

    // Attach to the FPGA, with a PCIe connection
    rc = fpga_pci_attach(slot_id, pf_id, bar_id, 0, &pci_bar_handle);
    if (rc != 0) {
        printf("ERROR: Unable to attach to the AFI on slot id %d, pf id %d, bar id %d\n", slot_id, pf_id, bar_id);
        return rc;
    }

    printf("PCI BAR attached successfully\n");

    // Test the Add-One operation
    rc = test_add_one_operation(pci_bar_handle);
    if (rc != 0) {
        printf("ERROR: Add-One operation test failed\n");
        goto cleanup;
    }

cleanup:
    // Detach from the FPGA
    if (pci_bar_handle >= 0) {
        rc = fpga_pci_detach(pci_bar_handle);
        if (rc != 0) {
            printf("ERROR: Failure while detaching from the FPGA\n");
        } else {
            printf("PCI BAR detached successfully\n");
        }
    }

    return rc;
}

static int test_add_one_operation(pci_bar_handle_t pci_bar_handle) {
    int rc = 0;
    uint32_t test_data[NUM_REGISTERS];
    uint32_t output_data[NUM_REGISTERS];
    uint32_t status = 0;
    int poll_count = 0;
    const int max_polls = 1000;

    printf("\n=== Testing Add-One Operation ===\n");

    // Step 1: Initialize test data
    printf("Step 1: Initializing test data\n");
    for (int i = 0; i < NUM_REGISTERS; i++) {
        test_data[i] = 0x10000000 + i;
        printf("  Input[%d] = 0x%08x\n", i, test_data[i]);
    }

    // Step 2: Clear control register
    printf("Step 2: Clearing control register\n");
    rc = fpga_pci_poke(pci_bar_handle, CONTROL_REG_ADDR, 0x00000000);
    if (rc != 0) {
        printf("ERROR: Failed to clear control register\n");
        return rc;
    }

    // Step 3: Write input data to FPGA
    printf("Step 3: Writing input data to FPGA\n");
    for (int i = 0; i < NUM_REGISTERS; i++) {
        uint32_t addr = INPUT_BASE_ADDR + (i * 4);
        rc = fpga_pci_poke(pci_bar_handle, addr, test_data[i]);
        if (rc != 0) {
            printf("ERROR: Failed to write input register %d\n", i);
            return rc;
        }
        printf("  Wrote 0x%08x to address 0x%02x\n", test_data[i], addr);
    }

    // Step 4: Verify input data readback
    printf("Step 4: Verifying input data readback\n");
    for (int i = 0; i < NUM_REGISTERS; i++) {
        uint32_t addr = INPUT_BASE_ADDR + (i * 4);
        uint32_t read_data = 0;
        rc = fpga_pci_peek(pci_bar_handle, addr, &read_data);
        if (rc != 0) {
            printf("ERROR: Failed to read input register %d\n", i);
            return rc;
        }
        if (read_data != test_data[i]) {
            printf("ERROR: Input readback mismatch at reg %d: expected 0x%08x, got 0x%08x\n", 
                   i, test_data[i], read_data);
            return 1;
        }
        printf("  ✅ Input[%d] readback: 0x%08x\n", i, read_data);
    }

    // Step 5: Check initial status
    printf("Step 5: Checking initial status\n");
    rc = fpga_pci_peek(pci_bar_handle, STATUS_REG_ADDR, &status);
    if (rc != 0) {
        printf("ERROR: Failed to read status register\n");
        return rc;
    }
    printf("Initial status: 0x%08x\n", status);

    // Step 6: Start computation
    printf("Step 6: Starting Add-One computation\n");
    rc = fpga_pci_poke(pci_bar_handle, CONTROL_REG_ADDR, START_BIT);
    if (rc != 0) {
        printf("ERROR: Failed to start computation\n");
        return rc;
    }
    printf("Computation started\n");

    // Step 7: Wait for completion
    printf("Step 7: Waiting for computation to complete\n");
    poll_count = 0;
    status = 0;

    while (!(status & DONE_BIT) && poll_count < max_polls) {
        usleep(1000); // 1ms delay between polls
        rc = fpga_pci_peek(pci_bar_handle, STATUS_REG_ADDR, &status);
        if (rc != 0) {
            printf("ERROR: Failed to read status register during polling\n");
            return rc;
        }
        poll_count++;

        if (poll_count % 100 == 0) {
            printf("  Polling... count=%d, status=0x%08x\n", poll_count, status);
        }
    }

    if (poll_count >= max_polls) {
        printf("ERROR: Timeout waiting for computation completion after %d polls\n", poll_count);
        return 1;
    }

    printf("✅ Computation completed after %d polls\n", poll_count);

    // Step 8: Clear start bit
    printf("Step 8: Clearing start bit\n");
    rc = fpga_pci_poke(pci_bar_handle, CONTROL_REG_ADDR, 0x00000000);
    if (rc != 0) {
        printf("ERROR: Failed to clear start bit\n");
        return rc;
    }

    // Step 9: Read output data
    printf("Step 9: Reading output data\n");
    for (int i = 0; i < NUM_REGISTERS; i++) {
        uint32_t addr = OUTPUT_BASE_ADDR + (i * 4);
        rc = fpga_pci_peek(pci_bar_handle, addr, &output_data[i]);
        if (rc != 0) {
            printf("ERROR: Failed to read output register %d\n", i);
            return rc;
        }
        printf("  Output[%d] = 0x%08x\n", i, output_data[i]);
    }

    // Step 10: Verify results
    printf("Step 10: Verifying results\n");
    printf("\nRESULTS COMPARISON:\n");
    printf("Reg# | Input      | Output     | Expected   | Status\n");
    printf("-----|------------|------------|------------|-------\n");

    int correct_count = 0;
    for (int i = 0; i < NUM_REGISTERS; i++) {
        uint32_t expected = test_data[i] + 1;
        bool is_correct = (output_data[i] == expected);
        if (is_correct) correct_count++;

        printf("%2d   | 0x%08x | 0x%08x | 0x%08x | %s\n", 
               i, test_data[i], output_data[i], expected, 
               is_correct ? "✅ PASS" : "❌ FAIL");
    }

    printf("\nSUMMARY:\n");
    printf("  Correct results: %d/%d\n", correct_count, NUM_REGISTERS);
    printf("  Accuracy: %d%%\n", (correct_count * 100) / NUM_REGISTERS);

    if (correct_count == NUM_REGISTERS) {
        printf("🎉 ALL OUTPUTS CORRECT! Add-One operation working perfectly!\n");
        return 0;
    } else {
        printf("💥 SOME OUTPUTS INCORRECT! Add-One operation has issues.\n");
        return 1;
    }
}
