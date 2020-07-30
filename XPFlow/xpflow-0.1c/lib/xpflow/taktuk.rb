
require 'thread'
require 'securerandom'

module XPFlow

    class TakTukRun

        @@mutex = Mutex.new
        @@counter = 0
        @@hash = SecureRandom.hex(16)

        attr_reader :filename

        def initialize(taktuk, nodes, opts = {})
            @taktuk = taktuk
            @nodes = nodes
            @opts = { :escape => 1 }.merge(opts)
            _write_run_file()
        end

        def self.get_uniq
            @@mutex.synchronize do
                @@counter += 1
                @@counter
            end
        end

        def _ensure_file(key)
            @opts[key] = %(mktemp).strip unless @opts.key?(key)
            return @opts[key]
        end

        def filename
            return _ensure_file(:filename)
        end

        def stdout
            return _ensure_file(:stdout)
        end

        def stderr
            return _ensure_file(:stderr)
        end

        def grouped_nodes
            # gives a hash of lists that contain all nodes
            # merged together at each key - they will be together in taktuk execution
            # for better locality etc.
            h = Hash.new { |h, k| h[k] = [] }
            @nodes.each { |x| h[x.group].push(x) }
            return h
        end

        def nodes_mapping
            # gives a mapping from .userhost to a list of nodes
            # this handles the duplicated nodes
            h = Hash.new { |h, k| h[k] = [] }
            @nodes.each { |x| h[x.userhost].push(x) }
            return h 
        end

        def _write_run_file
            File.open(filename, "w") do |f|
                f.puts("#!/bin/bash")
                f.puts("set -eu")
                f.puts("TAKTUK=${TAKTUK:-#{@taktuk}}")
                f.puts("$TAKTUK #{@opts[:propagate] ? '-s' : ''} \\")
                grouped_nodes().each_pair do |group, ns|
                    # f.puts("-b \\")  # -b and -e cause bugs!!! grrrh!! TakTuk hangs!
                    ns.each { |x| f.puts("  -m #{x.userhost} \\") }
                    # f.puts("-e \\")
                end
                f.puts('"$@"')
            end
            return self
        end

        def execute_raw(cmd, opts = {})
            # execute the command at the lowest level
            # return stdout & stderr, but throw an exception if taktuk failed
            original_cmd = cmd
            opts = @opts.merge(opts)
            opts[:escape].times { cmd = Shellwords.escape(cmd) }

            real_command = "bash #{filename} synchronize broadcast exec [ #{cmd} ]"

            output = %x(#{real_command} < /dev/null 1> #{stdout} 2> #{stderr})

            raise ExecutionError.new("Command '#{original_cmd}' returned error (see #{stdout} and #{stderr})!") if $?.exitstatus != 0
        
            return [ stdout, stderr ]
        end

        def execute_shell(cmd, opts = {})
            # executes 'cmd' in a shell, so shell variables and redirections are possible

            out, err = execute_raw(cmd, opts)

            # parsing of the output
            # EXAMPLE: root@172.16.0.3-2: hostname > /tmp/nazwa (3825): status > Exited with status 0

            status_exp = /^(\S+)-(\d+): .+\((\d+)\): status > Exited with status (\d+)$/
            output_exp = /^(\S+)-(\d+): .+\((\d+)\): (output|error) > (.+)$/

            outputs = Hash.new { |h, k| h[k] = [] }
            errputs = Hash.new { |h, k| h[k] = [] }
            results = []

            File.open(out).each_line do |line|
                m = line.strip.match(output_exp)
                if m
                    _, rank, _, stream, text = m.captures
                    (stream == "output" ? outputs : errputs )[rank.to_i].push(text)
                    next
                end
                m = line.strip.match(status_exp)
                if m
                    node, rank, ident, status = m.captures
                    results.push({ :name => node, :rank => rank.to_i, :ident => ident.to_i, :status => status.to_i })
                    next
                end
            end

            names = nodes_mapping()
            results.each do |r|
                r[:stdout] = outputs[r[:rank]].join("\n")
                r[:stderr] = errputs[r[:rank]].join("\n")
                r[:node] = names[r[:name]].pop()
                raise "Fatal error" if r[:node].nil?
            end

            return results
        end

        def execute(cmd, opts = {})
            original_cmd = cmd
            results = execute_shell(cmd, opts)
            return _split_results(results)
        end

        def execute_remote(cmd, opts = {})
            # executes a command which results will be stored remotely
            original_cmd = cmd
            prefix = "/tmp/.taktuk--#{@@hash}--#{TakTukRun.get_uniq}"
            out_file, err_file = proc { |x| "#{prefix}--out--#{x}" }, proc { |x| "#{prefix}--err--#{x}" }
            out, err = out_file.call("$TAKTUK_RANK"), err_file.call("$TAKTUK_RANK")

            real_cmd = "#{cmd} 1> #{out} 2> #{err}"
            results = execute_shell(real_cmd, opts)

            results.each do |r|
                rank = r[:rank]
                r[:stdout_file] = out_file.call(rank)
                r[:stderr_file] = err_file.call(rank)
            end

            return _split_results(results)
        end

        def put(src, dest, opts = {})
            # distributes a file over all nodes
            # returns md5's for all nodes

            real_command = "bash #{filename} synchronize broadcast put [ #{src} ] [ #{dest} ]"
            output = %x(#{real_command} 1> /dev/null 2> /dev/null)

            succ, fail = execute("md5sum #{dest}")

            if fail.length != 0
                raise "Some nodes failed (try #{real_command})."
            end

            succ.each { |x| x[:hash] = x[:stdout].split.first }

            return succ
        end

        def _split_results(results)
            return [
                results.select { |r| r[:status] == 0 },
                results.select { |r| r[:status] != 0 }
            ]
        end

    end

end


if $0 == __FILE__

end
