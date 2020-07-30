
process :main do
    project = 'reu2020'
    profile = 'single-pc'
    experiment = 'myexp3'
    # starting an experiment
    #startExperiment(project,experiment, profile)
    newexp = powderExperiment('reu2020', 'myexp3', 'single-pc')
    #puts "proj: #{newexp.project}, newexp: #{newexp.experiment}, prof: #{newexp.profile}"
    powder_execute_one(newexp,'node','Hmoffat','ping -c6 google.com')
    #ssh = 'Hmoffat@pc839.emulab.net'
    #ssh = "Hmoffat@node.myexp3.reu2020.emulab.net"
    # node = simple_node(ssh)
    #res = execute_one(node, 'ping -c6 google.com')
    # log(res.stdout)
    #startExperiment( newexp )
    # checking status of the experiment
    #experimentStatus(project, experiment)
    # terminating the experiment
    #terminateExperiment(project, profile)
end