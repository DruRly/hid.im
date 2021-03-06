require 'png'
require 'png/reader'
require 'paperclip_file'
require 'digest/sha1'

class Hidim < ActiveRecord::Base
  has_attached_file :png
  has_attached_file :torrent, :path => '/tmp/paperclip/:class/:id.torrent'

  attr_accessible :torrent

  validates_attachment_content_type :torrent, :content_type => ['application/x-bittorrent', 'application/x-torrent'],
                                    :message => "The file you uploaded does not appear to be a torrent."
  validates_attachment_presence :torrent, :message => "Please select 'Browse' to select a file before submitting."
  validates_attachment_size :torrent, :less_than => 300.kilobytes, :message => "Please select a file smaller than 250KB."
  validates_presence_of :token
  validates_uniqueness_of :token

  before_validation_on_create :generate_token
  before_create :set_content
  before_create :convert_to_png

  named_scope :featured, :conditions => {:featured => true}
  named_scope :not_featured, :conditions => {:featured => nil}

  named_scope :stale, lambda { { :conditions => ['created_at < ?', 5.minutes.ago] } }

  def self.clear_stale
    Hidim.not_featured.stale.destroy_all
  end

  def generate_token
    self.token = rand(36**8).to_s(36) if self.new_record? and self.token.nil?
  end

  def to_yaml
    self.token
  end

  def name
    self.torrent_file_name
  end

  def hashed
    Digest::SHA1.hexdigest(@content) rescue "deadbeefdeadbeefdeadbeefdeadbeebadcoffee"
  end

  def set_content
    @content = self.torrent.queued_for_write[:original].read
  end

  def convert_to_png
    height = 30
    key = "hidim is torrents!".unpack("C*")
    metadata =  "i#{height}e"
    metadata += "#{self.name.size.to_s}:#{self.name}"
    metadata += "#{self.hashed.size}:#{self.hashed}"
    metadata += "i#{@content.size.to_s}e"

    decimal = key + metadata.unpack("C*") + @content.unpack("C*")

    font_width = 5
    width = decimal.size / 3 / height + 1

    canvas = PNG::Canvas.new(width + font_width + 2, height + 2, PNG::Color::Black)
    pixels = decimal.in_groups_of(3)
    lines = pixels.in_groups_of(height)

    lines.each_with_index do |line, i|
      line.each_with_index do |pixel, j|
        pixel ||= []
        pixel[0] ||= 0
        pixel[1] ||= 0
        pixel[2] ||= 0
        canvas[i + font_width + 1, j + 1] = PNG::Color.new(pixel[0], pixel[1], pixel[2], 255)
      end
    end

    logo_path = File.join(File.dirname(__FILE__), '..', '..', 'public', 'images', 'hidim.png')
    logo = PNG.load_file logo_path
    
    canvas.composite logo, 1, 1
    
    png = PNG.new canvas
    pngfile = PaperClipFile.new
    pngfile.original_filename = "torrent.png"
    tmpfile = Tempfile.new('torrent')
    tmpfile.write(png.to_blob)
    pngfile.to_tempfile = tmpfile

    self.attachment_for(:png).assign(pngfile)
  end
end
