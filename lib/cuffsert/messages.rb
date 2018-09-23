module CuffSert
  class Message
    attr_reader :message

    def initialize(message)
      @message = message
    end

    def ===(other)
      # For the benefit of value_matches? and regex
      other.is_a?(self.class) && (other.message === @message || @message === other.message)
    end

    def as_observable
      Rx::Observable.just(self)
    end
  end

  class Abort < Message ; end
  class Report < Message ; end
  class Done < Message
    def initialize
      super('Done.')
    end
  end
  class ChangeSet < Message ; end
end
