require 'fileutils'

require 'bosh/core/shell'
require 'bosh/stemcell/builder_options'
require 'bosh/stemcell/infrastructure'
require 'bosh/stemcell/operating_system'
require 'bosh/stemcell/stage_collection'
require 'bosh/stemcell/stage_runner'

module Bosh::Stemcell
  class BuilderCommand
    def initialize(options)
      @infrastructure = Infrastructure.for(options.fetch(:infrastructure_name))
      @operating_system = OperatingSystem.for(options.fetch(:operating_system_name))

      @stemcell_builder_options = BuilderOptions.new(tarball: options.fetch(:release_tarball_path),
                                                     stemcell_version: options.fetch(:version),
                                                     infrastructure: infrastructure,
                                                     operating_system: operating_system)
      @environment = ENV.to_hash
      @shell = Bosh::Core::Shell.new
    end

    def build
      sanitize

      prepare_build_root

      prepare_build_path

      copy_stemcell_builder_to_build_path

      prepare_work_root

      persist_settings_for_bash

      stage_collection = StageCollection.for(stemcell_builder_options.spec_name)
      stage_runner = StageRunner.new(stages: stage_collection.stages,
                                     build_path: build_path,
                                     command_env: command_env,
                                     settings_file: settings_path,
                                     work_path: work_root)
      stage_runner.configure_and_apply

      stemcell_file
    end

    def chroot_dir
      File.join(work_path, 'chroot') # also defined in bash stages
    end

    private

    attr_reader :shell,
                :environment,
                :infrastructure,
                :operating_system,
                :stemcell_builder_options

    def sanitize
      FileUtils.rm_rf('*.tgz')

      system("sudo umount #{File.join(work_path, 'mnt/tmp/grub/root.img')} 2> /dev/null")
      system("sudo umount #{File.join(work_path, 'mnt')} 2> /dev/null")
      system("sudo rm -rf #{base_directory}")
    end

    def settings
      stemcell_builder_options.default
    end

    def base_directory
      File.join('/mnt', 'stemcells', infrastructure.name, infrastructure.hypervisor, operating_system.name)
    end

    def build_root
      File.join(base_directory, 'build')
    end

    def work_root
      File.join(base_directory, 'work')
    end

    def prepare_build_root
      FileUtils.mkdir_p(build_root, verbose: true)
    end

    def prepare_work_root
      FileUtils.mkdir_p(work_root, verbose: true)
    end

    def build_path
      File.join(build_root, 'build')
    end

    def work_path
      File.join(work_root, 'work')
    end

    def prepare_build_path
      FileUtils.rm_rf(build_path, verbose: true) if Dir.exists?(build_path)
      FileUtils.mkdir_p(build_path, verbose: true)
    end

    def stemcell_builder_source_dir
      File.join(File.expand_path('../../../../..', __FILE__), 'stemcell_builder')
    end

    def copy_stemcell_builder_to_build_path
      FileUtils.cp_r(Dir.glob("#{stemcell_builder_source_dir}/*"), build_path, preserve: true, verbose: true)
    end

    def settings_path
      File.join(build_path, 'etc', 'settings.bash')
    end

    def persist_settings_for_bash
      File.open(settings_path, 'a') do |f|
        f.printf("\n# %s\n\n", '=' * 20)
        settings.each do |k, v|
          f.print "#{k}=#{v}\n"
        end
      end
    end

    def command_env
      "env #{hash_as_bash_env(proxy_settings_from_environment)}"
    end

    def stemcell_file
      File.join(work_path, settings['stemcell_tgz'])
    end

    def proxy_settings_from_environment
      keep = %w(HTTP_PROXY NO_PROXY)

      environment.select { |k| keep.include?(k.upcase) }
    end

    def hash_as_bash_env(env)
      env.map { |k, v| "#{k}='#{v}'" }.join(' ')
    end
  end
end
