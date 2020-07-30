
# encoding: UTF-8

#
#  Implements useful routines and some nasty/ugly/ingenious/beautiful tricks. 
#

require 'thread'

class Class

    def __build_constructor__(*fields)
        attrs = []
        supers = []
        inits = Hash.new

        if fields.first.is_a?(Array)
            supers = fields.first
            attrs = fields[1..-1]
        else
            attrs = fields
        end

        if attrs.last.is_a?(Hash)
            inits = attrs.last
            attrs.pop
        end

        s = "def initialize("
        s += (supers + attrs).map { |x| x.to_s }.join(", ")
        s += ")\n"
        s += "super("
        s += supers.map { |x| x.to_s }.join(", ")
        s += ")\n"

        attrs.each do |x|
            s += "@#{x} = #{x}\n"
        end

        inits.each_pair do |k, v|
            s += "@#{k} = #{v.inspect}\n"
        end

        s += "self.init if self.respond_to?(:init)\n"

        s += "end\n"

        return s
    end

    # Generates constructor on-the-fly from a specification.
    # See 'test_tricks' in tests or classes derived from AbstractRun.

    def constructor(*fields)
        s1 = __build_constructor__(*fields)
        class_eval(s1)
    end

    # Declares a list of objects that the object consists of.
    # Used to recursively traverse the structure of the workflow.
    # See classes derived from AbstractRun.

    def children(*fields)
        list = fields.map { |x| "@#{x}" }.join(', ')
        s  = "def __children__\n"
        s += "    return XPFlow::resolve_children([ #{list} ])\n"
        s += "end\n"
        h = fields.map { |x| ":#{x} => @#{x}" }.join(", ")
        s += "def __children_hash__\n"
        s += "    return { #{h} }\n"
        s += "end\n"
        class_eval(s)
    end

    # Declares additional variables declared in a run.
    def declares(*fields)
        hash = fields.map { |f| "@#{f} => self" }.join(", ")
        s  = "def __declarations__\n"
        s += "    return { #{hash} }\n"
        s += "end\n"
        class_eval(s)
    end

    def activities(*methods)
        maps = {}
        methods.each do |m|
            if m.is_a?(Hash)
                m.each_pair { |k, v| maps[k] = v }
            elsif m.is_a?(Symbol)
                maps[m] = m
            else
                raise
            end
        end
        s  = "def __activities__\n"
        s += "    return #{maps.inspect.gsub('=>',' => ')}\n"
        s += "end\n"
        class_eval(s)
    end

end

class Object

    attr_writer :__repr__
    
    def __repr__
        return instance_exec(&@__repr__) if @__repr__.is_a?(Proc)
        return @__repr__ unless @__repr__.nil?
        return to_s
    end

    def instance_variables_compat
        # Ruby 1.8 returns strings, but version 1.9 returns symbols
        return instance_variables.map { |x| x.to_sym }.sort
    end

    def inject_method(name, &block)
        if $ruby19
            self.define_singleton_method(name, &block)
        else
            (class << self; self; end).send(:define_method, name, &block)
        end
    end

end

class String

    def extract(exp)
        return exp.match(self).captures.first
    end

end

class Array

    def tail
        self[1..-1]
    end

    def same(x)
        return ((x - self == []) && (self - x == []))
    end

    def split_into(n)
        # splits into n arrays of the same size
        this = self
        raise "Impossible to split #{this.length} into #{n} groups" \
            if this.length % n != 0
        chunk = this.length / n
        return n.times.map { |i| this.slice(i*chunk, chunk)  }
    end

end

class Hash

    alias :old_select :select

    def select(*args, &block)
        return Hash[old_select(*args, &block)]
    end if $ruby18
end

class IO

    def self.write(name, content)
        File.open(name, 'wb') do |f|
            f.write(content)
        end
    end

end


module XPFlow

    # parse comments next to the invocation of the 
    # function higher in the stack

    def self.realpath(filename)
        return Pathname.new(filename).realpath.to_s
    end

    def self.stack_array
        stack = Kernel.caller()
        stack = stack.map do |frame|
            m = frame.match(/^(.+):(\d+)$/)
            m = frame.match(/^(.+):(\d+):in .+$/) if m.nil?
            raise "Could not parse stack '#{frame}'" if m.nil?
            filename, lineno = m.captures

            filename = realpath(filename)
            [ filename, lineno.to_i ]
        end
        return stack
    end

    def self.parse_comment_opts(source)
        source = realpath(source)
        stack = stack_array()
        while stack.first.first != source
            # remove all possible non-dsl files on the stack
            stack.shift
        end
        while stack.first.first == source
            # get all possible dsl files on the stack
            stack.shift
        end
        # now the first frame *SHOULD* be the one that entered DSL
        filename, line = stack.first
        line = IO.read(filename).lines.to_a[line - 1]
        if !line.include?('#!')
            return { }
        else
            comment = line.split('#!').last.strip
            opts = { }
            comment.split(",").each do |pair|
                pair = pair.strip
                if !pair.include?('=')
                    opts[pair.to_sym] = true
                else
                    k, v = pair.split('=', 2).map(&:strip)
                    opts[k.to_sym] = eval(v)
                end
            end
            return opts
        end
    end

    # Removes nodes that are not important from
    # graphing point of view

    def self.block_info(block)
        # gives a string repr. of arguments to this block
        s = []
        arity = block.arity
        if !block.respond_to?(:parameters)  # Ruby 1.8
            is_neg = (arity < 0)
            arity = (-arity - 1) if is_neg
            args = arity.times.map { |i| "arg#{i+1}" }
            args.push('[args...]')
            return args.join(', ')
        end
        for t, name in to_lambda(block).parameters
            name = "[#{name}]" if t == :opt
            name = "[#{name}...]" if t == :rest
            s.push(name)
        end
        return s.join(', ')
    end

    def self.to_lambda(block)
        # converts a block to lambda (see http://stackoverflow.com/questions/2946603)
        obj = Object.new
        obj.define_singleton_method(:_, &block)
        return obj.method(:_).to_proc
    end


    # Used by 'children' above.
    # Interprets dependant objects of the object
    # and flattens them to one large list.

    def self.resolve_children(obj)
        raise unless obj.is_a?(Array)
        res = []
        for x in obj
            if x.is_a?(Array)
                res += resolve_children(x)
            elsif x.is_a?(Hash)
                res += resolve_children(x.values)
            else
                res.push(x)
            end
        end
        return res
    end

    # Exception thrown if the execution of the workflow failed.
    # Possibly encapsulates many inner exceptions.

    class RunError < StandardError

        attr_reader :run
        alias :old_to_s :to_s

        def initialize(run, children, msg = nil)
            super(msg)
            children = [ children ] unless children.is_a?(Array)
            @run = run
            @children = children
        end

        def self.trace(x)
            if x.is_a?(RunError)
                return x.stacktrace
            else
                frame = x.backtrace.first
                file, line = /^(.+):(\d+)/.match(frame).captures
                return [ [x.to_s, [ Frame.new(file, line.to_i) ]] ]
            end
        end

        def stacktrace
            elements = @children.map { |c| RunError.trace(c) }.reduce([], :+)
            elements.each do |reason, stack|
                stack.push(@run.meta)
            end
            return elements
        end

        # Gives one line summary of the error.

        def summary
            s = stacktrace()
            if s.length == 1
                reason, stack = s.first
                frame = stack.first
                return "'#{reason}' (#{frame.location})"
            else
                return "#{s.length} errors"
            end
        end

        def to_s
            summary
        end

    end

    # A special version of RunError exception
    # that simply throws an error message.

    class RunMsgError < RunError

        def initialize(run, msg)
            super(run, nil, msg)
        end

        def stacktrace
            return [ [self.to_s, [ @run.meta ] ] ]
        end

        def to_s
            return old_to_s
        end

    end

    # Measures execution time (use 'Timer.measure')
    # and returns useful information.
    # For example:
    # t = Timer.measure do
    #    sleep 1
    # end
    # puts t.with_ms

    class Timer

        def self.measure
            start = Time.now
            x = yield
            done = Time.now
            return Timer.new(done - start, x)
        end

        def initialize(t, v)
            @t = t
            @v = v
        end

        def value
            return @v
        end

        def to_s(digits = nil)
            return @t.to_s if digits.nil?
            return "%.#{digits}f" % @t
        end

        def with_ms
            return to_s(3)
        end

        def secs
            return @t
        end
    end

    class AbstractDumper

        def digest(meta)
            # convert a meta-hash to deterministic string
            fingerprint = meta.each.map.to_a.sort
            return Digest::SHA256.hexdigest(fingerprint.inspect)
        end

        def dump(obj, opts = {})
            obj = obj.clone
            validity = Timespan.to_secs(opts.fetch(:valid, Infinity))
            obj['valid'] = Time.now.to_f + validity
            obj['time_string'] = Time.now.to_s
            obj['time_float'] = Time.now.to_f
            set(digest(obj['meta']), obj.to_yaml)
        end

        def load(meta)
            s = get(digest(meta))
            return nil if s.nil?
            obj = YAML::load(s)
            return nil if obj['meta'] != meta  # collision
            return nil if Time.now.to_f > obj['valid']  # expired
            return obj
        end

        def set(key, value)
            raise 'Not implemented'
        end

        def get(key)
            raise 'Not implemented'
        end

    end

    class FileDumper < AbstractDumper

        @@prefix = ".xpflow-cp-"

        def filename(key)
            return "#{@@prefix}#{key}"
        end

        def set(key, value)
            File.open(filename(key), 'w') do |f|
                f.write(value)
            end
        end

        def get(key)
            name = filename(key)
            return nil unless File.exists?(name)
            File.open(name) do |f| 
                f.read
            end
        end

        def list
            # lists checkpoints
            # TODO: relegate to AbstractDumper somehow
            files = Dir.glob("./#{@@prefix}*")
            h = Hash.new { |h, k| h[k] = [] }
            files.each do |f|
                contents = IO.read(f)
                cp = YAML.load(contents)
                name = cp["meta"][:name]
                h[name].push(cp)
            end

            h2 = { }

            h.each_pair do |name, cps|
                begin
                    h2[name] = cps.sort { |x, y| x['time_float'] <=> y['time_float'] }
                rescue
                    # if cp style changed
                end
            end

            return h2
        end

    end

    class MemoryDumper < AbstractDumper

        def initialize
            super
            @lock = Mutex.new
            @store = {}
        end

        def get(key)
            @lock.synchronize do
                @store[key]
            end
        end

        def set(key, value)
            @lock.synchronize do
                @store[key] = value
            end
        end

    end


    class Cache

        # TODO: avoid cache stampede

        def initialize
            @lock = Mutex.new
            @store = {}
        end

        def get(label)
            @lock.synchronize do
                @store[label]
            end
        end

        def set(label, value)
            @lock.synchronize do
                @store[label] = value
            end
        end

        def fetch(label)
            x = get(label)
            return x unless x.nil?
            v = yield
            set(label, v)
            return v
        end

    end

    class Timespan
        # parses various timespan formats

        def self.to_secs(s)
            return s.to_f if s.is_a?(Numeric)
            return Infinity if [ 'always', 'forever', 'infinitely' ].include?(s.to_s)
            parts = s.to_s.split(':').map { |x| Integer(x) rescue nil }
            if parts.all? && [ 2, 3 ].include?(parts.length)
                secs = parts.zip([ 3600, 60, 1 ]).map { |x, y| x * y }.reduce(:+)
                return secs
            end
            m = /^(\d+|\d+\.\d*)\s*(\w*)?$/.match(s)
            num, unit = m.captures
            mul = case unit
                when '' then 1
                when 's' then 1
                when 'm' then 60
                when 'h' then 60 * 60
                when 'd' then 24 * 60 * 60
                else nil
            end
            raise "Unknown timespan unit: '#{unit}' in #{s}" if mul.nil?
            return num.to_f * mul
        end

        def self.to_time(s)
            secs = to_secs(s).to_i
            minutes = secs / 60; secs %= 60
            hours = minutes / 60; minutes %= 60
            minutes += 1 if secs > 0
            return '%.02d:%.02d' % [ hours, minutes ]
        end

    end

    Infinity = 1.0/0.0

end

