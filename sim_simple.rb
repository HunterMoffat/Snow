# This hopefully sets up the sim-ran node
command = Thread.new do 
  system("sudo apt-get remove -y --purge man-db
      sudo bash
      cd /opt
      sudo systemctl start mongodb
      git clone https://gitlab.flux.utah.edu/jczhu/oaisim-xran/
      cd oaisim-xran
      git checkout develop
      cd cmake_targets
      sudo ./build_oai -I -c -C --eNB --UE -w SIMU
      ")
end
command.join
