# frozen_string_literal: true

require 'http'

class ColissimoLabel::FindRelayPoint

  def initialize(addressee_data, estimated_delivery_date, weight_package)
    @addressee_data          = addressee_data
    @estimated_delivery_date = estimated_delivery_date
    @weight_package          = weight_package
    @errors                  = []
  end

  def perform
    response      = perform_request
    status        = response.code
    soap_response = response.to_param

    raise StandardError, soap_response if status != 200

    parse         = Nokogiri::XML(soap_response)
    root          = parse.root
    error_code    = root.xpath('//errorCode').text
    error_message = root.xpath('//errorMessage').text

    raise StandardError, error_message if error_code != '0'

    root.xpath('//listePointRetraitAcheminement').map do |point|
      {
        pickup_id:      point.at_xpath('identifiant').text,
        name:           point.at_xpath('nom').text,
        address:        [point.at_xpath('adresse1'), point.at_xpath('adresse2'), point.at_xpath('adresse3')].map(&:text).select(&:present?).join(' '),
        postcode:       point.at_xpath('codePostal').text,
        city:           point.at_xpath('localite').text,
        country:        point.at_xpath('libellePays').text,
        country_code:   point.at_xpath('codePays').text,
        latitude:       point.at_xpath('coordGeolocalisationLatitude').text.to_f,
        longitude:      point.at_xpath('coordGeolocalisationLongitude').text.to_f,
        distance:       point.at_xpath('distanceEnMetre').text.to_i,
        max_weight:     point.at_xpath('poidsMaxi').text.to_i,
        parking:        point.at_xpath('parking').text.to_b,
        business_hours: {
          monday:    point.at_xpath('horairesOuvertureLundi').text,
          tuesday:   point.at_xpath('horairesOuvertureMardi').text,
          wednesday: point.at_xpath('horairesOuvertureMercredi').text,
          thursday:  point.at_xpath('horairesOuvertureJeudi').text,
          friday:    point.at_xpath('horairesOuvertureVendredi').text,
          saturday:  point.at_xpath('horairesOuvertureSamedi').text,
          sunday:    point.at_xpath('horairesOuvertureDimanche').text
        }
      }
    end
  end

  private

  def perform_request
    HTTP.get(service_url,
             params: {
                       accountNumber: ColissimoLabel.contract_number,
                       password:      ColissimoLabel.contract_password,
                       address:       @addressee_data[:address],
                       zipCode:       @addressee_data[:postcode],
                       city:          @addressee_data[:city],
                       countryCode:   @addressee_data[:country_code],
                       shippingDate:  @estimated_delivery_date,
                       weight:        @weight_package
                     }.compact)
  end

  # Services =>
  # findRDVPointRetraitAcheminement : à partir d’une adresse postale fournie en entrée, restitue les points de retrait les plus proches de cette adresse
  # findPointRetraitAcheminementByID : à partir d’un Identifiant de Point Retrait (identifiant Point Retrait), restitue le détail des informations associé au Point Retrait transmis
  def service_url(service = 'findRDVPointRetraitAcheminement')
    "https://ws.colissimo.fr/pointretrait-ws-cxf/PointRetraitServiceWS/2.0/#{service}"
  end

end
