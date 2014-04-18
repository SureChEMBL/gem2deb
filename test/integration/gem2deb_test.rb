require 'test_helper'

class Gem2DebTest < Gem2DebTestCase

  def self.build(gem)
    FileUtils.cp gem, tmpdir
    gem = File.basename(gem)
    Dir.chdir(tmpdir) do
      cmd = "gem2deb -d #{gem}"
      run_command(cmd)
    end
  end

  Dir.glob('test/sample/*/pkg/*.gem').each do |gem|
    puts "Building #{gem} ..."
    self.build(gem)
    should "build #{gem} correcly" do
      package_name = 'ruby-' + File.basename(File.dirname(File.dirname(gem))).gsub('_', '-').downcase
      binary_packages = File.join(self.class.tmpdir, "#{package_name}_*.deb")
      packages = Dir.glob(binary_packages)
      assert !packages.empty?, "building #{gem} produced no binary packages! (expected to find #{binary_packages})"
    end
  end

  should 'generate a non-lintian-clean copyright file' do
    changes_file = File.join(self.class.tmpdir, "ruby-simplegem_*.changes")
    assert_match /E: ruby-simplegem: helper-templates-in-copyright/, `lintian #{changes_file}`
  end

  def self.build_tree(directory)
    FileUtils.cp_r(directory, tmpdir)
    dir = File.join(tmpdir, File.basename(directory))
    yield(dir)
    puts "Building #{directory} ..."
    Dir.chdir(dir) do
      run_command('fakeroot debian/rules install')
    end
  end

  self.build_tree('test/sample/documentation') do |dir|
    should 'contain generated documentation' do
        assert_file_exists "#{dir}/debian/gem2deb_generated_docs/html"
    end
  end

  self.build_tree('test/sample/examples') do |dir|

    should 'not compress *.rb files installed as examples' do
      assert_no_file_exists "#{dir}/debian/ruby-examples/usr/share/doc/ruby-examples/examples/test.rb.gz"
      assert_file_exists "#{dir}/debian/ruby-examples/usr/share/doc/ruby-examples/examples/test.rb"
    end

    should 'install CHANGELOG.rdoc as upstream changelog' do
      changelog = "#{dir}/debian/ruby-examples/usr/share/doc/ruby-examples/changelog.gz"
      assert_file_exists changelog
    end

  end

  self.build_tree('test/sample/multibinary') do |dir|
    context "multibinary source package" do
      should "install foo in ruby-foo" do
        assert_file_exists "#{dir}/debian/ruby-foo/usr/bin/foo"
      end
      should 'install foo.rb in ruby-foo' do
        assert_file_exists "#{dir}/debian/ruby-foo/usr/lib/ruby/vendor_ruby/foo.rb"
      end
      should 'install bar in ruby-bar' do
        assert_file_exists "#{dir}/debian/ruby-bar/usr/bin/bar"
      end
      should 'install bar.rb ruby-bar' do
        assert_file_exists "#{dir}/debian/ruby-bar/usr/lib/ruby/vendor_ruby/bar.rb"
      end
      should 'support installing upstream CHANGELOG in multibinary package' do
        assert_file_exists "#{dir}/debian/ruby-bar/usr/share/doc/ruby-bar/changelog.gz"
      end

      should 'support native extensions' do
        assert Dir.glob("#{dir}/debian/ruby-baz/**/baz.so").size > 0, 'baz.so not found!!!'
      end
    end
  end

  self.build_tree('test/sample/simpleextension_dh_auto_install_destdir') do |dir|
    should 'honor DH_RUBY_USE_DH_AUTO_INSTALL_DESTDIR when building extensions' do
      assert Dir.glob("#{dir}/debian/tmp/**/*.so").size > 0, 'no .so files found in debian/tmp/'
    end
  end

end
