# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/pub/helpers"
require "yaml"
module Dependabot
  module Pub
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      include Dependabot::Pub::Helpers

      def latest_version
        version = version_unless_ignored(current_report["latest"], allowed_version: dependency.version)
        raise AllVersionsIgnored if version.nil? && @raise_on_ignored

        version
      end

      def latest_resolvable_version_with_no_unlock
        # Version we can get if we're not allowed to change pubspec.yaml, but we
        # allow changes in the pubspec.lock file.
        entry = current_report["compatible"].find { |d| d["name"] == dependency.name }
        return nil unless entry

        version_unless_ignored(entry["version"])
      end

      def latest_resolvable_version
        # Latest version we can get if we're allowed to unlock the current
        # package in pubspec.yaml
        entry = current_report["singleBreaking"].find { |d| d["name"] == dependency.name }
        return nil unless entry

        version_unless_ignored(entry["version"])
      end

      def updated_requirements
        # Requirements that need to be changed, if obtain:
        # latest_resolvable_version
        entry = current_report["singleBreaking"].find { |d| d["name"] == dependency.name }
        return unless entry

        parse_updated_dependency(entry, requirements_update_strategy: resolved_requirements_update_strategy).
          requirements
      end

      private

      # Returns unparsed_version if it looks like a git-revision.
      #
      # Otherwise it will be parsed with Dependabot::Pub::Version.new and
      # checked against the ignored_requirements:
      #
      # * If not ignored the parsed Version object will be returned.
      # * If allowed_version is non-nil and the parsed version is the same it
      #   will be returned.
      # * Otherwise returns nil
      def version_unless_ignored(unparsed_version, allowed_version: nil)
        if git_revision?(unparsed_version)
          unparsed_version
        else
          new_version = Dependabot::Pub::Version.new(unparsed_version)
          if !allowed_version.nil? && !git_revision?(allowed_version) &&
             Dependabot::Pub::Version.new(allowed_version) == new_version
            return new_version
          end
          return nil if ignore_requirements.any? { |r| r.satisfied_by?(new_version) }

          new_version
        end
      end

      def git_revision?(s)
        s.match?(/^[0-9a-f]{6,}$/)
      end

      def latest_version_resolvable_with_full_unlock?
        entry = current_report["multiBreaking"].find { |d| d["name"] == dependency.name }
        # This a bit dumb, but full-unlock is only considered if we can get the
        # latest version!
        entry && ((!git_revision?(entry["version"]) && latest_version == Dependabot::Pub::Version.new(entry["version"])) ||
          latest_version == entry["version"])
      end

      def updated_dependencies_after_full_unlock
        # We only expose non-transitive dependencies here...
        direct_deps = current_report["multiBreaking"].reject do |d|
          d["kind"] == "transitive"
        end
        direct_deps.map do |d|
          parse_updated_dependency(d, requirements_update_strategy: resolved_requirements_update_strategy)
        end
      end

      def report
        @report ||= dependency_services_report
      end

      def current_report
        report.find { |d| d["name"] == dependency.name }
      end

      def resolved_requirements_update_strategy
        @resolved_requirements_update_strategy ||= resolve_requirements_update_strategy
      end

      def resolve_requirements_update_strategy
        raise "Unexpected requirements_update_strategy #{requirements_update_strategy}" unless
          [nil, "widen_ranges", "bump_versions", "bump_versions_if_necessary"].include? requirements_update_strategy

        if requirements_update_strategy.nil?
          # Check for a version field in the pubspec.yaml. If it is present
          # we assume the package is a library, and the requirement update
          # strategy is widening. Otherwise we assume it is an application, and
          # go for "bump_versions".
          pubspec = dependency_files.find { |d| d.name == "pubspec.yaml" }
          begin
            parsed_pubspec = YAML.safe_load(pubspec.content, aliases: false)
          rescue ScriptError
            return "bump_versions"
          end
          if parsed_pubspec["version"].nil? || parsed_pubspec["publish_to"] == "none"
            "bump_versions"
          else
            "widen_ranges"
          end
        else
          requirements_update_strategy
        end
      end
    end
  end
end

Dependabot::UpdateCheckers.register("pub", Dependabot::Pub::UpdateChecker)
