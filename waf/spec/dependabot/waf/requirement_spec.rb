# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/waf/requirement"

RSpec.describe Dependabot::Waf::Requirement do
  subject(:requirement) { described_class.new(requirement_string) }

  let(:requirement_string) { "1" }

  describe ".new" do
    it { is_expected.to be_a(described_class) }

    context "with a blank string" do
      let(:requirement_string) { "" }

      it { is_expected.to eq(described_class.new(">= 0")) }
    end

    describe "major" do
      context "with a 1" do
        it { is_expected.to eq(described_class.new("~> 1")) }
      end

      context "with a 2" do
        let(:requirement_string) { "2" }

        it { is_expected.to eq(described_class.new("~> 2")) }
      end
    end

    describe "checkout" do
      context "with a specified version" do
        let(:requirement_string) { "1.1.4" }

        it { is_expected.to eq(described_class.new(">=1.1.4", "< 1.2.0")) }
      end
    end
  end
end
