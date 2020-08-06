require 'fileutils'
file = File.open("/opt/nextepc/install/98-nextepc.netdev")
File.write(file, "[NetDev]
                Name=pgwtun
                Kind=tun
                EOF")