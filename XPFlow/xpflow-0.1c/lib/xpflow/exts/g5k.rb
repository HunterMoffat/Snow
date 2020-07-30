#
# name: XPFlow::G5K::Library
#

require 'tempfile'
require 'etc'
require 'json'
require 'xpflow'
require 'restclient'
require 'pp'
require 'digest'
require 'date'
require 'cgi'
require 'shellwords'

module XPFlow; module G5K

    SSH_CONFIG = "/tmp/.xpflow_ssh_config_#{Etc.getlogin}"

    def self.install_ssh_config_file(user)
        # TODO: this has to be fixed
        # race conditions are possible
        File.open(SSH_CONFIG, File::WRONLY|File::CREAT, 0600) do |f|
            f.flock(File::LOCK_EX)
            f.truncate(0)
            f.write("LogLevel quiet\n")
            f.write("StrictHostKeyChecking no\n")
            f.write("UserKnownHostsFile /dev/null\n")
            f.write("ForwardAgent yes\n")
            f.write("Host g5k\n")
            f.write("  Hostname access.nancy.grid5000.fr\n")
            f.write("  User #{user}\n\n")
            f.write("Host *.g5k\n")
            f.write("  User #{user}\n")
            f.write("  ProxyCommand ssh -F #{SSH_CONFIG} g5k \"nc -q 0 `basename %h .g5k` %p\"\n\n")

        end
    end

    def self.get_ssh_key
        name = File.expand_path('~/.ssh/id_rsa.pub')
        raise 'SSH key not present' unless File.exists?(name)
        return IO::read(name).strip
    end

    class G5KRestFactory

        def initialize
            @mutex = Mutex.new
        end

        def get_credentials
            return [ $g5k_user, $g5k_pass ]
        end

        def connect
            @mutex.synchronize do
                creds = get_credentials()
                G5KRest.new(*creds)
            end
        end

    end

    class G5KArray < Array

        alias old_select select

        def list
            return self
        end

        def uids
            return self.map { |it| it['uid'] }
        end

        def select(&block)
            return old_select(&block)
        end

        def __repr__
            return self.map { |it| it.__repr__ }.to_s
        end

    end

    class G5KJson < Hash

        def items
            return self['items']
        end

        def rel(r)
            return self['links'].detect { |x| x['rel'] == r }['href']
        end

        def rel_self
            return rel('self')
        end

        def rel_parent
            return rel('parent')
        end

        def link(title)
            return self['links'].detect { |x| x['title'] == title }['href']
        end

        def uid
            return self['uid']
        end

        def self.parse(s)
            return JSON.parse(s, :object_class => G5KJson, :array_class => G5KArray)
        end

        def __repr__
            return self['uid'] unless self['uid'].nil?
            return Hash[self.map { |k, v| [k, v.__repr__ ] }].to_s
        end

        def refresh(g5k)
            return g5k.get_json_raw(rel_self)
        end

        def job_type
            # gets type of job
            return (self['types'].include?('deploy') ? :deploy : :normal)
        end

    end

    class G5KRest

        # Basic Grid5000 Rest Interface

        attr_reader :user

        def self.from_config
            G5KRestFactory.new.connect
        end

        def initialize(user, pass)
            @user = user
            @pass = pass
            raise "You forgot to use :g5k library!" if (user.nil? or pass.nil?)
            user_escaped = CGI.escape(user)
            pass_escaped = CGI.escape(pass)
            @endpoint = "https://#{user_escaped}:#{pass_escaped}@api.grid5000.fr"
            @api = RestClient::Resource.new(@endpoint, :timeout => 15)
        end

        def resource(path)
            path = path[1..-1] if path.start_with?('/')
            return @api[path]
        end

        def delete_json_raw(path)
            begin
                return resource(path).delete()
            rescue RestClient::InternalServerError => e
                raise
            end
        end

        def post_json_raw(path, json)
            r = resource(path).post(json.to_json, 
                :content_type => "application/json", :accept => "application/json")
            return G5KJson.parse(r)
        end

        def get_json_raw(path)
            maxfails = 3
            fails = 0
            while true
                begin
                    r = resource(path).get()
                    return G5KJson.parse(r)
                rescue RestClient::RequestTimeout
                    fails += 1
                    raise if fails > maxfails
                    Kernel.sleep(1.0)
                end
            end
        end


        def get_json(resource)
            return get_json_raw("sid/#{resource}")
        end

        def post_json(resource, json)
            begin
                return post_json_raw("sid/#{resource}", json)
            rescue => e
                raise
            end
        end

        def get_items(resource)
            return get_json(resource).items
        end


        def get_sites
            sites = get_items('sites').list
            return sites
        end

        def get_site_status(site)
            return get_items("sites/#{site}/status").list
        end

        def get_jobs(site, uid = nil)
            filter = uid.nil? ? "" : "&user_uid=#{uid}"
            resource = "sites/#{site}/jobs/?state=running#{filter}"
            return get_items(resource).list
        end

        def get_job(site, jid)
            resource = "sites/#{site}/jobs/#{jid}"
            return get_json(resource)
        end

        def get_clusters(site)
            return get_items("sites/#{site}/clusters").list
        end

        def get_switches(site)
            items = get_items("sites/#{site}/network_equipments")
            items = items.select { |x| x['kind'] == 'switch' }
            # extract nodes connected to those switches
            items.each { |switch|
                conns = switch['linecards'].detect { |c| c['kind'] == 'node' }
                next if conns.nil?  # IB switches for example
                nodes = conns['ports'] \
                    .select { |x| x != {} } \
                    .map { |x| x['uid'] } \
                    .map { |x| "#{x}.#{site}.grid5000.fr"}
                switch['nodes'] = nodes
            }
            return items.select { |it| it.key?('nodes') }
        end

        def get_switch(site, name)
            s = get_switches(site).detect { |x| x.uid == name }
            raise "Unknown switch '#{name}'" if s.nil?
            return s
        end

        def follow_link(obj, rel)
            return get_json_raw(obj.link(rel))
        end

        def follow_parent(obj)
            return get_json_raw(obj.rel_parent)
        end

        def get_nodes_status(site)
            nodes = {}
            get_site_status(site).map do |node|
                name = node['node_uid']
                name = "#{name}.#{site}.grid5000.fr" unless name.end_with?('.fr')
                status = node['system_state']
                nodes[name] = status
            end
            return nodes
        end

    end

    Factory = G5KRestFactory.new

    class Library < ActivityLibrary

        attr_accessor :logging
        attr_accessor :proxy

        activities :reserve, :reserve_nodes, :release, :nodes, :switches, :switch,
                   :nodes_of_switch, :sites, :jobs, :wait_for_job, :nodes_available,
                   :release_all, :my_jobs, :wait_for_reservation, :nodes_available?,
                   :deploy, :execute, :copy, :bash, :dist_keys, :execute_frontend,
                   :bash_frontend, :distribute, :retrieve, :kavlan, :vlan_nodes,
                   :vlan_bash, :pick_reservation,
                   :node_site, :nodes_sites, :run_script, :rsync,
                   :version, :job,
                   :clean, :dist_ssh_keys

        def initialize
            super
            @cache = Cache.new
            G5K.install_ssh_config_file(g5k.user)
            inject_library('__core__', CoreLibrary.new)
        end

        def version
            return "0.1"
        end

        def inside_g5k
            # checks if we are inside Grid5000
            @cache.fetch(:inside_g5k) do
                `hostname`.strip.end_with?('grid5000.fr')
            end
        end

        def g5k
            Factory.connect
        end

        def nodes_with_site(nodes)
            # maps each node to its site
            ss = site_uids()
            h = {}
            nodes.each do |n|
                s = ss.detect { |x| n.include?(x) }
                raise "Could not map node '#{n}' to its site" if s.nil?
                h[n] = s
            end
            return h
        end

        def nodes_sites(nodes)
            # returns a set of sites the given nodes are at
            return nodes_with_site(nodes).values.uniq
        end

        def node_site(node)
            return nodes_sites([ node ]).first
        end

        def nodes_status(nodes)
            # maps nodes to their statuses
            status = {}
            nodes_sites(nodes).each do |site|
                st = g5k.get_nodes_status(site)
                st = st.select { |k, v| nodes.include?(k) }
                st = Hash[st]
                status = status.merge(st)
            end
            # beware: it is not guaranteed that every node will have its status!
            return status
        end

        def nodes_available(nodes, opts = {})
            ignore_dead = opts[:ignore_dead]
            status = nodes_status(nodes)
            avail = status.select do |k, v|
                (v == 'free') or (ignore_dead and v == 'unknown')
            end
            return Hash[avail].keys
        end

        def nodes_available?(nodes, opts = {})
            avail = nodes_available(nodes, opts)
            unavail = nodes - avail
            r = unavail.empty?
            r.inject_method(:availability) do
                1.0 - (unavail.length.to_f / nodes.length.to_f)
            end
            r.inject_method(:total) { nodes.length }
            return r
        end

        def filter_dead_nodes(nodes)
            # remove dead or unknown nodes
            dead = []
            nodes_status(nodes).each do |node, status|
                dead.push(node) if status == 'unknown'
            end
            return nodes - dead
        end

        def parse_time(spec)
            spec = spec.strip
            return DateTime.now.to_s if spec == "now"
            timezone = `date +%Z`.strip
            return DateTime.parse("#{spec} #{timezone}").to_s
        end

        def handle_slash(opts)
            slash = nil
            predefined = { :slash_22 => 22, :slash_18 => 18 }
            if opts[:slash]
                bits = opts[:slash].to_i
                slash = "slash_#{bits}=1"
            else
                slashes = predefined.select { |label, bits| opts.key?(label) }
                unless slashes.empty?
                    label, bits = slashes.first
                    count = opts[label].to_i
                    slash = "slash_#{bits}=#{count}"
                end
            end
            return slash
        end

        def pick_reservation(opts = {})
            site = opts[:site]
            jobs = site.nil? ? my_all_jobs() : jobs(site)
            # pp jobs
            jobs = jobs.select { |x| x['state'] == 'running' }
            jobs = jobs.select { |x| x['user_uid'] == g5k.user }  # WEIRD!
            raise "No reservations available" if jobs.empty?
            raise "Too many reservation meeting the criteria." if jobs.length > 1
            job = jobs.first
            info "Found reservation with ID = #{job["uid"]}"
            j = g5k.get_json_raw(job.rel_self)
            j = wait_for_job(j)
            return j
        end

        def job(site, jid)
            j = g5k.get_job(site, jid.to_i)
            j = wait_for_job(j)
            return j
        end

        def reserve_nodes(opts)
            # helper for making the reservations the easy way
            nodes = opts.fetch(:nodes, 1)
            time = opts.fetch(:time, '01:00:00')
            at = opts[:at]
            slash = handle_slash(opts)
            site = opts[:site]
            type = opts.fetch(:type, :normal)
            keep = opts[:keep]
            name = opts.fetch(:name, 'xpflow job')
            command = opts[:cmd]
            async = opts[:async]
            ignore_dead = opts[:ignore_dead]
            props = nil
            vlan = opts[:vlan]
            cluster = opts[:cluster]

            raise 'At least nodes, time and site must be given' \
                if [nodes, time, site].any? { |x| x.nil? }

            secs = Timespan.to_secs(time)
            time = Timespan.to_time(time)

            if nodes.is_a?(Array)
                all_nodes = nodes
                nodes = filter_dead_nodes(nodes) if ignore_dead
                removed_nodes = all_nodes - nodes
                info "Ignored nodes #{removed_nodes}." unless removed_nodes.empty?
                hosts = nodes.map { |n| "'#{n}'" }.sort.join(',')
                props = "host in (#{hosts})"
                nodes = nodes.length
            end

            raise 'Nodes must be an integer.' unless nodes.is_a?(Integer)
            site = site.__repr__
            raise 'Type must be either :deploy or :normal' \
                unless (type.respond_to?(:to_sym) && [ :normal, :deploy ].include?(type.to_sym))
            command = "sleep #{secs}" if command.nil?    
            type = type.to_sym

            resources = "/nodes=#{nodes},walltime=#{time}"
            resources = "{cluster='#{cluster}'}" + resources unless cluster.nil?
            resources = "{type='kavlan'}/vlan=1+" + resources if vlan == true
            resources = "#{slash}+" + resources unless slash.nil?

            payload = {
                'resources' => resources,
                'name' => name,
                'command' => command
            }

            info "Reserving resources: #{resources} (type: #{type}) (in #{site})"

            payload['properties'] = props unless props.nil?
            if type == :deploy
                payload['types'] = [ 'deploy' ]
            else
                payload['types'] = [ 'allow_classic_ssh' ]
            end

            unless at.nil?
                dt = parse_time(at)
                payload['reservation'] = dt
                info "Starting this reservation at #{dt}"
            end

            begin
                r = g5k.post_json("sites/#{site}/jobs", payload)
            rescue => e
                raise
            end

            # it may be a different thread that releases reservations
            # therefore we need to dereference proxy which
            # in fact uses Thread.current and is local to the thread...
            
            engine = proxy.engine

            engine.on_finish do
                engine.verbose("Releasing job at #{r.rel_self}")
                release(r)
            end if keep != true

            job = g5k.get_json_raw(r.rel_self)
            job = wait_for_job(job) if async != true
            return job
        end

        def info(msg)
            if @logging
                @logging.call(msg)
            else
                proxy.engine.log(msg, :g5k)
            end
        end

        def wait_for_job(job)
            # wait for the job to be in a running state
            # timeouts after 10 seconds
            jid = job.__repr__
            info "Waiting for reservation #{jid}"
            Timeout.timeout(36000) do
                while true
                    job = job.refresh(g5k)
                    t = job['scheduled_at']
                    if !t.nil?
                        t = Time.at(t)
                        secs = [ t - Time.now, 0 ].max.to_i
                        info "Reservation #{jid} should be available at #{t} (#{secs} s)"
                    end
                    break if job['state'] == 'running'
                    raise "Job is finishing." if job['state'] == 'finishing'
                    Kernel.sleep(5)
                end
            end
            info "Reservation #{jid} ready"
            return job
        end

        def release_all(site)
            # releases all jobs on a site
            site = site.__repr__
            Timeout.check(20) do
                jobs = my_jobs(site)
                pass if jobs.length == 0
                begin
                    jobs.each { |j| release(j) }
                rescue RestClient::InternalServerError => e
                    raise unless e.response.include?('already killed')
                end
            end
        end

        def release(r)
            begin
                return g5k.delete_json_raw(r.rel_self)
            rescue RestClient::InternalServerError => e
                raise unless e.response.include?('already killed')
            end
        end

        def reserve(opts)
            raise 'not implemented'
        end

        def sites
            @cache.fetch(:sites) do
                g5k.get_sites
            end
        end

        def site_uids
            return sites.uids
        end

        def nodes(r)
            return r['nodes'] if r.key?('nodes')
            return r['assigned_nodes']
        end

        def vlan_nodes(r)
            vlan = kavlan(r)
            return vlan[:hosts]
        end

        def jobs(site)
            name = site.__repr__
            return g5k.get_jobs(name)
        end

        def my_jobs(site)
            name = site.__repr__
            return g5k.get_jobs(name, g5k.user)
        end

        def my_all_jobs
            ss = sites()
            return ss.map { |s| my_jobs(s) }.reduce(:+)
        end

        def switches(site)
            name = site.__repr__
            return g5k.get_switches(name)
        end

        def switch(site, sw)
            name = site.__repr__
            return g5k.get_switch(site, sw)
        end

        def wait_for_reservation(opts = {})
            site = opts.fetch(:site, :any).__repr__
            timeout = opts.fetch(:timeout, Infinity)
            name = opts[:name]

            timeout = Timespan.to_secs(timeout)
            places = sites.uids
            places = places.select { |uid| uid == site } if site != 'any'
            raise "No '#{site}' site" if places.empty?
            job = nil
            Timeout.check(timeout) do
                js = places.map { |p| my_jobs(p) }.reduce(:+)
                js = js.select { |j| j['name'] == name } unless name.nil?
                job = js.first
                pass unless job.nil?
            end
            job = wait_for_job(job)
            return job
        end

        def kavlan(job)
            jid = job['uid']
            site = g5k.follow_parent(job).uid
            begin
                info = bash_frontend(site) do
                    uid = run "kavlan -V -j #{jid}"
                    list = run "kavlan -l -j #{jid}"
                    { :uid => uid.to_i, :hosts => list.lines.map { |x| x.strip } }
                end
            rescue Bash::StatusError => e
                raise e if e.output.strip != 'no vlan found'
                return nil
            end
            return info
        end


        def get_ssh_key_for_site(site)
            ssh_key = bash_frontend(site) do
                name = expand_path '~/.ssh/id_rsa.pub'
                (exists name) ? (contents name).strip : nil
            end
            return ssh_key
        end

        def deploy(job, opts = {})
            # TODO: make sure this is deployment job
            # TODO: this is deprecated

            nodes = job['assigned_nodes']
            env = opts[:env]

            site = g5k.follow_parent(job).uid

            keys = [ G5K.get_ssh_key() ]

            frontend_ssh_key = get_ssh_key_for_site(site)

            keys.push(frontend_ssh_key) unless frontend_ssh_key.nil?

            info "Deploying #{keys.length} SSH keys"

            raise "Environment must be given" if env.nil?

            payload = {
                'nodes' => nodes,
                'environment' => env,
                'key' => keys.join("\n") + "\n",
            }

            vlan = kavlan(job)

            if !vlan.nil?
                payload['vlan'] = vlan[:uid]
                info "Found VLAN with uid = #{vlan[:uid]}"
            end

            info "Creating deployment"
            # puts payload.inspect
            
            begin
                r = g5k.post_json("sites/#{site}/deployments", payload)
            rescue => e
                raise e
            end

            info "Entering waiting loop"

            Timeout.check(Infinity) do
                r = r.refresh(g5k)
                pass if r['status'] == 'terminated'
                info "Waiting for deployment to finish (state = #{r['status']})."
            end

            ok = r['result'].map { |node, info| info }.all? { |x| x['state'] == 'OK' }

            raise "Deployment (at least partially) failed" unless ok

            return r

        end

        def find_node(node)
            j, n, site = nil, nil, nil
            # 1. Try to find a site.
            info "Looking for node #{node}..."
            # info "Sites considered: #{site_uids.inspect}"
            site = site_uids.detect { |s| node.include?(s) }
            # info "Site is #{site}"
            jobs = (site.nil?) ? my_all_jobs() : my_jobs(site)
            # info "Jobs considered: #{jobs.inspect}"
            jobs = jobs.map { |x| x.refresh(g5k) }
            for job in jobs do
                n = job['assigned_nodes'].detect { |n| n.start_with?(node) }
                if n.nil? == false
                    j = job
                    site = g5k.follow_parent(job).uid if site.nil?
                    break
                end
            end
            return j, n, site
        end

        def _ssh(site, job, n, cmd)
            # connects to node 'n', on site 'site', being a part of 'job'
            cmd = Shellwords.escape(cmd)
            cmd2 = Shellwords.escape(cmd)
            bashc = "OAR_JOB_ID=#{job.uid} oarsh #{n} -- #{cmd2}"
            if inside_g5k
                if job.job_type == :deploy
                    return "ssh root@#{n} -- #{cmd}"
                else
                    # TODO: this can be simplified if we are
                    # running on 'site'
                    return "ssh -F #{SSH_CONFIG} #{site}.grid5000.fr -- #{bashc}"
                end
            else
                proxy = "ssh -F #{SSH_CONFIG} #{site}.g5k"
                if job.job_type == :deploy
                    return "#{proxy} -- ssh root@#{n} -- #{cmd2}"
                else
                    return "#{proxy} -- #{bashc}"
                end
            end
        end

        def _ssh_deploy(site, node, cmd)
            gw = _ssh_gw(site, node)
            return "#{gw} -- #{cmd}"
        end

        def _ssh_gw(site, node)
            if inside_g5k
                return "ssh root@#{node}"
            else
                proxy = "ssh -F #{SSH_CONFIG} #{site}.g5k"
                return "#{proxy} -- ssh root@#{node}"
            end
        end

        def _frontend(site, cmd)
            if inside_g5k
                ssh = "ssh -F #{SSH_CONFIG} #{site}.grid5000.fr"    
            else
                ssh = "ssh -F #{SSH_CONFIG} #{site}.g5k"
            end
            cmd = Shellwords.escape(cmd)
            return "#{ssh} -- #{cmd}"
        end

        def execute(node, cmd, prefix = '', postfix = '')
            if node.include?("kavlan")
                ssh = _ssh_deploy('nancy', node, 'bash') # TODO: how does it work?
                ssh = ssh.gsub("bash", "")  # TODO: OMG
                prog = "#{prefix}#{ssh} #{cmd} #{postfix}"
            else
                job, n, site = find_node(node)
                raise "Node '#{node}' not found" if job.nil?
                prog = "#{prefix}#{_ssh(site, job, n, cmd)}#{postfix}"
            end
            info "Running command: #{prog}"
            return `#{prog}`
        end

        def execute_frontend(site, cmd, prefix = '')
            bash_frontend(site) do
                run(cmd)
            end
        end

        def bash(node, opts = {}, &block)
            return vlan_bash(node, debug, &block) if node.include?("kavlan")
            job, n, site = find_node(node)
            raise "Node #{node} not found" if job.nil?
            ssh = _ssh(site, job, n, 'bash')
            info "Running bash via: #{ssh}"
            return Bash.bash(ssh, opts, &block)
        end

        def vlan_bash(node, opts = {}, &block)
            ssh = _ssh_deploy('nancy', node, 'bash') # TODO: how does it work?
            info "Running vlan bash via: #{ssh}"
            return Bash.bash(ssh, opts, &block)
        end

        def bash_local(&block)
            return Bash.bash(&block)
        end

        def bash_frontend(site, opts = {}, &block)
            proxy = _frontend(site, 'bash')
            info "Running bash via: #{proxy}"
            return Bash.bash(proxy, opts, &block)
        end

        def copy(filename, node, path)
            raise 'File does not exist!' unless File.exists?(filename)
            base = File.basename(filename)
            bash(node) do
                path = expand_path(path)  # get rid of ~
                if exists(path)
                    type = get_type(path)
                    if type == :dir
                        path = File.join(path, base)
                    elsif type == :file
                        # pass
                    else
                        raise 'Unknown file type.'
                    end
                else
                    # the path does not exist
                end
            end
            info "Copying file #{filename} to #{node}:#{path}"
            return execute(node, "tee #{path}", "cat #{filename} | ")  # FIX THIS
        end

        def retrieve(node, path, dir = '.')
            files = bash(node) do
                glob(path)
            end
            files.each do |f|
                base = File.basename(f)
                dest = File.join(dir, base)
                execute(node, "cat #{f}", "", " > #{dest}")
            end
        end

        def dist_keys(master, slaves)
            # generates and distributes SSH keys so that
            # master can connect password-lessly
            # if public key is already present, it won't be
            # recreated
            label = "#{master} && #{slaves}"
            if @cache.get(label)
                info "SSH keys already distributed."
                return
            end
            priv = '~/.ssh/id_rsa'
            pub = "#{priv}.pub"
            key = bash(master) do
                trunc '~/.ssh/config'
                append_line '~/.ssh/config', 'Host *'
                append_line '~/.ssh/config', 'StrictHostKeyChecking no'
                if !exists(priv)
                    run("ssh-keygen -N '' -q -f #{priv}")
                end
                run("ssh-keygen -y -f #{priv}").strip
            end
            info "The key is: #{key}"
            (slaves + [ master ]).uniq.each do |node|
                bash(node) do
                    make_dirs '~/.ssh'
                    append_line '~/.ssh/authorized_keys', key
                end
            end
            @cache.set(label, true)
            info "Keys distributed."
        end

        def dist_ssh_keys(nodes)
            master = nodes.first
            rest = nodes.tail
            dist_keys(master, rest)
            return master
        end

        def clean
            proxy.engine.inline_process :"g5k-clean" do
                sites = run :"sites"
                forall sites do |s|
                    log "Cleaning ", s
                    jobs = run :"my_jobs", s
                    log "Cleaning ", s, " from ", (length_of jobs), " jobs..."
                    run :"release_all", s
                    log "Done with #{name_of s}"
                end
            end
            return true
        end

        def run_script(node, name)
            # TODO
            tmp = '/tmp/script-xpflow.sh'
            info "Pushing script #{name} to the node #{node}"
            copy($files[name], node, tmp) # TODO
            return execute(node, "bash -e #{tmp}")
        end

        def rsync(node, name, where)
            info "Pushing '#{name}' to the node #{node}"
            rsh = _ssh_gw('sophia', node) # TODO: how does it work?
            dir = $dirs[name]
            cmd = "rsync --delete --numeric-ids --archive --bwlimit=100000 --rsh '#{rsh}' #{dir} :#{where}"
            info "Running: #{cmd}"
            return `#{cmd}`
        end

    end

end; end
