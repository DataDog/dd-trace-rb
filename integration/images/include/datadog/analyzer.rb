require 'json'

class Analyzer
  def initialize(filename)
    @filename = filename
  end

  def analyze
    data = []
    File.open(@filename) do |f|
        f.each_line do |line|
          data << (parsed=JSON.parse(line))
        end
    end

    data.group_by{ |row| row['generation'] }
        .sort{|a,b| a[0].to_i <=> b[0].to_i }
        .each do |k,v|
          puts "location #{k} objects #{v.count}"
        end
  end

  def analyze_objects(gen_range = nil)
    data = []
    File.open(@filename) do |f|
        f.each_line do |line|
          parsed = JSON.parse(line)
          if gen_range && gen_range.include?(parsed['generation'].to_i)
            data << parsed
          end
        end
    end

    data.group_by{ |row| "#{row['file']}:#{row['line']}" }
        .sort{|a,b| b[1].length <=> a[1].length }
        .each do |k,v|
          puts "line #{k} objects #{v.count}"
        end
  end

  def analyze_generation(gen)
    data = []
    File.open(@filename) do |f|
        f.each_line do |line|
          parsed=JSON.parse(line)
          data << parsed if parsed["generation"] == gen
        end
    end
    data.group_by{|row| "#{row["file"]}:#{row["line"]}"}
        .sort{|a,b| b[1].count <=> a[1].count}
        .each do |k,v|
          puts "#{k} * #{v.count}"
        end
  end
end

if ARGV[1]
  if ARGV[1] == 'objects'
    range = nil
    if ARGV[2]
      range_end = ARGV[2].to_i
      range_start = ARGV[3].to_i
      range = Range.new(range_start, range_end)
    end
    Analyzer.new(ARGV[0]).analyze_objects(range)
  else
    Analyzer.new(ARGV[0]).analyze_generation(ARGV[1].to_i)
  end
else
  Analyzer.new(ARGV[0]).analyze
end
