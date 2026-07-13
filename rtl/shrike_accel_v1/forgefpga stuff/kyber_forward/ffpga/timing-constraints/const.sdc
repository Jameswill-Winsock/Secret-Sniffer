create_clock -name clk \
    -period 20.000 \
    -waveform {0 10} \
    [get_ports clk]