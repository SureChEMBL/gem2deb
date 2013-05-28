# Copyright © 2011, Lucas Nussbaum <lucas@debian.org>
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'gem2deb'
require 'gem2deb/installer'
require 'find'
require 'fileutils'

module Gem2Deb

  class DhRuby

    include Gem2Deb

    attr_accessor :verbose
    attr_accessor :installer_class

    def initialize
      @verbose = true
      @skip_checks = nil
      @installer_class = Gem2Deb::Installer
    end

    def clean
      puts "  Entering dh_ruby --clean" if @verbose

      package = packages.first
      installer = installer_class.new(package, '.')
      installer.verbose = self.verbose

      installer.run_make_clean_on_extensions

      puts "  Leaving dh_ruby --clean" if @verbose
    end

    def configure
      # puts "  Entering dh_ruby --configure" if @verbose
      # puts "  Leaving dh_ruby --configure" if @verbose
    end

    def build
      # puts "  Entering dh_ruby --build" if @verbose
      # puts "  Leaving dh_ruby --build" if @verbose
    end

    def test
      # puts "  Entering dh_ruby --test" if @verbose
      # puts "  Leaving dh_ruby --test" if @verbose
    end

    TEST_RUNNER = File.expand_path(File.join(File.dirname(__FILE__),'test_runner.rb'))

    def install(argv)
      puts "  Entering dh_ruby --install" if @verbose

      # FIXME supported_versions is passed a lot of times to the installer, it
      # should probably be an attribute of that class
      supported_versions =
        if all_ruby_versions_supported?
          SUPPORTED_RUBY_VERSIONS.keys.clone
        else
          ruby_versions.clone
        end

      package = packages.first
      installer = installer_class.new(package, '.', ruby_versions)
      installer.verbose = self.verbose
      installer.dh_auto_install_destdir = argv.first

      installer.install_files_and_build_extensions(supported_versions)
      installer.update_shebangs

      run_tests(supported_versions)

      installer.install_substvars(supported_versions)
      installer.install_gemspec(supported_versions)
      check_rubygems(installer)

      puts "  Leaving dh_ruby --install" if @verbose
    end

    protected

    def check_rubygems(installer)
      if skip_checks?
        return
      end

      begin
        installer.check_rubygems
      rescue Gem2Deb::Installer::RequireRubygemsFound
        handle_test_failure("require-rubygems")
      end
    end

    def handle_test_failure(test)
      if ENV['DH_RUBY_IGNORE_TESTS']
        if ENV['DH_RUBY_IGNORE_TESTS'].split.include?('all')
          puts "WARNING: Test \"#{test}\" failed, but ignoring all test results."
          return
        elsif ENV['DH_RUBY_IGNORE_TESTS'].split.include?(test)
          puts "WARNING: Test \"#{test}\" failed, but ignoring this test result."
          return
        end
      end
      if STDIN.isatty and STDOUT.isatty and STDERR.isatty
        # running interactively
        continue = nil
        begin
          puts
          print "Test \"#{test}\" failed. Continue building the package? (Y/N) "
          STDOUT.flush
          c = STDIN.getc
          continue = true if c.chr.downcase == 'y'
          continue = false if c.chr.downcase == 'n'
        end while continue.nil?
        if not continue
          exit(1)
        end
      else
          puts "ERROR: Test \"#{test}\" failed. Exiting."
          exit(1)
      end
    end

    def run_tests(supported_versions)
      supported_versions.dup.each do |rubyver|
        if !run_tests_for_version(rubyver)
          supported_versions.delete(rubyver)
        end
      end
    end

    def run_tests_for_version(rubyver)
      if skip_checks?
        return
      end

      cmd = "#{SUPPORTED_RUBY_VERSIONS[rubyver]} -I#{LIBDIR} #{TEST_RUNNER}"
      puts(cmd) if $VERBOSE
      system(cmd)

      if $?.exitstatus != 0
        handle_test_failure(rubyver)
        return false
      else
        return true
      end
    end

    def skip_checks?
      if @skip_checks.nil?
        if ENV['DEB_BUILD_OPTIONS'] && ENV['DEB_BUILD_OPTIONS'].split(' ').include?('nocheck')
          puts "DEB_BUILD_OPTIONS includes nocheck, skipping all checks (test suite, rubygems usage etc)." if @verbose
          @skip_checks = true
        else
          @skip_checks = false
        end
      end
      @skip_checks
    end

    def packages
      @packages ||= `dh_listpackages`.split
    end

    def ruby_versions
      @ruby_versions ||=
        begin
          # find ruby versions to build the package for.
          lines = File.readlines('debian/control').grep(/^XS-Ruby-Versions: /)
          if lines.empty?
            puts "No XS-Ruby-Versions: field found in source!" if @verbose
            exit(1)
          else
            lines.first.split[1..-1]
          end
        end
    end

    def all_ruby_versions_supported?
      ruby_versions.include?('all')
    end

  end
end
