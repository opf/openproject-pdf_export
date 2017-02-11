#-- copyright
# OpenProject PDF Export Plugin
#
# Copyright (C)2014 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License version 3.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.md for more details.
#++

module OpenProject::PdfExport::ExportCard
  class ColumnElement
    def initialize(pdf, property_name, config, orientation, work_package)
      @pdf = pdf
      @property_name = property_name
      @config = config
      @orientation = orientation
      @work_package = work_package
    end

    def draw
      # Get value from model
      if @work_package.respond_to?(@property_name)
        value = extract_property
      else
        value = extract_custom_field
      end

      draw_value(value)
    end

    private

    def extract_property
      value = @work_package.send(@property_name)

      case @property_name.to_s
      when 'children'
        return value.to_a
      end

      value
    end

    def extract_custom_field
      # Look in Custom Fields
      value = ""
      available_languages.each do |locale|
        I18n.with_locale(locale) do
          if (customs = @work_package.custom_field_values.select {|cf| cf.custom_field.name == @property_name} and customs.count > 0)
            value = customs.first.value
            @custom_field = customs.first.custom_field
          end
        end
        @localised_custom_field_name = @custom_field.name if !!@custom_field
      end

      value
    end

    def available_languages
      Setting.available_languages
    end

    def label_text(value)
      if @has_label
        custom_label = @config['custom_label']
        label_text = if custom_label
                  "#{custom_label}"
                else
                  localised_property_name
                end
        if @config['has_count'] && value.is_a?(Array)
          label_text = "#{label_text} (#{value.count})"
        end

        label_text += ": "
      else
        label_text = ""
      end
      label_text
    end

    def abbreviated_text(text, options)
      options = options.merge!({ document: @pdf })
      text_box = Prawn::Text::Box.new(text, options)
      left_over = text_box.render(:dry_run => true)

      # Be sure to do length arithmetics on chars, not bytes!
      left_over = left_over.mb_chars
      text      = text.to_s.mb_chars

      text = left_over.size > 0 ? text[0 ... -(left_over.size + 5)] + "[...]" : text
      text.to_s
    rescue Prawn::Errors::CannotFit
      ''
    end

    def abbreviated_formatted_text(texts, options)
      # Note: This is fragile as it assumes that texts consists of 2 parts, the label and the content
      options = options.merge!({ document: @pdf })
      text_box = Prawn::Text::Formatted::Box.new(texts, options)
      left_overs = text_box.render(:dry_run => true)
      text = texts[1][:text]
      if left_overs.count > 0
        if pos = text.index(left_overs.first[:text]) and !!pos && pos >= 5
          text.slice(0, pos - 5) + "[...]"
        else
          # Text box is too small to fit anything in - just return empty string.
          ""
        end
      else
        text
      end
    rescue Prawn::Errors::CannotFit
      ''
    end

    def localised_property_name
      @work_package.class.human_attribute_name(@localised_custom_field_name ||= @property_name)
    end

    def draw_value(value)
      # Font size
      if @config['font_size']
        # Specific size given
        overflow = :truncate
        font_size = Integer(@config['font_size'])

        if @config['min_font_size']
          # Range given
          overflow = :shrink_to_fit
          min_font_size = Integer(@config['min_font_size'])
        else
          min_font_size = font_size
        end
      else
        # Default
        font_size = 12
        overflow = :truncate
      end

      font_style = (@config['font_style'] or "normal").to_sym
      text_align = (@config['text_align'] or "left").to_sym

      # Label and text
      @has_label = @config['has_label']
      @default_label_font_size = 12
      indented = @config['indented']

      # Flatten value to a display string
      display_value = value
      display_value = display_value.map{|c| c.to_s }.join("\n") if display_value.is_a?(Array)
      display_value = display_value.to_s if !display_value.is_a?(String)

      if @has_label && indented
        width_ratio = 0.2 # Note: I don't think it's worth having this in the config

        # Label Textbox
        offset = [@orientation[:x_offset], @orientation[:height] - (@orientation[:text_padding] / 2)]
        box = @pdf.text_box(label_text(value),
          {:height => @orientation[:height],
           :width => @orientation[:width] * width_ratio,
           :at => offset,
           :style => :bold,
           :overflow => overflow,
           :size => @default_label_font_size,
           :min_font_size => min_font_size,
           :align => :left})

        # Get abbraviated text
        options = {:height => @orientation[:height],
          :width => @orientation[:width] * (1 - width_ratio),
          :at => offset,
          :style => font_style,
          :overflow => overflow,
          :size => font_size,
          :min_font_size => min_font_size,
          :align => text_align}
        text = abbreviated_text(display_value, options)
        offset = [@orientation[:x_offset] + (@orientation[:width] * width_ratio), @orientation[:height] - (@orientation[:text_padding] / 2)]

        # Content Textbox
        box = @pdf.text_box(text, {:height => @orientation[:height],
          :width => @orientation[:width] * (1 - width_ratio),
          :at => offset,
          :style => font_style,
          :overflow => overflow,
          :size => font_size,
          :min_font_size => min_font_size,
          :align => text_align})
      else
        offset = [@orientation[:x_offset], @orientation[:height] - (@orientation[:text_padding] / 2)]
        options = {:height => @orientation[:height],
          :width => @orientation[:width],
          :at => offset,
          :style => font_style,
          :overflow => overflow,
          :align => text_align}

        # Need to get abbreviated text with the label and then chop off the label
        abbreviated_text = abbreviated_formatted_text([{ text: label_text(value), styles: [:bold], :size => font_size },
          { text: display_value, :size => font_size }], options)
        texts = [{ text: label_text(value), styles: [:bold], :size => font_size },
          { text: abbreviated_text, :size => font_size }]

        # Label and Content Textbox
        box = @pdf.formatted_text_box(texts, {:height => @orientation[:height],
          :width => @orientation[:width],
          :at => offset,
          :style => font_style,
          :overflow => overflow,
          :align => text_align})
      end
    end
  end
end
