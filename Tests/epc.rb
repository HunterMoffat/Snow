# A simple script that will auto set up the sim ran node for the first tutorial

# installing mongo db
command = Thread.new do 
    system('sudo apt-get remove -y --purge man-db')
end
command.join
command = Thread.new do 
    system('sudo apt-get update')
end
command.join
command = Thread.new do 
    system('sudo apt-get -y install mongodb')
end
command.join
command = Thread.new do 
    system('sudo systemctl start mongodb')
end
command.join
# Install other prerequisite build and library packages
command = Thread.new do 
    system('sudo apt-get -y install autoconf libtool gcc pkg-config \
        git flex bison libsctp-dev libgnutls28-dev libgcrypt-dev \
        libssl-dev libidn11-dev libmongoc-dev libbson-dev libyaml-dev
')
end
command.join

puts "\n[ANSWER YES]\n"

command = Thread.new do 
    system('')
end
command.join
# install nodeJS (needed by NextEPC HSS database interface)
command = Thread.new do 
    system('curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
        sudo apt-get -y install nodejs
        ')
end
command.join
#Install Wireshark
command = Thread.new do 
    system('sudo apt-get -y install wireshark')
end
command.join
puts "\n[ANSWER NO]\n"

#Download and compile NextEPC on the epc node
command = Thread.new do 
    system('sudo bash')
end
command.join
command = Thread.new do 
    system('cd /opt')
end
command.join
command = Thread.new do 
    system('git clone https://github.com/nextepc/nextepc')
end
command.join
command = Thread.new do 
    system('cd nextepc')
end
command.join
command = Thread.new do 
    system('autoreconf -iv
        ./configure --prefix=`pwd`/install
        ')
end
command.join
command = Thread.new do 
    system('make -j `nproc`')
end
command.join
command = Thread.new do 
    system('make install')
end
command.join
command = Thread.new do 
    system('exit')
end
command.join
# Install nodeJS library prerequisites and build the NextEPC HSS Web UI
command = Thread.new do 
    system('cd /opt/nextepc/webui')
end
command.join
command = Thread.new do 
    system('sudo npm install')
end
command.join
# Configure networking on the epc node to support NextEPC
command = Thread.new do 
    system('sudo bash')
end
command.join
command = Thread.new do 
    system('cat << EOF > /etc/systemd/network/98-nextepc.netdev
        [NetDev]
        Name=pgwtun
        Kind=tun
        EOF
        ')
end
command.join
command = Thread.new do 
    system('exit')
end
command.join
# Restart systemd's networking handler
command = Thread.new do 
    system('sudo systemctl restart systemd-networkd')
end
command.join
command = Thread.new do 
    system('')
end
command.join
# Set the IP address on the pgwtun tunnel device
command = Thread.new do 
    system('sudo ip addr add 192.168.0.1/24 dev pgwtun')
end
command.join
command = Thread.new do 
    system('sudo ip link set up dev pgwtun')
end
command.join
command = Thread.new do 
    system('sudo iptables -t nat -A POSTROUTING -o `cat /var/emulab/boot/controlif` -j MASQUERADE')
end
command.join
# Configure NextEPC services (HSS, MME, PGW, SGW)
command = Thread.new do 
    system('cd /opt/nextepc/install/etc/nextepc')
end
command.join
command = Thread.new do 
    system('cp /proj/reu2020/reudata/nextepc.conf .')
end
command.join
# Add the simulated UE subscriber information to the HSS database
command = Thread.new do 
    system('cd /opt/nextepc/webui')
end
command.join
command = Thread.new do 
    system('sudo npm run dev')
end
command.join
print "\n  Waiting for completion of browser portion of tutorial \n"
print "\n have you completed browser portion? [y/n] \n"
finished = gets
if finished == "y"
    command = Thread.new do 
        system('sudo /opt/nextepc/install/bin/nextepc-epcd')
    end
    command.join
end
