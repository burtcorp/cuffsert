configure do |rspec|
  rspec.shared_context_metadata_behavior = :apply_to_host_groups
end

shared_context 'stack states' do
  let :stack_complete do
    {
      'Stacks' => [{
        'StackId' => stack_id,
        'StackName' => stack_name,
        'StackStatus' => 'CREATE_COMPLETE',
      }]
    }
  end

  let :stack_in_progress do
    {
      'Stacks' => [{
        'StackId' => stack_id,
        'StackName' => stack_name,
        'StackStatus' => 'CREATE_IN_PROGRESS',
      }]
    }
  end

  let :stack_rolled_back do
    {
      'Stacks' => [{
        'StackId' => stack_id,
        'StackName' => stack_name,
        'StackStatus' => 'ROLLBACK_COMPLETE',
      }]
    }
  end
end

def observe_expect(subject)
  result = []
  error = nil
  Thread.new do
    spinlock = 1
    subject.subscribe(
      lambda { |event| result << event },
      lambda { |err| error = err ; spinlock -= 1 },
      lambda { spinlock -= 1 }
    )

    for n in 1..10
      break if spinlock == 0
      sleep(0.05)
    end
    raise 'timeout' if spinlock == 1
  end.join
  raise error if error
  expect(result)
end
