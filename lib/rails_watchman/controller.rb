require "ruby-watchman"
require "socket"
require "pathname"
require "set"
require "singleton"

module RailsWatchman
  class Controller
    include Singleton

    def initialize
      @subscriptions = {}
      @recv_thread = nil
      @socket = nil
    end

    def watch!(dirs:)
      roots = RubyWatchman.query(["watch-list"], socket)["roots"]
      (Array(dirs) - roots).each do |dir|
        result = RubyWatchman.query(["watch", dir], socket)
        raise "Watch failed #{result["error"]}" if result.has_key?("error")
      end
    end

    def unwatch!(dirs:)
      dirs.each do |dir|
        result = RubyWatchman.query(["watch-del", dir], socket)
        raise "Delete watching failed #{result["error"]}" if result.has_key?("error")
      end
    end

    def subscribe!(files: [], dirs: {}, subscription_name:, &block)
      roots = RubyWatchman.query(["watch-list"], socket)["roots"]
      paths_with_root = {}

      (dirs.keys + files).map do |path|
        root = roots.detect { |root| path.start_with?(root) }
        raise ArgumentError.new("'#{path}' can't subscribe because the path doesn't watch") if root.nil?
        paths_with_root[path] = root
      end

      paths_with_root.each do |path, root|
        p = Pathname.new(path)
        relative_path = p.to_s[root.size + 1, p.to_s.size]
        relative_path = File.join(relative_path, "/") unless relative_path.nil?
        if p.directory?
          expression = ["anyof"]
          Array(dirs[path]).each do |pattern|
            expression << ["match", "#{relative_path}**/*.#{pattern}", "wholename"]
          end
          result = RubyWatchman.query(['subscribe', root, subscription_name, { "fields" => ["name"], "expression" => expression } ], socket)
        else
          result = RubyWatchman.query(["subscribe", root, subscription_name, { "fields" => ["name"], "expression" => ["name", relative_path, "wholename"] } ], socket)
        end
        raise "'#{path}' subscribe failed #{result["error"]}" if result.include?("error")
        socket.recvmsg
      end

      @subscriptions[subscription_name] = block
      recvmsg
    end

    def terminate
      @recv_thread.kill if !@recv_thread.nil? && @recv_thread.alive?
      @socket.close if !@socket.nil? && !@socket.closed?
    end

    private

    def recvmsg
      return if !@recv_thread.nil? && @recv_thread.alive?

      @recv_thread = Thread.new do
        loop do
          begin
            msg = socket.recvmsg()[0]
            result = RubyWatchman.load(msg)
            @subscriptions[result["subscription"]]&.call
          rescue ArgumentError
          end
        end
      end
    end

    def socket
      return @socket if !@socket.nil? && !@socket.closed?

      # TODO: Allow to specify the path of `watchman`.
      @socket = begin
        sockname = RubyWatchman.load(
          %x{watchman --output-encoding=bser get-sockname}
        )["sockname"]
        raise "Can't connect to 'watchman'" unless $?.exitstatus.zero?

        UNIXSocket.open(sockname)
      end
    end
  end
end
