# encoding: UTF-8

#
# Various structures/classes used everywhere.
#

module XPFlow

    module Operations
        def ==(x); XPFlow::BinaryOp.new('==', self, x) end
        def +(x);  XPFlow::BinaryOp.new('+', self, x) end
        def *(x);  XPFlow::BinaryOp.new('*', self, x) end
        def /(x);  XPFlow::BinaryOp.new('/', self, x) end
        def -(x);  XPFlow::BinaryOp.new('-', self, x) end
        def <(x);  XPFlow::BinaryOp.new('<', self, x) end
        def >(x);  XPFlow::BinaryOp.new('>', self, x) end
        def <=(x); XPFlow::BinaryOp.new('<=', self, x) end
        def >=(x); XPFlow::BinaryOp.new('>=', self, x) end
        def -@;    XPFlow::UnaryOp.new('-@', self) end
        def &(x);  XPFlow::BinaryOp.new('&', self, x) end
        def |(x);  XPFlow::BinaryOp.new('|', self, x) end
        def not;   XPFlow::NegOp.new(self) end

        def index(i); XPFlow::IndexOp.new(self, i) end

    end

    module Meta

        def meta
            if @frame
                return @frame
            else
                return Frame.new('<unknown>', '<unknown>')
            end
        end

        def collect_meta(skip = 0)
            original = caller(skip).first
            x = /^(.+):(\d+)/.match(original)
            file, line = x.captures
            @frame = Frame.new(file, line.to_i, self)
        end

    end

    class Visiter

        attr_reader :values

        def initialize
            @values = []
        end

        def collect(x)
            @values.push(x)
        end
    end

    module Traverse

        def _visit(ctx, &block)
            # puts self.class
            results = __children__.map { |x| x._visit(ctx, &block) }
            return ctx.instance_exec(self, results, &block)
        end

        def visit(&block)
            ctx = Visiter.new
            _visit(ctx, &block)
            return ctx.values
        end

        def object_key
            return @key
        end

        def _workflow(o)
            h = { :type => o.class.to_s.split("::").last }
            key = o.object_key()
            h[:key] = key unless key.nil?
            if o.respond_to?(:workflow_value)
                return o.workflow_value
            end
            o.__children_hash__.each do |k, v|
                if h.key?(k)
                    raise "Child '#{k}' exists in workflow. Please change it."
                end
                if v.respond_to?(:workflow)
                    h[k] = v.workflow
                elsif v.is_a?(Array)
                    h[k] = v.map { |x| _workflow(x) }
                else
                    h[k] = "Undefined for class #{v.class}"
                end
            end
            return h
        end

        def workflow
            return _workflow(self)
        end

        def vars_uses
            # returns a hash mapping a variable in the workflow
            # to list of nodes that use it
            uses = visit do |node, children|
                vs = children.select { |x| x.is_a?(XPVariable) }
                vs = Hash[vs.map { |x| [ x.key, node ] }]
                collect(vs) if vs.length > 0
                node
            end
            # uses contains an array of hashes that must be merged
            # every [k,v] is [variable, node that uses it]
            summary = {}
            uses.each do |h|
                h.each do |key, node|
                    summary[key] = [] unless summary.key?(key)
                    summary[key].push(node)
                end
            end
            summary
        end

        def vars
            # returns variables used in that workflow
            return vars_uses.keys
        end

        def declarations
            # returns a hash that maps all variables
            # to the nodes that define them
            decls = visit do |node, children|
                collect({ node.key => node }) if node.is_a?(AbstractRun)
                collect(node.__declarations__) if node.respond_to?(:__declarations__)
            end
            return decls.reduce({}) { |x, y| x.merge(y) }
        end

        def vars_uses_declarations
            # like 'declarations' but only shows
            # declarations of variables that are used in that workflow
            vs = vars()
            ds = declarations()
            # iteration variables will show up as nils
            return Hash[ vs.map { |x| [x, ds[x]] } ]
        end

    end

    class ActivityList
        
        include Traverse
        children :activities
        constructor :activities

    end

    class Frame

        attr_reader :file
        attr_reader :line
        attr_reader :obj

        def initialize(file, line, obj = nil)
            @file = file
            @line = line
            @obj = obj
        end

        def location
            return '%s:%s' % [ @file, @line ]
        end

        def location_long
            return '%s at line %s' % [ @file, @line ]
        end

        def to_s
            return "<Frame: #{location}>"
        end
    end

    class FakeScope
        # a faked scope for evaluate_offline
    end

    class XPValue

        include Operations
        include Traverse

        def self.flatten(obj)
            return obj.flatten if obj.is_a?(XPOp)
            return obj if obj.is_a?(XPValue)
            raise if obj.is_a?(AbstractRun)
            return XPList.new(obj.map { |x| self.flatten(x) }) if obj.is_a?(Array)
            return XPHash.new(obj.map { |k, v| [ k, self.flatten(v) ] }) if obj.is_a?(Hash)
            return XPVariable.new(obj.key) if obj.is_a?(DSLVariable)
            return XPConst.new(obj)
        end

        def evaluate(scope); raise end

        def evaluate_offline
            begin
                return self.evaluate(FakeScope.new)
            rescue NoMethodError => e
                return nil
            end
        end

    end


    class XPConst < XPValue

        constructor :obj
        children

        def evaluate(scope)
            o = @obj
            if o.is_a?(String)
                o = DSLVariable.replace(o, scope)
                o = XPOp.replace(o, scope)
            end
            return o
        end

        def workflow_value # TODO, handle strings
            return @obj
        end

    end

    class XPList < XPValue

        constructor :obj
        children :obj

        def evaluate(scope)
            @obj.map { |x| x.evaluate(scope) }
        end

    end

    class XPHash < XPValue

        constructor :obj

        def evaluate(scope)
            o = Hash[@obj]
            Hash[o.map { |k, v| [k, v.evaluate(scope) ]}]
        end

        def __children__
            return @obj.map { |k, v| v }
        end

    end

    class XPVariable < XPValue

        attr_reader :key
        constructor :key
        children

        def evaluate(scope)
            scope[@key]
        end

        def workflow_value
            return "var(#{@key})"
        end

    end



    class XPOp < XPValue
        
        @@instances = {}  # TODO: this may consume memory

        def flatten
            raise
        end

        def self.replace(s, scope)
            out = s.gsub(/Op\[-@@@@-(\d+)-@@@@-\]/) do |m|
                identifier = $1.to_i
                @@instances[identifier].evaluate(scope)
            end
            return out
        end

        def to_s
            @@instances[object_id()] = self
            return "Op[-@@@@-#{object_id()}-@@@@-]"
        end

    end

    class NegOp < XPOp

        constructor :arg
        children :arg

        def evaluate(scope)
            return !@arg.evaluate(scope)
        end

        def flatten
            return NegOp.new(XPValue.flatten(@arg))
        end

    end

    class UnaryOp < XPOp

        constructor :type, :arg
        children :arg

        def evaluate(scope)
            x = @arg.evaluate(scope)
            return x.send(@type)
        end

        def flatten
            return UnaryOp.new(@type, XPValue.flatten(@arg))
        end

    end

    class BinaryOp < XPOp

        constructor :type, :left, :right
        children :left, :right

        def evaluate(scope)
            a = @left.evaluate(scope)
            b = @right.evaluate(scope)
            return a.send(@type, b)
        end

        def flatten
            return BinaryOp.new(@type, XPValue.flatten(@left), XPValue.flatten(@right))
        end

    end

    class IndexOp < XPOp
        
        constructor :arg, :index
        children :arg

        def evaluate(scope)
            v = @arg.evaluate(scope)
            i = @index.evaluate(scope)
            return v[i]
        end

        def flatten
            return IndexOp.new(XPValue.flatten(@arg), XPValue.flatten(@index))
        end

    end

end

