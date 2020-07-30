# encoding: UTF-8

#
# Implementation of core activities.
#

require 'erb'
require 'ostruct'

module XPFlow

    class Erb < OpenStruct

        def render(hash)
            ERB.new(hash).result(binding)
        end

        def self.render(template, hash)
            x = Erb.new(hash)
            return x.render(template)
        end

    end

    # SSH = Net::SSH

    class CoreLibrary < HiddenActivityLibrary

        activities :sleep, :value, :code, :log, :repr, :system, :range,
                :render_file, :render, :render_inline, :assert, :debug,
                :start, :set_scope, :get_scope, :fail, :new_experiment,
                :arguments, :item_range, :shift,
                :send => :send_method, :id => :value, :"λ" => :code

        def render_inline(template, hash = {})
            return Erb.render(template, hash)
        end

        def shift(array)
            return [ array.first, array.tail ]
        end

        def render(name, hash = {})
            tmpl = $files[name]
            raise "Template does not exist!" if tmpl.nil?
            template = IO.read(tmpl)
            return render_inline(template, hash)
        end

        def arguments(shift = 0)
            tab = Scope.current.parent_activity[:__name__].arguments
            return tab[shift ... tab.length]
        end

        def new_experiment
            # inserts a new experiment in the +1 scope
            scope = Scope.current.parent_activity
            parent_experiment = scope[:__experiment__]
            name = scope[:__name__].activity_full_name
            scope[:__experiment__] = parent_experiment.create_subexperiment(name)
        end

        def render_file(name, out, hash = {})
            s = render(name, hash)
            File.open(out, "wb") do |f|
                f.write(s)
            end
            return nil
        end

        def sleep(time)
            span = Timespan.to_secs(time)
            if span.infinite?
                loop do; Kernel.sleep(1) end
            end
            Kernel.sleep(span)
        end

        def system(cmd)
            result = `#{cmd}`
            status = $?
            code = status.exitstatus
            raise "'#{cmd}' returned with code = #{code}" if code != 0
            return result
        end

        def value(*args)
            return args.first if args.length == 1
            return args
        end

        def code(*args)
            raise 'No code given.' unless block_given?
            return yield(*args)
        end

        def flatten_msgs(msgs)
            return msgs.map { |m| m.__repr__ }.join("")
        end

        def get_scope(name)
            return Scope.current[name]
        end

        def process_name
            return Scope.current.parent[:__name__].activity_full_name
        end

        def log(*msgs)
            msg = "Process %s: %s" % [ process_name.green, flatten_msgs(msgs) ]
            proxy.engine.log(msg)
            return nil
        end

        def debug(*msgs)
            proxy.engine.debug(
                "Process %s: %s" % [ process_name.green, flatten_msgs(msgs) ])
            return nil
        end

        def fail(msg = "?", prob = 1.0)
            raise "Failure (reason: #{msg})" if (Kernel.rand <= prob)
        end

        def send_method(o, method, *args)
            return o.send(method.to_sym, *args) if o.respond_to?(method)
            return o[method] if (o.is_a?(Hash) and o.key?(method))
            return o[method.to_s] if (o.is_a?(Hash) and o.key?(method.to_s))
            raise "No '#{method}' method for #{o.class}"
        end

        def repr(v)
            return v.__repr__
        end

        def range(*args)
            f = args.first
            if args.length == 1 and f.is_a?(Range)
                return f.to_a
            elsif args.length == 1 and f.is_a?(Fixnum)
                return range(0 ... f)
            elsif args.length == 2
                return range(f ... args.last)
            elsif args.length == 3
                return (args[0] .. args[1]).step(args[2]).to_a
            end
            raise "Wrong arguments to range: #{args}"
        end

        def item_range(items, last)
            return items[0 ... last]
        end

        def set_scope(key, value)
            Scope.current.parent.parent[key] = value   # TODO: that's kind of weird
        end

        def assert(condition)
            raise "Assertion failed." unless condition
        end

        # mapped from runtime library

        def start(*args)
            return proxy.engine.runtime.invoke(:start, args)
        end

        def finish(*args)
            return proxy.engine.runtime.invoke(:finish, args)
        end

        def event(*args)
            return proxy.engine.runtime.invoke(:event, args)
        end

    end

    class GetSetLibrary < SyncedActivityLibrary

        activities :get, :set, :config, :config_full,
            :entry_activity,
            :conf => :config

        attr_accessor :configuration

        include SerializableLibrary

        def setup
            @storage = {}
            @configuration = {}
        end

        def get(key)
            raise "Unknown key: #{key}" unless @storage.key?(key)
            return @storage[key]
        end

        def set(key, value)
            @storage[key] = value
        end

        def config(key)
            raise "Unknown config option: #{key}" unless @configuration.key?(key)
            return @configuration[key]
        end

        def config_full
            return @configuration
        end

        def update_config(hash)
            h = {}
            hash.each_pair do |k, v|
                h[k.to_sym] = v
            end
            @configuration.merge!(h)
        end

        def set_entry_activity(name)
            set(:__original_entry__, name)
        end

        def entry_activity
            return get(:__original_entry__)
        end

    end

    class RunLater
        # runs an activity later

        attr_reader :name
        attr_reader :args

        def initialize(name, args)
            @name = name
            @args = args
        end

        def to_s
            return "RunLater of '#{@name}' with (#{@args.inspect})"
        end

        def extend(args)
            return RunLater.new(@name, @args + args)
        end

    end

    class DataLibrary < SyncedActivityLibrary

        activities :store, :data, :avg, :sum, :stddev, :gauss,
            :conf_interval, :save_yaml,
            :data_vector, :data_push,
            :run_later, :get_of, :minimal_sample, :sample_enough

        def data_vector(values = nil)
            return ValueData.new(values)
        end

        def get_of(object, key, default = nil)
            str = key.to_s
            sym = key.to_sym
            if object.is_a?(Hash)
                return object[str] if object.key?(str)
                return object[sym] if object.key?(sym)
                return default unless default.nil?
                raise "No such key as '#{key}' in #{object}"
            end

            if object.respond_to?(sym)
                return object.__send__(sym)
            end

            return default unless default.nil?
            raise "No such property as '#{key}' on #{object} of class #{object.class}"
        end

        def setup
            @storage = {}
        end

        def store(name, value)
            @storage[name] = ValueData.new unless @storage.key?(name)
            @storage[name].push(value.to_f)
        end

        def data(name)
            @storage[name] = ValueData.new unless @storage.key?(name)
            return @storage[name]
        end

        def run_later(name, *args)
            if name.is_a?(RunLater)
                return name.extend(args)
            end
            return RunLater.new(name, args)
        end

        def _stddev(vector)
            m = avg(vector)
            disp = vector.map { |x| (x - m)**2 }.reduce(:+)
            var = disp.to_f / (vector.length - 1)
            return (var ** 0.5)
        end

        def _sum(vector)
            return vector.reduce(:+)
        end

        def _avg(vector)
            return sum(vector).to_f / (vector.length)
        end

        def gauss(m = 0.0, s = 1.0)
            x = Kernel.rand
            y = Kernel.rand
            p = (-2 * Math.log(1 - y)) ** 0.5
            return m + s * Math.cos(2*Math::PI*x) * p 
        end

        def data_push(data, x)
            data.push(x)
        end

        def confidence_precision(name)
            return data(name).confidence_precision
        end

        def conf_precision(x)
            return x.confidence_precision
        end

        def confidence_interval(name)
            return data(name).confidence_interval
        end

        def stddev(name)
            return data(name).stddev
        end

        def sum(name)
            if name.is_a?(Array)
                return name.reduce(:+)
            else
                return data(name).sum
            end
        end

        def save_yaml(filename, obj)
            IO.write(filename, obj.to_yaml)
        end

        # opts:
        #  :dist => distribution type (default: :normal, also: :n, :t, :tstudent)
        #  :conf => confidence (default: 0.95)
        #  :rel => relative precision in percents (default: 0.1)
        #  :abs => absolute precision (e.g., 5)

        def _parse_sample_opts(v, _opts)
            opts = { :conf => 0.95, :rel => 0.1, :abs => nil, :dist => :n }.merge(_opts)
            dists = { :n => :n, :normal => :n, :t => :t, :tstudent => :t }
            opts[:dist] = dists[opts[:dist]]
            raise "Wrong confidence" if (opts[:conf] <= 0.0 or opts[:conf] >= 1.0)
            if opts[:abs].nil?
                opts[:abs] = v.average() * opts[:rel]
            end
            opts[:info] = v._dist(opts[:dist], opts[:abs], opts[:conf])
            return opts
        end

        def flatten_data(x)
            if x.is_a?(Array)
                return ValueData.new(x)
            elsif x.is_a?(ValueData)
                return x
            else
                raise "Wrong data type: #{x.class}"
            end
        end

        def sample_enough(v, opts = {})
            v = flatten_data(v)
            opts = _parse_sample_opts(v, opts)
            info = opts[:info]
            return info[:d] <= opts[:abs]
        end

        def minimal_sample(v, opts = {})
            v = flatten_data(v)
            opts = _parse_sample_opts(v, opts)
            return opts[:info][:sample]
        end

        def conf_interval(v, opts = {})
            v = flatten_data(v)
            opts = _parse_sample_opts(v, opts)
            return opts[:info][:interval]
        end

    end

    class TestLibrary < SyncedActivityLibrary
        # used for testing

        attr_reader :values
        activities :collect

        def setup
            @values = []
        end

        def collect(value)
            @values.push(value)
        end

    end

end
