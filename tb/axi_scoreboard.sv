import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_scoreboard extends uvm_scoreboard;

  axi_ref_model ref_model;
  uvm_analysis_imp #(axi_transaction, axi_scoreboard) ap_imp;

  int unsigned n_writes, n_reads;
  int unsigned n_write_beats, n_read_beats;
  int unsigned n_data_mismatch, n_resp_mismatch;

  `uvm_component_utils(axi_scoreboard)

  function new(string name = "axi_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    ap_imp = new("ap_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ref_model = axi_ref_model::type_id::create("ref_model", this);
  endfunction

  function void write(axi_transaction tr);
    if (tr.dir == axi_transaction::AXI_WRITE) check_write(tr);
    else                                      check_read(tr);
  endfunction

  function void check_write(axi_transaction tr);
    slave_t target = decode_addr(tr.addr);
    string resp_str;
    n_writes++;
    n_write_beats += tr.num_beats();
    if (target == SLV_SRAM) begin
      resp_str = (tr.bresp == RESP_OKAY)   ? "OKAY"   :
                 (tr.bresp == RESP_SLVERR) ? "SLVERR" :
                 (tr.bresp == RESP_DECERR) ? "DECERR" : "EXOKAY";
      if (tr.bresp !== RESP_OKAY) begin
        `uvm_error(get_type_name(),
          $sformatf({"RESPONSE_MISMATCH\n",
                     "id=%0d burst=%s start_addr=0x%08h\n",
                     "expected=OKAY actual=%s"},
                    tr.id, burst_to_string(tr.burst), tr.addr, resp_str))
        n_resp_mismatch++;
      end
      else begin
        ref_model.apply_write(tr);
        `uvm_info(get_type_name(),
          $sformatf("WRITE ok  %s", tr.convert2string()), UVM_MEDIUM)
      end
    end
    else begin
      resp_str = (tr.bresp == RESP_OKAY)   ? "OKAY"   :
                 (tr.bresp == RESP_SLVERR) ? "SLVERR" :
                 (tr.bresp == RESP_DECERR) ? "DECERR" : "EXOKAY";
      if (tr.bresp !== RESP_DECERR) begin
        `uvm_error(get_type_name(),
          $sformatf({"RESPONSE_MISMATCH\n",
                     "id=%0d burst=%s start_addr=0x%08h\n",
                     "expected=DECERR actual=%s"},
                    tr.id, burst_to_string(tr.burst), tr.addr, resp_str))
        n_resp_mismatch++;
      end
    end
  endfunction

  function void check_read(axi_transaction tr);
    slave_t target = decode_addr(tr.addr);
    string resp_str;
    n_reads++;
    n_read_beats += tr.num_beats();
    if (target != SLV_SRAM) begin
      foreach (tr.rresp[i]) begin
        resp_str = (tr.rresp[i] == RESP_OKAY)   ? "OKAY"   :
                   (tr.rresp[i] == RESP_SLVERR) ? "SLVERR" :
                   (tr.rresp[i] == RESP_DECERR) ? "DECERR" : "EXOKAY";
        if (tr.rresp[i] !== RESP_DECERR) begin
          `uvm_error(get_type_name(),
            $sformatf({"RESPONSE_MISMATCH\n",
                       "id=%0d burst=%s start_addr=0x%08h beat=%0d ",
                       "beat_addr=0x%08h\nexpected=DECERR actual=%s"},
                      tr.id, burst_to_string(tr.burst), tr.addr, i,
                      tr.get_beat_addr(i), resp_str))
          n_resp_mismatch++;
        end
      end
      return;
    end

    for (int beat = 0; beat < tr.num_beats(); beat++) begin
      bit [AXI_ADDR_W-1:0] ba  = tr.get_beat_addr(beat);
      bit [AXI_DATA_W-1:0] exp = ref_model.predict_read(ba);
      resp_str = (tr.rresp[beat] == RESP_OKAY)   ? "OKAY"   :
                 (tr.rresp[beat] == RESP_SLVERR) ? "SLVERR" :
                 (tr.rresp[beat] == RESP_DECERR) ? "DECERR" : "EXOKAY";
      if (tr.rresp[beat] !== RESP_OKAY) begin
        `uvm_error(get_type_name(),
          $sformatf({"RESPONSE_MISMATCH\n",
                     "id=%0d burst=%s start_addr=0x%08h beat=%0d ",
                     "beat_addr=0x%08h\nexpected=OKAY actual=%s"},
                    tr.id, burst_to_string(tr.burst), tr.addr, beat, ba,
                    resp_str))
        n_resp_mismatch++;
      end
      else if (tr.rdata[beat] !== exp) begin
        `uvm_error(get_type_name(),
          $sformatf({"DATA_MISMATCH\n",
                     "id=%0d burst=%s start_addr=0x%08h beat=%0d ",
                     "beat_addr=0x%08h\nexpected=0x%08h actual=0x%08h ",
                     "response=%s"},
                    tr.id, burst_to_string(tr.burst), tr.addr, beat, ba,
                    exp, tr.rdata[beat], resp_str))
        n_data_mismatch++;
      end
    end

    `uvm_info(get_type_name(),
      $sformatf("READ done %s", tr.convert2string()), UVM_MEDIUM)
  endfunction

  function string burst_to_string(burst_t burst);
    case (burst)
      BURST_FIXED: return "FIXED";
      BURST_INCR : return "INCR";
      BURST_WRAP : return "WRAP";
      default    : return "RSVD";
    endcase
  endfunction

  function int unsigned total_mismatches();
    return n_data_mismatch + n_resp_mismatch;
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf({

      "\n## AXI SCOREBOARD\n",
      "Writes checked      : %0d\n",
      "Reads checked       : %0d\n",
      "Write beats         : %0d\n",
      "Read beats          : %0d\n",
      "Data mismatches     : %0d\n",
      "Response mismatches : %0d\n",
      "-----------------------\n",
      "SCOREBOARD: writes=%0d reads=%0d mismatches=%0d"},
      n_writes, n_reads, n_write_beats, n_read_beats,
      n_data_mismatch, n_resp_mismatch,
      n_writes, n_reads, total_mismatches()), UVM_NONE)
  endfunction

endclass : axi_scoreboard
