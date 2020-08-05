#!/bin/bash
echo sudo bash

cd /opt
git clone https://github.com/nextepc/nextepc
cd nextepc
autoreconf -iv
./configure --prefix=`pwd`/install
make -j `nproc`
make install
echo exit

cd /opt/nextepc/webui
sudo npm install
