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

        it { is_expected.to eq(format('http://example.com/%s', described_class::PLACEHOLDER)) }

        context 'and base: :exclude' do
          let(:options) { { base: :exclude } }

          it { is_expected.to eq(described_class::PLACEHOLDER) }
        end
      end

      context 'with unencoded ASCII characters' do
        # URLs do not permit all ASCII characters to be unencoded in the URL.
        let(:url) { 'http://example.com/|' }

        it { is_expected.to eq(format('http://example.com/%s', described_class::PLACEHOLDER)) }

        context 'and base: :exclude' do
          let(:options) { { base: :exclude } }

          it { is_expected.to eq(described_class::PLACEHOLDER) }
        end
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

  describe '#base_url' do
    subject(:result) { described_class.base_url(url, options) }

    let(:options) { {} }

    context 'given a URL' do
      let(:url) { 'http://example.com/path?category_id=1&sort_by=asc#featured' }

      context 'default behavior' do
        it { is_expected.to eq('http://example.com') }
      end

      context 'with Unicode characters' do
        # URLs do not permit unencoded non-ASCII characters in the URL.
        let(:url) { 'http://example.com/path?繋がってて' }

        it { is_expected.to eq('http://example.com') }
      end

      context 'with unencoded ASCII characters' do
        # URLs do not permit all ASCII characters to be unencoded in the URL.
        let(:url) { 'http://example.com/|' }

        it { is_expected.to eq('http://example.com') }
      end

      context 'without a base' do
        let(:url) { '/foo' }

        it { is_expected.to eq('') }
      end

      context 'that is entirely invalid' do
        let(:url) { "\x00" }

        it { is_expected.to eq('') }
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
          let(:query) { 'key1=val1&pass=03cb9f67-dbbc-4cb8-b966-329951e10934&key2=val2&token=03cb9f67dbbc4cb8b966329951e10934&public_key=MDNjYjlmNjctZGJiYy00Y2I4LWI5NjYtMzI5OTUxZTEwOTM0&key3=val3&json=%7B%20%22sign%22%3A%20%22%7B0x03cb9f67%2C0xdbbc%2C0x4cb8%2C%7B0xb9%2C0x66%2C0x32%2C0x99%2C0x51%2C0xe1%2C0x09%2C0x34%7D%7D%22%7D' } # rubocop:disable Metrics/LineLength
          let(:options) { { obfuscate: :internal } }

          it { is_expected.to eq('key1=val1&<redacted>&key2=val2&<redacted>&<redacted>&key3=val3&json=%7B%20<redacted>%7D') } # rubocop:disable Metrics/LineLength
        end

        context 'with a matching, URL-encoded JSON substring' do
          let(:query) { 'json=%7B%20%22sign%22%3A%20%22%7B0x03cb9f67%2C0xdbbc%2C0x4cb8%2C%7B0xb9%2C0x66%2C0x32%2C0x99%2C0x51%2C0xe1%2C0x09%2C0x34%7D%7D%22%7D' } # rubocop:disable Metrics/LineLength
          let(:options) { { obfuscate: :internal } }

          it { is_expected.to eq('json=%7B%20<redacted>%7D') }
        end

        context 'with a reduced show option overlapping with a potential obfuscation match' do
          let(:query) { 'pass=03cb9f67-dbbc-4cb8-b966-329951e10934&key2=val2&key3=val3' }
          let(:options) { { show: %w[pass key2], obfuscate: :internal } }

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

  describe 'OBFUSCATOR_REGEX' do
    let(:regex) { described_class::OBFUSCATOR_REGEX }

    key_matches = %w[
      pwd
      passwd
      password
      oldpassword
      newpassword
      old_password
      new_password
      password1
      password2
      pass
      passphrase
      secret
      apikey
      apikeyid
      privatekey
      privatekeyid
      publickeyid
      accesskeyid
      secretkeyid
      api_key
      api_key_id
      private_key
      private_key_id
      public_key_id
      access_key_id
      secret_key_id
      token
      consumerid
      consumerkey
      consumersecret
      consumer_id
      consumer_key
      consumer_secret
      sign
      signed
      signature
      auth
      authentication
      authorization
    ]

    # rubocop:disable Layout/LineLength
    value_matches = {
      'OpenSSH RSA private key' => <<~DUMMY,
      -----BEGIN OPENSSH PRIVATE KEY-----
      b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABlwAAAAdzc2gtcn
      NhAAAAAwEAAQAAAYEAsZH8CwhvSFt9sDfnW8rNST9akUwPUEZ/F52Xa+SK8+8hlwpD46+3
      udRf7+930ZOBTp2kYx2q7YppbG+DaIGjTdXJZB5L60b4x8k8xgTP1oLphHXKNAMuB/wXci
      cCzcPPIlBlTNx/d7Pqz+WvLuD7ZOB2ctZUlgI4OdmYWL91fnMkDY3x4jrh5NpQoZrUxNRZ
      Sn3PKZMQeEJ8htxG0KxA80ZMpvDU5b2SGjr9NVXbJkV1rq4oCPQJ6oKAON3g9yalrMI8gp
      Jkp51t4fvYgeG4Ea0iE9kAboKSB1TOKW5E+FK5aXFRHgM4mDTwuB+tZbl9Hdf6jp7WjBTL
      bySrhv9yY/LdfTvp0k2va3vj80uUJvCf+8c2scTiKveA+xZxjxuSYnyeFmUVhdDw6bTl2y
      WO9mLpm/sWiba/S5an0unyc1pAOvD0/2WhJOSYGjx4Zb1L5seSZZj+7tnhXGzR6R0B6CHy
      Y15PCdxA145eUaehPSsQEQ96eOUofG+C6FUfGdPpAAAFgKX3mGal95hmAAAAB3NzaC1yc2
      EAAAGBALGR/AsIb0hbfbA351vKzUk/WpFMD1BGfxedl2vkivPvIZcKQ+Ovt7nUX+/vd9GT
      gU6dpGMdqu2KaWxvg2iBo03VyWQeS+tG+MfJPMYEz9aC6YR1yjQDLgf8F3InAs3DzyJQZU
      zcf3ez6s/lry7g+2TgdnLWVJYCODnZmFi/dX5zJA2N8eI64eTaUKGa1MTUWUp9zymTEHhC
      fIbcRtCsQPNGTKbw1OW9kho6/TVV2yZFda6uKAj0CeqCgDjd4PcmpazCPIKSZKedbeH72I
      HhuBGtIhPZAG6CkgdUziluRPhSuWlxUR4DOJg08LgfrWW5fR3X+o6e1owUy28kq4b/cmPy
      3X076dJNr2t74/NLlCbwn/vHNrHE4ir3gPsWcY8bkmJ8nhZlFYXQ8Om05dsljvZi6Zv7Fo
      m2v0uWp9Lp8nNaQDrw9P9loSTkmBo8eGW9S+bHkmWY/u7Z4Vxs0ekdAegh8mNeTwncQNeO
      XlGnoT0rEBEPenjlKHxvguhVHxnT6QAAAAMBAAEAAAGBAKXhABi2am6nuURzFNf1Hcy9OD
      ffW7bcBEHlX9zUhNHXpANa/YynS/R25qBXjhDjwLnWHgjRYCnDUTSQ/6sS36EIg7fZbYZ+
      qEzKOtGpERcM+GRbPOdVyRyAbM6gjsf1kXw2qksg+Jq0IjjQEdSzK2VTIpOokSAJNskj8m
      OFh5b2rMlUvo9d/kQxhX1SDE1LKZai7HGkBpCxW28IO8cYAxy/oT+aXue3LdL/JCc86xpX
      bNYfrxqeDt1Zx7pX255GJJPtuB3amp+PglRnPuSk91DlhpgBW7ZqHmPQR7LLV517vMhP4+
      rTsoZaEBBI/S4hLHfeseMiPUD5wqidzrvjdk7+q35g+2hO61qiGgoglSDV2L9mjm2Lk4yg
      7LbcYr9X8ckVbrJOTC5H9cuMRHygzQCR9rVNPrurwDMZ+JUYJtASEZitZ1lBxRAsouce+B
      6ztuRhheXFWYhwdehaMHaUxvUrtO/Vvnv4FvtoGlXyQUcRVNmZCQu+rmtzPZkNqIqv4QAA
      AMEAhrSKxvyqoKejFbBhLRkQyVZU6h1j/hrOzYjcsTd5IcCixA3R+q/ikmwP4HnyI8vdq6
      Co5yY8nQ2YlnlmZ450wjEj6Rgh02/SUHV3JEl9ii7OUhsXmd3/FjX2SeVMFnpa7B1OWgST
      lIH2d25qwyIWYCwN8es7MS4xi+boGRPKNI6v0PMxp8aK+5zwyRaNbmjt098VUE3zsBqyxX
      oXym2ewZ10UUJzEkQ42HsFZAYdGVVr3oOLSzHixM3szR0USWkFAAAAwQDfslAAUCFc2GzC
      t2fLP9GKTJn6t/m+q6yc7PSkgKaTfMVCouIwOQ02GShF+nXBfyhnwaRinOTqQ6eaOv6d0Z
      prFI4mEeNdAcVQgFuYmnIs1a6hSTC5xNDa0IwSJeV0em+GKOdy/uwZPtjK41C1hKU+eyhz
      QAr5wTuesEiympm7B9kfX3GkaK365A7so3qkjfI4KJ/OztIbvrE/I61HApQdgLZFBfIGen
      Cmf9/y9CdT/CeMJ5Mdb3ZptPgo/qJh+IUAAADBAMs2dd1Yf4NtqV6V37MHT3wxNR9TgaQI
      FYDS9xHS44tMyFZsKsJNv1MaU3q6005L5iopMjp5nevzZXiquK/u+EBeNjJoITssGl7EWc
      eb74Rbv91GoKI++DcArG/fRVzLbnmDUy++LjBH+x6Z2fQ9WDRmvc8BD2OGPJpd433OJ7yo
      mgbkEHHoCn9BfsRmX4UBZbUs/ft96m59q1TfzJv+OO3eZsNvum3fzEej+8O/sqPVqr8BEL
      nN0N+h0y2dlTH9FQAAAAVkdW1teQECAwQ=
      -----END OPENSSH PRIVATE KEY-----
      DUMMY
      'OpenSSH RSA public key' => 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCxkfwLCG9IW32wN+dbys1JP1qRTA9QRn8XnZdr5Irz7yGXCkPjr7e51F/v73fRk4FOnaRjHartimlsb4NogaNN1clkHkvrRvjHyTzGBM/WgumEdco0Ay4H/BdyJwLNw88iUGVM3H93s+rP5a8u4Ptk4HZy1lSWAjg52ZhYv3V+cyQNjfHiOuHk2lChmtTE1FlKfc8pkxB4QnyG3EbQrEDzRkym8NTlvZIaOv01VdsmRXWurigI9AnqgoA43eD3JqWswjyCkmSnnW3h+9iB4bgRrSIT2QBugpIHVM4pbkT4UrlpcVEeAziYNPC4H61luX0d1/qOntaMFMtvJKuG/3Jj8t19O+nSTa9re+PzS5Qm8J/7xzaxxOIq94D7FnGPG5JifJ4WZRWF0PDptOXbJY72Yumb+xaJtr9LlqfS6fJzWkA68PT/ZaEk5JgaPHhlvUvmx5JlmP7u2eFcbNHpHQHoIfJjXk8J3EDXjl5Rp6E9KxARD3p45Sh8b4LoVR8Z0+k= dummy',
      'OpenSSH DSA public key' => 'ssh-dss AAAAB3NzaC1kc3MAAACBALLggHdugwXVQTPHPZh2WqMEkcx0q3EY3j3f31QAVb4GCZpE3up8Hl7rg+wM5OwL9RchtQ/OpI+xwa4McwBL0vj1VXjCx3a0jhMljFSKZtekRZznpJc++wEZmRbhuzesOzYjMk903xehqbNZiJVGq1xuo/BsIHX4+HVeNVyUiowXAAAAFQCe1bNGoXBrB8ig6+zCAhT7TCROOQAAAIA2K5vaYf1kMw9maY6UC7lNHNh+V3ffgOHguh0037598t9PbIqBPUQfwBnCGwMMskt1fsMnV5Drc4Bbhc91LdaGMYYaQnZzeiJgLxwO4dlPvt0UlFZTYpFEPfoguCDIOgQbFvHo926LaZnqNUiURM/iGH/UJ2kULOTDKjbI1pSi5AAAAIBY8bcba06SeH1hVh/UD/5akTLdonS/3rwB6ofUGAHFiS2LhahMHOaozKRgI2Wp/+NNRjxQs4vaE4ahU57jZ/sBDQ3OdwOULbZCQp6KaL+IM6OT5Xue2/bt0fUwn/T7hZ41GXv6HVfojB5MQG8rEpcYf1xBwbUkmWysw04gnjUR7w== dummy',
      'OpenSSH ECDSA public key' => 'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBJX/IRZ4icqvJ8OpEDMs5X566bilqX6u6XEF/f/llF4YmiiSpo6cTVzl/2L9HXSfOlwuzVyRFaLpMWEUE3az0PI= dummy'
    }
    # rubocop:enable Layout/LineLength

    key_matches.each do |key|
      context "given query string key #{key.inspect} and its value" do
        let(:str) { format('%<key>s=foo', { key: key }) }

        it 'matches key and value' do
          expect(regex).to match(str)
        end

        it 'substitutes the whole string' do
          expect(str.gsub(regex, '')).to eq ''
        end
      end

      context "given JSON-ish key #{key.inspect} and its value" do
        let(:str) { format('"%<key>s": "foo"', { key: key }) }

        it 'matches key and value' do
          expect(regex).to match(str)
        end

        it 'substitutes the whole string' do
          expect(str.gsub(regex, '')).to eq ''
        end
      end
    end

    value_matches.each do |name, val|
      context "given #{name} value" do
        let(:str) { val }

        it 'matches value' do
          expect(regex).to match(str)
        end

        it 'substitutes the whole string' do
          expect(str.gsub(regex, '')).to eq ''
        end
      end
    end
  end
end
