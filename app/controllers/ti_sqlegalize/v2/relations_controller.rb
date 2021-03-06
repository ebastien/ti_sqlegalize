# encoding: utf-8
module TiSqlegalize
module V2

  class RelationsController < TiSqlegalize::ApplicationController

    include TiSqlegalize::V2::Concerns::DomainRepresentable

    ensure_signed_in

    before_action do
      permitted = params.permit(:id, :query_id, :domain_id, :schema_id)
      @relation_id = permitted[:id]
      @query_id = permitted[:query_id]
      @domain_id = permitted[:domain_id]
      @schema_id = permitted[:schema_id]
    end

    def show_by_query
      raise InvalidParams unless @query_id

      query = Query.find @query_id

      if query
        if query.status == :finished
          render_api json: query_to_jsonapi(query), status: 200
        else
          render_conflict
        end
      else
        render_not_found
      end
    end

    def index_by_domain
      raise InvalidParams unless @domain_id

      domain = begin
        Domain.find @domain_id
      rescue Domain::UnknownDomain
        nil
      end

      if domain
        render_api json: domain_relations_to_jsonapi(domain), status: 200
      else
        render_not_found
      end      
    end

    def index_by_schema
      raise InvalidParams unless @schema_id

      schema = begin
        Schema.find @schema_id
      rescue Schema::UnknownSchema
        nil
      end

      if schema && current_user.can_read_schema?(schema)
        render_api json: schema_tables_to_jsonapi(schema), status: 200
      else
        render_not_found
      end
    end

    def show
      raise InvalidParams unless @relation_id

      table = Table.find @relation_id

      if table && current_user.can_read_schema?(table.schema)
        render_api json: table_to_jsonapi(table), status: 200
      else
        render_not_found
      end
    end

  private

    def query_to_jsonapi(query)
      heading = query.schema.map do |column|
        [ "heading_#{column.name}", {
          links: {
            related: v2_query_result_heading_url(query.id, column.name)
          },
          data: {
            type: 'domain',
            id: column.domain.id
          }
        }]
      end

      included = query.schema.map { |c| c.domain.id }.uniq.map do |id|
        domain = Domain.find(id)
        domain_to_jsonapi(domain, relationships: false)[:data]
      end

      {
        data: {
          type: 'relation',
          id: query.id,
          attributes: {
            sql: query.statement,
            heading: query.schema.map { |column| column.name }
          },
          relationships: {
            body: {
              links: {
                related: v2_query_result_body_url(query.id)
              }
            }
          }.merge(Hash[heading]),
          links: {
            :self => v2_query_result_url(query.id)
          }
        },
        included: included
      }
    end

    def table_to_jsonapi(table)
      heading = table.columns.map do |c|
        [ "heading_#{c.name}", {
          links: {
            related: v2_relation_heading_url(table.id, c.id)
          },
          data: {
            type: 'domain',
            id: c.domain.id
          }
        }]
      end

      included = table.columns.map { |c| c.domain.id }.uniq.map do |id|
        domain = Domain.find(id)
        domain_to_jsonapi(domain, relationships: false)[:data]
      end

      {
        data: {
          type: 'relation',
          id: table.id,
          attributes: {
            name: table.name,
            heading: table.columns.map { |c| c.name }
          },
          relationships: {
            body: {
              links: {
                related: v2_relation_body_url(table.id)
              }
            }
          }.merge(Hash[heading]),
          links: {
            :self => v2_relation_url(table.id)
          }
        },
        included: included
      }
    end

    def domain_relations_to_jsonapi(domain)
      {
        links: {
          :self => v2_domain_relations_url(domain.id)
        },
        # Not implemented
        data: [].map { |t| table_to_jsonapi(t)[:data] }
      }
    end

    def schema_tables_to_jsonapi(schema)
      {
        links: {
          :self => v2_schema_relations_url(schema.id)
        },
        data: schema.tables.map { |t| table_to_jsonapi(t)[:data] }
      }
    end
  end
end
end
