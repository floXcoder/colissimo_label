lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'colissimo_label/version'

Gem::Specification.new do |spec|
  spec.name    = 'colissimo_label'
  spec.version = ColissimoLabel::VERSION
  spec.authors = ['FloXcoder']
  spec.email   = ['flo@l-x.fr']

  spec.summary     = 'Generate Colissimo label for all countries'
  spec.description = 'Generate Colissimo label for all countries with customs declaration (Colissimo webservice account required).'
  spec.homepage    = 'https://github.com/floXcoder/colissimo_label'
  spec.license     = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'rails', '6.0.0'
  spec.add_dependency 'activesupport', '~> 6'
  spec.add_dependency 'rack', '~> 2'
  spec.add_dependency 'railties', '~> 6'
  spec.add_dependency 'http', '~> 4'

  spec.add_development_dependency 'bundler', '~> 2'
  spec.add_development_dependency 'rake', '~> 12'
  spec.add_development_dependency 'rspec', '~> 3'
  spec.add_development_dependency 'simplecov', '~> 0.16'
  spec.add_development_dependency 'webmock', '~> 3'
end
