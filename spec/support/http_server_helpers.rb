require 'webrick'

module HttpServerHelpers
  module ClassMethods
    def http_server(&block)
      let(:http_server_port) { http_server[:Port] }

      let(:http_server) do
        WEBrick::HTTPServer.new(
          Port: 0,
        ).tap do |http_server|
          instance_exec(http_server,&block)
        end
      end

      around do |example|
        @server_thread = Thread.new do
          http_server.start
        end
        loop do
          break if http_server.status == :Running || !@server_thread.alive?
          sleep 0.5
        end
        expect(@server_thread).to be_alive
        example.run
        @server_thread.kill
        loop do
          break unless @server_thread.alive?
          sleep 0.5
        end
      end
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end
end
