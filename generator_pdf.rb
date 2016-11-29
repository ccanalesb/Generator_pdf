require 'prawn'
require 'barby'
require 'barby/barcode/code_128'
require 'barby/outputter/png_outputter'
require 'barby/outputter/svg_outputter'
require 'stringio'
require 'prawn/measurement_extensions'
require 'prawn-svg'
require 'barby/barcode/qr_code'

module Generator

	def Generator.insert_code_png(pdf, string, x, y)
		barcode = Barby::Code128B.new(string)
		outputter = Barby::PngOutputter.new(barcode)
		outputter.height = 30
		outputter.margin = 0
		blob = outputter.to_svg #Raw PNG data
		data = StringIO.new(blob)
		pdf.image data, :at => [x, y], :width => 70, :height => 30

	end

	def Generator.insert_code_svg(pdf, string, x, y, width, height)
		barcode = Barby::Code128B.new(string)
		outputter = Barby::SvgOutputter.new(barcode)
		outputter.height = height
		outputter.margin = 0
		blob = outputter.to_svg #Raw PNG data
		data = StringIO.new(blob)
		pdf.bounding_box([x,y], :width => width, :height => height) do
			pdf.svg data, :vposition => :bottom, :position => :center
		end
	end

	def Generator.insert_qr_svg(pdf, string, x, y, width, height)
		barcode = Barby::QrCode.new(string, size: 4)
		outputter = Barby::SvgOutputter.new(barcode)
		outputter.height = height
		outputter.margin = 0
		blob = outputter.to_svg #Raw PNG data
		# File.open('barcode.svg', 'wb'){|f| f.write blob }
		data = StringIO.new(blob)
		pdf.bounding_box([x,y], :width => width, :height => height) do
			pdf.svg data, :vposition => :bottom, :position => :center, :bottom_margin => 0.4.cm
			
		end
	end

	def Generator.render(template, data, output_filename)
		validation = {
			font: String,
			size: Array,
			boxes: Array
		}
		box_validation = {
			position: Array,
			size: Array,
			align: String,
			font_size: Integer
		}
		# Do validation on template general shape
		template_shape_validation = template.valid_template?validation
		if template_shape_validation[:valid] then
			#If it is valid, the try to validate each defined box in the template
			template[:boxes].each_with_index{ |box,index|
					box_shape_validation = box.valid_template?box_validation
					if not box_shape_validation[:valid] then
						raise ArgumentError.new("#{box_shape_validation[:reason]} on box number #{index}")
					end
			}
		else
			raise raise ArgumentError.new(template_shape_validation[:reason])
		end
		# Check if the amount of data given fits the template
		if(template[:boxes].count != data.count) then
			raise ArgumentError.new("Data input should have the same lenght as available boxes. "\
			 			"Expecting #{template[:boxes].count} but #{data.count} given")
		end

		# From here template seems to be valid
		pdf = Prawn::Document.new(:page_size => template[:size], :margin => 0)
		pdf.font template[:font]
		template[:boxes].each_with_index do |box,index|
			value = data[index]
			if value.start_with?('text:', 'qr:', 'code128:', 'base64:') then
				if value.start_with?('text:') then
					pdf.text_box(
						value.sub('text:',''),
						:at => box[:position],
						:size => box[:font_size],
						:width => box[:size][0],
						:height=> box[:size][1],
						:overflow => :shrink_to_fit,
						:disable_wrap_by_char => true,
						:align => box[:align].to_sym
					)
				elsif value.start_with?('code128:') then
					insert_code_svg(
						pdf,
						(value.sub('code128:','')),
						box[:position][0],
						box[:position][1],
						box[:size][0],
						box[:size][1]
					)
				elsif value.start_with?('qr:') then
					insert_qr_svg(
						pdf,
						value.sub('qr:',''),
						box[:position][0],
						box[:position][1],
						box[:size][0],
						box[:size][1]
					)	
				end
			else
				pdf.text_box(
					value,
					:at => box[:position],
					:size => box[:font_size],
					:width => box[:size][0],
					:height=> box[:size][1],
					:overflow => :shrink_to_fit,
					:disable_wrap_by_char => true,
					:align => box[:align].to_sym
				)
			end
		end
		pdf.render_file output_filename
	end

	def Generator.render_bounds(template, output_filename)
		validation = {
			font: String,
			size: Array,
			boxes: Array
		}
		box_validation = {
			position: Array,
			size: Array,
			align: String,
			font_size: Integer
		}
		# Do validation on template general shape
		template_shape_validation = template.valid_template?validation
		if template_shape_validation[:valid] then
			#If it is valid, the try to validate each defined box in the template
			template[:boxes].each_with_index{ |box,index|
					box_shape_validation = box.valid_template?box_validation
					if not box_shape_validation[:valid] then
						raise ArgumentError.new("#{box_shape_validation[:reason]} on box number #{index}")
					end
			}
		else
			raise raise ArgumentError.new(template_shape_validation[:reason])
		end

		# From here template seems to be valid
		pdf = Prawn::Document.new(:page_size => template[:size], :margin => 0)
		pdf.font template[:font]
		pdf.stroke_bounds
		template[:boxes].each do |box|
			pdf.bounding_box(box[:position], :width => box[:size][0], :height => box[:size][1]) do
				pdf.stroke_bounds
			end
		end
		pdf.render_file output_filename
	end
	
	
end

if Gem.win_platform?
	require 'win32ole'
	$shell = WIN32OLE.new('Shell.Application')
else
	require 'cups'
end

module Printer
	def Printer.print_label_win(template, data)
		Generator.render(template, data, "output.pdf")
		$shell.ShellExecute('output.pdf', '', '', 'print', 1)
	end

	def Printer.print_label_cups(template,data)
		Generator.render(template, data, "output.pdf")
		printer = Cups.default_printer
		pj = Cups::PrintJob.new("output.pdf", printer)
		pj.print
		# system("lpr", "output.pdf") or raise "lpr failed"
	end

end

module Serializer
  def Serializer.symbolize_recursive(hash)
    {}.tap do |h|
      hash.each { |key, value| h[key.to_sym] = map_value(value) }
    end
  end

  def Serializer.map_value(thing)
    case thing
    when Hash
      symbolize_recursive(thing)
    when Array
      thing.map { |v| map_value(v) }
    else
      thing
    end
  end
end