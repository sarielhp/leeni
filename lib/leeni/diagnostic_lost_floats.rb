# frozen_string_literal: true

# ==============================================================================
# lib/leeni/diagnostic_lost_floats.rb
#
# "Float(s) lost" moved to its cause: the \marginpar or float started inside a
# box, which the runtime hook (LaTeXBuilder::FLOAT_BOX_HOOK) logs as
# LEENI_FLOAT_IN_BOX:<line>:<kind>.
# Part of LaTeXDiagnostics (lib/leeni/diagnostics.rb), which includes it.
# ==============================================================================

module LaTeXDiagnostics
  # LaTeX notices a lost float at the next \clearpage, often pages after the
  # \marginpar or float that went into a box, and the float it names may be an
  # innocent later one. Each "Float(s) lost" error is moved to the first marker
  # logged since the previous such error; without a marker it stays where TeX
  # put it, with the catalogue's generic hint.
  module LostFloats
    FLOAT_IN_BOX_MARKER = /^LEENI_FLOAT_IN_BOX:(\d+):(\S+)/

    # The indices are those of extract_errors, which reads the same lines.
    def relocate_lost_floats!(err_items, content)
      lost = err_items.select { |item| item[:catalog_id] == :float_lost }
      return err_items if lost.empty?

      markers = collect_float_in_box_markers(content)
      previous = -1
      lost.sort_by { |item| item[:index] }.each do |item|
        found = markers.select { |m| m[:index] > previous && m[:index] < item[:index] }
        previous = item[:index]
        relocate_lost_float(item, found) unless found.empty?
      end
      err_items
    end

    private

    def collect_float_in_box_markers(content)
      file_stack = [@filename]
      lines = join_error_continuations(LaTeXUtils.filter_subcommand_noise(content)).lines
      lines.each_with_index.filter_map do |line, idx|
        track_log_file(line, file_stack)
        m = FLOAT_IN_BOX_MARKER.match(line)
        m && { index: idx, file: current_log_file(file_stack), line: m[1].to_i, kind: m[2] }
      end
    end

    def relocate_lost_float(item, found)
      culprit = found.first
      noticed = "#{File.basename(item[:file].to_s)}:#{item[:line]}"
      item.merge!(file: culprit[:file], line: culprit[:line], line_str: culprit[:line].to_s,
                  root_line: nil, root_col: nil)
      item[:catalog] = (item[:catalog] || {}).merge(hint: lost_float_hint(culprit, noticed, found.size - 1),
                                                    root_line: nil, root_col: nil)
      # --emacs prints the raw block, whose first line AUCTeX reads as file:line.
      item[:err_block] = [item[:err_block].first.to_s.sub(/\A.*?:\d+:/, "#{culprit[:file]}:#{culprit[:line]}:"),
                          *item[:err_block].drop(1)]
      item[:formatted] = format_error_block(item[:err_block], culprit[:line], catalog: item[:catalog], item: item)
    end

    def lost_float_hint(culprit, noticed, others)
      what = if culprit[:kind] == 'marginpar'
               'a \\marginpar (maybe from a macro such as \\todo or a comment macro)'
             else
               "a #{culprit[:kind]} environment"
             end
      more = others.positive? ? " (and #{others} more after it)" : ''
      "#{what} starts here inside a box, float or caption, so it never reaches the page#{more}; " \
        "LaTeX noticed the lost float only at #{noticed}"
    end
  end
end
