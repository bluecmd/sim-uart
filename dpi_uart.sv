/*
 * DPI UART
 *
 * Implements 8n1 decoding/encoding for a given divisor.
 * Divisor is calculated as SYS_CLK / (BAUD * 16)
 *
 * Copyright (C) 2013 Christian Svensson <blue@cmd.nu>
 *
 * Based on Milkymist SoC UART
 *  Copyright (C) 2007, 2008, 2009, 2010 Sebastien Bourdeauducq
 *  Copyright (C) 2007 Das Labor
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3 of the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module dpi_uart #(
  // Calling DPI functions can be expensive. If data was not available, wait
  // this amount of clock cycles until next uart_tx_is_data_available call.
  // The default will probably feel sluggish, but my trivial tests has shown
  // that it makes the speed impact of the TX path negligible.
  parameter DATA_AVAIL_BACKOFF = 100000
) (
  input         rst_i,
  input         clk_i,

  input         uart_rx_i,
  output        uart_tx_o,

  input [15:0]  divisor_i
);

  import "DPI-C" function int uart_tx_is_data_available();
  import "DPI-C" function int uart_tx_get_data();
  import "DPI-C" function void uart_rx_new_data(input integer chr);
  import "DPI-C" function void uart_init();

  initial
  begin
    uart_init();
  end

  reg [15:0]  div_cntr_r;
  wire        strobe;
  assign      strobe = (div_cntr_r == 0);

  always @(posedge clk_i)
  begin
    if (rst_i) begin
      div_cntr_r <= divisor_i - 1;
    end else begin
      div_cntr_r <= div_cntr_r - 1;
      if (strobe)
        div_cntr_r <= divisor_i - 1;
    end
  end

  // Synchronize uart_rx
  reg uart_rx_r1;
  reg uart_rx_r2;

  always @(posedge clk_i)
  begin
    uart_rx_r1 <= uart_rx_i;
    uart_rx_r2 <= uart_rx_r1;
  end

  // UART RX Logic
  reg       rx_busy_r;
  reg       rx_break_r;
  reg [3:0] rx_count16_r;
  reg [3:0] rx_bitcount_r;
  reg [7:0] rx_reg_r;
  reg       prev_uart_rx_r;

  always @(posedge clk_i)
  begin
    if (rst_i) begin
      rx_busy_r <= 1'b0;
      rx_count16_r  <= 4'd0;
      rx_bitcount_r <= 4'd0;
      rx_break_r <= 1'b0;
      prev_uart_rx_r <= 1'b0;
    end else begin
      rx_break_r <= 1'b0;
      if (strobe) begin
        prev_uart_rx_r <= uart_rx_r2;
        if (~rx_busy_r) begin // look for start bit
          if (~uart_rx_r2 & prev_uart_rx_r) begin // start bit found
            rx_busy_r <= 1'b1;
            rx_count16_r <= 4'd7;
            rx_bitcount_r <= 4'd0;
          end
        end else begin
          rx_count16_r <= rx_count16_r + 4'd1;
          if (rx_count16_r == 4'd0) begin // sample
            rx_bitcount_r <= rx_bitcount_r + 4'd1;
            if (rx_bitcount_r == 4'd0) begin // verify startbit
              if (uart_rx_r2)
                rx_busy_r <= 1'b0;
            end else if (rx_bitcount_r == 4'd9) begin
              rx_busy_r <= 1'b0;
              if (uart_rx_r2) begin // stop bit ok
                uart_rx_new_data(rx_reg_r);
              end else if (rx_reg_r == 8'h00) // break condition
                rx_break_r <= 1'b1;
            end else
              rx_reg_r <= {uart_rx_r2, rx_reg_r[7:1]};
          end
        end
      end
    end
  end

  // UART TX Logic
`ifdef UART_READONLY
  assign uart_tx_o = 1'b0;
`else
  reg       tx_busy_r;
  reg [3:0] tx_bitcount_r;
  reg [3:0] tx_count16_r;
  reg [7:0] tx_reg_r;
  reg       tx_data_avail_r;
  reg       uart_tx_r;
  integer   data_avail_backoff_r;

  assign uart_tx_o = uart_tx_r;

  always @(posedge clk_i) begin
    if (rst_i) begin
      data_avail_backoff_r <= 0;
      tx_data_avail_r <= 1'b0;
    end else begin
      if (data_avail_backoff_r != 0)
        data_avail_backoff_r <= data_avail_backoff_r - 1;

      tx_data_avail_r <= tx_data_avail_r & ~tx_busy_r;
      if (~tx_data_avail_r & ~tx_busy_r) begin
        if (data_avail_backoff_r == 0) begin
          if (uart_tx_is_data_available())
            tx_data_avail_r <= 1'b1;
          else
            data_avail_backoff_r <= DATA_AVAIL_BACKOFF - 1;
        end
      end
    end
  end

  always @(posedge clk_i)
  begin
    if (rst_i) begin
      tx_busy_r <= 1'b0;
      uart_tx_r <= 1'b1;
    end else begin
      if (~tx_busy_r & tx_data_avail_r) begin
        tx_reg_r <= uart_tx_get_data();
        tx_bitcount_r <= 4'd0;
        tx_count16_r <= 4'd1;
        tx_busy_r <= 1'b1;
        uart_tx_r <= 1'b0;
      end else if (strobe & tx_busy_r) begin
        tx_count16_r  <= tx_count16_r + 4'd1;
        if (tx_count16_r == 4'd0) begin
          tx_bitcount_r <= tx_bitcount_r + 4'd1;
          if (tx_bitcount_r == 4'd8) begin
            uart_tx_r <= 1'b1;
          end else if (tx_bitcount_r == 4'd9) begin
            uart_tx_r <= 1'b1;
            tx_busy_r <= 1'b0;
          end else begin
            uart_tx_r <= tx_reg_r[0];
            tx_reg_r <= {1'b0, tx_reg_r[7:1]};
          end
        end
      end
    end
  end
`endif // UART_READONLY
endmodule
