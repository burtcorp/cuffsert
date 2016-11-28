require 'cuffsert/rxcfclient'

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

describe CuffSert::RxCFClient do
  let(:stack_id) { 'ze-id' }
  let(:stack_name) { 'ze-stack' }
  let(:example_stack) { {} }

  let :r1_done do
    {
      'EventId' => 'r1_done',
      'StackId' => stack_id,
      'LogicalResourceId' => 'resource1_id',
      'ResourceStatus' => 'CREATE_COMPLETE',
      'Timestamp' => '2013-08-23T01:02:28.025Z',
    }
  end

  let :r2_progress do
    {
      'EventId' => 'r2_progress',
      'StackId' => stack_id,
      'LogicalResourceId' => 'resource2_id',
      'ResourceStatus' => 'CREATE_IN_PROGRESS',
      'Timestamp' => '2013-08-23T01:02:28.025Z',
    }
  end

  let :r2_done do
    {
      'EventId' => 'r2_done',
      'StackId' => stack_id,
      'LogicalResourceId' => 'resource2_id',
      'ResourceStatus' => 'CREATE_COMPLETE',
      'Timestamp' => '2013-08-23T01:02:38.534Z',
    }
  end

  let :r2_rolled_back do
    {
      'EventId' => 'r2_rolled_back',
      'StackId' => stack_id,
      'LogicalResourceId' => 'resource2_id',
      'ResourceStatus' => 'DELETE_COMPLETE',
      'Timestamp' => '2013-08-23T01:02:38.534Z',
    }
  end

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

  let :stack_in_progress_events do
    { 'StackEvents' => [r1_done, r2_progress] }
  end

  let :stack_complete_events do
    { 'StackEvents' => [r1_done, r2_done] }
  end

  let :stack_rolled_back_events do
    {'StackEvents' => [r1_done, r2_rolled_back] }
  end

  context 'create succesful' do
    let :aws_mock do
      mock = double(:aws_mock)
      expect(mock).to receive(:create_stack)
        .and_return(stack_in_progress)
      expect(mock).to receive(:describe_stack_events)
        .at_least(3).times
        .and_return(
          stack_in_progress_events,
          stack_in_progress_events,
          stack_complete_events
        )
      expect(mock).to receive(:describe_stacks)
        .at_least(:twice)
        .and_return(
          stack_in_progress,
          stack_complete
        )
      mock
    end

    subject do
      described_class.new(aws_mock)
    end

    it 'produces an event stream' do
      events = subject.create_stack(example_stack)
      observe_expect(events).to eq(
        [r1_done, r2_progress, r2_done]
      )
    end
  end

  context 'create failed' do
    let :aws_mock do
      mock = double(:aws_mock)
      expect(mock).to receive(:create_stack)
        .and_return(stack_in_progress)
      expect(mock).to receive(:describe_stack_events)
        .at_least(:twice)
        .and_return(
          stack_in_progress_events,
          stack_rolled_back_events
        )
      expect(mock).to receive(:describe_stacks)
        .and_return(stack_rolled_back)
      mock
    end

    subject do
      described_class.new(aws_mock)
    end

    it 'produces an event stream' do
      events = subject.create_stack(example_stack)
      observe_expect(events).to eq(
        [r1_done, r2_progress, r2_rolled_back]
      )
    end
  end
end
