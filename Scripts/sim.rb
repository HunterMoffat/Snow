system("sudo apt-get remove -y --purge man-db
        sudo bash &&
        cd /opt &&
        git clone https://gitlab.flux.utah.edu/jczhu/oaisim-xran/ &&
        cd oaisim-xran &&
        git checkout develop &&
        cd cmake_targets &&
        echo yes | sudo ./build_oai -I -c -C --eNB --UE -w SIMU")