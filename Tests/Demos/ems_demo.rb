# A DEMO OF THE EMS USING POWDER TO COMMUNICATE

# ███████╗██╗ ██████╗██╗  ██╗    ██████╗ ███████╗███╗   ███╗ ██████╗ 
# ██╔════╝██║██╔════╝██║ ██╔╝    ██╔══██╗██╔════╝████╗ ████║██╔═══██╗
# ███████╗██║██║     █████╔╝     ██║  ██║█████╗  ██╔████╔██║██║   ██║
# ╚════██║██║██║     ██╔═██╗     ██║  ██║██╔══╝  ██║╚██╔╝██║██║   ██║
# ███████║██║╚██████╗██║  ██╗    ██████╔╝███████╗██║ ╚═╝ ██║╚██████╔
# ╚══════╝╚═╝ ╚═════╝╚═╝  ╚═╝    ╚═════╝ ╚══════╝╚═╝     ╚═╝ ╚═════╝ 

process :main do
    #ssh1 = 'Hmoffat@pc11-fort.emulab.net' 
    ssh2 = "#{var(:ssh)}"
    puts ssh2
    #ssh2 = "Hmoffat@pc02-mebvm-2.emulab.net"
    # cellsdr1-browning-comp
    # b210-humanities-nuc2
    # cmd3 = "sudo srsue"
    # cmd4 = "ifconfig tun_srsue"
    # cmd5 = "ping 172.16.0.1"
    node = simple_node(ssh2)
    # r = execute_one(node, cmd4)
    # log "Executing #{r.command}.  Stdout is: \n #{r.stdout}"
    log "Pinging"
    r2 = execute_one(node,"hostname")
    log "Executing #{r2.command}.  Stdout is: \n #{r2.stdout}"
    
    # res = try :retry => 10, :timeout => 1 do
    #     log("Retrying")
    #     execute_one(node, "invalid command")
    # end
    # log res
end
