# encoding: utf-8
module TiSqlegalize
module V2

  class SchemasController < TiSqlegalize::ApplicationController
    ensure_signed_in

    def index
      render_not_found
    end

    def show
      render_not_found
    end
  end

end
end
