# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/waf/update_checker"
require "dependabot/waf/requirement"
require "dependabot/waf/version"
require "dependabot/requirements_update_strategy"

module Dependabot
  module Waf
    class UpdateChecker
      class RequirementsUpdater
        extend T::Sig

        class UnfixableRequirement < StandardError; end

        VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-*]+)*/
        ALLOWED_UPDATE_STRATEGIES = T.let(
          [
            RequirementsUpdateStrategy::LockfileOnly,
            RequirementsUpdateStrategy::BumpVersions,
            RequirementsUpdateStrategy::BumpVersionsIfNecessary
          ].freeze,
          T::Array[Dependabot::RequirementsUpdateStrategy]
        )

        def initialize(requirements:, updated_source:, update_strategy:, target_version:)
          @requirements = requirements
          @updated_source = updated_source
          @update_strategy = update_strategy

          check_update_strategy

          return unless target_version && version_class.correct?(target_version)

          @target_version = version_class.new(target_version)
        end

        def updated_requirements
          return requirements if update_strategy.lockfile_only?

          # requirements must be matched by index.
          requirements.map do |req|
            req = req.merge(source: updated_source)
            next req unless target_version
            next req if req[:requirement].nil?

            if update_strategy == RequirementsUpdateStrategy::BumpVersionsIfNecessary
              update_version_requirement_if_needed(req)
            else
              update_version_requirement(req)
            end
          end
        end

        private

        attr_reader :requirements
        attr_reader :updated_source
        attr_reader :update_strategy
        attr_reader :target_version

        def update_version_requirement_if_needed(req)
          raise NotImplementedError
        end

        def update_version_requirement(req)
          string_reqs = req[:requirement]

          new_requirement =
            if (exact_req = exact_req(string_reqs))
              update_version_string(exact_req)
            elsif (req_to_update = non_range_req(string_reqs)) && update_version_string(req_to_update) != req_to_update
              update_version_string(req_to_update)
            else
              update_range_requirements(string_reqs)
            end
          req.merge(requirement: new_requirement)
        end

        def non_range_req(string_reqs)
          # It shouldn't include this
          return "*" if string_reqs.include?("*")

          string_reqs
        end

        def exact_req(string_reqs)
          return unless Requirement.new(string_reqs).exact?

          string_reqs
        end

        def update_version_string(req_string)
          new_target_parts = target_version.to_s
          req_string.sub(VERSION_REGEX) do |old_version|
            next target_version.to_s if old_version.match?(/\d-/)

            old_parts = old_version.split(".")
            new_parts = new_target_parts.split(".").first(old_parts.count)
            new_parts.map.with_index do |part, i|
              unless old_parts[i].nil?
                old_parts[i] == "*" ? "*" : part
              end
            end.join(".")
          end
        end

        def update_range_requirements(string_reqs)
          new_target_parts = target_version.to_s
          string_reqs.sub(VERSION_REGEX) do |old_version|
            next target_version.to_s if old_version.match?(/\d-/)

            old_parts = old_version.split(".")
            new_parts = new_target_parts.split(".").first(old_parts.count)
            new_parts.map.with_index do |part, i|
              unless old_parts[i].nil?
                old_parts[i] == "*" ? "*" : part
              end
            end.join(".")
          end
        end

        def check_update_strategy
          return if ALLOWED_UPDATE_STRATEGIES.include?(update_strategy)

          raise "Unknown update strategy: #{update_strategy}"
        end

        def version_class
          Waf::Version
        end
      end
    end
  end
end
