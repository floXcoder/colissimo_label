# frozen_string_literal: true

require 'http'

class ColissimoLabel::GenerateLabel
  require 'pathname'

  def initialize(filename, destination_country, shipping_fees, sender_data, addressee_data, options = {})
    @filename             = filename
    @destination_country  = destination_country
    @shipping_fees        = shipping_fees
    @outputPrintingType   = options.fetch(:label_type, nil)
    @product_code         = options.fetch(:product_code, nil)
    @weight               = options.fetch(:weight, nil)
    @insurance_value      = options.fetch(:insurance_value, nil) || "0"
    @order_id             = options.fetch(:order_id, nil)
    @sender_data          = sender_data
    @addressee_data       = addressee_data
    @pickup_id            = options.fetch(:pickup_id, nil)
    @pickup_type          = options.fetch(:pickup_type, nil)
    @customs_total_weight = options.fetch(:customs_total_weight, nil)
    @cn23_data            = options.fetch(:cn23_data, nil)
    @errors               = []
  end

  def perform
    byebug
    response       = perform_request
    status         = response.code
    parts          = response.to_a.last.force_encoding('BINARY').split('Content-ID: ')
    label_filename = @filename + '.' + file_format
    local_path = ColissimoLabel.colissimo_local_path.chomp('/') + '/'
    label_path = local_path + 'labels/' + label_filename
    cn23_path = nil

    if ColissimoLabel.s3_bucket
      colissimo_pdf = ColissimoLabel.s3_bucket.object(ColissimoLabel.s3_path.chomp('/') + '/' + label_filename)
      colissimo_pdf.put(acl: 'public-read', body: parts[2])
    else
      some_path = Pathname(label_path)
      some_path.dirname.mkpath
      File.open(label_path, 'wb') do |file|
        file.write(parts[2])
      end
    end

    if require_customs?
      cn23_filename = @filename + '_cn23.pdf'
      cn23_path = local_path + 'cn23/' + cn23_filename

      if ColissimoLabel.s3_bucket
        customs_pdf = ColissimoLabel.s3_bucket.object(ColissimoLabel.s3_path.chomp('/') + '/' + customs_filename)
        customs_pdf.put(acl: 'public-read', body: parts[3])
      else
        some_path = Pathname(cn23_path)
        some_path.dirname.mkpath
        File.open(cn23_path, 'wb') do |file|
          file.write(parts[3])
        end
      end
    end

    if status == 400
      error_message = response.body.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').scan(/"messageContent":"(.*?)"/).last.first
      raise StandardError, error_message
    else
      parcel_number = response.body.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').scan(/"parcelNumber":"(.*?)",/).last.first

      return [parcel_number, label_path, cn23_path]
    end
  end

  private

  def file_format
    return 'pdf' if @outputPrintingType == 'PDF_A4_300dpi' || @outputPrintingType == 'PDF_10x15_300dpi'
    return 'zpl' if @outputPrintingType == 'ZPL_10x15_300dpi' || @outputPrintingType == 'ZPL_10x15_203dpi'
    return 'dpl' if @outputPrintingType == 'DPL_10x15_300dpi' || @outputPrintingType == 'DPL_10x15_203dpi'
  end

  def perform_request(delivery_date = Date.today)
    HTTP.post(service_url,
              json: {
                      "contractNumber": ColissimoLabel.contract_number,
                      "password":       ColissimoLabel.contract_password,
                      "outputFormat":   {
                        "x":                  '0',
                        "y":                  '0',
                        "outputPrintingType": @outputPrintingType
                      },
                      "letter":         {
                                          "service":   {
                                            "commercialName": @sender_data[:company_name],
                                            "productCode":    @product_code,
                                            "depositDate":    delivery_date.strftime('%F'),
                                            "totalAmount":    (@shipping_fees * 100).to_i,
                                            # "returnTypeChoice": '2' # Retour à la maison en prioritaire
                                          },
                                          "parcel":    {
                                                         "weight":           @weight,
                                                         "pickupLocationId": @pickup_id,
                                                         "insuranceValue":   @insurance_value
                                                       }.compact,
                                          "sender":    {
                                            "address": format_sender
                                          },
                                          "addressee": {
                                            "address": format_addressee
                                          }
                                        }.merge(cn23_declaration)
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
      "mobileNumber": @addressee_data[:mobile], # Numéro de portable, obligatoire si pickup
      "doorCode1": @addressee_data[:door_code_1], # Code porte 1
      "doorCode2": @addressee_data[:door_code_2], # Code porte 2
      "email": @addressee_data[:email], # Adresse courriel
      "intercom": @addressee_data[:intercom] # Interphone
    }.compact.transform_values(&:strip)
  end

  # weight: Colissimo weigh themselves all packages (so not relevant here)
  def format_weight

    # if require_customs?
    #   @customs_total_weight
    # else
    #   '0.1'
    # end
  end

  # Déclaration douanière de type CN23
  def cn23_declaration
    if require_customs?
      {
        "customsDeclarations": {
          "includeCustomsDeclarations": 1, # Inclure déclaration
          "contents": {
            "article":  @cn23_data["products"].map { |product|
              {
                "description":   product[:description],
                "quantity":      product[:quantity].to_i,
                "weight":        product[:weight].to_i,
                "value":         product[:unit_price].to_f.round(2),
                "originCountry": product[:country_code],
                "currency":      product[:currency_code],
                "hsCode":        product[:hs_code] ? product[:hs_code].to_i : "" # Objets d'art, de collection ou d'antiquité (https://pro.douane.gouv.fr/prodouane.asp)
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
              "value": @cn23_data[:category].to_i
            }
          }
        }
      }
    else
      {}
    end
  end

  def require_customs?
    @cn23_data && @cn23_data["products"] && @cn23_data["products"].length > 0
  end

  # Certains pays, comme l'Allemagne, requiert une signature pour la livraison
  # DOM : Colissimo France et International sans signature
  # DOS : Colissimo France et International avec signature
  # Pays avec Point Relais : https://www.colissimo.entreprise.laposte.fr/fr/offre-europe
  # BPR : Colissimo - Point Retrait – en Bureau de Poste
  # A2P : Colissimo - Point Retrait – en relais Pickup ou en consigne Pickup Station
  # def product_code
  #   if %w[DE IT GB LU].include?(@destination_country)
  #     'DOS'
  #   elsif !@pickup_id.nil? && %w[FR].include?(@destination_country)
  #     @pickup_type || 'BPR'
  #   else
  #     'DOM'
  #   end
  # end

end
