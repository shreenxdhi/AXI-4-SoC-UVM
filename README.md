# Design and UVM Verification of a Simplified AXI4 Memory Subsystem

This project implements a small AXI4-based memory subsystem and verifies it
using a UVM testbench. It was developed as a final-year B.Tech ECE project and
is arranged as two SystemVerilog source files so that the complete design can
be copied directly into EDA Playground.

The subsystem has a 32-bit address bus, 32-bit data bus and 4-bit transaction
ID. Address decoding routes valid memory accesses to a 64 KB SRAM model. The
peripheral placeholder and all unmapped addresses return an AXI `DECERR`
response.

## Project objectives

- Understand the five independent AXI4 channels and their handshakes.
- Implement address decoding and response routing for a small AXI fabric.
- Support byte, halfword and word accesses using `WSTRB`.
- Verify single-beat and INCR burst transfers using UVM.
- Check read data and AXI responses with an independent reference model.
- Measure the exercised transaction space using functional coverage.

## Architecture

![AXI4 subsystem and UVM environment](images/axi4-uvm-block-diagram.png)

The UVM master agent supplies transactions to the DUT. Its driver converts
sequence items into AXI signal activity, while its monitor reconstructs
completed transfers. Each monitored transaction is sent to both the
scoreboard and the coverage collector. The scoreboard maintains its own
byte-addressable memory model and uses it to predict read data.

## Address map

| Region | Address range | Behaviour |
| --- | --- | --- |
| SRAM | `0x0000_0000`–`0x0000_FFFF` | Read and write, `OKAY` response |
| Peripheral placeholder | `0x1000_0000`–`0x1000_0FFF` | `DECERR` response |
| All other addresses | Unmapped | `DECERR` response |

The peripheral region is only an address-map placeholder in the present
version; it does not contain working peripheral registers.

## Implemented features

- AXI4 INCR bursts from 1 to 16 beats
- Byte, halfword and word transfer sizes
- Independent write-address and write-data channel driving
- Byte-enable writes using `WSTRB`
- Configurable SRAM response delays
- `WLAST`, `RLAST`, `BID` and `RID` checking
- Directed and constrained-random sequences
- UVM driver, monitor, sequencer, agent, scoreboard and coverage collector
- Byte-addressable reference memory
- Functional coverpoints and cross coverage

## Repository layout

```text
.
├── axi-4_soc_top.sv              AXI package, interface and RTL
├── tb_axi-4_soc.sv               UVM environment, tests and testbench top
├── docs/
│   ├── design_specification.md   Design behaviour and implementation details
│   └── verification_plan.md      Test strategy and coverage plan
├── images/
│   └── axi4-uvm-block-diagram.png
└── results/
    └── README.md                 Recorded simulation result
```

The two-file source layout is intentional. It keeps the project easy to run on
EDA Playground without maintaining a long compile list.

## Available tests

| Test | Purpose |
| --- | --- |
| `smoke_test` | Four single-beat word write/read pairs |
| `incr_burst_4_test` | Four-beat word INCR burst |
| `incr_burst_8_test` | Eight-beat word INCR burst |
| `incr_burst_16_test` | Sixteen-beat word INCR burst |
| `incr_byte_burst_test` | Eight-beat byte INCR burst |
| `incr_halfword_burst_test` | Eight-beat halfword INCR burst |
| `incr_word_burst_test` | Eight-beat word INCR burst |
| `random_incr_test` | Random aligned INCR write/read pairs |

## Running on EDA Playground

1. Select **SystemVerilog/Verilog** as the language.
2. Select **Cadence Xcelium 25.03** as the simulator.
3. Enable **UVM 1.2**.
4. Paste `axi-4_soc_top.sv` into the design pane.
5. Paste `tb_axi-4_soc.sv` into the testbench pane.
6. Enter the required test in the run options and start the simulation.

For the smoke test:

```text
-access +rw -coverage all +UVM_TESTNAME=smoke_test
```

For 100 constrained-random write/read pairs:

```text
-access +rw -coverage all +UVM_TESTNAME=random_incr_test +RANDOM_PAIRS=100
```

The scoreboard summary, functional coverage and UVM severity counts are
printed near the end of the simulator output.

## Recorded results

The smoke and 100-pair random tests were run on Cadence Xcelium 25.03-s001 with
the default seed of 1. Both runs completed with no data or response mismatches
and no UVM warnings, errors or fatals.

| Test | Seed | Writes | Reads | Write/read beats | Mismatches | Coverage | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `smoke_test` | 1 | 4 | 4 | 4 / 4 | 0 | 34.26% | Pass |
| `random_incr_test` | 1 | 100 | 100 | 574 / 574 | 0 | 58.33% | Pass |

See [results/README.md](results/README.md) for the simulator and run details.

## Present limitations

- Only one write transaction and one read transaction can be active at a time.
- Multiple outstanding transactions and response reordering are not supported.
- INCR is the verified burst type in the present test set.
- Exclusive accesses, cache coherency and low-power behaviour are not covered.
- The SRAM is a simulation model rather than a synthesized memory macro.
- The project has been verified by simulation and has not been implemented on
  an FPGA or fabricated as hardware.

These restrictions keep the work focused on AXI channel operation, burst
handling and UVM-based verification rather than attempting a complete
commercial SoC.

## Documentation

- [Design specification](docs/design_specification.md)
- [Verification plan](docs/verification_plan.md)
