# encoding: UTF-8

#
# Implementation of core execution engine.
#

$original_argv = [ ]

module XPFlow

    class Context

        attr_reader :activity_full_name
        attr_reader :arguments

        constructor :activity_full_name, :arguments

        def short_name
            return @activity_full_name.split(".").last
        end

    end

    class AbstractActivity

        attr_reader :name
        attr_reader :opts
        constructor :name, :opts

        def execute; raise end
        def info; @opts[:info] end
        
    end

    class ProcessActivity

        include Traverse
        include Meta

        attr_reader :name
        attr_reader :args
        attr_reader :body

        attr_accessor :doc
        attr_accessor :opts

        constructor :name, :args, :body
        children :body

        def init
            # attach checkpoints
            @body.attach_to_checkpoints(self)
            @macro = false
        end

        def set_macro
            @macro = true
        end

        def split(node)
            return @body.split(node)
        end

        def execute(args)
            result = Scope.region do |scope|
                @args.length.times do |i|
                    key = @args[i]
                    scope[key] = args[i]
                end

                scope[:__activity__] = self
                full_name = (scope[:__namespace__] + [ @name ]).join(".")
                scope[:__name__] = Context.new(full_name, args)
                
                unless opts[:idempotent].nil?
                    scope[:__idempotent__] = opts[:idempotent]
                end
                @body.run()
            end
            return result
        end

        def collect_meta(skip)
            super(skip)
            @body.collect_meta(skip + 1)
        end

        def doc_name
            return doc unless doc.nil?
            return name.to_s
        end

        def to_s
            "#<#{info}>"
        end

        def arity
            return @args.length
        end

        def info
            return "Process '#{@name}' with arity = #{arity}"
        end

    end

    class ReturnException < Exception

        attr_reader :value

        def initialize(value)
            super()
            @value = value
        end
    end

    class BlockActivity < AbstractActivity

        constructor [ :name, :opts ], :block
        
        attr_reader :block
        attr_accessor :doc
        attr_accessor :opts

        def doc_name
            return doc unless doc.nil?
            return name.to_s
        end

        def execute(args, &block)
            result = Scope.region do |scope|
                unless opts[:idempotent].nil?
                    scope[:__idempotent__] = opts[:idempotent]
                end
                # puts scope[:__namespace__].inspect
                scope[:__activity__] = self
                full_name = (scope[:__namespace__] + [ @name ]).join(".")
                scope[:__name__] = Context.new(full_name, args)
                proxy = EngineProxy.new(self, block)
                proxy.__parent__ = @opts[:__parent__]
                proxy.execute_proxy(args, @block)
            end
            return result
        end

        def arity
            return @block.arity
        end

        def info
            block_info = XPFlow::block_info(@block)
            return "Activity '#{@name}' with args: { #{block_info} }"
        end

        def to_s
            return info()
        end

    end

    class EngineProxy

        attr_accessor :__parent__

        constructor :activity, :block

        def log(*msgs)
            instance_name = Scope.current[:__name__].activity_full_name
            msg = "Activity %s: %s" % [ instance_name.green, msgs.join('') ]
            engine.log(msg)
            return nil
        end

        def engine
            return Scope.engine
        end

        def collect(v)
            engine.test_lib.invoke(:collect, v)
        end

        def __block__
            return @block
        end

        def execute_proxy(args, block)
            begin
                return self.instance_exec(*args, &block)
            rescue ReturnException => e
                return e.value
            end
        end

        def system(cmd)
            run("__core__.system", cmd)
        end

        def parent(*args)
            raise "No parent activity for #{@activity.name}" if __parent__.nil?
            return __parent__.execute(args)
        end

        def set_result(x)
            Scope.current[:__result__] = x
        end

        def result
            # gives result of a previous execution
            x = Scope.current.get(:__result__, nil)
            return x
        end

        def pass(value = nil)
            # a tricky way to simulate 'return' inside activities
            raise ReturnException.new(value)
        end

        def run(name, *args, &block)
            r = ActivityRun.run_activity_block(name) do |activity|
                activity.execute(args)
            end
            return r
        end

        def execute(*args)
            return run(:"nodes.execute", *args)
        end

        def execute_one(*args)
            return run(:"nodes.execute_one", *args)
        end

        def execute_many(*args)
            return run(:"nodes.execute_many", *args)
        end

    end

    class BasicLibrary < Library

        # library with initialized core functionality

        attr_reader :runtime
        attr_reader :test_lib

        def initialize()
            super()
            inject_library('__data__', DataLibrary.new)
            inject_library('__core__', CoreLibrary.new)

            @runtime = RuntimeLibrary.new
            import_library('runtime', @runtime)

            @test_lib = TestLibrary.new
            @getset_lib = GetSetLibrary.new
            @collection_lib = CollectionLibrary.new

            @getset_lib.set(:pool, 16) ## default parallelism

            inject_library('__test__', @test_lib)
            inject_library('__getset__', @getset_lib)
            inject_library('collection', @collection_lib)

            @nodes_lib = NodesLibrary.new
            inject_library('nodes', @nodes_lib)
        end

    end

    class Engine < BasicLibrary

        attr_reader :dumper
        
        attr_reader :nodes_manager
        attr_reader :main_directory
        attr_reader :opts

        def initialize(conf = {})
            super()

            @conf = {
                :experiment_class => Experiment,
                :dumper_class => FileDumper
            }.merge(conf)

            if ENV.key?("TESTING") or conf[:testing] == true
                @conf[:experiment_class] = ExperimentBlackHole
                @conf[:dumper_class] = MemoryDumper
            end

            @lock = Mutex.new
            @cv = ConditionVariable.new

            @scope = Scope.push

            @opts = nil
            @config = Options.defaults

            @activity_ids = {}

            @inline_process_counter = 0
            @inline_processes = {}

            @error_handlers = []
            @finish_handlers = []
            @after_handlers = []

            @logging = Logging.new
            @logging.add($console, :console)

            @dumper = @conf[:dumper_class].new

            # username = ENV["USER"]
            # @main_directory = DirectoryManager.new("/tmp/xpflow-#{username}") # TODO
            @main_directory = DirectoryManager.new(nil)
            @nodes_manager = NodesManager.new(@main_directory.subdir("nodes"))

        end

        def init_from_options(opts)
            @config = opts.config

        end

        def getset
            return @getset_lib 
        end

        def console
            return @logging.get(:console)
        end

        ### CONCURRENCY

        def synchronized
            @lock.synchronize do
                yield
            end
        end
        
        def wait
            @cv.wait(@lock)
        end

        def broadcast
            @cv.broadcast
        end

        def collected
            return @test_lib.values
        end




        ### HANDLERS

        def call_error_handlers(e)
            @error_handlers.each do |args, block|
                block.call(e, *args)
            end
        end

        def call_finish_handlers
            hs = @finish_handlers
            verbose("Running #{hs.length} finalizers") if hs.length > 0
            hs.each do |args, block|
                block.call(*args)
            end
        end

        def call_after_handlers
            @after_handlers.each do |args, block|
                block.call(*args)
            end
        end

        def on_error(*args, &block)
            @error_handlers.push([args, block])
        end

        def on_finish(*args, &block)
            @finish_handlers.push([args, block])
        end

        def on_after(*args, &block)
            @after_handlers.push([args, block])
        end

        def _execute(cmd)
            out = %x(#{cmd} 2> /dev/null).strip
            return [ out, $?.exitstatus ]
        end

        def _get_git_tag
            me = realize(__FILE__)
            my_dir = File.dirname(me)
            has_git = false

            _, code = _execute("git --version")
            return "(git is not installed)" if code != 0

            status, code = _execute("cd #{my_dir} && git status --porcelain")
            return "(not git repo)" if code != 0

            tag, code = _execute("cd #{my_dir} && git rev-parse --short HEAD")
            return "(no tag?)" if code != 0

            if status == ""
                return tag
            else
                return "#{tag} (with changes)"
            end
        end

        def list_variables
            log "Variable list follows:"
            if $variables.nil? == false
                $variables.each_pair do |k, v|
                    log "    #{k} = #{v}"
                end
            end
            log "End of variable list."
        end

        ### EXECUTION

        def execute(name, *args)
            # IO.write("./.xpflow-graph.yaml", self.traversal_graph.to_yaml) # TODO
            r = nil
            Scope.current[:__engine__] = self
            Scope.current[:__experiment__] = @conf[:experiment_class].new("__root__", "./results").install()
            Scope.current[:__library__] = self
            Scope.current[:__namespace__] = []
            begin
                log("Execution started.")
                log("Cmdline: " + $original_argv.inspect)
                log("Git tag: " + _get_git_tag())
                log("Temporary path is #{main_directory.path}")
                list_variables()
                t = Timer.measure do
                    r = ActivityRun.run_activity_block(name) do |activity|
                        activity.execute(args)
                    end
                end
                log("Execution finished (#{t.with_ms} s).")
            rescue RunError => e
                log("Execution failed miserably.")
                call_error_handlers(e)
                raise
            ensure
                call_finish_handlers()
                call_after_handlers()
            end
            return r
        end

        def execute_with_tb(*args)
            ok = false
            begin
                v = execute(*args)
                ok = true
            rescue RunError => e
                XPFlow::show_stacktrace(e)
            end
            return [ v, ok ]
        end

        def execute_quiet(*args)
            ok = true
            begin
                execute(*args)
            rescue RunError => e
                ok = false
            end
            return ok
        end

        ### LOGGING

        def log(msg, label = :normal)
            return if label == :none
            @logging.log(msg, label) if @config[:labels].include?(label)
        end

        def debug(msg)
            verbose(msg)
        end

        def verbose(msg, paranoic = false)
            log(msg, paranoic ? :paranoic : :verbose)
        end

        def paranoic(msg)
            log(msg, :paranoic)
        end

        ### ACTIVITY TRACKING

        def activity_id(name)
            synchronized do
                @activity_ids[name] = 0 unless @activity_ids.key?(name)
                @activity_ids[name] += 1
                @activity_ids[name]
            end
        end

        def activity_period(name, opts = {}, &block)
            label = opts[:log_level] || :paranoic
            gantt = (opts[:gantt] == true)
            log("Started activity %s." % [ name.green ], label)
            begin
                @runtime.invoke(:event, [ :start_activity, { :name => name, :time => Time.now } ]) if gantt
                t = Timer.measure(&block)
                log("Finished activity %s (%s s)." % [ name.green, t.with_ms ], label)
                return t.value
            rescue => e
                verbose("Activity %s failed: %s" % [ name.green, e.to_s ])
                raise
            ensure
                @runtime.invoke(:event, [ :finish_activity, { :name => name, :time => Time.now } ]) if gantt
            end
        end

        ### CONFIGURATION

        def config(label)
            value = @config[label]
            yield(value) if (value && block_given?)
            return value
        end


        ### Command dispatching

        def execute_run(filename, activity)

            $entry_point = realpath(filename)

            main_activity = get_activity_or_nil(activity)
            
            if main_activity.nil?
                Kernel.puts "There is no activity :#{activity} in the namespace. Quitting."
                exit 1
            end

            Kernel.srand(var(:seed, :int, 31415926535))
    
            res = execute_with_tb(activity)

            @config[:after].each do |runinfo|
                activity = @runtime.get_activity_or_nil(runinfo.name.to_s)
                activity.execute(runinfo.args)
            end

            return res

        end

        def execute_workflow(filename, activity)
            return RuntimeLibrary.save_workflow(@config[:output], self, activity)
        end

    end

    class TestEngine < Engine

        def initialize
            super(:testing => true)
        end

    end

end
