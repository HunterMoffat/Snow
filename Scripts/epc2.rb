system("sudo systemctl restart systemd-networkd
        sudo ip addr add 192.168.0.1/24 dev pgwtun
        sudo ip link set up dev pgwtun
        sudo iptables -t nat -A POSTROUTING -o `cat /var/emulab/boot/controlif` -j MASQUERADE
        cd /opt/nextepc/install/etc/nextepc
        cp /proj/reu2020/reudata/nextepc.conf   
        ")
