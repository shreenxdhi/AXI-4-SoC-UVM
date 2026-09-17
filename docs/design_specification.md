# Design Specification

## 1. Purpose

The design is a simplified AXI4 memory subsystem intended for studying address
decoding, burst transfers, byte enables and response handling. It contains one
AXI master-facing port, a small routing fabric, a 64 KB SRAM model and two
error-response targets.

The project is simulation-oriented. Its main purpose is to provide a design
that is large enough to verify using a complete UVM environment while keeping
the RTL understandable and demonstrable within an undergraduate project.

## 2. Interface configuration

| Parameter | Value |
| --- | ---: |
| Address width | 32 bits |
| Data width | 32 bits |
| Strobe width | 4 bits |
| ID width | 4 bits |
| Maximum tested burst length | 16 beats |
| Supported transfer sizes | 1, 2 and 4 bytes |

The interface contains the five AXI channels: write address, write data, write
response, read address and read data. Each channel uses the standard
`VALID/READY` handshake. A transfer takes place on a rising clock edge when
both signals are asserted.

## 3. Address map

| Target | Start address | End address | Response |
| --- | --- | --- | --- |
| SRAM | `0x0000_0000` | `0x0000_FFFF` | `OKAY` |
| Peripheral placeholder | `0x1000_0000` | `0x1000_0FFF` | `DECERR` |
| Error target | All remaining addresses | — | `DECERR` |

The peripheral range is reserved to demonstrate address decoding. In the
current implementation it is connected to an error responder and does not
provide functional registers.

## 4. Design blocks

### 4.1 AXI package

`axi_pkg` holds the bus parameters, response and burst enumerations, memory-map
constants and address helper functions. Keeping these definitions in one
package avoids repeating protocol values in the RTL and testbench.

`decode_addr()` selects the target from the start address. `lane_base()` finds
the beginning of the current 32-bit data lane. `beat_addr()` calculates the
address of an individual burst beat.

### 4.2 AXI interface

`axi_if` groups the five AXI channels into a single SystemVerilog interface.
Master and slave modports specify the direction of each signal. The design and
UVM driver therefore share one consistent signal definition.

### 4.3 SRAM slave

`axi_sram` models 65,536 byte locations. Memory is initialized to zero so that
reads from unwritten locations return a deterministic value.

The write path stores the address attributes after an AW handshake and accepts
the required number of W beats. Each asserted bit in `WSTRB` enables one byte
of `WDATA`. A write response is produced after the final beat.

The read path stores the address attributes after an AR handshake and returns
one data beat at a time. `RLAST` is asserted on the final requested beat.

A 16-bit linear-feedback shift register supplies small response delays. This
introduces changes in `READY` and `VALID` timing so that the testbench does not
depend on zero-wait-state behaviour.

### 4.4 Error responder

`axi_err_slave` accepts a complete read or write transaction and returns
`DECERR`. For writes, it consumes data until `WLAST` before producing the B
response. For reads, it returns the requested number of zero-valued data beats
and asserts `RLAST` on the final beat.

### 4.5 Routing fabric

`axi_fabric` decodes AW and AR addresses independently. Write and read traffic
can therefore progress through their separate channel paths.

The selected write target is saved when the AW handshake occurs. This saved
selection is used for the W channel and later for the B response. Similarly,
the selected read target is saved during the AR handshake and retained while
the R beats are returned.

This implementation assumes a single active transaction on each path. It does
not contain the queues or ID tracking needed for multiple outstanding
transactions.

### 4.6 Top level

`soc_top` connects the fabric to three targets:

1. SRAM target for addresses from `0x0000_0000` to `0x0000_FFFF`.
2. Peripheral placeholder, currently implemented as a `DECERR` responder.
3. Default error responder for all unmapped addresses.

## 5. Burst and byte-lane behaviour

An INCR burst advances by the number of bytes specified by `AxSIZE`. For a
four-byte transfer, successive beat addresses increase by four. Byte and
halfword transfers advance by one and two bytes respectively.

The SRAM is byte-addressable. During a write, `WSTRB[0]` controls bits 7:0 of
`WDATA`, `WSTRB[1]` controls bits 15:8, and so on. Disabled lanes keep their
previous memory contents.

Although helper code includes FIXED and WRAP address calculations, the current
verification work concentrates on aligned INCR traffic.

## 6. Reset behaviour

Reset is active low through `aresetn`. During reset, the slave state machines
return to their idle states, channel handshakes are disabled and saved IDs and
burst counters are cleared. The testbench holds reset low for five rising clock
edges before beginning UVM stimulus.

## 7. Design limitations

- One active transaction per read or write path
- No transaction reordering
- No exclusive-access support
- No cache-coherency support
- No functional peripheral registers
- No clock-domain crossing or low-power logic
- Simulation SRAM rather than implementation-specific memory
- No synthesis or timing-closure results

These are deliberate scope limits. They allow the project to concentrate on
protocol handshakes, data movement and verification methodology.
