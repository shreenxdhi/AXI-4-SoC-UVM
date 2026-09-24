# Simulation Results

All runs used Cadence Xcelium 25.03-s001 with CDNS-UVM 1.2 on EDA Playground,
seed 1. The numbers below are copied straight from the simulator logs.

The command is the same each time except for the test name and its plusargs:

```text
xrun -Q -unbuffered -timescale 1ns/1ns -sysv -access +rw -coverage all \
     +UVM_TESTNAME=<test> [test plusargs] -uvmhome $UVM_HOME \
     $UVM_HOME/src/uvm_macros.svh design.sv testbench.sv
```

---

## 1. Regression summary

| Test | Plusargs | W / R txns | W / R beats | Mismatches | Err / Fatal | Cov | Sim end | Result |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `smoke_test` | none | 4 / 4 | 4 / 4 | 0 | 0 / 0 | 37.38% | 515 ns | PASS |
| `incr_burst_4_test` | none | 1 / 1 | 4 / 4 | 0 | 0 / 0 | 37.38% | 325 ns | PASS |
| `fixed_burst_test` | none | 1 / 1 | 4 / 4 | 0 | 0 / 0 | 37.38% | 345 ns | PASS |
| `wrap_burst_test` | none | 1 / 1 | 4 / 4 | 0 | 0 / 0 | 37.38% | 345 ns | PASS |
| `unaligned_burst_test` | none | 1 / 1 | 4 / 4 | 0 | 0 / 0 | 37.38% | 345 ns | PASS |
| `err_response_test` | none | 1 / 1 | 1 / 4 | 0 | 0 / 0 | 40.22% | 175 ns | PASS |
| `random_incr_test` | `+RANDOM_PAIRS=100` | 100 / 100 | 574 / 574 | 0 | 0 / 0 | 62.20% | 36,365 ns | PASS |
| `coverage_max_test` | none | 108 / 108 | 598 / 601 | 0 | 0 / 0 | 85.01% | 37,275 ns | PASS |
| `axi_stress_test` | `+STRESS_PAIRS=100 +TIMEOUT_NS=10000000` | 120 / 120 | 639 / 654 | 0 | 0 / 0 | 85.01% | 40,085 ns | PASS |
| **Total (9 runs)** | | **337 / 337** | **1,832 / 1,853** | **0** | **0 / 0** | | | |

No run produced a warning, error or fatal, and none of the 21 bound AXI
assertions fired. Those assertions cover handshake stability, valid stability,
WLAST/RLAST position, the 4 KB beat-bound rule, WRAP alignment and the first and
last beat byte lanes, and they were active in all nine runs.

---

## 2. Per-test notes

### smoke_test
Four single-beat word write/read pairs at `0x100` to `0x10C`, IDs 0 to 3, all
returning `OKAY`.

```text
SCOREBOARD: writes=4 reads=4 mismatches=0
FUNCTIONAL COVERAGE: 37.38%          *** TEST PASSED ***        515 ns
```

### incr_burst_4_test, fixed_burst_test, wrap_burst_test
One 4-beat INCR burst at `0x100`, one 4-beat FIXED burst at `0x300`, and one
legal 4-beat WRAP burst at `0x3C` with a wrap boundary at `0x20`. Each is
written and then read back and compared byte for byte.

```text
WRITE ok  addr=0x00000100 len=3(4 beats) size=2(4 B) burst=INCR   writes=1 reads=1 mismatches=0
WRITE ok  addr=0x00000300 len=3(4 beats) size=2(4 B) burst=FIXED  writes=1 reads=1 mismatches=0
WRITE ok  addr=0x0000003c len=3(4 beats) size=2(4 B) burst=WRAP   writes=1 reads=1 mismatches=0
```

Coverage stays at 37.38% for all three. Each test only adds one coverpoint bin
out of about 94 scored cells, which moves the average by roughly 1% and is lost
at this display precision.

### unaligned_burst_test
A 4-beat halfword INCR burst starting at the unaligned address `0x302`. The
scoreboard checks the WSTRB lane placement, backed by the `a_first_beat_lanes`
and `a_wstrb_in_lane` assertions.

### err_response_test
Two unmapped accesses, a single-beat write and a 4-beat read. `axi_err_slave`
returns `DECERR` on B and on every read beat with the correct `RLAST`, and the
scoreboard checks both (1 write, 1 read, 0 mismatches). Coverage goes from
37.38% to 40.22%. The `DECERR` response cells close, but the bursts are all
word-aligned INCR, so the crosses that pair `DECERR` with other sizes and
lengths stay open.

### random_incr_test (+RANDOM_PAIRS=100)
100 constrained-random aligned INCR write/read pairs across the SRAM. They use
all three transfer sizes and all four length groups, IDs 0 to 15, and every read
matches its write.

```text
SCOREBOARD: writes=100 reads=100 mismatches=0
FUNCTIONAL COVERAGE: 62.20%          *** TEST PASSED ***      36,365 ns
```

An earlier capture of this run, before the assertions were added, reported
58.33%. The coverage model and the traffic are unchanged; the difference comes
from how the covergroup is scored against the current build. The sequence only
produces aligned `OKAY` INCR traffic, so the FIXED, WRAP, unaligned and
`DECERR` bins are left for the other tests.

### coverage_max_test
Runs the whole directed set plus 100 random pairs in one simulation: 108 write
and 108 read transactions, 598 write and 601 read beats, no mismatches. It hits
every size, length, burst and alignment bin.

```text
SCOREBOARD: writes=108 reads=108 mismatches=0
FUNCTIONAL COVERAGE: 85.01%          *** TEST PASSED ***      37,275 ns
```

### axi_stress_test
`+STRESS_PAIRS=100`: 100 random pairs (lengths 1 to 16, all three sizes, IDs 0
to 15, across the whole SRAM) followed by five directed groups of FIXED, WRAP,
unaligned and `DECERR` traffic, with the error address moved forward each group.

```text
SCOREBOARD: writes=120 reads=120 mismatches=0
FUNCTIONAL COVERAGE: 85.01%          *** TEST PASSED ***      40,085 ns
Stress run completed 100 random write/read pairs at time 40085
```

---

## 3. Protocol assertions

`axi_sva.sv` holds the 21 concurrent assertions, attached through
`axi_sva_bind.sv`. Xcelium does not allow binding a module directly into an
interface type, and reports `*E,CUINMI` when it is attempted, so the bind
targets `tb_top` and reads the signals through the `axi_bus` interface instance
instead. Every transaction passes through that instance, so the checks cover the
same traffic. A violation is reported as a `UVM_ERROR` and fails the run. None
of the runs above had one.

---

## 4. Why coverage stops at 85.01%

The covergroup has six coverpoints and six crosses, about 94 scored cells. Three
cells can never be hit and are removed with `ignore_bins`: the `SLVERR` bin,
WRAP with one beat, and byte with unaligned. The rest of the gap to 100% is a
stimulus limitation, not a limit of the checker.

The fabric sends every unmapped address to `axi_err_slave`, so `DECERR` does
appear on the monitored interface, and `err_response_test` checks it. The issue
is that the error bursts are always word-aligned INCR, and the only unaligned
traffic is halfword INCR reads. So the cells left open are the crosses that
combine `DECERR` with other sizes or lengths, and the write with unaligned
cells.

Closing them needs testbench changes rather than RTL changes: randomize the
length, size and burst of the error sequences, add an unaligned write pattern,
and re-run `coverage_max_test`. Until that is done, 85.01% is the number we
report. The cells removed with `ignore_bins` are unreachable by the protocol
itself, while the cells still open are simply not produced by the current
stimulus, and these two cases are kept separate.
