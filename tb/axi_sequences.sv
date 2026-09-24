import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;
class axi_base_seq extends uvm_sequence #(axi_transaction);
  `uvm_object_utils(axi_base_seq)
  function new(string name = "axi_base_seq"); super.new(name); endfunction
endclass

class axi_single_write_seq extends axi_base_seq;
  `uvm_object_utils(axi_single_write_seq)

  bit [AXI_ADDR_W-1:0] m_addr = SRAM_BASE;
  bit [AXI_DATA_W-1:0] m_data = 32'hDEAD_BEEF;
  bit [AXI_ID_W-1:0]   m_id   = '0;

  function new(string name = "axi_single_write_seq"); super.new(name); endfunction

  task body();
    axi_transaction tr = axi_transaction::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize() with {
          dir   == axi_transaction::AXI_WRITE;
          addr  == m_addr;
          id    == m_id;
          len   == 0;
          size  == 2;
          burst == BURST_INCR;
        })
      `uvm_fatal("RANDFAIL", "single write randomize failed")
    tr.data[0] = m_data;
    finish_item(tr);
  endtask
endclass

class axi_single_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_single_read_seq)

  bit [AXI_ADDR_W-1:0] m_addr = SRAM_BASE;
  bit [AXI_ID_W-1:0]   m_id   = '0;

  function new(string name = "axi_single_read_seq"); super.new(name); endfunction

  task body();
    axi_transaction tr = axi_transaction::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize() with {
          dir   == axi_transaction::AXI_READ;
          addr  == m_addr;
          id    == m_id;
          len   == 0;
          size  == 2;
          burst == BURST_INCR;
        })
      `uvm_fatal("RANDFAIL", "single read randomize failed")
    finish_item(tr);
  endtask
endclass

class axi_write_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_write_read_seq)

  int unsigned n_pairs = 4;

  function new(string name = "axi_write_read_seq"); super.new(name); endfunction

  task body();
    for (int i = 0; i < n_pairs; i++) begin
      bit [AXI_ADDR_W-1:0] a = SRAM_BASE + 32'h0100 + (i * 4);
      bit [AXI_DATA_W-1:0] d = 32'hA5A5_0000 + i;
      axi_transaction wr = axi_transaction::type_id::create("wr");
      axi_transaction rd = axi_transaction::type_id::create("rd");
      start_item(wr);
      if (!wr.randomize() with {
            dir == axi_transaction::AXI_WRITE; addr == a; id == i;
            len == 0; size == 2; burst == BURST_INCR;
          }) `uvm_fatal("RANDFAIL", "smoke write randomize failed")
      wr.data[0] = d;
      finish_item(wr);
      start_item(rd);
      if (!rd.randomize() with {
            dir == axi_transaction::AXI_READ; addr == a; id == i;
            len == 0; size == 2; burst == BURST_INCR;
          }) `uvm_fatal("RANDFAIL", "smoke read randomize failed")
      finish_item(rd);
    end
  endtask
endclass


class axi_incr_write_seq extends axi_base_seq;
  `uvm_object_utils(axi_incr_write_seq)

  bit [AXI_ADDR_W-1:0] start_addr    = SRAM_BASE + 32'h0100;
  int unsigned         burst_length = 4;
  bit [2:0]            transfer_size = 2;
  bit [AXI_ID_W-1:0]   axi_id        = '0;
  bit [AXI_DATA_W-1:0] payload[];

  function new(string name = "axi_incr_write_seq"); super.new(name); endfunction

  task body();
    axi_transaction tr = axi_transaction::type_id::create("tr");
    if (burst_length < 1 || burst_length > 16)
      `uvm_fatal("BAD_BURST_LENGTH",
        $sformatf("INCR burst_length must be 1..16, got %0d", burst_length))
    if (transfer_size > 2)
      `uvm_fatal("BAD_TRANSFER_SIZE",
        $sformatf("transfer_size must be 0..2, got %0d", transfer_size))
    if (payload.size() != 0 && payload.size() != burst_length)
      `uvm_fatal("BAD_PAYLOAD",
        $sformatf("payload has %0d elements; expected %0d",
                  payload.size(), burst_length))

    start_item(tr);
    if (!tr.randomize() with {
          dir   == axi_transaction::AXI_WRITE;
          addr  == local::start_addr;
          id    == local::axi_id;
          len   == local::burst_length - 1;
          size  == local::transfer_size;
          burst == BURST_INCR;
        })
      `uvm_fatal("RANDFAIL", "INCR write randomize failed")
    if (payload.size() == burst_length)
      foreach (tr.data[i]) tr.data[i] = payload[i];
    else
      foreach (tr.data[i]) tr.data[i] = 32'hA000_0000 |
                                             (axi_id << 16) | i;
    finish_item(tr);
  endtask
endclass : axi_incr_write_seq


class axi_incr_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_incr_read_seq)

  bit [AXI_ADDR_W-1:0] start_addr     = SRAM_BASE + 32'h0100;
  int unsigned         burst_length  = 4;
  bit [2:0]            transfer_size = 2;
  bit [AXI_ID_W-1:0]   axi_id        = '0;

  function new(string name = "axi_incr_read_seq"); super.new(name); endfunction

  task body();
    axi_transaction tr = axi_transaction::type_id::create("tr");
    if (burst_length < 1 || burst_length > 16)
      `uvm_fatal("BAD_BURST_LENGTH",
        $sformatf("INCR burst_length must be 1..16, got %0d", burst_length))
    if (transfer_size > 2)
      `uvm_fatal("BAD_TRANSFER_SIZE",
        $sformatf("transfer_size must be 0..2, got %0d", transfer_size))
    start_item(tr);
    if (!tr.randomize() with {
          dir   == axi_transaction::AXI_READ;
          addr  == local::start_addr;
          id    == local::axi_id;
          len   == local::burst_length - 1;
          size  == local::transfer_size;
          burst == BURST_INCR;
        })
      `uvm_fatal("RANDFAIL", "INCR read randomize failed")
    finish_item(tr);
  endtask
endclass : axi_incr_read_seq


class axi_incr_write_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_incr_write_read_seq)

  bit [AXI_ADDR_W-1:0] start_addr     = SRAM_BASE + 32'h0100;
  int unsigned         burst_length  = 4;
  bit [2:0]            transfer_size = 2;
  bit [AXI_ID_W-1:0]   axi_id        = '0;
  bit [AXI_DATA_W-1:0] payload[];

  function new(string name = "axi_incr_write_read_seq"); super.new(name); endfunction

  task body();
    axi_incr_write_seq wr_seq;
    axi_incr_read_seq  rd_seq;

    if (transfer_size <= 2 && (start_addr % (1 << transfer_size)) == 0) begin
      for (int beat = 0; beat < burst_length; beat++) begin
        bit [AXI_ADDR_W-1:0] expected = start_addr + (beat << transfer_size);
        bit [AXI_ADDR_W-1:0] actual = beat_addr(start_addr,
          burst_length - 1, transfer_size, BURST_INCR, beat);
        if (actual != expected)
          `uvm_fatal("BEAT_ADDR",
            $sformatf("beat_addr mismatch beat=%0d expected=0x%08h actual=0x%08h",
                      beat, expected, actual))
      end
    end

    wr_seq = axi_incr_write_seq::type_id::create("wr_seq");
    wr_seq.start_addr     = start_addr;
    wr_seq.burst_length  = burst_length;
    wr_seq.transfer_size = transfer_size;
    wr_seq.axi_id        = axi_id;
    wr_seq.payload       = payload;
    wr_seq.start(m_sequencer);

    rd_seq = axi_incr_read_seq::type_id::create("rd_seq");
    rd_seq.start_addr     = start_addr;
    rd_seq.burst_length  = burst_length;
    rd_seq.transfer_size = transfer_size;
    rd_seq.axi_id        = axi_id;
    rd_seq.start(m_sequencer);
  endtask
endclass : axi_incr_write_read_seq


class axi_random_incr_seq extends axi_base_seq;
  `uvm_object_utils(axi_random_incr_seq)

  int unsigned num_transactions = 50;

  function new(string name = "axi_random_incr_seq"); super.new(name); endfunction

  task body();
    for (int pair = 0; pair < num_transactions; pair++) begin
      axi_transaction wr = axi_transaction::type_id::create("wr");
      axi_transaction rd = axi_transaction::type_id::create("rd");
      int unsigned chosen_size = $urandom_range(2, 0);
      int unsigned chosen_len;
      case (pair % 4)
        0: chosen_len = 0;
        1: chosen_len = $urandom_range(3, 1);
        2: chosen_len = $urandom_range(7, 4);
        default: chosen_len = $urandom_range(15, 8);
      endcase

      start_item(wr);
      if (!wr.randomize() with {
            dir   == axi_transaction::AXI_WRITE;
            burst == BURST_INCR;
            size  == local::chosen_size;
            len   == local::chosen_len;
            addr inside {[SRAM_BASE : SRAM_BASE + SRAM_SIZE - 1]};
            (addr % (1 << size)) == 0;
            (addr + ((len + 1) << size)) <= (SRAM_BASE + SRAM_SIZE);
          })
        `uvm_fatal("RANDFAIL", "random INCR write randomize failed")
      finish_item(wr);

      start_item(rd);
      if (!rd.randomize() with {
            dir   == axi_transaction::AXI_READ;
            burst == BURST_INCR;
            addr  == wr.addr;
            id    == wr.id;
            len   == wr.len;
            size  == wr.size;
          })
        `uvm_fatal("RANDFAIL", "matching random INCR read randomize failed")
      finish_item(rd);
    end
  endtask
endclass : axi_random_incr_seq


class axi_burst_write_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_burst_write_read_seq)

  burst_t              m_burst       = BURST_INCR;
  bit [AXI_ADDR_W-1:0] start_addr    = SRAM_BASE + 32'h0300;
  int unsigned         burst_length  = 4;
  bit [2:0]            transfer_size = 2;
  bit [AXI_ID_W-1:0]   axi_id        = '0;

  function new(string name = "axi_burst_write_read_seq"); super.new(name); endfunction

  task body();
    axi_transaction wr = axi_transaction::type_id::create("wr");
    axi_transaction rd = axi_transaction::type_id::create("rd");

    if (burst_length < 1 || burst_length > 16)
      `uvm_fatal("BAD_BURST_LENGTH",
        $sformatf("burst_length must be 1..16, got %0d", burst_length))
    if (transfer_size > 2)
      `uvm_fatal("BAD_TRANSFER_SIZE",
        $sformatf("transfer_size must be 0..2, got %0d", transfer_size))
    if (m_burst == BURST_WRAP &&
        !(burst_length inside {2, 4, 8, 16}))
      `uvm_fatal("BAD_WRAP_LENGTH",
        $sformatf("WRAP burst_length must be 2, 4, 8 or 16, got %0d",
                  burst_length))

    start_item(wr);
    if (!wr.randomize() with {
          dir   == axi_transaction::AXI_WRITE;
          addr  == local::start_addr;
          id    == local::axi_id;
          len   == local::burst_length - 1;
          size  == local::transfer_size;
          burst == local::m_burst;
        })
      `uvm_fatal("RANDFAIL", "burst write randomize failed")
    foreach (wr.data[i]) wr.data[i] = 32'hB000_0000 | (axi_id << 16) | i;
    finish_item(wr);

    start_item(rd);
    if (!rd.randomize() with {
          dir   == axi_transaction::AXI_READ;
          addr  == local::start_addr;
          id    == local::axi_id;
          len   == local::burst_length - 1;
          size  == local::transfer_size;
          burst == local::m_burst;
        })
      `uvm_fatal("RANDFAIL", "burst read randomize failed")
    finish_item(rd);
  endtask
endclass : axi_burst_write_read_seq


class axi_unaligned_write_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_unaligned_write_read_seq)

  bit [AXI_ADDR_W-1:0] start_addr = SRAM_BASE + 32'h0302;
  int unsigned         burst_length = 4;
  bit [2:0]            transfer_size = 1;
  bit [AXI_ID_W-1:0]   axi_id        = '0;

  function new(string name = "axi_unaligned_write_read_seq");
    super.new(name);
  endfunction

  task body();
    axi_transaction wr = axi_transaction::type_id::create("wr");
    axi_transaction rd = axi_transaction::type_id::create("rd");

    if (transfer_size == 0)
      `uvm_fatal("BAD_TRANSFER_SIZE",
        "unaligned sequences require size 1 or 2")

    start_item(wr);
    if (!wr.randomize() with {
          dir   == axi_transaction::AXI_WRITE;
          addr  == local::start_addr;
          id    == local::axi_id;
          len   == local::burst_length - 1;
          size  == local::transfer_size;
          burst == BURST_INCR;
        })
      `uvm_fatal("RANDFAIL", "unaligned write randomize failed")
    foreach (wr.data[i])
      wr.data[i] = 32'hC000_0000 | (i << 8) | (i + 1);
    finish_item(wr);

    start_item(rd);
    if (!rd.randomize() with {
          dir   == axi_transaction::AXI_READ;
          addr  == local::start_addr;
          id    == local::axi_id;
          len   == local::burst_length - 1;
          size  == local::transfer_size;
          burst == BURST_INCR;
        })
      `uvm_fatal("RANDFAIL", "unaligned read randomize failed")
    finish_item(rd);
  endtask
endclass : axi_unaligned_write_read_seq


class axi_err_write_seq extends axi_base_seq;
  `uvm_object_utils(axi_err_write_seq)

  bit [AXI_ADDR_W-1:0] m_addr = PERIPH_BASE;

  function new(string name = "axi_err_write_seq"); super.new(name); endfunction

  task body();
    axi_transaction tr = axi_transaction::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize() with {
          dir   == axi_transaction::AXI_WRITE;
          addr  == local::m_addr;
          len   == 0;
          size  == 2;
          burst == BURST_INCR;
        })
      `uvm_fatal("RANDFAIL", "DECERR write randomize failed")
    tr.data[0] = 32'hE000_0001;
    finish_item(tr);
  endtask
endclass : axi_err_write_seq


class axi_err_read_seq extends axi_base_seq;
  `uvm_object_utils(axi_err_read_seq)

  bit [AXI_ADDR_W-1:0] m_addr     = PERIPH_BASE;
  int unsigned         burst_length = 4;

  function new(string name = "axi_err_read_seq"); super.new(name); endfunction

  task body();
    axi_transaction tr = axi_transaction::type_id::create("tr");
    start_item(tr);
    if (!tr.randomize() with {
          dir   == axi_transaction::AXI_READ;
          addr  == local::m_addr;
          len   == local::burst_length - 1;
          size  == 2;
          burst == BURST_INCR;
        })
      `uvm_fatal("RANDFAIL", "DECERR read randomize failed")
    finish_item(tr);
  endtask
endclass : axi_err_read_seq
