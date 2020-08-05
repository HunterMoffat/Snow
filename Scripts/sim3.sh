#!/bin/bash
cd /opt/oaisim-xran/cmake_targets/lte_build_oai/build
sudo RFSIMULATOR=127.0.0.1 ./lte-uesoftmodem -C 2125000000 -r 25 --rfsim
echo DONE
