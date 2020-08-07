# A test that creates an experiment based off of the single-pc profile from POWDER
require 'thread'
process :main do
    username  = 'Hmoffat'
    profile = 'single-pc'
    project = 'reu2020'
    exp1 = 'one'
    exp2 = 'two'
    one = powderExperiment(project, exp1, profile)
    two = powderExperiment(project, exp2, profile)
    experiments = Array.new(2)
    experiments[0] = one
    experiments[1] = two
    log('Status of Multiple Experiments')
    res = statusMultiple(experiments)
    log("Status: #{res}")
    log("Executing simple commands")
    powder_execute_one( one, 'node', username, 'hostname && time')
    powder_execute_one( one, 'node', username, 'hostname && time')
    #terminateMultiple(experiments)
end
