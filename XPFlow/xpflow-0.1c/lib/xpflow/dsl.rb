# encoding: UTF-8

#
# DSL implementation.
#

module XPFlow

    class LibraryLink

        constructor :process, :key, :parts

        def method_missing(method, *args, &block)
            new_parts = @parts + [ method.to_s ]
            full_name = new_parts.join(".")
            obj = @process.library.resolve_name(full_name)
            if obj.nil?
                raise "No such object '#{full_name}'"
            end
            if obj.is_a?(Library)
                raise NoMethodError, "Library referencing requires no args" if args.length > 0
            else
                # activity/process
                args = XPValue.flatten(args)
                full_name = XPValue.flatten(full_name)
                run = RunDSL.new(@process, @key, full_name, args, {}, block)
                return @process.push(run)
            end
            return LibraryLink.new(@process, @key, new_parts)
        end
    end

    class Key

        def initialize(array)
            @array = array
        end

    end

    class DSL

        def initialize(process, key)
            @process = process
            if key.nil?
                @_key = []
            elsif key.is_a?(Array)
                @_key = key
            elsif key.is_a?(String)
                @_key = from_string(key)
            else
                raise "Unsupported key type"
            end
            @current_key = -1
            @keys = []
        end

        def from_string(s)  # string => Array
            raise "error" unless s.start_with?("/")
            arr = s.split("/"); arr.shift
            return arr
        end

        def to_string(arr)
            return "/" + arr.join("/")
        end

        def key
            return to_string(@_key)
        end

        def new_key
            @current_key += 1
            key = @_key + [ @current_key ]
            @keys.push(key)
            return to_string(key)
        end

        def parse(*args, &block)
            begin
                $current_dsl.push(self)
                self.instance_exec(*args, &block)
            ensure
                $current_dsl.pop
            end
            return self
        end

        def repr
            {
                :key => key()
            }
        end

    end

    $current_dsl = []

    class DSLVariable

        include Operations

        attr_reader :key
        constructor :key

        def to_s
            "Var[-@@@@-#{key}-@@@@-]"
        end

        def self.replace(s, scope)
            out = s.gsub(/Var\[-@@@@-([\/\d]+)-@@@@-\]/) do |m|
                key = $1
                scope.get(key).to_s
            end
            return out
        end

        def to_ary
            return 10.times.map do |i|
                u = XPValue.flatten(self)
                u.index(XPConst.new(i))
            end
        end

        def as_s
            return method_missing(:to_s)
        end

        def as_i
            return method_missing(:to_i)
        end

        def method_missing(method, *args)
            dsl = $current_dsl.last
            raise "Fatal error" if dsl.nil?
            raise "Arguments are unsupported" if args.length > 0
            return dsl.get_of(self, method)
        end

    end

    class RunDSL < DSL

        constructor [ :process, :key ], :name, :args, :opts, :block

        def repr
            super.merge({
                :type => :run,
                :name => @name,
                :args => @args,
                :opts => @opts
            })
        end

        def collect_meta(xxxx)
            {

            }
        end

        def as_run
            return ActivityRun.new(key, @name, @args, @opts, @block)
        end

    end

    class ReturnLoopDSL < DSL 

        constructor [ :process, :key ], :flag, :cond, :value

        def as_run
            return ReturnLoopRun.new(key, @flag, @cond, @value)
        end
    end

    class CheckpointDSL < DSL

        constructor [ :process, :key ], :name, :opts, :parent

        def as_run
            return CheckpointRun.new(new_key, @name, @opts, @parent)
        end
    end

    class OtherwiseDSL < DSL

        constructor [ :process, :key ]

    end

    class ListDSL < DSL

        constructor [ :process, :key ], :list

        def __list__
            return @list
        end

        def __as_run__
            return @list.map(&:as_run)
        end

        def push(x, inc = 0)
            @list.push(x)
            return DSLVariable.new(x.key)
        end

        def parse_and_push(dsl, *args, &block)
            return push(dsl.parse(*args, &block))
        end

        def as_run
            runs = __as_run__
            return SequenceRun.new(key, runs)
        end

        def __workflow__(*args)
            block, _ = @process.current_workflow
            seq = SequenceDSL.new(@process, new_key)
            return parse_and_push(seq, *args, &block)
        end

        ### DSL PART ###

        def parallel(opts = {}, &block)
            retries = opts[:retry]
            if retries.nil?
                dsl = ParallelDSL.new(@process, new_key)
                return parse_and_push(dsl, &block)
            else
                try :retry => retries do
                    parallel(&block)
                end
            end
        end

        def any(&block)
            one = XPValue.flatten(-1)
            dsl = ManyDSL.new(@process, new_key, one)
            return parse_and_push(dsl, &block)
        end

        def many(arg, &block)
            n = XPValue.flatten(arg)
            dsl = ManyDSL.new(@process, new_key, n)
            return parse_and_push(dsl, &block)
        end

        def formany(arg, array, &block)
            n = XPValue.flatten(arg)
            array = XPValue.flatten(array)
            dsl = ForManyDSL.new(@process, new_key, n, array)
            return parse_and_push(dsl, &block)
        end

        def sequence(&block)
            dsl = SequenceDSL.new(@process, new_key)
            return parse_and_push(dsl, &block)
        end

        def seq(&block)
            return sequence(&block)
        end

        def seqtry(&block)
            dsl = SeqtryDSL.new(@process, new_key)
            return parse_and_push(dsl, &block)
        end

        def foreach(array, opts = {}, &block)
            array = XPValue.flatten(array)
            opts = XPValue.flatten(opts)
            dsl = ForEachDSL.new(@process, new_key, array, opts)
            return parse_and_push(dsl, &block)
        end

        def forall(array, opts = {}, &block)
            array = XPValue.flatten(array)
            opts = XPValue.flatten(opts)
            dsl = ForAllDSL.new(@process, new_key, array, opts)
            return parse_and_push(dsl, &block)
        end

        def times(loops, &block)
            loops = XPValue.flatten(loops)
            dsl = TimesDSL.new(@process, new_key, loops)
            return parse_and_push(dsl, &block)
        end

        def forany(array, &block)
            one = XPValue.flatten(-1)
            array = XPValue.flatten(array)
            dsl = ForManyDSL.new(@process, new_key, one, array)
            return parse_and_push(dsl, &block)
        end

        def on(condition, &block)
            condition = XPValue.flatten(condition)
            dsl = IfDSL.new(@process, new_key, condition)
            return parse_and_push(dsl, &block)
        end

        def switch(*args, &block)
            if args.length == 0
                s = SwitchDSL.new(@process, new_key)
                parse_and_push(s, &block)
            elsif args.length == 1
                s = BoundSwitchDSL.new(@process, new_key, XPValue.flatten(args.first))
                parse_and_push(s, &block)
            else
                raise
            end
        end

        def multi(&block)
            dsl = MultiDSL.new(@process, new_key)
            return parse_and_push(dsl, &block)
        end

        def try(opts = {}, &block)
            opts = XPValue.flatten(opts)
            dsl = TryDSL.new(@process, new_key, opts)
            return parse_and_push(dsl, &block)
        end

        def result(path, opts = {}, &block)
            # TODO: reimplement with macros!
            opts = XPValue.flatten(opts)
            path = XPValue.flatten(path)
            dsl = ResultDSL.new(@process, new_key, path, opts)
            return parse_and_push(dsl, &block)
        end

        def loop(opts = {}, &block)
            opts = XPValue.flatten(opts)
            dsl = LoopDSL.new(@process, new_key, opts)
            return parse_and_push(dsl, &block)
        end

        def cache(opts = {}, &block)
            dsl = CacheDSL.new(@process, new_key, opts)
            return parse_and_push(dsl, &block)
        end


        def info(opts = {}, &block)
            opts = XPValue.flatten(opts)
            dsl = InfoDSL.new(@process, opts)
            return parse_and_push(dsl, &block)
        end

        def run(arg, *args, &block)
            # Kernel.puts "run: #{args} #{args.inspect}"
            opts = XPFlow::parse_comment_opts(__FILE__)
            name = nil
            if arg.is_a?(Hash)
                opts = opts.merge(arg)
                name, args = args.first, args.tail
            else
                name = arg
            end
            raise 'No name given' if name.nil?
            args = XPValue.flatten(args)
            name = XPValue.flatten(name)
            return push(RunDSL.new(@process, new_key, name, args, opts, block))
        end

        def rerun(name, *args, &block)
            # TODO
            try :retry => 100000 do   # as many times as needed
                run(name, *args, &block)
            end
        end

        def sleep(t)
            # this has to be present in DSL for some rather obscure reasons :)
            return method_missing(:sleep, t)
        end

        def puts(*args)
            # overloads the standard 'puts'
            return method_missing(:log, *args)
        end

        def fail(*args)
            # same here
            return method_missing(:fail, *args)
        end

        def system(cmd)
            # same here
            return method_missing(:system, cmd)
        end

        def send(o, method, *args)
            # same reason as sleep
            return method_missing(:send, o, method, *args)
        end

        def method_missing(method, *args, &block)
            # this is rather tricky:
            #   1. DSL has predefined commands.
            #   2. When no command matches we try to find "injected" activity, or activity
            #      the was injected into the DSL. That way we can move many DSL commands to activities.
            #   3. When injected activities do not match, we try to match with a namespace. If there
            #      is a library with such a name we return a special variable. The only use for that
            #      is to be able to run activities like that: run g5k.reserve_nodes
            #   4. If nothing matches, we raise an error.

            # pp @process.library.traversal_graph

            name = method.to_s
            activity = @process.library.get_activity_or_nil(name)

            if activity.is_a?(MacroDSL)
                m = activity
                seq = nil
                raise "Macro must be provided with a workflow" if block.nil?
                @process.with_workflow(block, args) do
                    seq = SequenceDSL.new(@process, new_key)
                    seq.parse(*args, &m.block)
                    push(seq)
                end
                return seq
            end

            if activity.nil? == false
                args = XPValue.flatten(args)
                name = XPValue.flatten(name)
                opts = XPFlow::parse_comment_opts(__FILE__)
                run = RunDSL.new(@process, new_key, name, args, opts, block)
                return push(run)
            end

            library = @process.library.get_library_or_nil(name)

            if library.nil? == false
                raise NoMethodError, "Library referencing requires no args" if args.length > 0
                return LibraryLink.new(@process, new_key, [ method.to_s ])
            end

            if name.end_with?('_of') and [ 1, 2 ].include?(args.length)
                name = name.chomp('_of')
                return self.get_of(args.first, name.to_sym, args[1])
            end

            raise NoMethodError, "Unknown or malformed DSL command or no such activity (:#{method})"
        end

        def _visit(*args)
            pp caller
            raise "Somebody did something stupid (see #{self.class})."
        end

        def experiment_scope(name = nil, &block)
            # creates a new experiment scope
            dsl = ExperimentDSL.new(@process, name)
            return parse_and_push(dsl, &block)
        end

        ### END OF DSL ###

    end

    class SequenceDSL < ListDSL

        def initialize(process, key)
            super(process, key, [])
        end

        def self.repr(o)
            return {
                :key => o.key,
                :type => :seq,
                :body => o.__list__.map(&:repr)
            }
        end

        def repr
            return SequenceDSL.repr(self)
        end

    end

    class ProcessDSL < SequenceDSL

        attr_reader :args
        attr_reader :name
        attr_reader :library

        def initialize(name, library, &block)
            super(self, [])
            @name = name
            @library = library
            @workflows = []  # a stack of current workflows used in macros
            if block.nil?
                raise "Block is nil?"
            end
            count = block.arity
            if count >= 0
                @args = count.times.map { |i| DSLVariable.new(new_key()) }
            else
                @args = 10.times.map { |i| DSLVariable.new(new_key()) }
            end
            self.parse(*@args, &block)
        end

        def checkpoint(*args)
            name = nil
            opts = {}
            opts = args.pop if args.last.is_a?(Hash)
            raise 'Wrong arguments' if args.length > 1
            name = args.first if args.length == 1
            push(CheckpointDSL.new(@process, new_key, name, opts, self))
        end

        def get_injection(name)
            return @library.get_injection(name)
        end

        def as_process
            keys = @args.map(&:key)
            seq = self.as_run
            return ProcessActivity.new(@name, keys, seq)
        end

        def repr
            return {
                :type => :process,
                :name => @name,
                :body => SequenceDSL.repr(self)
            }
        end

        def with_workflow(m, args)
            begin
                @workflows.push([ m, args ])
                yield
            ensure
                @workflows.pop
            end
        end

        def current_workflow
            raise "No current workflow" if @workflows.length == 0
            return @workflows.last
        end

    end


    class InnerDSL < SequenceDSL

        alias :sequence_run :as_run

    end

    class WithParamsDSL < InnerDSL

        def parse(&block)
            args = @args.map { |x| DSLVariable.new(x) }
            return super(*args, &block)
        end

        def repr
            super.merge({
                :args => @args
            })
        end

    end


    class SeqtryDSL < InnerDSL

        constructor [ :process, :key ]

        def as_run
            return SeqtryRun.new(key, sequence_run.body)
        end

    end

    class ExperimentDSL < InnerDSL

        constructor [ :process ], :name

        def as_run
            return ExperimentRun.new(@process.get_key, @name, sequence_run)
        end

    end

    class ForEachDSL < WithParamsDSL

        constructor [ :process, :key ], :array, :opts

        def init
            @args = [ new_key() ] # iterator
        end

        def as_run
            return ForEachRun.new(key, @array, @args.first, @opts, sequence_run)
        end

        def repr
            super.merge({
                :type => :foreach,
                :array => @array
            })
        end

    end

    class ParallelDSL < InnerDSL

        def as_run
            return ParallelRun.new(key, __as_run__)
        end
    end

    class TimesDSL < WithParamsDSL

        constructor [ :process, :key ], :loops

        def init
            @args = [ new_key() ]  # iterator
        end

        def as_run
            return TimesRun.new(key, @loops, @args.first, sequence_run)
        end
    end

    class ForAllDSL < WithParamsDSL

        constructor [ :process, :key ], :array, :opts

        def init
            @args = [ new_key() ] # iterator
        end

        def as_run
            return ForAllRun.new(key, @array, @args.first, @opts, sequence_run)
        end
    end

    class ForManyDSL < WithParamsDSL

        constructor [ :process, :key ], :number, :array

        def init
            @args = [ new_key() ] # iterator
        end

        def as_run
            return ForManyRun.new(key, @number, @array, @args.first, sequence_run)
        end

    end

    class ManyDSL < InnerDSL

        constructor [ :process, :key ], :number

        def as_run
            return ManyRun.new(key, @number, __as_run__)
        end

    end

    class TryDSL < InnerDSL

        constructor [ :process, :key ], :opts

        def as_run
            return TryRun.new(key, @opts, sequence_run)
        end

    end

    class ResultDSL < InnerDSL

        constructor [ :process, :key ], :path, :opts

        def as_run
            return ResultRun.new(key, @path, @opts, sequence_run)
        end

    end

    class CacheDSL < InnerDSL

        constructor [ :process, :key ], :opts

        def as_run
            return CacheRun.new(key, @opts, sequence_run)
        end

    end

    class InfoDSL < InnerDSL

        constructor [ :process, :key ], :opts

        def as_run
            return InfoRun.new(key, @opts, sequence_run)
        end
    end


    class IfDSL < SequenceDSL

        constructor [ :process, :key ], :cond

        def otherwise
            push(OtherwiseDSL.new(@process, new_key))
        end

        def as_run
            i = nil
            @list.length.times do |j|
                i = j if (@list[j].is_a?(OtherwiseDSL))
            end
            on_true = []
            on_false = []
            if i.nil?
                on_true = @list
            else
                on_true = @list[0..(i-1)]
                on_false = @list[(i+1)..-1]
                raise if (on_true.length + on_false.length + 1) != @list.length
            end
            on_true = ListDSL.new(@process, new_key, on_true).as_run
            on_false = ListDSL.new(@process, new_key, on_false).as_run
            return IfRun.new(key, @cond, on_true, on_false)
        end

    end

    class LoopDSL < WithParamsDSL

        constructor [ :process, :key ], :opts

        def init
            @flag = new_key()
            @iter = new_key()
            @array = new_key()
            @args = [ @iter, @array ]
        end

        def return_on(cond, value = nil)
            cond = XPValue.flatten(cond)
            value = XPValue.flatten(value)
            push(ReturnLoopDSL.new(@process, key, @flag, cond, value))
        end

        def as_run
            return LoopRun.new(key, @flag, @iter, @array, __as_run__, @opts)
        end
    end

    class SwitchDSL < DSL

        constructor [ :process, :key ], :cases => [], :default => nil

        def on(cond, &block)
            body = SequenceDSL.new(@process, new_key).parse(&block)
            @cases.push([ XPValue.flatten(cond), body ])
        end

        def default(&block)
            @default = SequenceDSL.new(@process, new_key).parse(&block)
        end

        def _cases_as_runs
            return @cases.map { |c, b| [ c, b.as_run ] }
        end

        def _default_as_run
            return nil if @default.nil?
            return @default.as_run
        end

        def as_run
            return SwitchRun.new(key, _cases_as_runs, _default_as_run)
        end
    end

    class MultiDSL < SwitchDSL

        def as_run
            return MultiRun.new(key, _cases_as_runs, _default_as_run)
        end
    end

    class BoundSwitchDSL < SwitchDSL

        constructor [ :process, :key ], :cond

        def as_run
            return BoundSwitchRun.new(key, _cases_as_runs, _default_as_run, @cond)
        end
    end

    class MacroDSL

        # stores a block for workflow construction later

        attr_reader :block

        constructor :name, :engine, :block

    end

end
