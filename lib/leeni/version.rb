# frozen_string_literal: true

# ==============================================================================
# lib/leeni/version.rb
#
# Canonical version and executable path resolution for leeni.
# ==============================================================================

module Leeni
  VERSION = '1.0.49'.freeze
  EXECUTABLE = File.expand_path('../../leeni', __dir__).freeze
end

VERSION = Leeni::VERSION
LEENI_EXECUTABLE = Leeni::EXECUTABLE
