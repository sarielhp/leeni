# frozen_string_literal: true

class LaTeXIndicator
  @thr = nil
  @t0 = nil
  @active = false

  def self.start(label, enabled: true, delay: 0.2)
    return unless enabled

    stop(clear: false, enabled: true)
    already_active = @active
    @t0 ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)

    if already_active
      print "\r\e[2K#{Rainbow('  ▸ ').cyan}#{label}"
      $stdout.flush
    end

    @thr = Thread.new do
      unless already_active
        sleep delay
        @active = true
        print "\r\e[2K#{Rainbow('  ▸ ').cyan}#{label}"
        $stdout.flush
      end

      loop do
        sleep 1.0
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @t0).round
        print "\r\e[2K#{Rainbow('  ▸ ').cyan}#{label} [#{elapsed}s]"
        $stdout.flush
      end
    rescue StandardError
      nil
    end
  end

  def self.stop(clear: false, enabled: true)
    return unless enabled

    if @thr
      begin
        @thr.kill
      rescue StandardError
        nil
      end
      begin
        @thr.join(0.05)
      rescue StandardError
        nil
      end
      @thr = nil
    end

    return unless clear

    print "\r\e[2K" if @active
    $stdout.flush
    @active = false
    @t0 = nil
  end
end
