
# this is a temporary directory that contains
# files generated on-the-fly to simplify things

require 'tmpdir'
require 'thread'
require 'fileutils'
require 'monitor'
require 'erb'
require 'ostruct'
require 'yaml'

module XPFlow

    class ExecutionError < StandardError

    end

    class LocalExecutionResult

        def initialize(cmd, stdout, stderr)
            @cmd = cmd
            @stdout = stdout
            @stderr = stderr
        end

        def stdout
            return IO.read(@stdout)
        end

        def stderr
            return IO.read(@stderr)
        end

        def stdout_file
            return @stdout
        end

        def stderr_file
            return @stderr
        end

        def command
            return @cmd
        end

        def to_s
            return "LocalExecutionResult(#{@cmd}, out => #{@stdout}, err => #{@stderr})"
        end

    end

    class DirectoryManager

        attr_reader :path

        def initialize(path)
            @mutex = Monitor.new
            if path.nil?
                @path = Dir.mktmpdir()  # TODO: remove while exiting
                # use remove_entry_secure
            else
                if File.directory?(path)
                    FileUtils.remove_entry_secure(path)
                end
                Dir.mkdir(path)
                @path = path
            end
            @counter = 0
        end

        def synchronize(&block)
            return @mutex.synchronize(&block)
        end

        def mktemp(&block)
            fname = synchronize do
                @counter += 1
                File.join(@path, "tmpfile-#{@counter}")
            end
            if block_given?
                File.open(fname, "wb", &block)
            end
            return fname
        end

        def join(name)
            return File.join(@path, name)
        end

        def open(fname, flags, &block)
            path = File.join(@path, fname)
            return synchronize { File.open(path, flags, &block) }
        end

        def run_with_files(name, stdout, stderr, opts = {})
            # assumes that name is properly escaped!!!
            name = join(name)
            out = `#{name} 2> #{stderr} > #{stdout}`
            raise ExecutionError.new("Command #{name} returned error (see #{stdout} and #{stderr})!") if $?.exitstatus != 0
            return LocalExecutionResult.new(name, stdout, stderr)
        end

        def run(name, opts = {})
            return run_with_files(name, self.mktemp(), self.mktemp(), opts)
        end

        def run_ssh(cmd, opts = {})
            # runs a command remotely
            # the form is ".../ssh 'ENV cmd args' "
            # TODO: Escaping yo!

            stdout = (opts[:out].nil?) ? self.mktemp() : opts[:out]
            stderr = (opts[:err].nil?) ? self.mktemp() : opts[:err]
            stdin  = opts.fetch(:in, "/dev/null")

            if opts[:env] and opts[:env] != {}
                prefix = opts[:env].each_pair.map { |k, v| "#{k}=#{v}" }.join(" ")
                cmd = "#{prefix} #{cmd}"
            end

            if opts[:wd]
                cmd = "cd #{opts[:wd]}; #{cmd}"
            end

            cmd = Shellwords.escape(cmd)
            cmd = "ssh #{cmd}"
            real_cmd = join(cmd)
            out = `#{real_cmd} < #{stdin} 2> #{stderr} 1> #{stdout}`

            raise ExecutionError.new("Command #{real_cmd} failed (see #{stdout} and #{stderr})") if $?.exitstatus != 0
            return LocalExecutionResult.new(cmd, stdout, stderr)
        end

        def _subdir(name)
            path = join(name)
            Dir.mkdir(path) # TODO: what if exists?
            return DirectoryManager.new(path)
        end

        def subdir(name)
            synchronize { _subdir(name) }
        end

    end

end # module
