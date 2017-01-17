module CuffSert
  class Abort
    attr_reader :message

    def initialize(message)
      @message = message
    end

    def ===(other)
      # For the benefit of value_matches? and regex
      other.is_a?(Abort) && (other.message === @message || @message === other.message)
    end

    def as_observable
      Rx::Observable.just(self)
    end
  end
end
