module Jekyll
  module LiquifyFilter
    def liquify(input)
      Liquid::Template.parse(input.to_s).render(@context)
    end
  end
end
Liquid::Template.register_filter(Jekyll::LiquifyFilter)
