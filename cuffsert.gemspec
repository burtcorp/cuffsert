Gem::Specification.new do |spec|
  spec.name        = 'cuffsert'
  spec.version     = '0.5.0'
  spec.date        = '2016-11-28'
  spec.summary     = 'Cuffsert provides a quick up-arrow-enter loading of a CloudFormation stack with good feedback'
  spec.description = 'Cuffsert allows encoding the metadata and commandline arguments needed to load a template in a versionable file which takes CloudFormation the last mile to really become an infrastructure-as-code platform.'
  spec.authors     = ['Anders Qvist']
  spec.email       = 'bittrance@gmail.com'
  spec.homepage    = 'http://rubygems.org/gems/cuffsert'
  spec.license     = 'MIT'

  spec.executables = ['cuffsert']
  spec.files       = `git ls-files -z`.split("\x0").reject { |f| f.match(/^spec/) }

  spec.add_runtime_dependency 'aws-sdk'
  spec.add_runtime_dependency 'rx'

  spec.add_development_dependency 'bundler', '~> 1.12'
  spec.add_development_dependency 'byebug'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'simplecov'
end
