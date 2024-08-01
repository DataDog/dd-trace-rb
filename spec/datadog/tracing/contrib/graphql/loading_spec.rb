RSpec.describe 'loading graphql' do
  context 'then datadog' do
    let(:code) do
      <<-E
        require "graphql"
        require "datadog"
        exit 0
      E
    end

    it 'loads successfully by itself' do
      rv = system("ruby -e #{Shellwords.shellescape(code)}")
      expect(rv).to be true
    end
  end

  context 'after datadog' do
    let(:code) do
      <<-E
        require "datadog"
        require "graphql"
        exit 0
      E
    end

    it 'loads successfully by itself' do
      rv = system("ruby -e #{Shellwords.shellescape(code)}")
      expect(rv).to be true
    end
  end
end
