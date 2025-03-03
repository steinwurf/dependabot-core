# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/waf/version"

module Dependabot
  module Waf
    class Requirement < Dependabot::Requirement
      extend T::Sig

      version_pattern = Waf::Version::VERSION_PATTERN
      quoted = OPS.keys.map { |k| Regexp.quote(k) }.join("|")

      PATTERN_RAW = "\\s*(#{quoted})?\\s*(#{version_pattern})\\s*".freeze
      PATTERN = /\A#{PATTERN_RAW}\z/

      # resolve.json only contains a single element per entry.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      # There aren't many strict requirements strings in waf resolve.
      # Mostly it comes down to major versions or git tags.
      # Therefore, requirements comes in either a single integer or a string release tag.
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          next unless req_string != ""

          req_string.to_s
        end

        super(requirements)
      end

      def self.parse(obj)
        return ["~>", Waf::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "~>", Waf::Version.new(T.must(matches[2]))]
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("waf", Dependabot::Waf::Requirement)
