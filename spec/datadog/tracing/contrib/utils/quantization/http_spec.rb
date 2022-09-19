# typed: false

require 'spec_helper'

require 'datadog/tracing/contrib/utils/quantization/http'

RSpec.describe Datadog::Tracing::Contrib::Utils::Quantization::HTTP do
  describe '#url' do
    subject(:result) { described_class.url(url, options) }

    let(:options) { {} }

    context 'given a URL' do
      let(:url) { 'http://example.com/path?category_id=1&sort_by=asc#featured' }

      context 'default behavior' do
        it { is_expected.to eq('http://example.com/path?category_id&sort_by') }
      end

      context 'default behavior for an array' do
        let(:url) { 'http://example.com/path?categories[]=1&categories[]=2' }

        it { is_expected.to eq('http://example.com/path?categories[]') }
      end

      context 'with query: show: value' do
        let(:options) { { query: { show: ['category_id'] } } }

        it { is_expected.to eq('http://example.com/path?category_id=1&sort_by') }
      end

      context 'with query: show: :all' do
        let(:options) { { query: { show: :all } } }

        it { is_expected.to eq('http://example.com/path?category_id=1&sort_by=asc') }
      end

      context 'with query: exclude: value' do
        let(:options) { { query: { exclude: ['sort_by'] } } }

        it { is_expected.to eq('http://example.com/path?category_id') }
      end

      context 'with query: exclude: :all' do
        let(:options) { { query: { exclude: :all } } }

        it { is_expected.to eq('http://example.com/path') }
      end

      context 'with fragment: :show' do
        let(:options) { { fragment: :show } }

        it { is_expected.to eq('http://example.com/path?category_id&sort_by#featured') }
      end

      context 'with base: :show' do
        let(:options) { { base: :show } }

        it { is_expected.to eq('http://example.com/path?category_id&sort_by') }
      end

      context 'with base: :exclude' do
        let(:options) { { base: :exclude } }

        it { is_expected.to eq('/path?category_id&sort_by') }
      end

      context 'with Unicode characters' do
        # URLs do not permit unencoded non-ASCII characters in the URL.
        let(:url) { 'http://example.com/path?繋がってて' }

        it { is_expected.to eq(described_class::PLACEHOLDER) }
      end

      context 'with internal obfuscation and the default replacement' do
        let(:url) { 'http://example.com/path?password=hunter2' }
        let(:options) { { query: { obfuscate: :internal } } }

        it { is_expected.to eq('http://example.com/path?%3Credacted%3E') }
      end

      context 'with internal obfuscation and a custom replacement' do
        let(:url) { 'http://example.com/path?password=hunter2' }
        let(:options) { { query: { obfuscate: { with: 'NOPE' } } } }

        it { is_expected.to eq('http://example.com/path?NOPE') }
      end

      context 'with custom obfuscation and a custom replacement' do
        let(:url) { 'http://example.com/path?password=hunter2&foo=42' }
        let(:options) { { query: { obfuscate: { regex: /foo=\w+/, with: 'NOPE' } } } }

        it { is_expected.to eq('http://example.com/path?password=hunter2&NOPE') }
      end
    end
  end

  describe '#query' do
    subject(:result) { described_class.query(query, options) }

    context 'given a query' do
      context 'and no options' do
        let(:options) { {} }

        context 'with a single parameter' do
          let(:query) { 'foo=foo' }

          it { is_expected.to eq('foo') }

          context 'with an invalid byte sequence' do
            # \255 is off-limits https://en.wikipedia.org/wiki/UTF-8#Codepage_layout
            # There isn't a graceful way to handle this without stripping interesting
            # characters out either; so just raise an error and default to the placeholder.
            let(:query) { "foo\255=foo" }

            it { is_expected.to eq('?') }
          end
        end

        context 'with multiple parameters' do
          let(:query) { 'foo=foo&bar=bar' }

          it { is_expected.to eq('foo&bar') }
        end

        context 'with array-style parameters' do
          let(:query) { 'foo[]=bar&foo[]=baz' }

          it { is_expected.to eq('foo[]') }
        end

        context 'with semi-colon style parameters' do
          let(:query) { 'foo;bar' }
          # Notice semicolons aren't preseved... no great way of handling this.
          # Semicolons are illegal as of 2014... so this is an edge case.
          # See https://www.w3.org/TR/2014/REC-html5-20141028/forms.html#url-encoded-form-data

          it { is_expected.to eq('foo;bar') }
        end

        context 'with object-style parameters' do
          let(:query) { 'user[id]=1&user[name]=Nathan' }

          it { is_expected.to eq('user[id]&user[name]') }

          context 'that are complex' do
            let(:query) { 'users[][id]=1&users[][name]=Nathan&users[][id]=2&users[][name]=Emma' }

            it { is_expected.to eq('users[][id]&users[][name]') }
          end
        end
      end

      context 'and a show: :all option' do
        let(:query) { 'foo=foo&bar=bar' }
        let(:options) { { show: :all } }

        it { is_expected.to eq(query) }
      end

      context 'and a show option' do
        context 'with a single parameter' do
          let(:query) { 'foo=foo' }
          let(:key) { 'foo' }
          let(:options) { { show: [key] } }

          it { is_expected.to eq('foo=foo') }

          context 'that has a Unicode key' do
            let(:query) { '繋=foo' }
            let(:key) { '繋' }

            it { is_expected.to eq('繋=foo') }

            context 'that is encoded' do
              let(:query) { '%E7%B9%8B=foo' }
              let(:key) { '%E7%B9%8B' }

              it { is_expected.to eq('%E7%B9%8B=foo') }
            end
          end

          context 'that has a Unicode value' do
            let(:query) { 'foo=繋' }
            let(:key) { 'foo' }

            it { is_expected.to eq('foo=繋') }

            context 'that is encoded' do
              let(:query) { 'foo=%E7%B9%8B' }

              it { is_expected.to eq('foo=%E7%B9%8B') }
            end
          end

          context 'that has a Unicode key and value' do
            let(:query) { '繋=繋' }
            let(:key) { '繋' }

            it { is_expected.to eq('繋=繋') }

            context 'that is encoded' do
              let(:query) { '%E7%B9%8B=%E7%B9%8B' }
              let(:key) { '%E7%B9%8B' }

              it { is_expected.to eq('%E7%B9%8B=%E7%B9%8B') }
            end
          end
        end

        context 'with multiple parameters' do
          let(:query) { 'foo=foo&bar=bar' }
          let(:options) { { show: ['foo'] } }

          it { is_expected.to eq('foo=foo&bar') }
        end

        context 'with array-style parameters' do
          let(:query) { 'foo[]=bar&foo[]=baz' }
          let(:options) { { show: ['foo[]'] } }

          it { is_expected.to eq('foo[]=bar&foo[]=baz') }

          context 'that contains encoded braces' do
            let(:query) { 'foo[]=%5Bbar%5D&foo[]=%5Bbaz%5D' }

            it { is_expected.to eq('foo[]=%5Bbar%5D&foo[]=%5Bbaz%5D') }

            context 'that exactly matches the key' do
              let(:query) { 'foo[]=foo%5B%5D&foo[]=foo%5B%5D' }

              it { is_expected.to eq('foo[]=foo%5B%5D&foo[]=foo%5B%5D') }
            end
          end
        end

        context 'with object-style parameters' do
          let(:query) { 'user[id]=1&user[name]=Nathan' }
          let(:options) { { show: ['user[id]'] } }

          it { is_expected.to eq('user[id]=1&user[name]') }

          context 'that are complex' do
            let(:query) { 'users[][id]=1&users[][name]=Nathan&users[][id]=2&users[][name]=Emma' }
            let(:options) { { show: ['users[][id]'] } }

            it { is_expected.to eq('users[][id]=1&users[][name]&users[][id]=2') }
          end
        end
      end

      context 'and an exclude: :all option' do
        let(:query) { 'foo=foo&bar=bar' }
        let(:options) { { exclude: :all } }

        it { is_expected.to eq('') }
      end

      context 'and an exclude option' do
        context 'with a single parameter' do
          let(:query) { 'foo=foo' }
          let(:options) { { exclude: ['foo'] } }

          it { is_expected.to eq('') }
        end

        context 'with multiple parameters' do
          let(:query) { 'foo=foo&bar=bar' }
          let(:options) { { exclude: ['foo'] } }

          it { is_expected.to eq('bar') }
        end

        context 'with array-style parameters' do
          let(:query) { 'foo[]=bar&foo[]=baz' }
          let(:options) { { exclude: ['foo[]'] } }

          it { is_expected.to eq('') }
        end

        context 'with object-style parameters' do
          let(:query) { 'user[id]=1&user[name]=Nathan' }
          let(:options) { { exclude: ['user[name]'] } }

          it { is_expected.to eq('user[id]') }

          context 'that are complex' do
            let(:query) { 'users[][id]=1&users[][name]=Nathan&users[][id]=2&users[][name]=Emma' }
            let(:options) { { exclude: ['users[][name]'] } }

            it { is_expected.to eq('users[][id]') }
          end
        end
      end

      context 'and an obfuscate: :internal option' do
        context 'with a non-matching substring' do
          let(:query) { 'foo=foo' }
          let(:options) { { obfuscate: :internal } }

          it { is_expected.to eq('foo=foo') }
        end

        context 'with a matching substring at the beginning' do
          let(:query) { 'pass=03cb9f67-dbbc-4cb8-b966-329951e10934&key2=val2&key3=val3' }
          let(:options) { { obfuscate: :internal } }

          it { is_expected.to eq('<redacted>&key2=val2&key3=val3') }
        end

        context 'with a matching substring in the middle' do
          let(:query) { 'key1=val1&public_key=MDNjYjlmNjctZGJiYy00Y2I4LWI5NjYtMzI5OTUxZTEwOTM0&key3=val3' }
          let(:options) { { obfuscate: :internal } }

          it { is_expected.to eq('key1=val1&<redacted>&key3=val3') }
        end

        context 'with a matching substring at the end' do
          let(:query) { 'key1=val1&key2=val2&token=03cb9f67dbbc4cb8b966329951e10934' }
          let(:options) { { obfuscate: :internal } }

          it { is_expected.to eq('key1=val1&key2=val2&<redacted>') }
        end

        context 'with multiple matching substrings' do
          let(:query) { 'key1=val1&pass=03cb9f67-dbbc-4cb8-b966-329951e10934&key2=val2&token=03cb9f67dbbc4cb8b966329951e10934&public_key=MDNjYjlmNjctZGJiYy00Y2I4LWI5NjYtMzI5OTUxZTEwOTM0&key3=val3&json=%7B%20%22sign%22%3A%20%22%7B0x03cb9f67%2C0xdbbc%2C0x4cb8%2C%7B0xb9%2C0x66%2C0x32%2C0x99%2C0x51%2C0xe1%2C0x09%2C0x34%7D%7D%22%7D' }
          let(:options) { { obfuscate: :internal } }

          it { is_expected.to eq('key1=val1&<redacted>&key2=val2&<redacted>&<redacted>&key3=val3&json=%7B%20%22<redacted>%7D') }
        end

        context 'with a matching, URL-encoded JSON substring' do
          let(:query) { 'json=%7B%20%22sign%22%3A%20%22%7B0x03cb9f67%2C0xdbbc%2C0x4cb8%2C%7B0xb9%2C0x66%2C0x32%2C0x99%2C0x51%2C0xe1%2C0x09%2C0x34%7D%7D%22%7D' }
          let(:options) { { obfuscate: :internal } }

          it { is_expected.to eq('json=%7B%20%22<redacted>%7D') }
        end

        context 'with a reduced show option overlapping with a potential obfuscation match' do
          let(:query) { 'pass=03cb9f67-dbbc-4cb8-b966-329951e10934&key2=val2&key3=val3' }
          let(:options) { { show: ['pass', 'key2'], obfuscate: :internal } }

          it { is_expected.to eq('<redacted>&key2=val2&key3') }
        end

        context 'with a reduced show option distinct from a potentail obfuscation match' do
          let(:query) { 'pass=03cb9f67-dbbc-4cb8-b966-329951e10934&key2=val2&key3=val3' }
          let(:options) { { show: ['key2'], obfuscate: :internal } }

          it { is_expected.to eq('pass&key2=val2&key3') }
        end

        context 'with an exclude option overlapping with a potential obfuscation match' do
          let(:query) { 'pass=03cb9f67-dbbc-4cb8-b966-329951e10934&key2=val2&key3=val3' }
          let(:options) { { exclude: ['key2'], obfuscate: :internal } }

          it { is_expected.to eq('<redacted>&key3=val3') }
        end

        context 'with an exclude option distinct from a potential obfuscation match' do
          let(:query) { 'pass=03cb9f67-dbbc-4cb8-b966-329951e10934&key2=val2&key3=val3' }
          let(:options) { { exclude: ['pass'], obfuscate: :internal } }

          it { is_expected.to eq('key2=val2&key3=val3') }
        end
      end

      context 'and an obfuscate with custom options' do
        context 'with regex: :internal' do
          let(:query) { 'pass=03cb9f67-dbbc-4cb8-b966-329951e10934&key2=val2&key3=val3' }
          let(:options) { { obfuscate: { regex: :internal } } }

          it { is_expected.to eq('<redacted>&key2=val2&key3=val3') }
        end

        context 'with a custom regex' do
          let(:query) { 'pass=03cb9f67-dbbc-4cb8-b966-329951e10934&key2=val2&key3=val3' }
          let(:options) { { obfuscate: { regex: /key2=[^&]+/ } } }

          it { is_expected.to eq('pass=03cb9f67-dbbc-4cb8-b966-329951e10934&<redacted>&key3=val3') }
        end

        context 'with a custom replacement' do
          let(:query) { 'pass=03cb9f67-dbbc-4cb8-b966-329951e10934&key2=val2&key3=val3' }
          let(:options) { { obfuscate: { with: 'NOPE' } } }

          it { is_expected.to eq('NOPE&key2=val2&key3=val3') }
        end

        context 'with an empty replacement' do
          let(:query) { 'pass=03cb9f67-dbbc-4cb8-b966-329951e10934&key2=val2&key3=val3' }
          let(:options) { { obfuscate: { with: '' } } }

          it { is_expected.to eq('&key2=val2&key3=val3') }
        end
      end
    end
  end
end
