require 'yaml'
require 'json'

class Matrix
  RUBY_TO_JRUBY = {
    '2.5' => ['9.2'],
    '2.6' => ['9.3'],
    '3.1' => ['9.4'],
  }

  def initialize(matrixfile = 'Matrixfile')
    @matrixfile = matrixfile
    @matrix = matrix
  end

  def map
    eval(File.open(@matrixfile, 'r:UTF-8').read)
  end

  def definitions
    map.each_with_object({}) do |(spec, appraisals), h|
      h[spec] = appraisals.each_with_object({}) do |(group, rubies), h2|
        ruby = rubies.scan(/✅ (\S+)/).flatten

        has_jruby = ruby.delete('jruby')

        engines = { 'ruby' => ruby }

        if has_jruby && (versions = RUBY_TO_JRUBY.select { |r, _| ruby.include?(r) }.values.flatten).any?
          engines['jruby'] = versions
        end

        h2[group] = engines
      end
    end.tap do |definitions|
      # Rails 4.x is not supported on JRuby 9.2 (which is RUBY_VERSION 2.5)
      definitions.each { |_, appraisals| appraisals.each { |appraisal, engines| appraisal =~ /^rails4/ && engines.key?('jruby') && engines['jruby'].delete('9.2') } }
    end
  end

  def matrix
    definitions.each_with_object([]) do |(spec, appraisals), a|
      appraisals.each do |appraisal, engines|
        engines.each do |engine, versions|
          versions.each do |version|
            a << {
              spec: {
                task: spec,
                appraisal: appraisal,
              },
              engine: {
                name: engine,
                version: version
              }
            }
          end
        end
      end
    end
  end

  def to_a
    @matrix
  end

  def select!(&block)
    @matrix.select!(&block)
  end

  def engines
    @matrix.each_with_object([]) { |e, a| a << e[:engine] }.uniq!
  end

  def specs
    @matrix.each_with_object([]) { |e, a| a << e[:spec][:task] }.uniq!
  end

  def appraisals
    @matrix.each_with_object([]) { |e, a| a << e[:spec][:appraisal] }.uniq!
  end
end

if $0 == __FILE__
  matrix = Matrix.new

  selected_engine_name = nil
  selected_engine_version = nil
  selected_spec_task = nil
  selected_spec_appraisal = nil
  output = nil
  format = nil
  ARGV.each do |arg|
    case arg
    when /^engine.name:(\S+)/ then selected_engine_name = $1
    when /^engine.version:(\S+)/ then selected_engine_version = $1
    when /^spec:(\S+)/ then selected_spec_task = $1
    when /^appraisal:(\S*)/ then selected_spec_appraisal = $1
    when 'engines' then output = 'engines'
    when 'specs' then output = 'specs'
    when 'appraisals' then output = 'appraisals'
    when '--json' then format = 'json'
    end
  end

  if selected_engine_name
    matrix.select! { |e| e[:engine][:name] == selected_engine_name }
  end

  if selected_engine_version
    matrix.select! { |e| e[:engine][:version] == selected_engine_version }
  end

  if selected_spec_task
    matrix.select! { |e| e[:spec][:task] == selected_spec_task }
  end

  if selected_spec_appraisal
    matrix.select! { |e| e[:spec][:appraisal] == selected_spec_appraisal }
  end

  out = case output
        when 'engines'
          matrix.engines
        when 'specs'
          matrix.specs
        when 'appraisals'
          matrix.appraisals
        else
          { include: matrix.to_a }
        end

  case format
  when 'json'
    puts(JSON.dump(out))
  else
    out.each { |e| puts e }
  end
end
