
require 'erb'
require 'ostruct'
require 'xpflow/exts/g5k'
require 'yaml'
require 'thread'
require 'shellwords'
require 'xpflow/exts/powder'

def get_g5k_username
    raise "No G5K username!" if $g5k_user.nil?
    return $g5k_user
end

module XPFlow

    # manages all nodes

    class NodesManager

        def initialize(directory)
            @directory = directory
            @mutex = Mutex.new
            @node_counter = 0
        end

        def synchronize(&block)
            return @mutex.synchronize(&block)
        end

        def subdir(name)
            return @directory.subdir(name)
        end

        def get_node(user, host, factory, opts = {})
            synchronize do
                @node_counter += 1
                node_directory = subdir("#{host}--#{user}--#{factory.name}--#{@node_counter}")
                opts[:factory] = factory
                factory.build(user, host, node_directory, opts)
            end
        end

    end

    class SimpleNodeFactory
        # build a directly-reachable host

        def name
            return "normal"
        end

        def build(*args)
            return SimpleNode.new(*args)
        end

    end

    class G5KNodeFactory

        def name
            return "grid5000"
        end

        def build(user, host, node_directory, opts)
            opts = { :group => _get_group(host) }.merge(opts)
            return G5KNode.new(user, host, node_directory, opts)
        end

        def _get_group(host)
            m = /^(\w+)-(\d+).+$/.match(host)   # <cluster>-<nodeid> ...
            if m
                return m.captures.first
            else
                return nil
            end
        end

    end

    class ProxiedFactory

        def initialize(node)
            @node = node
        end

        def name
            return "proxy"
        end

        def build(user, host, directory, opts)
            opts[:proxy] = @node
            return ProxiedNode.new(user, host, directory, opts)
        end

    end

    class AbstractNode

        # a node that is installed using a set of templates

        attr_reader :user
        attr_reader :host
        attr_reader :directory

        def initialize(user, host, directory, opts = {})
            @user = user
            @host = host
            @directory = directory
            @mutex = Mutex.new
            @opts = opts

            __setup__()
        end

        def options
            return @opts
        end

        def domain
            # gets accessibility domain of a node (nodes from within one domain
            # are pairwise accessible and reachable)
            return @opts[:factory].name
        end

        def synchronize(&block)
            return @mutex.synchronize(&block)
        end

        def group
            return @opts[:group]
        end

        def userhost
            return "#{@user}@#{@host}"
        end

        def tmpfile
            return execute("mktemp").stdout.strip
        end

        def to_s
            return "#{self.class}('#{userhost}')"
        end

        def path
            return @directory.path
        end

        def md5sum(files)
            h = {}
            output = execute("md5sum #{files.join(' ')}").stdout.strip
            output.lines.each do |line|
                hash, filename = line.split
                h[filename] = hash
            end
            return h
        end

        def run(*args)
            return @directory.run(*args)
        end

        def execute(cmd, env = {}, opts = {})
            # opts will become an env of execution
            wd = opts[:wd]
            env = env.each_pair.select { |k, v| v.is_a?(String) }.map { |k, v| [ k.to_s, v ] }
            env = Hash[env]
            return @directory.run_ssh(cmd, :env => env, :wd => wd)
        end

        def execute_with_files(cmd, out, err)
            return @directory.run_ssh(cmd, :out => out, :err => err)
        end

        def ping()
            @directory.run("ping")
        end

        def hostname()
            @directory.run("hostname")
        end

        def scp(from, to)
            @directory.run("scp #{from} #{to}")
        end

        def scp_many(files, to_dir)
            args = files.join(" ")  # TODO: escaping?
            return @directory.run("scp_many #{to_dir} #{args}")
        end

        def file(path, &block)
            # creates a file here and then does scp to the node
            filename = @directory.mktemp(&block)
            scp(filename, path) 
        end

        def proxy_factory
            # generates a node factory for nodes proxied through this one
            return ProxiedFactory.new(self)
        end

        def context
            return {
                :user => self.user,
                :host => self.host,
                :path => self.path
            }
        end

    end

    class TemplateNode < AbstractNode

        def __setup__
            raise "No template!" if template_name().nil?
            NodeUtils.install_templates(path(), template_name(), context)
        end

    end

    class SimpleNode < TemplateNode
        
        # a simple, directly reachable node
        def template_name
            "basic"
        end

    end

    class ProxiedNode < TemplateNode

        def template_name
            "proxy"
        end

        def context
            return super.merge({ :proxy => "#{@opts[:proxy].path}/ssh" })
        end

    end

    class G5KNode < AbstractNode

        def labels
            # TODO: I don't know if it is a good way to do it
            sites = %w{bordeaux grenoble lille luxembourg lyon nancy reims rennes sophia toulouse}
            site = sites.select { |x| @host.include?(x) }.map(&:to_sym)
            return [ :g5k ] + site[0..0]
        end

        def self.inside_g5k
            return $hostname.end_with?('grid5000.fr')
        end

        def __setup__
            # here we make some magic; there are 3 cases:
            #    1. Inside grid5000, we make efficient bootstrap using basic-templates
            #    2. Inside inria, we have efficient access to G5K
            #    3. Really outside (``chez moi'' for example)

            is_g5k = G5KNode.inside_g5k()
            return install_inside_g5k() if is_g5k
            if File.exist?("/etc/resolv.conf")
                resolv = IO.read("/etc/resolv.conf").lines.
                    select { |line| line.start_with?("domain ") or line.start_with?("search ") }
                domain = resolv.first
                if domain.nil? == false
                    domain = domain.split[1]
                    gw = inria_gateway(domain)
                    return install_inside_inria(gw) if (gw.nil? == false)
                end
            end
            return install_generic()
        end

        def inria_gateway(domain)
            # more stuff has to be implemented here
            return "grid5000.loria.fr" if domain == "loria.fr"
            return nil
        end

        def install_inside_g5k
            NodeUtils.install_templates(path(), "basic",
                context.merge({ :g5k_user => get_g5k_username() })
            )
        end

        def install_inside_inria(gw)
            NodeUtils.install_templates(path(), "inria",
                context.merge({ :g5k_user => get_g5k_username(), :gw => gw })
            )
        end

        def install_generic
            NodeUtils.install_templates(path(), "inria",
                context.merge({ :g5k_user => get_g5k_username(), :gw => "access.grid5000.fr" })
            )
        end

        def self.kavlan(job, manager)
            link = job["links"].select { |x| x["rel"] == "parent" }.first["href"]
            site = link.split("/").last
            front = manager.get_node(get_g5k_username(), "#{site}.grid5000.fr", G5KNodeFactory.new)
            ns = job["assigned_nodes"]
            begin
                ns = front.execute("kavlan -l -j #{job["uid"]}").lines.map(&:strip)
            rescue
                nil
            end
            return ns.map { |x| manager.get_node("root", x, G5KNodeFactory.new) }
        end

        def self.get_ssh_config
            return %x(echo ~/.ssh/config).strip
        end

        def self.obtain_ssh_pubkey_path
            return %x(echo ~/.ssh/id_rsa.pub).strip
        end

    end

    ### TYPES OF RESULTS ###

    class BasicRemoteResult

        attr_reader :opts
        attr_reader :node

        def initialize(node, cmd, stdout, stderr, opts = {})
            @node = node
            @cmd = cmd
            @stdout = stdout
            @stderr = stderr
            @opts = opts
        end

        def stdout
            return @stdout
        end

        def stderr
            return @stderr
        end

        def command
            return @cmd
        end

        def save_stdout(filename)
            IO.write(filename, @stdout)
        end

        def save_stderr(filename)
            IO.write(filename, @stderr)
        end

        def to_s
            return "BasicRemoteResult('#{@cmd}' on #{@node})"
        end

    end

    class FileRemoteResult < BasicRemoteResult

        def initialize(node, cmd, stdout, stderr, opts = {})
            # however! stdout & stderr are *paths*!
            super
        end

        def stdout
            return @node.execute("cat #{@stdout}").stdout
        end

        def stderr
            return @node.execute("cat #{@stderr}").stdout
        end

        def stdout_file
            return @stdout
        end

        def stderr_file
            return @stderr
        end

        def save_stdout(filename)
            return @node.execute_with_files("cat #{@stdout}", filename, "/dev/null")
        end

        def save_stderr(filename)
            return @node.execute_with_files("cat #{@stderr}", filename, "/dev/null")
        end

        def to_s
            return "FileRemoteResult('#{@cmd}' on #{@node}, out => #{@stdout}, err => #{@stderr})"
        end

    end

    class FileRemote
        # a remote file (but usually already local)
        # result is probably: LocalExecutionResult

        attr_reader :path
        attr_reader :result

        def initialize(path, result)
            @path = path
            @result = result
        end

    end

    class ManyExecutionResult

        def initialize(list, cmd)
            @list = list
            @command = cmd
        end

        def to_list
            return @list
        end

        def length
            return @list.length
        end

        def to_s
            return "ManyResult('#{@command}' on #{@list.length} nodes)"
        end

        def each(&block)
            return @list.each(&block)
        end

    end

    

    # we obtain a global grid5000 user
    $hostname = %x(hostname).strip
    $ssh_key = G5KNode.obtain_ssh_pubkey_path

    ## XPFLOW LIBRARY

    class NodesLibrary < ActivityLibrary

        activities :node_list, :execute, :copy, :run_script, :check_node, :file,
            :g5k_get_avail, :proxy_node, :broadcast, :g5k_site, :g5k_job,
            :g5k_nodes, :monitor_node,
            :g5k_kavlan_id, :g5k_kavlan_nodes_file, :g5k_frontend_from_job,
            :g5k_kavlan_nodes, :nodes_file, :execute_funny,
            :g5k_node, :execute_many, :execute_many_local, :all_prefixes, :execute_one, :distribute_one,
            :execute_many_ignore_errors, :g5k_kadeploy, :execute_many_here,
            :bootstrap_taktuk, :simple_node, :node_range, :taktuk_raw, :test_connectivity,
            :nodes_from_file, :nodes_from_result, :distribute, :chain_copy, :ssh_key,
            :nodes_from_machinefile, :g5k_deploy_keys, :localhost, :file_consistency,
            :ping_localhost, :ping_node, :g5k_reserve_nodes,
            :g5k_sites, :startExperiment, :experimentStatus, :terminateExperiment, :powderExperiment,
            :powder_execute_one, :powder_execute_many
        
        # Executes a command on a node in an experiment
        def powder_execute_one(experiment,node_name,user_name,command)
            lib = POWDER::Library.new
            ssh = "#{user_name}@#{node_name}.#{experiment.experiment}.#{experiment.project}.emulab.net"
            node = simple_node(ssh)
            res = execute_one(node,command)
            lib.log.log(res.stdout)          
        end


        # Executes the same command accross any number of nodes in an experiment and logs the result
        def powder_execute_many(experiment,*node_names,user_name,command)
            for i in node_names do
                powder_execute_one(experiment,node_names[i],user_name,command)
            end
        end
        # creates and returns a powder experiment object
        def powderExperiment(project,experiment,profile)
            exp = POWDER::PowderExperiment.new(project,experiment,profile)
            return exp
        end
        # starts a powder experiment using arguments or a powder experiment object
        def startExperiment(*args)
            lib = POWDER::Library.new
            lib.startExperiment(*args)
        end
        # terminates a powder experiment using arguments or a powder experiment object
        def terminateExperiment(*args)
            lib = POWDER::Library.new
            lib.terminateExperiment(*args)
        end
        # checks the status of a powder experiment using arguments or a powder experiment object
        def experimentStatus(*args)
            lib = POWDER::Library.new
            lib.experimentStatus(*args)
        end
        def setup
            nil
        end

        def ping_node(node, target)
            result = execute_one(node,"ping #{target} -c 1")
            result.stdout[/time=(\d+.*) /,1].to_f
        end

        def ping_localhost(node = nil)
            node = self.localhost() if node.nil?
            ping_node(node, "localhost") 
        end

        def get_g5k_tmpfile(prefix = "tmp")
            hash = 16.times.map { |x| (rand * 16).to_i.to_s(16) }.join
            return "/tmp/.#{prefix}-#{get_g5k_username()}-#{hash}"
        end

        def all_prefixes(nodes, inc = 1)
            arr = []
            i = inc - 1
            while i < nodes.length
                arr.push(nodes[0..i])
                i += inc
            end
            return arr
        end

        def nodes
            return Scope.current[:__nodes__]
        end

        def _transform_nodes(x)
            if x.is_a?(String)
                return x.strip.split
            elsif x.is_a?(Hash)
                h = x.map { |k, v| [ k.strip, _transform_nodes(v) ] }
                return Hash[h]
            elsif x.is_a?(Array)
                return x.map { |x| _transform_nodes(x) }
            else
                raise "Error!"
            end
        end

        def _get_node_via_proxy(name, parent = nil)
            name = name.strip
            name = "nancy.g5k" if name == "g5k"
            if /^(.+)\.g5k$/.match(name)
                raise "G5K proxies must be topmost" if !parent.nil?
                # special syntax for G5K
                site = name.split(".").first
                proxy = g5k_site(site)
                return proxy
            else
                user, host = name.split("@")
                if parent.nil?
                    proxy = simple_node(name)
                else
                    proxy = proxy_node(parent, user, host)
                end
                return proxy
            end
        end

        def __transform_with_proxy(structure, proxy, nodes)
            # proxy_node(via, user, host)
            if structure.is_a?(String)
                node = _get_node_via_proxy(structure, proxy)
                nodes[:nodes].push(node)
            elsif structure.is_a?(Array)
                structure.each { |x| __transform_with_proxy(x, proxy, nodes) }
            elsif structure.is_a?(Hash)
                structure.each_pair do |p, sub|
                    new_proxy = _get_node_via_proxy(p, proxy)
                    nodes[:proxies].push(new_proxy)
                    __transform_with_proxy(sub, new_proxy, nodes)
                end
            else
                raise "Error!"
            end
        end

        def _transform_with_proxy(tree)
            nodes = { :nodes => [], :proxies => [] }
            __transform_with_proxy(tree, nil, nodes)
            return nodes
        end

        def nodes_from_machinefile(filename, opts = {})
            nodes = IO.read(filename).strip.split
            nodes = nodes.map { |x| "#{opts[:user]}@#{x}" }
            return nodes.map { |x| simple_node(x) }
        end

        def nodes_from_file(filename, opts = {})
            contents = IO.read(filename)
            yaml = YAML.load(contents)
            tree = _transform_nodes(yaml)
            nodes = _transform_with_proxy(tree)
            return nodes[:nodes]
        end

        def _parse_opts(array)
            h = {}
            array.each do |o|
                k, v = o.split("=")
                h[k.to_sym] = v
            end
            return h
        end

        def nodes_from_result(result, proxy = nil)
            lines = result.stdout.strip.lines.map(&:strip)
            r = lines.map do |line|
                userhost = line.split.first
                opts = _parse_opts(line.split[1..-1])
                if proxy.nil?
                    simple_node(userhost, opts)
                else
                    u, h = userhost.split("@")
                    proxy_node(proxy, u, h, opts)
                end
            end
            return r
        end

        # activities

        def node_list()
            return nodes()
        end

        def get_node_list(args)
            # extracts nodes and a command from arguments
            if args.length == 1
                return [ node_list(), args.first ]
            end
            if args.length == 2
                cmd = args.last
                return [ arrayize(args.first), cmd ]
            end
            raise "Wrong number of arguments"
        end

        def arrayize(nodes)
            # turns the argument into a list of nodes
            if !nodes.is_a?(Array)
                nodes = [ nodes ]
            end
            return nodes
        end

        def execute(nodes, cmd, env = {})
            wd = env.delete(:wd)
            nodes = arrayize(nodes)
            arr = []
            nodes.each do |node|
                res = node.execute(cmd, env, :wd => wd)
                arr.push(res)
            end
            return arr
        end

        def execute_one(node, cmd, env = {})
            return execute(node, cmd, env).first
        end

        def _execute_many_parse_args(args)
            opts = {}
            opts = args.pop if args.last.is_a?(Hash)
            nodes, cmd = get_node_list(args)
            return [ nodes, cmd, opts ]
        end

        def _get_taktuk(nodes, options = {})
            # domains = nodes.map(&:domain).uniq
            # raise "TakTuk: nodes span different domains" if domains.length != 1

            master = nodes.first
            nodes = nodes.tail if options[:exclude_master]
            taktuk = File.join(master.directory.path, "ssh taktuk")
            directory = proxy.engine.main_directory
            opts = {
                :stdout => directory.mktemp(),
                :stderr => directory.mktemp(),
                :filename => directory.mktemp()
            }.merge(options)
            return TakTukRun.new(taktuk, nodes, opts)
        end

        def bootstrap_taktuk(nodes)
            
            if nodes.is_a?(AbstractNode)
                nodes = [ nodes ]
            end

            if nodes.length == 0
                return
            end

            cmd = "(dpkg -l | grep taktuk) || apt-get install -y --force-yes taktuk"
            escaped_cmd = Shellwords.escape(cmd)
            master = nodes.first
            master.execute(escaped_cmd)

            proxy.log("#{master} has TakTuk now")

            return execute_many(nodes, cmd, :propagate => true)
        end

        def execute_many_here(*args)
            nodes, cmd, opts = _execute_many_parse_args(args)

            return ManyExecutionResult.new([], cmd) if nodes.length == 0

            taktuk = _get_taktuk(nodes, opts)
            
            # command has to be escape 2 times: local shell and remote shell
            succ, fail = taktuk.execute(cmd, :escape => 2)

            if succ.length != nodes.length
                raise "TakTuk: Some nodes failed (success: #{succ.length}/#{nodes.length}). See #{taktuk.stdout}"
            end

            results = succ.map do |x|
                BasicRemoteResult.new(x[:node], cmd, x[:stdout], x[:stderr])
            end
            return ManyExecutionResult.new(results, cmd)
        end

        def execute_many(*args)
            nodes, cmd, opts = _execute_many_parse_args(args)

            return ManyExecutionResult.new([], cmd) if nodes.length == 0

            taktuk = _get_taktuk(nodes, opts)

            succ, fail = taktuk.execute_remote(cmd, :escape => 2)

            if succ.length != nodes.length
                msg = "TakTuk: Some nodes failed (success: #{succ.length}/#{nodes.length})."
                if fail.length > 0
                    msg += " See #{fail.first[:stdout_file]}"
                end
                msg += " See #{taktuk.stdout}"
                raise msg
            end

            results = succ.map do |x|
                FileRemoteResult.new(x[:node], cmd, x[:stdout_file], x[:stderr_file])
            end
            return ManyExecutionResult.new(results, cmd)
        end

        def distribute_one(f, nodes, dest, opts = {})

            nodes = [ nodes ] unless nodes.is_a?(Array)

            if f.is_a?(String)
                # nothing
            elsif f.is_a?(LocalExecutionResult)
                f = f.stdout_file
            elsif f.is_a?(FileRemote)
                f = f.result.stdout_file
            else
                raise "I don't know how to distribute #{f.class}"
            end

            if dest.end_with?("/")  # a directory
                dest = File.join(dest, File.basename(f))
            else # a file
                # it's fine
            end

            proxy.log("Saving to: #{dest}")

            master = nodes.first

            return nil if nodes.length == 0

            master = nodes.first
            master.scp_many([ f ], dest)

            return nil if nodes.length == 1

            taktuk = _get_taktuk(nodes, :exclude_master => true)
            results = taktuk.put(dest, dest, :escape => 2)

            if results.length + 1 != nodes.length
                raise "Some nodes did not respond."
            end

            thelist = results.map { |x| x[:hash] }.uniq
            raise "Some hashes were different." if thelist.length != 1

            orig_hash = md5sum(nodes, [ dest ]).map { |x| x[:hash] }.uniq

            if orig_hash.length != 1
                raise "Hashes could not be verified."
            end

            return nil
        end

        def file_consistency(nodes, fs)
            if !fs.is_a?(Array)
                fs = [ fs ]
            end
            sums = md5sum(nodes, fs)
            hashes = Hash.new { |h, k| h[k] = [] }
            sums.each do |h|
                hashes[h[:filename]].push(h[:hash])
            end
            hashes.each_pair do |f, h|
                raise "File #{f} is not consistent" if h.uniq.length != 1
            end
        end

        def md5sum(nodes, files)
            h = []
            results = execute_many_here nodes, "md5sum #{files.join(' ')}"
            results.to_list.each do |r|
                r.stdout.strip.lines do |line|
                    hash, filename = line.split
                    h.push({ :filename => filename, :hash => hash })
                end
            end
            return h
        end

        def distribute(glob, nodes, dest, opts = {})

            nodes = [ nodes ] unless nodes.is_a?(Array)
            glob = glob.first if glob.is_a?(Array)

            if glob.is_a?(String)
                files = Dir[glob]  # get a list of files
            elsif glob.is_a?(LocalExecutionResult)
                files = [ glob.stdout_file ]
            elsif glob.is_a?(FileRemote)
                files = [ glob.result.stdout_file ]
            else
                raise "I don't know how to distribute #{glob.class}"
            end
            remote_files = files.map { |f| File.join(dest, File.basename(f)) }

            proxy.log("Found #{files.length} files to distribute.")

            return nil if nodes.length == 0

            master = nodes.first
            master.scp_many(files, dest)

            proxy.log("Files copied to #{master}:#{dest}")

            if nodes.length == 1
                return nil
            end

            md5sum = master.execute("md5sum #{remote_files.join(' ')}").stdout
            orig_hashes = {}
            md5sum.strip.lines do |line|
                hash, filename = line.strip.split
                orig_hashes[filename] = hash
            end

            hashes = {}
            remote_files.each do |filepath|
                proxy.log("Distributing #{filepath}")
                taktuk = _get_taktuk(nodes, :exclude_master => true)
                results = taktuk.put(filepath, filepath, :escape => 2)
                
                if results.length + 1 != nodes.length
                    raise "Some nodes did not respond."
                end

                thelist = results.map { |x| x[:hash] }.uniq
                raise "Some hashes were different." if thelist.length != 1

                hashes[filepath] = thelist.first
            end

            raise "Weird?" if hashes.keys.sort != orig_hashes.keys.sort

            orig_hashes.keys.each do |filepath|
                raise "Hash for #{filepath} does not match." \
                    if orig_hashes[filepath] != hashes[filepath]
            end

            proxy.log("MD5s match.")

        end

        def ssh_key
            return $ssh_key
        end

        def test_connectivity(nodes)
            execute_many nodes, "true"
        end

        def chain_copy(nodes, src, dest, opts = {})

            nodes = [ nodes ] unless nodes.is_a?(Array)

            raise "'#{src}' does not exist!" unless File.exist?(src)

            dest = File.join(dest, File.basename(src))

            return nil if nodes.length == 0

            master = nodes.first
            laster = nodes.last

            master.scp(src, dest)

            proxy.log("#{src} copied to #{master}:#{dest}")

            if nodes.length == 1
                return nil
            end

            orig_hash = master.execute("md5sum #{dest}").stdout.strip.split.first

            execute_many(nodes, "apt-get install -y mbuffer")

            # mbuffer creates a buffer of size 2% * memory (by default) 
            # we do chainsend thing

            second = nodes[1].host
            ssh_opts = "-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
            master.file("/tmp/.chainsend") do |f|
                f.puts "set -eu"
                f.puts "cat $1 | ssh #{ssh_opts} #{second} \"bash /tmp/.chainsend $1\""
            end
            laster.file("/tmp/.chainsend") do |f|
                f.puts "set -eu"
                f.puts "cat > $1"
            end
            nodes.each_with_index do |node, i|
                next if i == 0 or i == nodes.length - 1
                next_host = nodes[i+1].host
                node.file("/tmp/.chainsend") do |f|
                    f.puts "set -eu"
                    f.puts "tee $1 | mbuffer -q | ssh #{ssh_opts} #{next_host} \"bash /tmp/.chainsend $1\""
                end
            end

            proxy.log("Chain prepared.")
            
            master.execute("bash /tmp/.chainsend #{dest}")
            results = execute_many_here(nodes, "md5sum #{dest}")

            hashes = results.to_list.map { |x| x.stdout.split.first }.uniq

            raise "Hashes differ." if hashes.length != 1

            return nil
        end

        def file(node, path)
            r = execute_one(node, "cat #{path}")
            return FileRemote.new(path, r)
        end

        def copy(name, nodes, where)
            # make a copy of a file named "name" to "nodes"
            # at path "where"; name can be: 
            #     * a path (at local fs)
            #     * a LocalExecutionResult (as a result of remote execution)
            #     * RemoteFile - pointer to a file on a remote node

            name = name.first if name.is_a?(Array)
            
            if name.is_a?(String)
                # ok
            elsif name.is_a?(LocalExecutionResult)
                name = name.stdout_file
            elsif name.is_a?(FileRemote)
                name = name.result.stdout_file
            else
                raise "Unknown file source: #{name.class}"
            end

            nodes = arrayize(nodes)
            result = nodes.map do |node|
                node.scp(name, where)
            end
            return result
        end

        def run_script(name, label = :all)
            path = $files[name]
            node_list(label).each do |node|
                f = node.tmpfile
                node.scp(path, f)
                node.chmod(f, "700")
                out = node.execute(f)
                node.rm(f)
            end
        end

        def check_node(node)
            debug "Checking #{node}..."
            failed = []
            begin
                node.ping()
            rescue ExecutionError => e
                return false
            end
            return true
        end

        def with_g5k_lib(p)
            lib = G5K::Library.new
            lib.logging = proc { |x| p.engine.log(x) }
            lib.proxy = p
            return yield(lib)

        end

        def g5k_reserve_nodes(*args)
            with_g5k_lib(proxy) do |lib|
                lib.reserve_nodes(*args)
            end
        end

        def g5k_sites(*args)
            with_g5k_lib(proxy) do |lib|
                lib.sites()
            end
        end

        def g5k_get_avail(opts = {})
            with_g5k_lib(proxy) do |lib|
                lib.pick_reservation(opts)
            end
        end

        def nodes_file(user, filepath)
            nodes = IO.read(filepath).chomp.lines.map(&:chomp)
            nodes = nodes.map do |host|
                simple_node("#{user}@#{host}")
            end
            return nodes
        end

        def g5k_job(opts = {})
            lib = G5K::Library.new
            lib.logging = proc { |x| puts x }
            job = lib.job(opts[:site], opts[:id])
            return job
        end

        def g5k_nodes(job)
            hosts = job["assigned_nodes"]
            username = get_g5k_username()
            return hosts.map { |h| g5k_node(username, h) }
        end

        def g5k_site_from_job(job)
            nodes = job["assigned_nodes"]
            link = job["links"].select { |x| x["rel"] == "parent" }.first
            site = link["href"].split("/").last
            return site
        end

        def _filter_vlan(ok_nodes, vlan_nodes)
            h = {}
            hosts = ok_nodes.each { |x| h[x.split(".").first] = true }
            # puts hosts.inspect
            good_ones = vlan_nodes.select { |x| h.key?(x.split("-kavlan").first) }
            # puts good_ones.inspect
            return good_ones
        end

        def g5k_deploy_keys(nodes, site)
            # assumes you are on the frontend
            key = get_g5k_tmpfile("ssh_key")
            frontend = g5k_site(site)
            frontend.execute("rm -f #{key} #{key}.pub; ssh-keygen -f #{key} -q -N \'\'")
            nodes.each do |n|
                proxy.log "Sending key to: #{n.userhost}"
                frontend.execute("scp -o 'BatchMode=yes' -o 'UserKnownHostsFile=/dev/null' #{key} #{n.userhost}:.ssh/id_rsa")
                frontend.execute("ssh-copy-id -i #{key}.pub #{n.userhost}")
            end
            frontend.execute("rm -f #{key} #{key}.pub")
        end

        def g5k_kadeploy(job, env, custom = "", opts = {})

            site = g5k_site_from_job(job)
            frontend = g5k_site(site)
            nodes = job["assigned_nodes"]

            nodes = opts.key?(:count) ? nodes[0...opts[:count]] : nodes
            final_nodes = opts[:real_nodes]

            proxy.log("Using #{nodes.length} machines.")

            machinefile = get_g5k_tmpfile("machines")
            nodes_ok = get_g5k_tmpfile("good_nodes")

            IO.write(machinefile, nodes.join("\n"))
            frontend.scp(machinefile, machinefile)
            kadeploy = "kadeploy3 -f #{machinefile} -e #{env} -k #{custom} -o #{nodes_ok}"
            proxy.log("Running deployment: #{kadeploy}")
            frontend.execute(kadeploy)
            frontend.execute("rm -f #{machinefile}")

            key = get_g5k_tmpfile("ssh_key")
            frontend.execute("rm -f #{key} #{key}.pub; ssh-keygen -f #{key} -q -N \'\'")

            ok_nodes = frontend.execute("sort -V #{nodes_ok}").stdout.split
            frontend.execute("rm -f #{nodes_ok}")

            proxy.log("Nodes that survived: #{ok_nodes.length}/#{nodes.length}")
            proxy.log("Final nodes: #{final_nodes}")

            if final_nodes.nil?
                final_nodes = ok_nodes
            else
                final_nodes = _filter_vlan(ok_nodes, final_nodes)
            end

            # we have to install SSH keys
            final_nodes.each do |n|
                host = "root@#{n}"
                frontend.execute("scp -o 'BatchMode=yes' -o 'UserKnownHostsFile=/dev/null' #{key} #{host}:.ssh/id_rsa")
                frontend.execute("ssh-copy-id -i #{key}.pub #{host}")
            end
            frontend.execute("rm -f #{key} #{key}.pub")

            all_nodes = final_nodes.map { |x| g5k_node("root", x) }
            return all_nodes
        end

        def g5k_frontend_from_job(job)
            site = g5k_site_from_job(job)
            frontend = g5k_site(site)
            return frontend
        end

        def g5k_kavlan_id(job)
            uid = job['uid']
            frontend = g5k_frontend_from_job(job)
            out = frontend.execute("kavlan -V -j #{uid}")
            return out.stdout.strip.to_i
        end

        def g5k_kavlan_nodes_file(job)
            # TODO
            uid = job['uid']
            kavlan_nodes = get_g5k_tmpfile("kavlan_nodes")
            frontend = g5k_frontend_from_job(job)
            out = frontend.execute("kavlan -l -j #{uid}")
            IO.write(kavlan_nodes, out.stdout)
            frontend.scp(kavlan_nodes, kavlan_nodes)
            return kavlan_nodes
        end

        def g5k_kavlan_nodes(job)
            uid = job['uid']
            frontend = g5k_frontend_from_job(job)
            out = frontend.execute("kavlan -l -j #{uid}")
            hosts = out.stdout.strip.lines.map(&:strip)
            nodes = hosts.map { |x| g5k_node("root", x) }
            return nodes
        end

        def g5k_site(site)
            manager = proxy.engine.nodes_manager
            return manager.get_node(get_g5k_username(), "#{site}.grid5000.fr", G5KNodeFactory.new)
        end

        def g5k_node(user, host)
            manager = proxy.engine.nodes_manager
            return manager.get_node(user, host, G5KNodeFactory.new)
        end

        def proxy_node(via, user, host, opts = {})
            manager = proxy.engine.nodes_manager
            return manager.get_node(user, host, ProxiedFactory.new(via), opts)
        end

        def split(pattern)
            pattern = pattern.strip
            if pattern == ""
                raise "Empty host specification"
            end
            parts = pattern.split("@")
            if parts.length == 2
                return parts
            elsif parts.length > 2
                raise "Invalid host specification: #{pattern}"
            else
                proxy.log "User not specified. This is not reproducible."
                return [ Etc.getlogin, pattern ]
            end
        end

        def broadcast(pattern)
            manager = proxy.engine.nodes_manager
            user, address = split(pattern)  
            nodes = NodeUtils.broadcast_ping(address)
            proxy.log("Found #{nodes.length} hosts via ICMP broadcast")
            return nodes.map { |n| manager.get_node(user, n) }
        end

        def node_range(ip_start, count)
            user, host = split(ip_start)
            parts = host.split(".").map(&:to_i)
            ips = []
            count.times do |i|
                j = 3
                while j > 0 and parts[j] == 256
                    parts[j] = 0
                    parts[j - 1] += 1
                    j -= 1
                end
                ip = parts.map(&:to_s).join(".")
                ips.push(ip)
                parts[3] += 1
            end
            return ips.map { |x| simple_node("#{user}@#{x}") }
        end

        def simple_node(pattern, opts = {})
            user, host = split(pattern)
            manager = proxy.engine.nodes_manager
            return manager.get_node(user, host, SimpleNodeFactory.new, opts)
        end

        def localhost()
            user = ENV["USER"]
            return simple_node("#{user}@127.0.0.1")
        end

    end

    module NodeUtils

        def self.get_templates_dir(name)
            here = File.dirname(__FILE__)
            return realpath(File.join(here, name))
        end

        def self.render_file(t, path, ctx)
            out = Erb.render(IO.read(t), ctx)
            File.open(path, "wb") do |f|
                f.write(out)
                f.chmod(0700)
            end
        end

        def self.install_templates(path, name, ctx)
            templates = get_templates_dir("templates")
            ctx = ctx.merge({ :templates => templates })
            tdir = get_templates_dir("templates/utils")
            Dir.entries(tdir).each do |f|
                template = File.join(tdir, f)
                output = File.join(path, f)
                render_file(template, output, ctx) if File.file?(template)
            end
            config = get_templates_dir("templates/ssh-config.#{name}")
            ssh_config = File.join(path, "ssh-config")
            render_file(config, ssh_config, ctx)
        end

        # uses a broadcast ping to get a list of nodes that respond
        def self.broadcast_ping(address, timeout = 2)
            output = %x(ping -c 3 -n -b #{address} -w #{timeout} 2> /dev/null)
            # raise "Ping returned error #{$?.exitstatus}." if $?.exitstatus != 0
            ms = output.scan(/from ([\.0-9]+): icmp_seq=/)
            addresses = ms.flatten.uniq.sort
            raise "No nodes found" if addresses.length == 0
            return addresses
        end

        class Erb < OpenStruct

            def render(hash)
                ERB.new(hash).result(binding)
            end

            def self.render(template, hash)
                x = Erb.new(hash)
                return x.render(template)
            end

        end

    end

end
