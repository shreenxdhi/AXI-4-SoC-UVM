# Verification Plan

## 1. Verification objective

The testbench checks that the subsystem routes AXI transactions to the correct
target, stores enabled write bytes, returns the expected read data and produces
the required response and end-of-burst signals.

The environment uses UVM so that stimulus generation, signal driving,
monitoring, checking and coverage collection remain separate. This makes it
possible to add tests without changing the DUT or the main checking logic.

## 2. Testbench structure

| Component | Responsibility |
| --- | --- |
| `axi_transaction` | Stores address, ID, direction, burst and payload fields |
| `axi_driver` | Drives the five AXI channels and receives responses |
| `axi_monitor` | Reconstructs completed transfers from bus activity |
| `axi_agent` | Contains the driver, monitor and sequencer |
| `axi_ref_model` | Maintains expected byte-addressable memory contents |
| `axi_scoreboard` | Checks response codes and read data |
| `axi_coverage` | Samples protocol features and cross coverage |
| `axi_env` | Connects the agent, scoreboard and coverage collector |
| `axi_sva` (bound) | Concurrent SVA property checks on every AXI channel of the interface |

## 3. Checking strategy

### 3.1 Write checking

For an SRAM address, the scoreboard expects an `OKAY` write response. After a
successful response, it applies the observed `WSTRB` values and write data to
its reference memory.

For a peripheral-placeholder or unmapped address, it expects `DECERR` and does
not update the reference memory.

### 3.2 Read checking

For each SRAM read beat, the scoreboard calculates the beat address and obtains
the expected 32-bit value from the reference memory. It compares this value
with the monitored `RDATA` and expects an `OKAY` response.

For an address outside SRAM, every returned beat must contain `DECERR`.

### 3.3 Protocol checks

The driver and monitor check:

- `BID` against the write transaction ID
- `RID` against the read transaction ID
- `WLAST` only on the final write beat
- `RLAST` only on the final read beat

In addition, `rtl/axi_sva.sv` provides 21 concurrent assertions attached to
every `axi_if` instance through the `bind` statement in
`rtl/axi_sva_bind.sv`, so no RTL or interface code is modified:

| Group | Checked rules |
| --- | --- |
| Handshake stability | AW, AR, W, B and R payloads remain unchanged while VALID is high and READY is low; VALID is not dropped before the handshake |
| Burst legality | Burst type never the reserved `2'b11`; WRAP only with 2/4/8/16 beats; WRAP start address aligned to the transfer size |
| Byte lanes | `WSTRB` never all-zero; first-beat strobes respect the address byte offset (unaligned rule); aligned first beat stays inside its natural byte window |
| Beat counting | Write and read beats never exceed `LEN+1`; `WLAST`/`RLAST` asserted exactly on the final beat |
| Response sanity | No `BVALID`/`RVALID` without an outstanding request; responses restricted to `OKAY`/`DECERR` |

Assertion failures are reported through `uvm_error`, so they raise the
`UVM_ERROR` count and fail the test verdict.

The global watchdog ends the test with a fatal error if a handshake problem
causes the simulation to stop progressing. Its limit defaults to 2 ms and can
be overridden with `+TIMEOUT_NS=<ns>` for very long stress runs.

## 4. Test plan

| Requirement | Test | Expected result | Status |
| --- | --- | --- | --- |
| Single-beat word access | `smoke_test` | Four write/read pairs pass | Run and passed |
| Four-beat INCR transfer | `incr_burst_4_test` | Data and response checks pass | Available |
| Eight-beat INCR transfer | `incr_burst_8_test` | Data and response checks pass | Available |
| Sixteen-beat INCR transfer | `incr_burst_16_test` | Data and response checks pass | Available |
| Byte-lane operation | `incr_byte_burst_test` | Enabled byte values are retained | Available |
| Halfword operation | `incr_halfword_burst_test` | Enabled halfwords are retained | Available |
| Word operation | `incr_word_burst_test` | Full words are retained | Available |
| Random address, size and length | `random_incr_test` | All paired reads match writes | Run and passed |
| FIXED burst operation | `fixed_burst_test` | Every beat reads from the same address | Available |
| WRAP burst operation | `wrap_burst_test` | Beat addresses wrap inside the aligned 4-beat window | Available |
| Unaligned transfer | `unaligned_burst_test` | Byte lanes are retained across unaligned beats | Available |
| Peripheral `DECERR` | `err_response_test` | Write and read return `DECERR` | Available |
| Unmapped-address `DECERR` | Future directed test | Write and read return `DECERR` | Planned |
| Long-duration endurance | `axi_stress_test` | 1,000 random pairs plus directed markers, zero mismatches, all SVA checks hold | Available |
| Full coverage regression | `coverage_max_test` | Directed plus random mix, zero mismatches | Available |


“Available” means that the test is present in the source. It is not marked as
completed here until its simulator output has been saved and reviewed.

## 5. Functional coverage model

The coverage collector samples each completed transaction.

| Coverpoint | Bins |
| --- | --- |
| Operation | Read, write |
| Burst | FIXED, INCR, WRAP |
| Transfer size | Byte, halfword, word |
| Burst length | 1, 2–4, 5–8, 9–16 beats |
| Alignment | Aligned, unaligned |
| Response | `OKAY`, `DECERR` (`SLVERR` unreachable, `ignore_bins`) |

The following crosses are collected (with the architecturally unreachable
`WRAP`×1-beat and `byte`×unaligned cells excluded):

- Burst type × transfer size
- Burst type × burst length
- Operation × burst type
- Operation × transfer size
- Transfer size × alignment
- Operation × response

Coverage is used to show which combinations were exercised. A passing test and
high coverage measure different things: the scoreboard determines whether the
observed behaviour is correct, while coverage shows the breadth of stimulus.

## 6. Recorded smoke-test result

The supplied EDA Playground log records the following run:

| Item | Recorded value |
| --- | --- |
| Simulator | Cadence Xcelium 25.03-s001 |
| UVM library | CDNS-UVM 1.2 |
| Test | `smoke_test` |
| Seed | 1 |
| Simulation end time | 515 ns |
| Writes checked | 4 |
| Reads checked | 4 |
| Write beats | 4 |
| Read beats | 4 |
| Data mismatches | 0 |
| Response mismatches | 0 |
| Functional coverage | 34.26% |
| UVM warnings/errors/fatals | 0 / 0 / 0 |
| Overall result | Pass |

## 7. Recorded random-test result

The 100-pair constrained-random run used aligned INCR transactions within the
SRAM region. Transfer size, burst length, address and transaction ID varied
across the run.

| Item | Recorded value |
| --- | --- |
| Simulator | Cadence Xcelium 25.03-s001 |
| UVM library | CDNS-UVM 1.2 |
| Test | `random_incr_test` |
| Random pairs | 100 |
| Seed | 1 |
| Simulation end time | 36,365 ns |
| Writes checked | 100 |
| Reads checked | 100 |
| Write beats | 574 |
| Read beats | 574 |
| Data mismatches | 0 |
| Response mismatches | 0 |
| Functional coverage | 62.20% |
| UVM warnings/errors/fatals | 0 / 0 / 0 |
| Overall result | Pass |

This run covers all three supported transfer sizes and all four burst-length
groups. Coverage remains below 100% because the sequence intentionally
generates only aligned SRAM accesses with INCR bursts and `OKAY` responses.
FIXED, WRAP, unaligned and error-response bins are therefore not covered by
this test.

The directed tests `fixed_burst_test`, `wrap_burst_test`,
`unaligned_burst_test` and `err_response_test` were added to close exactly
those remaining bins, and all four have since been recorded as passing runs
on Xcelium. `coverage_max_test`, which replays the whole mix in one
simulation, recorded 85.01% functional coverage with zero mismatches and
zero assertion failures. The residual gap is a stimulus-side limitation
(error bursts are generated only as word-aligned INCR), analyzed in
[results/README.md](../results/README.md).

## 8. Regression procedure

For each test:

1. Select Cadence Xcelium 25.03 and UVM 1.2 in EDA Playground.
2. Run with `-access +rw -coverage all` and the required `UVM_TESTNAME`.
3. Confirm that the scoreboard reports zero mismatches.
4. Confirm that `UVM_ERROR` and `UVM_FATAL` are zero.
5. Record the random seed and coverage percentage.
6. Save the complete simulator output before starting the next run.

Random tests should be repeated with several seeds. Results must be recorded
from actual runs rather than inferred from a single successful simulation.

## 9. Completion criteria

A test is considered passed when:

- the sequence completes before the watchdog timeout;
- the scoreboard reports no data or response mismatch;
- no `axi_sva` assertion fires;
- the UVM summary reports zero errors and fatals; and
- the expected transactions appear in the scoreboard counts.

Warnings from the simulator's coverage instrumentation should be reviewed
separately from UVM protocol and data-checking failures.
