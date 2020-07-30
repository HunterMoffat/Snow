
require 'sinatra/base'
require 'json'

class << Sinatra::Base

    def quit!(server, handler_name)
        server.respond_to?(:stop!) ? server.stop! : server.stop
    end

    # copy-pasted-adjusted from sinatra code (1.3.2-2 in Debian)
    def _run_custom!(options={})
        set options
        set :logging, nil
        handler      = detect_rack_handler
        handler_name = handler.name.gsub(/.*::/, '')
        handler.run self, :Host => bind, :Port => port do |server|
            @__quit__ = proc { || quit!(server, handler_name) }
            server.threaded = settings.threaded if server.respond_to? :threaded=
            set :running, true
            yield server if block_given?
        end
    end

    def run_custom!(options={})
        # it may result in a race
        # small note here:
        # THERE MUST BE A SPECIAL PLACE 
        #     IN HELL FOR PEOPLE DOING THINGS LIKE THIS!!!
        handler = trap(:INT, 'DEFAULT')  # take previous handler
        trap(:INT, handler)
        t = Thread.new(handler) do |h|
            x = h
            while x == h do
                sleep 0.1
                x = trap(:INT, &h)
            end
            # x is sinatra wicked handler
            # let's overwrite it back
            trap(:INT, &h)
        end
        _run_custom!(options)
    end

    def quit_custom!
        return @__quit__.call()
    end

    public

        # sets xpflow engine
        def set_engine(engine)
            $__gui_engine__ = engine
        end

end


class Rest

    attr_reader :engine

    def initialize(engine)
        @engine = engine
    end

    def activities
        ns = @engine.get_global_namespace()
        return ns.each.map do |name, o|
            { :name => name, :info => o.info }
        end.to_a
    end

    def active
        h = @engine.spectator.info
        h2 = []
        h.each_pair do |k, v|
            h2.push({ :name => k, :info => v })
        end
        return h2
    end

end


class Controller < Sinatra::Base

    set :port, 8080
    set :public_folder, File.join(File.dirname(__FILE__), 'gui-files')

    def rest
        return Rest.new($__gui_engine__)
    end

    def json(obj)
        content_type 'application/json', :charset => 'utf-8'
        return obj.to_json
    end

    get '/__rest__/:method' do |m|
        x = rest.send(m.to_sym)
        json x
    end

    get '/' do
        erb :index
    end

end

if $0 == __FILE__

    require 'xpflow'

    process :main do
        run :whatever
        run :whatever
    end

    activity :whatever do |x|
        sleep 10
        log "cze"
    end

    Controller.set_engine($engine)

    trap(:INT) do
        puts 'Shutting everything down...'
        Controller.quit_custom!
    end

    t = Thread.new do
        Controller.run_custom!
    end

    $engine.execute_from_argv :main

    t.join

end
