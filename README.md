# jteeprom

Verilog modules compatible with common EEPROM chips such as 93C46 or 93C06 by Jose Tejada (jotego)

# Related Repositories

The FPGA conversion of the [CPS1](https://github.com/jotego/jtcps1) CAPCOM arcade system uses this repository.

# Test waveforms

This can obtained by dumping to the error.log file the commands sent by the CPU in the Cadillacs'n Dinosaurs game:

```mame dino -debug -log```

And then

```wp f1c006,1,w,1,{logerror "%d - %d - %d\n", (wpdata&0x80)>>7,(wpdata&0x40)>>6,wpdata&1;go}```

After booting, the error.log will contain the read access done by the game. If you go into the test menu, and change the settings, the error.log will contain the write commands.

# Contribute

You can show your appreciation through
* Patreon: https://patreon.com/topapate
* Paypal: https://paypal.me/topapate