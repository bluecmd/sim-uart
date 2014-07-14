module testbench (
    input           sys_clk_i,
    input           sys_rst_i
);
  // 80 MHz / (16 * 115200 Baud) = ~43
  parameter UART_DIVISOR = 16'd43;

  wire        uart_txd;
  wire        uart_rxd;

  orpsoc soc_i (
    .sys_clk_i            (sys_clk_i),
    .sys_rst_i            (sys_rst_i),
    .uart0_srx_pad_i      (uart_rxd),
    .uart0_stx_pad_o      (uart_txd),
  );

  dpi_uart uart_i (
    .rst_i(sys_rst_i),
    .clk_i(sys_clk_i),
    .uart_rx_i(uart_txd),
    .uart_tx_o(uart_rxd),
    .divisor_i(UART_DIVISOR)
  );

endmodule
