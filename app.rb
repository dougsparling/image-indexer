require 'sinatra'
require_relative 'image_indexer'

set :bind, '0.0.0.0'
set :port, 4567

directory = ARGV[0] || Dir.pwd
indexer = ImageIndexer.new(directory)

get '/' do
  erb :index, locals: { query: nil, results: [], directory: directory }
end

get '/search' do
  query = params[:query]
  results = []
  if query && !query.empty?
    results = indexer.search_images_query(query, 100)
  end
  erb :index, locals: { query: query, results: results, directory: directory }
end

get '/image/:id' do |id|
  image_data = indexer.find_image_by_id(id.to_i)
  if image_data
    path = image_data['path']
    if File.exist?(path) && File.file?(path)
      content_type = get_content_type(path)
      headers 'Cache-Control' => 'no-cache, no-store, must-revalidate'
      headers 'Pragma' => 'no-cache'
      headers 'Expires' => '0'
      send_file path, :type => content_type, :disposition => 'inline'
    else
      status 404
      "Image file not found for ID: #{id}"
    end
  else
    status 404
    "Image data not found for ID: #{id}"
  end
end

get '/fullscreen/:id' do |id|
  image_data = indexer.find_image_by_id(id.to_i)
  if image_data
    erb :fullscreen, locals: { image: image_data }
  else
    status 404
    "Image not found for ID: #{id}"
  end
end

helpers do
  def get_content_type(path)
    case File.extname(path).downcase
    when '.png' then 'image/png'
    when '.jpg', '.jpeg' then 'image/jpeg'
    when '.gif' then 'image/gif'
    when '.bmp' then 'image/bmp'
    when '.webp' then 'image/webp'
    else 'application/octet-stream' # Fallback for unknown types
    end
  end
end

__END__

@@index
<!DOCTYPE html>
<html>
<head>
  <title>Image Indexer Search</title>
  <style>
    body { font-family: sans-serif; display: flex; flex-direction: column; align-items: center; margin-top: 50px; }
    .search-container { margin-bottom: 30px; }
    .search-container input[type="text"] { width: 400px; padding: 10px; font-size: 16px; border: 1px solid #ccc; border-radius: 5px; }
    .search-container button { padding: 10px 20px; font-size: 16px; background-color: #007bff; color: white; border: none; border-radius: 5px; cursor: pointer; }
    .search-container button:hover { background-color: #0056b3; }
    .results-container { width: 90%; max-width: 1200px; }
    .image-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
    .image-item { border: 1px solid #eee; padding: 10px; text-align: center; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    .image-item img { max-width: 100%; height: auto; display: block; margin: 0 auto 10px auto; }
    .image-item p { font-size: 14px; color: #555; }
  </style>
</head>
<body>
  <div class="search-container">
    <form action="/search" method="get">
      <input type="text" name="query" placeholder="search image captions" value="<%= query %>" autofocus>
      <button type="submit">Search</button>
    </form>
  </div>

  <% if results.any? %>
    <h2>Results for "<%= query %>" in <%= directory %></h2>
    <div class="results-container">
      <div class="image-grid">
        <% results.each do |item| %>
          <div class="image-item">
            <a href="/fullscreen/<%= item['id'] %>">
              <img src="/image/<%= item['id'] %>">
            </a>
            <p><%= item['caption'] %></p>
          </div>
        <% end %>
      </div>
    </div>
  <% elsif query && !query.empty? %>
    <p>No results found for "<%= query %>".</p>
  <% end %>
</body>
</html>

@@fullscreen
<!DOCTYPE html>
<html>
<head>
  <title><%= image['caption'] %></title>
  <style>
    body {
      font-family: sans-serif;
      margin: 0;
      background-color: #fff;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      height: 100vh;
      overflow: hidden;
    }
    .header {
      width: 100%;
      background-color: rgba(255, 255, 255, 0.7);
      padding: 10px 20px;
      display: flex;
      align-items: center;
      position: fixed;
      top: 0;
      left: 0;
      z-index: 10;
    }
    .back-arrow {
      color: black; 
      font-size: 36px;
      text-decoration: none;
      margin-right: 20px;
    }
    .caption {
      color: black;
      font-size: 18px;
      flex-grow: 1;
      text-align: center;
      white-space: normal; 
      word-wrap: break-word;
      max-width: calc(100% - 80px);
    }
    .fullscreen-image-container {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 100%;
      height: 100%;
    }
    .fullscreen-image {
      max-width: 90%;
      max-height: 90%;
      object-fit: contain;
    }
  </style>
</head>
<body>
  <div class="header">
    <a href="javascript:history.back()" class="back-arrow">&#8592;</a>
    <span class="caption"><%= image['caption'] %></span>
  </div>
  <div class="fullscreen-image-container">
    <img src="/image/<%= image['id'] %>" class="fullscreen-image">
  </div>
</body>
</html>
