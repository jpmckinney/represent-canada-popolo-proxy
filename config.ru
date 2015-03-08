# coding: utf-8
require 'rubygems'
require 'bundler/setup'

require 'json'

require 'faraday'
require 'sinatra'

BASE_URL = 'http://scrapers-ruby.herokuapp.com/'

CONTACT_DETAIL_NOTE_MAP = {
  'Arrondissement' => 'constituency',
  'Hôtel de ville' => 'legislature',
}

CONTACT_DETAIL_TYPE_MAP = {
    'address' => 'postal',
    'cell' => 'alt',
    'fax' => 'fax',
    'voice' => 'tel',
}

get '/*' do
  organization_id = params[:splat][0]

  party_names = {}
  response = Faraday.get("#{BASE_URL}organizations?in_network_of=#{organization_id}")
  return response.status if response.status != 200
  JSON.load(response.body).each do |organization|
    if organization['classification'] == 'political party'
      party_names[organization['_id']] = organization['name']
    end
  end

  party_memberships = {}
  response = Faraday.get("#{BASE_URL}memberships?in_network_of=#{organization_id}")
  return response.status if response.status != 200
  JSON.load(response.body).each do |membership|
    if party_names.keys.include?(membership['organization_id'])
      party_memberships[membership['person_id']] = membership['organization_id']
    end
  end

  people = {}
  response = Faraday.get("#{BASE_URL}people?member_of=#{organization_id}")
  return response.status if response.status != 200
  JSON.load(response.body).each do |person|
    people[person['_id']] = person
  end

  posts = {}
  response = Faraday.get("#{BASE_URL}posts?organization_id=#{organization_id}")
  return response.status if response.status != 200
  JSON.load(response.body).each do |post|
    posts[post['_id']] = post
  end

  source_url = "#{BASE_URL}memberships?organization_id=#{organization_id}"
  response = Faraday.get(source_url)
  return response.status if response.status != 200

  data = []

  JSON.load(response.body).each do |membership|
    person_id = membership['person_id']
    person = people.fetch(person_id)
    post = posts.fetch(membership['post_id'])

    party_id = party_memberships[person_id]
    party_name = if party_id
      party_names.fetch(party_id)
    else
      nil
    end

    gender = case person['gender']
    when 'female'
      'F'
    when 'male'
      'M'
    else
      nil
    end

    offices_by_note = {}
    person['contact_details'].each do |contact_detail|
      if contact_detail['type'] != 'email' && contact_detail['note']
        note = contact_detail['note']
        offices_by_note[note] ||= {}
        offices_by_note[note]['type'] = CONTACT_DETAIL_NOTE_MAP.fetch(note)
        offices_by_note[note][CONTACT_DETAIL_TYPE_MAP.fetch(contact_detail['type'])] = contact_detail['value']
      end
    end

    record = {
      name: person['name'],
      district_name: post['area']['name'],
      elected_office: membership['role'],
      source_url: source_url,
      first_name: person['given_name'],
      last_name: person['family_name'],
      party_name: party_name,
      email: person['email'],
      # url
      # photo_url
      # personal_url
      # district_id
      gender: gender,
      offices: offices_by_note.values,
      # boundary_url
    }

    if person['honorific_prefix']
      record[:extra] = {
        honorific_prefix: person['honorific_prefix'],
      }
    end

    data << record
  end

  content_type 'application/json'
  JSON.dump(data)
end

run Sinatra::Application
