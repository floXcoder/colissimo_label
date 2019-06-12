# frozen_string_literal: true

require 'http'

class ColissimoLabel::GenerateLabel

  def initialize(filename, destination_country, shipping_fees, sender_data, addressee_data, customs_total_weight = nil, customs_data = nil)
    @filename             = filename
    @destination_country  = destination_country
    @shipping_fees        = shipping_fees
    @sender_data          = sender_data
    @addressee_data       = addressee_data
    @customs_total_weight = customs_total_weight
    @customs_data         = customs_data
    @errors               = []
  end

  def perform
    response       = perform_request
    status         = response.code
    parts          = response.to_a.last.force_encoding('BINARY').split('Content-ID: ')
    label_filename = @filename + '.pdf'

    if ColissimoLabel.s3_bucket
      colissimo_pdf = ColissimoLabel.s3_bucket.object(ColissimoLabel.s3_path.chomp('/') + '/' + label_filename)
      colissimo_pdf.put(acl: 'public-read', body: parts[2])
    else
      File.open(ColissimoLabel.colissimo_local_path.chomp('/') + '/' + label_filename, 'wb') do |file|
        file.write(parts[2])
      end
    end

    if require_customs?
      customs_filename = @filename + '-customs.pdf'

      if ColissimoLabel.s3_bucket
        customs_pdf = ColissimoLabel.s3_bucket.object(ColissimoLabel.s3_path.chomp('/') + '/' + customs_filename)
        customs_pdf.put(acl: 'public-read', body: parts[3])
      else
        File.open(ColissimoLabel.colissimo_local_path.chomp('/') + '/' + customs_filename, 'wb') do |file|
          file.write(parts[3])
        end
      end
    end

    if status == 400
      error_message = response.body.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').scan(/"messageContent":"(.*?)"/).last.first
      raise StandardError, error_message
    else
      parcel_number = response.body.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').scan(/"parcelNumber":"(.*?)",/).last.first

      return parcel_number
    end
  end

  private

  def perform_request(delivery_date = Date.today)
    HTTP.post(service_url,
              json: {
                      "contractNumber": ColissimoLabel.contract_number,
                      "password":       ColissimoLabel.contract_password,
                      "outputFormat":   {
                        "x":                  '0',
                        "y":                  '0',
                        "outputPrintingType": 'PDF_10x15_300dpi'
                      },
                      "letter":         {
                                          "service":   {
                                            "productCode": product_code,
                                            "depositDate": delivery_date.strftime('%F'),
                                            "totalAmount": (@shipping_fees * 100).to_i,
                                            # "returnTypeChoice": '2' # Retour à la maison en prioritaire
                                          },
                                          "parcel":    {
                                            "weight": format_weight
                                          },
                                          "sender":    {
                                            "address": format_sender
                                          },
                                          "addressee": {
                                            "address": format_addressee
                                          }
                                        }.merge(customs)
                    }.compact)
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

  def format_sender
    {
      "companyName": @sender_data[:company_name],
      "line2":       @sender_data[:address],
      "city":        @sender_data[:city],
      "zipCode":     @sender_data[:postcode],
      "countryCode": @sender_data[:country_code]
    }
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
      "phoneNumber": @addressee_data[:phone], # Numéro de téléphone
      "mobileNumber": @addressee_data[:mobile], # Numéro de portable
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
      '0.1'
    end
  end

  # Déclaration douanière de type CN23
  def customs
    if require_customs?
      {
        "customsDeclarations": {
          "includeCustomsDeclarations": 1, # Inclure déclaration
          "contents": {
            "article":  @customs_data.map { |customs|
              {
                "description":   customs[:description],
                "quantity":      customs[:quantity],
                "weight":        customs[:weight],
                "value":         customs[:item_price],
                "originCountry": customs[:country_code],
                "currency":      customs[:currency_code],
                "hsCode":        customs[:customs_code] # Objets d'art, de collection ou d'antiquité (https://pro.douane.gouv.fr/prodouane.asp)
              }
            },
            "category": {
              # Nature de l'envoi
              # 1 => Cadeau
              # 2 => Echantillon commercial
              # 3 => Envoi commercial
              # 4 => Document
              # 5 => Autre
              # 6 => Retour de marchandise
              "value": 3
            }
          }
        }
      }
    else
      {}
    end
  end

  def require_customs?
    %w[CH].include?(@destination_country)
  end

  # DOM : Colissimo France et International sans signature / DOS : Colissimo France et International avec signature
  # Certains pays, comme l'Allemagne, requiert une signature pour la livraison
  def product_code
    if %w[DE IT GB LU].include?(@destination_country)
      'DOS'
    else
      'DOM'
    end
  end

end
