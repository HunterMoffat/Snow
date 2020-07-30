
require 'thread'

module XPFlow

    class EventHandler

        def initialize(block)
            @block = block
        end

        def run(*args)
            return @block.call(*args)
        end

    end

    class EventRouter

        def initialize
            @mutex = Mutex.new
            @listeners = Hash.new { |h, key| h[key] = [] }
        end

        def synchronize(&block)
            return @mutex.synchronize(&block)
        end

        def listen(event, &block)
            synchronize do
                @listeners[event].push(EventHandler.new(block))
            end
        end

        def publish(event, args = [])
            hs = synchronize do
                @listeners[event].map { |x| x } # copy
            end
            hs.each do |h|
                h.run(*args)
            end
        end

    end

end


if __FILE__ == $0
    r = XPFlow::EventRouter.new
    r.listen(:complete) do |x|
        puts "yo! #{x}"
    end
    r.publish :cze
    r.publish :complete, [ 1, 2 ]
end
