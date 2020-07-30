# encoding: UTF-8

#
# Takes care of command line interface.
#

module XPFlow

    class RunInfo

        attr_reader :name
        attr_reader :args

        def initialize(name, *args)
            @name = name
            @args = args
        end

    end

    class CmdlineError < Exception

        def ignore?
            return false
        end

    end

    class UnknownCommandError < CmdlineError

        def initialize(cmd)
            super("unknown command `#{cmd}'")
        end

    end

    class CmdlineNoFileError < CmdlineError

        def initialize(path)
            super("file `#{path}' does not exist")
        end
    end

    class CmdlineIgnoreError < CmdlineError

        def ignore?
            return true
        end
    end

    class Options

        attr_reader :args
        attr_reader :config
        attr_reader :includes
        attr_reader :command
        attr_reader :entry

        def initialize(args)
            @args = args.clone
            @command = nil
            @config = Options.defaults
            @includes = []
            @entry = nil
            @verbose = false
            parse
        end

        def verbose?
            return @verbose
        end

        def self.defaults
            # Define a sane default configuration
            {
                :labels => [],
                :ignore_checkpoints => false,
                :checkpoint => nil,
                :activity => nil,
                :instead => [],
                :after => [],
                :vars => {}
            }
        end

        def load_config(conffile)
            if !File.exist?(conffile)
                raise CmdlineNoFileError.new(conffile)
            end
            type = File.extname(conffile).downcase
            contents = File.read(conffile)

            data = case type
                when '.json' then JSON.parse(contents)
                when '.yaml' then YAML.load(contents)
                else raise CmdlineError.new("unknown config file type (#{type})")
            end

            raise CmdlineError.new("bad config file format") unless data.is_a?(Hash)

            return data
        end

        # Parses options from the command line

        def parse
            parser = OptionParser.new do |opts|
                opts.banner = [
                    "Usage: #{$0} <command> [options] ARGUMENTS",
                    "",
                    "Available commands:",
                    "",
                    "  * help -- show help",
                    "  * run <files*> -- run a workflow from a file",
                    "  * workflow <files*> -o <output> -- generate a workflow from a file",
                    "",
                    "Options:"
                ].join("\n")

                opts.on("-v", "--verbose", "Run verbosely") do
                    @config[:labels] += [ :verbose ]
                    @verbose = true
                end
                opts.on("-q", "--quiet", "Run quietly") do
                    @config[:labels] = [ :normal ]
                end
                opts.on("-p", "--paranoiac", "Run paranoically") do
                    @config[:labels] += [ :verbose, :paranoic ]
                end
                opts.on("-l", "--labels LABELS", "Log messages labeled with LABELS") do |labels|
                    @config[:labels] += labels.split(',').map { |x| x.downcase.to_sym }
                end
                
                opts.on("-i", "--ignore-checkpoints", "Ignore automatically saved checkpoints") do
                    @config[:ignore_checkpoints] = true
                end
                opts.on("-c", "--checkpoint NAME", "Jump to checkpoint NAME (if exists)") do |name|
                    @config[:checkpoint] = name
                end
                # opts.on("-c", "--list-checkpoints", "List available checkpoints") do
                #    @config[:instead] += [ RunInfo.new(:list_checkpoints) ]
                # end
                # opts.on("-i", "--info NAME", "Show information NAME") do |name|
                #     @config[:instead] += [ RunInfo.new(name.to_sym) ]
                # end
                # opts.on("-L", "--list", "List declared activities") do
                #     @config[:instead] += [ RunInfo.new(:activities) ]
                # end
                opts.on("-g", "--gantt", "Show Gantt diagram after execution") do
                    @config[:after] += [ RunInfo.new(:show_gantt) ]
                end
                opts.on("-G", "--save-gantt FILE", "Save Gantt diagram information to FILE") do |name|
                    @config[:after] += [ RunInfo.new(:save_gantt, name) ]
                end
                opts.on("-V", "--vars SPEC", "Set variables from the cmdline") do |spec|
                    pairs = spec.split(',').map { |x| x.split('=') }
                    unless pairs.all? { |x| x.length == 2 }
                        raise CmdlineError.new("Wrong vars syntax - <name>=<value> expected.")
                    end
                    @config[:vars].merge!(Hash[*pairs.flatten])
                end
                opts.on("-f", "--file FILE", "Set variables from a YAML file") do |file|
                    params = load_config(file)
                    @config[:vars].merge!(params)
                end
                opts.on("-o", "--output FILE", "Set output file for some commands") do |file|
                    @config[:output] = file
                end
            end

            parser.parse!(@args)
            
            @config[:labels] += [ :normal ]
            @config[:labels].uniq!

            @command = @args.first
            @params = @args.tail

            if command == "help" || command.nil?
                show_usage(parser)
                raise CmdlineIgnoreError.new
            elsif command == "version"
                raise CmdlineError.new("Unsupported.")
            elsif command == "run"
                load_files()
            elsif command == "workflow"
                if @config[:output].nil?
                    raise CmdlineError.new("output file must be provided with -o switch")
                end
                load_files()
            else
                # try to parse command as a filename
                begin
                    @entry = parse_activity_spec(command)
                rescue CmdlineNoFileError
                    raise UnknownCommandError.new(command)
                end
                @command = "run"
                @params = @args
                load_files()
            end
        end

        def load_files
            # loads files from command line
            if @params.length == 0
                raise CmdlineError.new("at least one file must be given")
            end
            @entry = parse_activity_spec(@params.first)
            @params.each do |spec|
                x = parse_activity_spec(spec)
                @includes.push(x.first)
            end
        end

        def parse_activity_spec(path)
            parts = path.split(":", 2)
            activity = nil
            if parts.length == 1
                activity = "main"  # by default use 'main' activity
            else
                path, activity = parts
            end
            if !File.exist?(path)
                raise CmdlineNoFileError.new(path)
            end
            return [ path, activity ]
        end

        def vars
            return @config[:vars]
        end

        def dispatch(obj)
            if @command == "run"
                return obj.execute_run(*@entry)
            elsif @command == "workflow"
                return obj.execute_workflow(*@entry)
            end
        end

        def show_usage(parser)
            Kernel.puts(parser.banner)
            Kernel.puts(parser.summarize); Kernel.puts
        end

    end

end
