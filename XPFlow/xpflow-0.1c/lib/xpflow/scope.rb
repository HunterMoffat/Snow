
require 'thread'

module XPFlow

    $scope_mutex = Mutex.new
    $scope_cv = ConditionVariable.new

    class Scope

        constructor :parent, :vars => { }

        attr_reader :parent
        attr_reader :vars

        def push
            return Scope.new(self)
        end

        def vars
            return @vars
        end

        def [](key)
            return get(key)
        end

        def get(key, return_nil = false)
            found = false
            val = nil
            $scope_mutex.synchronize do
                while true
                    found, val = try_get(key)
                    break if (found or return_nil)
                    $scope_cv.wait($scope_mutex)
                end
            end
            return val
        end

        def get_now(key, default = nil)
            v = get(key, true)
            return (v.nil?) ? default : v
        end

        def []=(key, value)
            $scope_mutex.synchronize do
                @vars[key] = value
                $scope_cv.broadcast
            end
        end

        def merge!(hash)
            $scope_mutex.synchronize do
                @vars.merge!(hash)
                $scope_cv.broadcast
            end
        end

        # do not use methods below!

        def try_get(key)
            curr = self
            found = false
            val = nil
            while (not found) and (not curr.nil?)
                found, val = curr.query(key)
                curr = curr.parent
            end
            return [ found, val ]
        end

        def query(key)
            return [ @vars.key?(key), @vars[key] ]
        end

        def to_s
            @vars.inspect + @parent.to_s
        end

        def to_a
            arr = [ @vars ]
            arr += @parent.to_a unless @parent.nil?
            return arr
        end

        def to_keys
            return to_a.map(&:keys)
        end

        def containing(key)
            if @vars.key?(key)
                return self
            else
                return @parent.containing(key)
            end
        end

        def current_activity(levels = 1)
            this = Scope.current
            while levels > 0 
                if this.vars.key?(:__activity__)
                    levels -= 1
                end
                break if levels == 0
                this = this.parent
            end
            return this
        end

        def parent_activity
            return current_activity(2)
        end

        def engine
            value = get(:__engine__, nil)
            raise "No engine!" if value.nil?
            return value
        end

        def experiment
            value = get(:__experiment__, nil)
            raise "No experiment!" if value.nil?
            return value
        end

        # static methods
        # it's okay to use them

        def self.reset()
            Scope.set(Scope.new(nil))
        end

        def self.set(scope, hash = {})
            Thread.current[:__scope__] = scope 
            scope.merge!(hash)
        end

        def self.current()
            return Thread.current[:__scope__]
        end

        def self.engine()
            return current().engine
        end

        def self.push()
            return current().push
        end

        def self.region(&block)
            previous = self.current()
            result = nil
            begin
                new_scope = previous.push()
                Scope.set(new_scope)
                result = block.call(new_scope)
            ensure
                Scope.set(previous)
            end
            return result
        end

    end

    Scope.reset()  # initialize the global scope

end
