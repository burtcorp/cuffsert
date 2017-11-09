require 'cuffsert/cfarguments'
require 'cuffsert/metadata'
require 'spec_helpers'
require 'tempfile'
require 'uri'

describe '#as_create_stack_args' do
  include_context 'metadata'
  include_context 'templates'

  subject { CuffSert.as_create_stack_args(meta) }

  it { should include(:timeout_in_minutes => CuffSert::TIMEOUT) }
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
    before { meta.stack_uri = URI.join('file:///', template_body.path) }
    subject { CuffSert.as_create_stack_args(meta) }

    it { should include(:template_body => template_json) }
    it { should_not include(:template_uri) }
  end

  context 'when meta parameters have no value' do
    let :meta do
      super().tap do |meta|
        meta.parameters = { 'ze-key' => nil }
      end
    end
    
    it do
      expect { subject }.to raise_error(/supply value for.*ze-key/i)
    end
  end

  context 'everything is a string' do
    let :meta do
      meta = CuffSert::StackConfig.new
      meta.tags = {'numeric' => 1}
      meta.parameters = {'bool' => true}
      meta.stack_uri = URI.parse(s3url)
      meta
    end

    it { should include(:tags => include({:key => 'numeric', :value => '1'})) }
    it do
      should include(:parameters => include(
        {:parameter_key => 'bool', :parameter_value => 'true'}
      ))
    end
  end
end

describe '#as_update_change_set' do
  include_context 'metadata'

  subject { CuffSert.as_update_change_set(meta) }

  it { should include(:change_set_name => meta.stackname) }
  it { should include(:use_previous_template => false) }
  it { should include(:change_set_type => 'UPDATE') }
  it { should_not include(:timeout_in_minutes) }
  
  context 'when meta parameters have no value' do
    let :meta do
      super().tap do |meta|
        meta.parameters = { 'ze-key' => nil }
      end
    end
    
    it 'should use previous value' do
      should include(:parameters => include({
        :parameter_key => 'ze-key',
        :use_previous_value => true
      }))
    end
  end
end

describe '#as_delete_stack_args' do
  include_context 'metadata'
  include_context 'stack states'

  subject { CuffSert.as_delete_stack_args(stack_rolled_back) }

  it { should include(:stack_name => stack_id) }
end
