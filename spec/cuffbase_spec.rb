require 'cuffbase'
require 'spec_helpers'

describe CuffBase do
  include_context 'templates'
  
  let(:parameters) { {'from_template' => {'Default' => 'ze-default'}} }

  describe '.empty_from_template' do
    subject { CuffBase.empty_from_template(template_body) }
  
    context 'given a template without parameters' do
      it { should eq({}) }
    end

    context 'given a template with a parameter' do
      let(:template_json) { JSON.dump({'Parameters' => parameters}) }

      it { should include('from_template' => nil) }
    end
  end

  describe '.defaults_from_template' do
    subject { CuffBase.defaults_from_template(template_body) }

    context 'given a template with a parameter' do
      let(:template_json) { JSON.dump({'Parameters' => parameters}) }
 
      it { should include('from_template' => 'ze-default') }
    end
    
    context 'given a template without parameters' do
      it { should eq({}) }
    end
  end
end