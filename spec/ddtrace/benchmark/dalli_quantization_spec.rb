# require 'spec_helper'

require 'benchmark/ips'
require 'ddtrace'
require 'datadog/tracing/contrib/dalli/quantize'

operation = :set
args = ['foo', Random.bytes(1_000_000), *Array.new(100, 1)].freeze

module Original
  module_function

  def format_command(operation, args)
    placeholder = "#{operation} BLOB (OMITTED)"
    command = [operation, *args].join(' ').strip
    command = Datadog::Core::Utils.utf8_encode(command, binary: true, placeholder: placeholder)
    Datadog::Core::Utils.truncate(command, 100)
  rescue => e
    puts("Error sanitizing Dalli operation: #{e}")
    placeholder
  end
end

module StaticObfuscation
  module_function

  def format_command(operation, args)
    placeholder = "#{operation} BLOB (OMITTED)"
    command = +operation.to_s

    args.each do |arg|
      str = arg.to_s

      if str.bytesize >= 100
        command << ' (TOO LARGE OMITTED)'
        break
      elsif !str.empty?
        command << ' ' << str
      end

      break if command.length >= 100
    end

    command = Datadog::Core::Utils.utf8_encode(command, binary: true, placeholder: placeholder)
    Datadog::Core::Utils.truncate(command, 100)
  rescue => e
    puts("Error sanitizing Dalli operation: #{e}")
    placeholder
  end
end

module ParsedObfuscation
  module_function

  def format_command(operation, args)
    placeholder = "#{operation} BLOB (OMITTED)"
    command = +operation.to_s

    args.each do |arg|
      str = arg.to_s

      if str.bytesize >= 100
        command << ' ' << Datadog::Core::Utils.truncate(str, 100)
        break
      elsif !str.empty?
        command << ' ' << str
      end

      break if command.length >= 100
    end

    command = Datadog::Core::Utils.utf8_encode(command, binary: true, placeholder: placeholder)
    Datadog::Core::Utils.truncate(command, 100)
  rescue => e
    puts("Error sanitizing Dalli operation: #{e}")
    placeholder
  end
end

Benchmark.ips do |x|
  x.report('original') { Original.format_command(operation, args) }
  x.report('parsed') { ParsedObfuscation.format_command(operation, args) }
  x.report('static') { StaticObfuscation.format_command(operation, args) }
  x.compare!(order: :baseline)
end
