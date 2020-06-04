# A simple script that will auto set up the sim ran node for the first tutorial
# installing mongo db
command = Thread.new do 
    system("sudo apt-get remove -y --purge man-db
        sudo apt-get update
        sudo apt-get -y install mongodb
        sudo systemctl start mongodb
        sudo apt-get -y install autoconf libtool gcc pkg-config \
        git flex bison libsctp-dev libgnutls28-dev libgcrypt-dev \
        libssl-dev libidn11-dev libmongoc-dev libbson-dev libyaml-dev
        ")
end
command.join
