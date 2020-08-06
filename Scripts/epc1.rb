# A simple script that will auto set up the sim ran node for the first tutorial
# installing mongo db

require 'fileutils'
# cat << EOF > /etc/systemd/network/98-nextepc.netdev
#         
#         Name=pgwtun
#         Kind=tun
#         EOF

system("sudo apt-get remove -y --purge man-db")
system("sudo apt-get update")
system("sudo apt-get -y install mongodb")
system("sudo systemctl start mongodb")
system("echo yes | sudo apt-get -y install autoconf libtool gcc pkg-config \
        git flex bison libsctp-dev libgnutls28-dev libgcrypt-dev \
        libssl-dev libidn11-dev libmongoc-dev libbson-dev libyaml-dev")
puts "\n[DONE WITH THE FIRST]\n"
system("sudo apt-get -y install nodejs")
system("cd /opt && sudo git clone https://github.com/nextepc/nextepc")
system("cd /opt/nextepc && sudo autoreconf -iv && sudo ./configure --prefix=`pwd`/install && sudo make -j `nproc` && sudo make install")
puts "\n[ABOUT TO WRITE THE FILE]\n"
# system("cd Snow/Scripts/ sudo ruby epc2.rb")
file = File.open("/etc/systemd/network/98-nextepc.netdev", 'w+')
File.write(file, "[NetDev]\nName=pgwtun\nKind=tun")
puts "\n[DONE WRITING FILE #{file}]\n"
system("sudo systemctl restart systemd-networkd")
system("sudo ip addr add 192.168.0.1/24 dev pgwtun")
system("sudo ip link set up dev pgwtun")
system("sudo iptables -t nat -A POSTROUTING -o `cat /var/emulab/boot/controlif` -j MASQUERADE")
system("cd /opt/nextepc/install/etc/nextepc && sudo cp /proj/reu2020/reudata/nextepc.conf")
                