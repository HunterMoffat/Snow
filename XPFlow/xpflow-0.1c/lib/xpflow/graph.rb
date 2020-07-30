
begin
    require('cairo')  # this is to hide it from bundle.rb
    $check_cairo = proc {}
rescue LoadError
    $check_cairo = proc { raise "Please install cairo for Ruby." }
end

module Graphing

    class LatexGrapher

        def initialize(flow, opts = {})
            @flow = flow
            @opts = opts
            @indent = 0
            @text = [ "% flow-latex workflow" ]
        end

        def self.indent_arrays(array)
            lines = []
            array.each do |x|
                if x.is_a?(String)
                    lines.push(x)
                elsif x.is_a?(Array)
                    x = indent_arrays(x)
                    arr = x.map { |it| "  " + it }
                    lines += arr
                elsif x.nil?
                    # nop
                else
                    raise "What is #{x.class}?"
                end
            end
            return lines
        end

        def draw()
            lines = @flow.latex()
            lines = LatexGrapher.indent_arrays(lines)
            # puts lines
            return lines.join("\n")
        end



    end

    class TikzGrapher

        attr_reader :nodes
        attr_reader :coords
        attr_reader :boxes
        # and also paths

        def initialize(flow, opts = {})
            @flow = flow
            @nodes = {}
            @coords = {}
            @links = Hash.new { |h, k| h[k] = [] }
            @lines = []
            @styles = {}
            @boxes = []
            @joins = []
            @count = 0
            @opts = opts
            @matrix = [ Size.new(0, 0) ]
        end

        def name
            "tikz"
        end

        def transform(p)
            # transform a given point
            return p + @matrix.last
        end

        def tr(p)
            return transform(p)
        end

        def push_origin(x, y)
            # pushes transformation stack and puts origin in p
            p = transform(Size.new(x, y))
            begin
                @matrix.push(p)
                yield
            ensure
                @matrix.pop
            end
        end


        def option(x)
            return @opts[x] == true
        end

        def final?(label)
            raise if not @nodes.key?(label) and not @coords.key?(label)
            return @nodes.key?(label)
        end

        def check_links
            @links.each do |s, ends|
                raise if !final?(s) and ends.length > 1
            end
        end

        def get_position(label)
            return @coords[label] if @coords.key?(label)
            return @nodes[label][:pos] if @nodes.key?(label)
            raise "Unknown label '#{label}'"
        end

        def get_path(l1, l2)
            # gets path l1 -> l2 -> ... -> (final node)
            path = [ l1, l2 ]
            while !final?(path.last) do
                succ = @links[path.last]
                raise if succ.length > 1
                path.push(succ.first)
                raise if path.length > 1000 # in case there is a bug ...
            end
            # TODO: remove repetitions on the path?
            return path
        end

        def paths
            check_links()  # check if links are ok
            list = []
            @links.each do |s, ends|
                ends.each do |e|
                    path = get_path(s, e)
                    list.push(path)
                end if final?(s)
            end
            return list
        end

        def text_measurer
            # by default we don't have it
            return nil
        end

        def draw(box = nil)
            Thread.current[:text_measure] = text_measurer() # TODO: ugly hack!
            box = @flow.size if box.nil?
            @flow.tikz(self, Size.ZERO, box)

            els = {
                :nodes => @nodes,
                :paths => paths,
                :coords => @coords,
                :boxes => @boxes,
                :positions => {},
                :lines => @lines,
                :joins => @joins
            }

            els[:nodes].each { |label, n| els[:positions][label] = n[:pos] }
            els[:coords].each { |label, pos| els[:positions][label] = pos }

            return draw_elements(els, box)
        end

        def draw_elements(els, box)
            
            lines = []
            lines += [ "", "% Special curves", "" ]

            lines += [ "", "% Boxes", "" ]
            els[:boxes].each do |b|
                pos, box, opts = b[:pos], b[:box], b[:opts]
                style = "dashed"
                if opts[:style]
                    style = "#{style},#{opts[:style]}"
                end
                lines.push("\\draw[#{style}] #{pos} rectangle #{pos + box};")
            end

            lines += [ "", "% Intermediate nodes", "" ]
            els[:coords].each do |label, pos|
                lines.push("\\coordinate (#{label}) at #{pos};")
            end

            els[:lines].each do |l|
                coords, opts =  l
                type = opts[:type]
                if type == :bezier 
                    raise "Wrong number of points (should be = 1 mod 3)" if coords.length % 3 != 1
                    # strictly speaking tikz has no beziers, but it will suffice
                    lines.push("\\draw[dashed,gray] #{coords.first}  % total #{coords.length} points")
                    (coords.length / 3).times do |i|
                        a, b, c = coords[(i*3 + 1)...(i*3 + 4)]
                        lines.push("    .. controls #{a} and #{b} .. #{c}")
                    end
                    lines[-1] = lines[-1] + ";"
                elsif type == :solid
                    path = coords.map(&:to_s).join(" -- ")
                    lines.push("\\draw[solid,#{opts[:style]}] #{path};")
                else
                    raise "Unsupported curve of type '#{type}'"
                end
            end

            lines += [ "% Final nodes", "" ]
            els[:nodes].each do |label, n|
                style, pos, name = n[:style], n[:pos], n[:name]
                anchor = n[:anchor]
                # TODO: support anchor
                # puts n.inspect
                name = name.gsub('_', '\_')

                style = "" if style == "text"
                lines.push("\\node[#{style},fill=white] (#{label}) at #{pos} {#{name}};")
            end

            lines += [ "", "% Links between final nodes", "" ]
            els[:paths].each do |p|
                p = p.map { |x| "(#{x})" }.join(" to ")
                lines.push("\\draw[sequence] #{p};")
            end
            
            lines += [ "", "% Joins", "" ]
            els[:joins].each do |pts, type|
                s = pts.map { |x| "(#{x})" }.join(" to ")
                style = case type
                    when :plain
                        ""
                    when :arrow
                        "->"
                    when :arrow_dashed
                        "dashed,->"
                    else
                        raise "Unknown type '#{type}'"
                end
                lines.push("\\draw[#{style}] #{s};")
            end

            lines.push("")
            return lines.join("\n")
        end

        def get_label
            @count += 1
            return "node-#{@count}"
        end

        def add_task(name, pos, style = 'task', anchor = nil, size = nil, label = nil)
            label = get_label() if label.nil?
            @nodes[label] = { :name => name, :pos => tr(pos), :style => style,
                :anchor => anchor, :size => size }
            return label
        end

        def add_text(name, pos, anchor = "cm", size = 1.0)
            return add_task(name, pos, 'text', anchor, size)
        end

        def add_gateway(pos, text); add_task(text, pos, 'gateway'); end
        def add_start(pos); add_task('', pos, 'start'); end
        def add_finish(pos); add_task('', pos, 'finish'); end

        def add_coord(pos)
            label = get_label()
            @coords[label] = tr(pos)
            return label
        end

        def add_box(pos, box, force = false, opts = {})
            @boxes.push({ :pos => tr(pos), :box => box, :opts => opts }) \
                if force or option(:boxes) or option(:debug)
        end

        def add_link(*labels)
            (1...labels.length).each do |i|
                @links[labels[i - 1]].push(labels[i])
            end
        end

        def add_join(points, type = :plain)
            points = points.map do |p|
                p = self.add_coord(p) if p.is_a?(Size)
                p
            end
            @joins.push([ points, type ])
        end

        def add_line(path, opts = { :style => :solid })
            @lines.push([ path, opts ])
        end

        def label_pos(name)
            return @nodes[name][:pos]
        end

    end

    class CairoGrapher < TikzGrapher

        WHITE = [ 1, 1, 1 ]
        BLACK = [ 0, 0, 0 ]
        LGRAY = [ 0.8, 0.8, 0.8 ]
        RED = [ 1, 0, 0]

        def initialize(flow, writer, opts = {})
            super(flow, opts)
            @writer = writer
            @ctx = writer.context
            @dims = writer.size
            @font_size = 0.35
        end

        def name
            "cairo"
        end

        # rescales Cairo canvas so that it fits the workflow nicely

        def rescale(box)
            cw, ch = @dims.map(&:to_f)
            factor = [ cw / box.width, ch / box.height ].min
            w, h = factor * box.width, factor * box.height
            @ctx.translate( (cw - w) / 2.0, (ch - h) / 2.0)
            @ctx.scale(factor, factor)
            # TODO
        end

        def background
            set_white
            @ctx.rectangle(0, 0, *@dims)
            @ctx.fill
        end

        def bbox(box)
            @ctx.set_line_width(0.005)
            @ctx.set_dash(0.04)
            set_black
            @ctx.rectangle(0, 0, box.width, box.height)
            @ctx.stroke
        end

        def set_black
            @ctx.set_source_rgb(*BLACK)
        end

        def set_white
            @ctx.set_source_rgb(*WHITE)
        end

        def fill_and_stroke(fill = WHITE, stroke = BLACK)
            unless fill.nil?
                @ctx.set_source_rgb(*fill)
                @ctx.fill_preserve
            end
            @ctx.set_source_rgb(*stroke)
            @ctx.stroke
        end

        def find_pos(pos, extents, anchor)
            # finds a position according to the extents and anchor

            x_shifts = {
                'l' => 0.0 - extents.x_bearing,
                'c' => -extents.width * 0.5 - extents.x_bearing ,
                'r' => -extents.width - extents.x_bearing
            }

            y_shifts = {
                't' => -extents.y_bearing,
                'm' => -extents.y_bearing - extents.height * 0.5,
                'b' => -extents.y_bearing - extents.height,
                'v' => 0.0
            }

            dy = y_shifts.select { |k, v| anchor.include?(k) }
            dy = dy.empty? ? y_shifts['m'] : dy.values.first

            dx = x_shifts.select { |k, v| anchor.include?(k) }
            dx = dx.empty? ? x_shifts['c'] : dx.values.first

            return pos.at(dx, dy)
        end

        def show_text(text, p)
            if option(:debug)  # draw bearing and all that typographic stuff
                @ctx.save
                @ctx.set_dash(0.03)
                @ctx.move_to(*p.coords)
                e = @ctx.text_extents(text)
                @ctx.rel_line_to(0, e.y_bearing)
                @ctx.rel_line_to(+e.x_bearing + e.width, 0)
                @ctx.rel_line_to(0, e.height)
                @ctx.rel_line_to(-e.x_bearing - e.width, 0)
                @ctx.close_path
                fill_and_stroke(nil, BLACK)

                @ctx.set_dash(nil)
                @ctx.move_to(*p.coords)
                @ctx.rel_line_to(e.x_bearing + e.width, 0)
                @ctx.move_to(*p.coords)
                @ctx.rel_move_to(e.x_bearing, e.y_bearing)
                @ctx.rel_line_to(0, e.height)
                fill_and_stroke(nil, RED)
                
                @ctx.restore
            end
            set_black
            @ctx.move_to(*p.coords)
            @ctx.show_text(text)
            @ctx.stroke
        end

        def approximate_size(text, size)
            if size.is_a?(Size)
                @ctx.set_font_size(@font_size)
                extents = @ctx.text_extents(text)
                sx = size.width / extents.width
                sy = size.height / extents.height
                return [ sx, sy ].min
            else
                size = -size
                @ctx.set_font_size(@font_size)
                extents = @ctx.text_extents(text)
                return size / extents.height
            end
        end

        def text_measurer
            return proc { |text|
                @ctx.save
                @ctx.set_font_size(@font_size)
                ex = @ctx.text_extents(text)
                @ctx.restore
                ex
            }
        end

        def draw_elements(els, box)

            background()
            rescale(box)
            # bbox(box)

            @ctx.select_font_face("Droid Serif",
                Cairo::FONT_SLANT_NORMAL, Cairo::FONT_WEIGHT_NORMAL)
            
            pos = els[:positions]

            set_black
            @ctx.set_line_width(0.01)
            @ctx.set_dash(nil)

            els[:paths].each do |path|
                raise if path.length < 2
                @ctx.move_to(*pos[path.first].coords)
                path[1..-1].each do |n|
                    @ctx.line_to(*pos[n].coords)
                end
                @ctx.stroke
            end

            @ctx.set_dash(0.03)
            els[:boxes].each do |b|
                pos, box = b[:pos], b[:box]
                rect = pos.coords + box.coords
                @ctx.rectangle(*rect)
                @ctx.stroke
            end

            els[:lines].each do |path, style|
                if style == :bezier or style == { :type => :bezier }
                    raise "Bezier curve must have >= 4 and % 3 == 1 points!" \
                        if path.length < 4 or path.length % 3 != 1

                    if option(:debug)
                        @ctx.save
                        (path.length / 3).times do |i|
                            [ 3*i + 1, 3*i + 2 ].each do |j|
                                r = 0.05
                                params = path[j].coords + [ r, 0, 6.28 ]
                                @ctx.set_dash(nil)
                                @ctx.arc(*params)
                                fill_and_stroke(RED, RED)
                            end
                            @ctx.set_dash(0.03)
                            @ctx.move_to(*path[3*i + 1].coords)
                            @ctx.line_to(*path[3*i + 2].coords)
                            fill_and_stroke(nil, RED)
                        end
                        @ctx.restore
                    end

                    path = path.dup
                    first = path.shift
                    @ctx.move_to(*first.coords)
                    while path.length > 0
                        
                        
                        args = path[0].coords + path[1].coords + path[2].coords
                        @ctx.curve_to(*args)
                        path.shift(3)
                    end
                    @ctx.stroke
                else
                    raise "Unknown style of a line (#{style})!"
                end
            end

            @ctx.set_dash(nil)
            els[:nodes].each do |label, n|
                @ctx.set_font_size(@font_size)
                @ctx.set_source_rgb(*BLACK)
                @ctx.save
                style = n[:style]
                position = n[:pos]
                name = n[:name]
                anchor = n[:anchor].to_s
                size = n[:size]
                anchor = "cm" if anchor.nil? # center, middle
                size = 1.0 if size.nil?
                # anchor can contain: l, r, t, b, c, m
                if style == "start" or style == "finish"
                    x, y = position.coords
                    @ctx.set_line_width(style == "start" ? 0.02 : 0.04)
                    @ctx.arc(x, y, 0.2, 0, 2 * Math::PI)
                    fill_and_stroke
                elsif style == "task"
                    extents = @ctx.text_extents(name)
                    bw, bh = extents.width + 0.2, extents.height + 0.2
                    x, y = position.width - bw / 2.0, position.height - bh / 2.0
                    @ctx.rectangle(x, y, bw, bh)
                    fill_and_stroke
                    if option(:debug) # showing middle points of tasks
                        @ctx.move_to(x + bw * 0.5, y)
                        @ctx.rel_line_to(0, bh)
                        @ctx.move_to(x, y + bh * 0.5)
                        @ctx.rel_line_to(bw, 0)
                        fill_and_stroke(WHITE, [ 0.7, 0.7, 0.7 ])
                    end
                    fill_and_stroke
                    p = find_pos(position, extents, "cm")
                    show_text(name, p)
                elsif style == "text"
                    size = approximate_size(name, size) if size.is_a?(Size ) or size < 0.0
                    @ctx.set_font_size(@font_size * size)  # set font size here
                    p = find_pos(position, @ctx.text_extents(name), anchor)
                    show_text(name, p)
                elsif style == "gateway"
                    x, y = position.coords
                    @ctx.move_to(x, y)
                    @ctx.rel_move_to(-0.2, 0)
                    @ctx.rel_line_to(+0.2, +0.2)
                    @ctx.rel_line_to(+0.2, -0.2)
                    @ctx.rel_line_to(-0.2, -0.2)
                    @ctx.close_path
                    fill_and_stroke
                    p = find_pos(position, @ctx.text_extents(name), "cm")
                    show_text(name, p)
                else
                    raise "Unknown style #{style}!"
                end
                @ctx.restore
            end

            @writer.finish
        end

    end

    class PNGWriter

        attr_reader :size
        attr_reader :context

        def initialize(filename, size = [ 800, 600 ])
            $check_cairo.call
            @filename = filename
            @size = size.map(&:to_f)
            @surface = Cairo::ImageSurface.new(Cairo::FORMAT_ARGB32, *@size)
            @context = Cairo::Context.new(@surface)
        end

        def finish
            @surface.write_to_png(@filename)
        end

    end

    class PDFWriter

        attr_reader :size
        attr_reader :context

        def initialize(filename, size = [ 800, 600 ])
            $check_cairo.call
            @filename = filename
            @size = size
            @surface = Cairo::PDFSurface.new(filename, *@size)
            @context = Cairo::Context.new(@surface)
        end

        def finish
            @context.show_page
        end

    end

    def self.to_pdf(process, filename, opts = {})
        writer = Graphing::PDFWriter.new(filename)
        Graphing::CairoGrapher.new(process, writer, opts).draw()
    end

    def self.to_png(process, filename, opts = {})
        writer = Graphing::PNGWriter.new(filename)
        Graphing::CairoGrapher.new(process, writer, opts).draw()
    end

    def self.to_tikz(process, filename, opts = {})
        File.open(filename, "w") do |f|
            f.write(to_text(process, opts))
        end
    end

    def self.to_latex(process, filename, opts = {})
        File.open(filename, "w") do |f|
            f.write(to_tex(process, opts))
        end
    end

    def self.to_text(process, opts = {})
        return Graphing::TikzGrapher.new(process, opts).draw()
    end

    def self.to_tex(process, opts = {})
        process = process.simplify
        return Graphing::LatexGrapher.new(process, opts).draw()
    end

    def self.to_file(process, filename, format)
        m = "to_#{format}".downcase.to_sym
        raise "Format #{format} unsupported." unless self.respond_to?(m)
        return self.__send__(m, process, filename)
    end




    class Size

        attr_reader :width
        attr_reader :height

        def initialize(w, h)
            @width = w
            @height = h
        end

        def self.flatten(*args)
            if args.length == 1
                el = args.first
                return el if el.is_a?(Size)
                return Size.new(*el)
            elsif args.length == 2
                return Size.new(*args)
            else
                raise "What is #{args}?"
            end
        end

        def to_s
            return "(%.6f, %.6f)" % [@width, @height]
        end

        def self.ZERO
            return Size.new(0, 0)
        end

        def +(o)
            o = Size.flatten(o)
            return Size.new(@width + o.width, @height + o.height)
        end

        def -(o)
            o = Size.flatten(o)
            return self + [ -o.width, -o.height ]
        end

        def *(x)
            return Size.new(@width * x, @height * x)
        end

        def /(x)
            x = x.to_f
            return Size.new(@width / x, @height / x)
        end

        def at(*args)
            return self + args.first if args.length == 1
            return self + args
        end

        def xproj(y = 0)
            # project width
            return Size.new(@width, y)
        end

        def yproj
            return Size.new(0, height)
        end

        def coords
            return [ @width, @height ]
        end

        def shrink(scalex, scaley = nil)
            scaley = scalex if scaley.nil?
            x = Size.new(@width * scalex, @height * scaley)
            offset = (self - x) / 2
            return [ offset, x ]
        end

        def center
            return self * 0.5
        end

        def vh_path(endpoint, height = nil)
            # creates a path |-| from self to endpoint, returns all 4 points
            height = (self.height + endpoint.height) * 0.5 if height.nil?
            return [ self, self.xproj(height), endpoint.xproj(height), endpoint ]
        end

        def x; @width end
        def y; @height end
    end

    class Flow

        def initialize(opts)
            @opts = standard_opts().merge(default_opts().merge(opts))
        end

        def size
            raise 'Error'
        end

        def simplify
            return self
        end

        def default_opts
            return { }
        end

        def standard_opts
            return { 'box' => { :value => false } }
        end

        def option(name, &block)
            x = @opts[name.to_s][:value]
            x = block.call(x) if block_given?
            return x
        end

        def has_box?
            return option(:box, &:to_s) == "true"
        end

        def draw_common(state, pos, box)
            state.add_box(pos, box, true) if has_box?
        end

        def tikz(state, pos, box)
            draw_common(state, pos, box)
        end

    end

    class Block < Flow

        def initialize(name, opts = {})
            super({ :flow => :right }.merge(opts))
            @name = name
        end

        def size
            measurer = Thread.current[:text_measure]
            if measurer.nil?
                chars = @name.to_s.split("\\\\").map(&:length).max
                w = 1 + (chars - 1) * 0.18
                return Size.new(w, 1)
            else
                # we have measurer helper here
                extents = measurer.call(@name)
                return Size.new(extents.width, 1)
            end
        end

        def tikz(state, pos, box, label = nil)
            super(state, pos, box)
            width2 = box.width * 0.5
            height2 = box.height * 0.5
            first = state.add_coord(pos + [ 0.0, height2 ])
            last = state.add_coord(pos + [ box.width, height2 ])
            node = state.add_task(@name, pos + [ width2, height2 ], 'task', nil, nil, label)
            if @opts[:flow] == :left
                state.add_link(last, node)
                state.add_link(node, first)
                return [ last, first ]
            else
                state.add_link(first, node)
                state.add_link(node, last)
                return [ first, last ]    
            end
        end

        def latex()
            opts = { :text => @name }.merge(@opts)
            return nil if opts[:hide]
            return [ "\\task {#{opts[:text]}}" ]
        end

    end

    class GroupFlow < Flow

        def initialize(list, opts = {})
            super(opts)
            @list = list
        end

    end

    class SequenceFlow < GroupFlow

        @@margin = 0.3

        def size
            if @list.length == 0
                return Size.new(0.0, 0.0)
            end
            sizes = @list.map(&:size)
            w = sizes.map(&:width).reduce(:+)
            h = sizes.map(&:height).max
            w += sizes.length * @@margin
            return Size.new(w, h)
        end

        def self.simplify_array(array)
            # flattens an array of sequences
            newarray = []
            newlist = array.each do |it|
                it = it.simplify
                if it.is_a?(SequenceFlow)
                    newarray += it.sequence()
                else
                    newarray.push(it)
                end
            end
            return newarray
        end

        def into_lines
            # finds nl's inside sequence, and if they exist turns everything into lines
            lines = []
            sizes = []
            line = []
            @list.each do |item|
                if item.is_a?(NewLine)
                    lines.push(line)
                    sizes.push(item.option(:size, &:to_f))
                    line = []
                else
                    line.push(item)
                end
            end
            lines.push(line) if line != []
            if lines.length == 1
                return self
            else
                lines = lines.map { |x| SequenceFlow.new(x) }
                opts = @opts.merge({ 'padding' => { :value => sizes }})
                return LinesFlow.new(lines, opts)
            end
        end

        def simplify
            array = SequenceFlow.simplify_array(@list)
            return SequenceFlow.new(array, @opts)
        end

        def sequence
            return @list
        end

        def els_sizes
            return @list.map(&:size)
        end

        def tikz(state, pos, box)
            super
            first = pos.at(0, box.height * 0.5)
            last = pos.at(box.width, box.height * 0.5)
            first = state.add_coord(first)
            last = state.add_coord(last)
            if @list.length == 0
                state.add_link(first, last)
                return [ first, last ]
            end
            s = self.els_sizes
            sum = s.map(&:width).reduce(:+).to_f
            m = (box.width - sum) / s.length.to_f
            m2 = m * 0.5
            state.add_box(pos, box)
            
            # m is a size of every margin

            b, e = nil, nil # first and last node
            prev = nil
            offset = m2
            for el in @list do
                els = el.size
                middle = (box.height - els.height) * 0.5
                start, ending = el.tikz(state, pos.at(offset, middle), els)
                b = start if b.nil?
                e = ending
                state.add_link(prev, start) unless prev.nil? 
                prev = ending
                offset += els.width + m
            end
            
            state.add_link(first, b)
            state.add_link(e, last)

            return [ first, last ]
        end

        def latex()
            children = @list.map(&:latex)
            return [ '\seq' ] + children + [ '\end' ]
        end

    end

    class LoopFlow < SequenceFlow

        @@hsize = 1.0
        @@vsize = 1.0

        def initialize(*args)
            super
            @breaks = []
        end

        def size
            s = super()
            return s.at(@@vsize, @@hsize)
        end

        def tikz(state, pos, box)
            Thread.current[:__loop__] = [] if Thread.current[:__loop__].nil?
            Thread.current[:__loop__].push(self)

            # state.add_box(pos, box, true)

            finish = pos.at(box.width, box.height * 0.5)

            box = box.at(-@@vsize, -@@hsize)
            pos = pos.at(0, @@hsize * 0.5)

            # state.add_box(pos, box, true)

            s, e = super(state, pos, box)

            ee = state.get_position(e)
            ss = state.get_position(s)
            a = ee.xproj(pos.height)
            b = ss.xproj(pos.height)
            state.add_join([ e, a, b, s ], :arrow)

            # TODO: this will only work nicely with one
            # break
            @breaks.each do |x|
                xx = state.get_position(x)
                a = xx.xproj(pos.height + box.height)
                b = finish.xproj(pos.height + box.height)
                state.add_join([x, a, b, finish])
            end

            ff = state.add_coord(finish)

            state.add_link(e, ff)

            Thread.current[:__loop__].pop()

            return [s, ff]
        end

        def add_break(label)
            @breaks.push(label)
        end

    end

    class BreakLoop < Block

        @@counter = 0

        def tikz(state, pos, box)
            @@counter += 1
            label = "break-#{@@counter}"
            s, e = super(state, pos, box, label)
            Thread.current[:__loop__].last.add_break(label)
            return [ s, e ]
        end

    end

    class SubprocessFlow < SequenceFlow
        # this one contains a subprocess, with its name
        # we ask for +2 in height so that we can nicely
        # fit the name of the process

        def initialize(list, name)
            super(list)
            @name = name
        end

        def size
            s = super()
            return s.at(0, 2)
        end

        def tikz(state, pos, box)
            s = self.size
            links = super(state, pos, box)
            state.add_box(pos, box, true)
            label = Size.new(box.width, 1)
            offset, box = label.shrink(0.8, 0.7)
            state.add_text("#{@name}", pos + offset + box.center, "cm", box)
            return links
        end
    end

    class BoxedFlow < Flow

        def initialize(flow, name, opts = {})
            super(opts)
            @flow = flow
            @name = name
        end

        def size
            s = @flow.size
            return s.at(0, 2)
        end

        def space
            space = 0.0
            space = @opts['space'][:value].to_f if @opts['space']
            return space
        end

        def tikz(state, pos, box)
            itsize = @flow.size
            diff = box - itsize
            flowpos = pos + diff * 0.5
            links = @flow.tikz(state, pos.at(0, 1), Size.new(box.width, itsize.height))
            
            pos = pos.at(0, self.space)

            title = state.add_task("{\\Large\\sc{}#{@name}}",
                pos.at(box.width/2, box.height - 0.5), 'draw', "cm", 1.0)

            m1 = state.get_position(title)
            c1 = pos.at(box.width/2, box.height - 1)
            p1 = pos.at(0, box.height - 1 - 0.4)
            p2 = pos.at(0, box.height - 1)
            p3 = pos.at(box.width, box.height - 1)
            p4 = pos.at(box.width, box.height - 1 - 0.4)

            state.add_line([ m1, c1 ], :type => :solid)
            state.add_line([ p1, p2, p3, p4 ], :type => :solid)

            return links
        end

    end

    class SplitFlow < GroupFlow

        def initialize(list, text)
            super(list)
            @text = text
            @hjustify = 0.5
            @vjustify = 0.75
            @hmargin = 0.0
            @vmargin = 0.0
        end

        def split_size
            sizes = @list.map(&:size)
            w = sizes.map(&:width).max
            h = sizes.map(&:height).reduce(:+)
            return Size.new(w + 2, h).at(@hmargin * 2, @vmargin * 2)
        end

        def size
            return split_size
        end

        def justify(pos, box)
            s = self.size
            dx = (box.width - s.width) * 0.5 * (1 - @hjustify)
            dy = (box.height - s.height) * 0.5 * (1 - @vjustify)
            pos = pos.at(dx, dy)
            box = Size.new(box.width - 2*dx, box.height - 2*dy)
            return [ pos, box ]
        end

        def margine(pos, box)
            box = box.at(-2 * @hmargin, -2 * @vmargin)
            pos = pos.at(@hmargin, @vmargin)
            return [ pos, box ]
        end

        def tikz(state, pos, box)
            # state.add_box(pos, box, true)
            pos, box = margine(pos, box)
            # state.add_box(pos, box, true)
            pos, box = justify(pos, box)
            # state.add_box(pos, box, true)
            first = pos.at(0.5, box.height * 0.5)
            last = pos.at(box.width - 0.5, box.height * 0.5)
            first = @split = state.add_gateway(first, @text)
            last = @merge = state.add_gateway(last, @text)

            s = self.split_size
            pos = pos + [ (box.width - s.width) * 0.5, 0.0 ]
            offset = (box.height - s.height) * 0.5
            for el in @list do
                els = el.size
                start, ending = el.tikz(state, pos.at(1, offset), Size.new(s.width - 2, els.height))
                state.add_link(first, start)
                state.add_link(ending, last)
                offset += els.height
            end
            
            return [ first, last ]
        end

    end

    class ParallelFlow < SplitFlow

        def initialize(list)
            super(list, '+')
        end

        def latex()
            children = @list.map(&:latex)
            return [ '\parallel' ] + children + [ '\end' ]
        end

    end

    class ForallFlow < SplitFlow

        def initialize(list, opts = {})
            # TODO
            opts = { :symbol => '\normalsize{\&}' }.merge(opts)
            super(list, opts[:symbol])
        end

        def size
            s = super()
            return s.at(0, 2)
        end

        def tikz(state, pos, box)
            # state.add_box(pos, box, true)
            # state.add_box(pos.at(0, 1), box.at(0, -2), true)
            
            endings = super(state, pos, box)
            first, last = endings

            first = state.label_pos(@split)
            last = state.label_pos(@merge)

            span = (last - first).width

            steps = 2

            (-steps..steps).each do |i|
                
                next if i == 0

                x = i.to_f / steps
                lcorner = first + [ 0, x ]
                rcorner = last + [ 0, x ]
                middle = (lcorner + rcorner) / 2
                
                c1 = (lcorner + first) / 2
                c2 = (lcorner + middle) / 2
                c3 = (rcorner + middle) / 2
                c4 = (rcorner + last) / 2

                state.add_line([ first, c1, c2, middle, c3, c4, last ], :type => :bezier)
            end

            return endings
        end

        def latex()
            # TODO
            children = @list.map(&:latex).first[1...-1]
            return [ '\forall' ] + children + [ '\end' ]
        end

    end

    class ForeachFlow < ForallFlow

        def initialize(list, opts = {})
            super(list, :symbol => '\normalsize\textbf{=}')
        end

        def latex()
            # TODO
            children = @list.map(&:latex).first[1...-1]
            return [ '\foreach' ] + children + [ '\end' ]
        end

    end

    class SubFlow < Flow

        def initialize(flow)
            super({ })
            @flow = flow
        end

        def size
            return @flow.size
        end

        def tikz(state, pos, box)
            endings = @flow.tikz(state, pos, box)
            state.add_box(pos, box, true)
            return endings
        end

    end

    class NewLine < Flow

        def default_opts
            return { 'size' => { :value => 0 } }
        end

        def initialize(opts = {})
            super(opts)
        end

    end

    class LinesFlow < GroupFlow
        ## multiple line flow

        def default_opts
            return {
                'padding' => { :value => 0 },
                'align' => { :value => :left }
            }
        end

        def padding
            pad = option(:padding)
            if pad.is_a?(Array) # comes from nl's
                return pad
            else
                return [ pad.to_f ] * (@list.length - 1)
            end
        end

        def total_padding
            return self.padding.reduce(:+)
        end

        def align
            return option(:align, &:to_sym)
        end

        def size
            sizes = @list.map(&:size)
            w = sizes.map(&:width).max
            h = sizes.map(&:height).reduce(:+)
            h += self.total_padding
            return Size.new(w, h)
        end

        def tikz(state, pos, box)
            super
            w = box.width
            # state.add_box(pos, box, true)
            mysize = self.size()
            offset = (box.height - mysize.height) * 0.5
            
            pairs = []
            links = []

            paddings = self.padding() + [ 0.0 ] # fake padding
            position_y = pos.height + box.height - offset
            @list.each_with_index do |flow, idx|
                half_padding = paddings[idx] * 0.5
                size = flow.size()
                position_y -= size.height
                line_pos = pos.xproj(position_y)
                if align() == :center
                    xdelta = (mysize.width - size.width) * 0.5
                    line_pos = line_pos.at(xdelta, 0)
                elsif align() == :right
                    xdelta = (mysize.width - size.width)
                    line_pos = line_pos.at(xdelta, 0)
                end
                line_box = Size.new(size.width, size.height)
                x = flow.tikz(state, line_pos, line_box)
                pairs.push(x)
                links.push(position_y - half_padding)
                position_y -= paddings[idx]
            end

            (1...pairs.length).each do |i|
                pred = pairs[i - 1].last
                succ = pairs[i].first
                pos_pred = state.get_position(pred)
                pos_succ = state.get_position(succ)
                _, a, b, _ = pos_pred.vh_path(pos_succ, links[i - 1])
                n1, n2 = [ a, b ].map { |x| state.add_coord(x) }
                state.add_link(pred, n1, n2, succ)
            end

            return [pairs.first.first, pairs.last.last]
        end


    end

    class ProcessFlow < Flow

        def initialize(process)
            super({})
            @process = process
        end

        def simplify
            return ProcessFlow.new(@process.simplify)
        end

        def size
            size = @process.size
            return size.at(2, 0)
        end

        def tikz(state, pos, box)
            state.add_box(pos, box)
            first, last = @process.tikz(state, pos.at(1, 0), box.at(-2, 0))
            ff = state.get_position(first)
            ll = state.get_position(last)
            m = box.height * 0.5
            start = state.add_start(pos.at(0.5, ff.height))
            state.add_link(start, first)
            finish = state.add_finish( (pos + box + [-0.5, 0]).xproj(ll.height))
            state.add_link(last, finish)
        end

        def latex()
            return @process.latex()
        end

    end

    def self.blockify(it)
        it = Block.new(it) unless it.is_a?(Flow)
        return it
    end

    def self.seq(arr, opts = {})
        arr = arr.map { |x| blockify(x) }
        return SequenceFlow.new(arr, opts)
    end

    def self.box(flow, name, opts = {})
        flow = blockify(flow)
        return BoxedFlow.new(flow, name, opts)
    end

    def self.nl(opts)
        return NewLine.new(opts)
    end

    def self.break(name, opts)
        return BreakLoop.new(name, opts)
    end

    def self.loop(arr, opts)
        arr = arr.map { |x| blockify(x) }
        return LoopFlow.new(arr, opts)
    end

    def self.par(*arr)
        arr = arr.map { |x| blockify(x) }
        return ParallelFlow.new(arr) 
    end

    def self.lines(arr, opts)
        arr = arr.map { |x| blockify(x) }
        return LinesFlow.new(arr, opts)
    end

    def self.forall(arr, opts)
        arr = arr.map { |x| blockify(x) }
        seq = SequenceFlow.new(arr)
        return ForallFlow.new([ seq ], opts)
    end

    def self.foreach(arr, opts)
        arr = arr.map { |x| blockify(x) }
        seq = SequenceFlow.new(arr)
        return ForeachFlow.new([ seq ], opts)
    end

    module DSL

        class Element

            def initialize
                @list = []
            end

            def push(x)
                @list.push(x)
            end

            def push_many(arr)
                @list += arr
            end


            def task(name)
                push(Block.new(name))
            end

            def seq_tasks(*names)
                blocks = names.map { |x| Block.new(x) }
                push(SequenceFlow.new(blocks))
            end

            def tasks(*names)
                blocks = names.map { |x| Block.new(x) }
                push_many(blocks)
            end

            def sequence(&block)
                push(Sequence.new.parse(&block))
            end

            def parallel(&block)
                push(Parallel.new.parse(&block))
            end

            def lines(&block)
                push(Lines.new.parse(&block))
            end

            def parse(&block)
                instance_exec(&block)
                return build()
            end

            alias seq sequence

        end

        class LineMarker; end

        class Sequence < Element

            def build
                multiline = @list.any? { |x| x.is_a?(LineMarker) }
                if multiline
                    lines = []
                    curr = []
                    (@list + [ LineMarker.new ]).each do |x|
                        if x.is_a?(LineMarker)
                            lines.push(SequenceFlow.new(curr))
                            curr = []
                        else
                            curr.push(x)
                        end
                    end
                    return LinesFlow.new(lines)
                else
                    return SequenceFlow.new(@list)
                end
            end

            def newline
                push(LineMarker.new)
            end

        end

        class Process < Sequence

            alias seq_build build

            def build
                return ProcessFlow.new(seq_build)
            end

        end

        class Parallel < Element

            def build
                return ParallelFlow.new(@list)
            end

        end

        class Lines < Element

            def build
                return LinesFlow.new(@list)
            end

        end

        def self.workflow(&block)
            return Process.new.parse(&block)
        end

    end

end

if $0 == __FILE__
    if false
        G = Graphing
        seq1 = G.seq('D')
        seq2 = G.seq('E', 'H')
        par1 = G.par('F', 'G')
        seq3 = G.seq('C', par1)

        seq3 = G::SubFlow.new(seq3)

        par2 = G.par(seq1, seq2, seq3)
        main = G.seq('Ale jaja jak berety', 'B', par2)
        p = G::ProcessFlow.new(main)

        g = G::TikzGrapher.new(p, :boxes => false)
        puts g.draw()
    end

    if true
        DSL = Graphing::DSL

        p = DSL.workflow do
            task 'cze'
            parallel do
                tasks 'Clean', 'Find'
                seq_tasks 'A', 'B', 'C', 'D'
                parallel do
                    seq_tasks 'one', 'two'
                    task 'wow'
                end
            end
        end

        p = DSL.workflow do
            parallel do
                lines do
                    seq_tasks(*'a b c'.split)
                    seq_tasks(*'x y'.split)
                    seq_tasks(*'1 2 3'.split)
                    parallel do
                        task 'O rany'
                        task 'banany'
                    end
                end
                seq_tasks 'Clean', 'Find'
            end
        end

        writer = Graphing::PDFWriter.new('/tmp/draw.pdf')
        g = Graphing::CairoGrapher.new(p, writer, :debug => false)
        g.draw()
    end


end
