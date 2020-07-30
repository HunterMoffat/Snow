
require 'thread'

module XPFlow

    $xpflow_global_mutex = Mutex.new

    def self.global_synchronize(&block)
        return $xpflow_global_mutex.synchronize(&block)
    end

    $xpflow_global_counters = {}

    def self.global_counter(label = :global)
        value = global_synchronize do
            h = $xpflow_global_counters
            if h.key?(label)
                h[label] += 1
            else
                h[label] = 0
            end
            h[label]
        end
        return value
    end

    # Implements a pool of threads.
    # The threads can execute blocks of code

    class ThreadPool

        def initialize(size)
            @size = size
            @queue = Queue.new
            @threads = size.times.map do
                Thread.new do
                    worker
                end
            end
        end

        def worker
            while true
                el = @queue.pop
                break if el.nil?
                block, args = el
                block.call(*args)
            end
        end

        def execute(*args, &block)
            @queue.push([ block, args ])
        end

        def join(yes_or_no = true)
            @size.times { @queue.push(nil) }
            @threads.each { |t| t.join } if yes_or_no
        end
    end

    class OrderedArray

        def initialize
            @queue = []
            @lock = Mutex.new
            @cond = ConditionVariable.new
        end

        def give(i, x)
            @lock.synchronize do
                @queue.push([i, x])
                @cond.broadcast
            end
        end

        def take(n)
            @lock.synchronize do
                while @queue.length < n
                    @cond.wait(@lock)
                end
                arr = @queue.sort { |x, y| x.first <=> y.first }.map { |i, x| x }
                arr
            end
        end

    end

    # Let's one thread wait for a value
    # Do not call 'take' multiple times.

    class Meeting

        def initialize(run)
            @lock = Mutex.new
            @cond = ConditionVariable.new
            @queue = []
            @run = run
        end

        def give(x)
            @lock.synchronize do
                @queue.push(x)
                @cond.broadcast
            end
        end

        def _take(n)
            flatten = (n < 0)
            n = n.abs
            @lock.synchronize do
                while @queue.length < n
                    @cond.wait(@lock)
                end
                arr = @queue.shift(n)
                arr = arr.first if flatten
                arr
            end
        end

        def take(n)
            begin
                return _take(n)
            rescue Interrupt => e
                raise RunMsgError.new(@run, "Thread rendez-vous has been interrupted.")
            end
        end

    end

    # Collects exceptions (using 'push' method)
    # and rethrows them collectively as RunError.

    class ExceptionBag

        def initialize
            @lock = Mutex.new
            @bag = []
        end

        def push(x)
            @lock.synchronize do
                @bag.push(x)
            end
        end

        def raise_if_needed(run)
            @lock.synchronize do
                copy = @bag.map.to_a
                raise RunError.new(run, copy) if copy.length > 0
            end
        end

    end

    class Threads
        
        def self.defaults
            return { :join => true }
        end

        def self.merge_opts(x, y)
            return x.merge(y) { |k, old, new|
                (new.nil? ? old : new)
            }
        end

        def self.run(run, list, opts = {}, &block)
            opts = merge_opts(defaults(), opts)
            bag = ExceptionBag.new
            size = [ list.length, opts[:pool] ].min
            pool = ThreadPool.new(size)
            list.each_with_index do |el, i|
                pool.execute(el, i) do |x, it|
                    begin
                        block.call(x, it)
                    rescue RunError => e
                        bag.push(e)
                    end
                end
            end
            pool.join(opts[:join])
            bag.raise_if_needed(run)
        end

    end

end
