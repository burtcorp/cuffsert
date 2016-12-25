module CuffSert
  INPROGRESS_STATES = %w[
    CREATE_IN_PROGRESS
    UPDATE_IN_PROGRESS
    UPDATE_COMPLETE_CLEANUP_IN_PROGRESS
    UPDATE_ROLLBACK_IN_PROGRESS
    UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS
    DELETE_IN_PROGRESS
  ]

  GOOD_STATES = %w[
    CREATE_COMPLETE
    ROLLBACK_COMPLETE
    UPDATE_COMPLETE
    UPDATE_ROLLBACK_COMPLETE
    DELETE_COMPLETE
    DELETE_SKIPPED
  ]

  BAD_STATES = %w[
    CREATE_FAILED
    UPDATE_ROLLBACK_FAILED
    UPDATE_FAILED
    DELETE_FAILED
    FAILED
  ]

  FINAL_STATES = GOOD_STATES + BAD_STATES

  def self.state_category(state)
    if BAD_STATES.include?(state)
      :bad
    elsif GOOD_STATES.include?(state)
      :good
    elsif INPROGRESS_STATES.include?(state)
      :progress
    else
      raise 'Ye olde should-not-occur error'
    end
  end
end
