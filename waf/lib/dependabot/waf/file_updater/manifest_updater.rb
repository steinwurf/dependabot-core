# typed: true
# frozen_string_literal: true

require "json"
require "dependabot/waf/file_updater"

module Dependabot
  module Waf
    class FileUpdater
      class ManifestUpdater
        def initialize(dependencies:, manifest:)
          @dependencies = dependencies
          @manifest = manifest
        end

        def updated_manifest_content
          dependencies
            .select { |dep| requirement_changed?(manifest, dep) }
            .reduce(manifest.content.dup) do |content, dep| # Something is happening in the reduce, dep is pretty much empty. No requiremnts included
              updated_content = content

              updated_content = update_requirements(
                content: updated_content,
                filename: manifest.name,
                dependency: dep
              )

              # updated_content = update_git_pin(
              #  content: updated_content,
              #  filename: manifest.name,
              #  dependency: dependencies
              # )
              raise "Expected content to change!" if content == updated_content

              updated_content
            end
        end

        private

        attr_reader :dependencies
        attr_reader :manifest

        def requirement_changed?(file, dependency)
          changed_requirements = dependency.requirements - dependency.previous_requirements

          changed_requirements.any? { |f| f[:file] == file.name }
        end

        def update_requirements(content:, filename:, dependency:)
          updated_content = content.dup

          reqs = dependency.requirements.zip(dependency.previous_requirements).reject do |new_req, old_req|
            new_req == old_req
          end

          reqs.each do |new_req, old_req|
            raise "Bad req match" unless new_req[:file] == old_req[:file]
            next if new_req[:requirement] == old_req[:requirement]
            next unless new_req[:file] == filename

            updated_content = update_manifest_req(
              content: updated_content,
              dep: dependency,
              old_req: old_req.fetch(:requirement),
              new_req: new_req.fetch(:requirement)
            )
          end

          updated_content
        end

        def update_manifest_req(content:, dep:, old_req:, new_req:)
          # Check if requirements should be updated
          scanned_content = content.match(declaration_regex(dep))

          # Using unamed indexes is a very bad idea.
          puts scanned_content.named_captures

          if scanned_content.named_captures.fetch("resolver") == "git"
            if scanned_content.named_captures.fetch("method") == "semver"
              return update_manifest_req_semver(content, dep, old_req,
                                                new_req)
            end

            update_manifest_req_checkout(content, dep, old_req, new_req)

          elsif scanned_content.named_captures.fetch("resolver") == "http"
            update_manifest_req_http(content, dep, old_req, new_req)
          else
            content
          end
        end

        def declaration_regex(dep)
          # Find method and resolver to check
          /{\s*
(?:
\s*"name":\s*"#{Regexp.escape(dep.name)}",?\s*|
\s*"resolver":\s*"(?<resolver>git|http)",?\s*|
\s*"method":\s*"(?<method>semver|checkout)",?\s*|
\s*(?<major>"major":\s*\d+),?\s*|
\s*"source":\s*"(?<source>[^"]+)",?\s*|
\s*(?<checkout>"checkout":\s*"(?:[0-9a-f]+|\d+(?:\.\d+)*))",?\s*|
\s*"internal":\s*(?<internal>true|false),?\s*|
\s*"optional":\s*(?<optional>true|false),?\s*|
\s*"recurse":\s*(?<recurse>true|false),?\s*|
\s*"pull_submodules":\s*(?<pull_submodules>true|false),?\s*|
\s*"filename":\s*"(?<filename>[^"]+)",?\s*|
\s*"extract":\s*(?<extract>true|false),?\s*|
\s*"sources":\s*\[\s*"(?<sources>[^"]+)"(?:,\s*"[^"]+")*\s*\],?\s*
)*\s*}/mx
        end

        def update_manifest_req_semver(content, dep, old_req, new_req)
          content.gsub(declaration_regex(dep)) do |part|
            line = content.match(declaration_regex(dep)).named_captures.fetch("major")
            new_line = line.gsub(old_req.scan(/\d+/).first, new_req.scan(/\d+/).first)
            new_part = part.gsub(line, new_line)

            # Because it does not replace lines in place :()
            content = content.gsub(part, new_part)
          end

          content
        end

        def update_manifest_req_checkout(content, dep, old_req, new_req)
          content.gsub(declaration_regex(dep)) do |part|
            line = content.match(declaration_regex(dep)).named_captures.fetch("checkout")
            new_line = line.gsub(old_req, new_req)

            new_part = part.gsub(line, new_line)

            content = content.gsub(part, new_part)
          end

          content
        end

        # Have to wait for later. Not strictly necessary.
        def update_manifest_req_http(content:, dep:, old_req:, new_req:)
          raise NotImplementedError
        end

        def update_git_pin(content:, filename:, dependency:)
          raise NotImplementedError
        end
      end
    end
  end
end
