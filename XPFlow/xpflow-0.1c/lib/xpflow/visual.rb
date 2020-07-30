# encoding: UTF-8

#
# Visualization of engine execution/data.
#

def dict(h)
    return XPFlow::Visual::Dict.new(h)
end

module XPFlow

    module Visual

        class Dict

            def initialize(h)
                @h = h
            end

            def to_h
                return @h
            end

            def method_missing(method)
                return @h[method]
            end

            def [](key)
                return @h[key]
            end

            def to_s
                return "d(#{@h.to_s})"
            end

        end

        def self.pair_activities(events)
            # returns a list with pairs named
            # after the activities, and values
            # being start, finish

            starts = events.select { |x| x.type == :start_activity }
            starts = starts.sort { |x, y| x.meta[:time] <=> y.meta[:time] }
            ends = events.select { |x| x.type == :finish_activity }
            contents = ends.map { |x| [ x.meta[:name], x.meta[:time] ] }
            ends = Hash[ contents ]

            return starts.map do |ev|
                name = ev.meta[:name]
                start = ev.meta[:time]
                finish = ends[name]
                dict({ :name => name, :start => start, :finish => finish, :meta => ev.meta })
            end
        end

        def self.get_times(activities)
            t_start = activities.map(&:start).min
            t_finish = activities.map(&:finish).compact.max
            return [ t_start, t_finish, t_finish - t_start ]
        end

        def self.terminal_size
            begin
                return `tput cols`.to_i - 14
            rescue Errno::ENOENT
                return nil
            end
        end

        def self.show_gantt(events)
            
            if events.empty?
                puts
                puts "=== GANTT DIAGRAM IS EMPTY ===".red
                puts
                return
            end

            times = compute_times(events)
            activities = times[:activities]
            t_start, t_finish, t_span = times[:time_start], times[:time_finish], times[:time_span]
            left_size = activities.map { |x| x[:name].length }.max # length of names

            width = terminal_size()
            width = width - left_size unless width.nil?
            width = 80 if (width.nil? or width < 80)

            puts
            puts "=== ACTIVITY GANTT DIAGRAM ===".red
            puts
            activities.each do |a|
                a = dict(a)
                chars = (width * a.graph_span).to_i
                margin = (width * a.graph_start).to_i
                bar = ('=' * chars).yellow
                indent = (' ' * margin)
                status = (a.finished ? '%.3f s' % a.secs_span : 'running')
                puts "%s  %s%s (%s)" % \
                    [ a.name.ljust(left_size).white!, indent, bar, status ]
            end
        end

        def self.compute_times(events)
            activities = pair_activities(events)
            activities = activities.select { |x| !x.name.start_with?("__") }
            t_start, t_finish, t_span = get_times(activities)
            activities = activities.map do |x|
                finished = (!x.finish.nil?)
                v = {
                    :name => x.name,
                    :finished => finished,
                    :time_start => x.start,
                    :time_finish => x.finish,
                    :time_span => finished ? x.finish - x.start : nil,
                    :secs_start => x.start - t_start,
                    :secs_finish =>  finished ? x.finish - t_start : t_span,
                    :secs_span => finished ? x.finish - x.start : t_finish - x.start,
                }
                v[:graph_start] = v[:secs_start] / t_span
                v[:graph_finish] = v[:secs_finish] / t_span
                v[:graph_span] = v[:secs_span] / t_span
                v
            end
            return {
                :time_start => t_start,
                :time_finish => t_finish,
                :time_span => t_span,
                :activities => activities
            }
        end

        def self.save_gantt(filename, events)
            times = compute_times(events)
            IO.write(filename, times.to_yaml)
        end

        def self.show_activities()
            events = $engine.runtime.events()
            activities = pair_activities(events)
            activities = activities.select { |x| x.finish.nil? }
            $console.synchronize do
                bar = ("=" * 80).red
                tab = ' ' * 4
                puts; puts bar
                puts "CURRENT ACTIVITIES".blue
                activities.each do |x|
                    puts "#{tab}#{x.meta[:name].green} #{x.meta.inspect}"
                end
                puts bar
            end
        end
    end

    def self.show_stacktrace(e)
        trace = e.stacktrace

        puts
        puts "=== ERRORS ===".red

        tab = ' ' * 4
        for error in trace
            msg, frames = error
            puts tab + "#{msg}".yellow
            for f in frames
                line = (tab * 2) + "#{f.location_long}"
                line += " (at #{f.obj.class})" if f.obj
                puts line
            end
        end
    end

    class TerminalThread
        # a thread that listens on the terminal
        # to collect events
        # assumes stdin is tty

        def initialize
            @config = %x(stty --save).strip
            @r, @w = IO.pipe
            @t = nil
        end

        def cols
            size = %x(stty size).split
            return size.last.to_i
        end

        def start
            system("stty -icanon -echo")
            @t = Thread.new do
                loop do
                    ready = IO.select([ STDIN, @r ], [], []).first
                    if ready.include?(STDIN)
                        char = STDIN.readpartial(1)
                        c = cols()
                        case char
                            when 'i' then Visual.show_activities()
                            else begin
                                $console.synchronize do
                                    puts "Key #{char.inspect} pressed.".rjust(c).blue
                                end
                        end
                            
                        end
                    end
                    break if ready.include?(@r)
                end
            end
        end

        def stop
            system("stty #{@config}")
            @w.close
            @t.join(1.0)
        end

        def self.start_thread
            if STDIN.tty? and not ENV.key?("BATCH")
                $__terminal_thread__ = TerminalThread.new
                $__terminal_thread__.start
                at_exit { $__terminal_thread__.stop }
            end
        end

    end

end

