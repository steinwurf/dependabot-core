# typed: true
# frozen_string_literal: true

require "json"
require "dependabot/git_commit_checker"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module Waf
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/manifest_updater"
      require_relative "file_updater/lockfile_updater"
      def self.updated_files_regex
        [
          /^resolve\.json$/,
          /^lock_version_resolve\.json$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        manifest_files.each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(
              file: file,
              content: updated_manifest_content(file)
            )
        end

        if lockfile && updated_lockfile_content != lockfile.content
          updated_files <<
            updated_file(file: lockfile, content: updated_lockfile_content)
        end

        raise "No files changed!" if updated_files.empty?

        updated_files
      end

      private

      def check_required_files
        raise "No resolve.json!" unless get_original_file("resolve.json")
      end

      def updated_manifest_content(file)
        ManifestUpdater.new(
          dependencies: dependencies,
          manifest: file
        ).updated_manifest_content
      end

      def updated_lockfile_content
        @updated_lockfile_content ||=
          LockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          ).updated_lockfile_content
      end

      def manifest_files
        @manifest_files ||=
          dependency_files
          .select { |f| f.name.end_with?("resolve.json") }
          .reject(&:support_file?)
      end

      def lockfile
        @lockfile ||= get_original_file("lock_version_resolve.json")
      end
    end
  end
end

Dependabot::FileUpdaters.register("waf", Dependabot::Waf::FileUpdater)
