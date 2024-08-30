# typed: strict
# frozen_string_literal: true

require "dependabot/waf/file_fetcher"
require "dependabot/waf/file_parser"
require "dependabot/waf/update_checker"
require "dependabot/waf/file_updater"
require "dependabot/waf/metadata_finder"
require "dependabot/waf/requirement"
require "dependabot/waf/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("waf", name: "waf", colour: "4A412A")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check("waf", ->(_) { true })
