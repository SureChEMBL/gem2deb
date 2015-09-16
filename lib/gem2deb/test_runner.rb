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

require 'rbconfig'
require 'fileutils'
require 'shellwords'
require 'tmpdir'

require 'gem2deb/banner'
require 'gem2deb/metadata'

module Gem2Deb
  class TestRunner

    include FileUtils::Verbose

    attr_accessor :autopkgtest
    attr_accessor :check_dependencies
    attr_accessor :smoke_assets

    def load_path
      if self.autopkgtest
        return ['.']
      end

      # We should only use installation paths for the current Ruby
      # version.
      #
      # We assume that installation has already proceeded into
      # subdirectories of the debian/ directory.
      #
      # It is important that the directories under debian/ $LOAD_PATH in the
      # same order than their system-wide equivalent

      dirs = []
      $LOAD_PATH.grep(/vendor/).each do |dir|
        dirs += Dir.glob('debian/*/' + dir).map { |d| File.expand_path(d) }
      end

      # And we add the current directory:
      dirs << "."

      dirs
    end

    def env_with_gem_path
      if self.autopkgtest
        { }
      else
        {
          'GEM_PATH' => (Gem.path + Dir.glob("debian/*/usr/share/rubygems-integration/{all,#{ruby_api_version}}")).join(':')
        }
      end
    end

    def run_tests
      if check_dependencies
        do_check_dependencies
      end
      if smoke_assets
        do_smoke_assets
      end
      do_run_tests
    end

    def do_check_dependencies
      print_banner "Checking Rubygems dependency resolution on #{rubyver}"
      metadata = Gem2Deb::Metadata.new('.')
      if metadata.gemspec
        cmd = [rubyver, '-e', 'gem "%s"' % metadata.name]
        puts "GEM_PATH=#{env_with_gem_path['GEM_PATH']} " + cmd.shelljoin
        system(env_with_gem_path, *cmd)
        exitstatus = $?.exitstatus
        if exitstatus != 0
          system 'gem', 'list'
          exit(exitstatus)
        end
      end
    end

    def do_smoke_assets
      print_banner "Running smoke test for rails assets on #{rubyver}"
      metadata = Gem2Deb::Metadata.new('.')
      if metadata.name =~ /^rails-assets/
      	asset_name = metadata.name.split('rails-assets-')[1]
	do_smoke(asset_name, metadata.name)
      elsif metadata.name =~ /-rails$/
      	asset_name = metadata.name.split('-rails')[0]
	do_smoke(asset_name, metadata.name)
      end
    end

    def do_smoke(asset, gem)
      print_banner "Running smoke test for #{asset}"
      if ENV['ADTTMP']
      	tmpdir = ENV['ADTTMP']
      else
      	tmpdir = Dir.mktmpdir
      end
      Dir.chdir(tmpdir)
      # 'rails new foo' throws errors which cause autopkgtest to fail
      system "rails new foo >/dev/null 2>&1"
      Dir.chdir("foo")
      open('app/assets/javascripts/application.js', 'a') { |f|
        f.puts "# =require #{asset}"
	}
      open('Gemfile', 'a') { |f|
        f.puts "gem \'#{gem}\'"
	}
      system "bundle install --local"
      system "bundle exec rake assets:precompile"
    end

    # Override in subclasses
    def do_run_tests
    end

    # override in subclasses
    def required_file
      nil
    end

    def activate?
      required_file && File.exist?(required_file)
    end

    def run_ruby(*args)
      run(rubyver, *args)
    end

    def run_rake(*args)
      run(rubyver.sub('ruby', 'rake'), *args)
    end

    def run(program, *args)
      rubylib = load_path.join(':')
      cmd = [program] + args

      rlib = (ENV['RUBYLIB'] ? ENV['RUBYLIB'] + ':' : '') + rubylib
      puts "RUBYLIB=#{rubylib} " + cmd.shelljoin

      if autopkgtest
        move_away 'lib'
        move_away 'ext'
      end
      system({ 'RUBYLIB' => rlib }, *cmd)
      exitstatus = $?.exitstatus
      if autopkgtest
        restore 'lib'
        restore 'ext'
      end
      exit(exitstatus)
    end

    def move_away(dir)
      if File.exist?(dir)
        mv dir, '.gem2deb.' + dir
      end
    end

    def restore(dir)
      if File.exist?('.gem2deb.' + dir)
        mv '.gem2deb.' + dir, dir
      end
    end

    def self.inherited(subclass)
      @subclasses ||= []
      @subclasses << subclass
    end
    def self.subclasses
      @subclasses
    end
    def self.detect
      subclasses.map(&:new).find do |runner|
        runner.activate?
      end
    end
    def self.detect!
      detect || bail("E: this tool must be run from inside a Debian source package.")
    end
    def self.bail(msg)
      puts msg
      exit 1
    end
    def rubyver
      @rubyver ||= RbConfig::CONFIG['ruby_install_name']
    end
    def ruby_api_version
      RbConfig::CONFIG['ruby_version']
    end
    def ruby_binary
      @ruby_binary ||= File.join('/usr/bin', rubyver)
    end

    def print_banner(msg)
      Gem2Deb::Banner.print(msg)
    end

    class TestsListedInMetadata < TestRunner
      def required_file
        'debian/ruby-test-files.yaml'
      end
      def do_run_tests
        print_banner "Run tests for #{rubyver} from debian/ruby-test-files.yaml"
        run_ruby(
          '-ryaml',
          '-e',
          'YAML.load_file("debian/ruby-test-files.yaml").each { |f| require f }'
        )
      end
    end

    class DebianRakefile < TestRunner
      def required_file
        'debian/ruby-tests.rake'
      end
      def do_run_tests
        print_banner "Run tests for #{rubyver} from debian/ruby-tests.rake"
        run_rake('-f', 'debian/ruby-tests.rake')
      end
    end

    class DebianRubyFile < TestRunner
      def required_file
        'debian/ruby-tests.rb'
      end
      def do_run_tests
        print_banner "Run tests for #{rubyver} from debian/ruby-tests.rb"
        ENV['RUBY_TEST_VERSION'] = rubyver
        ENV['RUBY_TEST_BIN'] = ruby_binary
        run_ruby(required_file)
      end
    end

    class DontKnownHowToRunTests < TestRunner
      def required_file
        'debian/rules'
      end
      def do_run_tests
        print_banner "Run tests for #{rubyver}: no test suite!"
      end
    end

  end

end
