require 'cuffit/cli_args'

describe 'CuffIt#parse_cli_args' do
  subject do |example|
    argv = example.metadata[:argv] || example.metadata[:description_args][0]
    CuffIt.parse_cli_args(argv)
  end

  
end
