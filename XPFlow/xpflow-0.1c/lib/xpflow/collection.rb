
# stuff related to collecting execution results

module XPFlow

    class FileResult

        attr_reader :filename
        attr_reader :info

        def initialize(filename, info)
            @filename = filename
            @info = info
        end

    end

    class Collection

        attr_reader :path

        def initialize(path)
            @results = {}
            @files = {}
            @path = path
        end

        def create(subdir)
            return Collection.new(File.join(@path, subdir))
        end

        def create_path()
            if File.directory?(@path)
                FileUtils.remove_entry_secure(@path)
            end
            Dir.mkdir(@path)
        end

        def collect_result(key, result)
            @results[key] = result
        end

        def save_all
            index = 0
            @results.each do |key, result|
                prefix = File.join(@path, key.to_s)
                if result.is_a?(ManyExecutionResult)
                    files = save_manyresult(result, prefix)
                    @files[key] = files
                else
                    raise "Can't collect results of type #{result.class}"
                end
            end
        end

        def save_manyresult(result, prefix)
            summary = "#{prefix}-summary.yaml"
            info = []
            files = []
            pad = result.length.to_s.length
            counter = 1
            result.to_list.each do |r|
                basename = "#{counter.to_s.rjust(pad, '0')}"
                stdout_file = "#{basename}.stdout"
                stderr_file = "#{basename}.stderr"
                stdout_file = "#{prefix}-#{stdout_file}"
                stderr_file = "#{prefix}-#{stderr_file}"
                r.save_stdout(stdout_file)
                r.save_stderr(stderr_file)
                node = r.node
                this_info = {
                    # TODO: add more data, e.g., provenance, real paths?
                    :stdout => stdout_file,
                    :stderr => stderr_file,
                    :host => node.host,
                    :user => node.user
                }
                info.push(this_info)
                files.push(FileResult.new(stdout_file, this_info))
                counter += 1
            end
            IO.write(summary, info.to_yaml)
            return files
        end

    end

    class CollectionLibrary < SyncedActivityLibrary

        activities :collect_result, :save_all_results,
            :get_files, :transform_to_float,
            :result_collection

        def setup

        end

        def result_collection
            return Scope.current[:__collection__]
        end

        def collect_result(key, result)
            return result_collection.collect_result(key, result)
        end

        def save_all_results
            return result_collection().save_all()
        end

        def transform_to_float(results, script)
            files = @files[results]
            script = $files[script]
            floats = files.map do |r|
                x = proxy.run :"__core__.system", "#{script} #{r.filename}"
                x.to_f
            end
            return ValueData.new(floats)
        end

    end

end
