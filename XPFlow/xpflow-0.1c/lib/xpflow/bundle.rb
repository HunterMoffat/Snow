
#
# builds a one-file-bundle of xpflow
# 
# TODO: it's not finished:
#   * it won't bundle various external files (e.g., node templates)
#   * __FILE__ usage should be standarized somehow to make everything work
#
# We roughly do the following (bundle method):
#
#   - take all files from lib directory
#   - discard some files that are not used
#   - pull ../xpflow (entry point for the library) as well
#   - remove "require" uses all over the place, checking if
#     we know about them
#   - then merge them all and wrap in an envelope that
#     temporarily replaces $0 (so that inline code won't run)
#   - for interested parties, we set $bundled = true
#   - finally we append model.rb (TODO: it needs fixing)
#   - the order of files *must* not matter!
#
# For executable method, we also:
#  
#   - pull main bin/xpflow script
#   - replace a specially marked region with the result
#     of bundle() method
#
# Therefore, a todo list:
#   1) Fix __FILE__ uses so that model.rb works
#   2) Bundle external files as well (pack them, serialize
#      and then extract them on-the-fly?)
#   3) make everything more robust and less hackish
#

module XPFlow

    class Bundler

        def initialize
            basic = [ '../colorado', 'utils', 'structs', 'scope', 'library' ]
            discard = [ 'ensemble', 'ssh', 'bash' ]
            files = basic + (__get_my_requires__.sort - basic - discard)
            @here = File.dirname(__FILE__)
            files += [ '../xpflow']

            @files = files.map { |x| File.join(@here, "#{x}.rb") }
        end

        def bundle
            ignored = [ "xpflow/exts/g5k", "colorado" ]
            libs = [ "thread", "monitor", "pp", "digest", "open3", "tmpdir",
                "fileutils", "monitor", "erb", "ostruct", "yaml", "shellwords",
                 "etc", "optparse", "pathname" ] # TODO: g5k should be pulled in
            parts = []
            puts "Bundling files:"
            @files.each do |f|
                puts " - #{f}"
                contents = IO.read(f)
                new_cont = contents.gsub(/require\s+(\S+)/) do |req|
                    lib = req.split("'")[1]
                    if (libs + ignored).include?(lib) or lib == "xpflow"
                        ""
                    else
                        puts "Warning: untreated library (#{lib})"
                    end
                end
                parts.push(new_cont)
            end

            s = parts.join("\n")

            lib_lines = libs.map { |x| "require('#{x}')" }
            model = File.join(@here, "exts", "model.rb")

            final = ([ "# encoding: UTF-8" ] + lib_lines + [
                "$tmp_0 = $0; $0 = 'faked_name'; $bundled = true",
                s,
                "$0 = $tmp_0",
                IO.read(model)
            ]).join("\n")

            return final
        end

        def executable
            b = bundle()
            main_file = File.join(@here, "..", "..", "bin", "xpflow")
            contents = IO.read(main_file)

            exp = Regexp.new("(\#XSTART.+\#XEND)", Regexp::MULTILINE)
            main = contents.gsub(exp, b)

            return main
        end

    end
end

if __FILE__ == $0
    require 'xpflow'

    bundle = ARGV.first

    if bundle.nil?
        raise "Please provide an output file."
    end

    bundler = XPFlow::Bundler.new
    output = bundler.executable()
    
    IO.write(bundle, output)

end
