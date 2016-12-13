require 'cuffsert/metadata'
require 'cuffsert/rxcfclient'
require 'spec_helpers'

describe CuffSert::RxCFClient do
  include_context 'metadata'
  include_context 'stack states'
  include_context 'stack events'

  let :cfargs do
    {}
  end

  let(:create_reply) { {:stack_id => stack_id} }

  context '#find_stack_blocking' do
    context 'finds a stack' do
      let :aws_mock do
        mock = double(:aws_mock)
        expect(mock).to receive(:describe_stacks)
          .with(:stack_name => stack_name)
          .and_return(stack_complete_describe)
        mock
      end

      subject { described_class.new(aws_mock).find_stack_blocking(meta) }

      it { should include(:stack_name => stack_name) }
    end

    let :aws_validation_error do
      Aws::CloudFormation::Errors::ValidationError.new(
        nil, 'Stack with id production does not exist'
      )
    end

    context 'finds nothing' do
      let :aws_mock do
        mock = double(:aws_mock)
        expect(mock).to receive(:describe_stacks)
          .and_raise(aws_validation_error)
        mock
      end

      subject { described_class.new(aws_mock).find_stack_blocking(meta) }

      it { should be(nil) }
    end
  end

  context 'create succesful' do
    let :aws_mock do
      mock = double(:aws_mock)
      expect(mock).to receive(:create_stack)
        .and_return(create_reply)
      expect(mock).to receive(:describe_stack_events)
        .with(:stack_name => stack_id)
        .at_least(:twice)
        .and_return(
          stack_in_progress_events,
          stack_complete_events
        )
      expect(mock).to receive(:describe_stacks)
        .at_least(:twice)
        .and_return(
          stack_in_progress_describe,
          stack_complete_describe
        )
      mock
    end

    subject do
      described_class.new(aws_mock)
    end

    it 'produces an event stream' do
      events = subject.create_stack(cfargs)
      observe_expect(events).to eq(
        [r1_done, r2_progress, r2_done]
      )
    end
  end

  context 'create failed with rollback' do
    let :aws_mock do
      mock = double(:aws_mock)
      expect(mock).to receive(:create_stack)
        .and_return(create_reply)
      expect(mock).to receive(:describe_stack_events)
        .at_least(:twice)
        .and_return(
          stack_in_progress_events,
          stack_rolled_back_events
        )
      expect(mock).to receive(:describe_stacks)
        .at_least(:twice)
        .and_return(
          stack_in_progress_describe,
          stack_rolled_back_describe
        )
      mock
    end

    subject do
      described_class.new(aws_mock)
    end

    it 'produces an event stream' do
      events = subject.create_stack(cfargs)
      observe_expect(events).to eq(
        [r1_done, r2_progress, r2_rolled_back]
      )
    end
  end
end
