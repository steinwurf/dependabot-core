# typed: false
# frozen_string_literal: true

require "json"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/waf/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"
RSpec.describe Dependabot::Waf::FileUpdater do
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }
  let(:previous_requirements) do
    [{ file: "resolve.json", requirement: "13", groups: ["semver"], source: nil }]
  end
  let(:requirements) { previous_requirements }
  let(:dependency_previous_version) { "13.0.0" }
  let(:dependency_version) { "13.0.0" }
  let(:dependency_name) { "tunnel" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "waf"
    )
  end
  let(:lockfile_fixture_name) { "version_only_semver.json" }
  let(:manifest_fixture_name) { "version_only_semver.json" }
  let(:lockfile_body) { fixture("lockfiles", lockfile_fixture_name) }
  let(:manifest_body) { fixture("manifests", manifest_fixture_name) }
  let(:waf_file_body) { fixture("git_repo_responses", "waf") }
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "lock_version_resolve.json", content: lockfile_body)
  end
  let(:manifest) do
    Dependabot::DependencyFile.new(name: "resolve.json", content: manifest_body)
  end
  let(:waf_file) do
    Dependabot::DependencyFile.new(name: "waf", content: waf_file_body)
  end
  let(:files) { [manifest, lockfile, waf_file] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com"
    }]
  end
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end

  before { FileUtils.mkdir_p(tmp_path) }

  it_behaves_like "a dependency file updater"
  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.not_to(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    it { expect { updated_files }.not_to output.to_stdout }
    its(:length) { is_expected.to eq(1) }

    context "without a lockfile" do
      let(:files) { [manifest] }

      context "when no files have changed" do
        it "raises a helpful error" do
          expect { updater.updated_dependency_files }
            .to raise_error("No files changed!")
        end
      end

      context "when the manifest has changed" do
        let(:requirements) do
          [{
            file: "resolve.json",
            requirement: "14",
            groups: ["semver"],
            source: nil
          }]
        end

        its(:length) { is_expected.to eq(1) }

        describe "the updated manifest" do
          subject(:updated_manifest_content) do
            updated_files.find { |f| f.name == "resolve.json" }.content
          end

          it "includes the new requirement" do
            expect(described_class::ManifestUpdater)
              .to receive(:new)
              .with(dependencies: [dependency], manifest: manifest)
              .and_call_original
            expect(JSON.parse(updated_manifest_content)).to include(JSON.parse(%({"name": "tunnel", "recurse": false, "resolver": "git", "method": "semver", "major": 14, "source": "github.com/steinwurf/tunnel.git"})))
          end
        end
      end
    end

    context "with a lockfile" do
      # Have to switch file since we are using WAF to update it.
      let(:lockfile_fixture_name) { "version_only_semver.json" }
      let(:manifest_fixture_name) { "version_only_semver.json" }

      let(:dependency_version) { "13.0.0" }
      let(:dependency_name) { "tunnel" }

      describe "the updated lockfile" do
        subject(:updated_lockfile_content) do
          updated_files.find { |f| f.name == "lock_version_resolve.json" }.content
        end

        it "updates the dependency version in the lockfile" do
          expect(described_class::LockfileUpdater)
            .to receive(:new)
            .with(
              credentials: credentials,
              dependencies: [dependency],
              dependency_files: files
            ).and_call_original

          expect(updated_lockfile_content)
            .to include(%("tunnel"))
          expect(updated_lockfile_content).not_to include(
            "bdc66374feba871dbe15583675582cc65dd01809"
          )
          expect(updated_lockfile_content).to include(
            "ca4dcff4c6bfea5a56b3126adbab1c134c39e651"
          )
        end
      end

      context "with checkout" do
        let(:lockfile_fixture_name) { "version_only_checkout.json" }
        let(:manifest_fixture_name) { "version_only_checkout.json" }

        let(:previous_requirements) do
          [{ file: "resolve.json", requirement: "13.0.0", groups: ["checkout"], source: nil }]
        end

        let(:requirements) do
          [{
            file: "resolve.json",
            requirement: "13.1.0",
            groups: ["checkout"],
            source: nil
          }]
        end

        describe "the updated lockfile" do
          subject(:updated_lockfile_content) do
            updated_files.find { |f| f.name == "lock_version_resolve.json" }.content
          end

          it "updates the dependency version in the lockfile" do
            expect(described_class::LockfileUpdater)
              .to receive(:new)
              .with(
                credentials: credentials,
                dependencies: [dependency],
                dependency_files: files
              ).and_call_original

            expect(updated_lockfile_content)
              .to include(%("tunnel"))
            expect(updated_lockfile_content).not_to include(
              "55f5d8f5109a32ad27de586ec4c4d49e86acfa73"
            )
            expect(updated_lockfile_content).to include(
              "ca4dcff4c6bfea5a56b3126adbab1c134c39e651"
            )
          end
        end
      end
    end
  end
end
