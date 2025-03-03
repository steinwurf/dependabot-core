# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Waf
    class Version < Dependabot::Version
      extend T::Sig

      attr_reader :build_info

      VERSION_PATTERN = '[0-9]+(?>\.[0-9a-zA-Z]+)*' \
                        '(-[0-9A-Za-z-]+(\.[0-9a-zA-Z-]+)*)?' \
                        '(\+[0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*)?'
      ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/

      def initialize(version)
        @version_string = version.to_s
        version = version.to_s.split("+").first if version.to_s.include?("+")

        super
      end

      def to_s
        @version_string
      end

      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end

      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(ANCHORED_VERSION_PATTERN)
      end

      def <=>(other)
        return 1 if other.nil?

        version_comparison = super
        return version_comparison unless version_comparison&.zero?

        return build_info.nil? ? 0 : 1 unless other.is_a?(Waf::Version)

        lhsegments = build_info.to_s.split(".").map(&:downcase)
        rhsegments = other.build_info.to_s.split(".").map(&:downcase)
        limit = [lhsegments.count, rhsegments.count].min

        lhs = ["1", *lhsegments.first(limit)].join(".")
        rhs = ["1", *rhsegments.first(limit)].join(".")

        local_comparison = Gem::Version.new(lhs) <=> Gem::Version.new(rhs)

        return local_comparison unless local_comparison&.zero?

        lhsegments.count <=> rhsegments.count
      end
    end
  end
end

Dependabot::Utils.register_version_class("waf", Dependabot::Waf::Version)
