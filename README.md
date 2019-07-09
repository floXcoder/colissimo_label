# ColissimoLabel

Generate Colissimo label for all countries with customs declaration :fire:

To use this gem, you need to have an WebService account in Colissimo. Ask for it when you set up a new contract with Colissimo. 

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'colissimo_label'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install colissimo_label

```ruby
require 'colissimo_label'
```

## Options

Colissimo contract number (dedicated for webservices) (**required**):

```ruby
ColissimoLabel.contract_number = ENV['COLISSIMO_CONTRACT_NUMBER']
```

Colissimo password (dedicated for webservices) (**required**):

```ruby
ColissimoLabel.contract_password = ENV['COLISSIMO_PASSWORD']
```

I you want to save generated files on AWS S3, initialize the bucket:
    
```ruby
ColissimoLabel.s3_bucket = Aws::S3::Resource.new.bucket('my_bucket_name')
```

Define the directory to save files (**required** if s3_bucket used):

```ruby
ColissimoLabel.s3_path = 'path/to/colissimo'
```

Declare local path to save generated files (**required** if no use of S3):

```ruby
ColissimoLabel.colissimo_local_path = Rails.root.join('public', 'colissimo')
```

## Usage

To generate a new Colissimo label, use the following methods.

For a national address:

```ruby
parcel_number = ColissimoLabel::GenerateLabel.new(
        'label_filename', # Name of the file generated
        'FR', # Normalized country code of the destination
        9.99, # Amount of the shipping fees (paid by the customer)
        {
          company_name: 'Sender company name',
          address:      'Address',
          city:         'City',
          postcode:     'Postcode',
          country_code: 'Normalized country code'
        },
        {
          last_name:    'Last name of the addressee',
          first_name:   'First name of the addressee',
          address_bis:  'Address bis of the addressee',
          address:      'Address of the addressee',
          city:         'City of the addressee',
          postcode:     'Postcode of the addressee',
          country_code: 'Normalized country code of the addressee',
          phone:        'Phone number of the addressee',
          mobile:       'Mobile number of the addressee',
          email:        'Email of the addressee'
        }
      ).perform
```

For a foreign address (which required customs declaration):

```ruby
parcel_number = ColissimoLabel::GenerateLabel.new(
        'label_filename', # Name of the file generated
        'CH', # Normalized country code of the destination
        9.99, # Amount of the shipping fees (paid by the customer)
        {
          company_name: 'Sender company name',
          address:      'Address',
          city:         'City',
          postcode:     'Postcode',
          country_code: 'Normalized country code'
        },
        {
          last_name:    'Last name of the addressee',
          first_name:   'First name of the addressee',
          address_bis:  'Address bis of the addressee',
          address:      'Address of the addressee',
          city:         'City of the addressee',
          postcode:     'Postcode of the addressee',
          country_code: 'Normalized country code of the addressee',
          phone:        'Phone number of the addressee',
          mobile:       'Mobile number of the addressee',
          email:        'Email of the addressee'
        },
        2, # Total weight of the package
        [ # Details content of your package
          {
            description:   'Product description',
            quantity:      1,
            weight:        2,
            item_price:    100,
            country_code:  'FR',
            currency_code: 'EUR',
            customs_code:  'hsCode' # Harmonized system code of your product
          }
        ]
      ).perform
```

In both cases, if the label cannot be generated it raises a StandardError with the reason. Otherwise, the parcel number is returned and files saved in the specified folders.

## Documentation

Colissimo documentation can be found here:

https://www.colissimo.entreprise.laposte.fr/system/files/imagescontent/docs/spec_ws_affranchissement.pdf

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/floXcoder/colissimo_label. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the ColissimoLabel project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/colissimo_label/blob/master/CODE_OF_CONDUCT.md).
