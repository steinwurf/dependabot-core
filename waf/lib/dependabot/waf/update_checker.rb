# typed: true
# frozen_string_literal: true

require "dependabot/git_commit_checker"
require "dependabot/requirements_update_strategy"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Waf
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig
      require_relative "update_checker/file_preparer"
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_resolver"
      def latest_version
        @latest_version =
          if git_dependency?
            latest_version_for_git_dependency
          elsif http_dependency?
            latest_version_for_http_dependency
          end
      end

      def latest_resolvable_version
        @latest_resolvable_version ||=
          if git_dependency?
            latest_resolvable_version_for_git_dependency
          elsif http_dependency?
            latest_resolvable_version_for_http_dependency
          end
      end

      def latest_resolvable_version_with_no_unlock
        @latest_resolvable_version_with_no_unlock ||= fetch_latest_resolvable_version(unlock_requirement: false)
      end

      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          updated_source: updated_source,
          target_version: target_version,
          update_strategy: requirements_update_strategy
        ).updated_requirements
      end

      def requirements_update_strategy
        return @requirements_update_strategy if @requirements_update_strategy

        RequirementsUpdateStrategy::BumpVersions
      end

      private

      # TODO: Implement a method for resolving dependencies,
      # where all dependency constraints are unlocked.
      # If this is not implemented, there might be conditions where dependencies can block eachother from updating.
      def latest_version_resolvable_with_full_unlock?
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def git_dependency?
        git_commit_checker.git_dependency?
      end

      def latest_version_for_git_dependency
        latest_version = latest_git_version

        return latest_version unless dependency.requirements[0][:groups].include?("semver")

        matched_version = latest_version.to_s.scan(/\d+/)

        split_original = dependency.version.to_s.scan(/\d+/).length()

        composed_version = ""

        for i in 0..split_original - 1 do
          if i != 0
            composed_version = composed_version + "."
          end
          composed_version = composed_version + matched_version[i]
        end

        version_class.new(composed_version)
      end

      def latest_resolvable_version_for_git_dependency
        latest_resolvable_commit_with_unchanged_git_source unless git_commit_checker.pinned?

        if git_commit_checker.pinned_ref_looks_like_version? && latest_git_tag_is_resolvable?
          new_tag = git_commit_checker.local_tag_for_latest_version
          return new_tag.fetch(:version)
        end

        dependency.version
      end

      def latest_git_version
        # If the dependency is not pinned, then the latest version is the latest commit for the specified branch.
        git_commit_checker.head_commit_for_current_branch unless git_commit_checker.pinned?

        # If the dependency is pinned to a tag,
        # then we should update that tag.
        if git_commit_checker.pinned_ref_looks_like_version?
          latest_tag = git_commit_checker.local_tag_for_latest_version
          return latest_tag&.fetch(:version) || dependency.version
        end

        # If the dependency is pinned to a tag that doesn't look like a
        # version then there's nothing we can do.
        dependency.version
      end

      def latest_resolvable_commit_with_unchanged_git_source
        fetch_latest_resolvable_version(unlock_requirement: false)
      rescue SharedHelpers::HelperSubprocessFailed => e
        return if e.message.include?("versions conflict")

        raise e
      end

      def latest_git_tag_is_resolvable?
        return @git_tag_resolvable if @latest_git_tag_is_resolvable_checked

        @latest_git_tag_is_resolvable_checked = true

        return false if git_commit_checker.local_tag_for_latest_version.nil?

        replacement_tag = git_commit_checker.local_tag_for_latest_version

        prepared_files = FilePreparer.new(
          dependency_files: dependency_files,
          dependency: dependency,
          unlock_requirement: true,
          replacement_git_pin: replacement_tag.fetch(:tag)
        ).prepared_dependency_files

        VersionResolver.new(
          dependency: dependency,
          prepared_dependency_files: prepared_files,
          original_dependency_files: dependency_files,
          credentials: credentials
        ).latest_resolvable_version
        @git_tag_resolvable = true
      rescue SharedHelpers::HelperSubprocessFailed => e
        raise e unless e.message.include?("versions conflict")

        @git_tag_resolvable = false
      end

      def fetch_latest_resolvable_version(unlock_requirement:)
        prepared_files = FilePreparer.new(
          dependency_files: dependency_files,
          dependency: dependency,
          unlock_requirement: unlock_requirement,
          latest_allowable_version: latest_version
        ).prepared_dependency_files

        VersionResolver.new(
          dependency: dependency,
          prepared_dependency_files: prepared_files,
          original_dependency_files: dependency_files,
          credentials: credentials
        ).latest_resolvable_version
      end

      def updated_source
        return dependency_source_details unless git_dependency?

        # Update the git tag if updating a pinned version
        return unless git_commit_checker.pinned_ref_looks_like_version? && latest_git_tag_is_resolvable?

        if git_commit_checker.local_tag_for_latest_version
          new_tag = git_commit_checker.local_tag_for_latest_version
          dependency_source_details.merge(ref: new_tag.fetch(:tag))
        end

        # Otherwise return the orginal source
        dependency_source_details
      end

      def dependency_source_details
        dependency.source_details
      end

      def target_version
        preferred_resolvable_version.to_s
      end

      def http_dependency?
        return true if dependency.requirements[0][:source][:type] == "http"

        false
      end

      def latest_version_for_http_dependency
        # dependency.version # Cannot update currently

        nil
      end

      def latest_resolvable_version_for_http_dependency
        # dependency.version

        nil
      end

      def git_commit_checker
        @git_commit_checker ||=
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("waf", Dependabot::Waf::UpdateChecker)
