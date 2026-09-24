# AXI4 Memory Subsystem — UVM Verification

SystemVerilog/UVM verification of a simplified AXI4 memory subsystem with an
address-decoding fabric, a 64 KB SRAM slave and a `DECERR` error slave.

[TEST IT ON EDA PLAYGROUND](https://www.edaplayground.com/x/WKEU)

---

## 1. Design Overview

The subsystem is a single-master AXI4 memory subsystem: a 32-bit address bus,
32-bit data bus and 4-bit transaction ID. The fabric decodes every address and
routes the five AXI channels to the matching slave.

```
master ──► axi_fabric ──► axi_sram        0x0000_0000 – 0x0000_FFFF   OKAY
                    └──► axi_err_slave    all other addresses          DECERR
```

| Region | Address range | Behaviour |
| --- | --- | --- |
| SRAM | `0x0000_0000`–`0x0000_FFFF` | Read and write, `OKAY` response |
| Error slave | everything else | `DECERR` response |

Writes honour `WSTRB` byte enables. Reads return `RID`/`RLAST` per beat. INCR
bursts of 1–16 beats are supported at byte, halfword and word sizes, including
unaligned starts and FIXED/WRAP burst encodings.

---

## 2. DUT Specification

| Parameter | Value |
| --- | --- |
| Address width | 32 bits |
| Data width | 32 bits (4 byte lanes) |
| ID width | 4 bits |
| Max burst length | 16 beats |
| Transfer sizes | Byte, halfword, word |
| Burst types | FIXED, INCR, WRAP |
| SRAM | 64 KB byte-addressable model, configurable latency |
| Responses | `OKAY`, `DECERR` |
| Clock / reset | Single `aclk`, active-low `aresetn` |
| Verification methodology | UVM 1.2 |

---

## 3. Verification Objectives

| # | Objective | Check |
| --- | --- | --- |
| 1 | Address decoding | SRAM accesses return `OKAY`, unmapped return `DECERR` |
| 2 | Data integrity | Read data equals the reference-model prediction |
| 3 | Byte enables | `WSTRB` gates exactly the enabled byte lanes |
| 4 | Burst bookkeeping | `WLAST`/`RLAST` on the final beat only |
| 5 | ID routing | `BID`/`RID` match the issued transaction ID |
| 6 | Burst types | FIXED, INCR and WRAP beat addresses follow the spec |
| 7 | Unaligned transfers | First/final beat lanes respect the byte offset |
| 8 | Handshake stability | VALID payloads stable while READY is low |
| 9 | Response legality | Only `OKAY`/`DECERR` ever appear on B/R |
| 10 | Long-duration operation | Ordering and data hold under stress traffic |

---

## 4. UVM Architecture

![AXI4 subsystem and UVM environment](images/axi4-uvm-block-diagram.png)

```
Sequence → Sequencer → Driver → DUT (axi_if) → Monitor ─┬→ Scoreboard → Ref model
                                                        └→ Coverage
```

| Component | Responsibility |
| --- | --- |
| `axi_transaction` | Sequence item: addr, id, dir, len, size, burst, payload |
| `axi_driver` | Converts items into five-channel AXI pin activity |
| `axi_monitor` | Reconstructs completed transfers from the bus |
| `axi_agent` | Driver + monitor + sequencer |
| `axi_ref_model` | Byte-addressable expected memory |
| `axi_scoreboard` | Compares responses and read data against the model |
| `axi_coverage` | Coverpoints and crosses over the transaction space |
| `axi_env` | Connects agent, scoreboard and coverage |
| `axi_sva` (bound) | 21 concurrent protocol assertions on the interface |

---

## 5. Testbench Organization

```
rtl/
├── axi_pkg.sv              Parameters, enums, address helpers
├── axi_if.sv               Interface with master/slave modports
├── axi_sram.sv             64 KB SRAM slave
├── axi_err_slave.sv        DECERR responder
├── axi_fabric.sv           Address decoder and channel router
├── soc_top.sv              Top level
├── axi_sva.sv              SVA protocol checker
└── axi_sva_bind.sv         bind of the checker at tb_top (via axi_bus)

tb/
├── tb_pkg.sv               Includes every TB class below
├── tb_top.sv               Clocks, reset, DUT, bind, run_test
├── axi_transaction.sv
├── axi_driver.sv  axi_monitor.sv  axi_agent.sv
├── axi_ref_model.sv  axi_scoreboard.sv  axi_coverage.sv  axi_env.sv
├── axi_sequences.sv        Directed and constrained-random sequences
└── axi_tests.sv            All UVM tests
```

All UVM classes are compiled through `tb_pkg.sv`; `tb_top.sv` holds DUT
instantiation, interfaces, clock/reset generation, the SVA bind and test
startup.

---

## 6. Stimulus Strategy

| Element | Behavior |
| --- | --- |
| Direction | Randomized read/write, write-then-readback pairs |
| Address | Random inside the SRAM window, size-aligned or deliberately unaligned |
| Size / len | Constrained to legal combinations (WRAP only 2/4/8/16 beats) |
| Handshake timing | Random AW/W/AR stalls (`addr_delay`, `data_delay`) |
| Error traffic | Directed accesses into the unmapped region expecting `DECERR` |
| 4 KB rule | INCR bursts never cross a 4 KB boundary (AMBA constraint) |

---

## 7. Test Plan

| Test | Stimulus | Intent |
| --- | --- | --- |
| `smoke_test` | Four single-beat word write/read pairs | Basic bring-up |
| `incr_burst_4/8/16_test` | Word INCR bursts | Burst addressing |
| `incr_byte_burst_test` | Eight-beat byte INCR | Byte-lane operation |
| `incr_halfword_burst_test` | Eight-beat halfword INCR | Halfword operation |
| `incr_word_burst_test` | Eight-beat word INCR | Full-width operation |
| `random_incr_test` | N constrained-random write/read pairs | Address, size, length space |
| `fixed_burst_test` | Four-beat FIXED burst | Same-address beats |
| `wrap_burst_test` | Four-beat WRAP burst | Wrap-window addressing |
| `unaligned_burst_test` | Unaligned halfword INCR | Byte-offset strobing |
| `err_response_test` | Peripheral-region write/read | `DECERR` path |
| `axi_stress_test` | 1,000 random pairs + directed markers | Endurance, long-run ordering |
| `coverage_max_test` | Full directed + random mix | Close every reachable bin in one run |

All 14 tests share one reusable environment and scoreboard.

---

## 8. Reference Model / Scoreboard

| Metric | Source |
| --- | --- |
| Writes / reads checked | Completed transfers from the monitor |
| Write / read beats | Per-beat counts |
| Data mismatches | Read beat vs reference-model prediction |
| Response mismatches | Observed `BRESP`/`RRESP` vs expected |
| Functional coverage | Covergroup instance score, reported per run |

Model: byte-addressable memory; write applies `WSTRB`, read predicts each beat
address through the same burst-address helper the RTL uses.

---

## 9. SystemVerilog Assertions

`axi_sva.sv` is attached through a `bind` statement in `axi_sva_bind.sv`.
Xcelium does not allow binding a module into an interface type, so the bind
targets `tb_top` and reads the signals through the `axi_bus` interface
instance. Every transaction passes through that instance, so the same traffic
is checked. The RTL and interface files stay untouched, and failures are
reported through `uvm_error` so they fail the test.

| Group | Properties |
| --- | --- |
| Handshake stability | AW/AR/W/B/R payloads stable while VALID high and READY low (A1, A5, A10, A12, A15) |
| Burst legality | No reserved burst encoding; WRAP only 2/4/8/16 beats; WRAP start aligned (A2–A4, A13, A14) |
| Byte lanes | `WSTRB` nonzero; first-beat byte-offset rule; aligned first beat inside its natural window (A6, A20, A21) |
| Beat counting | Beats never exceed `LEN+1`; `WLAST`/`RLAST` exactly on the final beat (A7, A8, A17, A18) |
| Response sanity | No `BVALID`/`RVALID` without an outstanding request; only `OKAY`/`DECERR` (A9, A11, A16, A19) |

---

## 10. Functional Coverage

| Coverpoint / cross | Bins |
| --- | --- |
| Operation | Read, write |
| Burst | FIXED, INCR, WRAP |
| Size | Byte, halfword, word |
| Length | 1, 2–4, 5–8, 9–16 beats |
| Alignment | Aligned, unaligned |
| Response | `OKAY`, `DECERR` |
| Crosses | burst×size, burst×length, dir×burst, dir×size, size×alignment, dir×response |

Cells that the protocol can never reach (`SLVERR`, WRAP with one beat, byte
with unaligned) are removed with `ignore_bins` and explained in
`axi_coverage.sv`. The recorded 85.01% is a stimulus gap rather than a checker
limit: the error bursts are only ever word-aligned INCR, so some crosses stay
open. The reasoning is in [results/README.md](results/README.md).

---

## 11. Verification Results

Recorded on Cadence Xcelium 25.03-s001, CDNS-UVM 1.2, seed 1. Nine regression
runs, all passed:

| Test | Transactions | Mismatches | Coverage | Result |
| --- | --- | --- | --- | --- |
| `smoke_test` | 4 W + 4 R | 0 | 37.38% | PASS |
| `incr_burst_4_test` | 1 W + 1 R (4-beat INCR) | 0 | 37.38% | PASS |
| `fixed_burst_test` | 1 W + 1 R (4-beat FIXED) | 0 | 37.38% | PASS |
| `wrap_burst_test` | 1 W + 1 R (4-beat WRAP) | 0 | 37.38% | PASS |
| `unaligned_burst_test` | 1 W + 1 R (halfword, `0x302`) | 0 | 37.38% | PASS |
| `err_response_test` | 1 W + 1 R (`DECERR` both) | 0 | 40.22% | PASS |
| `random_incr_test` (`+RANDOM_PAIRS=100`) | 100 W + 100 R (574 / 574 beats) | 0 | 62.20% | PASS |
| `coverage_max_test` | 108 W + 108 R (598 / 601 beats) | 0 | 85.01% | PASS |
| `axi_stress_test` (`+STRESS_PAIRS=100`) | 120 W + 120 R (639 / 654 beats) | 0 | 85.01% | PASS |

Across the nine runs that is 674 transactions and 3,685 beats checked, with no
mismatches, no UVM warnings, errors or fatals, and no assertion failures. The
two composite runs, `coverage_max_test` and `axi_stress_test`, cover 228 write
and 228 read transactions between them. Per-test detail and the coverage
analysis are in [results/README.md](results/README.md).

---

## 12. Running on EDA Playground

1. Select **SystemVerilog/Verilog**, simulator **Cadence Xcelium 25.03**,
   library **UVM 1.2**.
2. In the **design.sv** pane, paste the RTL in this order:
   `axi_pkg.sv` → `axi_if.sv` → `axi_sva.sv` → `axi_err_slave.sv` →
   `axi_sram.sv` → `axi_fabric.sv` → `soc_top.sv`.
3. In the **testbench.sv** pane, start with a top-level
   `` `include "uvm_macros.svh" `` line, then `tb_pkg.sv` with the ten
   `` `include "axi_*.sv" `` lines replaced by the literal contents of the
   matching files in `tb/`, then `tb_top.sv` with the contents of
   `axi_sva_bind.sv` inlined where its `` `include `` was.
4. Register every remaining referenced file as an *Additional Document*
   (the ⊞ button) so the compiler sees them.
5. Set the run options and press Run.

```text
+UVM_TESTNAME=smoke_test
+UVM_TESTNAME=random_incr_test +RANDOM_PAIRS=100
+UVM_TESTNAME=coverage_max_test
+UVM_TESTNAME=axi_stress_test +STRESS_PAIRS=100 +TIMEOUT_NS=10000000
```

(`axi_stress_test` defaults to 1,000 pairs; the recorded log used 100 pairs
with the raised watchdog to fit the Playground time budget.)

A passing run ends with:

```text
SCOREBOARD: writes=N reads=N mismatches=0
*** TEST PASSED ***
```

With a local simulator:

```sh
xrun rtl/axi_pkg.sv rtl/axi_if.sv rtl/axi_sva.sv rtl/axi_sram.sv \
     rtl/axi_err_slave.sv rtl/axi_fabric.sv rtl/soc_top.sv \
     tb/tb_pkg.sv tb/tb_top.sv \
     -sv -uvm -uvmhome CDNS-1.2 +incdir+rtl +incdir+tb \
     -access +rw -coverage all +UVM_TESTNAME=smoke_test
```

---

## 13. Tools

| Tool / Language | Usage |
| --- | --- |
| SystemVerilog | RTL, interface, assertions |
| UVM 1.2 | Verification methodology |
| Cadence Xcelium 25.03 | Simulation |
| EDA Playground | Online compile/sim environment |

---

## 14. Present Limitations

| Limitation | Note |
| --- | --- |
| One transaction at a time | No outstanding-transaction reordering |
| INCR-focused checking | FIXED/WRAP covered by directed tests only |
| No exclusive access, coherency or low-power | Out of scope |
| SRAM is a simulation model | Not a synthesized memory macro |
| Simulation-verified | No FPGA implementation or STA |

---

## Conclusion

| Result | Value |
| --- | --- |
| Regression runs recorded | 9 tests, all PASS |
| Transactions verified | 674 (3,685 beats) |
| Scoreboard mismatches | 0 |
| UVM warnings / errors / fatals | 0 / 0 / 0 |
| Protocol assertions | 21, active in every test, 0 failures |
| Functional coverage recorded | 85.01% (remaining gap is stimulus-side, see results) |

The environment separates stimulus, driving, monitoring, reference-model
checking, protocol assertions and functional coverage from the AXI4 RTL.

## Documentation

- [Design specification](docs/design_specification.md)
- [Verification plan](docs/verification_plan.md)
