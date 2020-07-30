
# some runtime related
# activities

module XPFlow

    # TODO
    # I have to decide what is a model of an event

    class RuntimeEvent

        attr_reader :type
        attr_reader :meta

        constructor :type, :meta

        def to_s
            "<Event: type = #{@type.inspect}, meta = #{@meta.inspect}>"
        end

    end

    class RuntimeLibrary < MonitoredActivityLibrary

        activities :activities,
            :run_group, :show_gantt, :save_gantt,
            :start, :finish, :event, :dump_events, :events,
            :list_checkpoints,
            :list => :activities

        def setup
            @events = []
        end

        def checkpoint
            return @events
        end

        def restore(state)
            @events = state
        end

        # these are routed as well from stdlib.rb
        def event(type, meta = {})
            ev = RuntimeEvent.new(type, {}.merge(meta))
            @events.push(ev)
        end

        def start(name, meta = {})
            event(:start, meta.merge({ :name => name }))
        end

        def finish(name, meta = {})
            event(:finish, meta.merge({ :name => name }))
        end

        def dump_events
            # debug activity
            pp @events
        end

        def events(type = nil, &block)
            if type.nil?
                events = @events
            else
                events = @events.select { |e| ev.type == type }
            end
            events = events.select(&block) if block_given?
            return events.dup
        end

        def activities
            puts "List of activities:"
            ns = proxy.engine.get_global_namespace()
            lines = ns.map { |k, v| "   * #{v.info}" }.sort
            puts lines.join("\n")
        end

        def self.save_workflow(filename, engine, name)
            p = engine.get_activity_object(name)
            ns = name.to_s.split(".")[0...-1]
            opts = { :engine => engine }
            flow = Graphing::XPFlowConverter.from_process(p, ns, opts)

            ext = File.extname(filename).downcase

            ropts = { :debug => false }
            case ext
                when '.tikz' then Graphing.to_tikz(flow, filename, ropts)
                when '.pdf' then Graphing.to_pdf(flow, filename, ropts)
                when '.png' then Graphing.to_png(flow, filename, ropts)
                when '.tex' then Graphing.to_latex(flow, filename, ropts)
                else
                    raise "Unsupported format '#{ext}'."
            end

            puts "Workflow of '#{name.to_s.green}' process saved to '#{filename.green}'."
            puts "Check out '#{"tikz_template.tex".green}' template in examples directory." if ext == '.tikz'
        end

        def run_group(infos)
            infos.each do |i|
                proxy.run i.name, *i.args
            end
        end

        def list_checkpoints
            cps = proxy.engine.dumper.list
            puts "List of checkpoints:"
            cps.each_pair do |k, v|
                puts "    #{k} => #{v.first['time_string']}"
            end
        end

        def show_gantt
            Visual.show_gantt(events())
        end

        def save_gantt(filename)
            Visual.save_gantt(filename, events())
        end

    end

end
