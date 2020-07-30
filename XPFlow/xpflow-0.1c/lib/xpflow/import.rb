
module XPFlow

    class GitRepo

        def initialize(address)
            @address = address
        end

        def versions
            version_exp = Regexp.new("refs/tags/xpflow/(.+)")
            cmd = "git ls-remote --tags #{@address}"
            # puts cmd
            tags = %x(#{cmd})
            tags = tags.strip.lines.map(&:split)
            vs = {}
            tags.each do |hash, tag|
                m = version_exp.match(tag)
                if !m.nil?
                    vs[m.captures.first] = hash
                end
            end
            return vs
        end

        def comparable_versions
            vs = versions()
            h = [ ]
            vs.each_pair do |version, hash|
                v = Repo.parse_version(version, hash)
                h.push(v) unless v.nil?
            end
            return h.sort { |x, y| y <=> x } # from the newest downwards
        end

        def filter_versions(&block)
            vs = comparable_versions()
            return vs.select(&block)
        end

        def get_latest
            return comparable_versions().max
        end

        def get_version(v)
            v = Version.flatten(v)
            v = v.to_dots if v.is_a?(Version)
            vs = versions()
            raise "No version #{v}" unless vs.key?(v)
            return AnyVersion.new(vs[v], v)
        end

        def get_less_than(v)
            v = Version.flatten(v)
            r = filter_versions { |x| (x <=> v) < 0 }
            raise "No version < #{v}" if r.length == 0
            return r.max
        end

        def get_less_equal(v)
            v = Version.flatten(v)
            r = filter_versions { |x| (x <=> v) <= 0 }
            raise "No version <= #{v}" if r.length == 0
            return r.max
        end

        def checkout_version(v)
            hash = v.hash
            tmpdir = %x(mktemp -d).strip
            Kernel.system("git clone #{@address} #{tmpdir}")
            Kernel.system("cd #{tmpdir} && git checkout #{hash} -b __xpflow__")
            
        end

    end

    class Modules

        # contains information about installed modules

        def initialize(directory)
            @directory = directory
            @versions = load_versions()
        end

        def load_versions
            dirs = Dir.entries(@directory) - [ ".", ".." ]
            
        end

    end

    class Version

        attr_reader :major
        attr_reader :minor
        attr_reader :manor

        def initialize(major, manor = 0, minor = 0)
            @major = major
            @manor = manor
            @minor = minor
        end

        def self.flatten(x)
            return x if x.is_a?(Version)
            parts = x.split(".").map(&:to_i)
            if (parts.length == 0 or parts.length > 3)
                raise "Wrong version '#{x}'"
            end
            return Version.new(*parts)
        end

        def middle
            return @manor
        end
        
        def <=>(x)
            return (self.major <=> x.major) if self.major != x.major
            return (self.manor <=> x.manor) if self.manor != x.manor
            return (self.minor <=> x.minor)
        end

        def to_dots
            return "#{@major}.#{@manor}.#{@minor}"
        end

        def to_s
            return "{Version #{to_dots}}"
        end
    
    end

    class AnyVersion

        attr_reader :hash
        attr_reader :name

        def initialize(hash, name)
            @hash = hash
            @name = name
        end

        def to_s
            return "{Version #{@name} #{@hash}}"
        end

    end

    class RepoVersion < Version

        attr_reader :hash

        def initialize(hash, major, manor = 0, minor = 0)
            super(major, manor, minor)
            @hash = hash
        end

        def to_s
            return "{Version #{to_dots} #{@hash}}"
        end

    end

    class Repo

        def self.parse_version(version, hash)
            exp = Regexp.new('^(\d+|\d+\.\d+|\d+\.\d+\.\d+)$')
            m = exp.match(version)
            return nil if m.nil?
            parts = version.split(".").map(&:to_i)
            return RepoVersion.new(hash, *parts)
        end

        def self.create(url)
            scheme, address = url.split("://", 2)
            repo = case scheme
                when 'github' then GitRepo.new("https://github.com/#{address}")
                when 'local' then GitRepo.new("file://#{address}")
                else
                    raise "Unknown scheme: #{scheme}"
            end
            return repo
        end

    end

    if __FILE__ == $0
        m = Modules.new("./modules")

        repo = Repo.create("local:///home/toma/projects/sandbox/xpflow-test")
        latest = repo.get_latest
        # repo.checkout_version(latest)
    end

end
