# A simple XpFlow Test 
require 'net/ssh'
require 'net/ssh/multi'

h1 = 'pc03-mebvm-2.emulab.net'
h2 = 'pc03-mebvm-1.emulab.net'
u = 'Hmoffat'
dir = "/ems/"
# This will ssh into each node and will clone my ems repo to it so It can run my scripts
puts 'Now ssh-ing into epc'

Net::SSH.start(h2, u) do |session|
  @result = session.exec!('git clone https://github.com/HunterMoffat/ems.git')
  puts @result
  session.exec!('cd ems')
  @result = puts @result
  session.exec!('ruby epc.rb')
  @result = puts @result
end

Net::SSH.start(h1, u) do |session|
  @result = session.exec!('git clone https://github.com/HunterMoffat/ems.git')
  puts @result
  @result = session.exec!('cd ems
    ruby sim_simple.rb')
  puts @result
end
