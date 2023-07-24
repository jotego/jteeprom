/*  This file is part of JTEEPROM.
    JTEEPROM program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTEEPROM program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTEEPROM.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 21-3-2020 */

// Module compatible with Microchip ER5911

module jt5911 #( parameter
    PROG=0, // 0 = 128x8bit, 1 = 64x16 bit. Pin in the original chip
localparam
    AW= PROG ?  5 : 6,   // Memory address bits
    DW= PROG ? 16 : 8    // Data width
) (
    input           rst,        // system reset
    input           clk,        // system clock
    // chip interface
    input           sclk,       // serial clock
    input           sdi,         // serial data in
    output      reg sdo,         // serial data out
    output      reg rdy,
    input           scs,         // chip select, active high. Goes low in between instructions
    // Dump access
    input           dump_clk,
    input  [AW-1:0] dump_addr,
    input           dump_we,
    input  [DW-1:0] dump_din,
    output [DW-1:0] dump_dout,
    // NVRAM contents changed
    input           dump_clr,   // Clear the flag
    output reg      dump_flag   // There was a write
);

localparam CW=AW+4;  // bits between the 4-bit op command and the data
localparam [3:0] CMDIN = PROG ? 4'd10 : 4'd9;

reg           prog_en, write_all;
reg           sdi_l;
reg           last_sclk, mem_we;
reg  [   1:0] dout_up;
wire          sclk_posedge = sclk && !last_sclk;
reg  [AW-1:0] addr;
reg  [DW-1:0] newdata, dout, mem_din;
wire [DW-1:0] qout;
reg  [   3:0] rx_cnt;
reg  [   3:0] op;
wire [DW-1:0] next_data = { newdata[0+:DW-1], sdi };
wire [CW-1:0] full_op = { op, addr };

`ifdef SIMULATION
wire [AW-1:0] next_addr = {addr[AW-2:0], sdi};
`endif

enum { IDLE=0, RX, READ, WRITE, WRITE_ALL, WAIT} st;

always @(posedge clk) last_sclk <= sclk;

jt5911_dual_ram #(.DW(DW), .AW(AW)) u_ram(
    .clk0   ( clk       ),
    .clk1   ( dump_clk  ),
    // First port: internal use
    .addr0  ( addr      ),
    .data0  ( mem_din   ),
    .we0    ( mem_we    ),
    .q0     ( qout      ),
    // Second port: dump
    .addr1  ( dump_addr ),
    .data1  ( dump_din  ),
    .we1    ( dump_we   ),
    .q1     ( dump_dout )
);

`ifdef JT5911_SIMULATION
    `define JT5911_WRITE(a,v) $display("EEPROM: %X written to %X", v, a[0+:AW]);
    `define JT5911_READ(a,v) $display("EEPROM: %X read from  %X", v, a[AW-1:0]);
    `define JT5911_ERASEEN  $display("EEPROM: erase enabled");
    `define JT5911_ERASEDIS $display("EEPROM: erase disabled");
    `define JT5911_ERASEALL $display("EEPROM: erase all");
`else
    `define JT5911_WRITE(a,v)
    `define JT5911_READ(a,v)
    `define JT5911_ERASEEN
    `define JT5911_ERASEDIS
    `define JT5911_ERASEALL
`endif

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        prog_en  <= 0;
        newdata  <= 0;
        mem_we   <= 0;
        st       <= IDLE;
        rx_cnt   <= 0;
        sdo      <= 0;
        rdy      <= 0;
        dout_up  <= 0;
        dump_flag<= 0;
    end else begin
        // data output
        dout_up <= dout_up>>1;
        if( dout_up[0] ) begin
            `JT5911_READ ( addr, qout )
            dout    <= qout;
        end
        mem_we <= 0;

        // It flags a write command, not necessarily a data change
        if( dump_clr )
            dump_flag <= 0;
        else if(mem_we) dump_flag <= 1;

        if( !scs ) begin
            st  <= IDLE;
            rdy <= 1;
        end else if( sclk_posedge ) begin
            sdi_l <= sdi;
            case( st )
                RX: begin
                    rx_cnt <= rx_cnt+1'd1;
                    { op, addr } <= { full_op[CW-2:0], sdi };
                    if( rx_cnt==CMDIN ) begin
                        casez( full_op[CW-1-:4] ) // op is top 4 bits
                            4'b1000: begin
                                st      <= READ;
                                sdo     <= 0;
                                dout_up <= 2'b10;
                            end
                            4'b?100: if( prog_en ) begin
                                st        <= WRITE;
                                rx_cnt    <= 0;
                                write_all <= 0;
                            end else begin
                                st <= WAIT;
                            end
                            4'b0011: begin
                                `JT5911_ERASEEN
                                prog_en <= 1;
                                st <= WAIT;
                            end
                            4'b0000: begin
                                `JT5911_ERASEDIS
                                prog_en <= 1'b0;
                                st <= WAIT;
                            end
                            4'b0010: if( prog_en ) begin
                                `JT5911_ERASEALL
                                rdy     <= 0;
                                newdata <= '1;
                                st      <= WRITE_ALL;
                            end else begin
                                st <= WAIT;
                            end
                            default: st <= WAIT;
                        endcase
                    end
                end
                WRITE: begin
                    newdata <= next_data;
                    rx_cnt  <= rx_cnt+1'd1;
                    sdo     <= 0; // busy
                    if( rx_cnt == (PROG?4'hf:4'h7) ) begin
                        mem_we <= 1;
                            `JT5911_WRITE( addr, next_data )
                        mem_din <= next_data;
                        st <= WAIT;
                    end
                end
                READ: { sdo, dout} <= { dout, 1'b1 };
                WRITE_ALL: begin
                    addr   <= addr+1'd1;
                    mem_we <= 1;
                    if( &addr ) st <= WAIT;
                end
                WAIT: rdy <= 1;
                IDLE: begin
                    sdo <= 1; // ready
                    if( sclk_posedge && sdi && !sdi_l ) begin
                        st <= RX; // start-bit detected
                        rx_cnt <= 0;
                    end
                end
                default:;
            endcase
        end
    end
end

endmodule


module jt5911_dual_ram #(parameter DW=8, AW=10) (
    input   clk0,
    input   clk1,
    // Port 0
    input   [DW-1:0] data0,
    input   [AW-1:0] addr0,
    input   we0,
    output reg [DW-1:0] q0,
    // Port 1
    input   [DW-1:0] data1,
    input   [AW-1:0] addr1,
    input   we1,
    output reg [DW-1:0] q1
    `ifdef JTFRAME_DUAL_RAM_DUMP
    ,input dump
    `endif
);
/* verilator lint_off MULTIDRIVEN */
(* ramstyle = "no_rw_check" *) reg [DW-1:0] mem[0:(2**AW)-1];

`ifdef SIMULATION
integer rstcnt;
initial begin
    for( rstcnt=0; rstcnt<2**AW; rstcnt=rstcnt+1)
        mem[rstcnt] = {DW{1'b1}};
end
`endif
always @(posedge clk0) begin
    q0 <= mem[addr0];
    if(we0) mem[addr0] <= data0;
end

always @(posedge clk1) begin
    q1 <= mem[addr1];
    if(we1) mem[addr1] <= data1;
end
/* verilator lint_on MULTIDRIVEN */
endmodule