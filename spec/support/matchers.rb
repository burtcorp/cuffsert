require 'rspec'

RSpec::Matchers.define :have_hash_path do |expected|
  class BadInput < Exception ; end

  def extract_value(haystack, needles)
    needle, tail = needles
    if haystack.include?(needle)
      value = haystack[needle]
    else
      raise BadInput.new("No #{needle} in #{haystack}")
    end

    if tail
      if value.respond_to?(:include?)
        extract_value(value, tail)
      else
        raise BadInput.new("Can't look for #{tail} in #{value}")
      end
    else
      value
    end
  end

  match do |actual|
    unless expected.respond_to?(:each_pair)
      expected = {expected => anything}
    end
    expected.each_pair do |path, expect_one|
      res = begin
        values_match?(
          expect_one,
          extract_value(actual, path.split('/'))
        )
      rescue BadInput => e
        false
      end
      return false unless res
    end
    return true
  end
end
