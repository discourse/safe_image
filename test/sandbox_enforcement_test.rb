# frozen_string_literal: true

require "open3"
require_relative "test_helper"

module SafeImage
  # configure!(landlock: true) must raise when the Landlock sandbox is
  # unavailable rather than silently configuring inline execution.
  #
  # Exercised in a child process with RubyGems disabled (plus explicit load
  # paths for the gem's runtime deps), so the landlock gem is genuinely
  # unloadable there — no stubbing, and no skip on hosts where landlock is
  # bundled for SandboxIntegrationTest.
  class SandboxEnforcementTest < TestCase
    SCRIPT = <<~'RUBY'
      require "safe_image"
      abort "landlock unexpectedly loadable in the child" if SafeImage.sandbox_available?

      begin
        SafeImage.configure!(backend: :vips, landlock: true)
        print "no error"
      rescue SafeImage::Error => e
        print e.message
      end
    RUBY

    def test_configure_fails_closed_without_landlock
      # Bundler's RUBYOPT would re-add the full bundle (landlock included) to
      # the child's load path, so scrub it alongside disabling RubyGems.
      env = { "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLE_BIN_PATH" => nil }
      command = [RbConfig.ruby, "--disable-gems"]
      # With RubyGems disabled the child loses every gem's load path, including
      # the gem's own bundled runtime deps (rexml, and fiddle from Ruby 3.5 on,
      # which ships a C extension under its own load-path entries). Pass the
      # parent's load paths through so those deps resolve, but drop landlock so
      # it stays genuinely unloadable and sandbox_available? reports false.
      load_paths = [File.expand_path("../lib", __dir__), *$LOAD_PATH]
      load_paths.reject { |path| path.to_s.include?("landlock") }.uniq.each { |path| command += ["-I", path] }

      stdout, stderr, status = Open3.capture3(env, *command, "-e", SCRIPT)

      assert status.success?, "sandbox-less child process failed:\n#{stderr}"
      assert_includes stdout, "landlock: true requested"
    end
  end
end
