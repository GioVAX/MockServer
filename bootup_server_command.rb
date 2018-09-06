require 'rack'

class BootupServerCommand
  def initialize(host, port)
    @host = host
    @port = port
  end

  def execute
    @thread = Thread.new { Rack::Server.start(app: MockBackend::API, Host: @host, Port: @port, AccessLog: []) }
  end

  def close
    @thread.exit
  end
end
