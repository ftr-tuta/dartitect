Pod::Spec.new do |s|
  s.name             = 'dartitect_privacy'
  s.version          = '1.0.0-rc.10'
  s.summary          = 'Explicit iOS tracking authorization for Dartitect.'
  s.description      = 'Reads and explicitly requests ATT without automatic prompts.'
  s.homepage         = 'https://github.com/ftr-tuta/dartitect'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'ftr' => 'ftr@tuta.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'
  s.frameworks = 'AppTrackingTransparency'
end
