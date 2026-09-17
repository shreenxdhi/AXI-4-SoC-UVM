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

The global watchdog ends the test with a fatal error if a handshake problem
causes the simulation to stop progressing.

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
| Random address, size and length | `random_incr_test` | All paired reads match writes | Available |
| Peripheral `DECERR` | Future directed test | Write and read return `DECERR` | Planned |
| Unmapped-address `DECERR` | Future directed test | Write and read return `DECERR` | Planned |

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
| Response | `OKAY`, `SLVERR`, `DECERR` |

The following crosses are collected:

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

The 34.26% result is reasonable for a smoke test because it uses only aligned,
single-beat, word-sized INCR traffic with `OKAY` responses. Other burst sizes,
length groups, alignment cases and response types remain uncovered.

## 7. Regression procedure

For each test:

1. Select Cadence Xcelium 25.03 and UVM 1.2 in EDA Playground.
2. Run with `-access +rw -coverage all` and the required `UVM_TESTNAME`.
3. Confirm that the scoreboard reports zero mismatches.
4. Confirm that `UVM_ERROR` and `UVM_FATAL` are zero.
5. Record the random seed and coverage percentage.
6. Save the complete simulator output before starting the next run.

Random tests should be repeated with several seeds. Results must be recorded
from actual runs rather than inferred from a single successful simulation.

## 8. Completion criteria

A test is considered passed when:

- the sequence completes before the watchdog timeout;
- the scoreboard reports no data or response mismatch;
- the UVM summary reports zero errors and fatals; and
- the expected transactions appear in the scoreboard counts.

Warnings from the simulator's coverage instrumentation should be reviewed
separately from UVM protocol and data-checking failures.
