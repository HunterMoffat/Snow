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
require 'logger'
# A module for xpflow that enables the power to start, terminate and monitor experiments given they have portal tools installed

#module XPFlow; module POWDER
    class Powder
        $LOG = Logger.new('powder.txt')
        #@path ='~/portal-tools/bin/'
        $PROFILE = ''
        $PROJECT = ''
        $EXPERIMENT = ''
        $PATH = '~/portal-tools/bin/'
        # PATH = PATH TO PORTAL-TOOLS/BIN/ ?

        # TODO Parameter set functions 
        def initialize(*args)
            # profile, project, experiment
            if args.size == 3
                $PROJECT  = args[0]
                $EXPERIMENT = args[1]
                $PROFILE = args[2]
            end
        end
        # Profile setter
        # def profile(name)
        #     @profile = name
        # end
        # # Project setter
        # def project(name)
        #     @project = name
        # end

        # # Experiment setter
        # def experiment(name)
        #     @experiment = name
        # end

        def startExperiment(*args)
            if args.size == 3
                $LOG.debug("Starting Experiment: #{$EXPERIMENT}, using profile #{$PROFILE} in project #{$PROJECT}")
                system("cd #{ $PATH } && ./startExperiment --project #{$PROJECT} --name #{$EXPERIMENT} PortalProfiles,#{$PROFILE}")
            else
                system("cd #{ $PATH } && ./startExperiment --project #{@project} --name #{@experiment} PortalProfiles,#{@profile}")
                puts "Starting the experiment with 0 args!\n"
            end
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
#     class Library < ActivityLibrary
#         attr_accessor :logging
#         activities :startExperiment, :terminateExperiment, :experimentStatus,
#                    :Profile, :project, :experiment
#         def initialize
#             super
#             @cache = Cache.new
#             # G5K.install_ssh_config_file(g5k.user)
#             inject_library('__core__', CoreLibrary.new)
#         end
        
#         def startExperiment(*args)
#             if args.size == 3
#                 puts "Starting the experiment with 3 args!\n"
#                 system("cd #{ $PATH } && ./startExperiment --project #{project} --name #{experiment} PortalProfiles,#{profile}")
#             else
#                 system("cd #{ $PATH } && ./startExperiment --project #{@project} --name #{@experiment} PortalProfiles,#{@profile}")
#                 puts "Starting the experiment with 0 args!\n"
#             end
#         end
#     end
# end;
# end
# end


