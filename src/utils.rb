require 'open3'
require 'time'
require 'fileutils'
require 'etc'
require 'tmpdir'
begin
	require 'debian/apt_pkg'
rescue LoadError
	$stderr.puts 'Unable to load debian/apt_pkg, skipping…'
end
require 'awesome_print'
require './config'

def args_list(arg, default)
	case arg
	when String
		arg.split /\s+/
	when nil
		default
	end
end

def result(*cmd, chdir: nil, sudo: false)
	first = cmd.first
	cmd = cmd.first if first.is_a? Array

	options = {}
	options[:chdir] = chdir if chdir
	cmd = %w[sudo] + cmd if sudo

	log = cmd.join ' '
	log = "(in #{chdir}) #{log}" if chdir
	$stderr.puts log
	o, e, s = Open3.capture3 *cmd, **options

	unless s.success?
		$stderr.puts e
		raise "Error during command #{cmd}"
	end
	o.chomp
end

def cmd(*cmd, chdir: nil, env: nil, sudo: false)
	first = cmd.first
	cmd = cmd.first if first.is_a? Array
	cmd = %i[sudo] + cmd if sudo
	cmd.collect! &:to_s
	orig_cmd = cmd

	$stderr.puts cmd.join ' '

	if env
		env = env.collect { |k, v| [k.to_s, v.to_s] }.to_h
		cmd = [env] + cmd
	end

	m =  chdir ? Dir.method(:chdir) : -> (dir, &block) { block.call }
	m.call(chdir) do
		result = system *cmd
		raise "Error during command #{orig_cmd} #{env}" unless result == true
	end
end

def build_dsc(directory, version: nil)
	source = result %w[dpkg-parsechangelog -S Source], chdir: directory
	version = result %w[dpkg-parsechangelog -S Version], chdir: directory unless version
	if RELEASE == 'unstable'
		version = version.sub /~.*$/, ''
		date = Time.now.utc.strftime '%Y%m%d0000'
		version = "#{version}~#{date}"
		cmd 'dch', '-bv', version, 'Nightly build', chdir: directory
	end
	cmd %w[dpkg-buildpackage -us -uc -S -d], chdir: directory
	[source, version]
end

def cowbuilder_init(dist, version, arch)
	env = { DIST: dist, VERSION: version, ARCH: arch }
	name = "#{dist}-#{version}-#{arch}"
	dir = File.join '/var/cache/pbuilder', name
	return if Dir.exists? dir
	FileUtils.mkdir_p File.join dir, 'aptcache'
	cmd 'cowbuilder', 'create', env: env
end

def cowbuilder_clean(dist, version, arch)
	name = "#{dist}-#{version}-#{arch}"
	FileUtils.rm_rf File.join '/var/cache/pbuilder', name
end

def cowbuilder(src, os, result: nil, sudo: false, home: false, network: false)
	os_dist, os_version, os_arch = os.values_at :dist, :version, :arch
	result = File.join Dir.pwd, 'result', os_dist, os_version unless result

	src_package, src_version = src.values_at :package, :version

	env = { BUILDRESULT: result, DIST: os_dist, VERSION: os_version, ARCH: os_arch }
	env[:USE_HOME] = 'yes' if home
	c = ['cowbuilder', 'build', "#{src_package}_#{src_version}.dsc"]
	c += %w[--use-network yes] if network
	cmd c, env: env, sudo: sudo
end

def build_deb(dsc, os)
	match = /^(.*)_([^_]+).dsc$/.match dsc
	raise "Invalid dsc #{dsc}" unless match
	package, version = match[1], match[2]
	cowbuilder({ package: package, version: version }, os)
end

def build(directory)
	package = build_dsc directory
	cowbuilder *package
end

def last_version(files)
	files = files.collect do |file|
		version = File.basename(file, '.*')
				.split('_')[1]
		[file, version]
	end.sort do |a, b|
		a = a.last
		b = b.last
		Debian::AptPkg.cmp_version a, b
	end.last.first
end

def remove_old_versions(versions)
	versions.each do |package, versions|
		versions = versions.sort do |a, b|
			a = a.last[1]
			b = b.last[1]
			Debian::AptPkg.cmp_version a, b
		end
		*to_remove, _ = versions
		to_remove = to_remove.collect &:first
		to_remove.each { |p| yield p }
	end
end

def aptly_keep_last_version(repo)
	packages = result ['aptly', 'repo', 'show', '-with-packages', repo]
	packages = packages.each_line
					.collect { |l| /^\s+(.*)/.match(l)&.[](1) }
					.compact
					.collect { |l| [l, l.split('_')] }
					.group_by { |l| l = l.last; [l.first, l.last] }
	remove_old_versions(packages) { |p| cmd ['aptly', 'repo', 'remove', repo, p] }
end

def update_repo(dist, version, result, release: :testing)
	result = File.join 'result', dist, result
	return unless Dir.exists? result

	repo = "#{dist}-#{version}-#{release}"
	c = %w[aptly repo add]
	c += ['-force-replace'] if ENV['FORCE_REPLACE']
	c += [repo, result]
	cmd c
	aptly_keep_last_version repo
end

def update_publish(dist, version, result=nil)
	result ||= version
	update_repo dist, version, result

	c = %w[aptly publish update]
	c += ["-gpg-key=#{GPG_KEY}"]
	c += ['-force-overwrite'] if ENV['FORCE_OVERWRITE']
	c += [version, dist]
	cmd c
end

def aptly(dist)
	version = DISTS[dist]
	repos = %w[stable testing].collect do |env|
		repo = "#{dist}-#{version}-#{env}"
		cmd ['aptly', 'repo', 'create', "-component=#{env}", "-distribution=#{version}", repo]
		repo
	end
	cmd ['aptly', 'publish', 'repo',
		"-gpg-key=#{GPG_KEY}", "-component=#{',' * (repos.size - 1)}",
		"-distribution=#{version}", "-architectures=#{ARCHS.join ','}"] + repos + [dist]
end

def aptly_drop_publishes
	publishes = result 'aptly', 'publish', 'list', '-raw'
	publishes.each_line do |publish|
		dist, version = publish.split /\s+/
		cmd 'aptly', 'publish', 'drop', version, dist
	end
end

def aptly_drop_repos
	repos = result 'aptly', 'repo', 'list', '-raw'
	repos.each_line { |r| cmd 'aptly', 'repo', 'drop', r.chomp }
end

def aptly_drop
	aptly_drop_publishes
	aptly_drop_repos
end

def do_in_tmp_dir(args=nil)
	Dir.mktmpdir(args, Dir.pwd) { |dir| Dir.chdir(dir) { yield dir } }
end

def directory_keep_last_version(repo)
		exts = %w[deb ddeb buildinfo changes].product(ARCHS + %w[all])
										.collect { |e, a| "_#{a}.#{e}"}

		exts = (%w[.debian.tar.xz .debian.tar.bz2 .orig.tar.xz .orig.tar.gz .dsc] + exts)
								.collect { |e| Regexp.escape e }
								.join '|'
		exts = Regexp.compile /(#{exts})$/

		def extract(file, exts)
				match = exts.match file
				raise "Unknown extension for #{file}" unless match
				ext = Regexp.escape match[1]
				match = /^([^_]+)_(.+)(#{ext})$/.match file
				match[1..-1]
		end

		packages = Dir[File.join repo, '*']
		packages = packages.collect { |p| File.basename p }
							.collect { |l| [l, extract(l, exts)] }
							.group_by { |l| l = l.last; [l.first, l.last] }
		remove_old_versions(packages) do |p|
				file = File.join repo, p
				puts "Removing #{file}"
				File.unlink file
		end
end
