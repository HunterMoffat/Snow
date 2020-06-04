# A simple XpFlow Test 
require 'net/ssh'
require 'net/ssh/multi'

h1 = 'pc06-fortvm-2.emulab.net'
h2 = 'pc06-fortvm-1.emulab.net'
u = 'Hmoffat'

process :main do
  setup_ssh
end
dir = "/ems/"
# This will ssh into each node and will clone my ems repo to it so It can run my scripts

Net::SSH.start(h1, u) do |session|
    session.exec!('git clone https://github.com/HunterMoffat/ems.git')
    session.exec!("cd #{dir}")
    session.exec!('ruby sim_simple.rb')
end

#   Net::SSH.start(h2, u) do |session|
#     session.exec!('git clone https://github.com/HunterMoffat/ems.git')
#     session.exec!("cd #{dir}")
#     session.exec!('ruby epc_simple.rb')
#   end

