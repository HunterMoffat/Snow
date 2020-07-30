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
require 'io/console'
# A module for xpflow that enables the power to start, terminate and monitor experiments given they have portal tools installed

module XPFlow; module POWDER
    class PowderExperiment
        
        attr_accessor :profile
        attr_accessor :project
        attr_accessor :experiment
        attr_accessor :username
        attr_accessor :node_names
        # @profile = ''
        # @project = ''
        # @experiment = ''
        
        # creates a powder experiment object
        def initialize(project,experiment,profile)
            @project = project
            @experiment = experiment
            @profile = profile
            @username = ''
            @node_names = Array.new
        end

    end
    class Library < ActivityLibrary
        attr_accessor :logging
        attr_accessor :log
        activities :startExperiment, :terminateExperiment, :experimentStatus, 
        :startMultiple, :terminateMultiple, :statusMultiple
        
        $path = '~/portal-tools/bin/'


        def initialize
            super
            @cache = Cache.new
            inject_library('__core__', CoreLibrary.new)
            @log = XPFlow::Logging.new
            @log.add($console, :console)
        end
        # starts a powder experiment using arguments in form (project, experiment, profile) or a powder experiment object
        def startExperiment(*args)
            if args.size == 3
                proj = args[0]
                exp = args[1]
                prof = args[2]
                @log.log ("Starting Powder Experiemnt: #{exp}, under the project: #{proj} using profile: #{prof}")
                res = system("cd #{ $path } && ./startExperiment --project #{proj} --name #{exp} PortalProfiles,#{prof}")
                @log.log(res)
            elsif args.size == 1
                proj = args[0].project
                exp = args[0].experiment
                prof = args[0].profile
                @log.log ("Starting Powder Experiemnt: #{exp}, under the project: #{proj} using profile: #{prof}")
                system("cd #{ $path } && ./startExperiment --project #{proj} --name #{exp} PortalProfiles,#{prof}")
            end
        end

        # Terminates the given experiment using arguments in form (project, experiment) or a powder experiment object
        def terminateExperiment(*args)
            if args.size == 2
                proj = args[0]
                exp = args[1] 
                @log.log("Terminating Experiment: #{exp}")
                res = system("cd #{ $path } && ./terminateExperiment #{proj},#{exp}")
                @log.log(res)
            else 
                proj = args[0].project
                exp = args[0].experiment
                @log.log("Terminating Experiment: #{exp}")
                res = system("cd #{ $path } && ./terminateExperiment #{proj},#{exp}")
                @log.log(res)
            end
        end
        # checks the status of a given experiment using arguments in form (project, experiment) or a powder experiment object
        def experimentStatus(*args)
            if args.size == 2
                proj = args[0]
                exp = args[1] 
                @log.log("Status of Experiment: #{exp}, Project: #{proj}")
                res = system("cd #{ $path } && ./experimentStatus #{proj},#{exp}")
                @log.log(res)
            else 
                proj = args[0].project
                exp = args[0].experiment
                @log.log("Status of Experiment: #{exp}, Project: #{proj}")
                res = system("cd #{ $path } && ./experimentStatus #{proj},#{exp}")
                @log.log(res)
            end
        end
        # Starts multiple experiments given a list of experiments
        def startMultiple(*args)
            for i in args do
                startExperiment(i)
            end
        end
        # Terminates multiple experiments given a list of experiments
        def terminateMultiple(*args)
            for i in args do
                terminateExperiment(i)
            end
        end
        # checks the status of multiple experiments given a list of experiments
        def statusMultiple(*args)
            for i in args do
                experimentStatus(i)
            end
        end
        # "node.myexp3.reu2020.emulab.net"
        def powder_execute_one(experiment,username,node_name, command)
            ssh = "#{node_name}.#{experiment.experiment}.#{experiment.project}.emulab.net"
            
        end
    end
end;
end
