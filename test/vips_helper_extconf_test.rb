# frozen_string_literal: true

require "open3"
require "fileutils"
require "shellwords"
require_relative "test_helper"

module SafeImage
  class VipsHelperExtconfTest < TestCase
    def setup
      # This test exercises extconf in isolation and must not require a working
      # installed helper on the host running it.
    end

    def test_extconf_install_succeeds_without_libvips
      with_extconf_dir do |dir, ext_dir|
        env = { "PKG_CONFIG" => File.join(dir, "missing-pkg-config") }
        stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, "extconf.rb", chdir: ext_dir)
        assert status.success?, "extconf failed unexpectedly:\nstdout:\n#{stdout}\nstderr:\n#{stderr}"

        stdout, stderr, status = Open3.capture3(env, "make", "install", chdir: ext_dir)
        assert status.success?, "make install failed unexpectedly:\nstdout:\n#{stdout}\nstderr:\n#{stderr}"
        assert_match(/without vips backend support/, stderr)
        refute_path_exists File.join(dir, "lib", "safe_image", "safe_image_vips_helper")
      end
    end

    def test_extconf_install_succeeds_when_helper_compile_fails
      with_extconf_dir do |dir, ext_dir|
        pkg_config = File.join(dir, "fake-pkg-config")
        File.write(pkg_config, <<~SH)
          #!/bin/sh
          case "$1" in
            --exists) exit 0 ;;
            --cflags|--libs) exit 0 ;;
          esac
          exit 1
        SH
        FileUtils.chmod(0o755, pkg_config)

        installed_helper = File.join(dir, "lib", "safe_image", "safe_image_vips_helper")
        FileUtils.mkdir_p(File.dirname(installed_helper))
        File.write(installed_helper, "stale helper")

        env = { "PKG_CONFIG" => pkg_config, "CFLAGS" => "-fno-such-safe-image-flag" }
        stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, "extconf.rb", chdir: ext_dir)
        assert status.success?, "extconf failed unexpectedly:\nstdout:\n#{stdout}\nstderr:\n#{stderr}"

        stdout, stderr, status = Open3.capture3(env, "make", "install", chdir: ext_dir)
        assert status.success?, "make install failed unexpectedly:\nstdout:\n#{stdout}\nstderr:\n#{stderr}"
        assert_match(/failed to compile optional libvips helper/, stderr)
        assert_match(/configure!\(backend: :vips\) will raise/, stderr)
        refute_path_exists installed_helper, "stale helper should be removed when the optional helper is skipped"
      end
    end

    def test_extconf_escapes_pkg_config_path_for_make
      with_extconf_dir do |dir, ext_dir|
        pkg_config_dir = File.join(dir, "pkg config $bin")
        FileUtils.mkdir_p(pkg_config_dir)
        invocation_marker = File.join(dir, "pkg-config-was-run")
        pkg_config = File.join(pkg_config_dir, "fake-pkg#config")
        File.write(pkg_config, <<~SH)
          #!/bin/sh
          touch #{invocation_marker.shellescape}
          exit 1
        SH
        FileUtils.chmod(0o755, pkg_config)

        env = { "PKG_CONFIG" => pkg_config }
        stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, "extconf.rb", chdir: ext_dir)
        assert status.success?, "extconf failed unexpectedly:\nstdout:\n#{stdout}\nstderr:\n#{stderr}"

        stdout, stderr, status = Open3.capture3(env, "make", "install", chdir: ext_dir)
        assert status.success?, "make install failed unexpectedly:\nstdout:\n#{stdout}\nstderr:\n#{stderr}"
        assert_path_exists invocation_marker, "PKG_CONFIG path should be shell-escaped in the generated Makefile"
      end
    end

    private

    def with_extconf_dir
      Dir.mktmpdir("safe-image-extconf-") do |dir|
        ext_dir = File.join(dir, "ext", "safe_image_vips_helper")
        FileUtils.mkdir_p(ext_dir)
        FileUtils.cp(File.expand_path("../ext/safe_image_vips_helper/extconf.rb", __dir__), ext_dir)
        FileUtils.cp(File.expand_path("../ext/safe_image_vips_helper/safe_image_vips_helper.c", __dir__), ext_dir)

        yield dir, ext_dir
      end
    end
  end
end
