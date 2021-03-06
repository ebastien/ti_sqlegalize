# encoding: utf-8
require 'rails_helper'

describe TiSqlegalize::Schema do

  before(:each) do
    mock_domains
    mock_schemas
  end

  let!(:schema) { Fabricate(:schema) }

  it "complains on unknown schema" do
    expect do
      TiSqlegalize::Schema.find 'not_a_schema'
    end.to raise_error(TiSqlegalize::Schema::UnknownSchema)
  end

  it "fetches an existing schema" do
    expect(TiSqlegalize::Schema.find schema.id).to eq(schema)
  end

  it "fetches all schemas" do
    schemas = TiSqlegalize::Schema.all
    expect(schemas.size).to eq(2)
    expect(schemas.find { |s| s.id == schema.id }).to eq(schema)
  end

  it "contains tables" do
    tables = schema.tables
    expect(tables.size).to eq(1)
  end
end
