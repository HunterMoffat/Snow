
# This code is not used anywhere
# runs ensemble of processes in parallel

class Procee

    attr_reader :pid
    attr_accessor :ident

    def initialize(cmd, out, err = nil)
        @cmd = cmd
        @out = File.open(out, "w")
        @err = err
        @pipe = nil
    end

    def spawn
        r, w = @pipe = IO.pipe
        opts = { :out => w, :in => "/dev/null" }
        opts[2] = @err.nil? ? "/dev/null" : @err
        @pid = Process.spawn(@cmd, opts)   # r, w is closed in the child process.
        w.close
    end

    def handler
        return @pipe.first
    end

    def consume(bytes)
        @out.write(bytes)
    end

end

class Ensemble

    def defaults
        {
            :timeout => 1.0,
            :buffer => 256
        }
    end

    def initialize(arr = nil, opts = {})
        arr = [] if arr.nil?
        @procs = []
        @opts = defaults.merge(opts)
        arr.each { |x| add(*x) }
    end

    def add(cmd, out, err = nil)
        p = Procee.new(cmd, out, err)
        p.ident = @procs.length
        @procs.push(p)
    end

    def launch()
        running = @procs.length
        pipes = {}
        @procs.each do |p|
            p.spawn()
            pipes[p.handler] = p
        end

        closed = []

        while running > 0
            arrays = IO.select(pipes.keys, [], [], @opts[:timeout])
            break if arrays.nil?
            ready = arrays.first
            ready.each do |r|
                p = pipes[r]
                begin
                    bytes = r.sysread(@opts[:buffer])
                    p.consume(bytes)
                rescue EOFError
                    running -= 1
                    pipes.delete(r)
                    closed.push(p.ident)
                    # puts "#{p.pid} finished."
                end
            end
        end
        
        # waiting for all of them to finish

        pidmap = {}
        @procs.each { |p| pidmap[p.pid] = p.ident }
        pids = @procs.map { |p| p.pid }

        status = {}

        iterations = 0
        delta = 0.5
        while pids.length > 0 && iterations < @opts[:timeout]
            p = Process.waitpid(-1, Process::WNOHANG)
            if p.nil?
                Kernel.sleep(delta)
                iterations += delta
                next
            end
            status[pidmap[p]] = $?
            pids.delete(p)
        end

        pids.each do |p|
            Process.kill(:KILL, p)
            Process.waitpid(p)
            status[pidmap[p]] = $?
        end

        result = {}

        status.each_pair do |ident, s|
            x = result[ident] = {
                :status => s.exitstatus,
                :blocked => !closed.include?(ident),
                :signal => s.termsig
            }
            x[:ok] = !x[:blocked] && x[:status] == 0 && x[:signal].nil?
        end

        puts result.inspect
    end

end

if __FILE__ == $0
    e = Ensemble.new([
        [ "echo -n 456 1>&2", "/tmp/1", "/tmp/err" ],
        [ "echo 123", "/tmp/2" ],
        [ "echo EDF", "/tmp/3" ] ])

    r = e.launch
end
