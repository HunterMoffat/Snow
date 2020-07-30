# encoding: UTF-8

#
# Data collection classes.
#

module XPFlow

    class ValueData

        attr_reader :values

        def initialize(vals = nil)
            vals = [] if vals.nil?
            @values = vals
        end

        def push(x)
            @values.push(x)
        end

        def ==(x)
            return (@values == x) if x.is_a?(Array)
            return (@values == x.values)
        end

        def average
            return @values.reduce(:+).to_f / @values.length
        end

        def average_variance
            raise 'The variance computation for sample with less than 2 elements is impossible' if @values.length < 2
            m = average()
            s = @values.map { |x| (x - m)**2 }.reduce(:+)
            return [ m, s / (@values.length - 1) ]
        end

        def variance
            return average_variance().last
        end

        def average_stddev
            m, v = average_variance()
            return m, v ** 0.5
        end

        def stddev
            return average_stddev().last
        end

        # START OF DISTRIBUTIONS

        # Credit for cdf_inverse : http://home.online.no/~pjacklam/notes/invnorm/
        # inverse standard normal cumulative distribution function
        def self.cdf_inverse(p)
            a = [0, -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
            b = [0, -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01]
            c = [0, -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
            d = [0, 7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00]
            #Define break-points.
            p_low  = 0.02425
            p_high = 1.0 - p_low

            x = 0.0
            q = 0.0
            #Rational approximation for lower region.
            if 0.0 < p && p < p_low
                q = Math.sqrt(-2.0*Math.log(p))
                x = (((((c[1]*q+c[2])*q+c[3])*q+c[4])*q+c[5])*q+c[6]) / ((((d[1]*q+d[2])*q+d[3])*q+d[4])*q+1.0)

                #Rational approximation for central region.
            elsif p_low <= p && p <= p_high
                q = p - 0.5
                r = q*q
                x = (((((a[1]*r+a[2])*r+a[3])*r+a[4])*r+a[5])*r+a[6])*q / (((((b[1]*r+b[2])*r+b[3])*r+b[4])*r+b[5])*r+1.0)

                #Rational approximation for upper region.
            elsif p_high < p && p < 1.0
                q = Math.sqrt(-2.0*Math.log(1.0-p))
                x = -(((((c[1]*q+c[2])*q+c[3])*q+c[4])*q+c[5])*q+c[6]) / ((((d[1]*q+d[2])*q+d[3])*q+d[4])*q+1.0)
            end

            #The relative error of the approximation has
            #absolute value less than 1.15 × 10−9.  One iteration of
            #Halley’s rational method (third order) gives full machine precision.
            if 0 < p && p < 1
                e = 0.5 * Math.erfc(-x/Math.sqrt(2.0)) - p
                u = e * Math.sqrt(2.0*Math::PI) * Math.exp((x**2.0)/2.0)
                x = x - u/(1.0 + x*u/2.0)
            end
            return x
        end

        # computes confidence interval, assuming that
        # the number of measures is large enough
        # to be approximated with CLT
        # prec is ABSOLUTE (here and below)

        def _compute_dist(prec, conf, cvalue)
            m, s = average_stddev()
            d = (cvalue * s).to_f / (@values.length ** 0.5)
            sample = ((cvalue * s / prec) ** 2).to_i + 1
            return {
                :interval => [ m - d, m + d ],
                :d => d,
                :sample => sample
            }
        end

        def _dist(name, prec, conf)
            r = case name
                when :n then _dist_n(prec, conf)
                when :t then _dist_t(prec, conf)
                else
                    raise "Unknown distribution: #{name}"
                end
            return r
        end

        def _dist_n(prec, conf)
            cvalue = ValueData.cdf_inverse((1 + conf) * 0.5)
            return _compute_dist(prec, conf, cvalue)
        end

        def confidence_interval_n(conf)
            return _dist_n(1.0, conf)[:interval]
        end

        # computes the minimal sample size
        def minimal_sample_n(prec, conf)
            return _dist_n(prec, conf)[:sample]
        end

        TSTUDENT = [
            nil,   12.71, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228,
            2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086, 2.080,
            2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042, 2.021, 2.009,
            2.000, 1.990, 1.984, 1.980, 1.960 ]

        def _get_tstudent_factor
            n = size()
            raise "size of sample must be positive" if n <= 0
            return (n < TSTUDENT.length) ? TSTUDENT[n] : TSTUDENT[-1]
        end

        def _dist_t(prec, conf)
            cvalue = _get_tstudent_factor()
            return _compute_dist(prec, conf, cvalue)
        end

        # computes confidence interval, assuming that
        # each measure is normal; therefore their
        # average is t-student
        def confidence_interval_t(conf)
            # TODO: confidence is ignored
            return _dist_t(1.0, conf)[:interval]
        end

        def minimal_sample_t(prec, conf)
            return _dist_t(prec, conf)[:sample]
        end

        # END OF DISTRIBUTIONS

        def map(&block)
            arr = @values.map(&block)
            return ValueData.new(arr)
        end

        def sort
            return ValueData.new(@values.sort)
        end

        def to_s
            return "<Data: #{@values.inspect}>"
        end

        def sum
            return @values.reduce(:+)
        end

        def size
            return @values.length
        end

        def length
            return size()
        end

        def append(x)
            return ValueData.new(self.values + [ x ])
        end

    end

    class NamedTuple

        def initialize(base, array)
            @base = base
            @array = array
        end

        def [](label)
            label = @base.unlabel(label) unless label.is_a?(Fixnum)
            return @array[label]
        end

        def value(idx)
            return @array[idx]
        end

        def values(idxs)
            return idxs.map { |i| @array[i] }
        end

        def method_missing(name, *args)
            idx = @base.unlabel(name)
            raise NoMethodError.new("undefined method '#{name}'", name) if (idx.nil? or args.length != 0)
            return @array[idx]
        end

        def to_s
            labels = @base.labels
            s = @array.each_with_index.map { |el, i|
                "#{labels[i]}=#{el}"
            }.join(', ')
            return "<#{s}>"
        end

        def to_a
            return @array
        end

    end

    class NamedTupleBase

        attr_reader :labels

        def initialize(labels)
            @labels = labels
        end

        def build(row)
            return row if row.is_a?(NamedTuple)
            if row.is_a?(Hash)
                row = @labels.map { |l| row[l] }
            elsif row.is_a?(Array)
            else
                raise
            end
            return NamedTuple.new(self, row)
        end

        def unlabel(label)
            return @labels.index(label)
        end

        def unlabels(labs)
            return labs.map { |l| unlabel(l) }
        end

        def split_labels(labs)
            left = []
            right = []
            @labels.each_with_index { |l, i|
                idx = labs.index(l)
                if idx.nil?
                    right.push(l)
                else
                    left.push([idx, l])
                end
            }
            left = left.sort.map { |x| x.last }
            return [left, right]
        end

        def to_s
            s = @labels.map { |x| x.to_s }.join(', ')
            return "<Base: #{s}>"
        end

    end

    class RowData

        def initialize(labs, rows = nil)
            rows = [] if rows.nil?
            @base = NamedTupleBase.new(labs)
            @rows = rows
        end

        def labels
            return @base.labels
        end

        def duplicate(rows = nil)
            return RowData.new(@base.labels, rows)
        end

        def length
            return @rows.length
        end

        def width
            return @base.labels.length
        end

        def push(row)
            row = @base.build(row)
            @rows.push(row)
        end

        def append(rows)
            rows.each { |r| push(r) }
        end

        def column(label)
            values = @rows.map { |row| row[label] }
            return ValueData.new(values)
        end

        def _group(labs, key_f = nil)
            # groups data by labels; returns hash
            labs = @base.unlabels(labs)
            groups = {}
            @rows.each { |r|
                key = r.values(labs)
                key = key_f.call(key) unless key_f.nil?
                groups[key] = duplicate() unless groups.key?(key)
                groups[key].push(r)
            }
            return groups
        end

        def _select(labs)
            rows = RowData.new(labs)
            labs = @base.unlabels(labs)
            @rows.each { |row| rows.push(row.values(labs)) }
            return rows
        end

        def _cluster(labs, key_f = nil)
            groups = _group(labs, key_f)
            left, right = @base.split_labels(labs)
            h = groups.map { |k, v| [ k, v._select(right) ] }
            return Hash[h]
        end

        def _sort(&block)
            rows = @rows.clone()  # shallow copy of the rows
            rows.sort!(&block)
            return duplicate(rows)
        end

        def _filter(&block)
            rows = @rows.select(&block)
            return duplicate(rows)
        end

        def _map(&block)
            @rows.map(&block)
        end

        def _expand(new_labels, &block)
            labs = @base.labels + new_labels
            rows = RowData.new(labs)
            @rows.each { |r|
                ext = block.call(r)
                ext = [ext] unless ext.is_a?(Array)
                rows.push(r.to_a + ext)
            }
            return rows
        end

        def _discard(old_labels)
            labs = @base.labels - old_labels
            rows = RowData.new(labs)
            idxs = @base.unlabels(labs)
            @rows.each { |r|
                rows.push(r.values(idxs))
            }
            return rows
        end

        def to_s
            s = @rows.map { |el| el.to_s }.join(", ")
            return "[ #{s} ]"
        end

        ### USER FRIENDLY PART

        def self.create(*labs)
            return RowData.new(labs)
        end

        def collect(*row)
            row = row.first if row.length == 1 and row.first.is_a?(Hash)
            push(row)
        end

        def table
            return @rows.map { |r| r.to_a }
        end

        def sort(&block); _sort(&block) end
        def select(*labs); _select(labs) end
        def group(*labs); _group(labs) end
        def group_one(label); _group([label], lambda { |k| k.first }) end
        def cluster(*labs); _cluster(labs) end
        def cluster_one(label); _cluster([label], lambda { |k| k.first }) end
        def filter(&block); _filter(&block) end
        def map(&block); _map(&block) end
        def expand(*labs, &block); _expand(labs, &block) end
        def discard(*labs); _discard(labs) end

    end

end

