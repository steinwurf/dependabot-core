# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/waf"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Waf do
  it_behaves_like "it registers the required classes", "waf"
end
