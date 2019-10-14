require 'cuffsert/actions'
require 'cuffsert/cfarguments'
require 'cuffsert/messages'
require 'cuffsert/metadata'
require 'rx'
require 'rx-rspec'
require 'spec_helpers'

shared_context 'action setup' do
  include_context 'changesets'
  include_context 'stack events'
  include_context 'stack states'
  include_context 'templates'

  let(:cfmock) { double(:cfclient) }
  let(:s3mock) { double(:s3client) }
  let(:confirm_update) { lambda { |*_| true } }
  let(:stack_path) { URI.join('file:///', template_body.path) }
  let :meta do
    meta = CuffSert::StackConfig.new
    meta.selected_path = [stack_name.split(/-/)]
    meta.stack_uri = stack_path
    meta
  end

  subject do
    action = described_class.new(meta, stack)
    action.cfclient = cfmock
    action.s3client = s3mock
    action.confirmation = confirm_update
    action
  end
end

shared_examples 'uploading' do
  context 'when the template is large' do
    let(:template_json) { format('{"key": "%s"}', '*' * 51201) }

    context 'and is given an s3 client (i.e. with --s3-upload-prefix)' do
      before do
        allow(s3mock).to receive(:upload).and_return([URI('s3://some-bucket/some-prefix.json'), Rx::Observable.just('OK')])
      end

      it 'uploads template' do
        expect(subject.as_observable).to complete
        expect(s3mock).to have_received(:upload).with(stack_path)
      end
    end

    context 'and is not given an s3 client (i.e. without --s3-upload-prefix)' do
      let(:s3mock) { nil }

      it 'raise error if we received no S3 client' do
        expect { subject.as_observable }.to raise_error(RuntimeError, /supply.*--s3-upload-prefix/i)
      end
    end
  end
end

describe CuffSert::MessageAction do
  let :message do
    CuffSert::Message.new('A message')
  end

  subject do
    described_class.new(message)
  end

  it 'emits the message' do
    expect(subject.as_observable).to emit_exactly(message)
  end
end

describe CuffSert::CreateStackAction do
  include_context 'action setup'

  let(:stack) { nil }

  describe '#validate!' do
    it 'raises no error when all conditions are met' do
      expect { subject.validate! }.not_to raise_error
    end
    
    context 'given no template' do
      let(:meta) { super().tap {|m| m.stack_uri = nil } }
      
      it 'raises an error' do
        expect { subject.validate! }.to raise_error(RuntimeError, /template to create/)
      end
    end
  end

  before do
    allow(cfmock).to receive(:create_stack).and_return(Rx::Observable.empty)
  end

  include_examples 'uploading'

  it 'creates it' do
    expect(cfmock).to receive(:create_stack)
      .with(CuffSert.as_create_stack_args(meta))
      .and_return(Rx::Observable.of(r1_done, r2_done))
    expect(subject.as_observable).to emit_exactly(
      [:create, stack_name],
      r1_done,
      r2_done,
      CuffSert::Done.new
    )
  end

  context 'given rejection' do
    let(:confirm_update) { lambda { |*_| false } }

    it 'takes no action' do
      expect(subject.as_observable).to emit_exactly(
        [:create, stack_name],
        CuffSert::Abort.new(/.*/)
      )
    end
  end
end

describe CuffSert::RecreateStackAction do
  include_context 'action setup'

  let(:stack) { stack_rolled_back }

  describe '#validate!' do
    it 'raises no error when all conditions are met' do
      expect { subject.validate! }.not_to raise_error
    end
    
    context 'given no template' do
      let(:meta) { super().tap {|m| m.stack_uri = nil } }
      
      it 'raises an error' do
        expect { subject.validate! }.to raise_error(RuntimeError, /template to re-create/)
      end
    end
  end

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
    expect(subject.as_observable).to emit_exactly(
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
      expect(subject.as_observable).to emit_exactly(
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

  describe '#validate!' do
    it 'raises no error when all conditions are met' do
      expect { subject.validate! }.not_to raise_error
    end
    
    context 'given no template' do
      let(:meta) do
        super().tap do |m|
          m.stack_uri = nil
          m.tags = {'t' => 'v'}
        end
      end

      it 'raises no error since there are tags' do
        expect { subject.validate! }.not_to raise_error
      end

      context 'and no tags or parameters' do
        let(:meta) { super().tap {|m| m.tags = {} } }

        it 'raises an error' do
          expect { subject.validate! }.to raise_error(RuntimeError, /update without template/)
        end
      end
    end
  end

  let :prev_template_source do
    {'old' => 'stuff'}
  end

  before do
    allow(cfmock).to receive(:prepare_update).and_return(change_set_stream)
    allow(cfmock).to receive(:get_template).and_return(Rx::Observable.just(prev_template_source))
    allow(cfmock).to receive(:update_stack).and_return(Rx::Observable.empty)
  end

  include_examples 'uploading'

  context 'given confirmation' do
    before do
      allow(cfmock).to receive(:prepare_update).and_return(change_set_stream)
      allow(cfmock).to receive(:update_stack).and_return(Rx::Observable.of(r1_done, r2_done))
    end

    it 'updates an existing stack' do
      expect(subject.as_observable).to emit_exactly(
        CuffSert::Templates.new([prev_template_source, template_source]),
        CuffSert::ChangeSet.new(change_set_ready),
        r1_done,
        r2_done,
        CuffSert::Done.new
      )
      expect(cfmock).to have_received(:prepare_update)
        .with(CuffSert.as_update_change_set(meta, stack))
      expect(cfmock).to have_received(:update_stack)
      expect(cfmock).to have_received(:get_template)
        .with(meta)
    end

    context 'with a large template' do
      let :template_source do
        {'hew' => 's' * 51200 + 'tuff' }
      end

      before do
        allow(s3mock).to receive(:upload).and_return([URI('s3://some-bucket/some-prefix.json'), Rx::Observable.just('OK')])
      end

      it 'still emits the local template' do
        expect(subject.as_observable).to emit_include(
          CuffSert::Templates.new([prev_template_source, template_source]),
          CuffSert::Done.new
        )
      end
    end

    context 'but no template' do
      let :meta do
        super().tap do |m|
          m.stack_uri = nil
        end
      end

      it 'says to use the existing template' do
        expect(subject.as_observable).to emit_include(
          CuffSert::Templates.new([prev_template_source, prev_template_source]),
        )
        expect(cfmock).to have_received(:prepare_update).with(
          hash_including(:use_previous_template => true)
        )
      end
    end
  end

  context 'when change set failed' do
    let(:change_set_stream) { Rx::Observable.of(change_set_failed) }

    it 'does not update' do
      expect(cfmock).to receive(:prepare_update)
        .with(CuffSert.as_update_change_set(meta, stack))
        .and_return(change_set_stream)
      expect(cfmock).to receive(:abort_update)
        .and_return(Rx::Observable.empty)
      expect(cfmock).not_to receive(:update_stack)

      expect(subject.as_observable).to emit_exactly(
        CuffSert::Templates.new([prev_template_source, template_source]),
        CuffSert::ChangeSet.new(change_set_failed),
        CuffSert::Abort.new(/update failed:.*unknown reason/i)
      )
    end
  end

  context 'when change set contains no changes' do
    let(:change_set_stream) { Rx::Observable.of(change_set_no_changes) }

    it 'does not update, and ends with a NoChanges action' do
      expect(cfmock).to receive(:prepare_update)
        .with(CuffSert.as_update_change_set(meta, stack))
        .and_return(change_set_stream)
      expect(cfmock).to receive(:abort_update)
        .and_return(Rx::Observable.empty)
      expect(cfmock).not_to receive(:update_stack)

      expect(subject.as_observable).to emit_exactly(
        CuffSert::Templates.new([prev_template_source, template_source]),
        CuffSert::ChangeSet.new(change_set_no_changes),
        CuffSert::NoChanges.new
      )
    end
  end

  context 'given rejection' do
    let(:confirm_update) { lambda { |*_| false } }

    it 'does not update' do
      expect(cfmock).to receive(:prepare_update)
        .with(CuffSert.as_update_change_set(meta, stack))
        .and_return(change_set_stream)
      expect(cfmock).to receive(:abort_update)
        .and_return(Rx::Observable.empty)
      expect(cfmock).not_to receive(:update_stack)

      expect(subject.as_observable).to emit_exactly(
        CuffSert::Templates.new([prev_template_source, template_source]),
        CuffSert::ChangeSet.new(change_set_ready),
        CuffSert::Abort.new(/.*/)
      )
    end
  end
end
