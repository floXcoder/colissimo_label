# frozen_string_literal: true

require 'active_support'

require 'colissimo_label/version'
require 'colissimo_label/find_relay_point'
require 'colissimo_label/generate_label'

module ColissimoLabel

  mattr_accessor :contract_number
  self.contract_number = nil
  mattr_accessor :contract_password
  self.contract_password = nil

  mattr_accessor :s3_bucket
  self.s3_bucket = nil
  mattr_accessor :s3_path
  self.s3_path = nil

  mattr_accessor :colissimo_local_path
  self.colissimo_local_path = nil

end
