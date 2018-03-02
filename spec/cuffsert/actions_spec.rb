require 'cuffsert/actions'
require 'cuffsert/cfarguments'
require 'cuffsert/messages'
require 'cuffsert/metadata'
require 'rx'
require 'rx-rspec'
require 'spec_helpers'

shared_context 'action setup' do
  include_context 'changesets'
  include_context 'metadata'
  include_context 'stack events'
  include_context 'stack states'

  let(:cfmock) { double(:cfclient) }
  let(:confirm_update) { lambda { |*_| true } }

  subject do
    action = described_class.new(meta, stack)
    action.cfclient = cfmock
    action.confirmation = confirm_update
    action.as_observable
  end
end

describe CuffSert::CreateStackAction do
  include_context 'action setup'

  let(:stack) { nil }

  it 'creates it' do
    expect(cfmock).to receive(:create_stack)
      .with(CuffSert.as_create_stack_args(meta))
      .and_return(Rx::Observable.of(r1_done, r2_done))
    expect(subject).to emit_exactly(
      [:create, stack_name],
      r1_done,
      r2_done
    )
  end

  context 'given rejection' do
    let(:confirm_update) { lambda { |*_| false } }

    it 'takes no action' do
      expect(subject).to emit_exactly(
        [:create, stack_name],
        CuffSert::Abort.new(/.*/)
      )
    end
  end
end

describe CuffSert::RecreateStackAction do
  include_context 'action setup'

  let(:stack) { stack_rolled_back }

  it 'deletes rolled-back stack before creating it again' do
    expect(cfmock).to receive(:delete_stack)
      .with(CuffSert.as_delete_stack_args(stack_rolled_back))
      .and_return(Rx::Observable.of(r1_deleted, r2_deleted))
    expect(cfmock).to receive(:create_stack)
      .with(CuffSert.as_create_stack_args(meta))
      .and_return(Rx::Observable.of(r1_done, r2_done))
    expect(subject).to emit_exactly(
      [:recreate, stack_rolled_back],
      r1_deleted,
      r2_deleted,
      r1_done,
      r2_done
    )
  end

  context 'given rejection' do
    let(:confirm_update) { lambda { |*_| false } }

    it 'aborts with neither deletion nor creation' do
      expect(cfmock).not_to receive(:delete_stack)
      expect(cfmock).not_to receive(:create_stack)
      expect(subject).to emit_exactly(
        [:recreate, stack_rolled_back],
        CuffSert::Abort.new(/.*/)
      )
    end
  end
end

describe CuffSert::UpdateStackAction do
  include_context 'action setup'

  let(:stack) { stack_complete }
  let(:change_set_stream) { Rx::Observable.of(change_set_ready) }

  before do
    expect(cfmock).to receive(:prepare_update)
      .with(CuffSert.as_update_change_set(meta))
      .and_return(change_set_stream)
  end

  context 'given confirmation' do
    it 'updates an existing stack' do
      expect(cfmock).to receive(:update_stack)
        .and_return(Rx::Observable.of(r1_done, r2_done))

      expect(subject).to emit_exactly(change_set_ready, r1_done, r2_done)
    end
  end

  context 'when change set failed' do
    let(:change_set_stream) { Rx::Observable.of(change_set_failed) }

    it 'does not update' do
      expect(cfmock).to receive(:abort_update)
        .and_return(Rx::Observable.empty)
      expect(cfmock).not_to receive(:update_stack)

      expect(subject).to emit_exactly(change_set_failed)
    end
  end

  context 'given rejection' do
    let(:confirm_update) { lambda { |*_| false } }

    it 'does not update' do
      expect(cfmock).to receive(:abort_update)
        .and_return(Rx::Observable.empty)
      expect(cfmock).not_to receive(:update_stack)

      expect(subject).to emit_exactly(change_set_ready, CuffSert::Abort.new(/.*/))
    end
  end
end
