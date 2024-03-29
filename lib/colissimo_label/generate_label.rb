# frozen_string_literal: true

require 'http'

class ColissimoLabel::GenerateLabel
  class ServiceUnavailable < StandardError; end

  def initialize(filename, destination_country, shipping_fees, sender_data, addressee_data, options = {})
    @filename            = filename
    @destination_country = destination_country
    @shipping_fees       = shipping_fees

    @sender_data    = sender_data
    @addressee_data = addressee_data

    @pickup_id           = options.fetch(:pickup_id, nil)
    @pickup_type         = options.fetch(:pickup_type, nil)
    @total_weight        = options.fetch(:total_weight, nil)
    @product_code        = options.fetch(:product_code, nil)
    @with_signature      = options.fetch(:with_signature, false)
    @insurance_value     = options.fetch(:insurance_value, nil)
    @label_output_format = options.fetch(:label_output_format, 'PDF_10x15_300dpi')
    @label_path          = options.fetch(:label_path, nil)

    @customs_data         = options.fetch(:customs_data, nil)
    @customs_total_weight = options.fetch(:customs_total_weight, nil)
    @customs_category     = options.fetch(:customs_category, 3)
    @customs_tva_number   = options.fetch(:customs_tva_number, nil)
    @eori_number          = options.fetch(:eori_number, nil)
    @customs_path         = options.fetch(:customs_path, nil)
    @customs_filename     = options.fetch(:customs_filename, 'customs')

    @order_id         = options.fetch(:order_id, nil)
    @sender_data      = sender_data
    @sender_ref_id    = options.fetch(:sender_ref_id, nil)
    @addressee_data   = addressee_data
    @addressee_ref_id = options.fetch(:addressee_ref_id, nil)

    @errors = []
  end

  def perform
    response       = perform_request
    status         = response.code
    parts          = response.to_a.last.force_encoding('BINARY').split('Content-ID: ')
    label_filename = @filename + '.' + file_format
    label_path     = nil
    customs_path   = nil

    if ColissimoLabel.s3_bucket
      label_path    = ColissimoLabel.s3_path.chomp('/') + '/' + (@label_path.present? ? @label_path + '/' : '')
      colissimo_pdf = ColissimoLabel.s3_bucket.object(label_path + label_filename)
      colissimo_pdf.put(acl: 'public-read', body: parts[2])
    else
      label_path = ColissimoLabel.colissimo_local_path.chomp('/') + '/' + (@label_path.present? ? @label_path + '/' : '')
      FileUtils.mkdir_p(label_path) unless File.directory?(label_path)
      File.open(label_path + label_filename, 'wb') do |file|
        file.write(parts[2])
      end
    end

    if require_customs?
      customs_filename = @filename + '-' + @customs_filename + '.pdf'

      if ColissimoLabel.s3_bucket
        customs_path = ColissimoLabel.s3_path.chomp('/') + '/' + (@customs_path.present? ? @customs_path + '/' : '')
        customs_pdf  = ColissimoLabel.s3_bucket.object(customs_path + customs_filename)
        customs_pdf.put(acl: 'public-read', body: parts[3])
      else
        customs_path = ColissimoLabel.colissimo_local_path.chomp('/') + '/' + (@customs_path.present? ? @customs_path + '/' : '')
        FileUtils.mkdir_p(customs_path) unless File.directory?(customs_path)
        File.open(customs_path + customs_filename, 'wb') do |file|
          file.write(parts[3])
        end
      end
    end

    if status == 400 || status == 500
      error_message = response.body.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').scan(/"messageContent":"(.*?)"/).last&.first
      raise ServiceUnavailable, error_message
    elsif status == 503
      raise ServiceUnavailable, { message: 'Colissimo: Service Unavailable', code: 503 }.to_json
    else
      if (response_message = response.body.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').scan(/"parcelNumber":"(.*?)",/).last)
        parcel_number = response_message.first

        if ColissimoLabel.s3_bucket
          return parcel_number
        else
          return [parcel_number, label_path, customs_path]
        end
      else
        error_message = response.body.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').scan(/"messageContent":"(.*?)"/).last&.first
        raise ServiceUnavailable, error_message
      end
    end
  end

  def payload
    build_colissimo_payload
  end

  private

  def perform_request(delivery_date = Date.today)
    HTTP.post(service_url, json: build_colissimo_payload(delivery_date))
  end

  def build_colissimo_payload(delivery_date = Date.today)
    {
      "contractNumber": ColissimoLabel.contract_number,
      "password":       ColissimoLabel.contract_password,
      "outputFormat":   {
        "x":                  '0',
        "y":                  '0',
        "outputPrintingType": @label_output_format
      },
      "letter":         {
                          "service":   {
                            "commercialName":   @sender_data[:company_name],
                            "productCode":      @product_code.presence || product_code,
                            "depositDate":      delivery_date.strftime('%F'),
                            "totalAmount":      (@shipping_fees * 100).to_i,
                            "returnTypeChoice": '2', # Retour à la maison en prioritaire
                            "orderNumber": @order_id
                          },
                          "parcel":    {
                                         "weight":           @weight,
                                         "pickupLocationId": @pickup_id,
                                         "insuranceValue":   @insurance_value
                                       }.compact,
                          "sender":    {
                                         "senderParcelRef": @sender_ref_id,
                                         "address":         format_sender
                                       }.compact,
                          "addressee": {
                                         "addresseeParcelRef": @addressee_ref_id,
                                         "address":            format_addressee
                                       }.compact
                        }.merge(customs_declaration)
    }.merge(customs_fields).compact
  end

  # Services =>
  # generateLabel : Génère  une  expédition : annonce informatique du colis + documents associés (étiquette et déclarations douanières)
  # checkGenerateLabel : Permet de tester les requêtes web service
  # getProductInter : Utile uniquement dans  le  cas  de  certaines  destinations internationales
  # getListMailBoxPickingDates : Fonctionne  avec le  produit Retour Colissimo France (numéro de colis généré via WS ou toute autre solution avec annonce)
  # planPickup : Fonctionne avec le produit Retour Colissimo France (n° colis généré via WS ou toute autre solution avec annonce)
  def service_url(service = 'generateLabel')
    "https://ws.colissimo.fr/sls-ws/SlsServiceWSRest/2.0/#{service}"
  end

  def file_format
    case @label_output_format
    when 'PDF_A4_300dpi', 'PDF_10x15_300dpi'
      'pdf'
    when 'ZPL_10x15_300dpi', 'ZPL_10x15_203dpi'
      'zpl'
    when 'DPL_10x15_300dpi', 'DPL_10x15_203dpi'
      'dpl'
    else
      'pdf'
    end
  end

  def format_sender
    {
      "companyName": @sender_data[:company_name],
      "lastName":    @sender_data[:last_name],
      "firstName":   @sender_data[:first_name],
      "line0":       @sender_data[:apartment],
      "line1":       @sender_data[:address_bis],
      "line2":       @sender_data[:address],
      "city":        @sender_data[:city],
      "zipCode":     @sender_data[:postcode],
      "countryCode": @sender_data[:country_code],
      "phoneNumber": @sender_data[:phone].presence || @sender_data[:mobile]
    }.compact.transform_values(&:strip)
  end

  def format_addressee
    {
      "companyName": @addressee_data[:company_name], # Raison sociale
      "lastName": @addressee_data[:last_name], # Nom
      "firstName": @addressee_data[:first_name], # Prénom
      "line0": @addressee_data[:apartment], # Etage, couloir, escalier, appartement
      "line1": @addressee_data[:address_bis], # Entrée, bâtiment, immeuble, résidence
      "line2": @addressee_data[:address], # Numéro et libellé de voie
      "line3": @addressee_data[:address_ter], # Lieu-dit ou autre mention
      "countryCode": @addressee_data[:country_code], # Code ISO du pays
      "city": @addressee_data[:city], # Ville
      "zipCode": @addressee_data[:postcode], # Code postal
      "phoneNumber": @addressee_data[:phone].presence || @addressee_data[:mobile], # Numéro de téléphone
      "mobileNumber": @addressee_data[:mobile], # Numéro de portable, obligatoire si pickup
      "doorCode1": @addressee_data[:door_code_1], # Code porte 1
      "doorCode2": @addressee_data[:door_code_2], # Code porte 2
      "email": @addressee_data[:email], # Adresse courriel
      "intercom": @addressee_data[:intercom] # Interphone
    }.compact.transform_values(&:strip)
  end

  # weight: Colissimo weigh themselves all packages (so not relevant here)
  def format_weight
    if require_customs?
      @customs_total_weight
    else
      @total_weight.presence || '0.1'
    end
  end

  # Déclaration douanière de type CN23
  def customs_declaration
    if require_customs?
      {
        "customsDeclarations":
          {
            "includeCustomsDeclarations": 1, # Inclure déclaration
            "importersReference": @customs_tva_number, # Numéro TVA pour la douane, si besoin
            "contents": {
              "article":  @customs_data.map { |product_customs|
                {
                  "description":   product_customs[:description],
                  "quantity":      product_customs[:quantity]&.to_i,
                  "weight":        product_customs[:weight]&.to_f.round(2),
                  "value":         product_customs[:item_price]&.to_f.round(2),
                  "originCountry": product_customs[:country_code],
                  "currency":      product_customs[:currency_code],
                  "hsCode":        product_customs[:customs_code].presence
                }.compact
              },
              "category": {
                # Nature de l'envoi
                # 1 => Cadeau
                # 2 => Echantillon commercial
                # 3 => Envoi commercial
                # 4 => Document
                # 5 => Autre
                # 6 => Retour de marchandise
                "value": @customs_category
              }
            }
          }.compact
      }
    else
      {}
    end
  end

  def customs_fields
    if require_customs? && @eori_number.present?
      {
        "fields": {
          "customField": [
                           {
                             "key":   'EORI',
                             "value": @eori_number
                           }
                         ]
        }
      }
    else
      {}
    end
  end

  def require_customs?
    @customs_data.present? || %w[CH NO US GB].include?(@destination_country)
  end

  # Certains pays, comme l'Allemagne, requiert une signature pour la livraison
  # DOM : Colissimo France et International sans signature
  # DOS : Colissimo France et International avec signature
  # Pays avec Point Relais : https://www.colissimo.entreprise.laposte.fr/fr/offre-europe
  # BPR : Colissimo - Point Retrait – en Bureau de Poste
  # A2P : Colissimo - Point Retrait – en relais Pickup ou en consigne Pickup Station
  def product_code
    if %w[DE IT ES GB LU NL DK AT SE].include?(@destination_country)
      'DOS'
    elsif !@pickup_id.nil? && %w[FR].include?(@destination_country)
      @pickup_type || 'BPR'
    elsif @with_signature
      'DOS'
    else
      'DOM'
    end
  end

end
