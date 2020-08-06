
# A test that creates an experiment based off of the ota_gnuradio profile from POWDER
# sim-ran.test.reu2020.emulab.net
# epc.test.reu2020.emulab.net
require 'thread'
process :main do
username  = 'Hmoffat'
profile = 'Moffat_LTE'
project = 'reu2020'
exp1 = 'test2'
gnu = powderExperiment(project, exp1, profile)
nodes = Array.new(2)
nodes[0] = 'sim-ran'
nodes[1] = 'epc'
# making the scripts executable
# Executing the scripts on each node
Thread.new{powder_execute_one(gnu ,'epc',username,"sudo /opt/nextepc/install/bin/nextepc-epcd")}
Thread.new{powder_execute_one(gnu ,'sim-ran',username,'cd Snow/Scripts && sudo ruby sim2.rb')}
Thread.new{powder_execute_one(gnu ,'sim-ran',username,'cd Snow/Scripts && sudo ruby sim3.rb')}
Thread.new{powder_execute_one(gnu ,'sim-ran',username,'cd Snow/Scripts && sudo ruby sim4.rb')}
# puts("Done, Have you completed the ssh bash thing yet?")
# answer = gets.chomp
# if answer["y"]
#     powder_execute_one(gnu ,'epc',username,"cd Snow/Scripts && sudo ruby epc1.rb")
# end
end
