lib = File.expand_path('lib')
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'datadog/tracing/distributed/datadog_tags_codec'

require 'fuzzbert'

class FuzzBert::Repeat < FuzzBert::Container
  def initialize(range = 1024)
    super()
    @range = range

    yield(self) if block_given?
  end

  def to_data
    ret = ""
    FuzzBert::PRNG.rand(@range).times { ret << super }
    ret
  end

  def call
    to_data
  end
end

class FuzzBert::Container
  def initialize(generators=[])
    @generators = generators
    yield(self) if block_given?
  end
end

class FuzzBert::TestSuite
  def data(desc, &blk)
    raise RuntimeError.new "No block was given" unless blk
    ret = blk.call

    generator = ret.respond_to?(:generator) ? ret.generator : ret
    raise "No generator returned from block" unless generator

    @generators << FuzzBert::Generator.new(desc, generator)
  end
end

fuzz "Datadog::Tracing::Distributed::DatadogTagsCodec#encode" do
  deploy do |data|
    begin
      Datadog::Tracing::Distributed::DatadogTagsCodec.decode(data)
    rescue Datadog::Tracing::Distributed::DatadogTagsCodec::DecodingError => _
      # This error is expected and part of the #decode's API.
      # We are looking for unexpected error types.
    end
  end

  data 'with a random string' do
    FuzzBert::Generators.random
  end

  data 'with a key value pair' do
    FuzzBert::Container.new do |c|
      c << FuzzBert::Generators.random
      c << FuzzBert::Generators.fixed("=")
      c << FuzzBert::Generators.random
    end
  end

  data 'with a list of key value pairs' do
    FuzzBert::Repeat.new do |r|
      r << FuzzBert::Generators.random
      r << FuzzBert::Generators.fixed("=")
      r << FuzzBert::Generators.random
      r << FuzzBert::Generators.fixed(",")
    end
  end

end

FuzzBert::AutoRun.run(limit: 1, pool_size: 1)
