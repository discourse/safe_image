# frozen_string_literal: true

require "rbconfig"
require "shellwords"

helper = "safe_image_vips_helper"
source = "safe_image_vips_helper.c"
lib_dir = File.expand_path("../../lib/safe_image", __dir__)
installed_helper = File.join(lib_dir, helper)

cflags =
  [ENV["CFLAGS"] || RbConfig::CONFIG["CFLAGS"], RbConfig::CONFIG["CPPFLAGS"], "$(VIPS_CFLAGS)"].compact.join(" ")
ldflags = [ENV["LDFLAGS"] || RbConfig::CONFIG["LDFLAGS"]].compact.join(" ")
pkg_config = ENV.fetch("PKG_CONFIG", "pkg-config")
make_pkg_config = pkg_config.shellescape.gsub("$", "$$")

File.write(
  "Makefile",
  <<~MAKEFILE
    SHELL = /bin/sh
    CC = #{RbConfig::CONFIG.fetch("CC")}
    CFLAGS = #{cflags}
    LDFLAGS = #{ldflags}
    PKG_CONFIG = #{make_pkg_config}
    VIPS_CFLAGS = $(shell $(PKG_CONFIG) --cflags vips 2>/dev/null)
    VIPS_LIBS = $(shell $(PKG_CONFIG) --libs vips 2>/dev/null)
    LIBS = $(VIPS_LIBS) -lm
    INSTALL = #{RbConfig::CONFIG.fetch("INSTALL", "install")}

    .PHONY: all install clean distclean

    all: #{helper}

    #{helper}: #{source}
    	rm -f #{helper}
    	if $(PKG_CONFIG) --exists vips >/dev/null 2>&1; then \
    		$(CC) $(CFLAGS) -o #{helper} #{source} $(LDFLAGS) $(LIBS) || { \
    			echo "safe_image: warning: failed to compile optional libvips helper; install will continue without vips backend support" >&2; \
    			rm -f #{helper}; \
    		}; \
    	else \
    		echo "safe_image: warning: pkg-config could not find libvips; install will continue without vips backend support" >&2; \
    	fi

    install: all
    	mkdir -p #{lib_dir.shellescape}
    	if [ -x #{helper} ]; then \
    		cp #{helper} #{installed_helper.shellescape}; \
    		chmod 0755 #{installed_helper.shellescape}; \
    	else \
    		rm -f #{installed_helper.shellescape}; \
    		echo "safe_image: warning: optional libvips helper was not installed; configure!(backend: :vips) will raise" >&2; \
    	fi

    clean:
    	rm -f #{helper} *.o

    distclean: clean
    	rm -f Makefile
  MAKEFILE
)
