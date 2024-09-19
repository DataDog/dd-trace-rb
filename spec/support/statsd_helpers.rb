module StatsdHelpers
  shared_context 'statsd' do
    let(:statsd) { spy('statsd') } # TODO: Make this an instance double.
    let(:stats) { Hash.new(0) }
    let(:stats_mutex) { Mutex.new }

    before do
      allow(statsd).to receive(:distribution) do |name, _value, _options = {}|
        stats_mutex.synchronize do
          stats[name] = 0 unless stats.key?(name)
          stats[name] += 1
        end
      end

      allow(statsd).to receive(:gauge) do |name, _value, _options = {}|
        stats_mutex.synchronize do
          stats[name] = 0 unless stats.key?(name)
          stats[name] += 1
        end
      end

      allow(statsd).to receive(:increment) do |name, options = {}|
        stats_mutex.synchronize do
          stats[name] = 0 unless stats.key?(name)
          stats[name] += options.key?(:by) ? options[:by] : 1
        end
      end

      allow(statsd).to receive(:time) do |name, _options = {}, &block|
        stats_mutex.synchronize do
          stats[name] = 0 unless stats.key?(name)
          stats[name] += 1
        end
        block.call
      end
    end
  end
end
