require 'json'

RSpec.describe Datadog::Ext::CI do
  describe '::tags' do
    def self.match(env, tags)
      it "matches tags from #{env}" do
        ClimateControl.modify('HOME' => env['HOME']) do
          expect(described_class.tags(env)).to eq(tags)
        end
      end
    end

    Dir.glob(File.dirname(__FILE__) + '/fixtures/ci/*.json') do |filename|
      File.open(filename) do |f|
        JSON.parse(f.read).each do |item|
          match(item[0], item[1])
        end
      end
    end
  end
end
