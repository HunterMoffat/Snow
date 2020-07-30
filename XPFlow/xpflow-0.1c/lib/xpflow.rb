
require 'thread'
require 'digest'
require 'etc'
require 'open3'
require 'yaml'
require 'optparse'
require 'monitor'
require 'colorado'
require 'pathname'
require 'highline'

def __get_my_requires__
    me = File.dirname(__FILE__)
    files = Dir.entries(File.join(me, 'xpflow'))
    files = files.select { |f| File.extname(f) == '.rb' }
    files = files.select { |f| !f.start_with?('with') }
    modules = files.map { |f| File.basename(f, File.extname(f)) }
    return modules
end

# some Ruby version trickery

_, $version = RUBY_VERSION.split('.')
$version = $version.to_i
$ruby18 = ($version == 8)
$ruby19 = ($version == 9)

class Symbol

    def <=>(x)
        return (self.to_s <=> x.to_s)
    end

end if $ruby18

if $bundled.nil?
    # necessary includes
    require('xpflow/utils')
    require('xpflow/structs')
    require('xpflow/library')
    require('xpflow/scope')

    for m in __get_my_requires__ do
        require('xpflow/' + m)
    end
end

Engine = $engine = XPFlow::Engine.new

def engine(&block)
    $engine.instance_exec(&block)
end

def process(*args, &block)
    engine { process(*args, &block) }
end

def activity(*args, &block)
    engine { activity(*args, &block) }
end

def macro(*args, &block)
    engine { macro(*args, &block) }
end

def dsl(name, *args, &block)
    return XPFlow::ProcessDSL.new(name, $engine, &block)
end

def empty_activity(*args)
    args.each do |name|
        activity(name) do
        end
    end
end

def script(name, path)
    # TODO: put more magic
    process(name) do |nodes|
        execute_many(nodes, path)
    end
    single = "#{name}_seq".to_sym
    process(single) do |node|
        execute(node, path)
    end
end

def activity_visibility(name)
    return true
end

def __parse_variables__()
    opts = XPFlow::Options.new(ARGV.dup)
    $variables = opts.vars
end

def parse_g5k_query(query, opts = { :max => 1 })
    lib = XPFlow::G5K::Library.new
    lib.logging = proc { |x| puts x }
    sites = lib.sites.map { |x| x['uid'] }
    best_sites = [ "nancy", "rennes", "sophia" ]
    sites = best_sites + (sites - best_sites)

    max = opts[:max]

    uniq_jobs = proc { |js| Hash[js.map { |j| [ [j['uid'], j['site']], j ] }].values }
    jobs_at_site = proc do |site|
        js = lib.jobs(site)
        js = js.select { |x| x['state'] == 'running' }
        js.select { |x| x['user_uid'] == lib.g5k.user }
    end
    site_from_job = proc { |j| j['links'].select { |l| l['rel'] == 'parent' }.first['href'].split("/").last }

    jobs = []

    query.split(":").each do |word|
        if word == '*'
            sites.each do |s|
                jobs = uniq_jobs.call(jobs + jobs_at_site.call(s))
                break if jobs.length >= max
            end
            break if jobs.length >= max
        elsif (m = word.match(/^([a-z]+)\/(.+)/)) and (sites.include?(m.captures.first))
            query_site, query_str = m.captures
            site_jobs = jobs_at_site.call(query_site)
            if query_str == '*'
                jobs = uniq_jobs.call(jobs + site_jobs)
                break if jobs.length >= max
            elsif query_str.match(/^[0-9]+$/)
                job_uid = query_str.to_i
                site_job = site_jobs.select { |x| x['uid'] == job_uid }
                if site_job.length == 0
                    raise "No job with id = #{job_uid} in '#{query_site}'."
                end
                jobs = uniq_jobs.call(jobs + [ site_job.first ])
                break if jobs.length >= max
            else
                raise "Cannot parse '#{query_str}'"
            end
        else
            raise "Cannot parse '#{word}'"
        end
    end

    grouped_jobs = Hash.new { |h, k| h[k] = [] }
    jobs.each { |j| grouped_jobs[site_from_job.call(j)].push(j) }
    jobs_info = grouped_jobs.each_pair.map { |site, jobs| "{" + jobs.map { |x| x['uid'] }.join(",") + "}@#{site}" }.join(" ")

    puts "Found #{jobs.length} jobs: #{jobs_info} (but :max is #{max})"

    jobs = jobs[0...max]
    return jobs
end

def parse_g5k_query_one_wait(query)
    lib = XPFlow::G5K::Library.new
    lib.logging = proc { |x| puts x }
    jobs = parse_g5k_query(query, :max => 1)
    if jobs.length == 0
        raise "Could not find any jobs."
    end
    job = jobs.first
    j = lib.g5k.get_json_raw(job.rel_self)
    j = lib.wait_for_job(j)
    return j
end

def _bool_var(v)
    return v if v.is_a?(TrueClass) or v.is_a?(FalseClass)
    v = v.strip
    if (v.to_i == 1) or ([ "true", "yes" ].include?(v.downcase))
        return true
    end
    return false
end

class Seq

    def initialize(arr)
        @arr = arr
    end

    def range
        return Seq.new(@arr.uniq.sort)
    end

    def self.parse(spec)
        nums = []
        parts = spec.strip.split("+").map(&:strip)
        parts.each do |p|
            if p.match(/^(\d+)$/)
                nums += [ p.to_i ]
            elsif (m = p.match(/^(\d+)(:|-|\.\.)(\d+)$/))
                s, _, e = m.captures.map(&:to_i)
                nums += (s..e).to_a
            elsif (m = p.match(/^(\d+)(:|-|\.\.)(\d+)\/(\d+)$/))
                s, _, e, div = m.captures.map(&:to_i)
                raise "Dividing by zero here" if div == 0
                raise "Division must be > 1" if div == 1
                if (e - s) % (div - 1) == 0
                    d = (e - s) / (div - 1)  # use integer arithmetic if possible
                else
                    d = (e - s).to_f / (div - 1).to_f
                end
                pts = []
                (1..(div - 2)).each do |i|
                    p = i * d + s
                    pts.push(p.to_i)
                end
                nums += ([ s ] + pts + [ e ])
            elsif (m = p.match(/^(\d+):(\d+):(\d+)$/))
                s, d, e = m.captures.map(&:to_i)
                if d == 0
                    raise "Zero range increment (#{p})"
                end
                while s <= e
                    nums.push(s)
                    s += d
                end
            else
                raise "Wrong range specification"
            end
        end
        return Seq.new(nums)
    end

    def to_s
        return "seq(#{@arr.inspect})"
    end

    def to_list
        return @arr.dup
    end

    def max
        return @arr.max
    end

end

$__highline__ = HighLine.new

def ask_for_type(name, type, opts)
    text = "Provide value of :#{name} (type :#{type}): "
    text = opts[:text] if opts[:text]
    if [ :seq, :str, :range, :pass ].include?(type)
        value = $__highline__.ask(text) do |q|
            q.echo = "*" if type == :pass
        end
        return value
    elsif type == :int
        value = $__highline__.ask(text, Integer)
        return value
    elsif type == :bool
        value = $__highline__.agree(text) { |q| q.default = "no" }
        return value
    else
        # TODO, support more variables
        raise "Unknown value for variable :#{name} (type :#{type})"
    end
end

def var(name, type = :str, default = nil, opts = {})
    # TODO
    if default.is_a?(Hash)
        opts = default
        default = opts[:default]
    end
    v = $variables[name.to_s]
    if v.nil?
        if default.nil?
            # try to ask for a variable
            if !STDIN.tty?
                raise "Unknown value for variable :#{name} (type :#{type})"
            end
            v = $variables[name.to_s] = ask_for_type(name, type, opts)
            if opts[:callback]
                opts[:callback].call(v)
            end
        else
            return default
        end
    end

    result = case type
        when :str then v
        when :int then v.to_i
        when :float then v.to_f
        when :bool then _bool_var(v)
        when :range then Seq.parse(v).range
        when :seq then Seq.parse(v)
        when :pass then v
        when :g5k then parse_g5k_query_one_wait(v)
        else
            raise "Unknown type '#{type}'"
    end
    return result
end

def set_var(name, value)
    $variables[name.to_s] = value
    return value
end

def experiment(name, &block)
    body_name = :"#{name}/body"
    before_name = :"#{name}/before"
    after_name = :"#{name}/after"
    $engine.process(body_name, &block)
    $engine.process(before_name) { }
    $engine.process(after_name) { }
    $engine.process(name) do |*args|
        run :"/new_experiment"  # create a new experiment
        log "Starting experiment '#{name}'"
        run(before_name, *args)
        result = run(body_name, *args)
        run(after_name, *args)
        log "Finished experiment '#{name}'"
        value(result)
    end
end

def after_activity(name, &block)
    # we replace the given activity with
    # a one that executes the previous one and then
    # the one given

    after_block = block
    activity(name) do |*args|
        value = parent(*args)
        self.set_result(value)
        value = self.instance_exec(*args, &after_block)
        value
    end
end

def before_activity(name, &block)
    # similarly to after_activity
    before_block = block
    activity(name) do |*args|
        self.instance_exec(*args, &before_block)
        parent(*args)
    end
end

def realize(path)
    return Pathname.new(path).realpath.to_s
end
