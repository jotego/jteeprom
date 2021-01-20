#!/bin/bash

iverilog test.v ../../hdl/jt9346.v -o sim -DJT9346_SIMULATION && sim -lxt