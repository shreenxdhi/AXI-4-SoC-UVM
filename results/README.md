# Simulation Results

## Smoke test

The recorded run was performed on EDA Playground using Cadence Xcelium
25.03-s001 and CDNS-UVM 1.2. The simulator used its default seed of 1.

```text
Test                    smoke_test
Simulation time         515 ns
Writes checked          4
Reads checked           4
Write beats             4
Read beats              4
Data mismatches         0
Response mismatches     0
Functional coverage     34.26%
UVM warnings            0
UVM errors              0
UVM fatals              0
Result                  PASS
```

The four word writes used addresses `0x00000100`, `0x00000104`,
`0x00000108` and `0x0000010C`. Each write was followed by a read from the same
address. All eight transactions received the expected response, and the four
read values matched the scoreboard's reference memory.

Xcelium printed several informational coverage warnings during elaboration.
These concern default coverage-tool settings, such as toggle scoring for
integer and multidimensional-array objects. They are not UVM failures and did
not affect the scoreboard result.

## Interpretation

The smoke test establishes that basic aligned word writes and reads work
through the fabric and SRAM. It also exercises transaction IDs from 0 to 3.
It does not by itself prove the byte, halfword, long-burst, random or error
response cases. Those tests should be run separately and added here only after
their logs have been checked.

## Reproduction

Use the following EDA Playground run options:

```text
-access +rw -coverage all +UVM_TESTNAME=smoke_test
```

The expected final report contains:

```text
SCOREBOARD: writes=4 reads=4 mismatches=0
FUNCTIONAL COVERAGE: 34.26%
*** TEST PASSED ***
UVM_WARNING : 0
UVM_ERROR   : 0
UVM_FATAL   : 0
```

## Random INCR test

The constrained-random test was run with 100 write/read pairs using the
default seed of 1. Every write was followed by a read using the same address,
ID, burst length and transfer size.

```text
Test                    random_incr_test
Random pairs            100
Seed                    1
Simulation time         36,365 ns
Writes checked          100
Reads checked           100
Write beats             574
Read beats              574
Data mismatches         0
Response mismatches     0
Functional coverage     58.33%
UVM warnings            0
UVM errors              0
UVM fatals              0
Result                  PASS
```

The run exercised byte, halfword and word transfers with burst lengths from
one to sixteen beats. All generated addresses were aligned and remained
inside the SRAM range.

Use the following EDA Playground options to reproduce this run:

```text
-access +rw -coverage all +UVM_TESTNAME=random_incr_test +RANDOM_PAIRS=100
```

The final report should contain:

```text
SCOREBOARD: writes=100 reads=100 mismatches=0
FUNCTIONAL COVERAGE: 58.33%
*** TEST PASSED ***
UVM_WARNING : 0
UVM_ERROR   : 0
UVM_FATAL   : 0
```
