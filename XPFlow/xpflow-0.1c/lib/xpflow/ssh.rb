# encoding: UTF-8

#
# Extensions to NetSSH library.
#  * implementation of transparent connection tunneling (Net::SSH.tunnel)
#

module Net; module SSH; module Service

    class LoopThread

        def initialize
            @lock = Mutex.new
            @active = true
            @t = Thread.new do
                yield Proc.new { active? }
            end
        end

        def active?
            @lock.synchronize do
                @active
            end
        end

        def join
            @lock.synchronize do
                @active = false
            end
            @t.join
        end

    end

    # additional forwarding methods
    class Forward

        def direct(socket, host, port)

            debug { "direct-redirect on #{socket}" }

            channel = session.open_channel("direct-tcpip", :string, host, :long, 
                port, :string, "127.0.0.1", :long, 22334) do |ch|
                ch.info { "Channel established" }
            end

            prepare_client(socket, channel, :local)

            channel.on_open_failed do |ch, code, desc|
                channel.error { "error: #{desc} (#{code})" }
                channel[:socket].close
            end
        end

        def connect(host, port)
            # in Ruby 1.9, one can write: Socket.pair(:UNIX, :STREAM, 0)
            client, server = Socket.pair('AF_UNIX', 'SOCK_STREAM', 0)
            direct(server, host, port)
            return client
        end

        def ssh(host, user, options = {})
            port = options.fetch(:port, 22)
            fd = connect(host, port)
            class << fd
                def peer_ip
                    "<faked IP>"
                end
            end
            t = LoopThread.new do |active|
                session.loop(0.1) do
                    active.call
                end
            end
            options[:proxy] = FakeFactory.new(fd)
            begin
                s = Net::SSH.start(host, user, options)
            rescue
                t.join   # stop the thread
                raise
            end
            class << s
                attr_accessor :loop_thread
                alias old_close close

                def close
                    old_close  # let this socket to close
                    loop_thread.join   # abandon upper loop
                end
            end
            s.loop_thread = t

            if block_given?
                begin
                    yield s
                ensure
                    s.close
                end
            else
                return s
            end
        end

    end

    class FakeFactory
        
        def initialize(socket)
            @socket = socket
        end

        def open(*args)
            return @socket
        end
    end

end; end; end

module Net; module SSH

    class SSHLogin
        
        attr_reader :user
        attr_reader :host
        attr_reader :port

        def initialize(spec)
            @user, @host, @port = parse(spec)
        end

        def parse(spec)
            m = /(?:(.+)@)?(.+?)(?::(\d+))?$/.match(spec)
            raise 'wrong login specification' if m.nil?
            user, host, port = m.captures
            port = 22 if port.nil?
            user = Etc.getlogin if user.nil?
            return [user, host, port.to_i]
        end

    end

    def self.tunnel(hosts, opts = {})
        hosts = hosts.map { |h| SSHLogin.new(h) }

        hops = []
        begin
            proxy = hosts.first
            opts[:port] = proxy.port
            hops.push(Net::SSH.start(proxy.host, proxy.user, opts))
            for node in hosts[1..-1] do
                opts[:port] = node.port
                next_hop = hops.last.forward.ssh(node.host, node.user, opts)
                hops.push(next_hop)
            end
        rescue
            while hops.length != 0 do
                hops.pop.close
            end
            raise
        end

        session = hops.last
        class << session
            alias older_close close
            attr_accessor :masters
            def close
                older_close
                while masters.length != 0 do
                    masters.pop.close
                end
            end
        end
        session.masters = hops[0...-1]

        if block_given?
            begin
                return(yield session)
            ensure
                session.close
            end
        else
            return session
        end
    end

end; end
