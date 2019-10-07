VERSIONS = {
	'couchdb-js': { src: '1.8.5', debian: '1.8.5-1' },
	couchdb: { src: '2.3.1', debian: '2.3.1-1' },
	cozy: { src: '1.3.2', debian: '1.3.2-1' },
	'python3-couchdb': { src: '1.2', debian: '1.2-1'},
	coclyco: { src: '0.4.1', debian: '0.4.1-1'},
}

DISTS = {
	'debian' => {
		archs: %w[amd64 armhf arm64],
		versions: %w[buster stretch]
	},
	'ubuntu' => {
		archs: %w[amd64],
		versions: %w[disco bionic]
	},
	'raspbian' => {
	 	archs: %w[armhf],
		versions: %w[buster stretch]
	}
}

ENVS = %w[stable testing]
ARCHS = %w[amd64 armhf arm64 source]

RELEASE = ENV.fetch 'RELEASE', 'testing'
GPG_KEY = '0x51F72B6A45D40BBE'
