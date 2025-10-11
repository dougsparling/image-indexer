# Image Indexer

This Ruby script provides a command-line tool to caption images in a specified directory using a local Moondream API, and enable searching through these captions. It uses SQLite for database storage and FTS5 for efficient full-text search.

## How to Use

### Indexing Images

To index images in a directory, run the script with the `index` command followed by the path to the directory containing your images.

```bash
bundle exec ruby image_indexer.rb index /path/to/your/images
```

### Searching Captions

To search through the indexed captions, use the `search` command followed by your search query.

```bash
bundle exec ruby image_indexer.rb search "your search query"
```