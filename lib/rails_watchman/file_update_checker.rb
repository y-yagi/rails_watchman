require "pathname"
require "set"
require "concurrent/atomic/atomic_boolean"

module RailsWatchman
  class FileUpdateChecker
    def initialize(files, dirs = {}, &block)
      unless block
        raise ArgumentError, "A block is required"
      end

      @updated = Concurrent::AtomicBoolean.new(false)
      @block = block
      subscription_name = "rails_watchman_file_update_checker_#{object_id}"
      @controller = RailsWatchman::Controller.instance
      @controller.subscribe!(files: files, dirs: dirs, subscription_name: subscription_name) { @updated.make_true }
    end

    def updated?
      @updated.true?
    end

    def execute
      @updated.make_false
      @block.call
    end

    def execute_if_updated
      if updated?
        yield if block_given?
        execute
        true
      end
    end
  end
end
