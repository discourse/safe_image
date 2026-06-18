# frozen_string_literal: true

require "bundler"
require "rake/testtask"
require "shellwords"

begin
  Bundler.setup :default, :development
  Bundler::GemHelper.install_tasks
rescue Bundler::BundlerError => error
  warn error.message
  warn "Run `bundle install` to install missing gems"
  exit error.status_code
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
end

formattable_ruby_files = FileList["Gemfile", "Rakefile", "*.gemspec", "{lib,test,bench}/**/*.rb"].to_a.freeze
formattable_c_files = FileList["ext/**/*.{c,h}"].to_a.freeze
stree_print_width = 120
clang_format = ENV.fetch("CLANG_FORMAT", "clang-format")

namespace :format do
  desc "Check Ruby/C formatting"
  task :check do
    sh "bundle exec stree check --print-width=#{stree_print_width} #{formattable_ruby_files.map(&:shellescape).join(" ")}"
    sh "#{clang_format.shellescape} --dry-run --Werror #{formattable_c_files.map(&:shellescape).join(" ")}"
  end
end

desc "Format Ruby/C files"
task :format do
  sh "bundle exec stree write --print-width=#{stree_print_width} #{formattable_ruby_files.map(&:shellescape).join(" ")}"
  sh "#{clang_format.shellescape} -i #{formattable_c_files.map(&:shellescape).join(" ")}"
end

namespace :fuzz do
  desc "Run deterministic SVG fuzz tests. Tune with SAFE_IMAGE_FUZZ_SEEDS and *_FUZZ_* env vars."
  Rake::TestTask.new(:svg) do |t|
    t.libs << "test"
    t.test_files = FileList["test/svg_*fuzz_test.rb"]
  end
end

task default: :test
