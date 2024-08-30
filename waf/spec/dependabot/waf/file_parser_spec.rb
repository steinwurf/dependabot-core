# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/waf/file_parser"
require "dependabot/dependency_file"
require "dependabot/source"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Waf::FileParser do
  let(:lockfile_fixture_name) { "bare_version_specified.json" }
  let(:manifest_fixture_name) { "bare_version_specified.json" }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "lock_version_resolve.json",
      content: fixture("lockfiles", lockfile_fixture_name)
    )
  end
  let(:manifest) do
    Dependabot::DependencyFile.new(
      name: "resolve.json",
      content: fixture("manifests", manifest_fixture_name)
    )
  end
  let(:files) { [manifest, lockfile] }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:parser) { described_class.new(dependency_files: files, source: source) }

  it_behaves_like "a dependency file parser"

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with only a manifest" do
      let(:files) { [manifest] }

      its(:length) { is_expected.to eq(2) }

      context "with an exact versions specified" do
        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("rng")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.0.1",
                file: "resolve.json",
                source: {
                  branch: "main",
                  ref: "1.0.1",
                  type: "git",
                  url: "https://gitlab.com/somewhere/rng.git"
                },
                groups: "checkout"
              }]
            )
          end
        end

        describe "uses unconventional git tag" do
          subject(:dependency) { dependencies.first }

          let(:manifest_fixture_name) { "unconventional_git_tag.json" }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("gtest-source")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq([{
              requirement: "release-1.11.0",
              file: "resolve.json",
              source: {
                branch: "main",
                ref: "release-1.11.0",
                type: "git",
                url: "https://github.com/google/googletest.git"
              },
              groups: "checkout"
            }])
          end
        end
      end

      context "with semver specified" do
        describe "the second dependency" do
          subject(:dependency) { dependencies.last }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("rng2")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: "1",
                file: "resolve.json",
                source: {
                  branch: "main",
                  ref: "1.0.0",
                  type: "git",
                  url: "https://gitlab.com/somewhere/rng2.git"
                },
                groups: "semver"
              }]
            )
          end
        end
      end

      context "with http resolves specified" do
        let(:manifest_fixture_name) { "http_git.json" }

        it "contructs an http type" do
          # The http dependency is not included.
          expect(dependencies.last.requirements).to eq(
            [{
              requirement: nil,
              file: "resolve.json",
              source: {
                type: "http",
                url: "gitlab.com/somewhere/release/v2.3.1/rng2.tar.gz"
              },
              groups: "http"
            }]
          )
        end
      end

      context "when the input is unparseable" do
        let(:manifest_fixture_name) { "unparseable" }

        it "raises a DependencyFileNotParseable error" do
          expect { parser.parse }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("resolve.json")
            end
        end
      end

      context "when there is no version number" do
        let(:manifest_fixture_name) { "blank_version" }

        it "raises a DependencyFileNotEvaluatable" do
          expect { parser.parse }
            .to raise_error(Dependabot::DependencyFileNotEvaluatable) do |error|
              expect(error.message).to include("No version where provided in the resolve.json file")
            end
        end
      end
    end

    context "with a lockfile" do
      its(:length) { is_expected.to eq(2) }

      context "when missing version number" do
        let(:lockfile_fixture_name) { "blank_version" }
        let(:manifest_fixture_name) { "blank_version" }

        it "raises a DependencyFileNotEvaluatable" do
          expect { parser.parse }
            .to raise_error(Dependabot::DependencyFileNotEvaluatable) do |error|
              expect(error.message).to include("No version where provided in the resolve.json or lockfile")
            end
        end
      end

      # context "when lock file is unparseable" do
      #  let(:lockfile_fixture_name) { "unparseable" }
      # end

      context "when the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("rng")
          expect(dependency.version).to eq("1.0.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.1",
              file: "resolve.json",
              groups: "checkout",
              source: {
                branch: "main",
                ref: "1.0.1",
                type: "git",
                url: "https://gitlab.com/somewhere/rng.git"
              }
            }]
          )
        end
      end

      describe "the second dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("rng2")
          expect(dependency.version).to eq("1.1.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1",
              file: "resolve.json",
              groups: "semver",
              source: {
                branch: "main",
                ref: "1.0.0",
                type: "git",
                url: "https://gitlab.com/somewhere/rng2.git"
              }
            }]
          )
        end
      end
    end
  end
end
