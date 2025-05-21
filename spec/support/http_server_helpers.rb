require 'webrick'

module HttpServerHelpers
  module ClassMethods
    def define_http_server(base_http_server_options = {}, &block)
      # If you wish to override any of the following let blocks, be sure
      # you do so AFTER calling +http_server+.

      let(:http_server_port) { http_server[:Port] }
      let(:http_server_init_signal) { Queue.new }

      # Additional options to pass to the Webrick server.
      # To change log destination, override +http_server_log+ or
      # +http_server_log_buffer+ or +http_server_access_log+.
      let(:http_server_options) do
        {}
      end

      let(:http_server_log_buffer) do
        StringIO.new # set to $stderr to debug
      end
      let(:http_server_log) do
        WEBrick::Log.new(http_server_log_buffer, WEBrick::Log::DEBUG)
      end
      let(:http_server_access_log) do
        [[http_server_log_buffer, WEBrick::AccessLog::COMBINED_LOG_FORMAT]]
      end

      let(:http_server) do
        options = {
          Logger: http_server_log,
          AccessLog: http_server_access_log,
          Port: 0,
          StartCallback: -> { http_server_init_signal.push(1) }
        }.update(base_http_server_options).update(http_server_options)
        WEBrick::HTTPServer.new(options).tap do |http_server|
          instance_exec(http_server, &block)
        end
      end
    end

    def http_server(&block)
      define_http_server(&block)

      around do |example|
        @server_thread = Thread.new do
          http_server.start
        rescue Exception # rubocop:disable Lint/RescueException
          http_server_init_signal.push(1)
          raise
        end
        http_server_init_signal.pop
        expect(@server_thread).to be_alive

        example.run

        http_server.shutdown
        @server_thread.join
      end
    end

    def define_http_server_uds(&block)
      let(:uds_temporary_directory) { Dir.mktmpdir }
      let(:uds_socket_path) { "#{uds_temporary_directory}/rspec_unix_domain_socket" }
      let(:uds_socket) { UNIXServer.new(uds_socket_path) } # Closing the socket is handled by webrick

      define_http_server(DoNotListen: true) do |http_server|
        http_server.listeners << uds_socket
        instance_exec(http_server, &block)
      end

      let(:uds_agent_base_url) { "unix://#{uds_socket_path}" }

      after do
        FileUtils.rm_f(uds_socket_path)
        begin
          FileUtils.remove_entry(uds_temporary_directory)
        rescue Errno::ENOENT => _e
          # Do nothing, it's ok
        end
      end
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end
end
