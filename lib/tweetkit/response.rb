# frozen_string_literal: true

require 'json'

module Tweetkit
  module Response
    class Tweets
      include Enumerable

      attr_accessor :annotations, :connection, :context_annotations, :entity_annotations, :expansions, :fields, :meta, :options, :original_response, :response, :tweets, :twitter_request

      def initialize(response, **options)
        parse! response, **options
      end

      def parse!(response, **options)
        parse_response response
        extract_and_save_tweets
        return unless @tweets

        extract_and_save_meta
        extract_and_save_expansions
        extract_and_save_options(**options)
        extract_and_save_request
      end

      def parse_response(response)
        @original_response = response
        @response = response.body
      end

      def extract_and_save_tweets
        if (data = @response['data'])
          if data.is_a?(Array)
            @tweets = @response['data'].collect { |tweet| Tweet.new(tweet) }
          else
            @tweets = [Tweet.new(@response['data'])]
          end
        else
          @tweets = []
        end
      end

      def extract_and_save_meta
        @meta = Meta.new(@response['meta'])
      end

      def extract_and_save_expansions
        @expansions = Expansions.new(@response['includes'])
      end

      def extract_and_save_options(**options)
        @options = options
      end

      def extract_and_save_request
        @connection = @options[:connection]
        @twitter_request = @options[:twitter_request]
      end

      def each(&block)
        tweets.each(&block)
      end

      def last
        tweets.last
      end

      def tweet
        tweets.first
      end

      def next_page
        connection.params.merge!({ next_token: meta.next_token })
        response = connection.get(twitter_request[:previous_url])
        parse! response,
               connection: connection,
               twitter_request: {
                 previous_url: twitter_request[:previous_url],
                 previous_query: twitter_request[:previous_query]
               }
        self
      end

      def prev_page
        connection.params.merge!({ previous: meta.previous_token })
        response = connection.get(twitter_request[:previous_url])
        parse! response,
               connection: connection,
               twitter_request: {
                 previous_url: twitter_request[:previous_url],
                 previous_query: twitter_request[:previous_query]
               }
        self
      end

      class HashBackedOpenStruct < OpenStruct
        def to_h
          table.dup
        end

        alias_method :data, :to_h
      end

      class Tweet < HashBackedOpenStruct
        attr_accessor :annotations, :attachments, :geo

        def initialize(tweet)
          super
          @annotations = Annotations.new(tweet['context_annotations'], tweet['entities'])
          @attachments = Attachments.new(tweet['attachments'])
          @geo = Geo.new(tweet['geo'])
        end

        def reply_to
          in_reply_to_user_id
        end

        def nsfw
          possibly_sensitive
        end

        def sensitive
          possibly_sensitive
        end

        def permission
          reply_settings
        end

        def device
          source
        end

        def withheld?
          withheld && !withheld.empty?
        end

        def context_annotations
          @annotations.context_annotations
        end

        def entity_annotations
          entities
        end

        def entities
          @annotations.entity_annotations
        end

        class Attachments
          attr_accessor :media_keys, :poll_ids

          def initialize(attachments)
            return unless attachments

            @media_keys = attachments['media_keys']
            @poll_ids = attachments['poll_ids']
          end
        end

        class Annotations
          attr_accessor :context_annotations, :entity_annotations

          def initialize(context_annotations, entity_annotations)
            @context_annotations = Context.new(context_annotations) if context_annotations
            @entity_annotations = Entity.new(entity_annotations) if entity_annotations
          end

          class Context
            include Enumerable

            attr_accessor :annotations

            def initialize(annotations)
              return unless annotations

              @annotations = annotations.collect { |annotation| Annotation.new(annotation) }
            end

            def each(&block)
              annotations.each(&block)
            end

            class Annotation
              attr_accessor :domain, :entity

              def initialize(annotation)
                @domain = annotation['domain']
                @entity = annotation['entity']
              end
            end
          end

          class Entity
            include Enumerable

            attr_accessor :annotations, :cashtags, :hashtags, :mentions, :urls

            def initialize(entity_annotations)
              return unless entity_annotations

              @annotations = entity_annotations['annotations']&.collect { |annotation| Annotation.new(annotation) }
              @cashtags = entity_annotations['cashtags']&.collect { |cashtag| Cashtag.new(cashtag) }
              @hashtags = entity_annotations['hashtags']&.collect { |hashtag| Hashtag.new(hashtag) }
              @mentions = entity_annotations['mentions']&.collect { |mention| Mention.new(mention) }
              @urls = entity_annotations['urls']&.collect { |url| Url.new(url) }
            end

            def each(&block)
              annotations.each(&block)
            end

            class Annotation < HashBackedOpenStruct
              def text
                normalized_text
              end
            end

            class Cashtag < HashBackedOpenStruct; end

            class Hashtag < HashBackedOpenStruct; end

            class Mention < HashBackedOpenStruct; end

            class Url < HashBackedOpenStruct; end
          end
        end

        class Geo < HashBackedOpenStruct; end

        class PublicMetrics < HashBackedOpenStruct; end
      end

      class Expansions
        attr_accessor :media, :places, :polls, :tweets, :users

        def initialize(expansions)
          return unless expansions

          @media = expansions['media']&.collect { |media_object| MediaObject.new(media_object) }
          @places = expansions['places']&.collect { |place| Place.new(place) }
          @polls = expansions['polls']&.collect { |poll| Poll.new(poll) }
          @tweets = expansions['tweets']&.collect { |tweet| Tweet.new(tweet) }
          @users = expansions['users']&.collect { |user| User.new(user) }
        end

        class MediaObject < HashBackedOpenStruct; end

        class Place < HashBackedOpenStruct
          attr_accessor :geo

          def initialize(place)
            super
            @geo = GeoJSON.new(place['geo'])
          end

          class GeoJSON < HashBackedOpenStruct; end
        end

        class Poll < HashBackedOpenStruct
          attr_accessor :options

          def initialize(poll)
            super
            @options = poll['options'].collect { |option| Option.new(option) }
          end

          class Option < HashBackedOpenStruct; end
        end

        class User < HashBackedOpenStruct; end
      end

      class Meta < HashBackedOpenStruct; end
    end
  end
end
