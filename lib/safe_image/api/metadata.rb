# frozen_string_literal: true

module SafeImage
  module API
    # Public read-only metadata operations. Methods stay exposed on SafeImage via
    # `extend`; inline behavior lives in operation classes.
    module Metadata
      def probe(path, max_pixels: nil)
        metadata_operations.probe(path, max_pixels: max_pixels)
      end

      def type(path, max_pixels: nil)
        metadata_operations.type(path, max_pixels: max_pixels)
      end

      def size(path, max_pixels: nil)
        metadata_operations.size(path, max_pixels: max_pixels)
      end

      def dimensions(path, max_pixels: nil)
        metadata_operations.dimensions(path, max_pixels: max_pixels)
      end

      def info(path, max_pixels: nil, animated: false, orientation: false)
        metadata_operations.info(path, max_pixels: max_pixels, animated: animated, orientation: orientation)
      end

      def orientation(path, max_pixels: nil)
        metadata_operations.orientation(path, max_pixels: max_pixels)
      end

      def dominant_color(path, max_pixels: nil)
        metadata_operations.dominant_color(path, max_pixels: max_pixels)
      end

      def remote_info(url, **kwargs)
        config
        Remote.info(url, **kwargs)
      end

      def remote_size(url, **kwargs)
        config
        Remote.size(url, **kwargs)
      end

      def remote_dimensions(url, **kwargs)
        remote_size(url, **kwargs)
      end

      def remote_type(url, **kwargs)
        config
        Remote.type(url, **kwargs)
      end

      def remote_animated?(url, **kwargs)
        config
        Remote.animated?(url, **kwargs)
      end

      def remote_dominant_color(url, **kwargs)
        config
        Remote.dominant_color(url, **kwargs)
      end

      def fetch_remote(url, **kwargs, &block)
        config
        Remote.fetch(url, **kwargs, &block)
      end

      def frame_count(path, max_pixels: nil)
        metadata_operations.frame_count(path, max_pixels: max_pixels)
      end

      def animated?(path, max_pixels: nil)
        metadata_operations.animated?(path, max_pixels: max_pixels)
      end

      private

      def metadata_operations
        MetadataOperations.new(config: SafeImage.config)
      end
    end
  end
end
