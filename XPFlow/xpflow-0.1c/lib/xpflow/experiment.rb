
module XPFlow

    class Experiment

        attr_reader :results

        def initialize(name, results_path, parent = nil)
            @name = name
            @parent = parent
            @results = Collection.new(results_path)
            @results.create_path()
            @log_filename = File.join(results_path, "experiment.log")
            @log_file = FileLog.new(@log_filename).open()
        end

        def create_subexperiment(name)
            new_path = File.join(@results.path, name)
            return Experiment.new(name, new_path, self)
        end

        def install
            return self
        end

        def log(*msgs)
            @log_file.log(*msgs)
            @parent.log(*msgs) unless @parent.nil?
        end

        def store_execution(execution)
            # puts execution
            # here we should store the execution so that it will be solved
        end

        def store_executions(array)
            array.each { |x| store_execution(x) }
        end

    end

    class ExperimentBlackHole

        # a version of Experiment that consumes eveything it is given
        # used in a testsuite

        def initialize(*args); end

        def create_subexperiment(name)
            return ExperimentBlackHole.new()
        end

        def install
            return self
        end

        def log(*msgs); end

        def store_execution(x); end

        def store_executions(x); end

    end

end
