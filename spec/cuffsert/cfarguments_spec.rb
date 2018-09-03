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
    let(:meta) { super().tap { |m| m.tags = {'k1' => 'v1', 'k2' => 'v2'} } }

    it { should include(:tags => include({:key => 'k1', :value => 'v1'})) }
    it { should include(:tags => include({:key => 'k2', :value => 'v2'})) }
    it { should_not include(:parameters) }
  end

  context 'when stack uri is an s3 url' do
    it { should include(:template_url => amazonaws_url) }
    it { should_not include(:template_body) }
  end

  context 'when stack uri is an amazonaws https uri' do
    let(:meta) { super().tap { |meta| meta.stack_uri = URI.parse(amazonaws_url) } }
    it { should include(:template_url => amazonaws_url) }
    it { should_not include(:template_body) }
  end

  context 'when stack uri is some other https uri' do
    let(:meta) { super().tap { |meta| meta.stack_uri = URI.parse('https://www.google.com') } }
    it { expect { subject }.to raise_error(/amazonaws.com/) }
  end

  context 'when stack uri scheme is file:' do
    let(:meta) { super().tap { |meta| meta.stack_uri = URI.join('file:///', template_body.path) } }

    it { should include(:template_body => template_json) }
    it { should_not include(:template_url) }

    context 'which points to a large template' do
      let(:template_json) { format('{"key": "%s"}', '*' * 51201) }

      it { should_not include(:template_url) }
      it { should_not include(:template_body) }
    end

    context 'which points to a template with lots of whitespace' do
      let(:template_json) { format('{"key": %s""}', ' ' * 51201) }

      it { should_not include(:template_url) }
      it { should include(:template_body => '{"key":""}') }
    end
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
  include_context 'stack states'

  subject { CuffSert.as_update_change_set(meta, stack_complete) }

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

  context 'when the user did not pass a template' do
    let(:meta) { super().tap {|m| m.stack_uri = nil } }

    it 'says to use the current template' do
      should include(:use_previous_template => true)
    end

    it 'does not automatically include parameters or tags' do
      should_not include(:parameters, :tags)
    end

    context 'and the current stack has some parameters' do
      let :stack_complete do
        super().merge(
          :parameters => [
            {:parameter_key => 'p1', :parameter_value => 'v1'},
            {:parameter_key => 'p2', :parameter_value => 'v2'},
          ],
        )
      end

      it 'includes default parameters from existing stack' do
        should include(:parameters => [
          include(:use_previous_value => true),
          include(:use_previous_value => true),
        ])
      end

      context 'and the user wants to change parameters' do
        let(:meta) { super().tap { |m| m.parameters = {'p1' => 'specified'} } }

        it 'includes unchanged parameters from existing stack' do
          should include(:parameters => [
            {:parameter_key => 'p1', :parameter_value => 'specified'},
            {:parameter_key => 'p2', :use_previous_value => true},
          ])
        end
      end
    end

    context 'and the current stack has some tags' do
      let :stack_complete do
        super().merge(:tags => [{:key => 'k2', :value => 'v2'}])
      end

      it 'still does not include tags' do
        should_not include(:tags)
      end

      context 'and the user wants to change tags' do
        let(:meta) { super().tap { |m| m.tags = {'k1' => 'specified'} } }

        it 'includes unchanged tags from existing stack' do
          should include(:tags => [
            {:key => 'k1', :value => 'specified'},
            {:key => 'k2', :value => 'v2'},
          ])
        end
      end
    end
  end
end

describe '#as_delete_stack_args' do
  include_context 'metadata'
  include_context 'stack states'

  subject { CuffSert.as_delete_stack_args(stack_rolled_back) }

  it { should include(:stack_name => stack_id) }
end
