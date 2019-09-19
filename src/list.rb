#!/usr/bin/env ruby
require 'awesome_print'
require 'colorize'
require './utils'

module Enumerable
  def group_by_recursive(level)
    groups = group_by(&:first)
      .collect { |k, vs| [k, vs.collect { |v| v.drop 1 }] }
      .to_h
    if level == 1
      groups.collect { |k, vs| [k, vs.collect(&:first)] }.to_h
    else
      groups.merge(groups) do |group, elements|
        elements.group_by_recursive(level - 1)
      end
    end
  end
end

PACKAGES = Dir['result/**/*.deb'].collect do |package|
    package = package.sub /^result\/(.*)\.deb$/, '\1'
    dist, os_version, package = package.split '/'
    package, version, arch = package.split '_'
    [package, version, dist, os_version, arch]
end.sort

# PACKAGES.group_by_recursive(4).each do |package, versions|
#     puts package.colorize :green
#     versions.each do |version, dists|
#         puts '  ' + version.colorize(:blue)
#         dists.each do |dist, vs|
#             puts '    ' + dist.colorize(:yellow)
#             vs.each do |v, archs|
#                 puts '      ' + v
#                 archs.each do |arch|
#                     puts '        ' + arch.colorize(:red)
#                 end
#             end
#         end
#     end
# end

dists = DISTS.collect do |dist, config|
    versions = config.fetch :versions
    versions.collect { |v| [dist, v] }
end.flatten 1

EXPECTED = {
    'couch-libmozjs185-1.0' => [:any, '1.8.5-1.0.0+couch-1'],
    'couch-libmozjs185-dev' => [:any, '1.8.5-1.0.0+couch-1'],
    'cozy-couchdb' => [:any, '2.3.1-1'],
    'cozy-nsjail' => [:any, '2.9-1'],
    'cozy' => [:all, '1.3.2-1'],
    'cozy-stack' => [:any, '1.3.2-1'],
    'python3-couchdb' => [:all, '1.2-1'],
    'cozy-coclyco' => [:all, '0.4.1-1'],
}.collect do |package, config|
    arch, version = config
    debs = case arch
    when :all
        dists.collect do |config|
            dist, os = *config
            [package, version, dist, os, 'all']
        end
    else
        dists.collect do |config|
            dist, os = *config
            archs = DISTS[dist][:archs]
            archs.collect { |a| [package, version, dist, os, a] }
        end.flatten 1
    end
end.flatten(1).sort

puts "#{PACKAGES.size.to_s.colorize :green} available packages:"
PACKAGES.each { |m| puts "  #{m.join ' '}"}

MISSINGS = EXPECTED - PACKAGES
puts "#{MISSINGS.size.to_s.colorize :red} missing packages:"
MISSINGS.each { |m| puts "  #{m.join ' '}"}

packages = PACKAGES.collect { |p| [p[2], p[3], p[4], p[0], p[1]] }
                  .group_by_recursive 4
# ap packages
