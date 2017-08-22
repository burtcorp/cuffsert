require 'cuffsert/confirmation'
require 'spec_helpers'
require 'stringio'

describe 'CuffSert#need_confirmation' do
  include_context 'metadata'
  include_context 'stack states'
  include_context 'changesets'

  let :local_meta do
    meta.op_mode = :normal
    meta
  end

  subject do
    CuffSert.need_confirmation(local_meta, :update, change_set_ready)
  end

  context 'with adds' do
    let(:change_set_changes) { [r2_add] }
    it { should be(false) }
  end

  context 'with non-replace modify' do
    let(:change_set_changes) { [r1_modify] }
    it { should be(false) }
  end

  context 'with conditional replace' do
    let(:change_set_changes) { [r1_conditional_replace] }
    it { should be(true) }
  end

  context 'with known replacement' do
    let(:change_set_changes) { [r1_replace] }
    it { should be(true) }
  end

  context 'with delete' do
    let(:change_set_changes) { [r3_delete] }
    it { should be(true) }
  end
  
  context 'given dangerous_ok' do
    let :local_meta do
      meta.op_mode = :dangerous_ok
      meta
    end

    context 'with known replacement' do
      let(:change_set_changes) { [r1_replace] }
      it { should be(false) }
    end

    context 'with delete' do
      let(:change_set_changes) { [r3_delete] }
      it { should be(false) }
    end
  end
  
  context 'given stack create' do
    subject { CuffSert.need_confirmation(local_meta, :create, nil) }
    it { should be(false) }
  end

  context 'given stack recreate' do
    subject do
      CuffSert.need_confirmation(
        local_meta,
        :recreate,
        stack_rolled_back
      )
    end

    it { should be(true) }

    context 'with dangerous_ok' do
      let :local_meta do
        meta.op_mode = :dangerous_ok
        meta
      end

      it { should be(false) }
    end
  end
end

describe 'CuffSert#ask_confirmation' do
  let(:output) { StringIO.new }

  subject { CuffSert.ask_confirmation(input, output) }

  context 'given non-tty' do
    let(:input) { StringIO.new }

    it { should be(false) }
    it { expect(output.string).to eq('') }
  end

  # context 'given a tty saying yea' do
  #   let(:input) { double(:stdin, :isatty => true, :getc => 'Y') }
  #
  #   it { should be(true) }
  #   it { expect(output.string).to match(/continue/) }
  # end
  #
  # context 'given a tty saying nay' do
  #   let(:input) { double(:stdin, :isatty => true, :getc => 'n') }
  #
  #   it { should be(false) }
  #   it { expect(output.string).to match(/continue/) }
  # end
  #
  # context 'given a tty saying foo' do
  #   let(:input) { double(:stdin, :isatty => true, :getc => 'f') }
  #
  #   it { should be(false) }
  # end
end

describe 'CuffSert#confirmation' do
  include_context 'metadata'
  subject { CuffSert.confirmation(meta, :create, nil) }
  
  it 'yields true for :create' do
    expect(subject).to be(true)
  end
  
  context 'given dry_run' do
    let :meta do
      super().tap { |m| m.op_mode = :dry_run }
    end
  
    it 'always yields false' do
      expect(subject).to be(false)
    end
  end
end