# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/waf/update_checker"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/requirements_update_strategy"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Waf::UpdateChecker do
  let(:dependency_version) { "v1.1.38" }
  let(:dependency_name) { "rng" }
  let(:dependency_organization) { "somewhere" }
  let(:dependency_source) { { branch: nil, ref: "v1.1.38", type: "git", url: "https://github.com/somewhere/rng" } }
  let(:requirements) do
    [{ file: "resolve.json", requirement: "1", groups: ["semver"], source: dependency_source }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "waf"
    )
  end
  let(:lockfile_fixture_name) { "bare_version_specified.json" }
  let(:manifest_fixture_name) { "bare_version_specified.json" }
  let(:waf_fixture_name) { "waf" }
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "resolve.json",
        content: fixture("manifests", manifest_fixture_name)
      ),
      # Dependabot::DependencyFile.new(
      #   name: "lock_version_resolve.json",
      #   content: fixture("lockfiles", lockfile_fixture_name)
      # ),
      Dependabot::DependencyFile.new(
        name: "waf",
        content: fixture("git_repo_responses", "waf")
      )
    ]
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:requirements_update_strategy) { nil }
  let(:security_advisories) { [] }
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      requirements_update_strategy: requirements_update_strategy
    )
  end
  let(:git_repo_fixture_name) { "#{dependency_name}" }
  let(:git_repo_response) { fixture("git_repo_responses", git_repo_fixture_name) }
  let(:git_repo_url) { "https://github.com/somewhere/#{dependency_name}.git" }

  let(:git_fixture_name) { "#{dependency_name}.json" }
  # let(:git_response) { fixture("git_responses", git_fixture_name) }
  let(:git_clone_response) { fixture("git_repo_responses", "rng_clone") }

  before do
    git_header = {
      "content-type" => "application/x-git-upload-pack-advertisement"
    }
    git_header_result = { "content-type" => "application/x-git-upload-pack-result" }
    stub_request(:get, git_repo_url + "/info/refs?service=git-upload-pack")
      .with(basic_auth: %w(x-access-token token))
      .to_return(
        status: 200,
        body: git_repo_response,
        headers: git_header
      )
    stub_request(:post, git_repo_url + "/git-upload-pack")
      .with(basic_auth: %w(x-access-token token))
      .to_return(
        status: 200, body: git_clone_response, headers: git_header_result
      )
  end

  it_behaves_like "an update checker"

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "when given an outdated dependency" do
      let(:dependency_name) { "tunnel" }
      let(:dependency_version) { "v13.0.0" }
      let(:dependency_source) { { branch: nil, ref: "v13.0.0", type: "git", url: "https://github.com/steinwurf/tunnel" } }
      let(:requirements) do
        [{ file: "resolve.json", requirement: "13", groups: ["semver"], source: dependency_source }]
      end
      let(:git_repo_url) { "https://github.com/steinwurf/#{dependency_name}.git" }
      let(:git_clone_response) { fixture("git_repo_responses", dependency_name) }

      let(:lockfile_fixture_name) { "version_only_semver.json" }
      let(:manifest_fixture_name) { "version_only_semver.json" }

      before do
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        git_header_result = { "content-type" => "application/x-git-upload-pack" }
        stub_request(:get, git_repo_url + "/info/refs?service=git-upload-pack")
          .with(basic_auth: %w(x-access-token token))
          .to_return(
            status: 200,
            body: git_repo_response,
            headers: git_header
          )
        stub_request(:post, git_repo_url + "/git-upload-pack")
          .with(basic_auth: %w(x-access-token token))
          .to_return(
            status: 200, body: git_clone_response, headers: git_header_result
          )
      end

      it { is_expected.to be_truthy }
    end

    context "when given an up-to-date dependency" do
      let(:dependency_version) { "2.1.0" }

      it { is_expected.to be_falsey }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    it { is_expected.to eq(Gem::Version.new("2.1.0")) }

    context "when using semver" do
      # TODO: There should be a mock of a GitHub tags response,
      # which includes newer and older major versions of the "library"

      it { is_expected.to eq(Gem::Version.new("2.1.0")) }
    end

    context "when using checkout" do
      let(:requirements) do
        [{ file: "resolve.json", requirement: "1.1.38", groups: ["checkout"], source: dependency_source }]
      end

      it { is_expected.to eq(Gem::Version.new("2.1.0")) }
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    let(:dependency_version) { "v13.0.0" }
    let(:dependency_name) { "tunnel" }
    let(:dependency_organization) { "somewhere" }
    let(:dependency_source) { { branch: nil, ref: "v13.0.0", type: "git", url: "https://github.com/steinwurf/tunnel" } }
    let(:requirements) do
      [{ file: "resolve.json", requirement: "13", groups: ["semver"], source: dependency_source }]
    end
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: dependency_version,
        requirements: requirements,
        package_manager: "waf"
      )
    end

    let(:git_repo_url) { "https://github.com/steinwurf/#{dependency_name}.git" }
    let(:git_repo_response) { fixture("git_repo_responses", dependency_name) }

    before do
      git_header = {
        "content-type" => "application/x-git-upload-pack-advertisement"
      }
      git_header_result = { "content-type" => "application/x-git-upload-pack" }
      stub_request(:get, git_repo_url + "/info/refs?service=git-upload-pack")
        .with(basic_auth: %w(x-access-token token))
        .to_return(
          status: 200,
          body: git_repo_response,
          headers: git_header
        )
      stub_request(:post, git_repo_url + "/git-upload-pack")
        .with(basic_auth: %w(x-access-token token))
        .to_return(
          status: 200, body: git_clone_response, headers: git_header_result
        )
    end

    context "when using semver" do
      let(:lockfile_fixture_name) { "version_only_semver.json" }
      let(:manifest_fixture_name) { "version_only_semver.json" }

      it { is_expected.to eq(Gem::Version.new("14.1.1")) }
    end

    context "when using checkout" do
      let(:lockfile_fixture_name) { "version_only_checkout.json" }
      let(:manifest_fixture_name) { "version_only_checkout.json" }

      let(:requirements) do
        [{ file: "resolve.json", requirement: "13.0.0", groups: ["checkout"], source: dependency_source }]
      end

      it { is_expected.to eq(Gem::Version.new("14.1.1")) }
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { checker.latest_resolvable_version_with_no_unlock }

    let(:dependency_version) { "v13.0.0" }
    let(:dependency_name) { "tunnel" }
    let(:dependency_organization) { "somewhere" }
    let(:dependency_source) { { branch: nil, ref: "v13.0.0", type: "git", url: "https://github.com/steinwurf/tunnel" } }
    let(:requirements) do
      [{ file: "resolve.json", requirement: "13", groups: ["semver"], source: dependency_source }]
    end
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: dependency_version,
        requirements: requirements,
        package_manager: "waf"
      )
    end

    let(:git_repo_url) { "https://github.com/steinwurf/#{dependency_name}.git" }
    let(:git_repo_response) { fixture("git_repo_responses", dependency_name) }

    before do
      git_header = {
        "content-type" => "application/x-git-upload-pack-advertisement"
      }
      git_header_result = { "content-type" => "application/x-git-upload-pack" }
      stub_request(:get, git_repo_url + "/info/refs?service=git-upload-pack")
        .with(basic_auth: %w(x-access-token token))
        .to_return(
          status: 200,
          body: git_repo_response,
          headers: git_header
        )
      stub_request(:post, git_repo_url + "/git-upload-pack")
        .with(basic_auth: %w(x-access-token token))
        .to_return(
          status: 200, body: git_clone_response, headers: git_header_result
        )
    end

    context "when using semver" do
      let(:lockfile_fixture_name) { "version_only_semver.json" }
      let(:manifest_fixture_name) { "version_only_semver.json" }

      it { is_expected.to eq(Gem::Version.new("13.1.0")) }
    end

    context "when using checkout" do
      let(:lockfile_fixture_name) { "version_only_checkout.json" }
      let(:manifest_fixture_name) { "version_only_checkout.json" }

      let(:requirements) do
        [{ file: "resolve.json", requirement: "13.0.0", groups: ["checkout"], source: dependency_source }]
      end

      it { is_expected.to eq(Gem::Version.new("13.0.0")) }
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements }

    let(:dependency_version) { "v13.0.0" }
    let(:dependency_name) { "tunnel" }
    let(:dependency_organization) { "somewhere" }
    let(:dependency_source) { { branch: nil, ref: "v13.0.0", type: "git", url: "https://github.com/steinwurf/tunnel" } }
    let(:requirements) do
      [{ file: "resolve.json", requirement: "13", groups: ["semver"], source: dependency_source }]
    end
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: dependency_version,
        requirements: requirements,
        package_manager: "waf"
      )
    end

    let(:git_repo_url) { "https://github.com/steinwurf/#{dependency_name}.git" }
    let(:git_repo_response) { fixture("git_repo_responses", dependency_name) }

    context "when using semver" do
      let(:lockfile_fixture_name) { "version_only_semver.json" }
      let(:manifest_fixture_name) { "version_only_semver.json" }

      let(:dependency_source) { { branch: nil, ref: "v13.0.0", type: "git", url: "https://github.com/steinwurf/tunnel" } }
      let(:requirements) do
        [{ file: "resolve.json", requirement: "13", groups: ["semver"], source: dependency_source }]
      end

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater)
          .to receive(:new)
          .with(
            requirements: requirements,
            updated_source: {
              branch: nil,
              ref: "v13.0.0",
              type: "git",
              url: "https://github.com/steinwurf/tunnel"
            },
            target_version: "14.1.1",
            update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersions
          )
          .and_call_original
        expect(checker.updated_requirements)
          .to eq(
            [{
              file: "resolve.json",
              requirement: "14",
              groups: ["semver"],
              source: { branch: nil, ref: "v13.0.0", type: "git", url: "https://github.com/steinwurf/tunnel" }
            }]
          )
      end
    end

    context "when using multiple dependencies" do
      let(:lockfile_fixture_name) { "version_only_semver_multi.json" }
      let(:manifest_fixture_name) { "version_only_semver_multi.json" }

      let(:dependency_source) { { branch: nil, ref: "v13.0.0", type: "git", url: "https://github.com/steinwurf/tunnel" } }
      let(:requirements) do
        [{ file: "resolve.json", requirement: "13", groups: ["semver"], source: dependency_source }]
      end

      it "updates the correct dependency" do
        expect(described_class::RequirementsUpdater)
          .to receive(:new)
          .with(
            requirements: requirements,
            updated_source: {
              branch: nil,
              ref: "v13.0.0",
              type: "git",
              url: "https://github.com/steinwurf/tunnel"
            },
            target_version: "14.1.1",
            update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersions
          ).and_call_original
        expect(checker.updated_requirements)
          .to eq(
            [{
              file: "resolve.json",
              requirement: "14",
              groups: ["semver"],
              source: { branch: nil, ref: "v13.0.0", type: "git", url: "https://github.com/steinwurf/tunnel" }
            }]
          )
      end
    end

    context "when using checkout" do
      let(:lockfile_fixture_name) { "version_only_checkout.json" }
      let(:manifest_fixture_name) { "version_only_checkout.json" }

      let(:dependency_source) { { branch: nil, ref: "v13.0.0", type: "git", url: "https://github.com/steinwurf/tunnel" } }
      let(:requirements) do
        [{ file: "resolve.json", requirement: "13.0.0", groups: ["checkout"], source: dependency_source }]
      end

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater)
          .to receive(:new)
          .with(
            requirements: requirements,
            updated_source: {
              branch: nil,
              ref: "v13.0.0",
              type: "git",
              url: "https://github.com/steinwurf/tunnel"
            },
            target_version: "14.1.1",
            update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersions
          ).and_call_original
        expect(checker.updated_requirements)
          .to eq(
            [{
              file: "resolve.json",
              requirement: "14.1.1",
              groups: ["checkout"],
              source: { branch: nil, ref: "v13.0.0", type: "git", url: "https://github.com/steinwurf/tunnel" }
            }]
          )
      end
    end
  end
end
