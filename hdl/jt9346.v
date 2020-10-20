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

// Module compatible with Microchip 96C06/46

module jt9346(
    input      clk,        // system clock
    input      rst,        // system reset
    // chip interface
    input      sclk,       // serial clock
    input      sdi,         // serial data in
    output reg sdo,         // serial data out and ready/not busy signal
    input      scs          // chip select, active high. Goes low in between instructions
);

parameter DW=16, AW=6;

localparam AMAX=2**AW-1;

reg  [DW-1:0] mem[0:AMAX];
reg           erase_en, write_all;
reg           last_sclk;
wire          sclk_posedge = sclk && !last_sclk;
reg  [   1:0] op;
reg  [AW-1:0] addr, cnt;
reg  [DW-1:0] rx_cnt, newdata, dout;
wire [AW+1:0] full_op = { op, addr };
wire [AW-1:0] new_addr = {addr[AW-2:0], sdi};
reg  [   6:0] st;

localparam IDLE=7'd1, RX=7'd2, READ=7'd4, WRITE=7'd8, WRITE_ALL=7'h10,
           PRE_READ=7'h20, WAITLOW=7'h40;

always @(posedge clk) last_sclk <= sclk;

`ifdef JT9346_SIMULATION
    `define REPORT_WRITE(a,v) $display("EEPROM: %X written to %X", v, a);
    `define REPORT_READ(a,v) $display("EEPROM: %X read from  %X", v, a);
    `define REPORT_ERASE(a  ) $display("EEPROM: %X ERASED", a);
    `define REPORT_ERASEEN  $display("EEPROM: erase enabled");
    `define REPORT_ERASEDIS $display("EEPROM: erase disabled");
    `define REPORT_ERASEALL $display("EEPROM: erase all");
    `define REPORT_WRITEALL $display("EEPROM: write all");
`else
    `define REPORT_WRITE(a,v)
    `define REPORT_READ(a,v)
    `define REPORT_ERASE(a)
    `define REPORT_ERASEEN
    `define REPORT_ERASEDIS
    `define REPORT_ERASEALL
    `define REPORT_WRITEALL
`endif

`ifdef SIMULATION
integer clrcnt;
initial begin
    for( clrcnt=0; clrcnt<=AMAX; clrcnt=clrcnt+1)
        mem[clrcnt] = {DW{1'b1}};
end
`endif

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        erase_en <= 0;
        cnt      <= {AW{1'b0}};
        newdata  <= {DW{1'b1}};
        st       <= IDLE;
        sdo      <= 0;
        addr     <= {AW{1'b0}};
        op       <= 2'd0;
    end else begin
        case( st )
            default: begin // IDLE
                sdo <= 1; // ready
                if( sclk_posedge && scs && sdi ) begin
                    st <= RX;
                    rx_cnt <= { {DW-1{1'b0}}, 1'b1 } << (AW+1);
                end
            end
            WAITLOW: if( !scs ) st <= IDLE;
            RX: if( sclk_posedge && scs ) begin
                rx_cnt <= { rx_cnt[DW-1], rx_cnt[DW-1:1] };
                { op, addr } <= { full_op[AW:0], sdi };
                if( rx_cnt[0] ) begin
                    case( full_op[6:5] ) // op is in bits 6:5
                        2'b10: begin
                            st     <= READ;
                            sdo    <= 0;
                            `REPORT_READ ( new_addr, mem[ new_addr ] )
                            dout   <= mem[ new_addr ];
                            rx_cnt <= {DW{1'b1}};
                        end
                        2'b01: begin
                            st        <= WRITE;
                            rx_cnt    <= { 1'b1, {DW-1{1'b0}}};
                            write_all <= 1'b0;
                        end
                        2'b11: begin // ERASE
                            `REPORT_ERASE(new_addr);
                            mem[ new_addr ] <= {DW{1'b1}};
                            st <= WAITLOW;
                        end
                        2'b00:
                            case( full_op[4:3] )
                                2'b11: begin
                                    `REPORT_ERASEEN
                                    erase_en <= 1;
                                    st <= WAITLOW;
                                end
                                2'b00: begin
                                    `REPORT_ERASEDIS
                                    erase_en <= 0;
                                    st <= WAITLOW;
                                end
                                2'b10: begin
                                    if( erase_en ) begin
                                        `REPORT_ERASEALL
                                        sdo     <= 0; // busy
                                        cnt     <= 0;
                                        newdata <= {DW{1'b1}};
                                        st      <= WRITE_ALL;
                                    end else begin
                                        st <= WAITLOW;
                                    end
                                end
                                2'b01: begin
                                    `REPORT_WRITEALL
                                    sdo       <= 0; // busy
                                    st        <= WRITE;
                                    rx_cnt    <= { 1'b1, {DW-1{1'b0}}};
                                    write_all <= 1;
                                end
                            endcase
                    endcase
                end
            end else if(!scs) begin
                st <= IDLE;
            end
            WRITE: if( sclk_posedge && scs ) begin
                newdata <= { newdata[DW-2:0], sdi };
                rx_cnt <= rx_cnt >> 1;
                sdo    <= 0; // busy
                if( rx_cnt[0] ) begin
                    if( write_all ) begin
                        cnt <= 0;
                        st  <= WRITE_ALL;
                    end else begin
                        `REPORT_WRITE( addr, { newdata[DW-2:0], sdi } )
                        mem[ addr ] <= { newdata[DW-2:0], sdi };
                    end
                end
            end else if(!scs) begin
                st <= IDLE;
            end
            /*
            PRE_READ: if( sclk_posedge && scs ) begin
                st <= READ;
                sdo <= 0;
            end else if(!scs) st<=IDLE;*/
            READ: if( sclk_posedge && scs ) begin
                // if(rx_cnt[0])
                    { sdo, dout} <= { dout, 1'b0 };
                // rx_cnt <= rx_cnt>>1;
                // if( ~|rx_cnt ) begin
                //     st <= IDLE;
                // end
            end else if(!scs) begin
                st <= IDLE;
            end
            WRITE_ALL: begin
                mem[cnt] <= newdata;
                if( &cnt ) begin
                    if(!scs) st<=IDLE;
                end else begin
                    cnt <= cnt+1'd1;
                end
            end
        endcase
    end
end

endmodule
