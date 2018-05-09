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
  let(:s3mock) { double(:s3client) }
  let(:confirm_update) { lambda { |*_| true } }

  subject do
    action = described_class.new(meta, stack)
    action.cfclient = cfmock
    action.s3client = s3mock
    action.confirmation = confirm_update
    action.as_observable
  end
end

shared_examples 'uploading' do
  context 'when the template is large' do
    include_context 'templates'

    let(:stack_path) { URI.join('file:///', template_body.path) }
    let(:meta) { super().tap { |meta| meta.stack_uri = stack_path } }
    let(:template_json) { format('{"key": "%s"}', '*' * 51201) }

    context 'and is given an s3 client (i.e. with --s3-upload-prefix)' do
      before do
        allow(s3mock).to receive(:upload).and_return([URI('s3://some-bucket/some-prefix.json'), Rx::Observable.just('OK')])
      end

      it 'uploads template' do
        expect(subject).to complete
        expect(s3mock).to have_received(:upload).with(stack_path)
      end
    end

    context 'and is not given an s3 client (i.e. without --s3-upload-prefix)' do
      let(:s3mock) { nil }

      it 'raise error if we received no S3 client' do
        expect { subject }.to raise_error(RuntimeError, /supply.*--s3-upload-prefix/i)
      end
    end
  end
end

describe CuffSert::CreateStackAction do
  include_context 'action setup'

  let(:stack) { nil }

  before do
    allow(cfmock).to receive(:create_stack).and_return(Rx::Observable.empty)
  end

  include_examples 'uploading'

  it 'creates it' do
    expect(cfmock).to receive(:create_stack)
      .with(CuffSert.as_create_stack_args(meta))
      .and_return(Rx::Observable.of(r1_done, r2_done))
    expect(subject).to emit_exactly(
      [:create, stack_name],
      r1_done,
      r2_done,
      CuffSert::Done.new
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

  before do
    allow(cfmock).to receive(:delete_stack).and_return(Rx::Observable.empty)
    allow(cfmock).to receive(:create_stack).and_return(Rx::Observable.empty)
  end

  include_examples 'uploading'

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
      r2_done,
      CuffSert::Done.new
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
    allow(cfmock).to receive(:prepare_update).and_return(change_set_stream)
    allow(cfmock).to receive(:update_stack).and_return(Rx::Observable.empty)
  end

  include_examples 'uploading'

  context 'given confirmation' do
    it 'updates an existing stack' do
      expect(cfmock).to receive(:prepare_update)
        .with(CuffSert.as_update_change_set(meta))
        .and_return(change_set_stream)
      expect(cfmock).to receive(:update_stack)
        .and_return(Rx::Observable.of(r1_done, r2_done))

      expect(subject).to emit_exactly(
        CuffSert::ChangeSet.new(change_set_ready), 
        r1_done, 
        r2_done, 
        CuffSert::Done.new
      )
    end
  end

  context 'when change set failed' do
    let(:change_set_stream) { Rx::Observable.of(change_set_failed) }

    it 'does not update' do
      expect(cfmock).to receive(:prepare_update)
        .with(CuffSert.as_update_change_set(meta))
        .and_return(change_set_stream)
      expect(cfmock).to receive(:abort_update)
        .and_return(Rx::Observable.empty)
      expect(cfmock).not_to receive(:update_stack)

      expect(subject).to emit_exactly(
        CuffSert::ChangeSet.new(change_set_failed), 
        CuffSert::Abort.new(/update failed:.*didn't contain/i)
      )
    end
  end

  context 'given rejection' do
    let(:confirm_update) { lambda { |*_| false } }

    it 'does not update' do
      expect(cfmock).to receive(:prepare_update)
        .with(CuffSert.as_update_change_set(meta))
        .and_return(change_set_stream)
      expect(cfmock).to receive(:abort_update)
        .and_return(Rx::Observable.empty)
      expect(cfmock).not_to receive(:update_stack)

      expect(subject).to emit_exactly(
        CuffSert::ChangeSet.new(change_set_ready), 
        CuffSert::Abort.new(/.*/)
      )
    end
  end
end
