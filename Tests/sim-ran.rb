#
#
# A simple script that will auto set up the sim ran node for the first tutorial
#
#
command = Thread.new do
    system(`sudo apt-get remove -y --purge man-db`)
end
command.join

command = Thread.new do 
    system('sudo bash')
end
command.join

command = Thread.new do 
    system('cd /opt')
end
command.join

command = Thread.new do 
    system('git clone https://gitlab.flux.utah.edu/jczhu/oaisim-xran/')
end
command.join
command = Thread.new do 
    system('cd oaisim-xran')
end
command.join
command = Thread.new do 
    system('git checkout develop')
end
command.join
command = Thread.new do 
    system('cd cmake_targets')
end
command.join
command = Thread.new do 
    system('sudo ./build_oai -I -c -C --eNB --UE -w SIMU')
end
command.join

