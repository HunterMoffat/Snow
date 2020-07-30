
module XPFlow

    class Semaphore

        def initialize(n)
            @n = n
            @mutex = Mutex.new
            @cond = ConditionVariable.new
        end

        def acquire
            @mutex.synchronize do
                while @n == 0
                    @cond.wait(@mutex)
                end
                @n -= 1
            end
        end

        def release
            @mutex.synchronize do
                @n += 1
                @cond.signal
            end
        end

        def synchronize
            begin
                @mutex.acquire
                yield
            ensure
                @mutex.release
            end
        end

    end

    class SyncQueue

        attr_reader :q

        def initialize
            @q = []
            @elements = Semaphore.new(0)
            @mutex = Mutex.new
            @cv = ConditionVariable.new  # empty queue
        end

        def push(x)
            @mutex.synchronize do
                @q.push(x)
            end
            @elements.release
        end

        def pop
            @elements.acquire
            return @mutex.synchronize do
                x = @q.shift
                @cv.broadcast if @q.length == 0
                x = yield(x) if block_given?
                x
            end
        end

        # waits for the queue to be empty

        def wait_empty
            @mutex.synchronize do
                while @q.length > 0
                    @cv.wait(@mutex)
                end
            end
        end

    end

end
