# typed: true
# frozen_string_literal: true

require "json"
require "dependabot/dependency_file"
require "dependabot/waf/file_parser"
require "dependabot/waf/update_checker"

module Dependabot
  module Waf
    class UpdateChecker
      class FilePreparer
        def initialize(dependency_files:, dependency:, unlock_requirement: true, replacement_git_pin: nil,
                       latest_allowable_version: nil)
          @dependency_files = dependency_files
          @dependency = dependency
          @unlock_requirement = unlock_requirement
          @replacement_git_pin = replacement_git_pin
          @latest_allowable_version = latest_allowable_version
        end

        def prepared_dependency_files
          files = []
          files += manifest_files.map do |file|
            DependencyFile.new(
              name: file.name,
              content: manifest_content_for_update_check(file),
              directory: file.directory
            )
          end
          files << lockfile if lockfile
          files
        end

        private

        attr_reader :dependency_files
        attr_reader :dependency
        attr_reader :replacement_git_pin
        attr_reader :latest_allowable_version

        def unlock_requirement?
          @unlock_requirement
        end

        def replace_git_pin?
          !replacement_git_pin.nil?
        end

        def manifest_content_for_update_check(file)
          content = file.content

          if !file.support_file? && replace_git_pin?
            content = replace_version_constraint(content, file.name) # Should run when semver is used.
            content = replace_git_pin(content) # Should run when checkout is used.
          end

          # content = add_http_urls(content)
          content
        end

        def add_http_urls(content)
          parsed_manifest = JSON.parse(content)

          parsed_manifest.each do |dep|
            next unless dep.is_a?(Hash)
            next unless dep["resolver"] == "git"

            dep["source"] = "https://" + dep["source"] if dep["source"]
            dep["sources"][0] = "https://" + dep["sources"][0] if dep["sources"]
          end

          JSON.dump(parsed_manifest)
        end

        def replace_version_constraint(content, filename)
          parsed_manifest = JSON.parse(content)

          parsed_manifest.each do |dep|
            updated_dep = temporary_requirement_for_resolution(filename)
          end
        end

        def temporary_requirement_for_resolution(filename)
          original_req = dependency.requirements.find { |r| r.fetch(:file) == filename }&.fetch(:requirement)

          lower_bound_req = if original_req && !unlock_requirement?
                              original_req
                            else
                              ">= #{lower_bound_version}"
                            end
          unless latest_allowable_version &&
                 Waf::Version.correct?(latest_allowable_version) &&
                 Waf::Version.new(latest_allowable_version) >=
                 Waf::Version.new(lower_bound_version)
          end
          lower_bound_req
        end

        def lower_bound_version; end

        # TODO: It seems like this should be different whether it is semver or checkout.
        # Currently it will not enter the correct method when it is a git tag.
        def replace_git_pin(content)
          parsed_manifest = content

          parsed_manifest.each do |i, req|
            next unless req.is_a?(Hash)
            next unless req["resolver"] == "git"

            parsed_manifest[i]["major"] = replacement_git_pin if req["major"]
            parsed_manifest[i]["checkout"] = replacement_git_pin if req["checkout"]
          end

          JSON.dump(parsed_manifest)
        end

        def dependency_names_for_type(parsed_manifest, type)
          names = []
          parsed_manifest.each do |content|
            names << content["name"] if dependency_type_checker(content, type)
          end

          names
        end

        def dependency_type_checker(dep, type)
          if dep["resolver"] == type
            return true
          elsif dep["method"] == type
            return true
          end

          false
        end

        def manifest_files
          @manifest_files ||=
            dependency_files.select { |f| f.name.end_with?("resolve.json") }

          raise "No resolve.json!" if @manifest_files.none?

          @manifest_files
        end

        def lockfile
          @lockfile ||= dependency_files.find { |f| f.name == "lock_version_resolve.json" }
        end

        def git_dependency?
          GitCommitChecker.new(dependency: dependency, credentials: []).git_dependency?
        end
      end
    end
  end
end
