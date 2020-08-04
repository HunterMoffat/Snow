#!/bin/bash
sudo apt-get remove -y --purge man-db
sudo apt-get update
sudo apt-get -y install mongodb
sudo systemctl start mongodb
sudo apt-get -y install autoconf libtool gcc pkg-config \
         git flex bison libsctp-dev libgnutls28-dev libgcrypt-dev \
         libssl-dev libidn11-dev libmongoc-dev libbson-dev libyaml-dev
yes
curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
sudo apt-get -y install nodejs
exit 0
