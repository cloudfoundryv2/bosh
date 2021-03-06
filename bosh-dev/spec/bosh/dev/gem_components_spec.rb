require 'spec_helper'
require 'timecop'
require 'bosh/dev/gem_components'

module Bosh::Dev
  describe GemComponents do
    subject(:gem_components) do
      GemComponents.new
    end

    its(:to_a) do
      should eq(%w[
        agent_client
        blobstore_client
        bosh-core
        bosh-stemcell
        bosh_agent
        bosh_aws_cpi
        bosh_cli
        bosh_cli_plugin_aws
        bosh_cli_plugin_micro
        bosh_common
        bosh_cpi
        bosh_encryption
        bosh_openstack_cpi
        bosh_registry
        bosh_vsphere_cpi
        director
        health_monitor
        monit_api
        package_compiler
        ruby_vim_sdk
        simple_blobstore_server
      ])
    end

    it { should have_db('director') }
    it { should have_db('bosh_registry') }

    describe '#component_needs_update' do
      include FakeFS::SpecHelpers
      let(:component) { 'fake-component' }
      let(:root) { '/fake-root' }
      let(:version) { 123 }
      let(:gemspec) { double('gemspec', files: []) }

      let(:gemspec_klass) { class_double('Gem::Specification').as_stubbed_const }

      before do
        Timecop.scale(3_600_000)

        gemspec_klass.stub(:load).with('/fake-root/fake-component/fake-component.gemspec').and_return(gemspec)

        FileUtils.mkdir_p('/fake-root/fake-component/lib')
        FileUtils.touch('/fake-root/fake-component/fake-component.gemspec')
      end

      context 'when a .gem file does not exist' do
        it 'needs an update' do
          expect(gem_components).to be_a_component_needing_update(component, root, version)
        end
      end

      context 'when a .gem file exists' do
        before do
          FileUtils.mkdir_p('/fake-root/release/src/bosh/fake-component')
          FileUtils.touch('/fake-root/release/src/bosh/fake-component/fake-component-123.gem')
        end

        context 'and its code has not been modified since it was last built' do
          it 'does not need an update' do
            expect(gem_components).not_to be_a_component_needing_update(component, root, version)
          end
        end

        context 'and its code has been modified since it was last built' do
          let(:gemspec) { double('gemspec', files: %w[/fake-root/fake-component/lib/fake-component.rb]) }

          before do
            FileUtils.touch('/fake-root/fake-component/lib/fake-component.rb')
          end

          it 'needs an update' do
            expect(gem_components).to be_a_component_needing_update(component, root, version)
          end
        end
      end
    end

    describe '#update_version' do
      let(:root) { Dir.mktmpdir }
      let(:global_bosh_version_file) { "#{root}/BOSH_VERSION" }
      let(:component_version_file) { "#{root}/fake-component/lib/fake/component/version.rb" }

      before do
        gem_components.stub(root: root)

        File.open(global_bosh_version_file, 'w') do |file|
          file.write('fake-bosh-version')
        end

        FileUtils.mkdir_p(File.dirname(component_version_file))
        File.open(component_version_file, 'w') do |file|
          file.write <<-RUBY.gsub /^\s+/, ''
            module Fake::Component
              VERSION = '1.5.0.pre.3'
            end
          RUBY
        end
      end

      after do
        FileUtils.rm_r(root)
      end

      it "set the component's version to the global BOSH_VERSION" do
        expect {
          gem_components.update_version('fake-component')
        }.to change { File.read(component_version_file) }.to <<-RUBY.gsub /^\s+/, ''
              module Fake::Component
                VERSION = 'fake-bosh-version'
              end
          RUBY
      end
    end
  end
end
