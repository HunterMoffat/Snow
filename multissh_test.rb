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
username = gets.to_s.delete("\n")
print "\nHow many nodes are you trying to connect to?\n"
# need to cast to int?
num_hosts = gets.to_i
print "\nWhat is your password?\n"
password = gets.to_s.delete("\n")
hosts = Array.new(num_hosts)
ports = Array.new(num_hosts)
commands = Array.new(num_hosts)
# getting all the host names of the nodes
for i in 0..num_hosts-1
    puts "\nWhat is the Host name for node #{i+1}? Example: pc10.emulab.net\n"
    cur_host = gets.to_s
    hosts[i] = cur_host
    puts "\nWhat is the port number for this host?\n"
    ports[i] = gets.to_s
    command = "#{username}@#{hosts[i]}"
    #if op_sys == 'LINUX'
        #command = "ssh -X -p #{port_no} #{username}@#{hosts[i]}"
    #elsif op_sys == 'WINDOWS'
        #command = "ssh -i ~/.ssh/#{priv_key_name} -p #{port_no} #{username}@#{hosts[i]}"
    #end
    commands[i] = command.delete("\n")
    print "\nCurrent command is:\n" + commands[i] + " \n" 
end
# Connecting to the hosts and start executing commands
Net::SSH.start( hosts[0].to_s, :password=>password.to_s, :port=>ports[0].to_s, :username=>username.to_s, :host_key=>priv_key_name.to_s) do |session|
    some_func(session, "ls")
end

def some_func(session, command)
    session.open_channel do |channel|
        channel.on_data do |ch, data|
        end
    channel.exec command.to_s
    end
end