require "test_helper"
require "pathname"

class FileUpdateCheckerTest < Minitest::Test
  include FileUtils

  attr_reader :tmpdir

  def setup
    RailsWatchman::Controller.instance.watch!(dirs: [tmpdir])
  end

  def teardown
    RailsWatchman::Controller.instance.unwatch!(dirs: [tmpdir])
  end

  def tmpfile(name)
    File.join(tmpdir, name)
  end

  def tmpfiles
    @tmpfiles ||= %w(foo.rb bar.rb baz.rb).map { |f| tmpfile(f) }
  end

  def run(*args)
    capture_exceptions do
      Dir.mktmpdir(nil, __dir__) { |dir| @tmpdir = dir; super }
    end
  end

  def new_checker(files = [], dirs = {}, &block)
    RailsWatchman::FileUpdateChecker.new(files, dirs, &block).tap do |c|
      wait
    end
  end

  def wait
    sleep 1
  end

  def touch(files)
    FileUtils.touch(files)
    wait
  end

  def test_should_not_execute_the_block_if_no_paths_are_given
    i = 0

    checker = new_checker { i += 1 }

    refute checker.execute_if_updated
    assert_equal 0, i
  end

  def test_should_not_execute_the_block_if_no_files_change
    i = 0

    touch(tmpfiles)

    checker = new_checker(tmpfiles) { i += 1 }

    refute checker.execute_if_updated
    assert_equal 0, i
  end

  def test_should_execute_the_block_once_when_files_are_created
    i = 0

    checker = new_checker(tmpfiles) { i += 1 }

    touch(tmpfiles[0])
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_should_execute_the_block_once_when_files_are_modified
    i = 0

    touch(tmpfiles)

    checker = new_checker(tmpfiles) { i += 1 }

    touch(tmpfiles[0])
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_should_execute_the_block_once_when_files_are_deleted
    i = 0

    touch(tmpfiles)

    checker = new_checker(tmpfiles) { i += 1 }

    rm_f(tmpfiles)
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_updated_should_become_true_when_watched_files_are_created
    i = 0

    checker = new_checker(tmpfiles) { i += 1 }
    refute_predicate checker, :updated?

    touch(tmpfiles[0])
    wait

    assert_predicate checker, :updated?
  end

  def test_updated_should_become_true_when_watched_files_are_modified
    i = 0

    touch(tmpfiles)

    checker = new_checker(tmpfiles) { i += 1 }
    refute_predicate checker, :updated?

    touch(tmpfiles[0])
    wait

    assert_predicate checker, :updated?
  end

  def test_updated_should_become_true_when_watched_files_are_deleted
    i = 0

    touch(tmpfiles)

    checker = new_checker(tmpfiles) { i += 1 }
    refute_predicate checker, :updated?

    rm_f(tmpfiles)
    wait

    assert_predicate checker, :updated?
  end

  def test_should_be_robust_to_handle_files_with_wrong_modified_time
    i = 0

    touch(tmpfiles)

    now  = Time.now
    time = Time.mktime(now.year + 1, now.month, now.day)
    File.utime(time, time, tmpfiles[0])

    checker = new_checker(tmpfiles) { i += 1 }

    touch(tmpfiles[1..-1])
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_should_return_max_time_for_files_with_mtime_zero
    i = 0

    touch(tmpfiles)

    time = Time.at(0) # wrong mtime from the future
    File.utime(time, time, tmpfiles[0])

    checker = new_checker(tmpfiles) { i += 1 }

    touch(tmpfiles[1..-1])
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_should_cache_updated_result_until_execute
    i = 0

    checker = new_checker(tmpfiles) { i += 1 }
    refute_predicate checker, :updated?

    touch(tmpfiles[0])
    wait

    assert_predicate checker, :updated?
    checker.execute
    refute_predicate checker, :updated?
  end

  def test_should_execute_the_block_if_files_change_in_a_watched_directory_one_extension
    i = 0

    checker = new_checker([], tmpdir => :rb) { i += 1 }

    touch(tmpfile("foo.rb"))
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_should_execute_the_block_if_files_change_in_a_watched_directory_any_extensions
    i = 0

    checker = new_checker([], tmpdir => []) { i += 1 }

    touch(tmpfile("foo.rb"))
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_should_execute_the_block_if_files_change_in_a_watched_directory_several_extensions
    i = 0

    checker = new_checker([], tmpdir => [:rb, :txt]) { i += 1 }

    touch(tmpfile("foo.rb"))
    wait

    assert checker.execute_if_updated
    assert_equal 1, i

    touch(tmpfile("foo.txt"))
    wait

    assert checker.execute_if_updated
    assert_equal 2, i
  end

  def test_should_not_execute_the_block_if_the_file_extension_is_not_watched
    i = 0

    checker = new_checker([], tmpdir => :txt) { i += 1 }

    touch(tmpfile("foo.rb"))
    wait

    refute checker.execute_if_updated
    assert_equal 0, i
  end

  def test_es_not_assume_files_exist_on_instantiation
    i = 0

    non_existing = tmpfile("non_existing.rb")
    checker = new_checker([non_existing]) { i += 1 }

    touch(non_existing)
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_detects_files_in_new_subdirectories
    i = 0

    checker = new_checker([], tmpdir => :rb) { i += 1 }

    subdir = tmpfile("subdir")
    mkdir(subdir)
    wait

    refute checker.execute_if_updated
    assert_equal 0, i

    touch(File.join(subdir, "nested.rb"))
    wait

    assert checker.execute_if_updated
    assert_equal 1, i
  end

  def test_looked_up_extensions_are_inherited_in_subdirectories_not_listening_to_them
    i = 0

    subdir = tmpfile("subdir")
    mkdir(subdir)

    checker = new_checker([], tmpdir => :rb, subdir => :txt) { i += 1 }

    touch(tmpfile("new.txt"))
    wait

    refute checker.execute_if_updated
    assert_equal 0, i

    touch(File.join(subdir, "nested.rb"))
    wait

    assert checker.execute_if_updated
    assert_equal 1, i

    touch(File.join(subdir, "nested.txt"))
    wait

    assert checker.execute_if_updated
    assert_equal 2, i
  end

  def test_initialize_raises_error_if_no_block_given
    assert_raises { new_checker([]) }
  end
end
