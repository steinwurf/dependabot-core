# typed: true
# frozen_string_literal: true

require "json"
require "open3"
require "dependabot/shared_helpers"
require "dependabot/waf/update_checker"
require "dependabot/waf/file_parser"
require "dependabot/waf/version"
require "dependabot/errors"

module Dependabot
  module Waf
    class UpdateChecker
      class VersionResolver
        UNABLE_TO_UPDATE = /Unable to update (?<url>.*?)$/
        BRANCH_NOT_FOUND_REGEX = /#{UNABLE_TO_UPDATE}.*to find branch `(?<branch>[^`]+)`/m
        REVSPEC_PATTERN = /revspec '.*' not found/
        OBJECT_PATTERN = /object not found - no match for id \(.*\)/
        REF_NOT_FOUND_REGEX = /#{UNABLE_TO_UPDATE}.*(#{REVSPEC_PATTERN}|#{OBJECT_PATTERN})/m
        GIT_REF_NOT_FOUND_REGEX = /Updating git repository `(?<url>[^`]*)`.*fatal: couldn't find remote ref/m

        def initialize(dependency:, credentials:, original_dependency_files:, prepared_dependency_files:)
          @dependency = dependency
          @prepared_dependency_files = prepared_dependency_files
          @original_dependency_files = original_dependency_files
          @credentials = credentials
        end

        def latest_resolvable_version
          return @latest_resolvable_version if defined?(@latest_resolvable_version)

          @latest_resolvable_version = fetch_latest_resolvable_version
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise DependencyFileNotResolvable, e.message
        end

        private

        attr_reader :dependency
        attr_reader :credentials
        attr_reader :prepared_dependency_files
        attr_reader :original_dependency_files

        def fetch_latest_resolvable_version
          base_directory = prepared_dependency_files.first.directory
          SharedHelpers.in_a_temporary_directory(base_directory) do
            write_temporary_dependency_files

            SharedHelpers.with_git_configured(credentials: credentials) do
              run_waf_resolve_command
            end

            updated_version = fetch_version_from_new_lockfile

            return if updated_version.nil?
            return updated_version if git_dependency?

            version_class.new(updated_version)
          end
          rescue SharedHelpers::HelperSubprocessFailed => e
            retry if better_specification_needed?(e)
            handle_waf_errors(e)
        end

        def write_temporary_dependency_files(prepared: true)
          write_manifest_files(prepared: prepared)

          # File.write(lockfile.name, lockfile.content) if lockfile
          File.write(waf_file.name, waf_file.content)
          File.write(wscript.name, wscript.content)
        end

        def write_manifest_files(prepared: true)
          manifest_files = if prepared then prepared_manifest_files
                           else
                             original_manifest_files
                           end

          manifest_files.each do |file|
            path = file.name
            dir = Pathname.new(path).dirname
            FileUtils.mkdir_p(dir)
            File.write(file.name, file.content)
          end
        end

        # Let waf handle the update
        def run_waf_resolve_command
          run_waf_command(
            "python waf resolve -vvv --lock_versions --resolve_path=/resolved_dependencies",
            fingerprint: "python waf resolve -vvv --lock_versions --resolve_path=/resolved_dependencies"
          )
        end

        def run_waf_command(command, fingerprint: nil)
          start = Time.now
          command = SharedHelpers.escape_command(command)

          stdout, process = Open3.capture2e(command)
          time_taken = Time.now - start

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

        def fetch_version_from_new_lockfile
          lockfile_content = File.read("lock_version_resolve.json")
          versions = JSON.parse(lockfile_content).fetch(dependency.name)

          version_class.new(versions.fetch("resolver_info"))
        end

        def better_specification_needed?(error)
          # If there is a way to make the specification better,
          # then this can be implemented.
          # For now let it be set to false.
          false
        end

        def handle_waf_errors(error)
          # These seems like a briliant candidate for test in production :)
          puts error
          nil
        end

        def prepared_manifest_files
          @prepared_manifest_files ||=
            prepared_dependency_files.select { |f| f.name == "resolve.json" }
        end

        def original_manifest_files
          @original_manifest_files ||=
            original_dependency_files.select { |f| f.name == "resolve.json" }
        end

        def wscript
          manifest = original_manifest_files
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
          @waf_file ||= original_dependency_files.find { |f| f.name == "waf" }
        end

        def lockfile
          @lockfile ||= prepared_dependency_files.find { |f| f.name == "lock_version_resolve.json" }
        end

        def version_class
          dependency.version_class
        end

        def git_dependency?
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          ).git_dependency?
        end
      end
    end
  end
end
