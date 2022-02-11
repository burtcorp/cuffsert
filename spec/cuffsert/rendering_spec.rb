require 'cuffsert/rendering'
require 'spec_helpers'

describe CuffSert::JsonRenderer do
	include_context 'stack events'
	include_context 'changesets'
	include_context 'stack states'

	let(:output) { StringIO.new }
	let(:error) { StringIO.new }

	describe '#templates' do
		let(:current_template) { 'current_template' }
		let(:pending_template) { 'pending_template' }

		subject do |example|
			described_class.new(output, error, example.metadata).templates(current_template, pending_template)
			output.string
		end

		context 'when silent', :verbosity => 0 do
			it { should be_empty }
		end

		context 'when default verbosity' do
			it { should match(/current.*pending/) }
		end
	end

	describe '#change_set' do
		let(:changeset) { change_set_ready }

		subject do |example|
			described_class.new(output, error, example.metadata).change_set(changeset)
			output.string
		end

		context 'when silent', :verbosity => 0 do
			it { should be_empty }
		end

		context 'when default verbosity' do
			it { should match(/^{".*}$/) }
			it { should include('"change_set_id":"ze-change-set-id"') }
		end
	end

	describe '#event' do
		let(:event) { r2_done }

		subject do |example|
			described_class.new(output, error, example.metadata).event(event, nil)
			output.string
		end

		context 'when silent', :verbosity => 0 do
			it { should be_empty }
		end

		context 'when default verbosity' do
			it { should match(/^{".*}$/) }
			it { should include('"event_id":"r2_done"') }
		end
	end

	describe '#stack' do
		let(:stack) { stack_complete }

		subject do |example|
			described_class.new(output, error, example.metadata).stack(:create, stack)
			output.string
		end

		context 'when silent', :verbosity => 0 do
			it { should be_empty }
		end

		context 'when default verbosity' do
			it { should match(/^{".*}$/) }
			it { should match(/"stack_id":"#{stack_id}"/) }
		end
	end

	describe '#report' do
		let(:message) { CuffSert::Report.new('goodness') }

		subject do |example|
			described_class.new(output, error, example.metadata).report(message)
			output.string
		end

		before { expect(output.string).to be_empty }

		context 'when silent', :verbosity => 0 do
			it { should be_empty }
		end

		context 'when default verbosity' do
			it { should be_empty }
		end

		context 'when verbose', :verbosity => 2 do
			it { should include('goodness') }
		end
	end

	describe '#abort' do
		let(:message) { CuffSert::Abort.new('badness') }

		subject do |example|
			described_class.new(output, error, example.metadata).abort(message)
			error.string
		end

		before { expect(output.string).to be_empty }

		context 'when silent', :verbosity => 0 do
			it { should be_empty }
		end

		context 'when default verbosity' do
			it { should include('badness') }
		end
	end

	describe '#done' do
		subject do |example|
			output = StringIO.new
			described_class.new(output, StringIO.new, example.metadata).done(CuffSert::Done.new)
			output.string
		end

		context 'when verbose', :verbosity => 2 do
			it { should be_empty }
		end
	end
end

describe CuffSert::ProgressbarRenderer do
	include_context 'stack states'
	include_context 'stack events'

	let :current_template do
		{}
	end

	let :pending_template do
		{}
	end

	let(:resource) do
		event.to_h.merge!(
			:states => [CuffSert.state_category(event[:resource_status])]
		)
	end

	describe '#event' do
		subject do |example|
			output = StringIO.new
			described_class.new(output, StringIO.new, example.metadata).event(event, resource)
			output.string
		end

		context 'given an failed event' do
			let(:event) { r2_failed }

			context 'when silent', :verbosity => 0 do
				it { should be_empty }
			end

			context 'when default verbosity' do
				it { should match(/resource2_name/) }
				it { should include('Insufficient permissions') }
			end

			context 'when verbose', :verbosity => 2 do
				it { should match(/resource2_name/) }
				it { should include('Insufficient permissions') }
			end
		end

		context 'given an in-progress event' do
			let(:event) { r2_progress }

			context 'when default verbosity' do
				it { should be_empty }
			end

			context 'when verbose', :verbosity => 2 do
				it { should match(/in.progress/i) }
			end
		end

		context 'given a successful event' do
			let(:event) { r2_done }

			context 'when default verbosity' do
				it { should be_empty }
			end

			context 'when verbose', :verbosity => 2 do
				it { should match(/complete/i) }
			end
		end
	end

	describe '#clear' do
		subject do |example|
			output = StringIO.new
			described_class.new(output, StringIO.new, example.metadata).clear
			output.string
		end

		context 'when silent', :verbosity => 0 do
			it { should be_empty }
		end

		context 'when default verbosity' do
			it { should eq("\r") }
		end
	end


	describe '#resource' do
		subject do |example|
			output = StringIO.new
			described_class.new(output, StringIO.new, example.metadata).resource(resource)
			output.string
		end

		context 'given a successful event' do
			let(:resource) { r2_done.to_h.merge({:states => [:good]}) }

			context 'when silent', :verbosity => 0 do
				it { should be_empty }
			end

			context 'when default verbosity' do
				it { should_not be_empty }
			end
		end

		context 'given bad :states' do
			let(:resource) { r2_progress.to_h.merge({:states => []}) }
			it { expect { subject }.to raise_error(/:states/) }
		end
	end

	describe '#templates' do
		subject do |example|
			output = StringIO.new
			error = StringIO.new
			presenter = described_class.new(output, error, example.metadata)
			presenter.templates(current_template, pending_template)
			output.string
		end

		it { should be_empty }

		context 'given an added condition' do
			let :pending_template do
				{'Conditions' => { 'ACondition' => {'Fn::Equals' => ['yes', 'no']}}}
			end

			it { should match(/\+.*ACondition/) }

			context 'when silent', :verbosity => 0 do
				it { should be_empty }
			end
		end

		context 'given an added parameter' do
			let :pending_template do
				{'Parameters' => {'AParam' => {'Type' => 'String'}}}
			end

			it { should match(/\+.*AParam.*Type.*String/) }

			context 'when silent', :verbosity => 0 do
				it { should be_empty }
			end
		end

		context 'given an added mapping' do
			let :pending_template do
				{'Mappings' => {'AMapping' => {'Value' => 'foo'}}}
			end

			it { should match(/\+.*AMapping.*Value.*foo/) }

			context 'when silent', :verbosity => 0 do
				it { should be_empty }
			end
		end

		context 'given an added output' do
			let :pending_template do
				{'Outputs' => {'AnOutput' => {'Value' => 'foo'}}}
			end

			it { should match(/\+.*AnOutput.*Value.*foo/) }

			context 'when silent', :verbosity => 0 do
				it { should be_empty }
			end
		end
	end

	describe '#change_set' do
		include_context 'changesets'

		let :current_template do
			{'Resources' => {}}
		end

		subject do
			output = StringIO.new
			presenter = described_class.new(output)
			presenter.templates(current_template, pending_template)
			presenter.change_set(changeset)
			output.string
		end

		context 'given an update changeset' do
			let(:changeset) { change_set_ready }

			context 'with an addition' do
				let(:change_set_changes) { [r2_add] }

				let :pending_template do
					{'Resources' => {'resource2_id' => {'Properties' => {'Foo' => 'Bar'}}}}
				end

				it { should match(/Updating.*ze-stack/) }
				it { should include('resource2_id') }
				it { should_not match(/\+/) }
			end

			context 'with a non-replacing changeset' do
				let(:change_set_changes) { [r1_modify] }

				let :current_template do
					{'Resources' => {'resource1_id' => {'Properties' => {'Foo' => 'Bar'}}}}
				end

				let :pending_template do
					{'Resources' => {'resource1_id' => {'Properties' => {'Foo' => 'Baz'}}}}
				end

				it { should include('Modify'.colorize(:yellow)) }
				it { should match(/Properties.*Foo/)}
				it { should match(/~.*Foo:.*Bar.*Baz/)}
			end

			context 'when a tag is modified' do
				let(:change_set_changes) { [r1_modify_tag] }

				let :change_set_changes do
					[
						Aws::CloudFormation::Types::ResourceChange.new({
							:action => 'Modify',
							:replacement => 'Never',
							:logical_resource_id => 'resource1_id',
							:resource_type => 'AWS::EC2::VPC',
							:scope => ['Tags'],
							:details => [
								{
									:target => {
										:attribute => 'Tags',
									},
								}
							],
						})
					]
				end

				let :current_template do
					{'Resources' => {'resource1_id' => {'Properties' => {'Tags' => {'Foo' => 'Bar'}}}}}
				end

				let :pending_template do
					{'Resources' => {'resource1_id' => {'Properties' => {'Tags' => {'Foo' => 'Baz'}}}}}
				end

				it { should match(/~.*Foo:.*Bar.*Baz/)}
			end

			context 'with an unconditional replacement' do
				let(:change_set_changes) { [r1_replace] }

				it { should include('Replace!'.colorize(:red)) }
			end

			context 'with a conditional replacement' do
				let(:change_set_changes) { [r1_conditional_replace] }

				it { should include('Replace?'.colorize(:red)) }
			end

			context 'with several changes' do
				let(:change_set_changes) { [r3_delete, r1_replace, r2_add, r1_conditional_replace] }
				it('sorts according to action') do
					should match(/add.*replace\?.*replace!.*remove/im)
				end
			end
		end
	end

	describe '#report' do
		let(:output) { StringIO.new }
		let(:error) { StringIO.new }

		subject do |example|
			described_class.new(output, error, example.metadata).abort(message)
			error.string
		end

		before do
			expect(output.string).to be_empty
		end

		context 'given a simple report message' do
			let(:message) { CuffSert::Abort.new('goodness') }

			context 'when silent', :verbosity => 0 do
				it { should be_empty }
			end

			context 'whenn default verbosity' do
				it { should include('goodness'.colorize(:red)) }
			end
		end
	end


	describe '#abort' do
		let(:output) { StringIO.new }
		let(:error) { StringIO.new }

		subject do |example|
			described_class.new(output, error, example.metadata).abort(message)
			error.string
		end

		before do
			expect(output.string).to be_empty
		end

		context 'given a simple abort message' do
			let(:message) { CuffSert::Abort.new('badness') }

			context 'when silent', :verbosity => 0 do
				it { should be_empty }
			end

			context 'whenn default verbosity' do
				it { should include('badness'.colorize(:red)) }
			end
		end

		context 'when given an exception' do
			let(:message) { RuntimeError.new('badness') }

			context 'when silent', :verbosity => 0 do
				it { should be_empty }
			end

			context 'when default verbosity' do
				it { should include('badness'.colorize(:red)) }
			end
		end
	end

	describe '#done' do
		subject do |example|
			output = StringIO.new
			described_class.new(output, StringIO.new, example.metadata).done(CuffSert::Done.new)
			output.string
		end

		context 'when silent', :verbosity => 0 do
			it { should be_empty }
		end

		context 'when default verbosity' do
			it { should match(/done/i) }
		end
	end

	context 'given a stack rreate' do
		subject do
			output = StringIO.new
			described_class.new(output).stack(:create, stack_name)
			output.string
		end

		it { should match(/Creating.*ze-stack/) }
	end


	context 'given a stack recreate' do
		subject do
			output = StringIO.new
			described_class.new(output).stack(:recreate, stack_rolled_back)
			output.string
		end

		it { should include('re-creating') }
	end
end
