# encoding: UTF-8

#
# Implementation of libraries, i.e., sets of activities
# that can be imported or injected into a namespace.
#

require 'monitor'

module XPFlow

    class ResolutionError < StandardError

    end

    class Library
        # implements .activity and .process methods
        # + some kind of activity management

        def initialize
            @names = { }
            @lock = Mutex.new
        end

        def synchronize
            @lock.synchronize do
                yield
            end
        end

        def [](key)
            return @names[key]
        end

        def []=(key, value)
            key = stringize(key)
            raise "'#{key}' already exists here" if @names.key?(key)
            raise "'#{key}' contains a dot" if key.include?(".")
            @names[key] = value
        end

        def set_force(key, value)
            @names[key] = value
        end

        def into_parts(name)
            array = name.split(".")
            return [ array[0...-1], array.last ]
        end

        def resolve_name(name)
            name = stringize(name)
            return resolve_parts(*into_parts(name))
        end

        def resolve_libs(libs)
            libs = libs + [] # copy
            path = libs.join(".")
            current = self
            while libs.length > 0
                name = libs.shift
                current = current[name]
                if !current.is_a?(Library)
                    raise ResolutionError.new("No such library '#{path}'")
                end
            end
            return current
        end

        def resolve_parts(libs, name)
            library = resolve_libs(libs)
            object = library[name]
            if object.nil?
                path = libs.join(".")
                raise ResolutionError.new("No such object '#{name}' in '#{path}'")
            end
            return object
        end

        def resolve_activity(libs, name)
            activity = resolve_parts(libs, name)
            if activity.is_a?(Library)
                path = (libs + [ name ]).join(".")
                raise ResolutionError.new("'#{path}' is not an activity")
            end
        end

        def create_libraries(libs)
            # creates all intermediate libraries if they don't exist
            current = self
            nesting = []
            while libs.length > 0
                name = libs.shift
                nesting.push(name)
                object = current[name]
                if object.nil?
                    current[name] = BasicLibrary.new
                elsif !object.is_a?(Library)
                    activity = nesting.join(".")
                    raise ResolutionError.new("Overwriting an activity '#{activity}'")
                end
                current = current[name]
            end
            return current
        end

        def get_library_or_nil(name)
            object = @names[name]
            return object
        end

        def get_activity_or_error(name)
            object = @names[name]
            if object.is_a?(Library)
                raise ResolutionError.new("No such activity '#{name}'")
            end
            return object
        end

        def get_activity_or_nil(name)
            previous = nil
            begin
                previous = get_activity_or_error(name)
            rescue ResolutionError => e
                previous = nil # there is no previous activity
            end
            return previous
        end


        def activity_alias(full_name, old_name)
            # creates an alias between full_name and another_name
            # please don't make it cyclic! :D
            object = get_object(old_name)
            raise "Object '#{old_name}' does not exist" if object.nil?
            libs, name = into_parts(full_name)
            library = resolve_libs(libs)
            library[name] = object
        end

        def traversal_graph
            g = {}
            @names.each do |k, v|
                r = case 
                    when v.is_a?(Library) then v.traversal_graph
                    when v.is_a?(XPFlow::BlockActivity) then "block"
                    when v.is_a?(XPFlow::ProcessActivity) then "process"
                    else
                        raise "Error: #{k} #{v} (#{v.class})"
                end
                g[k] = r
            end
            return g
        end

        def stringize(o)
            raise "Wrong name type: #{o.class}" if !(o.is_a?(String) || o.is_a?(Symbol))
            return o.to_s
        end

        # ===PUBLIC API=== #

        def activity(full_name, opts = {}, &block)
            name, library = _create_entry(full_name)

            opts[:__parent__] = library.get_activity_or_nil(name)

            block_activity = XPFlow::BlockActivity.new(name, opts, block)
            block_activity.doc = opts[:doc]

            library.set_force(name, block_activity)

            return block_activity
        end

        def constant(full_name, value)
            activity full_name do
                value
            end
        end

        def _create_entry(full_name)
            full_name = stringize(full_name)
            libs, name = into_parts(full_name)
            library = create_libraries(libs)
            return [ name, library ]
        end

        def process(full_name, opts = {}, &block)
            name, library = _create_entry(full_name)

            parent = opts[:__parent__] = library.get_activity_or_nil(name)

            process_activity = XPFlow::ProcessDSL.new(name, self, &block).as_process
            process_activity.doc = parent.doc unless parent.nil?
            process_activity.doc = opts[:doc] if opts[:doc]
            process_activity.opts = opts
            process_activity.collect_meta(2)

            library.set_force(name, process_activity)

            return process_activity
        end

        def macro(full_name, opts = {}, &block)
            name, library = _create_entry(full_name)

            m = XPFlow::MacroDSL.new(name, self, block)
            library.set_force(name, m)
            return m
        end

        def get_object(name)
            begin
                return resolve_name(name)
            rescue ResolutionError => e
                return nil
            end
        end

        def get_activity_object(name)
            object = get_object(name)
            if object.is_a?(Library)
                raise "'#{name}' is a library"
            end
            return object
        end

        def get_names
            return @names.keys
        end

        def get_libraries
            h = @names.select { |k, v| v.is_a?(Library) }
            return h
        end

        def import_library(name, library)
            self[name] = library
        end

        def inject_library(name, library)
            # this will inject all activities from 'library' into this library
            # this may overwrite some of them
            import_library(name, library)
            library.get_names.each do |object|
                activity_alias(object, "#{name}.#{object}")
            end
        end

        def setup
            # empty
        end

    end

    if __FILE__ == $0
        require 'pp'
        require 'xpflow'
        l = Library.new
        l.constant :a1, 1
        l.process :"czesc.siema" do; end
        g = Library.new
        g.activity :cze
        l.activity_alias("alejazda", "czesc")
        pp l.traversal_graph
    end

    # a library that does some nice tricks

    class ActivityLibrary < Library

        def initialize
            super
            setup()
            this = self
            __activities__.each_pair do |name, realname|
                activity(name, get_option(name)) do |*args|
                    this.invoke(realname, args, self, &self.__block__)
                end
            end
        end

        def invoke(method, args, proxy = nil, &block)
            Thread.current[:__proxy__] = proxy
            return self.send(method, *args, &block)
        end

        def proxy
            return Thread.current[:__proxy__]
        end

        def get_option(name)
            return { }
        end

    end

    class HiddenActivityLibrary < ActivityLibrary

        def get_option(name)
            return { :log_level => :none }
        end

    end

    class SyncedActivityLibrary < ActivityLibrary

        def invoke(method, args, proxy = nil, &block)
            synchronize do
                super
            end
        end

    end

    class MonitoredActivityLibrary < ActivityLibrary

        # with reentrant lock
        def initialize
            super
            @lock = Monitor.new
        end

    end

    IGNORED_LIBRARY_VARIABLES = Library.new.instance_variables

    module SerializableLibrary

        def checkpoint
            vars = self.instance_variables - IGNORED_LIBRARY_VARIABLES
            state = {}
            vars.each do |v|
                value = self.instance_variable_get(v)
                state[v] = value
            end
            return state
        end

        def restore(state)
            state.each_pair do |k, v|
                self.instance_variable_set(k, v)
            end
        end

    end # Serializable

end
