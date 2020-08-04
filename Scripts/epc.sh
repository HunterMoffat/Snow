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
sudo bash

cd /opt
git clone https://github.com/nextepc/nextepc
cd nextepc
autoreconf -iv
./configure --prefix=`pwd`/install
make -j `nproc`
make install

exit
cd /opt/nextepc/webui
sudo npm install
sudo bash

cat << EOF > /etc/systemd/network/98-nextepc.netdev
[NetDev]
Name=pgwtun
Kind=tun
EOF

exit
sudo systemctl restart systemd-networkd
sudo ip addr add 192.168.0.1/24 dev pgwtun
sudo ip link set up dev pgwtun
sudo iptables -t nat -A POSTROUTING -o `cat /var/emulab/boot/controlif` -j MASQUERADE
cd /opt/nextepc/install/etc/nextepc
cp /proj/reu2020/reudata/nextepc.conf
