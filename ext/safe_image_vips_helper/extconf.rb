# frozen_string_literal: true

require "mkmf"
require "rbconfig"

pkg_config("vips") or abort "libvips development files are required (pkg-config vips failed)"

pkg_cflags = `pkg-config --cflags vips`.strip
pkg_libs = `pkg-config --libs vips`.strip
cflags = [ENV["CFLAGS"] || RbConfig::CONFIG["CFLAGS"], RbConfig::CONFIG["CPPFLAGS"], pkg_cflags].compact.join(" ")
ldflags = [ENV["LDFLAGS"] || RbConfig::CONFIG["LDFLAGS"]].compact.join(" ")

helper = "safe_image_vips_helper"
source = "safe_image_vips_helper.c"
lib_dir = File.expand_path("../../lib/safe_image", __dir__)

File.write(
  "Makefile",
  <<~MAKEFILE
    SHELL = /bin/sh
    CC = #{RbConfig::CONFIG.fetch("CC")}
    CFLAGS = #{cflags}
    LDFLAGS = #{ldflags}
    LIBS = #{pkg_libs} -lm
    INSTALL = #{RbConfig::CONFIG.fetch("INSTALL", "install")}

    all: #{helper}

    #{helper}: #{source}
    	$(CC) $(CFLAGS) -o #{helper} #{source} $(LDFLAGS) $(LIBS)

    install: #{helper}
    	mkdir -p #{lib_dir}
    	cp #{helper} #{File.join(lib_dir, helper)}
    	chmod 0755 #{File.join(lib_dir, helper)}

    clean:
    	rm -f #{helper} *.o

    distclean: clean
    	rm -f Makefile
  MAKEFILE
)
