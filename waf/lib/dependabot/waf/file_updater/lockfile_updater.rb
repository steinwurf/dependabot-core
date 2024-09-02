# typed: true
# frozen_string_literal: true

require "json"
require "dependabot/git_commit_checker"
require "dependabot/waf/file_updater"
require "dependabot/waf/file_updater/manifest_updater"
require "dependabot/waf/file_parser"
require "dependabot/shared_helpers"

module Dependabot
  module Waf
    class FileUpdater
      class LockfileUpdater
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
        end

        def updated_lockfile_content
          base_directory = dependency_files.first.directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files

            SharedHelpers.with_git_configured(credentials: credentials) do
              run_waf_command("python3 waf resolve -vvv --lock_versions --resolve_path=/resolved_dependencies",
                              fingerprint: "python3 waf resolve -vvv --lock_versions --resolve_path=/resolved_dependencies")
            end

            updated_lockfile = File.read("lock_version_resolve.json")
            updated_lockfile = post_process_lockfile(updated_lockfile)

            next updated_lockfile if desired_lockfile_content(updated_lockfile)

            raise "Failed to update #{dependency.name}!"
          end
        rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
          handle_waf_errors(e)
        end

        private

        attr_reader :dependencies
        attr_reader :dependency_files
        attr_reader :credentials

        def dependency
          dependencies.first
        end

        def write_temporary_dependency_files
          write_temporary_manifest_files

          # File.write(lockfile.name, lockfile.content)
          File.write(wscript.name, wscript.content)
          File.write(waf_file.name, waf_file.content)
        end

        def write_temporary_manifest_files
          manifest_files.each do |file|
            path = file.name
            dir = Pathname.new(path).dirname
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, prepared_manifest_content(file))
          end
        end

        def prepared_manifest_content(file)
          content = updated_manifest_content(file)
          content
        end

        def updated_manifest_content(file)
          ManifestUpdater.new(
            dependencies: dependencies,
            manifest: file
          ).updated_manifest_content
        end

        def run_waf_command(command, fingerprint:)
          start = Time.now
          command = SharedHelpers.escape_command(command)

          stdout, process = Open3.capture2e(command)
          time_taken = Time.new - start

          return if process.success?

          raise SharedHelpers::HelperSubprocessFailed.new(
            message: stdout,
            error_context: {
              command: command,
              fingerprint: fingerprint,
              time_taken: time_taken,
              process_exit_value: process.to_s
            }
          )
        end

        # The function is here incase of ssh to http swapping is necessary.
        def post_process_lockfile(updated_lockfile)
          updated_lockfile
        end

        def desired_lockfile_content(updated_lockfile)
          req = updated_lockfile[dependency.name]

          req != dependency.version
        end

        def handle_waf_errors(error)
          puts error

          raise NotImplementedError
        end

        def manifest_files
          @manifest_files ||=
            dependency_files
            .select { |f| f.name == "resolve.json" }
        end

        def lockfile
          @lockfile ||= dependency_files.find { |f| f.name == "lock_version_resolve.json" }
        end

        # This function is a copy from the one in version_resolver
        def wscript
          manifest = manifest_files
          enabled_dependencies = ""
          app_name = "APPNAME = \"Dependabot updater\"\n"
          resolve = "def resolve(ctx):\n"

          manifest.each do |dep|
            enabled_dependencies + dependency_enabler(dep)
          end

          return Dependabot::DependencyFile.new(name: "wscript", content: app_name) if enabled_dependencies == ""

          Dependabot::DependencyFile.new(
            name: "wscript",
            content: app_name + resolve + enabled_dependencies
          )
        end

        def dependency_enabler(dependency)
          "    ctx.enable_dependency(\"#{dependency.name}\")\n"
        end

        def waf_file
          @waf_file ||= dependency_files.find { |f| f.name == "waf" }
        end
      end
    end
  end
end
