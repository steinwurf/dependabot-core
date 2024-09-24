# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

module Dependabot
  module Waf
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      # Probably not needed. It is not what I thought it was.
      DEPENDENCY_TYPES = %w(semver checkout http).freeze

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new
        dependency_set += manifest_dependencies
        dependency_set += lockfile_dependencies if lockfile

        dependency_set.dependencies
      end

      private

      def manifest_dependencies
        dependency_set = DependencySet.new

        parsed_file(waf_resolve).each do |requirement|
          name = name_from_declaration(requirement)
          next if lockfile && !version_from_lockfile(name)

          dependency_set << build_dependency(name, requirement, waf_resolve.name)
        end

        dependency_set
      end

      def lockfile_dependencies
        dependency_set = DependencySet.new
        return dependency_set unless lockfile

        parsed_file(lockfile).each do |name, requirement|
          next unless requirement

          dependency_set << Dependency.new(
            name: name,
            version: version_from_lockfile_details(requirement),
            package_manager: "waf",
            requirements: []
          )
        end

        dependency_set
      end

      def name_from_declaration(declaration)
        raise "Unexpected dependency declaration: #{declaration}" unless declaration.is_a?(Hash)

        declaration["name"]
      end

      def source_from_declaration(declaration)
        return if declaration.is_a?(String)
        raise "Unexpected dependency declaration: #{declaration}" unless declaration.is_a?(Hash)

        return git_source_details(declaration) if declaration["resolver"] == "git"

        http_source_details(declaration) if declaration["resolver"] == "http"
      end

      def requirement_from_declaration(declaration)
        return if declaration.is_a?(String)

        unless declaration.is_a?(Hash)
          raise Dependabot::DependencyFileNotEvaluatable
          # "Unexpected dependency declaration: #{declaration}"
        end

        return declaration["major"].to_s if declaration["method"] == "semver" && !declaration["major"].nil?

        if declaration["method"] == "checkout" && declaration["checkout"] != "" && !declaration["checkout"].nil?
          return declaration["checkout"]
        end

        return unless declaration["resolver"] != "http"

        raise Dependabot::DependencyFileNotEvaluatable,
              "No version where provided in the resolve.json file"
      end

      def group_from_declaration(declaration)
        return ["semver"] if declaration["resolver"] == "git" && declaration["method"] == "semver"
        return ["checkout"] if declaration["resolver"] == "git" && declaration["method"] == "checkout"
        return ["http"] if declaration["resolver"] == "http"

        ""
      end

      def git_source_details(declaration)
        ref = declaration["major"].to_s + ".0.0" if declaration["major"]
        {
          type: "git",
          url: "https://" + (declaration["source"] || declaration["sources"][0]), # Taking the first source is fine since multiple sources have never been used.
          branch: "main", # Not used from my knowledge.
          ref: (ref || declaration["checkout"]).to_s
        }
      end

      def http_source_details(declaration)
        {
          type: "http",
          url: declaration["source"]
        }
      end

      def version_from_files(name, requirement)
        return version_from_lockfile(name) if lockfile

        version_from_manifest(requirement)
      end

      def version_from_manifest(requirement)
        requirement["checkout"] || requirement["major"].to_s
      end

      def version_from_lockfile(name)
        return unless lockfile

        candidate_packages = parsed_file(lockfile).fetch(name.to_s, [])

        candidate_packages["resolver_info"]
      end

      def version_from_lockfile_details(package_details)
        return package_details["resolver_info"] if package_details["resolver_info"]

        raise DependencyFileNotEvaluatable, "No version where provided in the resolve.json or lockfile"
      end

      def build_dependency(name, requirement, file)
        Dependency.new(
          name: name,
          version: version_from_files(name, requirement),
          package_manager: "waf",
          requirements: [{
            requirement: requirement_from_declaration(requirement),
            file: file,
            groups: group_from_declaration(requirement),
            source: source_from_declaration(requirement)
          }]
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def waf_resolve
        @waf_resolve ||= T.let(get_original_file("resolve.json"), T.nilable(Dependabot::DependencyFile))
      end

      def lockfile
        @lockfile ||= get_original_file("lock_version_resolve.json")
      end

      def parsed_file(file)
        @parsed_file ||= {}
        @parsed_file[file.name] ||= JSON.parse(file.content)
      rescue JSON::ParserError, JSON::ValueOverwriteError
        raise DependencyFileNotParseable, file.path
      end

      sig { override.void }
      def check_required_files
        raise "No resolve.json" unless waf_resolve
      end
    end
  end
end

Dependabot::FileParsers.register("waf", Dependabot::Waf::FileParser)
