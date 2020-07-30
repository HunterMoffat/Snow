
require 'xpflow'

module Graphing

    class XPFlowConverter

        def self.from_process(process, ns, opts = {})
            c = XPFlowConverter.new(opts, ns)
            return c.do_process(process)
        end

        def initialize(opts, ns = nil)
            @opts = { :builtin => false, :checkpoints => false,
                :engine => nil, :subprocess => true }
            @opts.merge!(opts)
            if ns.nil?
                @ns = []
            else
                @ns = ns
            end
        end

        def engine
            return @opts[:engine]
        end

        def do_process(process)
            raise "Not a process!" if !process.is_a?(XPFlow::ProcessActivity)
            body = xpflow_recurse(process.body)
            return ProcessFlow.new(body)
        end

        def do_subprocess(process, name)
            libs, name = engine.into_parts(name)
            @ns.push(libs)
            list = xpflow_map(process.body.body)
            @ns.pop()
            return SubprocessFlow.new(list, process.doc_name)
        end

        def xpflow_recurse(x)
            klass = x.class.name.split('::').last
            return self.send(('do_' + klass).to_sym, x)
        end

        def xpflow_map(array)
            raise "Not an array (#{array})!" unless array.is_a?(Array)
            array = array.map { |it| xpflow_recurse(it) }
            array = array.compact  # remove nils = hidden elements
            return array
        end

        def do_SequenceRun(x)
            list = xpflow_map(x.body)
            return SequenceFlow.new(list)
        end

        def do_ActivityRun(x)
            # TODO

            if !x.opts[:process].nil?
                name = x.opts[:process]
            else
                name = x.get_name.evaluate_offline()
            end

            unless x.opts[:text].nil?
                return Block.new(x.opts[:text], x.opts)
            end

            if name.nil?
                return Block.new("Dynamic activity")
            end

            original_name = name = name.to_s

            library = @ns.flatten.join(".")
            if library != ""
                name = "#{library}.#{name}"
            end

            if activity_visibility(name) == false
                return nil
            end

            activity = engine.get_activity_object(name)

            return Block.new("#{name} *") if activity.nil?

            activity = engine.get_activity_object(name)
            desc = activity.doc
            if desc.nil?
                desc = original_name
            end

            if !x.builtin? or @opts[:builtin] or activity.doc
                return do_subprocess(activity, original_name) if \
                    activity.is_a?(XPFlow::ProcessActivity) and \
                    @opts[:subprocess]
                # must be an activity
                return Block.new(desc, x.opts)
            end

            return nil
        end

        def do_ExperimentRun(x)
            exp = x.get_name
            if exp.nil?
                return Block.new("Exp run") # TODO
            else
                name = "#{exp}.__standard__"
                activity = engine.get_activity_object(name)
                return do_subprocess(activity, "__standard__")
            end
        end

        def do_ResultRun(x)
            # TODO
            return xpflow_recurse(x.body)
        end

        def do_TimesRun(x)
            # TODO
            return xpflow_recurse(x.body)
        end

        def do_InfoRun(x)
            # TODO
            return xpflow_recurse(x.body) 
        end

        def do_ReturnLoopRun(x)
            # TODO
            return Block.new("Loop return")
        end

        def do_LoopRun(x)
            # TODO
            list = xpflow_map(x.body)
            return SubprocessFlow.new(list, "Loop")
        end

        def do_ParallelRun(x)
            list = xpflow_map(x.body)
            return ParallelFlow.new(list)
        end

        def do_CheckpointRun(x)
            # TODO
            return nil if !@opts[:checkpoints]
            return Block.new("Checkpoint :#{x.name}")
        end

        def do_CacheRun(x)
            # TODO: this should add something more
            return do_SequenceRun(x.body)
        end

        def do_TryRun(x)
            # TODO
            return xpflow_recurse(x.body)
        end

        def do_PeriodRun(x)
            # TODO
            return xpflow_recurse(x.body)
        end

        def do_ForAllRun(x)
            # TODO
            body = xpflow_recurse(x.body)
            return ForallFlow.new([ body ], {})
        end

        def do_ForEachRun(x)
            # TODO
            body = xpflow_recurse(x.body)
            return ForallFlow.new([ body ])
        end

        def do_ForManyRun(x)
            # TODO
            return xpflow_recurse(x.body) 
        end

        def do_IfRun(x)
            # TODO
            on_true = xpflow_recurse(x.on_true)
            on_false = xpflow_recurse(x.on_false)
            return ParallelFlow.new([ on_true, on_false ])
        end

    end

end

if $0 == __FILE__
    require('xpflow/graph')

    # use :g5k

    p = $engine.process :main do |site, sname|
        switch = run 'g5k.switch', site, sname
        log 'Experimenting with switch: ', switch
        nodes = run 'g5k.nodes', switch
        r = run 'g5k.reserve_nodes',
            :nodes => nodes, :time => '02:00:00', :site => site, :keep => false, 
            :type => :deploy, :ignore_dead => true
        nodes = (run 'g5k.nodes', r)
        nodes = code(nodes) { |ns| (ns.length % 2 == 0) ? ns : ns[0...-1] }  # we need an even number of nodes
        master, slaves = (first_of nodes), (tail_of nodes) 
        checkpoint :reserved
        rerun 'g5k.deploy', r, :env => 'squeeze-x64-nfs'
        checkpoint :deployed
        parallel :retry => 100 do
            period :install_pkgs do
                forall slaves do |slave|
                    run({ :gantt => false }, :install_pkgs, slave)
                end
            end
            sequence do
                run :install_pkgs, master
                run :build_netgauge, master
                run :distribute_netgauge, master, slaves
            end
        end
        checkpoint :run_experiment
        output = run :netgauge, master, nodes
        checkpoint :interpret_results
        run :analysis, output, switch
        log "DONE."
    end

    x = Graphing::XPFlowConverter.from_process(p, :builtin => false)
    s = Graphing::TikzGrapher.new(x).draw()
    
    $engine.activity :cze do
        log "cze"
    end

    q = $engine.process :bah do
        run :cze
        run 'whatever'
        run :main
    end
    x = Graphing::XPFlowConverter.from_process(q, 
        :builtin => false, :engine => $engine)
    puts Graphing.to_pdf(x, "cze.pdf", :debug => false)
end
