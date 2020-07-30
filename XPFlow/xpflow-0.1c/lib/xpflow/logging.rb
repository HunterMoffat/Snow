
require 'thread'

module XPFlow

    class AbstractLog

        def initialize
            @mutex = Mutex.new
        end

        def open(*args)
            raise "Not implemented!"
        end

        def log(*args)
            raise "Not implemented!"
        end

        def close(*args)
            raise "Not implemented!"
        end

        def synchronize(&block)
            return @mutex.synchronize(&block)
        end

    end

    class ConsoleLog < AbstractLog

        def initialize
            super
        end

        def log(*msgs)
            synchronize do
                msgs.each do |x|
                    x = x.plain unless STDOUT.tty?
                    puts x
                end
                STDOUT.flush
            end
        end

        def open; end
        def close; end

    end

    class FileLog < AbstractLog

        def initialize(fname)
            super()
            @fname = fname
            @f = nil
        end

        def open
            @f = File.open(@fname, "w")
            return self
        end

        def log(*msgs)
            synchronize do
                msgs.each do |x|
                    @f.write("#{x.plain}\n")
                end
                @f.flush
            end
        end

        def close
            @f.close
            @f = nil
        end

    end

    class Logging

        def initialize
            @loggers = {}
        end

        def add(logger, label)
            @loggers[label] = logger
        end

        def prefix
            t = Time.now
            s = t.strftime('%Y-%m-%d %H:%M:%S.%L')
            ms = t.usec / 1000
            return s.gsub('%L', "%03d" % ms) # Ruby 1.8 compat
        end

        def colorize(s, label)
            colors = {
                :normal => :green,
                :verbose => :yellow,
                :paranoic => :red,
                :default => :red!
            }
            c = colors[:default]
            c = colors[label] if colors.key?(label)
            return s.send(c)
        end

        def log(msg, label = :normal)
            pre = colorize(prefix, label)
            msg = "[ %s ] %s" % [ pre, msg ]
            @loggers.each_pair do |k, v|
                v.log(msg)
            end
            # TODO: kind of ugly
            Scope.current[:__experiment__].log(msg)  # log to the experiment
        end

        def get(label)
            return @loggers[label]
        end

        def using(&block)
            ls = @loggers.values
            opened = []
            x = nil?
            begin
                ls.each { |x| x.open(); opened.push(x) }
                x = block.call
            ensure
                opened.each { |x| x.close } # TODO
            end
            return x
        end

    end

    $console = ConsoleLog.new  # globally accessible, should be used by everybody

end

if __FILE__ == $0
    require 'colorado'
    s = "cze".green + "yo".red
    x = XPFlow::Logging.new
    x.add(XPFlow::ConsoleLog.new, :console)
    x.add(XPFlow::FileLog.new("test.log"), :file)

    x.using do
        x.log(s)
    end

end
