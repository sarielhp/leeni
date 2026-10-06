# frozen_string_literal: true

# ==============================================================================
# lib/latex_it/version.rb
#
# Canonical version and executable path resolution for latex_it.
# ==============================================================================

module LatexIt
  VERSION = '1.0.49'.freeze
  EXECUTABLE = File.expand_path('../../latex_it', __dir__).freeze
end

VERSION = LatexIt::VERSION
LATEX_IT_EXECUTABLE = LatexIt::EXECUTABLE
