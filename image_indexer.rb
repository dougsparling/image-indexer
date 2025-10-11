require 'optparse'
require 'sqlite3'
require 'base64'
require 'json'
require 'net/http'
require 'fileutils'

class ImageIndexer
  DB_NAME = '.image-indexer.db'
  MOONDREAM_API_URL = URI('http://localhost:2020/v1/caption')

  def initialize(directory = Dir.pwd)
    @directory = File.expand_path(directory)
    @db = nil
  end

  def run(mode, query = nil)
    case mode
    when :index
      index_images
    when :search
      search_images(query)
    else
      puts "Invalid mode. Use 'index' or 'search'."
      exit 1
    end
  end

  def search_images_query(query, results = nil)
    open_db unless @db # Ensure db is open if not already
    limit = if(results.nil?) then "" else "LIMIT #{results}" end
    @db.execute("SELECT T1.id, T1.path, T1.caption FROM images AS T1 JOIN image_captions AS T2 ON T1.id = T2.rowid WHERE T2.caption MATCH ? ORDER BY rank #{limit}", query)
  end

  def find_image_by_id(id)
    open_db unless @db
    result = @db.execute("SELECT id, path, caption FROM images WHERE id = ?", id).first
    result
  end

  private

  def open_db
    db_path = File.join(@directory, DB_NAME)
    @db = SQLite3::Database.new(db_path)
    @db.results_as_hash = true
    @db.execute("PRAGMA foreign_keys = ON;")
  end

  def create_schema
    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        caption TEXT
      );
    SQL
    # Create FTS5 table for captions
    @db.execute <<-SQL
      CREATE VIRTUAL TABLE IF NOT EXISTS image_captions USING fts5(caption, content='images', content_rowid='id');
    SQL
    # Create triggers to keep FTS table in sync
    @db.execute <<-SQL
      CREATE TRIGGER IF NOT EXISTS images_ai AFTER INSERT ON images BEGIN
        INSERT INTO image_captions(rowid, caption) VALUES (new.id, new.caption);
      END;
    SQL
    @db.execute <<-SQL
      CREATE TRIGGER IF NOT EXISTS images_ad AFTER DELETE ON images BEGIN
        INSERT INTO image_captions(image_captions, rowid, caption) VALUES('delete', old.id, old.caption);
      END;
    SQL
    @db.execute <<-SQL
      CREATE TRIGGER IF NOT EXISTS images_au AFTER UPDATE ON images BEGIN
        INSERT INTO image_captions(image_captions, rowid, caption) VALUES('delete', old.id, old.caption);
        INSERT INTO image_captions(rowid, caption) VALUES (new.id, new.caption);
      END;
    SQL
  end

  def find_images
    image_paths = []
    Dir.glob(File.join(@directory, '**', '*.{jpg,jpeg,png,gif,bmp,tiff,webp}'), File::FNM_CASEFOLD).each do |path|
      image_paths << File.absolute_path(path)
    end
    image_paths
  end

  def get_caption_from_api(path)
    image_data = File.binread(path)
    base64_image = Base64.strict_encode64(image_data)

    http = Net::HTTP.new(MOONDREAM_API_URL.host, MOONDREAM_API_URL.port)
    request = Net::HTTP::Post.new(MOONDREAM_API_URL)
    request['Content-Type'] = 'application/json'
    request.body = {
      # Sending the whole image is idiotic since the API runs on the same machine, but I couldn't find a way to just send a file:// path here
      "image_url": "data:image/jpeg;base64,#{base64_image}",
      "stream": false,
      "length": "long"
    }.to_json

    response = http.request(request)
    if response.is_a?(Net::HTTPSuccess)
      json_response = JSON.parse(response.body)
      json_response['caption']
    else
      puts "Error getting caption for #{path}: #{response.code} - #{response.message}"
      nil
    end
  rescue StandardError => e
    puts "Exception getting caption for #{path}: #{e.message}"
    nil
  end

  def index_images
    open_db
    create_schema

    indexed_paths = @db.execute("SELECT path FROM images").map { |row| row['path'] }
    all_paths = find_images
    
    to_process = all_paths.reject { |path| indexed_paths.include?(path) }
    total_new = to_process.length
    
    processed_count = 0
    total_time_spent = 0.0

    puts "Found #{all_paths.length} images in total."
    puts "Starting indexing of #{total_new} new images..."

    all_paths.each do |path|
      if indexed_paths.include?(path)
        puts "Skipping #{path}, already indexed."
      else
        processed_count += 1
        
        start_time = Time.now
        puts "Processing image #{processed_count}/#{total_new}: #{path}..."
        caption = get_caption_from_api(path)
        end_time = Time.now
        
        api_call_time = end_time - start_time
        total_time_spent += api_call_time

        if caption
          @db.execute("INSERT INTO images (path, caption) VALUES (?, ?)", [path, caption])
          puts "  Caption saved: #{caption}"
        else
          puts "  Failed to get caption for #{path}"
        end

        if processed_count > 0 # Avoid division by zero
          avg_time_per_image = total_time_spent / processed_count
          remaining_images = total_new - processed_count
          estimated_remaining_time = avg_time_per_image * remaining_images
          estimated_remaining_minutes = estimated_remaining_time / 60.0

          puts "  API call took: #{'%.2f' % api_call_time} seconds."
          puts "  Estimated remaining time: #{'%.2f' % estimated_remaining_minutes} minutes."
        end
        puts "---"
      end
    end

    puts "Indexing complete. Total new images processed: #{processed_count}."
  ensure
    @db.close if @db
  end

  def search_images(query)
    unless query && !query.empty?
      puts "Search query cannot be empty."
      exit 1
    end

    unless File.exist?(File.join(@directory, DB_NAME))
      puts "Database not found. Please run in 'index' mode first."
      exit 1
    end

    open_db

    puts "Searching for '#{query}'..."
    results = search_images_query(query, 5)

    if results.empty?
      puts "No results found for '#{query}'."
    else
      puts "Top 5 search results:"
      results.each_with_index do |row, i|
        puts "#{i + 1}. Path: #{row['path']}"
        puts "   Caption: #{row['caption']}"
        puts "---"
      end
    end
  ensure
    @db.close if @db
  end
end

# TODO: maybe extract into a separate file...
if __FILE__ == $0
  options = { directory: Dir.pwd } # Default to current directory
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby image_indexer.rb [options]"

    opts.on("-d DIRECTORY", "--directory DIRECTORY", "Specify the directory to index and store the database (defaults to current directory)") do |dir|
      options[:directory] = dir
    end

    opts.on("-i", "--index", "Run in indexing mode") do
      options[:mode] = :index
    end

    opts.on("-s QUERY", "--search QUERY", "Run in search mode with a query") do |query|
      options[:mode] = :search
      options[:query] = query
    end

    opts.on("-h", "--help", "Prints this help") do
      puts opts
      exit
    end
  end.parse!

  unless options[:mode]
    puts "Please specify a mode: --index or --search 'QUERY'"
    exit 1
  end

  indexer = ImageIndexer.new(options[:directory])
  indexer.run(options[:mode], options[:query])
end
