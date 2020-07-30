
# This simple library allows you to use
# colors with strings

module Colorado

    COLORS = {
        :red => 31,
        :green => 32,
        :yellow => 33,
        :blue => 34,
        :violet => 35,
        :magenta => 36,
        :white => 37,
        :normal => 0
    }

    KEYS = COLORS.keys + COLORS.keys.map { |c| "#{c}!" }

    module StringMix
        
        Colorado::KEYS.each do |color|
            define_method(color) do
                return Colorado::Str.new(self, color)
            end
        end

    end

    module BaseMix
        
        Colorado::KEYS.each do |color|
            define_method(color) do
                return self.plain.send(:color)
            end
        end

    end

    class Color

        attr_reader :bold
        attr_reader :color

        def initialize(c)
            @color = (c.is_a?(Color) ? c.color : c)
            @bold = @color.to_s.end_with?('!')
            @index = @color.to_s.chomp('!').to_sym
        end

        def code
            return COLORS[@index]
        end

        def prefix
            return '' if @index == :normal
            return (@bold ? "\e[#{code};1m" : "\e[#{code}m")
        end

        def suffix
            return '' if @index == :normal
            return "\e[0m"
        end

        def to_s
            return @color.to_s
        end

        def normal?
            return @index == :normal
        end

    end

    class Base

        include BaseMix

        attr_reader :color

        def initialize(color)
            @color = Color.new(color)
        end

        def +(s)
            s = Str.new(s) if s.is_a?(String)
            return Group.new(self.parts + s.parts)    
        end

    end

    class Str < Base

        def initialize(s, color = :normal)
            super(color)
            raise "Already colorized: #{s}" if Colorado.colorized(s)
            @s = s.to_s
        end

        def inspect
            "<'#{@s}' in #{@color}>"
        end

        def plain
            return @s
        end

        def parts
            return [ self ]
        end

        def to_s
            return "#{color.prefix}#{@s}#{color.suffix}"
        end
    end

    class Group < Base

        def initialize(array)
            super(:normal)
            @array = array
        end

        def exec(method)
            return @array.map { |it| it.send(method) }
        end

        def parts
            return exec(:parts).reduce(:+)
        end

        def plain
            return exec(:plain).reduce(:+)
        end

        def inspect
            return parts.inspect
        end

        def to_s
            return exec(:to_s).reduce(:+)
        end

    end

    def self.substitute(fmt, array)
        parts = fmt.split(/%(.)/)
        strings = []
        idx = 0
        parts.each_index do |i| 
            s = parts[i]
            if i.even? # normal string
                next if s == ''
                strings.push(Str.new(s))
            else
                if s == 's'
                    strings.push(fix(array[idx]))
                    idx += 1
                elsif s == '%'
                    strings.push(fix('%'))
                else
                    raise "Error!"
                end
            end
        end
        return Group.new(strings)
    end

    def self.fix(x)
        return x if x.is_a?(Base)
        return Str.new(x.to_s)
    end

    def self.colorized(s)
        return (!s.is_a?(Base) && s.to_s.include?("\e"))
    end

end

class String

    include Colorado::StringMix

    alias old_addition :+
    alias old_modulo :%

    def +(x)
        return Colorado::Str.new(self) + x if x.is_a?(Colorado::Base)
        return old_addition(x)
    end

    def %(x)
        return Colorado.substitute(self, [x]) if x.is_a?(Colorado::Base)
        return Colorado.substitute(self, x) if (x.is_a?(Array) && x.any? { |el| el.is_a?(Colorado::Base) } )
        return old_modulo(x)
    end

end
