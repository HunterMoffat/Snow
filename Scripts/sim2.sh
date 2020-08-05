#!/bin/bash
cd /opt/oaisim-xran/cmake_targets/lte_build_oai/build
sudo RFSIMULATOR=enb   ./lte-softmodem -O /opt/oaisim-xran/enb1.conf --rfsim
exit