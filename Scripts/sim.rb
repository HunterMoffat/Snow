system("sudo apt-get remove -y --purge man-db")
system("cd /opt && sudo git clone https://gitlab.flux.utah.edu/jczhu/oaisim-xran/")
system("cd /opt/oaisim-xran && git checkout develop && cd cmake_targets && sudo ./build_oai -I -c -C --eNB --UE -w SIMU")
