# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/waf/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Waf::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:dependency_source) { nil }
  let(:dependency_name) { "rng" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.3.0",
      requirements: [{
        file: "resolve.json",
        requirement: "1",
        groups: [],
        source: dependency_source
      }],
      package_manager: "waf"
    )
  end

  before do
    stub_request(:get, "https://example.com/status").to_return(
      status: 200,
      body: "Not GHES",
      headers: {}
    )
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "when dealing with a git source" do
      let(:dependency_source) do
        { type: "git", url: "https://github.com/my_fork/rng.git" }
      end

      it { is_expected.to eq("https://github.com/my_fork/rng") }

      context "when it doesn't match a supported source" do
        let(:dependency_source) do
          { type: "git", url: "https://example.com/my_fork/rng.git" }
        end

        it { is_expected.to be_nil }
      end
    end
  end
end
