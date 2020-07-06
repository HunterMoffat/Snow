require 'tempfile'
require 'etc'
require 'json'
require 'xpflow'
require 'restclient'
require 'pp'
require 'digest'
require 'date'
require 'cgi'
require 'shellwords'
# A module for xpflow that enables the power to start, terminate and monitor experiments given they have portal tools installed
module XPFlow; module POWDER
    SSH_CONFIG = "/tmp/.xpflow_ssh_config_#{Etc.getlogin}"
    class POWDER
        PROFILE = ''
        PROJECT = ''
        EXPERIMENT = ''
        # TODO Parameter set functions 

        # Profile setter
        def profile(name)
            PROFILE = name
        end
        # Project setter
        def project(name)
            PROJECT = name
        end

        # Experiment setter
        def experiment(name)
            EXPERIMENT = name
        end

        def startExperiment(project, experiment, profile)
            # TODO: FIGURE OUT HOW TO NAVIGATE TO PORTAL TOOLS FILE
            system("./startExperiment --project #{project} --name #{experiment} PortalProfiles,#{profile}")
        end
        def terminateExperiment(project, experiment)
            # TODO: FIGURE OUT HOW TO NAVIGATE TO PORTAL TOOLS FILE
            system("./terminateExperiment #{project},#{experiment}")
        end
        def experimentStatus(project, experiment)
            # TODO: FIGURE OUT HOW TO NAVIGATE TO PORTAL TOOLS FILE
            system("./experimentStatus #{project},#{experiment}")
        end
    end
end
end

