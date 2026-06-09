# frozen_string_literal: true

require "socket"

# Minimal loopback HTTP server serving canned responses, so the remote
# metadata helpers can be exercised without real network access.
#
# Routes map a request path to either { content_type:, body: } for a 200
# response or { redirect: } for a 302.
class StubImageServer
  attr_reader :port

  def initialize(routes)
    @routes = routes
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @running = true
    @thread = Thread.new { serve }
  end

  def url(path)
    "http://127.0.0.1:#{@port}#{path}"
  end

  def shutdown
    @running = false
    @server.close
    @thread.join
  end

  private

  def serve
    while @running
      socket = nil
      begin
        socket = @server.accept
        respond(socket, read_request_path(socket))
      rescue IOError, Errno::EBADF
        break
      ensure
        socket&.close
      end
    end
  end

  def read_request_path(socket)
    request_line = socket.gets.to_s
    while (line = socket.gets)
      break if line == "\r\n"
    end
    request_line.split[1].to_s
  end

  def respond(socket, path)
    route = @routes[path]
    if route.nil?
      socket.write "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    elsif route[:redirect]
      socket.write "HTTP/1.1 302 Found\r\nLocation: #{route[:redirect]}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    else
      body = route.fetch(:body)
      socket.write "HTTP/1.1 200 OK\r\nContent-Type: #{route.fetch(:content_type)}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n"
      socket.write body
    end
  end
end
