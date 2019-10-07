#!/bin/bash -xe
cat > /etc/apt/apt.conf.d/00-proxy <<-EOF
	Acquire::http { Proxy "http://apt-cacher-ng:3142" };
EOF

cat > /etc/apt/apt.conf.d/60-recommends <<-EOF
	APT::Install-Recommends "0";
	APT::Install-Suggests "0";
EOF

apt update -qq
apt install -qq -y wget ca-certificates lsb-release

wget https://apt.cozy.io/cozy-keyring.deb
dpkg -i cozy-keyring.deb

DIST="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
VERSION="$(lsb_release -sc)"
: ${RELEASE:=testing}

cat > /etc/apt/sources.list.d/cozy.list <<-EOF
	deb http://aptly/$DIST/ $VERSION $RELEASE
	deb-src http://aptly/$DIST/ $VERSION $RELEASE
EOF

debconf-set-selections <<EOF
	cozy-couchdb couchdb/mode select standalone
	cozy-couchdb couchdb/bindaddress string 127.0.0.1
	cozy-couchdb couchdb/nodename string couchdb@127.0.0.1
	cozy-couchdb couchdb/adminpass password admin
	cozy-couchdb couchdb/adminpass_again password admin

	cozy-stack cozy-stack/couchdb/nodename string couchdb@127.0.0.1
	cozy-stack cozy-stack/couchdb/address string 127.0.0.1:5984

	cozy-stack cozy-stack/couchdb/admin/user string admin
	cozy-stack cozy-stack/couchdb/admin/password password admin
	cozy-stack cozy-stack/couchdb/admin/password_again password admin

	cozy-stack cozy-stack/couchdb/cozy/user string cozy
	cozy-stack cozy-stack/couchdb/cozy/password password cozy
	cozy-stack cozy-stack/couchdb/cozy/password_again password cozy

	cozy-stack cozy-stack/cozy/password password admin
	cozy-stack cozy-stack/cozy/password_again password admin

	cozy-stack cozy-stack/address string 127.0.0.1
	cozy-stack cozy-stack/port string 8080
	cozy-stack cozy-stack/admin/address string 127.0.0.1
	cozy-stack cozy-stack/admin/port string 6060
EOF

apt update -qq
apt install -qq -y cozy

export COZY_ADMIN_PASSWORD=admin
cozy-stack instances add --passphrase aeris --apps settings,drive,photos,collect test.cozy.run
