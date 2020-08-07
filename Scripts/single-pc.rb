process :main do
    username  = 'Hmoffat'
    profile = 'Moffat_LTE'
    project = 'reu2020'
    exp1 = 'test'
    gnu = powderExperiment(project, exp1, profile)
    log("STARTING WORKFLOW")
    log("PINGING")
    powder_execute_one(gnu ,'sim-ran',username,"ping -c 3 -I oaitun_ue1 8.8.8.8")
end
    