# encoding: UTF-8

#
# Implementation of 'runs' or actions that can be executed
# within the experiment engine. They build logic behind DSL.
#

require 'timeout'

module XPFlow

    class AbstractRun

        include Traverse
        include Meta

        attr_accessor :key
        constructor :key

        def engine
            # shortcut to get an engine
            return Scope.engine
        end

        def run()
            exc = nil
            begin
                x = execute()
                Scope.current[@key] = x
            rescue => e
                raise if (e.is_a?(RunError)) and (e.run == self)
                exc = RunError.new(self, e)
            end
            raise exc unless exc.nil?
            return x
        end

        def run_threads(list, opts = {}, &block)
            # TODO: pool should be in the scope...
            list = listize(list)
            pool_size = engine.getset.get(:pool)
            nonnil = opts.select { |k, v| !v.nil? }
            opts = { :pool => pool_size }.merge(nonnil)
            return Threads.run(self, list, opts, &block)
        end

        def restart()
            # returns non-nil value (in fact, a hash) when can restart from this activity
            # the returned hash contains hash to copy to the scope
            return false
        end

        def listize(o)
            # tries to execute :to_list, if not
            # checks if is an array, otherwise panics
            if o.respond_to?(:to_list)
                o = o.to_list
            end
            if !o.is_a?(Array)
                raise "#{o} is not an array"
            end
            return o
        end

    end


    class SequenceRun < AbstractRun

        attr_reader :body

        constructor [ :key ], :body
        children :body

        def check_restartability()
            name = engine.config(:checkpoint)
            if engine.config(:ignore_checkpoints)
                engine.paranoic("Ignoring checkpoints.") \
                        if @body.any? { |r| r.is_a?(CheckpointRun) }
                return @body
            end
            list = []
            # TODO: I should collect all checkpoints and verify
            for r in @body.reverse do
                if name.nil? == false and r.is_a?(CheckpointRun) and r.name.to_s != name
                    list = [ r ] + list
                    next
                end
                cp = r.restart()
                if cp == true
                    # we restarted
                    engine.log("Checkpoint '#{r.name}' restarted.")
                    break
                else
                    list = [ r ] + list  # standard case
                end
            end
            return list
        end

        def execute()
            tail = check_restartability()
            results = []
            for r in tail do
                x = r.run()
                results.push(x)
            end
            return results.last
        end

        def attach_to_checkpoints(obj)
            @body.each do |i|
                if i.is_a?(CheckpointRun)
                    i.parent = obj
                end
            end
        end

        def split(node)
            before = []
            after = []
            first = true
            @body.each do |el|
                first = false if el == node
                (first ? before : after).push(el) if el != node
            end
            return [before, after].map { |x| ActivityList.new(x) }
        end

    end

    class SeqtryRun < AbstractRun

        attr_reader :body
        constructor [ :key ], :body

        children :body

        def execute()
            result = nil
            return nil if @body.length == 0
            for r in @body do
                fine = true
                begin
                    result = r.run()
                rescue RunError => e
                    engine.verbose("Error caused by #{e.summary}. Trying the next activity.")
                    fine = false
                end
                return result if fine == true
            end
            raise "Seqtry execution failed."
        end

    end

    class ExperimentRun < AbstractRun

        constructor [ :key ], :name, :args
        children :name, :args

        def execute()
            # TODO: more things here
            r = nil
            name = @name.evaluate(Scope.current)
            args = @args.evaluate(Scope.current)
            full_name = "#{name}.__standard__"
            ActivityRun.run_activity_block(full_name) do |activity|
                Scope.region do |scope|
                    # scope[:__collection__] = Collection.new
                    text = "Running experiment #{name}"
                    r = engine.activity_period(text, { :gantt => true }) do
                        activity.execute(args, &@block)
                    end
                end
            end
            return r
        end

        def get_name()
            # tries to evaluate the experiment name
            # without running (if it is possible)
            # returns nil otherwise
            return @name.evaluate_offline()
        end

    end

    class ActivityRun < AbstractRun

        constructor [ :key ], :name, :args, :opts, :block
        children :args

        attr_reader :opts
        attr_reader :name

        def self.run_activity_block(full_name)
            # runs activity using the current scope
            full_name = full_name.to_s
            lib = Scope.current[:__library__]
            ns = Scope.current[:__namespace__]
            if full_name.start_with?("/")
                full_name = full_name[1..-1]
                lib = Scope.engine
            end
            libs, name = lib.into_parts(full_name)
            library = lib.resolve_libs(libs)
            result = Scope.region do |scope|
                scope[:__library__] = library
                scope[:__namespace__] = namespace = ns + libs
                activity = library.get_activity_object(name)
                raise "No such activity '#{namespace.join(".")}.#{name}'" if activity.nil?
                yield(activity)
            end
            return result
        end

        def execute()
            r = nil
            this_name = @name.evaluate(Scope.current)
            preargs = []
            if this_name.is_a?(RunLater)
                preargs = this_name.args
                this_name = this_name.name
            end
            ActivityRun.run_activity_block(this_name) do |activity|
                
                activity_id = engine.activity_id(this_name)
                args = preargs + @args.evaluate(Scope.current)

                opts = { :gantt => true }.merge(activity.opts).merge(@opts)

                text = "#{this_name}:#{activity_id}"

                log_level = :verbose
                if this_name.to_s.start_with?("__")
                    log_level = :paranoic
                end
                if activity.doc.nil? == false
                    text = "[#{activity.doc}] (#{text})"
                    log_level = :normal
                end

                if !opts[:log_level].nil?
                    log_level = opts[:log_level]
                end

                period_opts = opts.merge({ :log_level => log_level })
                r = engine.activity_period(text, period_opts) do
                    activity.execute(args, &@block)
                end
            end
            return r
        end

        def get_name
            @name
        end

        def report(started, args)
            age = Time.now - started
            return {
                :title => "Activity #{get_name.to_s}",
                :args => args.inspect,
                :started => started,
                :age => "#{age} s"
            }
        end

        def to_s
            "<Activity #{get_name}>"
        end

        def builtin?
            # TODO: do it properly
            name = get_name().to_s
            return name.start_with?('__') && !name.start_with?('__nodes__')
        end

    end

    class ForEachRun < AbstractRun

        attr_reader :body

        constructor [ :key ], :list, :iter, :opts, :body
        children :list, :body
        declares :iter

        def execute()
            list = @list.evaluate(Scope.current)
            opts = @opts.evaluate(Scope.current)
            ignore_errors = opts[:ignore_errors]
            result = []
            for item in listize(list) do
                Scope.region do |scope|
                    scope[@iter] = item
                    x = Marker.new
                    begin
                        x = @body.run()
                    rescue RunError
                        raise if !ignore_errors
                    end
                    result.push(x) if !x.is_a?(Marker)
                end
            end
            return result
        end

    end

    class Marker
    end

    class ForAllRun < AbstractRun

        attr_reader :body

        constructor [ :key ], :list, :iter, :opts, :body
        children :list, :body
        declares :iter

        def execute()
            list = @list.evaluate(Scope.current)
            opts = @opts.evaluate(Scope.current)
            size = opts[:pool]
            ignore_errors = opts[:ignore_errors]
            result = OrderedArray.new
            scope = Scope.current
            run_threads(list, :pool => size) do |el, i|
                Scope.set(scope.push, { @iter => el })
                x = Marker.new
                begin
                    x = @body.run()
                rescue RunError
                    raise if !ignore_errors
                end
                result.give(i, x)
            end
            tabl = result.take(list.length)
            tabl = tabl.select { |x| !x.is_a?(Marker) }
            return tabl
        end

    end

    class ForManyRun < AbstractRun

        attr_reader :body

        constructor [ :key ], :number, :list, :iter, :body
        children :number, :list, :body
        declares :iter

        def execute()
            rendez = Meeting.new(self)
            n = @number.evaluate(Scope.current)
            list = @list.evaluate(Scope.current)
            scope = Scope.current
            run_threads(list, :join => false) do |it, _|
                Scope.set(scope.push, { @iter => it })
                x = @body.run()
                rendez.give(x)
            end
            # TODO: what about joining?
            return rendez.take(n)
        end

    end

    class ManyRun < AbstractRun

        attr_reader :body

        constructor [ :key ], :number, :body
        children :number, :body

        def execute()
            n = @number.evaluate(Scope.current)
            rendez = Meeting.new(self)
            scope = Scope.current
            run_threads(@body, :join => false) do |r, _|
                Scope.set(scope)
                x = r.run()
                rendez.give(x)
            end
            return rendez.take(n)
        end

    end

    class ParallelRun < AbstractRun

        attr_reader :body

        constructor [ :key ], :body
        children :body

        def execute()
            arr = OrderedArray.new
            scope = Scope.current
            rs = run_threads(@body) do |r, i|
                Scope.set(scope)
                x = r.run()
                arr.give(i, x)
            end
            values = arr.take(@body.length)
            return values.last
        end
    end

    class IfRun < AbstractRun

        attr_reader :on_true
        attr_reader :on_false

        constructor [ :key ], :condition, :on_true, :on_false
        children :condition, :on_true, :on_false

        def execute()
            x = @condition.evaluate(Scope.current)
            if x
                return @on_true.run()
            else
                return @on_false.run()
            end
        end

    end

    class SwitchRun < AbstractRun

        constructor [ :key ], :cases, :default
        children :cases, :default

        def execute()
            matches = @cases.select { |cond, result| cond.evaluate(Scope.current) }
            return execute_cases(matches)
        end

        def execute_cases(cases)
            if cases.length != 0
                _, r = cases.first # execute only the first match
                return r.run()
            elsif @default
                return @default.run()
            else
                return nil
            end
        end

    end

    class MultiRun < SwitchRun

        def execute_cases(cases)
            if cases.length != 0
                scope = Scope.current
                arr = OrderedArray.new
                ress = run_threads(cases) do |r, i|
                    Scope.set(scope.push)
                    x = r.last.run()
                    arr.give(i, x)
                end
                return arr.take(cases.length)
            elsif @default
                return @default.run()
            else
                return nil
            end
        end

    end

    class BoundSwitchRun < SwitchRun

        constructor [ :key, :cases, :default ], :condition
        children :cases, :default, :condition

        def execute()
            v = @condition.evaluate(Scope.current)
            matches = @cases.select { |cond, result|
                cond.evaluate(Scope.current) == v
            }
            return execute_cases(matches)
        end

    end

    class CheckpointRun < AbstractRun

        attr_accessor :parent

        constructor [ :key ], :name, :opts, :parent
        children

        def name
            return '[no name]' if @name.nil?
            return @name
        end

        def parent_keys
            return @parent.args  # arguments to the process
        end

        def state_keys
            before, after = @parent.split(self)
            vars1 = before.declarations.keys  # vars defined BEFORE the checkpoint
            vars2 = after.vars # vars used AFTER the checkpoint
            return (vars1 + parent_keys) # & vars2
        end

        def meta_info(scope)
            {
                :type => :checkpoint,
                :args => parent_keys.map { |x| scope[x] },
                :name => @name,
                :key => @key,
                :parent => @parent.name
            }
        end

        def checkpointable_libs()
            libs = engine.get_libraries
            libs = libs.select { |ns, l| l.respond_to?(:checkpoint) }
            return libs
        end

        def execute()
            scope = Scope.current
            state = { 'vars' => {} }
            state_keys.each { |k| state['vars'][k] = scope.get(k, true) } # TODO: fix this
            state['meta'] = meta_info(scope)
            lib_dump = checkpointable_libs().map do |ns, l|
                {
                    :state => l.checkpoint(),
                    :namespace => ns
                }
            end
            state['libs'] = lib_dump
            engine.dumper.dump(state, @opts)
            engine.verbose "Checkpoint '#{name}' saved."
            return nil
        end

        def restart()
            scope = Scope.current
            m = meta_info(scope)
            obj = engine.dumper.load(m)
            return false if obj.nil?
            vars = obj['vars']
            libs = obj['libs']
            vars.each_pair { |k, v| scope[k] = v }
            cplibs = checkpointable_libs()
            raise "Fatal checkpoint error (#{cplibs.length} != #{libs.length})" if cplibs.length != libs.length
            raise "Fatal checkpoint error (something wrong)" if cplibs.length != libs.length
            names1 = cplibs.map { |x| x.last }
            names2 = libs.map { |x| x[:namespace] }
            libs.each do |cp|
                ns = cp[:namespace]
                library = cplibs[ns]
                library.restore(cp[:state])
            end
            return true
        end

        def to_s
            "<Checkpoint #{@name.inspect}>"
        end

    end

    class CacheRun < AbstractRun

        attr_reader :body

        constructor [ :key ], :opts, :body
        children :body

        def meta_info()
            {
                :type => :cache,
                :key => @key
            }
        end

        def execute()
            ignoring = engine.config(:ignore_checkpoints)
            m = meta_info()
            o = engine.dumper.load(m)
            if o.nil? or ignoring == true
                value = @body.run()
                obj = { 'meta' => m, 'value' => value }
                engine.dumper.dump(obj)
                return value
            else
                engine.verbose("Cached block for key = #{@key} loaded.")
                return o['value']
            end
        end

    end

    class InfoRun < AbstractRun

        attr_reader :body

        constructor [ :key ], :opts, :body
        children :body

        def execute()
            opts = @opts.evaluate(Scope.current)
            opts = { :fail => true }.merge(opts)
            failed = false
            begin
                start_time = Time.now.to_f
                @body.run()
                end_time = Time.now.to_f
                total_time = end_time - start_time
            rescue RunError => e
                engine.verbose("Info run errored with #{e.summary}")
                failed = true
                total_time = 0.0
            end
            if opts[:fail] and failed
                raise "info block failed: "
            end
            return {
                :time => total_time,
                :failed => failed
            }
        end

    end

    class TryRun < AbstractRun

        attr_reader :body

        constructor [ :key ], :opts, :body
        children :body

        def execute()
            opts = { :retry => 1, :timeout => 0 }.merge(@opts.evaluate(Scope.current))
            engine.verbose("Try block: #{opts}")
            timeout, times = opts[:timeout], opts[:retry]
            times = 1 if times == false
            times = Infinity if times == true
            exc = nil
            for i in 1..times do
                begin
                    if timeout == 0
                        return @body.run()
                    else
                        begin
                            r = Timeout::timeout(timeout, exc) do
                                @body.run()
                            end
                            return r
                        rescue Timeout::Error => e
                            raise RunMsgError.new(self, "Timeout")
                        end
                    end
                rescue RunError => e
                    engine.verbose("Try rerun at #{meta.location}; caused by #{e.summary}")
                    exc = e
                end
            end
            raise exc
        end
    end

    class ResultRun < AbstractRun

        attr_reader :body

        constructor [ :key ], :path, :opts, :body
        children :body

        def execute()
            path = @path.evaluate(Scope.current)
            opts = @opts.evaluate(Scope.current)
            if File.exist?(path)
                engine.log("Result `#{path}' exists already. I won't run again.")
                yaml = IO.read(path)
                return YAML.load(yaml)
            end
            r = @body.run()
            IO.write(path, r.to_yaml)
            return r
        end

    end

    class TimesRun < AbstractRun

        attr_reader :body

        constructor [ :key ], :loops, :iter, :body
        children :body

        def execute()
            loops = @loops.evaluate(Scope.current)
            vals = []
            for i in 0...loops do
                Scope.region do |scope|
                    scope[@iter] = i
                    r = @body.run()
                    vals.push(r)
                end
            end
            return vals
        end

    end

    class LoopRun < AbstractRun

        attr_reader :body

        constructor [ :key ], :flag, :iter, :array, :body, :opts
        children :body

        def execute()
            opts = @opts.evaluate(Scope.current)
            max = opts[:max]
            arr = []
            result = Scope.region do |scope|
                scope[@flag] = done = [ :nothing, nil ]

                count = 0
                while true do
                    scope[@iter] = count
                    scope[@array] = arr.clone
                    res = nil
                    for r in @body do
                        res = r.run()
                        done = scope[@flag]
                        break if done.first != :nothing
                    end
                    break if done.first == :return
                    arr.push(res)
                    count += 1
                    break if (!max.nil? and count >= max)
                end

                if done.last.nil?
                    arr
                else
                    done.last
                end
            end
            return result
        end

    end

    class ReturnLoopRun < AbstractRun

        constructor [ :key ], :flag, :cond, :value
        children

        def execute()
            v = @cond.evaluate(Scope.current)
            if v then
                r = @value.evaluate(Scope.current)
                Scope.current[@flag] = [ :return, r ]
            end
        end
    end

end

