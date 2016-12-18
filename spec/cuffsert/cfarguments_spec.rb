require 'cuffsert/cfarguments'
require 'cuffsert/metadata'
require 'spec_helpers'
require 'tempfile'
require 'uri'

describe '#as_create_stack_args' do
  include_context 'metadata'
  include_context 'templates'

  subject { CuffSert.as_create_stack_args(meta) }

  it { should_not include(:change_set_name) }

  context 'given tags' do
    it { should include(:tags => include({:key => 'k1', :value => 'v1'})) }
    it { should include(:tags => include({:key => 'k2', :value => 'v2'})) }
    it { should_not include(:parameters) }
  end

  context 'when stack uri is an s3 url' do
    it { should include(:template_url => s3url) }
    it { should_not include(:template_body) }
  end

  context 'when stack uri is file' do
    subject do
      meta.stack_uri = URI.join('file:///', template_body.path)
      CuffSert.as_create_stack_args(meta)
    end

    it { should include(:template_body => template_json) }
    it { should_not include(:template_uri) }
  end
end

describe '#as_update_change_set' do
  include_context 'metadata'

  subject do
    CuffSert.as_update_change_set(meta)
  end

  it { should include(:change_set_name => meta.stackname) }
  it { should include(:use_previous_template => false) }
  it { should include(:change_set_type => 'UPDATE') }
  it { should_not include(:timeout_in_minutes) }
end

describe '#as_delete_stack_args' do
  include_context 'metadata'

  let(:stackname) { 'ze-stack' }

  let :meta do
    meta = CuffSert::StackConfig.new
    meta.stackname = stackname
    meta
  end

  subject { CuffSert.as_delete_stack_args(meta) }

  it { should include(:stack_name => stackname) }
end
