# frozen_string_literal: true

require 'spec_helper'

require 'colissimo_label/generate_label'

describe ColissimoLabel::GenerateLabel do
  let(:generate_label) { described_class }

  before(:all) do
    ColissimoLabel.contract_number   = 'Contract_number'
    ColissimoLabel.contract_password = 'Password'

    ColissimoLabel.colissimo_local_path = './spec/data/generated/'
  end

  context 'Colissimo national label' do
    let(:national_path) { './spec/data/national/' }

    before do
      stub_request(:post, "https://ws.colissimo.fr/sls-ws/SlsServiceWSRest/2.0/generateLabel").
        to_return(status: 200, body: File.read(national_path + 'generated_label'), headers: {})
    end

    it 'generates Colissimo label' do
      generate_label.new(
        'national_label',
        'FR',
        10,
        {
          company_name: 'MyCompany',
          address:      'Rue de Rivoli',
          city:         'Paris',
          postcode:     '75001',
          country_code: 'FR'
        },
        {
          last_name:    'addressee last name',
          first_name:   'addressee first name',
          address:      'Rue de la paix',
          city:         'Paris',
          postcode:     '75001',
          country_code: 'FR',
          phone:        '0100000000',
          mobile:       '0600000000',
          email:        'addressee@email.com'
        }
      ).perform

      expect(File.exist?(ColissimoLabel.colissimo_local_path + 'national_label.pdf')).to be true
    end
  end

  context 'Colissimo foreign label' do
    let(:foreign_path) { './spec/data/foreign/' }

    before do
      stub_request(:post, "https://ws.colissimo.fr/sls-ws/SlsServiceWSRest/2.0/generateLabel").
        to_return(status: 200, body: File.read(foreign_path + 'generated_label'), headers: {})
    end

    it 'generates customs documents and Colissimo label' do
      generate_label.new(
        'foreign_label',
        'CH',
        10,
        {
          company_name: 'MyCompany',
          address:      'Rue de Rivoli',
          city:         'Paris',
          postcode:     '75001',
          country_code: 'FR'
        },
        {
          last_name:    'addressee last name',
          first_name:   'addressee first name',
          address:      'Pont du Mont-Blanc',
          city:         'Genève',
          postcode:     '1207',
          country_code: 'CH',
          phone:        '0100000000',
          mobile:       '0600000000',
          email:        'addressee@email.com'
        },
        2,
        [
          {
            description:   'Product description',
            quantity:      1,
            weight:        2,
            item_price:    100,
            country_code:  'FR',
            currency_code: 'EUR',
            customs_code:  '85250800'
          }
        ]
      ).perform

      expect(File.exist?(ColissimoLabel.colissimo_local_path + 'foreign_label.pdf')).to be true
      expect(File.exist?(ColissimoLabel.colissimo_local_path + 'foreign_label-customs.pdf')).to be true
    end
  end

end
