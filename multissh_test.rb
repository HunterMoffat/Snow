# A simple program that tests to see if I am able to ssh into multiple hosts at 
# the same time
require 'net/ssh'
require 'net/ssh/multi'

print "\nWhat operating system are you using?  [Windows, Linux]\n"
op_sys = gets.to_s.upcase.delete("\n")
print "\n#{op_sys}\n"
print "\nWhat is the name of your private key associated with your emulab account?\n"
priv_key_name = gets.to_s.delete("\n")
print "\nEnter the username to connect to host\n"
user_name = gets.to_s.delete("\n")
print "\nHow many nodes are you trying to connect to?\n"
# need to cast to int?
num_hosts = gets.to_i
#print "\nWhat is your password?\n"
#password = gets.to_s.delete("\n")
hosts = Array.new(num_hosts)
ports = Array.new(num_hosts)
commands = Array.new(num_hosts)
# getting all the host names of the nodes
for i in 0..num_hosts-1
    puts "\nWhat is the Host name for node #{i+1}? Example: pc10.emulab.net\n"
    cur_host = gets.to_s
    hosts[i] = cur_host.to_s.delete("\n")
    puts "\nWhat is the port number for this host?\n"
    ports[i] = gets.to_s.delete("\n")
    #command = "#{username}@#{hosts[i]}"
    command = ""
    if op_sys == 'LINUX'
        command = "ssh -X -p #{ports[i]} #{user_name}@#{hosts[i]}"
    elsif op_sys == 'WINDOWS'
        command = "ssh -i ~/.ssh/#{priv_key_name} -p #{ports[i]} #{user_name}@#{hosts[i]}"
    end
    commands[i] = command.delete("\n")
    exec(commands[i].to_s)
    print "\nCurrent command is:\n" + commands[i] + " \n" 
end
#****** [THIS SORTA WORKS, CANT GET IT TO RUN THE COMMAND WHEN SSH'ED INTO THE NODE] ******
# Net::SSH.start(hosts[0],user_name) do |session|
#     session.exec 'sudo -su'
# end
# ****** [THIS SORTA WORKS BUT I DONT THINK IT IS WHAT I AM LOOKING FOR] ******
# Connecting to the hosts and start executing commands
Net::SSH::Multi.start do |session|
    # Connect to remote machines
    ### Change this!!###
    session.use "#{username}@#{hosts[0]}"
    session.exec('sudo -su') do |ch, stream, data|
      puts "[#{ch[:host]} : #{stream}] #{data}"
    end
    # Tell Net::SSH to wait for output from the SSH server
    session.loop
end