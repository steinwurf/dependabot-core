# typed: true
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/errors"

module Dependabot
  module Waf
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      def self.required_files_in?(filenames)
        filenames.include?("resolve.json")
      end

      def self.required_files_message
        "Repo must contain a resolve.json"
      end

      def ecosystem_versions
        version = if waf
                    version_regexer(waf.content)
                  else
                    "default"
                  end
        {
          package_managers: {
            "waf" => version
          }
        }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = T.let([], T::Array[DependencyFile])
        fetched_files << resolve_json
        fetched_files << lock_version_resolve_json if lock_version_resolve_json
        fetched_files << wscript
        fetched_files << waf
        fetched_files
      end

      private

      def version_regexer(input)
        regex = /VERSION="(?<version>[0-9]+[\.[0-9]+]*)"/

        m = regex.match("VERSION=\"0.0.0\"")

        # m = input.encode("utf-8", replace: nil).match(regex)

        return m[:version] if m[:version]

        "default"
      end

      def resolve_json
        @resolve_json ||= fetch_file_from_host("resolve.json")
        @resolve_json
      end

      def wscript
        @wscript ||= fetch_file_from_host("wscript")
      end

      def waf
        @waf ||= fetch_file_from_host("waf")
      end

      def lock_version_resolve_json
        return @lock_version_resolve_json if defined?(@lock_version_resolve_json)

        @lock_version_resolve_json ||= fetch_file_if_present("lock_version_resolve.json")
      end
    end
  end
end

Dependabot::FileFetchers
  .register("waf", Dependabot::Waf::FileFetcher)
