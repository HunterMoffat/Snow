# A simple script that will auto set up the sim ran node for the first tutorial
# installing mongo db


# cat << EOF > /etc/systemd/network/98-nextepc.netdev
#         [NetDev]
#         Name=pgwtun
#         Kind=tun
#         EOF
system("sudo apt-get remove -y --purge man-db
        sudo apt-get update
        sudo apt-get -y install mongodb
        sudo systemctl start mongodb
        echo yes | sudo apt-get -y install autoconf libtool gcc pkg-config \
        git flex bison libsctp-dev libgnutls28-dev libgcrypt-dev \
        libssl-dev libidn11-dev libmongoc-dev libbson-dev libyaml-dev
        sudo apt-get -y install nodejs
        
        cd /opt
        sudo git clone https://github.com/nextepc/nextepc
        cd nextepc
        sudo autoreconf -iv
        sudo ./configure --prefix=`pwd`/install
        sudo make -j `nproc`
        sudo make install
        ")
