# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/waf/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Waf::FileFetcher do
  let(:json_header) { { "content_type" => "application/json" } }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")
    stub_request(:get, url + "resolve.json?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "contents_resolve_json.json"),
        headers: json_header
      )

    stub_request(:get, url + "wscript?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "contents_wscript.json"),
        headers: json_header
      )

    stub_request(:get, url + "lock_version_resolve.json?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "contents_lock_version_resolve_json.json"),
        headers: json_header
      )

    stub_request(:get, url + "waf?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "contents_waf.json"),
        headers: json_header
      )

    allow(file_fetcher_instance).to receive(:commit).and_return("sha")
  end

  it_behaves_like "a dependency file fetcher"

  context "with a lockfile" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_waf_with_version.json"),
          headers: json_header
        )
    end

    it "fetches the lock_version_resolve.json, resolve.json and wscript" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(resolve.json waf wscript lock_version_resolve.json))
    end
  end

  context "without a lockfile" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_waf_without_lockfile.json"),
          headers: json_header
        )
      stub_request(:get, url + "lock_version_resolve.json?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404, headers: json_header)
    end

    it "fetches the resolve.json" do
      expect(file_fetcher_instance.files.map(&:name))
        .to include("resolve.json", "waf", "wscript")
    end

    it "provides the Waf version" do
      expect(file_fetcher_instance.ecosystem_versions).to eq({
        package_managers: { "waf" => "10.1.2" }
      })
    end
  end

  context "with waf file" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_waf_with_version.json"),
          headers: json_header
        )

      stub_request(:get, url + "waf?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: JSON.dump({ content: Base64.encode64("before VERSION=\"1.2.3\" after") }),
          headers: json_header
        )
    end

    it "fetches the waf file" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(lock_version_resolve.json resolve.json wscript waf))
    end

    it "provides the waf version" do
      expect(file_fetcher_instance.ecosystem_versions).to eq({
        package_managers: { "waf" => "1.2.3" }
      })
    end
  end

  context "without a resolve file" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_python.json"),
          headers: json_header
        )
      stub_request(:get, url + "resolve.json?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(status: 404, headers: json_header)
    end

    it "raises a DependencyFileNotFound error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
